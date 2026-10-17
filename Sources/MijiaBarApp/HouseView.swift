import SwiftUI
import AppKit
import MijiaCore

// MARK: - 锚点 / 素材

struct HouseAnchorRect: Codable {
    let x, y, w, h: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

struct HouseAnchorPoint: Codable {
    let x, y: Double
    var point: CGPoint { CGPoint(x: x, y: y) }
}

struct HouseAnchorFile: Codable {
    let size: [Double]
    var lamps: [HouseAnchorPoint]?
    var tv: HouseAnchorRect?
    var window: HouseAnchorRect?
    var ac: HouseAnchorRect?
    var artSize: CGSize { CGSize(width: size[0], height: size[1]) }
}

enum HouseAssets {
    static func baseImage(_ module: HouseModule) -> NSImage? {
        let name = "\(module.assetPrefix)-base"
        let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "House")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    static func anchors(_ module: HouseModule) -> HouseAnchorFile? {
        let name = "\(module.assetPrefix)-anchors"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "House")
            ?? Bundle.module.url(forResource: name, withExtension: "json"),
            let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HouseAnchorFile.self, from: data)
    }
}

// MARK: - 灯光状态

struct RoomModuleLighting: Equatable {
    var lampLevels: [Double]
    var tv: Double
    var ac: Double
    var cozy: Double

    static let demoNight = RoomModuleLighting(lampLevels: [1, 0.6], tv: 1, ac: 1, cozy: 1)
    static let allOff = RoomModuleLighting(lampLevels: [0, 0], tv: 0, ac: 0, cozy: 0.1)

    static func from(placed: [(Device, HouseSlot)], isOn: (Device) -> Bool?) -> RoomModuleLighting {
        var lamps = [0.0, 0.0]
        var tv = 0.0, ac = 0.0
        for (d, slot) in placed {
            guard d.isOnline, isOn(d) == true else { continue }
            switch slot.kind {
            case .light where slot.index < lamps.count: lamps[slot.index] = 1
            case .tv: tv = 1
            case .ac: ac = 1
            default: break
            }
        }
        let cozy = min(1, 0.12 + lamps.reduce(0, +) * 0.28 + tv * 0.32 + ac * 0.22)
        return RoomModuleLighting(lampLevels: lamps, tv: tv, ac: ac, cozy: cozy)
    }
}

struct HouseDevice: Equatable {
    let did: String, name: String, kind: HouseSlotKind, slot: Int, on: Bool
}

struct HouseRoom: Identifiable, Equatable {
    var id: String { key }
    let key: String, title: String, module: HouseModule
    let devices: [HouseDevice], overflow: Int
    let lighting: RoomModuleLighting
}

extension AppModel {
    func housePower(_ d: Device) -> Bool? { powerInfo(d)?.isOn }

    var houseRooms: [HouseRoom] {
        let hid = currentHomeId ?? ""
        let inHome = devices.filter { currentHomeId == nil || $0.homeId == currentHomeId }
        let groups = Dictionary(grouping: inHome) { $0.roomName ?? "" }
        return prefs.orderedRooms(home: hid, Array(groups.keys)).compactMap { k in
            let mod = HouseModule.from(roomName: k)
            if mod == .generic, !HouseModule.isEntryFoyer(roomName: k) { return nil }
            let list = prefs.orderedDevices(home: hid, key: k, groups[k] ?? [])
            let r = HouseLayout.assign(list, in: mod)
            let ds = r.placed.map { d, s in
                HouseDevice(did: d.did, name: displayName(d), kind: s.kind, slot: s.index, on: d.isOnline && (housePower(d) == true))
            }
            let light = RoomModuleLighting.from(placed: r.placed, isOn: { housePower($0) })
            return HouseRoom(key: k, title: k.isEmpty ? L("未分配房间", "Unassigned") : k, module: mod, devices: ds, overflow: r.overflow.count, lighting: light)
        }
    }

