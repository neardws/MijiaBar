import AppKit
import MijiaCore
import SwiftUI

// 小屋编辑模式（HouseWindow「编辑」）：在剖面上画出灯具位 / 徽章位，右侧面板按房间列出设备，
// 改动立即写进 house.json（MijiaCore/HouseStore），CLI / Agent / 其他 Mac 看到的是同一份配置。

struct HouseSelection: Equatable {
    let roomKey: String
    let spot: HouseSpot
}

struct HouseEditContext {
    var selected: HouseSelection?
    var onSelect: (HouseSelection) -> Void
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
        case "monitor": return L("显示器位", "Monitor")
        case "entry_light": return L("玄关灯位", "Entry light")
        default: return id
        }
    }

    /// 书房的显示器位和吸顶灯位挨得近，标签放到框上方，避免和徽章重叠
    static let labelAbove: Set<String> = ["monitor", "ceiling"]

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

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(module.lights) { light in
                if let r = rect(light) {
                    let d = light.matchedDevice(in: room.devices)
                    let sel = HouseSelection(roomKey: room.key, spot: .fixture(light.id))
                    slot(rect: r, round: true, device: d, label: d?.name ?? HouseFixtureNames.title(light.id),
                         labelAbove: HouseFixtureNames.labelAbove.contains(light.id), selected: edit.selected == sel) { edit.onSelect(sel) }
                }
            }
            ForEach(Array(HouseCatalog.badgeIds(room.module).enumerated()), id: \.offset) { i, id in
                if let p = module.badges?[safe: i], p.count >= 2 {
                    let d = room.devices.first { $0.spot == .badge(id) }
                    let sel = HouseSelection(roomKey: room.key, spot: .badge(id))
                    slot(rect: CGRect(x: p[0] - 26, y: p[1] - 44, width: 52, height: 52), round: false, device: d,
                         label: nil, selected: edit.selected == sel) { edit.onSelect(sel) }
                }
            }
        }
        .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
    }

    private func rect(_ l: HouseLightSpec) -> CGRect? {
        if let poly = l.corePolygon, !poly.isEmpty {
            let xs = poly.map { $0[0] }, ys = poly.map { $0[1] }
            let r = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            return r.insetBy(dx: min(0, (r.width - 44) / 2), dy: min(0, (r.height - 40) / 2)).insetBy(dx: -8, dy: -8)
        }
        if case .ellipse(let cx, let cy, let rx, let ry)? = l.reveal {
            _ = (rx, ry); return CGRect(x: cx - 32, y: cy - 20, width: 64, height: 40)   // 没有灯具本体（吸顶灯 / 玄关灯）：放在光斑中心
        }
        return nil
    }

    @ViewBuilder
    private func slot(rect r: CGRect, round: Bool, device: HouseDevice?, label: String?, labelAbove: Bool = false, selected: Bool, tap: @escaping () -> Void) -> some View {
        let color: Color = selected ? .accentColor : (device != nil ? Color(red: 1, green: 0.84, blue: 0.4) : .white)
        let shape = RoundedRectangle(cornerRadius: round ? min(r.width, r.height) / 2 : 10, style: .continuous)
        ZStack {
            shape.fill(color.opacity(selected ? 0.22 : 0.06))
            shape.strokeBorder(color.opacity(selected ? 1 : 0.85), style: StrokeStyle(lineWidth: selected ? 3.5 : 2, dash: selected ? [] : [7, 5]))
            if device == nil {
                Image(systemName: "plus").font(.system(size: 16, weight: .bold)).foregroundStyle(color.opacity(0.9))
                    .shadow(color: .black.opacity(0.6), radius: 2)
            }
        }
        .frame(width: r.width, height: r.height)
        .contentShape(shape)
        .onTapGesture(perform: tap)
        .position(x: r.midX, y: r.midY)
        if let label, round {
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
    }
}

// MARK: - 右侧面板

