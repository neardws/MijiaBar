import Foundation

/// 「小屋」视图的布局：固定的像素房间模块，按米家房间名自动匹配；每个模块有按设备类型固定的位置。
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

    /// 按顺序把设备放进位置；放不下或类型不支持的进 overflow
    public static func assign(_ ds: [Device], in m: HouseModule) -> (placed: [(Device, HouseSlot)], overflow: [Device]) {
        var used: [HouseSlotKind: Int] = [:]; var placed: [(Device, HouseSlot)] = []; var over: [Device] = []
        for d in ds {
            guard let k = HouseSlotKind.of(d.category), used[k, default: 0] < capacity(m, k) else { over.append(d); continue }
            placed.append((d, HouseSlot(k, used[k, default: 0]))); used[k, default: 0] += 1
        }
        return (placed, over)
    }

    /// 客厅模块内设备锚点（米）：x 沿墙宽，z 沿墙深，y 高度
    public static func livingAnchor(_ kind: HouseSlotKind, slot: Int) -> (x: Float, y: Float, z: Float) {
        switch kind {
        case .ac: return (2.2, 1.75, 0.12)
        case .tv: return (0.55, 0.42, 2.55)
        case .light: return slot == 0 ? (5.15, 0.02, 4.15) : (0.85, 0.02, 0.85)
        }
    }

    public static let livingRoomSize: Float = 6
}
