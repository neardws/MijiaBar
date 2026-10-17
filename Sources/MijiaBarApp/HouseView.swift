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

    func strength(_ l: RoomLighting) -> Double { l.level(id) }

    /// 放在这个灯具位上的设备（id 与 HouseCatalog / house.json 的 fixture id 一致）
    func matchedDevice(in devices: [HouseDevice]) -> HouseDevice? { devices.first { $0.spot == .fixture(id) } }
}

struct HouseCutawayModule: Decodable {
    let label: [Double]?
    /// 徽章位脚下的点（[x, y]），顺序对应 HouseCatalog.badgeIds：b1, b2, …
    let badges: [[Double]]?
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

    /// 徽章小图标：badge-<category>-{on,off}.png（scripts/gen-house-badges.py 生成，12×12）
    static func badge(_ c: DeviceCategory, on: Bool) -> NSImage? {
        let name = "badge-\(c.rawValue)-\(on ? "on" : "off")"
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

/// 一个房间的灯光：灯具位 id → 亮度（0…1）
struct RoomLighting: Equatable {
    var levels: [String: Double]
    var cozy: Double

    static let allOff = RoomLighting(levels: [:], cozy: 0)
    func level(_ id: String) -> Double { levels[id] ?? 0 }

    static func from(_ devices: [HouseDevice]) -> RoomLighting {
        var lv: [String: Double] = [:]
        var lamps = 0.0, tv = 0.0, ac = 0.0
        for d in devices where d.on {
            guard case .fixture(let id)? = d.spot else { continue }
            lv[id] = 1
            switch d.category { case .tv: tv = 1; case .ac: ac = 1; default: lamps += 1 }
        }
        return RoomLighting(levels: lv, cozy: min(1, 0.12 + lamps * 0.28 + tv * 0.32 + ac * 0.22))
    }
}

struct HouseDevice: Equatable {
    let did: String, name: String, category: DeviceCategory
    let spot: HouseSpot?
    var on: Bool
    let online: Bool
    /// 有开关（传感器之类没有）
    let toggleable: Bool
}

struct HouseRoom: Identifiable, Equatable {
    var id: String { key }
    let key: String, title: String, module: HouseModule
    var devices: [HouseDevice]
    var lighting: RoomLighting

    /// 截图用：指定哪些灯具位亮着；徽章设备跟着 badgesOn
    func lit(_ fixtures: Set<String>, badgesOn: Bool) -> HouseRoom {
        var r = self
        r.devices = devices.map { d in
            var d = d
            switch d.spot { case .fixture(let id)?: d.on = fixtures.contains(id); case .badge?: d.on = badgesOn && d.toggleable; case nil: break }
            return d
        }
        r.lighting = RoomLighting(levels: Dictionary(uniqueKeysWithValues: fixtures.map { ($0, 1.0) }), cozy: fixtures.isEmpty ? 0 : min(1, 0.12 + Double(fixtures.count) * 0.3))
        return r
    }
}

extension AppModel {
    func housePower(_ d: Device) -> Bool? { powerInfo(d)?.isOn }

    /// house.json 里的家庭 key
    var houseHomeKey: String { currentHomeId ?? devices.first?.homeId ?? "" }

    /// 自动布局 + house.json 覆盖项（纯函数，见 MijiaCore/HouseLayout.swift）
    var houseResolved: ResolvedHouse {
        let inHome = devices.filter { currentHomeId == nil || $0.homeId == currentHomeId }
        return HouseResolver.resolve(devices: inHome, config: house.homes[houseHomeKey], isHidden: { self.isHidden($0) }, name: { self.displayName($0) })
    }

    var houseRooms: [HouseRoom] { houseResolved.rooms.map(houseRoom) }

    func houseRoom(_ r: ResolvedHouseRoom) -> HouseRoom {
        let ds = r.devices.map { x -> HouseDevice in
            let p = device(x.did).flatMap { powerInfo($0) }
            return HouseDevice(did: x.did, name: x.name, category: x.category, spot: x.spot, on: x.online && p?.isOn == true, online: x.online, toggleable: p != nil)
        }
        return HouseRoom(key: r.key, title: r.title, module: r.module, devices: ds, lighting: .from(ds))
    }

    /// 改小屋配置：写 house.json（iCloud Drive 同步、文件协调锁），演示模式只改内存
    @discardableResult
    func updateHouse(_ f: (inout HouseFile) -> Void) -> Bool {
        if mock { var h = house; f(&h); house = h; return true }
        do { house = try HouseStore.update(f); return true } catch {
            showToast(L("保存小屋设置失败：", "Couldn't save house settings: ") + error.localizedDescription, error: true)
            houseNotice = L("保存失败：", "Couldn't save: ") + error.localizedDescription
            return false
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
    /// 编辑模式（HouseWindow）：画出灯具位 / 徽章位，点击选中位置，不切换设备
    var edit: HouseEditContext? = nil

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
                                                lit: lit, unlit: unlit, artSize: artSize, onToggle: edit == nil ? onToggle : nil)
                        }
                    }
                }
                ForEach(rooms) { room in
                    if let m = cut?.modules[room.module.rawValue] {
                        HouseBadgeLayer(module: m, room: room, phase: phase, artSize: artSize, onToggle: edit == nil ? onToggle : nil)
                    }
                }
                if let edit {
                    ForEach(rooms) { room in
                        if let m = cut?.modules[room.module.rawValue] {
                            HouseEditSlots(module: m, room: room, artSize: artSize, edit: edit)
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
        .modifier(HouseSceneDropModifier(edit: edit, targets: editTargets, scale: displayScale))
    }

    private var editTargets: [(sel: HouseSelection, rect: CGRect)] {
        guard edit != nil, let cut else { return [] }
        return rooms.flatMap { room -> [(sel: HouseSelection, rect: CGRect)] in
            guard let m = cut.modules[room.module.rawValue] else { return [] }
            return HouseEditSlots.targets(module: m, room: room).map { (sel: $0.sel, rect: $0.rect) }
        }
    }

    private func art(_ img: NSImage) -> some View {
        Image(nsImage: img).interpolation(.none).resizable().frame(width: artSize.width, height: artSize.height)
    }
}

/// 单个房间：每盏开着的灯按「房间多边形 ∩ 灯具蒙版」露出 lit 底图；关着的灯具本体用 unlit 盖回去。
private struct HouseRoomLightLayer: View {
    let module: HouseCutawayModule
    let devices: [HouseDevice]
    let lighting: RoomLighting
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

/// 徽章：没有专属灯具的设备（风扇、插座、净化器、传感器……）在地上的像素小图标；开着时脚下有一圈对应颜色的光。
struct HouseBadgeLayer: View {
    let module: HouseCutawayModule
    let room: HouseRoom
    let phase: HousePhase
    let artSize: CGSize
    var onToggle: ((String) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(HouseCatalog.badgeIds(room.module).enumerated()), id: \.offset) { i, id in
                if let d = room.devices.first(where: { $0.spot == .badge(id) }), let p = module.badges?[safe: i], p.count >= 2 {
                    HouseBadge(device: d, phase: phase)
                        .position(x: p[0], y: p[1] - 14)
                        .contentShape(Rectangle())
                        .onTapGesture { if d.toggleable { onToggle?(d.did) } }
                        .allowsHitTesting(onToggle != nil && d.toggleable)
                        .accessibilityElement()
                        .accessibilityLabel(d.name)
                        .accessibilityValue(d.toggleable ? (d.on ? L("开", "On") : L("关", "Off")) : "")
                }
            }
        }
        .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
    }
}

struct HouseBadge: View {
    let device: HouseDevice
    let phase: HousePhase