struct HouseEditPanel: View {
    @EnvironmentObject var m: AppModel
    @Binding var selection: HouseSelection?

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
                    m.updateHouse { $0.setDevice(home: home, did: d.did) { $0.place = fixture.map { "fixture:" + $0.id } ?? "badge" } }
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
                    m.updateHouse { $0.setDevice(home: home, did: o.did) { $0.place = fixture == nil ? "none" : "badge" } }
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
                m.updateHouse { $0.setDevice(home: home, did: d.did) { $0.visible = hidden } }
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
                Button(L("自动", "Automatic")) { m.updateHouse { $0.setDevice(home: home, did: d.did) { $0.place = nil } } }
                Divider()
                ForEach(fixtures, id: \.id) { f in
                    Button(HouseFixtureNames.title(f.id)) { m.updateHouse { $0.setDevice(home: home, did: d.did) { $0.place = "fixture:" + f.id } } }
                }
                Button(L("徽章", "Badge")) { m.updateHouse { $0.setDevice(home: home, did: d.did) { $0.place = "badge" } } }
                Button(L("只在按钮行", "Button row only")) { m.updateHouse { $0.setDevice(home: home, did: d.did) { $0.place = "none" } } }
                if o != nil {
                    Divider()
                    Button(L("恢复自动（这台设备）", "Reset this device")) { m.updateHouse { $0.reset(home: home, did: d.did) } }
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
    }

    private func isSelected(_ r: ResolvedHouseDevice?) -> Bool {
        guard let s = selection, let r, let spot = r.spot else { return false }
        return s.spot == spot && m.houseResolved.rooms.contains { $0.key == s.roomKey && $0.devices.contains { $0.did == r.did } }
    }

    // 简化版房间映射：米家房间 → 小屋模块
    private func roomMapping(_ resolved: ResolvedHouse) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("房间", "Rooms")).font(.system(size: 12, weight: .semibold))
            Text(L("每个小屋房间放一个米家房间，最多 4 个（厨房、卫生间、阳台的素材之后加）。", "Each house room shows one Mijia room (kitchen, bathroom and balcony art come later)."))
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
        }
    }

    private func mappingRow(key: String, title: String, status: String, active: Bool) -> some View {
        let current = m.house.homes[home]?.rooms[key]?.module
        return HStack(spacing: 8) {
            Circle().fill(active ? Color.green : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
            Text(title).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 4)
            Menu {
                Button(L("自动", "Automatic")) { m.updateHouse { $0.setRoom(home: home, key: key, module: nil) } }
                Divider()
                ForEach(HouseCatalog.artModules, id: \.self) { mod in
                    Button(mod.title) { m.updateHouse { $0.setRoom(home: home, key: key, module: mod.rawValue) } }
                }
                Divider()
                Button(L("不放进小屋", "Not in house")) { m.updateHouse { $0.setRoom(home: home, key: key, module: "none") } }
            } label: {
                HStack(spacing: 3) {
                    if current != nil { Image(systemName: "pin.fill").font(.system(size: 8)) }
                    Text(status).font(.system(size: 11))
                }
            }
            .menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary)
            .disabled(key.isEmpty)
        }
        .padding(.vertical, 3).padding(.horizontal, 6)
        .background(Theme.tile.opacity(0.6), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
    func houseResetAll() { updateHouse { $0.reset(home: houseHomeKey) } }
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
        m.updateHouse { $0.setDevice(home: home, did: "d10") { $0.visible = false } }
        let sel = HouseSelection(roomKey: m.houseRooms.first { $0.module == .living }?.key ?? "", spot: .fixture("floor_lamp"))
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: name)
            render(HousePilotHost().environmentObject(m), out.appendingPathComponent("house-window-\(suffix).png"), size: HouseWindow.normalSize)
            render(HousePilotHost(editing: true, selection: sel).environmentObject(m), out.appendingPathComponent("house-edit-\(suffix).png"), size: HouseWindow.editSize)
        }
        exit(0)
    }
}
