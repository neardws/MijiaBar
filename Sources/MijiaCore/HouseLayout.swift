import Foundation

/// 「小屋」视图的布局：固定的像素房间模块，按米家房间名自动匹配；每个模块有按设备类型固定的位置。
/// 用户不需要画户型；房间按列表里保存的房间顺序拼成一栋房子。
public enum HouseModule: String, CaseIterable, Codable, Sendable {
    case living, bedroom, study, generic

    /// 按房间名匹配模块（简繁英都认）；认不出的是 generic（原型里暂不显示）
    public static func from(roomName: String?) -> HouseModule {
        let n = (roomName ?? "").lowercased()
        func has(_ ks: [String]) -> Bool { ks.contains { n.contains($0) } }
        if has(["客厅", "客廳", "起居", "living", "lounge"]) { return .living }
        if has(["卧", "臥", "bedroom", "睡房"]) { return .bedroom }
        if has(["书房", "書房", "办公", "辦公", "工作室", "study", "office"]) { return .study }
        return .generic
    }
}

public enum HouseSlotKind: String, CaseIterable, Sendable {
    case light, ac, tv
    public static func of(_ c: DeviceCategory) -> HouseSlotKind? {
        switch c { case .light: return .light; case .ac: return .ac; case .tv: return .tv; default: return nil }
    }
}

public struct HouseSlot: Hashable, Sendable {
    public let kind: HouseSlotKind
    public let index: Int
    public init(_ kind: HouseSlotKind, _ index: Int) { self.kind = kind; self.index = index }
}

public enum HouseLayout {
    /// 每个模块每类设备有几个固定位置
    public static func capacity(_ m: HouseModule, _ k: HouseSlotKind) -> Int {
        switch (m, k) {
        case (.living, .light): return 2
        case (.bedroom, .light): return 2
        case (.study, .light): return 2
        case (.living, .tv), (.bedroom, .tv): return 1
        case (.generic, _), (.study, .tv): return 0
        case (_, .ac): return 1
        }
    }
    /// 按顺序把设备放进位置；放不下或类型不支持的进 overflow（界面上显示为「还有 N 台」）
    public static func assign(_ ds: [Device], in m: HouseModule) -> (placed: [(Device, HouseSlot)], overflow: [Device]) {
        var used: [HouseSlotKind: Int] = [:]; var placed: [(Device, HouseSlot)] = []; var over: [Device] = []
        for d in ds {
            guard let k = HouseSlotKind.of(d.category), used[k, default: 0] < capacity(m, k) else { over.append(d); continue }
            placed.append((d, HouseSlot(k, used[k, default: 0]))); used[k, default: 0] += 1
        }
        return (placed, over)
    }
    /// 房间在房子里的格子位置：两列，依次从后往前排（第 i 个房间 → (i % 2, i / 2)）
    public static func cell(_ i: Int) -> (col: Int, row: Int) { (i % 2, i / 2) }
}