    var livingRoomLighting: LivingRoomLighting {
        let l = houseRooms.first { $0.module == .living }?.lighting
        return LivingRoomLighting(lamp: l?.lampLevels.first ?? 0, tv: l?.tv ?? 0, cozy: l?.cozy ?? 0.1)
    }
}

/// 旧 API：单客厅灯光（截图 / 兼容）
struct LivingRoomLighting: Equatable {
    var lamp: Double, tv: Double, cozy: Double
    static let nightOn = LivingRoomLighting(lamp: 1, tv: 1, cozy: 1)
    static let allOff = LivingRoomLighting(lamp: 0, tv: 0, cozy: 0.1)
}

// MARK: - 单房间瓦片

struct HouseRoomTileView: View {
    let module: HouseModule
    let lighting: RoomModuleLighting
    var scale: CGFloat = 1

    private var meta: HouseAnchorFile? { HouseAssets.anchors(module) }
    private var artSize: CGSize { meta?.artSize ?? CGSize(width: 640, height: 359) }

    var body: some View {
        ZStack {
            baseArt
            nightDim
            windowMoon
            acGlow
            tvGlow
            lampGlows
            warmWash
        }
        .frame(width: artSize.width, height: artSize.height)
        .scaleEffect(scale)
        .frame(width: artSize.width * scale, height: artSize.height * scale)
    }

    @ViewBuilder private var baseArt: some View {
        if let img = HouseAssets.baseImage(module) {
            Image(nsImage: img).interpolation(.none).resizable().aspectRatio(contentMode: .fill)
        } else {
            Theme.bg2.overlay(Text(module.rawValue).font(.caption2).foregroundStyle(.tertiary))
        }
    }

    private var nightDim: some View {
        Color.black.opacity((1 - lighting.cozy) * 0.78).blendMode(.multiply).allowsHitTesting(false)
    }

    @ViewBuilder private var windowMoon: some View {
        if let r = meta?.window?.cgRect {
            let k = 0.3 + lighting.cozy * 0.35
            Ellipse()
                .fill(RadialGradient(colors: [Color(red: 0.55, green: 0.72, blue: 0.9).opacity(0.5 * k), .clear], center: .center, startRadius: 0, endRadius: 110))
                .frame(width: r.width * artSize.width, height: r.height * artSize.height * 0.75)
                .position(x: r.midX * artSize.width, y: r.midY * artSize.height)
                .blendMode(.screen).opacity(k).allowsHitTesting(false)
        }
    }

    @ViewBuilder private var acGlow: some View {
        if lighting.ac > 0, let r = meta?.ac?.cgRect {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Theme.cool.opacity(0.9), Theme.cool.opacity(0.5)], startPoint: .top, endPoint: .bottom))
                Glow(Theme.cool, 0.55, diameter: 48, softness: 36)
            }
            .frame(width: r.width * artSize.width, height: r.height * artSize.height)
            .position(x: r.midX * artSize.width, y: r.midY * artSize.height)
            .blendMode(.screen).opacity(lighting.ac).allowsHitTesting(false)
        }
    }

    @ViewBuilder private var tvGlow: some View {
        if lighting.tv > 0, let r = meta?.tv?.cgRect {
            ZStack {
                Rectangle()
                    .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.58, blue: 0.98), Color(red: 0.12, green: 0.38, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .opacity(0.88)
                Glow(Theme.cool, 0.6, diameter: 72, softness: 42)
            }
            .frame(width: r.width * artSize.width, height: r.height * artSize.height)
            .position(x: r.midX * artSize.width, y: r.midY * artSize.height)
            .blendMode(.screen).opacity(lighting.tv).allowsHitTesting(false)
        }
    }

    @ViewBuilder private var lampGlows: some View {
        let lamps = meta?.lamps ?? []
        ForEach(lamps.indices, id: \.self) { i in
            let k = i < lighting.lampLevels.count ? lighting.lampLevels[i] : 0
            if k > 0 {
                let p = lamps[i].point
                ZStack {
                    Glow(Color(red: 1, green: 0.78, blue: 0.42), 0.75 * k, diameter: 56, softness: 38)
                    Glow(Color(red: 1, green: 0.9, blue: 0.65), 0.5 * k, diameter: 200, softness: 64)
                }
                .position(x: p.x * artSize.width, y: p.y * artSize.height)
                .blendMode(.screen).opacity(k).allowsHitTesting(false)
            }
        }
    }

    private var warmWash: some View {
        let k = max(lighting.lampLevels.max() ?? 0, lighting.tv * 0.65, lighting.ac * 0.4)
        return LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0.38).opacity(0.4 * k), .clear], startPoint: .bottom, endPoint: .top)
            .frame(height: artSize.height * 0.5).frame(maxHeight: .infinity, alignment: .bottom)
            .blendMode(.screen).allowsHitTesting(false)
    }
}

