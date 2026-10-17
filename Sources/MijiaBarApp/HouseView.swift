import SwiftUI
import AppKit
import MijiaCore

// MARK: - 场景定义（Resources/House/house-cutaway.json，见 docs/house-pilot/ANCHORS.md）
//
// 灯光已经烘焙进底图：每个时段一张 unlit、一张 lit（像素完全对齐，只差灯光）。
// 运行时铺 unlit，再按「房间多边形 ∩ 灯具蒙版」淡入 lit，所以光不会和家具错位。
// 坐标均为 960×540 画布像素。

/// 灯具蒙版："room" = 整个房间；[cx, cy, rx, ry] = 羽化椭圆（与 gen-house-baked-lighting.py 一致）
enum HouseReveal: Decodable, Equatable {
    case room
    case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), s == "room" { self = .room; return }
        let v = try c.decode([Double].self)
        guard v.count == 4 else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "reveal must be \"room\" or [cx, cy, rx, ry]")
        }
        self = .ellipse(cx: v[0], cy: v[1], rx: v[2], ry: v[3])
    }
}

struct HouseLightSpec: Decodable, Identifiable {
    let id: String
    let kind: String          // lamp | sconce | ceiling | screen | ac
    let role: String          // light（按 slot）| tv | ac
    let slot: Int?
    let reveal: HouseReveal?
    let shade: [[Double]]?    // 灯罩多边形
    let screen: [[Double]]?   // 屏幕四边形
    let core: [[Double]]?     // 灯具本体（关灯时用 unlit 盖回去）

    /// 关掉时需要用 unlit 盖回去的灯具本体（防止同房间其他灯的 lit 蒙版把它“点亮”）
    var corePolygon: [[Double]]? { core ?? screen ?? shade }

    func strength(_ l: RoomModuleLighting) -> Double {
        switch role {
        case "tv": return l.tv
        case "ac": return l.ac
        default:
            guard let i = slot, i < l.lampLevels.count else { return 0 }
            return l.lampLevels[i]
        }
    }

    /// 与 HouseDevice 的 slot / kind 对应（仅已放进小屋的位置）
    func matchedDevice(in devices: [HouseDevice]) -> HouseDevice? {
        switch role {
        case "tv": return devices.first { $0.kind == .tv && $0.slot == (slot ?? 0) }
        case "ac": return devices.first { $0.kind == .ac && $0.slot == (slot ?? 0) }
        default:
            guard let i = slot else { return nil }
            return devices.first { $0.kind == .light && $0.slot == i }
        }
    }
}

struct HouseCutawayModule: Decodable {
    let label: [Double]?
    let region: [[Double]]
    let lights: [HouseLightSpec]
}

struct HouseCutawaySceneFile: Decodable {
    let size: [Double]
    let modules: [String: HouseCutawayModule]
    var artSize: CGSize { CGSize(width: size[0], height: size[1]) }
}

/// 剖面底图时段：本地 6:00–18:00 为白天，其余为夜间（与系统时区一致）。
enum HousePhase: Equatable {
    case day, night

    static func from(date: Date = Date(), calendar: Calendar = .current) -> HousePhase {
        // 截图用：MIJIABAR_HOUSE_PHASE=day / night 固定白天或夜晚，不随本机时间变
        switch ProcessInfo.processInfo.environment["MIJIABAR_HOUSE_PHASE"] {
        case "day": return .day
        case "night": return .night
        default: break
        }
        let h = calendar.component(.hour, from: date)
        return (6..<18).contains(h) ? .day : .night
    }

    var assetName: String { self == .day ? "day" : "night" }
}

@MainActor
enum HouseAssets {
    private static var images: [String: NSImage] = [:]
    private static var sceneCache: HouseCutawaySceneFile??

    /// 烘焙底图：house-cutaway-{day,night}-{unlit,lit}.png
    static func cutawayImage(phase: HousePhase, lit: Bool) -> NSImage? {
        let name = "house-cutaway-\(phase.assetName)-\(lit ? "lit" : "unlit")"
        if let img = images[name] { return img }
        guard let url = resourceURL(name, "png"), let img = NSImage(contentsOf: url) else { return nil }
        images[name] = img
        return img
    }

