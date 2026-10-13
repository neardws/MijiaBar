import Foundation

public enum PropValue: Codable, Hashable, CustomStringConvertible {
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

public struct DeviceState {
    public var values: [String: PropValue]
    public var spec: DeviceSpec?
    public var legacy: Bool
    public var source: String
    public var updated = Date()
    public init(values: [String: PropValue], spec: DeviceSpec?, legacy: Bool, source: String) {
        self.values = values; self.spec = spec; self.legacy = legacy; self.source = source
    }
}

/// 统一的设备读写：MIoT 走云端 miotspec，局域网 miIO 兜底；空调伴侣走旧版命令（局域网优先）
public final class Controller {
    public var cloud: XiaomiCloud?
    public let specs = SpecStore.shared
    public init(cloud: XiaomiCloud?) { self.cloud = cloud }

    public static func isLegacyAC(_ model: String) -> Bool { model.hasPrefix("lumi.acpartner.") }
    public static let legacyProps = ["power", "mode", "tar_temp", "fan_level", "ver_swing", "load_power"]
    static let legacySetters = ["power": "set_power", "mode": "set_mode", "tar_temp": "set_tar_temp", "fan_level": "set_fan_level", "ver_swing": "set_ver_swing"]

    func lan(_ d: Device) -> MiIODevice? {
        guard let ip = d.ip, let t = d.token, !ip.isEmpty, t.count == 32 else { return nil }
        return try? MiIODevice(ip: ip, tokenHex: t, timeout: 2.5)
    }

    public func readState(_ d: Device) async throws -> DeviceState {
        if Self.isLegacyAC(d.model) {
            var raw: [Any]?; var src = "lan"; var lastErr: Error = MiIOError.noLAN
            if let m = lan(d) { do { raw = try await m.send(method: "get_prop", params: Self.legacyProps) as? [Any] } catch { lastErr = error } }
            if raw == nil, let c = cloud { raw = try await c.rpc(did: d.did, method: "get_prop", params: Self.legacyProps) as? [Any]; src = "cloud" }
            guard let raw else { throw lastErr }
            var v: [String: PropValue] = [:]
            for (k, x) in zip(Self.legacyProps, raw) { v[k] = PropValue(x) }
            return DeviceState(values: v, spec: nil, legacy: true, source: src)
        }
        guard let spec = try await specs.spec(for: d.model) else { return DeviceState(values: [:], spec: nil, legacy: false, source: "none") }
        let props = spec.controlServices.flatMap(\.properties).filter(\.readable).prefix(48).map { ($0.siid, $0.iid) }
        var vals: [String: Any] = [:]; var src = "cloud"; var lastErr: Error?
        if let c = cloud {
            do { for chunk in stride(from: 0, to: props.count, by: 16).map({ Array(props[$0..<min($0 + 16, props.count)]) }) {
                vals.merge(try await c.getProps(did: d.did, chunk)) { $1 } } }
            catch { lastErr = error }
        }
        if vals.isEmpty, let m = lan(d) {
            src = "lan"
            do { for chunk in stride(from: 0, to: props.count, by: 8).map({ Array(props[$0..<min($0 + 8, props.count)]) }) {
                vals.merge(try await m.getProperties(chunk)) { $1 } } }
            catch { lastErr = lastErr ?? error }
        }
        if vals.isEmpty, !props.isEmpty, let e = lastErr ?? (cloud == nil ? MiIOError.noLAN : nil) { throw e }
        return DeviceState(values: vals.mapValues { PropValue($0) }, spec: spec, legacy: false, source: src)
    }

    public func set(_ d: Device, key: String, value: PropValue) async throws {
        if Self.isLegacyAC(d.model) {
            guard let method = Self.legacySetters[key] else { throw MijiaError.unknownProperty(key) }
            var v = value
            if key == "power" || key == "ver_swing", case .bool(let b) = value { v = .string(b ? "on" : "off") }
            if key == "tar_temp" { v = value.coerced(to: "int") }
            if let m = lan(d) {
                do { _ = try await m.send(method: method, params: [v.any]); return } catch { if cloud == nil { throw error } }
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
        try await m.setProperty(siid: p[0], piid: p[1], value: value.any)
    }

    public func action(_ d: Device, key: String, inputs: [Any]) async throws -> Any {
        let p = key.split(separator: ".").compactMap { Int($0) }
        guard p.count == 2 else { throw MijiaError.unknownProperty(key) }
        if let c = cloud { return try await c.action(did: d.did, siid: p[0], aiid: p[1], inputs: inputs) }
        guard let m = lan(d) else { throw MiIOError.noLAN }
        return try await m.action(siid: p[0], aiid: p[1], inputs: inputs)
    }
}