    /// 有开关的设备开着时亮；传感器这类没有开关的，在线就显示彩色
    private var lit: Bool { device.toggleable ? device.on : device.online }
    private var glow: Color {
        switch device.category {
        case .light: return Color(red: 1, green: 0.8, blue: 0.4)
        case .tv, .camera: return Color(red: 0.5, green: 0.75, blue: 1)
        case .ac, .fan, .airPurifier, .purifier, .dehumidifier: return Color(red: 0.55, green: 0.9, blue: 1)
        case .heater, .kitchen: return Color(red: 1, green: 0.6, blue: 0.3)
        default: return Color(red: 0.55, green: 1, blue: 0.6)
        }
    }

    var body: some View {
        ZStack {
            Ellipse().fill(Color.black.opacity(0.35)).frame(width: 30, height: 8).offset(y: 18)
            if device.toggleable && device.on {
                EllipticalGradient(colors: [glow.opacity(phase == .night ? 0.85 : 0.55), glow.opacity(0)])
                    .frame(width: 76, height: 28).offset(y: 17)
            }
            if let img = HouseAssets.badge(device.category, on: lit) {
                // 12×12 精灵按 3 倍最近邻放大（底图像素格是 2，徽章略粗一点，菜单栏里缩小后也看得清）
                Image(nsImage: img).interpolation(.none).resizable().frame(width: 36, height: 36)
                    .opacity(!device.online ? 0.45 : (!lit && phase == .night ? 0.8 : 1))
            }
        }
        .frame(width: 76, height: 56)
        .animation(.easeInOut(duration: 0.35), value: device.on)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
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
    var edit: HouseEditContext? = nil
    /// 标题栏的白天 / 夜间、设备已开标签（编辑模式下按钮多，隐藏）
    var showStatus = true
    /// 标题栏右侧的按钮（「编辑」/「恢复自动」「完成」）
    var accessory: AnyView? = nil

    private let sceneWidth: CGFloat = 660

    var body: some View {
        VStack(spacing: 0) {
            if showChrome { header }
            if rooms.isEmpty {
                Text(L("这个家里还没有能放进小屋的房间", "No rooms for the house view yet"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: sceneWidth, height: 200)
            } else {
                HouseCutawaySceneView(rooms: rooms, phase: phase, showLabels: true, fitWidth: showChrome ? sceneWidth : nil,
                                      onToggle: onToggle, edit: edit)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.stroke))
            }
            if showChrome, edit == nil, let onToggle { HouseDeviceChipRow(rooms: rooms, onToggle: onToggle) }
        }
        .padding(showChrome ? 12 : 0)
        .background(showChrome ? Theme.bg : .clear)
    }