// MARK: - 整栋小屋

struct HouseFullView: View {
    var rooms: [HouseRoom]
    var showChrome = true
    var onToggle: ((String) -> Void)?

    private let tileScale: CGFloat = 0.5
    private let tileW: CGFloat = 640 * 0.5
    private let tileH: CGFloat = 359 * 0.5
    private let cols = 2

    private var rows: Int { max(1, (rooms.count + cols - 1) / cols) }
    private var canvasW: CGFloat { tileW * CGFloat(cols) - 10 }
    private var canvasH: CGFloat { tileH * CGFloat(rows) - CGFloat(max(0, rows - 1)) * 8 }

    var body: some View {
        VStack(spacing: 0) {
            if showChrome { header }
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(red: 0.06, green: 0.07, blue: 0.11))
                if rooms.isEmpty {
                    Text(L("这个家里还没有能放进小屋的房间", "No rooms for the house view yet"))
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ForEach(Array(rooms.enumerated()), id: \.element.id) { i, room in
                    let cell = HouseLayout.cell(i)
                    HouseRoomTileView(module: room.module, lighting: room.lighting, scale: tileScale)
                        .overlay(alignment: .topLeading) {
                            Text(room.title).font(.system(size: 9, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(.black.opacity(0.45), in: Capsule()).foregroundStyle(.white.opacity(0.9))
                                .padding(6)
                        }
                        .offset(x: CGFloat(cell.col) * (tileW - 12) + (cell.row == 1 ? 4 : 0),
                                y: CGFloat(cell.row) * (tileH - 10))
                        .zIndex(Double(i))
                }
            }
            .frame(width: canvasW, height: canvasH)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
            if showChrome, let onToggle { deviceChips(onToggle) }
        }
        .padding(showChrome ? 12 : 0)
        .background(showChrome ? Theme.bg : .clear)
    }

    private var header: some View {
        HStack {
            Text(L("小屋", "House")).font(.system(size: 15, weight: .semibold))
            Spacer()
            let on = rooms.contains { $0.lighting.cozy > 0.35 }
            HStack(spacing: 4) {
                Circle().fill(on ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                Text(on ? L("夜灯已开", "Lights on") : L("已关灯", "Lights off")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.tile, in: Capsule())
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private func deviceChips(_ onToggle: (String) -> Void) -> some View {
        let chips = rooms.flatMap(\.devices).filter { $0.kind != .ac || $0.on }
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.did) { d in
                        HouseTapChip(icon: icon(d.kind), label: d.name, on: d.on, tint: tint(d.kind)) { onToggle(d.did) }
                    }
                }.padding(.top, 10)
            }
        }
    }

    private func icon(_ k: HouseSlotKind) -> String {
        switch k { case .light: return "lightbulb.fill"; case .tv: return "tv.fill"; case .ac: return "air.conditioner.horizontal" }
    }
    private func tint(_ k: HouseSlotKind) -> Color {
        switch k { case .light: return .yellow; case .tv: return .indigo; case .ac: return Theme.cool }
    }
}

struct LivingRoomHouseView: View {
    var lighting: LivingRoomLighting
    var showChrome = true
    var onToggleLamp: (() -> Void)?
    var onToggleTV: (() -> Void)?

