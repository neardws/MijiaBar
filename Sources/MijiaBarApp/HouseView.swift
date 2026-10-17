import SwiftUI
import AppKit
import MijiaCore

// MARK: - 锚点 / 素材（每房间 module-lights.json，见 docs/house-pilot/ANCHORS.md）

struct HouseAnchorRect: Codable {
    let x, y, w, h: Double
    var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
}

struct HouseAnchorPoint: Codable {
    let x, y: Double
    var point: CGPoint { CGPoint(x: x, y: y) }
}

enum HouseLightKind: String, Codable {
    case lamp, sconce, screen, ac, window, entry
}

struct HouseLightOverlay: Codable {
    let image: String?
    let imageDay: String?
    let imageNight: String?
    let w: Double?
    let h: Double?
}

struct HouseLightAnchor: Codable, Identifiable {
    let id: String
    let kind: HouseLightKind
    let role: String
    let slot: Int?
    let at: HouseAnchorPoint?
    let rect: HouseAnchorRect?
    let overlay: HouseLightOverlay?
}

struct HouseModuleLayout: Codable {
    var size: [Double]?
    let clip: HouseAnchorRect
    var label: HouseAnchorPoint?
    let lights: [HouseLightAnchor]
}

struct HouseModuleLightsFile: Codable {
    let module: String
    let tile: HouseModuleLayout
    let cutaway: HouseModuleLayout
}

struct HouseCutawayModule: Codable {
    let clip: HouseAnchorRect
    let label: HouseAnchorPoint?
    let lights: [HouseLightAnchor]
}

struct HouseCutawaySceneFile: Codable {
    let size: [Double]
    let modules: [String: HouseCutawayModule]
    var artSize: CGSize { CGSize(width: size[0], height: size[1]) }
}

/// 旧 tile 锚点文件（由 sync-house-lights.py 生成）
struct HouseAnchorFile: Codable {
    let size: [Double]?
    var lamps: [HouseAnchorPoint]?
    var tv: HouseAnchorRect?
    var window: HouseAnchorRect?
    var ac: HouseAnchorRect?
    var label: HouseAnchorPoint?
}

/// 剖面底图时段：本地 6:00–18:00 为白天，其余为夜间（与系统时区一致）。
enum HousePhase: Equatable {
    case day, night

    static func from(date: Date = Date(), calendar: Calendar = .current) -> HousePhase {
        let h = calendar.component(.hour, from: date)
        return (6..<18).contains(h) ? .day : .night
    }
}

enum HouseAssets {
    static func cutawayImage(phase: HousePhase) -> NSImage? {
        let name = phase == .day ? "house-cutaway-day-base" : "house-cutaway-night-base"
        let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "House")
            ?? Bundle.module.url(forResource: name, withExtension: "png")
            ?? Bundle.module.url(forResource: "house-cutaway-base", withExtension: "png", subdirectory: "House")
            ?? Bundle.module.url(forResource: "house-cutaway-base", withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    static func cutawayScene() -> HouseCutawaySceneFile? {
        guard let url = Bundle.module.url(forResource: "house-cutaway", withExtension: "json", subdirectory: "House")
            ?? Bundle.module.url(forResource: "house-cutaway", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HouseCutawaySceneFile.self, from: data)
    }

    static func moduleLights(_ module: HouseModule) -> HouseModuleLightsFile? {
        let name = "\(module.assetPrefix)-lights"
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "House")
            ?? Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(HouseModuleLightsFile.self, from: data)
    }

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

    static func glowImage(_ name: String) -> NSImage? {
        let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "House/glows")
            ?? Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "glows")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }

    static func moduleArtSize(_ module: HouseModule, cutaway: Bool = false) -> CGSize {
        if cutaway, let s = cutawayScene()?.artSize { return s }
        if let t = moduleLights(module)?.tile.size, t.count >= 2 { return CGSize(width: t[0], height: t[1]) }
        if let a = anchors(module), let sz = a.size, sz.count >= 2 { return CGSize(width: sz[0], height: sz[1]) }
        return CGSize(width: 640, height: 359)
    }
}

// MARK: - 灯光状态

struct RoomModuleLighting: Equatable {
    var lampLevels: [Double]
    var tv: Double
    var ac: Double
    var cozy: Double

    static let demoNight = RoomModuleLighting(lampLevels: [1, 0.6], tv: 1, ac: 1, cozy: 1)
    static let allOff = RoomModuleLighting(lampLevels: [0, 0], tv: 0, ac: 0, cozy: 0)

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

// MARK: - 叠光层（module lights 表驱动）

struct HouseRoomOverlays: View {
    let layout: HouseModuleLayout
    let lighting: RoomModuleLighting
    let artSize: CGSize
    var phase: HousePhase = .night

