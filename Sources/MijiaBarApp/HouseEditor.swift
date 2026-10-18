import AppKit
import MijiaCore
import SwiftUI

// 小屋编辑模式（HouseWindow「编辑」）：在剖面上画出灯具位 / 徽章位，右侧面板按房间列出设备，
// 改动立即写进 house.json（MijiaCore/HouseStore），CLI / Agent / 其他 Mac 看到的是同一份配置。

struct HouseSelection: Hashable {
    let roomKey: String
    let spot: HouseSpot
}

struct HouseEditContext {
    var selected: HouseSelection?
    var onSelect: (HouseSelection) -> Void
    var drag = HouseDragState()
    /// 拖放回调里读当前的拖动（drag 是渲染时的快照，DropDelegate 可能比它新）
    var currentSession: () -> HouseDragSession? = { nil }
    /// 正在拖动时，把设备放到这个位置的结果（nil = 没在拖）
    var verdict: (HouseSelection) -> HouseDropVerdict? = { _ in nil }
    var beginDrag: (String, HouseSelection?) -> NSItemProvider = { _, _ in NSItemProvider() }
    var setHover: (HouseSelection?) -> Void = { _ in }
    var setInScene: (Bool) -> Void = { _ in }
    /// 松手：目标位置（nil = 剖面空白处）+ 拖动内容
    var perform: @MainActor (HouseSelection?, String?) -> Void = { _, _ in }
}

enum HouseFixtureNames {
    static func title(_ id: String) -> String {
        switch id {
        case "floor_lamp": return L("落地灯位", "Floor lamp")
        case "sconce": return L("壁灯位", "Wall sconce")
        case "tv": return L("电视位", "TV")
        case "bedside": return L("床头灯位", "Bedside lamp")
        case "ac": return L("空调位", "Air conditioner")
        case "ceiling": return L("吸顶灯位", "Ceiling light")
        case "pendant": return L("吊灯位", "Pendant light")
        case "wall_lamp": return L("壁灯位", "Wall lamp")
        case "monitor": return L("显示器位", "Monitor")
        case "entry_light": return L("玄关灯位", "Entry light")
        default: return id
        }
    }

    /// 书房的显示器位和吸顶灯位挨得近，标签放到框上方，避免和徽章重叠
    static let labelAbove: Set<String> = ["monitor", "ceiling", "pendant", "entry_light"]

    static func spot(_ s: HouseSpot?) -> String {
        switch s {
        case .fixture(let id): return title(id)
        case .badge: return L("徽章", "Badge")
        case nil: return L("只在按钮行", "Button row only")
        }
    }
}

// MARK: - 剖面上的位置框

struct HouseEditSlots: View {
    let module: HouseCutawayModule
    let room: HouseRoom
    let artSize: CGSize
    let edit: HouseEditContext