    private var header: some View {
        HStack {
            Text(L("小屋", "House")).font(.system(size: 15, weight: .semibold))
            Spacer()
            if showStatus { statusPills }
            if let accessory { accessory }
        }
        .padding(.bottom, 8)
    }

    @ViewBuilder private var statusPills: some View {
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

}

struct HouseDeviceChipRow: View {
    var rooms: [HouseRoom]
    var onToggle: (String) -> Void
    var topPadding: CGFloat = 10

    var body: some View {
        let chips = rooms.flatMap(\.devices).filter { $0.toggleable && $0.online && ($0.category != .ac || $0.on) }
        if !chips.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.did) { d in
                        HouseTapChip(icon: HouseChipStyle.icon(d.category), label: d.name, on: d.on, tint: HouseChipStyle.tint(d.category)) { onToggle(d.did) }
                    }
                }.padding(.top, topPadding)
            }
        }
    }
}

enum HouseChipStyle {
    static func icon(_ c: DeviceCategory) -> String {
        switch c { case .light: return "lightbulb.fill"; case .tv: return "tv.fill"; case .fan: return "fan.fill"; default: return c.icon }
    }
    static func tint(_ c: DeviceCategory) -> Color {
        switch c { case .light: return .yellow; case .tv: return .indigo; case .ac: return Theme.cool; case .heater: return .orange; default: return .green }
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
            MainActor.assumeIsolated { window?.contentView = nil; window = nil; model.houseUndo.clear(); model.houseNotice = nil }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 编辑模式右边多一个设备面板，窗口加宽（保持左上角不动）
    static let normalSize = NSSize(width: 720, height: 560)
    static let editSize = NSSize(width: 1041, height: 640)
    static func resize(editing: Bool) {
        guard let w = window else { return }
        let size = editing ? editSize : normalSize
        var f = w.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        f.origin = NSPoint(x: w.frame.minX, y: w.frame.maxY - f.height)
        w.setFrame(f, display: true, animate: true)
    }
}

struct HousePilotHost: View {
    @EnvironmentObject var m: AppModel
    @State var editing = false
    @State var selection: HouseSelection?
    @State var drag = HouseDragState()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let rooms = m.houseRooms
            let phase = HousePhase.from(date: ctx.date)
            if editing {
                let resolved = m.houseResolved
                let edit = context(resolved)
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HouseFullView(rooms: rooms, phase: phase, onToggle: nil, edit: edit, showStatus: false, accessory: AnyView(editButtons))
                            .overlay(alignment: .bottom) { notice }
                        Text(L("把右边的设备拖到虚线框上放置；拖动已放好的设备可移动或交换，拖回右边或空白处移出。也可以点虚线框再在右边选。眼睛按钮只控制小屋里显示与否（不影响设备列表）。改动立即保存并同步到其他 Mac，⌘Z 撤销。",
                               "Drag a device from the right onto a dashed spot. Drag a placed device to move or swap it, or back to the list or an empty area to take it off. You can also click a spot and pick a device. The eye button shows or hides a device in the house only. Changes save right away and sync to your other Macs; ⌘Z undoes."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14).padding(.bottom, 12)
                    }
                    .frame(width: 684)
                    Divider()
                    HouseEditPanel(selection: $selection, edit: edit).frame(width: 356)
                }
            } else {
                HouseFullView(rooms: rooms, phase: phase, onToggle: { did in
                    guard let d = m.device(did) else { return }
                    withoutAnimation { m.toggle(d) }
                }, accessory: AnyView(editButton))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.bg)
    }

    private func context(_ resolved: ResolvedHouse) -> HouseEditContext {
        HouseEditContext(
            selected: selection,
            onSelect: { sel in selection = sel == selection ? nil : sel },
            drag: drag,
            currentSession: { drag.session },
            verdict: { t in
                guard let s = drag.session, let src = m.houseDragSource(s.did, resolved: resolved) else { return nil }
                return HouseEditing.planDrop(src, roomKey: t.roomKey, spot: t.spot, house: resolved)
            },
            beginDrag: { did, from in
                let d = m.device(did)
                drag = HouseDragState(session: HouseDragSession(did: did, name: d.map(m.displayName) ?? did, category: d?.category ?? .other, from: from))
                return NSItemProvider(object: (HouseDragSession.prefix + did) as NSString)
            },
            setHover: { h in if drag.hover != h { drag.hover = h } },
            setInScene: { v in if drag.inScene != v { drag.inScene = v } },
            perform: { t, payload in perform(t, payload: payload, resolved: resolved) })
    }

    /// 松手：放到位置上（可能交换），或从位置上移出
    private func perform(_ t: HouseSelection?, payload: String?, resolved: ResolvedHouse) {
        let s = drag.session
        drag = HouseDragState()
        guard let s, payload == s.payload else { return }
        let home = m.houseHomeKey
        if let t {
            guard let src = m.houseDragSource(s.did, resolved: resolved) else { return }
            switch HouseEditing.planDrop(src, roomKey: t.roomKey, spot: t.spot, house: resolved) {
            case .accept(let c):
                guard !c.isEmpty else { return }
                let verb = c.count > 1 ? L("交换 ", "Swap ") : (s.from == nil ? L("放置 ", "Place ") : L("移动 ", "Move "))
                m.houseEdit(verb + s.name) { HouseEditing.apply(c, to: &$0, home: home) }
                selection = t
            case .reject(let r):
                m.houseFlash(r.message)
            }
        } else if s.from != nil {
            let c = HouseEditing.planClear(did: s.did, house: resolved)
            guard !c.isEmpty else { return }
            m.houseEdit(L("移出 ", "Remove ") + s.name) { HouseEditing.apply(c, to: &$0, home: home) }
            if selection == s.from { selection = nil }
        }
    }

    @ViewBuilder private var notice: some View {
        if let n = m.houseNotice {
            Label(n, systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.78)))
                .padding(.bottom, 22)
                .transition(.opacity)
        }
    }

    private var editButton: some View {
        Button { selection = nil; editing = true; HouseWindow.resize(editing: true) } label: {
            Label(L("编辑", "Edit"), systemImage: "pencil").font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(.bordered).controlSize(.small)
        .help(L("选择每个位置放哪台设备、哪些设备在小屋里显示", "Choose which device goes where and what shows in the house"))
    }

    private var editButtons: some View {
        HStack(spacing: 6) {
            Text(L("编辑中", "Editing")).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.orange)
                .padding(.horizontal, 8).padding(.vertical, 4).background(Color.orange.opacity(0.14), in: Capsule())
            Button { m.houseUndoStep(redo: false) } label: {
                Label(L("撤销", "Undo"), systemImage: "arrow.uturn.backward").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered).controlSize(.small)
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!m.houseUndo.canUndo)
            .help(m.houseUndo.undoLabel.map { L("撤销：", "Undo: ") + $0 + "（⌘Z）" } ?? L("没有可撤销的操作", "Nothing to undo"))
            Button { m.houseUndoStep(redo: true) } label: {
                Label(L("重做", "Redo"), systemImage: "arrow.uturn.forward").font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.bordered).controlSize(.small)
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!m.houseUndo.canRedo)
            .help(m.houseUndo.redoLabel.map { L("重做：", "Redo: ") + $0 + "（⇧⌘Z）" } ?? L("没有可重做的操作", "Nothing to redo"))
            Button(L("恢复自动", "Reset to automatic")) { selection = nil; m.houseResetAll() }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(m.house.homes[m.houseHomeKey].map { h in h.devices.values.allSatisfy(\.isEmpty) && h.rooms.values.allSatisfy { $0.module == nil } } ?? true)
            Button(L("完成", "Done")) { selection = nil; drag = HouseDragState(); editing = false; HouseWindow.resize(editing: false) }
                .buttonStyle(.borderedProminent).controlSize(.small).keyboardShortcut(.defaultAction)
        }
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
        func all(_ r: HouseRoom) -> Set<String> { Set(HouseCatalog.fixtures(r.module).map(\.id)) }
        let onRooms = rooms.map { $0.lit(all($0), badgesOn: true) }
        let offRooms = rooms.map { $0.lit([], badgesOn: false) }
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
        let oneLamp = rooms.map { $0.lit($0.module == .living ? ["floor_lamp"] : [], badgesOn: false) }
        let twoLamps = rooms.map { $0.lit($0.module == .living ? ["floor_lamp"] : $0.module == .bedroom ? ["bedside"] : [], badgesOn: false) }
        let partial: [(String, HousePhase, [HouseRoom])] = [
            ("house-night-partial", .night, rooms),   // 演示数据的真实状态：客厅落地灯 + 电视，客厅空调徽章
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