    private var roomActive: Double { max(lighting.lampLevels.max() ?? 0, lighting.tv, lighting.ac) }

    var body: some View {
        ZStack {
            ForEach(layout.lights) { light in
                HouseLightGlowLayer(light: light, lighting: lighting, artSize: artSize, phase: phase,
                                    roomActive: roomActive)
            }
        }
        .frame(width: artSize.width, height: artSize.height)
        .mask(clipMask)
        .allowsHitTesting(false)
    }

    private var clipMask: some View {
        let r = layout.clip.cgRect
        return Rectangle()
            .frame(width: r.width * artSize.width, height: r.height * artSize.height)
            .position(x: r.midX * artSize.width, y: r.midY * artSize.height)
    }
}

private struct HouseLightGlowLayer: View {
    let light: HouseLightAnchor
    let lighting: RoomModuleLighting
    let artSize: CGSize
    let phase: HousePhase
    let roomActive: Double

    private var lampK: Double {
        guard light.role == "light", let i = light.slot, i < lighting.lampLevels.count else { return 0 }
        return lighting.lampLevels[i]
    }

    private var strength: Double {
        switch light.kind {
        case .window:
            if phase == .day { return 0.58 + roomActive * 0.22 }
            return roomActive > 0.01 ? min(0.48, 0.14 + roomActive * 0.32) : 0
        case .ac: return lighting.ac
        case .screen: return lighting.tv
        case .lamp, .sconce, .entry: return lampK
        }
    }

    /// 静态 PNG 叠层：设备灯夜间再叠一层 screen，拉开 on/off 对比（锚点不变）。
    private var displayOpacity: Double { min(1, strength) }
    private var deviceBoost: Bool {
        light.kind != .window && strength > 0.35
    }

    var body: some View {
        if displayOpacity > 0.001 {
            ZStack {
                pngOverlay.opacity(displayOpacity)
                if deviceBoost {
                    pngOverlay.opacity(displayOpacity * (phase == .night ? 0.52 : 0.38))
                }
            }
        }
    }

    @ViewBuilder private var pngOverlay: some View {
        if let name = overlayImageName(), let img = HouseAssets.glowImage(name) {
            let (w, h, px, py) = frameOnCanvas()
            Image(nsImage: img)
                .interpolation(.none)
                .resizable()
                .frame(width: w, height: h)
                .position(x: px, y: py)
                .blendMode(.screen)
        }
    }

    private func overlayImageName() -> String? {
        guard let ov = light.overlay else { return nil }
        if light.kind == .window {
            return phase == .day ? (ov.imageDay ?? ov.image) : (ov.imageNight ?? ov.image)
        }
        return ov.image
    }

    private func frameOnCanvas() -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        if let r = light.rect?.cgRect {
            let w = r.width * artSize.width, h = r.height * artSize.height
            return (w, h, r.midX * artSize.width, r.midY * artSize.height)
        }
        let ow = light.overlay?.w ?? 0.1, oh = light.overlay?.h ?? 0.18
        let w = CGFloat(ow) * artSize.width, h = CGFloat(oh) * artSize.height
        let p = light.at?.point ?? .zero
        return (w, h, CGFloat(p.x) * artSize.width, CGFloat(p.y) * artSize.height)
    }
}

// MARK: - 连通剖面整栋

struct HouseCutawaySceneView: View {
    var rooms: [HouseRoom]
    var phase: HousePhase = .from()
    var showLabels = true
    var fitWidth: CGFloat?

    private var cut: HouseCutawaySceneFile? { HouseAssets.cutawayScene() }
    private var artSize: CGSize { cut?.artSize ?? CGSize(width: 960, height: 540) }
    private var deviceCozy: Double { rooms.map(\.lighting.cozy).max() ?? 0 }
    /// 关灯时仍保留可读环境光（白天底图更亮、乘暗更轻）。
    private var ambient: Double {
        let floor = phase == .day ? 0.64 : 0.38
        return min(1, max(deviceCozy, floor))
    }
    private var dimStrength: Double { phase == .day ? 0.38 : 0.52 }
    private var displayScale: CGFloat {
        guard let fitWidth else { return 1 }
        return fitWidth / artSize.width
    }

