import Foundation

/// 通知：靠轮询比较前后两次状态得出事件。第一次看到设备只记基线，不提醒。
public enum NotifyKind: String, Codable, CaseIterable, Sendable {
    case contactOpened, leak, motion, offline, online, powerChange
    /// 默认开启：门窗打开、浸水；其余默认关闭，避免打扰
    public var defaultOn: Bool { self == .contactOpened || self == .leak }
}

/// 一台设备在某一时刻和通知有关的状态
public struct NotifySnapshot: Equatable, Sendable {
    public var online: Bool
    public var contactClosed: Bool?
    public var leak: Bool?
    public var motion: Bool?
    /// 距上次有人移动的秒数（部分人体传感器只有这个）
    public var noMotionSeconds: Double?
    public var powerOn: Bool?
    public init(online: Bool, contactClosed: Bool? = nil, leak: Bool? = nil, motion: Bool? = nil, noMotionSeconds: Double? = nil, powerOn: Bool? = nil) {
        self.online = online; self.contactClosed = contactClosed; self.leak = leak; self.motion = motion
        self.noMotionSeconds = noMotionSeconds; self.powerOn = powerOn
    }
}

public enum NotifyEvent: Equatable, Sendable {
    case contactOpened, leakDetected, leakCleared, motion, wentOffline, cameOnline, powered(Bool)
    public var kind: NotifyKind {
        switch self {
        case .contactOpened: return .contactOpened
        case .leakDetected, .leakCleared: return .leak
        case .motion: return .motion
        case .wentOffline: return .offline
        case .cameOnline: return .online
        case .powered: return .powerChange
        }
    }
}

public enum NotifyRules {
    /// 两次状态之间发生了什么
    public static func events(old: NotifySnapshot?, new: NotifySnapshot) -> [NotifyEvent] {
        guard let old else { return [] }
        var out: [NotifyEvent] = []
        if old.online && !new.online { out.append(.wentOffline) }
        if !old.online && new.online { out.append(.cameOnline) }
        guard new.online else { return out }
        if old.contactClosed == true, new.contactClosed == false { out.append(.contactOpened) }
        if old.leak == false, new.leak == true { out.append(.leakDetected) }
        if old.leak == true, new.leak == false { out.append(.leakCleared) }
        if old.motion == false, new.motion == true { out.append(.motion) }
        else if let a = old.noMotionSeconds, let b = new.noMotionSeconds, b < a { out.append(.motion) }
        if let a = old.powerOn, let b = new.powerOn, a != b { out.append(.powered(b)) }
        return out
    }
}

/// 防刷屏：同一设备同一类事件在 window 内只提醒一次；离线要连续看到 offlineConfirmations 次才算
public struct NotifyDebouncer: Sendable {
    public var window: TimeInterval
    public var offlineConfirmations: Int
    private var last: [String: Date] = [:]
    private var offlineSeen: [String: Int] = [:]
    public init(window: TimeInterval = 300, offlineConfirmations: Int = 2) { self.window = window; self.offlineConfirmations = offlineConfirmations }

    /// 每轮轮询都调用：记录离线次数，返回是否已确认离线
    public mutating func confirmOffline(_ did: String, online: Bool) -> Bool {
        if online { offlineSeen[did] = nil; return false }
        offlineSeen[did, default: 0] += 1
        return offlineSeen[did]! >= offlineConfirmations
    }
    public mutating func shouldFire(_ did: String, _ k: NotifyKind, now: Date = Date()) -> Bool {
        let key = did + "|" + k.rawValue
        if let t = last[key], now.timeIntervalSince(t) < window { return false }
        last[key] = now; return true
    }
}

/// 通知设置：按类型开关 + 按设备静音（UserDefaults）
public struct NotifySettings: Codable, Equatable, Sendable {
    public var kinds: [NotifyKind: Bool] = [:]
    public var muted: Set<String> = []
    public init() {}
    public static let defaultsKey = "MijiaBarNotify"
    public func isOn(_ k: NotifyKind) -> Bool { kinds[k] ?? k.defaultOn }
    public func allows(_ did: String, _ k: NotifyKind) -> Bool { isOn(k) && !muted.contains(did) }
    public var anyOn: Bool { NotifyKind.allCases.contains(where: isOn) }
    public static func load(_ d: UserDefaults = .standard) -> NotifySettings {
        d.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(NotifySettings.self, from: $0) } ?? NotifySettings()
    }
    public func save(_ d: UserDefaults = .standard) { if let x = try? JSONEncoder().encode(self) { d.set(x, forKey: Self.defaultsKey) } }
}