    /// 一个房间里所有可放置的位置（剖面原图坐标），点选和拖放命中测试共用
    static func targets(module: HouseCutawayModule, room: HouseRoom) -> [(sel: HouseSelection, rect: CGRect, round: Bool, labelAbove: Bool, fixture: String?)] {
        var out: [(HouseSelection, CGRect, Bool, Bool, String?)] = []
        for light in module.lights {
            // 墙挂灯具随墙被切掉：位置不在了，空着就不给放（没法往看不见的壁灯上放灯）；
            // 已经放了设备的，在 alt 地面点留一个位置框，方便拖走
            if light.hidden == true, !room.devices.contains(where: { $0.spot == .fixture(light.id) }) { continue }
            if let r = rect(light) {
                out.append((HouseSelection(roomKey: room.key, spot: .fixture(light.id)), r, true, HouseFixtureNames.labelAbove.contains(light.id), light.id))
            }
        }
        for (i, id) in HouseCatalog.badgeIds(room.module).enumerated() {
            if let p = module.badges?[safe: i], p.count >= 2 {
                out.append((HouseSelection(roomKey: room.key, spot: .badge(id)), CGRect(x: p[0] - 26, y: p[1] - 44, width: 52, height: 52), false, false, nil))
            }
        }
        return out.map { (sel: $0.0, rect: $0.1, round: $0.2, labelAbove: $0.3, fixture: $0.4) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.targets(module: module, room: room), id: \.sel) { t in
                let d = room.devices.first { $0.spot == t.sel.spot }
                slot(t.sel, rect: t.rect, round: t.round, device: d,
                     label: t.fixture.map { f in d?.name ?? HouseFixtureNames.title(f) }, labelAbove: t.labelAbove)
            }
        }
        .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
    }

    private static func rect(_ l: HouseLightSpec) -> CGRect? {
        // 合成场景：墙挂灯具随墙被切掉 / 吸顶灯 → 用 alt 点（地面替代位 / 光斑上方），和徽章位同样大小
        if let a = l.alt, a.count >= 2, l.hidden == true || l.corePolygon == nil {
            return CGRect(x: a[0] - 26, y: a[1] - 44, width: 52, height: 52)
        }
        if let poly = l.corePolygon, !poly.isEmpty {
            let xs = poly.map { $0[0] }, ys = poly.map { $0[1] }
            let r = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            return r.insetBy(dx: min(0, (r.width - 44) / 2), dy: min(0, (r.height - 40) / 2)).insetBy(dx: -8, dy: -8)
        }
        if case .ellipse(let cx, let cy, _, _)? = l.reveal {
            return CGRect(x: cx - 32, y: cy - 20, width: 64, height: 40)   // 没有灯具本体（吸顶灯 / 玄关灯）：放在光斑中心
        }
        return nil
    }

    private enum DropLook {
        case none, candidate, invalid, hoverOK, hoverBad(String)
        var isCandidate: Bool { if case .candidate = self { return true }; return false }
        var isInvalid: Bool { if case .invalid = self { return true }; return false }
        var isHover: Bool { switch self { case .hoverOK, .hoverBad: return true; default: return false } }
    }

    private func look(_ sel: HouseSelection) -> DropLook {
        guard edit.drag.session != nil, edit.drag.inScene, let v = edit.verdict(sel) else { return .none }
        let hovered = edit.drag.hover == sel
        switch v {
        case .accept: return hovered ? .hoverOK : .candidate
        case .reject(let r): return hovered ? .hoverBad(r.message) : .invalid
        }
    }

    @ViewBuilder
    private func slot(_ sel: HouseSelection, rect r: CGRect, round: Bool, device: HouseDevice?, label: String?, labelAbove: Bool) -> some View {
        let selected = edit.selected == sel
        let lk = look(sel)
        let green = Color(red: 0.25, green: 0.9, blue: 0.45), red = Color(red: 1, green: 0.32, blue: 0.3)
        let base: Color = selected ? .accentColor : (device != nil ? Color(red: 1, green: 0.84, blue: 0.4) : .white)
        let color: Color = { switch lk { case .hoverOK, .candidate: return green; case .hoverBad: return red; default: return base } }()
        let solid: Bool = { switch lk { case .hoverOK, .hoverBad: return true; default: return selected } }()
        let isDragged = edit.drag.session?.did == device?.did && device != nil && edit.drag.session != nil
        let shape = RoundedRectangle(cornerRadius: round ? min(r.width, r.height) / 2 : 10, style: .continuous)
        ZStack {
            shape.fill(color.opacity(solid ? 0.28 : (lk.isCandidate ? 0.14 : 0.06)))
            shape.strokeBorder(color.opacity(solid ? 1 : 0.9), style: StrokeStyle(lineWidth: solid ? 4 : (lk.isCandidate ? 2.5 : 2), dash: solid ? [] : [7, 5]))
            if case .hoverBad = lk {
                Image(systemName: "nosign").font(.system(size: 18, weight: .bold)).foregroundStyle(red).shadow(color: .black.opacity(0.6), radius: 2)
            } else if case .hoverOK = lk {
                Image(systemName: device == nil ? "arrow.down.circle.fill" : "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(green).shadow(color: .black.opacity(0.6), radius: 2)
            } else if device == nil {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(color.opacity(0.9))
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
        }
        .frame(width: r.width, height: r.height)
        .scaleEffect(lk.isHover ? 1.1 : 1)
        .opacity(lk.isInvalid ? 0.3 : (isDragged ? 0.5 : 1))
        .contentShape(shape)
        .onTapGesture { edit.onSelect(sel) }
        .modifier(HouseSlotDrag(enabled: device != nil) { edit.beginDrag(device?.did ?? "", sel) })
        .position(x: r.midX, y: r.midY)
        if case .hoverBad(let why) = lk {
            hoverTag(why, color: red, at: CGPoint(x: r.midX, y: r.maxY + 18))
        } else if case .hoverOK = lk, let s = edit.drag.session {
            hoverTag(device == nil || device?.did == s.did ? L("放到这里", "Drop here") : L("和 ", "Swap with ") + (device?.name ?? "") + L(" 交换", ""),
                     color: green, at: CGPoint(x: r.midX, y: r.maxY + 18))
        } else if let label, !lk.isInvalid {
            Text(label)
                .font(.system(size: 14, weight: .semibold)).lineLimit(1)
                .foregroundStyle(device != nil ? Color.white : Color.black.opacity(0.8))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(device != nil ? Color.black.opacity(0.72) : Color.white.opacity(0.85)))
                .overlay(Capsule().stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                .fixedSize()
                .position(x: r.midX, y: labelAbove ? r.minY - 14 : r.maxY + 16)
                .allowsHitTesting(false)
        }
        if lk.isHover, edit.drag.showPreview, let s = edit.drag.session {
            // 截图模式：系统拖动图像不会进 cacheDisplay，这里画一个同样的拖动标签 + 指针
            HouseDragChip(name: s.name, category: s.category)
                .overlay(alignment: .topLeading) {
                    Image(systemName: "cursorarrow").font(.system(size: 22)).foregroundStyle(.white)
                        .shadow(color: .black, radius: 1).offset(x: -10, y: -14)
                }
                .fixedSize()
                .position(x: r.midX + 70, y: r.midY + 6)
                .allowsHitTesting(false)
        }
    }

    private func hoverTag(_ s: String, color: Color, at p: CGPoint) -> some View {
        Text(s).font(.system(size: 14, weight: .bold)).lineLimit(1)
            .foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.92)))
            .fixedSize()
            .position(p)
            .allowsHitTesting(false)
    }
}