    var body: some View {
        ZStack {
            baseArt
            Color.black.opacity((1 - ambient) * dimStrength).blendMode(.multiply)
            ForEach(rooms) { room in
                if let layout = cutawayLayout(for: room.module) {
                    HouseRoomOverlays(layout: layout, lighting: room.lighting, artSize: artSize, phase: phase)
                }
            }
            if showLabels {
                ForEach(rooms) { room in
                    if let p = cut?.modules[room.module.rawValue]?.label?.point
                        ?? HouseAssets.moduleLights(room.module)?.cutaway.label?.point {
                        Text(room.title).font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: Capsule()).foregroundStyle(.white.opacity(0.92))
                            .position(x: p.x * artSize.width, y: p.y * artSize.height)
                    }
                }
            }
        }
        .frame(width: artSize.width, height: artSize.height)
        .clipped()
        .scaleEffect(displayScale, anchor: .top)
        .frame(width: artSize.width * displayScale, height: artSize.height * displayScale)
        .clipped()
    }

    @ViewBuilder private var baseArt: some View {
        if let img = HouseAssets.cutawayImage(phase: phase) {
            Image(nsImage: img).interpolation(.none).resizable().aspectRatio(contentMode: .fill)
        } else {
            Theme.bg2.overlay(Text("house-cutaway").font(.caption).foregroundStyle(.tertiary))
        }
    }

    private func cutawayLayout(for module: HouseModule) -> HouseModuleLayout? {
        if let m = cut?.modules[module.rawValue] {
            return HouseModuleLayout(size: [artSize.width, artSize.height], clip: m.clip, label: m.label, lights: m.lights)
        }
        return HouseAssets.moduleLights(module)?.cutaway
    }
}

struct HouseRoomTileView: View {
    let module: HouseModule
    let lighting: RoomModuleLighting
    var scale: CGFloat = 1

    private var tileLayout: HouseModuleLayout? { HouseAssets.moduleLights(module)?.tile }
    private var artSize: CGSize { HouseAssets.moduleArtSize(module) }

    var body: some View {
        ZStack {
            if let img = HouseAssets.baseImage(module) {
                Image(nsImage: img).interpolation(.none).resizable().aspectRatio(contentMode: .fill)
            }
            Color.black.opacity((1 - lighting.cozy) * 0.78).blendMode(.multiply)
            if let tileLayout { HouseRoomOverlays(layout: tileLayout, lighting: lighting, artSize: artSize) }
        }
        .frame(width: artSize.width, height: artSize.height)
        .scaleEffect(scale)
        .frame(width: artSize.width * scale, height: artSize.height * scale)
    }
}

// MARK: - 整栋小屋

struct HouseFullView: View {
    var rooms: [HouseRoom]
    var phase: HousePhase = .from()
    var showChrome = true
    var onToggle: ((String) -> Void)? = nil

    private let sceneWidth: CGFloat = 660

    var body: some View {
        VStack(spacing: 0) {
            if showChrome { header }
            if rooms.isEmpty {
                Text(L("这个家里还没有能放进小屋的房间", "No rooms for the house view yet"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: sceneWidth, height: 200)
            } else {
                HouseCutawaySceneView(rooms: rooms, phase: phase, showLabels: true, fitWidth: showChrome ? sceneWidth : nil)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
            }
            if showChrome, let onToggle { deviceChips(onToggle) }
        }
        .padding(showChrome ? 12 : 0)
        .background(showChrome ? Theme.bg : .clear)
    }

    private var header: some View {
        HStack {
            Text(L("小屋", "House")).font(.system(size: 15, weight: .semibold))
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: phase == .day ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(phase == .day ? Color.orange.opacity(0.85) : Color.indigo.opacity(0.75))
                Text(phase == .day ? L("白天", "Daytime") : L("夜间", "Nighttime"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.tile, in: Capsule())
            let on = rooms.contains { $0.lighting.cozy > 0.35 }
            HStack(spacing: 4) {
                Circle().fill(on ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                Text(on ? L("设备已开", "Devices on") : L("已关灯", "Lights off")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.tile, in: Capsule())
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private func deviceChips(_ onToggle: @escaping (String) -> Void) -> some View {
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
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 560),
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
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            HouseFullView(rooms: m.houseRooms, phase: HousePhase.from(date: ctx.date), onToggle: { did in
                guard let d = m.device(did) else { return }
                withoutAnimation { m.toggle(d) }
            })
        }
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
        let exports: [(String, HousePhase, [HouseRoom])] = [
            ("house-day-on", .day, nightRooms),
            ("house-day-off", .day, offRooms),
            ("house-night-on", .night, nightRooms),
            ("house-night-off", .night, offRooms),
            ("house-night", .night, nightRooms),
            ("house-off", .night, offRooms),
        ]
        for (name, phase, rs) in exports {
            render(HouseCutawaySceneView(rooms: rs, phase: phase, showLabels: false), out.appendingPathComponent("\(name).png"),
                   size: CGSize(width: 960, height: 540))
        }
        render(LivingRoomHouseView(lighting: .nightOn, showChrome: false), out.appendingPathComponent("living-room-night.png"), size: CGSize(width: 640, height: 359))
        render(LivingRoomHouseView(lighting: .allOff, showChrome: false), out.appendingPathComponent("living-room-off.png"), size: CGSize(width: 640, height: 359))
        exit(0)
    }
}