    static func cutawayScene() -> HouseCutawaySceneFile? {
        if let cached = sceneCache { return cached }
        let scene = resourceURL("house-cutaway", "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(HouseCutawaySceneFile.self, from: $0) }
        sceneCache = .some(scene)
        return scene
    }

    /// SPM 的 .process 可能把 House/ 摊平到 bundle 根目录，两处都找
    private static func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "House")
            ?? Bundle.module.url(forResource: name, withExtension: ext)
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

}

// MARK: - 连通剖面整栋（烘焙灯光）

struct HouseCutawaySceneView: View {
    var rooms: [HouseRoom]
    var phase: HousePhase = .from()
    var showLabels = true
    var fitWidth: CGFloat?
    /// 点剖面里的灯具切换设备；快照 CLI 传 nil
    var onToggle: ((String) -> Void)? = nil

    private var cut: HouseCutawaySceneFile? { HouseAssets.cutawayScene() }
    private var artSize: CGSize { cut?.artSize ?? CGSize(width: 960, height: 540) }
    private var displayScale: CGFloat {
        guard let fitWidth else { return 1 }
        return fitWidth / artSize.width
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let unlit = HouseAssets.cutawayImage(phase: phase, lit: false) {
                art(unlit)
                if let lit = HouseAssets.cutawayImage(phase: phase, lit: true) {
                    ForEach(rooms) { room in
                        if let m = cut?.modules[room.module.rawValue] {
                            HouseRoomLightLayer(module: m, devices: room.devices, lighting: room.lighting,
                                                lit: lit, unlit: unlit, artSize: artSize, onToggle: onToggle)
                        }
                    }
                }
            } else {
                Theme.bg2.overlay(Text("house-cutaway").font(.caption).foregroundStyle(.tertiary))
            }
            if showLabels {
                ForEach(rooms) { room in
                    if let p = cut?.modules[room.module.rawValue]?.label, p.count >= 2 {
                        Text(room.title).font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.black.opacity(0.5), in: Capsule()).foregroundStyle(.white.opacity(0.92))
                            .fixedSize()
                            .position(x: p[0], y: p[1])
                    }
                }
            }
        }
        .frame(width: artSize.width, height: artSize.height)
        .clipped()
        .scaleEffect(displayScale, anchor: .topLeading)
        .frame(width: artSize.width * displayScale, height: artSize.height * displayScale, alignment: .topLeading)
        .clipped()
    }

    private func art(_ img: NSImage) -> some View {
        Image(nsImage: img).interpolation(.none).resizable().frame(width: artSize.width, height: artSize.height)
    }
}

/// 单个房间：每盏开着的灯按「房间多边形 ∩ 灯具蒙版」露出 lit 底图；关着的灯具本体用 unlit 盖回去。
private struct HouseRoomLightLayer: View {
    let module: HouseCutawayModule
    let devices: [HouseDevice]
    let lighting: RoomModuleLighting
    let lit: NSImage
    let unlit: NSImage
    let artSize: CGSize
    var onToggle: ((String) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(module.lights) { light in
                let k = light.strength(lighting)
                if let reveal = light.reveal {
                    image(lit)
                        .mask(revealMask(reveal))
                        .opacity(k)
                        .animation(.easeInOut(duration: 0.35), value: k)
                }
            }
            ForEach(module.lights) { light in
                if let core = light.corePolygon {
                    let k = light.strength(lighting)
                    image(unlit)
                        .mask(HousePolygon(points: core).fill(Color.white))
                        .opacity(1 - k)
                        .animation(.easeInOut(duration: 0.35), value: k)
                }
            }
            if onToggle != nil {
                ForEach(module.lights) { light in
                    if let dev = light.matchedDevice(in: devices), let hit = HouseFixtureHit(light: light) {
                        hit.shape
                            .fill(Color.white.opacity(0.001))
                            .contentShape(hit.shape)
                            .onTapGesture { onToggle?(dev.did) }
                            .accessibilityElement()
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(dev.name)
                            .accessibilityValue(dev.on ? L("开", "On") : L("关", "Off"))
                            .accessibilityHint(L("切换设备", "Toggle device"))
                    }
                }
            }
        }
        .frame(width: artSize.width, height: artSize.height)
    }

    private func image(_ img: NSImage) -> some View {
        Image(nsImage: img).interpolation(.none).resizable().frame(width: artSize.width, height: artSize.height)
    }

    /// 不用 .blur：--house-snapshot 走 cacheDisplay，图层滤镜不会被渲染；羽化用渐变代替。
    @ViewBuilder private func revealMask(_ r: HouseReveal) -> some View {
        let room = HousePolygon(points: module.region).fill(Color.white)
        switch r {
        case .room:
            room
        case let .ellipse(cx, cy, rx, ry):
            ZStack(alignment: .topLeading) {
                EllipticalGradient(stops: [.init(color: .white, location: 0), .init(color: .white, location: 0.55),
                                           .init(color: .white.opacity(0), location: 1)])
                    .frame(width: rx * 2, height: ry * 2)
                    .offset(x: cx - rx, y: cy - ry)
            }
            .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
            .mask(room)
        }
    }
}