/// 已放置的设备可以从位置上拖走（拖到别的位置 = 移动 / 交换；拖回面板或空白处 = 移出）
private struct HouseSlotDrag: ViewModifier {
    let enabled: Bool
    let provider: () -> NSItemProvider
    func body(content: Content) -> some View {
        if enabled { content.onDrag(provider) } else { content }
    }
}

struct HouseDragChip: View {
    let name: String
    let category: DeviceCategory
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: HouseChipStyle.icon(category)).foregroundStyle(HouseChipStyle.tint(category))
            Text(name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
    }
}

// MARK: - 拖放

/// 拖动中的设备（拖动开始时记下来；NSItemProvider 里只带 payload 校验用）
struct HouseDragSession: Equatable {
    let did: String
    let name: String
    let category: DeviceCategory
    /// 从剖面上的某个位置拖出来（nil = 从面板拖出来）
    let from: HouseSelection?
    var payload: String { HouseDragSession.prefix + did }
    static let prefix = "mijiabar-house-device:"
}

struct HouseDragState: Equatable {
    var session: HouseDragSession?
    var hover: HouseSelection?
    var inScene = false
    /// 只有截图模式为 true：自己画拖动标签
    var showPreview = false
}

/// 整个剖面一个拖放目标：按指针位置换算到原图坐标，命中哪个位置框就是哪个（剖面用了 scaleEffect，
/// 不在每个位置框上单独挂 onDrop，避免缩放后命中区域对不上）。指针不在任何位置框上 = 空白处。
struct HouseSceneDropDelegate: DropDelegate {
    let edit: HouseEditContext
    let targets: [(sel: HouseSelection, rect: CGRect)]
    let scale: CGFloat

    func hit(_ p: CGPoint) -> HouseSelection? {
        let q = CGPoint(x: p.x / scale, y: p.y / scale)
        return targets.first { $0.rect.insetBy(dx: -6, dy: -6).contains(q) }?.sel
    }
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.plainText]) && edit.currentSession() != nil }
    func dropEntered(info: DropInfo) { edit.setInScene(true); edit.setHover(hit(info.location)) }
    func dropExited(info: DropInfo) { edit.setHover(nil); edit.setInScene(false) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        let t = hit(info.location)
        edit.setHover(t)
        if let t { return DropProposal(operation: edit.verdict(t)?.isAccepted == true ? .move : .forbidden) }
        return DropProposal(operation: edit.currentSession()?.from != nil ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        let t = hit(info.location)
        let perform = edit.perform
        edit.setHover(nil); edit.setInScene(false)
        HouseDropPayload.load(info.itemProviders(for: [.plainText])) { perform(t, $0) }
        return true
    }
}

