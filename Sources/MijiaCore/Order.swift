import Foundation

/// 用户自定义的房间与设备顺序（每个家庭一份，存在 prefs.json，App 与 CLI/MCP 共用）。
/// 房间用房间名作键（设备上只有房间名），未分配房间的键为 ""；收藏区的键为 `Prefs.favoritesKey`。
public struct HomeOrder: Codable, Equatable, Sendable {
    public var rooms: [String]?
    public var devices: [String: [String]]?
    public init() {}
}

public enum Ordering {
    /// 按保存的顺序排列 ids：保存过且仍存在的在前（保持保存顺序），新出现的按原有默认顺序接在后面，已删除的忽略
    public static func arrange(_ ids: [String], saved: [String]?) -> [String] {
        guard let saved, !saved.isEmpty else { return ids }
        let present = Set(ids); var seen = Set<String>(); var out: [String] = []
        for s in saved where present.contains(s) && seen.insert(s).inserted { out.append(s) }
        return out + ids.filter { !seen.contains($0) }
    }
    /// 只调整了可见项（搜索、隐藏设备不可见）时，把新的可见顺序写回完整列表：不可见项留在原位
    public static func mergeVisible(full: [String], visible: [String]) -> [String] {
        let vs = Set(visible); var it = visible.makeIterator()
        let merged = full.map { vs.contains($0) ? (it.next() ?? $0) : $0 }
        return merged + visible.filter { !full.contains($0) }
    }
    public enum Move: Sendable { case up, down, top }
    /// 把 id 上移 / 下移一位或移到顶部
    public static func moved(_ list: [String], _ id: String, _ m: Move) -> [String] {
        guard let i = list.firstIndex(of: id) else { return list }
        var l = list
        switch m {
        case .up: if i > 0 { l.swapAt(i, i - 1) }
        case .down: if i < l.count - 1 { l.swapAt(i, i + 1) }
        case .top: l.remove(at: i); l.insert(id, at: 0)
        }
        return l
    }
    /// 拖拽：把 id 放到 target 的位置（向下拖时放在 target 之后，向上拖时放在之前）
    public static func dropped(_ list: [String], _ id: String, onto target: String) -> [String] {
        guard id != target, let from = list.firstIndex(of: id), let to = list.firstIndex(of: target) else { return list }
        var l = list; l.remove(at: from); l.insert(id, at: to); return l
    }
}

extension Prefs {
    public static let favoritesKey = "★favorites"
    /// 设备的默认顺序：在线在前，再按名称
    public func defaultLess(_ a: Device, _ b: Device) -> Bool {
        let x = (a.isOnline ? 0 : 1, name(a)), y = (b.isOnline ? 0 : 1, name(b))
        return x.0 != y.0 ? x.0 < y.0 : x.1.localizedStandardCompare(y.1) == .orderedAscending
    }
    /// key 为 nil 时取房间顺序，否则取该房间（或收藏区）的设备顺序
    public func savedOrder(home: String, key: String?) -> [String]? {
        guard let h = order?[home] else { return nil }
        return key.map { h.devices?[$0] } ?? h.rooms
    }
    public mutating func setOrder(home: String, key: String?, _ ids: [String]) {
        var all = order ?? [:]; var h = all[home] ?? HomeOrder()
        if let key { var d = h.devices ?? [:]; d[key] = ids; h.devices = d } else { h.rooms = ids }
        all[home] = h; order = all
    }
    public func orderedRooms(home: String, _ keys: [String]) -> [String] { Ordering.arrange(keys, saved: savedOrder(home: home, key: nil)) }
    /// devices 先按默认顺序排，再套用保存的顺序
    public func orderedDevices(home: String, key: String, _ ds: [Device]) -> [Device] {
        let sorted = ds.sorted(by: defaultLess)
        let byId = Dictionary(sorted.map { ($0.did, $0) }, uniquingKeysWith: { a, _ in a })
        return Ordering.arrange(sorted.map(\.did), saved: savedOrder(home: home, key: key)).compactMap { byId[$0] }
    }
    /// CLI / MCP 的列表顺序：家庭按出现顺序，房间和房间内设备按用户顺序（收藏只是标记，设备仍在自己的房间里）
    public func sortedForList(_ ds: [Device], roomTitle: (String) -> String = { $0 }) -> [Device] {
        var homes: [String] = []; for d in ds where !homes.contains(d.homeId) { homes.append(d.homeId) }
        return homes.flatMap { h -> [Device] in
            let inHome = ds.filter { $0.homeId == h }
            let groups = Dictionary(grouping: inHome) { $0.roomName ?? "" }
            let keys = groups.keys.sorted { roomTitle($0).localizedStandardCompare(roomTitle($1)) == .orderedAscending }
            return orderedRooms(home: h, keys).flatMap { orderedDevices(home: h, key: $0, groups[$0]!) }
        }
    }
}