/// 画布像素坐标的多边形（房间区域 / 灯具本体）
struct HousePolygon: Shape {
    let points: [[Double]]
    func path(in _: CGRect) -> Path {
        var p = Path()
        let pts = points.filter { $0.count >= 2 }.map { CGPoint(x: $0[0], y: $0[1]) }
        guard let first = pts.first else { return p }
        p.move(to: first)
        pts.dropFirst().forEach { p.addLine(to: $0) }
        p.closeSubpath()
        return p
    }
}

/// 灯具点击区域：优先灯罩/屏幕/本体多边形，否则略放大的 reveal 椭圆
private struct HouseFixtureHit {
    let shape: AnyShape

    init?(light: HouseLightSpec) {
        if let poly = light.corePolygon, poly.count >= 3 {
            shape = AnyShape(HousePolygon(points: poly))
            return
        }
        guard case let .ellipse(cx, cy, rx, ry) = light.reveal else { return nil }
        let pad = 1.12
        shape = AnyShape(HouseRevealEllipse(cx: cx, cy: cy, rx: rx * pad, ry: ry * pad))
    }
}

private struct HouseRevealEllipse: Shape {
    let cx, cy, rx, ry: Double
    func path(in _: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
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
                HouseCutawaySceneView(rooms: rooms, phase: phase, showLabels: true, fitWidth: showChrome ? sceneWidth : nil,
                                      onToggle: onToggle)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
            }
            if showChrome, let onToggle { HouseDeviceChipRow(rooms: rooms, onToggle: onToggle) }
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

}

struct HouseDeviceChipRow: View {
    var rooms: [HouseRoom]
    var onToggle: (String) -> Void
    var topPadding: CGFloat = 10

    var body: some View {
        let chips = rooms.flatMap(\.devices).filter { $0.kind != .ac || $0.on }
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.did) { d in
                        HouseTapChip(icon: HouseChipStyle.icon(d.kind), label: d.name, on: d.on, tint: HouseChipStyle.tint(d.kind)) { onToggle(d.did) }
                    }
                }.padding(.top, topPadding)
            }
        }
    }
}

private enum HouseChipStyle {
    static func icon(_ k: HouseSlotKind) -> String {
        switch k { case .light: return "lightbulb.fill"; case .tv: return "tv.fill"; case .ac: return "air.conditioner.horizontal" }
    }
    static func tint(_ k: HouseSlotKind) -> Color {
        switch k { case .light: return .yellow; case .tv: return .indigo; case .ac: return Theme.cool }
    }
}

// MARK: - 主面板嵌入

