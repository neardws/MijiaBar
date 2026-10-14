import Foundation

/// 菜单栏速览：用户选的几个数值显示在菜单栏图标旁边（最多 Glance.maxItems 个）
public enum GlanceKind: String, Codable, CaseIterable, Sendable {
    case temperature, humidity, pm25, acTarget, power
}

public struct GlanceItem: Codable, Hashable, Sendable {
    public var did: String
    public var kind: GlanceKind
    public init(did: String, kind: GlanceKind) { self.did = did; self.kind = kind }
}

public enum Glance {
    public static let maxItems = 3
    public static let defaultsKey = "MijiaBarGlance"

    /// 紧凑格式：26° · 58% · PM35 · 36W；功率 ≥ 1000 W 显示 1.2kW
    public static func text(_ k: GlanceKind, _ v: Double) -> String {
        switch k {
        case .temperature, .acTarget:
            let r = (v * 10).rounded() / 10
            return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + "°"
        case .humidity: return "\(Int(v.rounded()))%"
        case .pm25: return "PM\(Int(v.rounded()))"
        case .power: return v >= 1000 ? String(format: "%.1fkW", v / 1000) : "\(Int(v.rounded()))W"
        }
    }

    public static func load(_ d: UserDefaults = .standard) -> [GlanceItem] {
        guard let data = d.data(forKey: defaultsKey), let v = try? JSONDecoder().decode([GlanceItem].self, from: data) else { return [] }
        return sanitize(v)
    }
    public static func save(_ items: [GlanceItem], _ d: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(sanitize(items)) { d.set(data, forKey: defaultsKey) }
    }
    /// 去重并截到上限
    public static func sanitize(_ items: [GlanceItem]) -> [GlanceItem] {
        var seen = Set<GlanceItem>(); return Array(items.filter { seen.insert($0).inserted }.prefix(maxItems))
    }
}
