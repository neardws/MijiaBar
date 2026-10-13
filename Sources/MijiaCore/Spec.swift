import Foundation

public struct ValueOption: Codable, Hashable, Sendable { public let value: Int; public let description: String
    public init(value: Int, description: String) { self.value = value; self.description = description } }

public func urnName(_ t: String) -> String { let p = t.split(separator: ":"); return p.count > 3 ? String(p[3]) : t }

public struct SpecProperty: Codable, Hashable, Sendable {
    public let siid: Int, iid: Int
    public let type: String, description: String, format: String
    public let access: [String]
    public let unit: String?
    public let range: [Double]?
    public let options: [ValueOption]?
    public var name: String { urnName(type) }
    public var key: String { "\(siid).\(iid)" }
    public var readable: Bool { access.contains("read") }
    public var writable: Bool { access.contains("write") }
    public var isNumber: Bool { format != "bool" && format != "string" }
    public init(siid: Int, iid: Int, type: String, description: String, format: String, access: [String], unit: String?, range: [Double]?, options: [ValueOption]?) {
        self.siid = siid; self.iid = iid; self.type = type; self.description = description; self.format = format
        self.access = access; self.unit = unit; self.range = range; self.options = options
    }
}
public struct SpecAction: Codable, Hashable, Sendable {
    public let siid: Int, iid: Int
    public let type: String, description: String
    public let inputs: [Int]
    public var name: String { urnName(type) }
    public var key: String { "\(siid).\(iid)" }
}
public struct SpecService: Codable, Hashable, Sendable {
    public let iid: Int
    public let type: String, description: String
    public let properties: [SpecProperty]
    public let actions: [SpecAction]
    public var name: String { urnName(type) }
    public func prop(_ name: String) -> SpecProperty? { properties.first { $0.name == name } }
    public init(iid: Int, type: String, description: String, properties: [SpecProperty], actions: [SpecAction]) {
        self.iid = iid; self.type = type; self.description = description; self.properties = properties; self.actions = actions
    }
}
public struct DeviceSpec: Codable, Hashable, Sendable {
    public let type: String, description: String
    public let services: [SpecService]
    public var name: String { urnName(type) }
    public init(type: String, description: String, services: [SpecService]) { self.type = type; self.description = description; self.services = services }
    public var controlServices: [SpecService] { services.filter { $0.iid != 1 } }
    public func prop(named n: String) -> SpecProperty? { controlServices.lazy.compactMap { $0.prop(n) }.first }
    public func prop(key: String) -> SpecProperty? { services.flatMap(\.properties).first { $0.key == key } }
    public func action(key: String) -> SpecAction? { services.flatMap(\.actions).first { $0.key == key } }
    public func action(named n: String) -> SpecAction? { services.flatMap(\.actions).first { $0.name == n } }
    /// 主开关：第一个可写的 on 属性
    public var mainOnProperty: SpecProperty? { controlServices.lazy.compactMap { $0.prop("on") }.first { $0.writable && $0.format == "bool" } }

    public static func parse(_ obj: [String: Any]) -> DeviceSpec {
        let services = (obj["services"] as? [[String: Any]] ?? []).map { s -> SpecService in
            let siid = s["iid"] as? Int ?? 0
            let props = (s["properties"] as? [[String: Any]] ?? []).map { p in
                SpecProperty(siid: siid, iid: p["iid"] as? Int ?? 0, type: p["type"] as? String ?? "",
                             description: p["description"] as? String ?? "", format: p["format"] as? String ?? "",
                             access: p["access"] as? [String] ?? [], unit: p["unit"] as? String,
                             range: (p["value-range"] as? [NSNumber])?.map(\.doubleValue),
                             options: (p["value-list"] as? [[String: Any]])?.map {
                                ValueOption(value: ($0["value"] as? NSNumber)?.intValue ?? 0, description: $0["description"] as? String ?? "") })
            }
            let acts = (s["actions"] as? [[String: Any]] ?? []).map { a in
                SpecAction(siid: siid, iid: a["iid"] as? Int ?? 0, type: a["type"] as? String ?? "",
                           description: a["description"] as? String ?? "", inputs: a["in"] as? [Int] ?? [])
            }
            return SpecService(iid: siid, type: s["type"] as? String ?? "", description: s["description"] as? String ?? "", properties: props, actions: acts)
        }
        return DeviceSpec(type: obj["type"] as? String ?? "", description: obj["description"] as? String ?? "", services: services)
    }
}

/// 从 miot-spec.org 拉取并缓存设备规格（可变状态都由 lock 保护）
public final class SpecStore: @unchecked Sendable {
    public static let shared = SpecStore()
    private var mem: [String: DeviceSpec] = [:]
    private var indexTask: Task<[String: String], Error>?
    private let lock = NSLock()

    public func spec(for model: String) async throws -> DeviceSpec? {
        if let s = lock.withLock({ mem[model] }) { return s }
        let file = Paths.specs.appendingPathComponent(model + ".json")
        if let d = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(DeviceSpec.self, from: d) {
            lock.withLock { mem[model] = s }; return s
        }
        guard let urn = try await index()[model] else { return nil }
        var c = URLComponents(string: "https://miot-spec.org/miot-spec-v2/instance")!
        c.queryItems = [URLQueryItem(name: "type", value: urn)]
        let (d, _) = try await URLSession.shared.data(from: c.url!)
        guard let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        let s = DeviceSpec.parse(obj)
        try? JSONEncoder().encode(s).write(to: file)
        lock.withLock { mem[model] = s }
        return s
    }

    private func index() async throws -> [String: String] {
        let task: Task<[String: String], Error> = lock.withLock {
            if let t = indexTask { return t }
            let t = Task { try await Self.loadIndex() }
            indexTask = t; return t
        }
        do { return try await task.value } catch { lock.withLock { indexTask = nil }; throw error }
    }

    private static func loadIndex() async throws -> [String: String] {
        let file = Paths.support.appendingPathComponent("spec-index.json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path), let m = attrs[.modificationDate] as? Date,
           Date().timeIntervalSince(m) < 7 * 86400, let d = try? Data(contentsOf: file),
           let idx = try? JSONDecoder().decode([String: String].self, from: d) { return idx }
        let (d, _) = try await URLSession.shared.data(from: URL(string: "https://miot-spec.org/miot-spec-v2/instances?status=all")!)
        let obj = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
        var best: [String: (String, Int, Bool)] = [:]
        for i in obj["instances"] as? [[String: Any]] ?? [] {
            guard let m = i["model"] as? String, let t = i["type"] as? String else { continue }
            let v = i["version"] as? Int ?? 0, rel = (i["status"] as? String) == "released"
            if let b = best[m], (b.2 && !rel) || (b.2 == rel && b.1 >= v) { continue }
            best[m] = (t, v, rel)
        }
        let idx = best.mapValues { $0.0 }
        try? JSONEncoder().encode(idx).write(to: file)
        return idx
    }
}