    var body: some View {
        let rl = RoomModuleLighting(lampLevels: [lighting.lamp], tv: lighting.tv, ac: 0, cozy: lighting.cozy)
        VStack(spacing: 0) {
            if showChrome {
                HStack {
                    Text(L("客厅小屋", "Living room")).font(.system(size: 15, weight: .semibold))
                    Spacer()
                }.padding(.bottom, 8)
            }
            HouseRoomTileView(module: .living, lighting: rl, scale: showChrome ? 336 / 640 : 1)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke))
            if showChrome {
                HStack(spacing: 8) {
                    if let onToggleLamp { HouseTapChip(icon: "lightbulb.fill", label: L("落地灯", "Floor lamp"), on: lighting.lamp > 0.5, tint: .yellow, action: onToggleLamp) }
                    if let onToggleTV { HouseTapChip(icon: "tv.fill", label: L("电视", "TV"), on: lighting.tv > 0.5, tint: .indigo, action: onToggleTV) }
                }.padding(.top, 10)
            }
        }
        .padding(showChrome ? 12 : 0)
        .background(showChrome ? Theme.bg : .clear)
    }
}

struct HouseTapChip: View {
    let icon: String, label: String, on: Bool, tint: Color, action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(on ? tint : .secondary)
                Text(label).font(.system(size: 11, weight: .medium)).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? tint.opacity(0.14) : Theme.tile, in: Capsule())
            .overlay(Capsule().stroke(on ? tint.opacity(0.35) : Theme.stroke))
        }
        .buttonStyle(.plain).hoverHighlight()
    }
}

// MARK: - 窗口

@MainActor
enum HouseWindow {
    private static var window: NSWindow?

    static func open(model: AppModel) {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let root = HousePilotHost().environmentObject(model)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = L("小屋", "House")
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: root)
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window?.contentView = nil; window = nil }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct HousePilotHost: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        HouseFullView(rooms: m.houseRooms, onToggle: { did in
            guard let d = m.device(did) else { return }
            withoutAnimation { m.toggle(d) }
        })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CLI

extension Snapshot {
    static func house(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let m = AppModel(mock: true)
        let rooms = m.houseRooms
        let nightRooms = rooms.map { r -> HouseRoom in
            var l = r.lighting
            l.lampLevels = l.lampLevels.map { _ in 1 }
            l.tv = 1
            if r.module == .bedroom { l.ac = 1 }
            l.cozy = 1
            return HouseRoom(key: r.key, title: r.title, module: r.module, devices: r.devices, overflow: r.overflow, lighting: l)
        }
        let offRooms = rooms.map { r in
            HouseRoom(key: r.key, title: r.title, module: r.module, devices: r.devices, overflow: r.overflow, lighting: .allOff)
        }
        self.appearance = NSAppearance(named: .darkAqua)
        for (name, rs) in [("house-night", nightRooms), ("house-off", offRooms)] {
            let rows = max(1, (rs.count + 1) / 2)
            render(HouseFullView(rooms: rs, showChrome: false), out.appendingPathComponent("\(name).png"),
                   size: CGSize(width: 630, height: CGFloat(rows) * 175 + 8))
        }
        render(LivingRoomHouseView(lighting: .nightOn, showChrome: false), out.appendingPathComponent("living-room-night.png"), size: CGSize(width: 640, height: 359))
        render(LivingRoomHouseView(lighting: .allOff, showChrome: false), out.appendingPathComponent("living-room-off.png"), size: CGSize(width: 640, height: 359))
        exit(0)
    }
}