enum HouseDropPayload {
    /// 读出拖动内容（异步），回到主线程再交给 handler
    static func load(_ providers: [NSItemProvider], _ handler: @escaping @MainActor (String?) -> Void) {
        let box = HandlerBox(handler)
        guard let p = providers.first else { Task { @MainActor in box.f(nil) }; return }
        _ = p.loadObject(ofClass: NSString.self) { obj, _ in
            let s = (obj as? NSString).map { String($0) }
            Task { @MainActor in box.f(s) }
        }
    }
    private final class HandlerBox: @unchecked Sendable {
        let f: @MainActor (String?) -> Void
        init(_ f: @escaping @MainActor (String?) -> Void) { self.f = f }
    }
}

// MARK: - 右侧面板

struct HouseEditPanel: View {
    @EnvironmentObject var m: AppModel
    @Binding var selection: HouseSelection?
    var edit = HouseEditContext(selected: nil, onSelect: { _ in })
    @State private var dropTargeted = false

    private var clearingDrag: HouseDragSession? { edit.drag.session.flatMap { $0.from != nil ? $0 : nil } }

    var body: some View {
        let resolved = m.houseResolved
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let sel = selection, let room = resolved.rooms.first(where: { $0.key == sel.roomKey }) {
                    spotCard(sel, room: room)
                }
                ForEach(resolved.rooms, id: \.key) { room in roomSection(room, hidden: Set(resolved.hidden)) }
                roomMapping(resolved)
                Text(storageNote).font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
        }
        // 从剖面上拖回面板 = 移出这个位置
        .onDrop(of: [.plainText], isTargeted: $dropTargeted) { providers in
            guard edit.currentSession()?.from != nil else { return false }
            let perform = edit.perform
            HouseDropPayload.load(providers) { perform(nil, $0) }
            return true
        }
        .overlay {
            if let s = clearingDrag, dropTargeted || edit.drag.showPreview && edit.drag.hover == nil {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.12))
                    RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    Label(L("松手：把「", "Release to take “") + s.name + L("」移出小屋位置", "” off its spot"), systemImage: "tray.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.accentColor)
                }
                .padding(8)
                .allowsHitTesting(false)
            }
        }
    }

    private var home: String { m.houseHomeKey }
    private func override(_ did: String) -> HouseDeviceOverride? { m.house.homes[home]?.devices[did] }

    private func roomDevices(_ key: String) -> [Device] {
        m.devices.filter { (m.currentHomeId == nil || $0.homeId == m.currentHomeId) && HouseResolver.roomKey($0) == key && HouseCatalog.showable($0.category) }
            .sorted { m.displayName($0).localizedStandardCompare(m.displayName($1)) == .orderedAscending }
    }

    // 选中的位置：这里放哪台设备
    @ViewBuilder
    private func spotCard(_ sel: HouseSelection, room: ResolvedHouseRoom) -> some View {
        let occupant = room.devices.first { $0.spot == sel.spot }
        let fixture: HouseFixture? = { if case .fixture(let id) = sel.spot { return HouseCatalog.fixture(room.module, id) }; return nil }()
        let candidates = room.devices.filter { d in fixture.map { $0.accepts(d.category) } ?? true }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: fixture == nil ? "square.dashed" : "lamp.floor").foregroundStyle(Color.accentColor)
                Text("\(room.title) · \(fixture.map { HouseFixtureNames.title($0.id) } ?? L("徽章位", "Badge spot"))")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button { selection = nil } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
            if candidates.isEmpty {
                Text(L("这个房间里没有能放在这里的设备", "No device in this room fits here")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(candidates, id: \.did) { d in
                let here = occupant?.did == d.did
                Button {
                    m.houseEdit(L("放置 ", "Place ") + d.name) { $0.setDevice(home: home, did: d.did) { $0.place = fixture.map { "fixture:" + $0.id } ?? HouseEditing.placeValue(sel.spot) } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: here ? "largecircle.fill.circle" : "circle").foregroundStyle(here ? Color.accentColor : .secondary)
                        Image(systemName: HouseChipStyle.icon(d.category)).foregroundStyle(HouseChipStyle.tint(d.category)).frame(width: 16)
                        Text(d.name).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                        if !here { Text(HouseFixtureNames.spot(d.spot)).font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if let o = occupant {
                Button(fixture == nil ? L("移出徽章位（只留在按钮行）", "Remove badge (button row only)") : L("清空这个位置（设备改用徽章）", "Empty this spot (device becomes a badge)")) {
                    m.houseEdit(L("移出 ", "Remove ") + o.name) { $0.setDevice(home: home, did: o.did) { $0.place = fixture == nil ? "none" : "badge" } }
                }
                .buttonStyle(.link).font(.system(size: 11))
            }
        }
        .padding(12)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Color.accentColor.opacity(0.35)))
    }

    // 每个进了小屋的房间：设备 + 显示开关 + 位置菜单
    private func roomSection(_ room: ResolvedHouseRoom, hidden: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(room.title).font(.system(size: 12, weight: .semibold))
                if room.title != room.module.title {
                    Text("→ " + room.module.title).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 2)
            ForEach(roomDevices(room.key), id: \.did) { d in
                deviceRow(d, resolved: room.devices.first { $0.did == d.did }, module: room.module, hidden: hidden.contains(d.did))
            }
        }
    }

    private func deviceRow(_ d: Device, resolved r: ResolvedHouseDevice?, module: HouseModule, hidden: Bool) -> some View {
        let o = override(d.did)
        let fixtures = HouseCatalog.fixtures(module).filter { $0.accepts(d.category) }
        return HStack(spacing: 8) {
            Button {
                m.houseEdit((hidden ? L("显示 ", "Show ") : L("隐藏 ", "Hide ")) + m.displayName(d)) { $0.setDevice(home: home, did: d.did) { $0.visible = hidden } }
            } label: {
                Image(systemName: hidden ? "eye.slash" : "eye").font(.system(size: 12))
                    .foregroundStyle(hidden ? Color.secondary : Color.accentColor).frame(width: 20)
            }
            .buttonStyle(.plain)
            .help(hidden ? L("在小屋里显示", "Show in house") : L("在小屋里隐藏（设备列表不受影响）", "Hide in house (device list unaffected)"))
            Image(systemName: HouseChipStyle.icon(d.category)).font(.system(size: 11))
                .foregroundStyle(hidden ? Color.secondary : HouseChipStyle.tint(d.category)).frame(width: 16)
            Text(m.displayName(d)).font(.system(size: 12)).lineLimit(1).foregroundStyle(hidden ? .secondary : .primary)
            Spacer(minLength: 4)
            Menu {
                Button(L("自动", "Automatic")) { m.houseEdit(L("放置 ", "Place ") + m.displayName(d)) { $0.setDevice(home: home, did: d.did) { $0.place = nil } } }
                Divider()
                ForEach(fixtures, id: \.id) { f in
                    Button(HouseFixtureNames.title(f.id)) { m.houseEdit(L("放置 ", "Place ") + m.displayName(d)) { $0.setDevice(home: home, did: d.did) { $0.place = "fixture:" + f.id } } }
                }
                Button(L("徽章", "Badge")) { m.houseEdit(L("放置 ", "Place ") + m.displayName(d)) { $0.setDevice(home: home, did: d.did) { $0.place = "badge" } } }
                Button(L("只在按钮行", "Button row only")) { m.houseEdit(L("放置 ", "Place ") + m.displayName(d)) { $0.setDevice(home: home, did: d.did) { $0.place = "none" } } }
                if o != nil {
                    Divider()
                    Button(L("恢复自动（这台设备）", "Reset this device")) { m.houseEdit(L("恢复自动 ", "Reset ") + m.displayName(d)) { $0.reset(home: home, did: d.did) } }
                }
            } label: {
                HStack(spacing: 3) {
                    if r?.pinned == true || o?.visible != nil { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    Text(hidden ? L("已隐藏", "Hidden") : HouseFixtureNames.spot(r?.spot)).font(.system(size: 11))
                }
            }
            .menuStyle(.borderlessButton).fixedSize()
            .foregroundStyle(.secondary)
            .disabled(hidden)
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(isSelected(r) ? Color.accentColor.opacity(0.12) : Theme.tile.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            if edit.drag.session?.did == d.did {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            }
        }
        .opacity(edit.drag.session?.did == d.did ? 0.55 : 1)
        .contentShape(Rectangle())
        .onDrag { edit.beginDrag(d.did, nil) } preview: { HouseDragChip(name: m.displayName(d), category: d.category) }
        .help(L("拖到剖面上的虚线框放置", "Drag onto a dashed spot in the house to place it"))
    }

    private func isSelected(_ r: ResolvedHouseDevice?) -> Bool {
        guard let s = selection, let r, let spot = r.spot else { return false }
        return s.spot == spot && m.houseResolved.rooms.contains { $0.key == s.roomKey && $0.devices.contains { $0.did == r.did } }
    }

    // 简化版房间映射：米家房间 → 小屋模块
    private func roomMapping(_ resolved: ResolvedHouse) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("房间", "Rooms")).font(.system(size: 12, weight: .semibold))
            Text(m.houseLayoutCells != nil
                 ? L("用的是自定义布局：这里的菜单直接改布局（换模块、加进空位、移出）；位置在「房间布局」里拖。", "Using a custom layout: these menus edit it directly (change type, add to a free cell, take out). Move rooms around in Room layout.")
                 : L("每个小屋房间放一个米家房间，最多 4 个；想要厨房、卫生间、阳台或别的摆法，用「房间布局」。", "Each house room shows one Mijia room, up to 4. For a kitchen, bathroom, balcony or another arrangement, use Room layout."))
                .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ForEach(resolved.rooms, id: \.key) { r in mappingRow(key: r.key, title: r.title, status: r.module.title, active: true) }
            ForEach(resolved.excluded) { e in mappingRow(key: e.key, title: e.title, status: reason(e), active: false) }
        }
        .padding(.top, 4)
    }

    private func reason(_ e: ExcludedHouseRoom) -> String {
        switch e.reason {
        case .noArt: return e.module == .generic ? L("没有对应模块", "No matching room") : e.module.title + L(" · 暂无素材", " · no art yet")
        case .spotTaken: return e.module.title + L(" · 已被占用", " · taken")
        case .excluded: return L("不放进小屋", "Not in house")
        case .unassigned: return L("未分配房间", "No room")
        case .notInLayout: return L("不在布局里", "Not in layout")
        }
    }

    private func mappingRow(key: String, title: String, status: String, active: Bool) -> some View {
        let current = m.house.homes[home]?.rooms[key]?.module
        return HStack(spacing: 8) {
            Circle().fill(active ? Color.green : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
            Text(title).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 4)
            if let layout = m.houseLayoutCells {
                layoutMenu(layout: layout, key: key, title: title, status: status)
            } else {
            Menu {
                Button(L("自动", "Automatic")) { m.houseEdit(L("房间 ", "Room ") + title) { $0.setRoom(home: home, key: key, module: nil) } }
                Divider()
                ForEach(HouseCatalog.artModules, id: \.self) { mod in
                    Button(mod.title) { m.houseEdit(L("房间 ", "Room ") + title) { $0.setRoom(home: home, key: key, module: mod.rawValue) } }
                }
                Divider()
                Button(L("不放进小屋", "Not in house")) { m.houseEdit(L("房间 ", "Room ") + title) { $0.setRoom(home: home, key: key, module: "none") } }
            } label: {
                HStack(spacing: 3) {
                    if current != nil { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    Text(status).font(.system(size: 11))
                }
            }
            .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary)
            .disabled(key.isEmpty)
            }
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(Theme.tile.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    /// 自定义布局时的房间菜单：直接改布局里这个房间的模块（换模块 / 加进布局 / 移出），和「房间布局」标签同一份数据
    private func layoutMenu(layout: [HouseLayoutCell], key: String, title: String, status: String) -> some View {
        let cell = layout.first { $0.room == key }
        func apply(_ module: String?) {
            guard let next = HouseLayoutSolver.setModule(layout, room: key, module: module) else { return }
            m.houseEdit(L("房间 ", "Room ") + title) { $0.setLayout(home: home, layout: next.isEmpty ? nil : next) }
        }
        let auto = HouseModule.isEntryFoyer(roomName: title) ? HouseModule.generic : HouseModule.from(roomName: title)
        return Menu {
            Button(L("自动（", "Automatic (") + auto.title + L("）", ")")) { apply(auto.rawValue) }
                .disabled(HouseLayoutSolver.setModule(layout, room: key, module: auto.rawValue) == nil)
            Divider()
            ForEach(HouseModule.allCases, id: \.self) { mod in
                Button {
                    apply(mod.rawValue)
                } label: {
                    if cell?.module == mod.rawValue { Label(mod.title, systemImage: "checkmark") } else { Text(mod.title) }
                }
                .disabled(HouseLayoutSolver.setModule(layout, room: key, module: mod.rawValue) == nil)
            }
            Divider()
            Button(L("不放进小屋", "Not in house")) { apply(nil) }.disabled(cell == nil)
        } label: {
            Text(cell.flatMap { HouseModule(rawValue: $0.module)?.title } ?? status).font(.system(size: 11))
        }
        .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary)
        .disabled(key.isEmpty)
    }

    private var storageNote: String {
        if m.mock { return L("演示数据：改动只保存在内存里。", "Demo data: changes stay in memory.") }
        let loc = HouseStore.location
        let where_: String
        switch loc.mode {
        case .icloud: where_ = L("iCloud 云盘 / MijiaBar / house.json（多台 Mac 同步）", "iCloud Drive / MijiaBar / house.json (synced across Macs)")
        case .local: where_ = L("本机 Application Support / MijiaBar / house.json", "This Mac: Application Support / MijiaBar / house.json")
        case .folder: where_ = (loc.path ?? "") + "/house.json"
        }
        return L("保存在 ", "Saved in ") + where_ + L("；也可以用 mijiabar house 命令或 MCP 修改。", ". Also editable with `mijiabar house` or MCP.")
    }
}

extension AppModel {
    func houseResetAll() { houseEdit(L("恢复自动", "Reset to automatic")) { $0.reset(home: houseHomeKey) } }

    /// 一次可撤销的编辑：立即写 house.json，记下改动前后的值
    func houseEdit(_ label: String, _ f: (inout HouseFile) -> Void) {
        let home = houseHomeKey
        var edit: HouseEdit?
        let ok = updateHouse { file in
            let before = file
            f(&file)
            edit = HouseEdit.diff(label: label, home: home, before: before, after: file)
        }
        if ok { houseUndo.record(edit) }
    }

    func houseUndoStep(redo: Bool) {
        var stack = houseUndo
        var out = HouseUndoStack.Outcome.empty
        guard updateHouse({ out = redo ? stack.redo(&$0) : stack.undo(&$0) }) else { return }
        houseUndo = stack
        if out == .stale {
            houseFlash(L("house.json 在别处被改过（命令行、Agent 或其他 Mac），撤销记录已清空", "house.json changed elsewhere (CLI, agent or another Mac); undo history cleared"))
        }
    }

    /// HouseWindow 里的短提示（拖放被拒绝、撤销记录作废……）
    func houseFlash(_ s: String) {
        houseNotice = s
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            if self.houseNotice == s { self.houseNotice = nil }
        }
    }

    func houseDragSource(_ did: String, resolved: ResolvedHouse) -> HouseDragSource? {
        guard let d = device(did) else { return nil }
        return HouseDragSource(did: did, category: d.category, roomKey: HouseResolver.roomKey(d), hiddenInHouse: resolved.hidden.contains(did))
    }
}

