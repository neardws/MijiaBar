import Foundation
import Network

public enum PropValue: Codable, Hashable, Sendable, CustomStringConvertible {
    case bool(Bool), int(Int), double(Double), string(String), null

    public init(_ a: Any?) {
        guard let a, !(a is NSNull) else { self = .null; return }
        if let n = a as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) }
            else if CFNumberIsFloatType(n) { self = .double(n.doubleValue) }
            else { self = .int(n.intValue) }
        } else if let s = a as? String { self = .string(s) }
        else { self = .string("\(a)") }
    }
    /// 解析命令行/JSON 字面量
    public static func parse(_ s: String) -> PropValue {
        let t = s.trimmingCharacters(in: .whitespaces)
        switch t.lowercased() { case "true": return .bool(true); case "false": return .bool(false); default: break }
        if let i = Int(t) { return .int(i) }
        if let d = Double(t) { return .double(d) }
        if t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") { return .string(String(t.dropFirst().dropLast())) }
        return .string(t)
    }
    public var any: Any {
        switch self { case .bool(let b): return b; case .int(let i): return i; case .double(let d): return d; case .string(let s): return s; case .null: return NSNull() }
    }
    public var doubleValue: Double? {
        switch self { case .int(let i): return Double(i); case .double(let d): return d; case .string(let s): return Double(s); case .bool(let b): return b ? 1 : 0; case .null: return nil }
    }
    public var boolValue: Bool? {
        switch self { case .bool(let b): return b; case .int(let i): return i != 0; case .string(let s): return ["on", "true", "1"].contains(s.lowercased()); default: return nil }
    }
    public var description: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return "\(i)"
        case .double(let d): return d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
        case .string(let s): return s
        case .null: return "-"
        }
    }
    /// 按 MIoT format 转换类型
    public func coerced(to format: String) -> PropValue {
        switch format {
        case "bool": return .bool(boolValue ?? false)
        case "float": return doubleValue.map { .double($0) } ?? self
        case "string": return .string(description)
        default: return doubleValue.map { .int(Int($0.rounded())) } ?? self
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else { self = .string(try c.decode(String.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .bool(let b): try c.encode(b); case .int(let i): try c.encode(i); case .double(let d): try c.encode(d); case .string(let s): try c.encode(s); case .null: try c.encodeNil() }
    }
}

public struct DeviceState: Sendable {
    public var values: [String: PropValue]
    public var spec: DeviceSpec?
    public var legacy: Bool
    public var source: String
    public var updated = Date()
    public init(values: [String: PropValue], spec: DeviceSpec?, legacy: Bool, source: String) {
        self.values = values; self.spec = spec; self.legacy = legacy; self.source = source
    }
}

/// 记录每台设备的局域网是否可达。不在家时局域网请求只会超时，
/// 失败一次后在 backoff 时间内直接走云端，不再每次先等一个超时。
struct LANHealth {
    var backoff: TimeInterval = 300
    private var downUntil: [String: Date] = [:]
    func shouldTry(_ did: String, now: Date = Date()) -> Bool { downUntil[did].map { now >= $0 } ?? true }
    mutating func recordFailure(_ did: String, now: Date = Date()) { downUntil[did] = now.addingTimeInterval(backoff) }
    mutating func recordSuccess(_ did: String) { downUntil[did] = nil }
    mutating func reset() { downUntil = [:] }
}

/// 统一的设备读写：MIoT 走云端 miotspec，局域网 miIO 兜底；空调伴侣走旧版命令（局域网优先）
/// 可以在任意线程使用：可变状态都由 lock 保护。
public final class Controller: @unchecked Sendable {
    public let specs = SpecStore.shared
    private let lock = NSLock()
    private var _cloud: XiaomiCloud?
    private var lanDevices: [String: MiIODevice] = [:]
    private var health = LANHealth()
    private let pathMonitor = NWPathMonitor()
    private var lastPath: String?
    private var _makeLAN: @Sendable (String, String) throws -> MiIODevice = { ip, token in try MiIODevice(ip: ip, tokenHex: token, timeout: 2.5) }

    public var cloud: XiaomiCloud? {
        get { lock.withLock { _cloud } }
        set { lock.withLock { _cloud = newValue } }
    }
    /// 测试时替换局域网设备的创建方式
    var makeLAN: @Sendable (String, String) throws -> MiIODevice {
        get { lock.withLock { _makeLAN } }
        set { lock.withLock { _makeLAN = newValue } }
    }

    public init(cloud: XiaomiCloud?) {
        _cloud = cloud
        // 换了网络（比如回到家）就重新尝试局域网；启动时的第一次回调不算
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let sig = "\(path.status)|" + path.availableInterfaces.map(\.name).joined(separator: ",")
            lock.withLock {
                if let last = self.lastPath, last != sig { self.health.reset() }
                self.lastPath = sig
            }
        }
        pathMonitor.start(queue: .global(qos: .utility))
    }
    deinit { pathMonitor.cancel() }

    public static func isLegacyAC(_ model: String) -> Bool { model.hasPrefix("lumi.acpartner.") }
    public static let legacyProps = ["power", "mode", "tar_temp", "fan_level", "ver_swing", "load_power"]
    static let legacySetters = ["power": "set_power", "mode": "set_mode", "tar_temp": "set_tar_temp", "fan_level": "set_fan_level", "ver_swing": "set_ver_swing"]

    /// 设备的局域网连接（同一设备复用，保留握手结果）。最近不可达且有云端可用时返回 nil，直接走云端。
    func lan(_ d: Device) -> MiIODevice? {
        guard let ip = d.ip, let t = d.token, !ip.isEmpty, t.count == 32 else { return nil }
        return lock.withLock {
            guard _cloud == nil || health.shouldTry(d.did) else { return nil }
            let k = "\(d.did)|\(ip)|\(t)"
            if let m = lanDevices[k] { return m }
            guard let m = try? _makeLAN(ip, t) else { return nil }
            lanDevices[k] = m
            return m
        }
    }

    /// 执行一次局域网请求，并记录这台设备的局域网是否可达
    func viaLAN<T: Sendable>(_ d: Device, _ m: MiIODevice, _ op: (MiIODevice) async throws -> T) async throws -> T {
        do {
            let r = try await op(m)
            lock.withLock { health.recordSuccess(d.did) }
            return r
        } catch {
            if MiIODevice.isUnreachable(error) { lock.withLock { health.recordFailure(d.did) } }
            throw error
        }
    }

    public func readState(_ d: Device) async throws -> DeviceState {
        if Self.isLegacyAC(d.model) {
            var raw: [PropValue]?; var src = "lan"; var lastErr: Error = MiIOError.noLAN
            if let m = lan(d) { do { raw = try await viaLAN(d, m) { try await $0.send(method: "get_prop", params: Self.legacyProps.map { .string($0) }) } } catch { lastErr = error } }
            if raw == nil, let c = cloud { raw = (try await c.rpc(did: d.did, method: "get_prop", params: Self.legacyProps) as? [Any])?.map { PropValue($0) }; src = "cloud" }
            guard let raw else { throw lastErr }
            var v: [String: PropValue] = [:]
            for (k, x) in zip(Self.legacyProps, raw) { v[k] = x }
            return DeviceState(values: v, spec: nil, legacy: true, source: src)
        }
        guard let spec = try await specs.spec(for: d.model) else { return DeviceState(values: [:], spec: nil, legacy: false, source: "none") }
        let props = spec.controlServices.flatMap(\.properties).filter(\.readable).prefix(48).map { ($0.siid, $0.iid) }
        var vals: [String: PropValue] = [:]; var src = "cloud"; var lastErr: Error?
        if let c = cloud {
            do { for chunk in stride(from: 0, to: props.count, by: 16).map({ Array(props[$0..<min($0 + 16, props.count)]) }) {
                vals.merge(try await c.getProps(did: d.did, chunk).mapValues { PropValue($0) }) { $1 } } }
            catch { lastErr = error }
        }
        if vals.isEmpty, let m = lan(d) {
            src = "lan"
            do { for chunk in stride(from: 0, to: props.count, by: 8).map({ Array(props[$0..<min($0 + 8, props.count)]) }) {
                vals.merge(try await viaLAN(d, m) { try await $0.getProperties(chunk) }) { $1 } } }
            catch { lastErr = lastErr ?? error }
        }
        if vals.isEmpty, !props.isEmpty, let e = lastErr ?? (cloud == nil ? MiIOError.noLAN : nil) { throw e }
        return DeviceState(values: vals, spec: spec, legacy: false, source: src)
    }

    public func set(_ d: Device, key: String, value: PropValue) async throws {
        if Self.isLegacyAC(d.model) {
            guard let method = Self.legacySetters[key] else { throw MijiaError.unknownProperty(key) }
            var v = value
            if key == "power" || key == "ver_swing", case .bool(let b) = value { v = .string(b ? "on" : "off") }
            if key == "tar_temp" { v = value.coerced(to: "int") }
            if let m = lan(d) {
                do { _ = try await viaLAN(d, m) { try await $0.send(method: method, params: [v]) }; return } catch { if cloud == nil { throw error } }
            }
            guard let c = cloud else { throw MiIOError.noLAN }
            _ = try await c.rpc(did: d.did, method: method, params: [v.any]); return
        }
        let p = key.split(separator: ".").compactMap { Int($0) }
        guard p.count == 2 else { throw MijiaError.unknownProperty(key) }
        if let c = cloud {
            do { try await c.setProp(did: d.did, siid: p[0], piid: p[1], value: value.any); return }
            catch { if lan(d) == nil { throw error } }
        }
        guard let m = lan(d) else { throw MiIOError.noLAN }
        try await viaLAN(d, m) { try await $0.setProperty(siid: p[0], piid: p[1], value: value) }
    }

    public func action(_ d: Device, key: String, inputs: [PropValue]) async throws -> PropValue {
        let p = key.split(separator: ".").compactMap { Int($0) }
        guard p.count == 2 else { throw MijiaError.unknownProperty(key) }
        if let c = cloud { return PropValue(try await c.action(did: d.did, siid: p[0], aiid: p[1], inputs: inputs.map(\.any))) }
        guard let m = lan(d) else { throw MiIOError.noLAN }
        return try await viaLAN(d, m) { try await $0.action(siid: p[0], aiid: p[1], inputs: inputs) }
    }
}