/// 设备列表顶部的紧凑剖面：宽度随主面板，点场景或「放大」打开独立小屋窗口。
struct HouseListEmbed: View {
    @EnvironmentObject var m: AppModel
    @State private var contentWidth: CGFloat = 0

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let rooms = m.houseRooms
            if !rooms.isEmpty {
                let phase = HousePhase.from(date: ctx.date)
                VStack(alignment: .leading, spacing: 6) {
                    embedChrome(phase: phase, cozy: rooms.contains { $0.lighting.cozy > 0.35 })
                    if contentWidth > 0 {
                        cutaway(rooms: rooms, phase: phase, width: contentWidth)
                    }
                    HouseDeviceChipRow(rooms: rooms, topPadding: 4) { did in
                        guard let d = m.device(did) else { return }
                        withoutAnimation { m.toggle(d) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    GeometryReader { geo in
                        Color.clear.onChange(of: geo.size.width, initial: true) { _, w in contentWidth = w }
                    }
                }
            }
        }
    }

    private func embedChrome(phase: HousePhase, cozy: Bool) -> some View {
        HStack(spacing: 8) {
            Text(L("小屋", "House")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: phase == .day ? "sun.max.fill" : "moon.stars.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(phase == .day ? Color.orange.opacity(0.85) : Color.indigo.opacity(0.75))
                Text(phase == .day ? L("白天", "Daytime") : L("夜间", "Nighttime"))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 7).padding(.vertical, 3).background(Theme.tile, in: Capsule())
            Circle().fill(cozy ? Color.green : Color.secondary.opacity(0.45)).frame(width: 6, height: 6)
            Spacer(minLength: 0)
            expandButton
        }
    }

    private var expandButton: some View {
        Button { HouseWindow.open(model: m) } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 10, weight: .semibold))
                Text(L("放大", "Enlarge")).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Theme.tile, in: Capsule())
            .overlay(Capsule().stroke(Theme.stroke))
        }
        .buttonStyle(.plain).hoverHighlight()
        .help(L("在窗口中打开小屋", "Open house in a window"))
        .accessibilityLabel(L("放大", "Enlarge"))
    }

    private func cutaway(rooms: [HouseRoom], phase: HousePhase, width: CGFloat) -> some View {
        HouseCutawaySceneView(rooms: rooms, phase: phase, showLabels: false, fitWidth: width) { did in
            guard let d = m.device(did) else { return }
            withoutAnimation { m.toggle(d) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke))
        .overlay(alignment: .topTrailing) {
            Button { HouseWindow.open(model: m) } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.92))
                    .padding(6)
                    .background(.black.opacity(0.45), in: Circle())
            }
            .buttonStyle(.plain).hoverHighlight()
            .help(L("放大", "Enlarge"))
            .accessibilityLabel(L("放大", "Enlarge"))
            .padding(6)
        }
        .accessibilityElement(children: .contain)
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
        let onRooms = rooms.map { r -> HouseRoom in
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
            ("house-day-on", .day, onRooms),
            ("house-day-off", .day, offRooms),
            ("house-night-on", .night, onRooms),
            ("house-night-off", .night, offRooms),
            ("house-night", .night, onRooms),
            ("house-off", .night, offRooms),
        ]
        // 网站用：只开部分灯具，展示「开哪盏只亮哪一处」
        func only(_ pick: (HouseRoom) -> RoomModuleLighting?) -> [HouseRoom] {
            rooms.map { r in HouseRoom(key: r.key, title: r.title, module: r.module, devices: r.devices, overflow: r.overflow, lighting: pick(r) ?? .allOff) }
        }
        let lamp = RoomModuleLighting(lampLevels: [1, 0], tv: 0, ac: 0, cozy: 0.4)
        let oneLamp = only { $0.module == .living ? lamp : nil }
        let twoLamps = only { $0.module == .living || $0.module == .bedroom ? lamp : nil }
        let partial: [(String, HousePhase, [HouseRoom])] = [
            ("house-night-partial", .night, rooms),   // 演示数据的真实状态：客厅落地灯 + 电视
            ("house-day-partial", .day, rooms),
            ("house-night-onelamp", .night, oneLamp),
            ("house-night-twolamps", .night, twoLamps),
        ]
        for (name, phase, rs) in exports + partial {
            render(HouseCutawaySceneView(rooms: rs, phase: phase, showLabels: false), out.appendingPathComponent("\(name).png"),
                   size: CGSize(width: 960, height: 540))
        }
        exit(0)
    }
}