// MARK: - 截图（`MijiaBar --house-window-snapshot <dir>`，演示数据）

extension Snapshot {
    static func houseWindow(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let m = AppModel(mock: true)
        // 演示覆盖项：摄像头只在小屋里隐藏（设备列表里还在）
        let home = m.houseHomeKey
        m.houseEdit("hide camera") { $0.setDevice(home: home, did: "d10") { $0.visible = false } }
        let sel = HouseSelection(roomKey: m.houseRooms.first { $0.module == .living }?.key ?? "", spot: .fixture("floor_lamp"))
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: name)
            render(HousePilotHost().environmentObject(m), out.appendingPathComponent("house-window-\(suffix).png"), size: HouseWindow.normalSize)
            render(HousePilotHost(editing: true, selection: sel).environmentObject(m), out.appendingPathComponent("house-edit-\(suffix).png"), size: HouseWindow.editSize)
        }
        // 拖动中（截图画不到系统拖动图像，用 showPreview 自己画）：落地灯拖到壁灯位 = 可以放；空调拖到落地灯位 = 拒绝
        let living = m.houseRooms.first { $0.module == .living }?.key ?? ""
        let valid = HouseDragState(session: HouseDragSession(did: "d3", name: m.device("d3").map(m.displayName) ?? "", category: .light,
                                                             from: HouseSelection(roomKey: living, spot: .fixture("floor_lamp"))),
                                   hover: HouseSelection(roomKey: living, spot: .fixture("sconce")), inScene: true, showPreview: true)
        let invalid = HouseDragState(session: HouseDragSession(did: "d1", name: m.device("d1").map(m.displayName) ?? "", category: .ac, from: nil),
                                     hover: HouseSelection(roomKey: living, spot: .fixture("floor_lamp")), inScene: true, showPreview: true)
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: name)
            render(HousePilotHost(editing: true, drag: valid).environmentObject(m), out.appendingPathComponent("house-drag-valid-\(suffix).png"), size: HouseWindow.editSize)
            render(HousePilotHost(editing: true, drag: invalid).environmentObject(m), out.appendingPathComponent("house-drag-invalid-\(suffix).png"), size: HouseWindow.editSize)
        }
        // 撤销 / 重做：再做两步，撤销一步，两个按钮都可用
        m.houseEdit(L("放置 ", "Place ") + "d4") { $0.setDevice(home: home, did: "d4") { $0.place = "badge:b3" } }
        m.houseEdit(L("交换 ", "Swap ") + "d3") { HouseEditing.apply([HouseDropChange(did: "d3", place: "fixture:sconce")], to: &$0, home: home) }
        m.houseUndoStep(redo: false)
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: name)
            render(HousePilotHost(editing: true).environmentObject(m), out.appendingPathComponent("house-edit-undo-\(suffix).png"), size: HouseWindow.editSize)
        }
        // 房间布局标签
        // 用解析出来的真实房间 key（标题跟语言走），再加两间没有经典美术的房间（厨房 / 浴室）
        let key = { (mod: HouseModule) in m.houseResolved.rooms.first { $0.module == mod }?.key ?? "name:" + mod.title }
        let mix: [HouseLayoutCell] = [
            .init(room: key(.bedroom), module: "bedroom", col: 0, row: 0),
            .init(room: key(.study), module: "study", col: 1, row: 0),
            .init(room: "name:" + L("卫生间", "Bathroom"), module: "bathroom", col: 2, row: 0),
            .init(room: key(.living), module: "living", col: 0, row: 1),
            .init(room: "name:" + L("厨房", "Kitchen"), module: "kitchen", col: 2, row: 1),
        ]
        m.houseEdit("layout") { $0.setLayout(home: home, layout: mix) }
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: name)
            render(HousePilotHost(editing: true, editTab: .arrange).environmentObject(m), out.appendingPathComponent("house-arrange-\(suffix).png"), size: HouseWindow.editSize)
        }
        // 自定义布局后的小屋本身：模块合成图 + 灯光 / 徽章（查看 + 摆放）
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: name)
            render(HousePilotHost().environmentObject(m), out.appendingPathComponent("house-composed-window-\(suffix).png"), size: HouseWindow.normalSize)
            render(HousePilotHost(editing: true).environmentObject(m), out.appendingPathComponent("house-composed-edit-\(suffix).png"), size: HouseWindow.editSize)
        }
        // Devices 标签的房间菜单在自定义布局下直接改布局：厨房移出，门口（自动 = 门厅模块）加进空出来的格子
        let entry = m.houseResolved.excluded.first { $0.reason == .notInLayout && HouseModule.isEntryFoyer(roomName: $0.title) }
        if var lay = m.house.homes[home]?.layout {
            lay = HouseLayoutSolver.setModule(lay, room: "name:" + L("厨房", "Kitchen"), module: nil) ?? lay
            if let entry { lay = HouseLayoutSolver.setModule(lay, room: entry.key, module: "generic") ?? lay }
            m.houseEdit("menu") { $0.setLayout(home: home, layout: lay) }
        }
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: name)
            render(HousePilotHost(editing: true).environmentObject(m), out.appendingPathComponent("house-composed-menu-\(suffix).png"), size: HouseWindow.editSize)
        }
        exit(0)
    }
}

/// 剖面整体的拖放目标（只在编辑模式挂上）
struct HouseSceneDropModifier: ViewModifier {
    let edit: HouseEditContext?
    let targets: [(sel: HouseSelection, rect: CGRect)]
    let scale: CGFloat
    func body(content: Content) -> some View {
        if let edit {
            content.onDrop(of: [.plainText], delegate: HouseSceneDropDelegate(edit: edit, targets: targets, scale: scale))
        } else {
            content
        }
    }
}
