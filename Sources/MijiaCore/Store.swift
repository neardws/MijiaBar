import Foundation
import Security

public enum Paths {
    public static var support: URL {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MijiaBar")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    public static var specs: URL {
        let u = support.appendingPathComponent("specs")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}

func loadJSON<T: Decodable>(_ t: T.Type, _ name: String) -> T? {
    guard let d = try? Data(contentsOf: Paths.support.appendingPathComponent(name)) else { return nil }
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    return try? dec.decode(T.self, from: d)
}
func saveJSON<T: Encodable>(_ v: T, _ name: String) {
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let url = Paths.support.appendingPathComponent(name)
    guard let d = try? enc.encode(v) else { return }
    try? d.write(to: url, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
}

/// 登录凭据只存在 macOS 钥匙串里
public enum Keychain {
    static let service = "com.neardws.MijiaBar"
    static func base(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    public static func set(_ data: Data, account: String) {
        SecItemDelete(base(account) as CFDictionary)
        var q = base(account); q[kSecValueData as String] = data
        SecItemAdd(q as CFDictionary, nil)
    }
    public static func get(account: String) -> Data? {
        var q = base(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }
    public static func delete(account: String) { SecItemDelete(base(account) as CFDictionary) }
}

public struct Session: Codable, Equatable, Sendable {
    public var userId: String
    public var ssecurity: String
    public var serviceToken: String
    public var region: String
    public var cUserId: String?
    public init(userId: String, ssecurity: String, serviceToken: String, region: String, cUserId: String? = nil) {
        self.userId = userId; self.ssecurity = ssecurity; self.serviceToken = serviceToken; self.region = region; self.cUserId = cUserId
    }
    public static func load() -> Session? {
        guard let d = Keychain.get(account: "session") else { return nil }
        return try? JSONDecoder().decode(Session.self, from: d)
    }
    public func save() { if let d = try? JSONEncoder().encode(self) { Keychain.set(d, account: "session") } }
    public static func clear() { Keychain.delete(account: "session") }
}

public struct Room: Codable, Hashable, Sendable { public var id: String; public var name: String; public var dids: [String] }
public struct Home: Codable, Hashable, Identifiable, Sendable {
    public var id: String; public var name: String; public var ownerId: String; public var rooms: [Room]
    public init(id: String, name: String, ownerId: String, rooms: [Room]) { self.id = id; self.name = name; self.ownerId = ownerId; self.rooms = rooms }
}

public enum DeviceCategory: String, Codable, CaseIterable, Sendable {
    case ac, plug, light, fan, heater, dehumidifier, sensor, tv, camera, speaker, kitchen, printer, purifier, other
    public static func guess(_ model: String) -> DeviceCategory {
        let m = model.lowercased()
        func has(_ s: String...) -> Bool { s.contains { m.contains($0) } }
        if has("printer") { return .printer }
        if has(".ysj.", "waterpuri", "water_purifier", ".wp.") { return .purifier }
        if has("acpartner", "aircondition", ".ac.", "airc") { return .ac }
        if has("heater") { return .heater }
        if has("derh", "dehumid") { return .dehumidifier }
        if has(".fan.") { return .fan }
        if has("plug", "switch", "outlet") { return .plug }
        if has("light", "lamp", "bulb", "ceiling") { return .light }
        if has("sensor", "motion", "flood", "magnet", "weather") { return .sensor }
        if has(".tv.") { return .tv }
        if has("camera", "cateye") { return .camera }
        if has("speaker") { return .speaker }
        if has("cooker", "ihcooker", "juicer", "mfcp", "kettle") { return .kitchen }
        return .other
    }
}

public struct Device: Codable, Hashable, Identifiable, Sendable {
    public var did: String
    public var name: String
    public var model: String
    public var ip: String?
    public var token: String?
    public var isOnline: Bool
    public var homeId: String
    public var homeName: String
    public var roomName: String?
    public var lastOnline: Date?
    public var id: String { did }
    public var category: DeviceCategory { DeviceCategory.guess(model) }
    public var isBLE: Bool { did.hasPrefix("blt.") }
    public init(did: String, name: String, model: String, ip: String? = nil, token: String? = nil, isOnline: Bool = true,
                homeId: String = "", homeName: String = "", roomName: String? = nil, lastOnline: Date? = nil) {
        self.did = did; self.name = name; self.model = model; self.ip = ip; self.token = token; self.isOnline = isOnline
        self.homeId = homeId; self.homeName = homeName; self.roomName = roomName; self.lastOnline = lastOnline
    }
}

/// 设备列表缓存（含局域网 token，文件权限 0600，只在本机）
public struct DeviceCache: Codable, Sendable {
    public var homes: [Home]; public var devices: [Device]; public var updated: Date
    public init(homes: [Home], devices: [Device], updated: Date) { self.homes = homes; self.devices = devices; self.updated = updated }
    public static func load() -> DeviceCache? { loadJSON(DeviceCache.self, "devices.json") }
    public func save() { saveJSON(self, "devices.json") }
    public static func clear() { try? FileManager.default.removeItem(at: Paths.support.appendingPathComponent("devices.json")) }
}

public struct DevicePrefs: Codable, Hashable, Sendable {
    public var alias: String?
    public var hidden: Bool?
    public var favorite: Bool?
    public var lastUsed: Date?
    public init() {}
}

public struct Prefs: Codable, Equatable, Sendable {
    public var devices: [String: DevicePrefs] = [:]
    public var region: String = "cn"
    public var selectedHome: String?
    public var menuBarDid: String?
    public init() {}
    public static func load() -> Prefs { loadJSON(Prefs.self, "prefs.json") ?? Prefs() }
    public func save() { saveJSON(self, "prefs.json") }

    /// 默认隐藏规则：离线，或云端 last_online 超过 30 天；用户手动设置优先
    public static let staleInterval: TimeInterval = 30 * 86400
    public static func autoHidden(_ d: Device) -> Bool {
        if !d.isOnline { return true }
        if let t = d.lastOnline, Date().timeIntervalSince(t) > staleInterval { return true }
        return false
    }
    public func isHidden(_ d: Device) -> Bool { devices[d.did]?.hidden ?? Prefs.autoHidden(d) }
    public func name(_ d: Device) -> String { devices[d.did]?.alias ?? d.name }
}

public struct AgentPolicy: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case disabled, readOnly, allowlist, full }
    public var mode: Mode = .readOnly
    public var allowlist: [String] = []
    public var confirmWrites: Bool = true
    public init() {}
    public static func load() -> AgentPolicy { loadJSON(AgentPolicy.self, "agent.json") ?? AgentPolicy() }
    public func save() { saveJSON(self, "agent.json") }
    public var canRead: Bool { mode != .disabled }
    public func canWrite(_ did: String) -> Bool { mode == .full || (mode == .allowlist && allowlist.contains(did)) }
}
