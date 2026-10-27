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
    var absentVariant: HouseAbsentVariant? = nil
    let id: String
    let kind: String          // lamp | sconce | ceiling | screen | ac
    let role: String          // light（按 slot）| tv | ac
    let slot: Int?
    let reveal: HouseReveal?
    let shade: [[Double]]?    // 灯罩多边形
    let screen: [[Double]]?   // 屏幕四边形
    let core: [[Double]]?     // 灯具本体（关灯时用 unlit 盖回去）
    /// 空调出风口下沿（两点）+ 送风方向：开机时画动态送风（HouseAirflow）
    var vent: [[Double]]? = nil
    var wall: String? = nil
    var flow: Double? = nil
    var flowDirection: Double { flow ?? (wall == "ne" ? -1 : 1) }

    /// 合成场景：墙挂灯具所在那段墙被切掉了（本体不可见，没有 shade/screen/core）
    var hidden: Bool? = nil
    /// 本体被切掉时的徽章位（地面点，空调用）
    var alt: [Double]? = nil

    /// 窗帘贴片（patch + rect + mid + quad）、家电显示屏 / 指示灯 / 滚筒门、家电本体（只用来点击）
    var patch: String? = nil
    var rect: [Double]? = nil
    var mid: Double? = nil
    var quad: [[Double]]? = nil
    var display: [[Double]]? = nil
    var led: [Double]? = nil
    var door: HouseDoor? = nil
    var body: [[Double]]? = nil
    var anchor: [Double]? = nil

    var isFloorAppliance: Bool { ["fan", "air-purifier", "dehumidifier", "heater", "humidifier", "vacuum"].contains(role) }
    var floorAnchor: CGPoint? {
        if let anchor, anchor.count == 2 { return CGPoint(x: anchor[0], y: anchor[1]) }
        guard let body, !body.isEmpty, body.allSatisfy({ $0.count == 2 }),
              let left = body.map({ $0[0] }).min(), let right = body.map({ $0[0] }).max(),
              let bottom = body.map({ $0[1] }).max() else { return nil }
        return CGPoint(x: (left + right) / 2, y: bottom)
    }

    /// 只有灯 / 屏幕 / 空调烘焙了光；窗帘、冰箱、热水器、洗衣机的状态全由 App 动态画（不露 lit 图）
    var bakesLight: Bool { ["light", "tv", "ac"].contains(role) }

    /// 关掉时需要用 unlit 盖回去的灯具本体（防止同房间其他灯的 lit 蒙版把它“点亮”）
    var corePolygon: [[Double]]? { bakesLight ? (core ?? screen ?? shade) : nil }
    /// 点击区域
    var hitPolygon: [[Double]]? { corePolygon ?? body ?? quad }

    func strength(_ l: RoomLighting) -> Double { l.level(id) }

    /// 放在这个灯具位上的设备（id 与 HouseCatalog / house.json 的 fixture id 一致）
    func matchedDevice(in devices: [HouseDevice]) -> HouseDevice? { devices.first { $0.spot == .fixture(id) } }

    func shouldShowAbsentVariant(in devices: [HouseDevice]) -> Bool {
        absentVariant != nil && hidden != true && matchedDevice(in: devices) == nil
    }
}

struct HouseCutawayModule: Decodable {
    let label: [Double]?
    /// 徽章位脚下的点（[x, y]），顺序对应 HouseCatalog.badgeIds：b1, b2, …
    let badges: [[Double]]?
    let region: [[Double]]
    let lights: [HouseLightSpec]
    /// 合成场景：本模块剪影减去后画模块（前方房间）的剪影；灯光蒙版用它，光不会透过前屋的墙
    var visible: [[[Double]]]? = nil
    var petVisible: [[[Double]]]? = nil
}

/// 场景来源：经典四室 = 手绘整图 + house-cutaway.json（按模块名查）；
/// 自定义布局 = 模块合成图 + 合成场景（HouseComposer，按房间 key 查）。
struct HouseSceneSource {
    let unlit: NSImage
    let lit: NSImage
    let scene: HouseCutawaySceneFile
    let byRoom: Bool
    var layout: [HouseLayoutCell]? = nil
    var artSize: CGSize { scene.artSize }
    func module(for room: HouseRoom) -> HouseCutawayModule? { scene.modules[byRoom ? room.key : room.module.rawValue] }

    @MainActor static func make(layout: [HouseLayoutCell]?, phase: HousePhase, style: String? = nil, config: HomeHouse = HomeHouse(), roomKeys: [String: String] = [:]) -> HouseSceneSource? {
        if (config.pets ?? [:]).values.contains(where: { !$0.deleted }) {
            let fallback = HouseLayoutSolver.classicFour.map { HouseLayoutCell(room: roomKeys[$0.module] ?? $0.module, module: $0.module, col: $0.col, row: $0.row) }
            let cells = HouseLayoutSolver.isClassicGeometry(layout) ? HouseLayoutSolver.setAllLevels(layout ?? fallback, flat: true) : (layout ?? fallback)
            return HouseModuleAssets.composedScene(layout: cells, phase: phase, style: style, config: config)
        }
        if !HouseStyles.info(style).hasClassicArt {
            let classic = HouseLayoutSolver.isClassicGeometry(layout)
            let fallback = HouseLayoutSolver.classicFour.map { HouseLayoutCell(room: roomKeys[$0.module] ?? $0.module, module: $0.module, col: $0.col, row: $0.row) }
            let cells = classic ? HouseLayoutSolver.setAllLevels(layout ?? fallback, flat: true) : (layout ?? fallback)
            guard let source = HouseModuleAssets.composedScene(layout: cells, phase: phase, style: style, config: config) else { return nil }
            if layout != nil { return source }
            var modules: [String: HouseCutawayModule] = [:]
            for cell in cells { modules[cell.module] = source.scene.modules[cell.room] }
            return HouseSceneSource(unlit: source.unlit, lit: source.lit,
                                    scene: HouseCutawaySceneFile(size: source.scene.size, modules: modules, decorSlots: source.scene.decorSlots, freeDecor: source.scene.freeDecor, origin: source.scene.origin), byRoom: false, layout: cells)
        }
        if let layout, !HouseLayoutSolver.isClassicGeometry(layout),
           let c = HouseModuleAssets.composedScene(layout: layout, phase: phase, style: style, config: config) { return c }
        guard let u = HouseAssets.cutawayImage(phase: phase, lit: false, style: style),
              let l = HouseAssets.cutawayImage(phase: phase, lit: true, style: style),
              let sc = HouseAssets.cutawayScene() else { return nil }
        return HouseSceneSource(unlit: u, lit: l, scene: sc, byRoom: false)
    }
}

struct HouseCutawaySceneFile: Decodable {
    let size: [Double]
    let modules: [String: HouseCutawayModule]
    var decorSlots: [HouseDecorSceneSlot]? = nil
    var freeDecor: [HouseFreeDecorSceneItem]? = nil
    var origin: [Double]? = nil
    var artSize: CGSize { CGSize(width: size[0], height: size[1]) }
}

struct HouseFreeDecorSceneItem: Decodable {
    let key: String
    let room: String
    let item: String
    let cell: [Int]
    let rect: [Double]
}

struct HouseDecorSceneSlot: Decodable {
    let room: String
    let slot: String
    let surface: String
    let wall: String?
    let sizes: [String]
    let x: Double
    let y: Double
    let item: String?
    let hidden: String?
    let rect: [Double]
}

/// 剖面底图时段：本地 6:00–18:00 为白天，其余为夜间（与系统时区一致）。
enum HousePhase: Hashable {
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

    /// 烘焙底图：house-cutaway-{day,night}-{unlit,lit}.png（风格包优先）
    static func cutawayImage(phase: HousePhase, lit: Bool, style: String? = nil) -> NSImage? {
        let name = "house-cutaway-\(phase.assetName)-\(lit ? "lit" : "unlit")"
        let styleId = HouseStyles.resolve(style)
        let key = "\(styleId)|\(name)"
        if let img = images[key] { return img }
        let url = HouseModuleAssets.resourceURL(name, "png", style: styleId) ?? resourceURL(name, "png")
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        images[key] = img
        return img
    }

    static func clearImageCache() { images.removeAll() }

    static func fixture(role: String, on: Bool) -> NSImage? {
        let name = "fixture-\(role)-\(on ? "on" : "off")"
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

    /// 窗帘关合贴片：<patch>-{day,night}-{unlit,lit}.png（scripts/house_modules/curtains.py）
    static func curtainPatch(_ name: String, phase: HousePhase, lit: Bool, style: String? = nil) -> NSImage? {
        let styleId = HouseStyles.resolve(style)
        let file = "\(name)-\(phase.assetName)-\(lit ? "lit" : "unlit")"
        let key = "\(styleId)|\(file)"
        if let img = images[key] { return img }
        let url = styleId == HouseStyles.defaultStyle
            ? (resourceURL(file, "png") ?? HouseModuleAssets.resourceURL(file, "png"))
            : (HouseModuleAssets.resourceURL(file, "png", style: styleId) ?? resourceURL(file, "png"))
        guard let url, let img = NSImage(contentsOf: url) else { return nil }
        images[key] = img
        return img
    }

    static func absentPatch(_ name: String, phase: HousePhase, lit: Bool, style: String? = nil) -> NSImage? {
        curtainPatch(name, phase: phase, lit: lit, style: style)
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
        AppResources.url(name, ext, subdirectory: "House")
            ?? AppResources.url(name, ext)
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
            switch d.category {
            case .tv: tv = 1
            case .ac: ac = 1
            case .curtain, .fridge, .washer, .waterHeater: break   // 不算「暖意」
            default: lamps += 1
            }
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
    /// 窗帘开合度 0（全关）..1（全开）；nil = 不知道，按 on 当全开 / 全关
    var level: Double? = nil
    /// 热水器正在加热、洗衣机正在洗（没有状态属性时按开着算）
    var busy: Bool = false
    var model: String = ""
    var contactClosed: Bool? = nil

    var isVacuum: Bool { HouseCatalog.isVacuum(category: category, model: model, name: name) }

    /// 窗帘露出的程度：没装设备 / 离线 = 1（底图里系起来的窗帘）
    var curtainOpen: Double { online ? min(1, max(0, level ?? (on ? 1 : 0))) : 1 }
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
        return HouseResolver.resolve(devices: inHome, config: house.homes[houseHomeKey], isHidden: { self.isHidden($0) }, name: { self.displayName($0) },
                                     layout: house.homes[houseHomeKey]?.layout)
    }

    var houseRooms: [HouseRoom] { houseResolved.rooms.map(houseRoom) }

    /// 用户自定义布局（非经典四室）时用模块合成图
    var houseLayoutCells: [HouseLayoutCell]? {
        let L = house.homes[houseHomeKey]?.layout
        return HouseLayoutSolver.isClassicGeometry(L) ? nil : L
    }

    /// 当前家庭的小屋风格（nil / 未知 → cozy-wood）
    var houseStyle: String { HouseStyles.resolve(house.homes[houseHomeKey]?.style) }


    func houseRoom(_ r: ResolvedHouseRoom) -> HouseRoom {
        let ds = r.devices.map { x -> HouseDevice in
            let p = device(x.did).flatMap { powerInfo($0) }
            var d = HouseDevice(did: x.did, name: x.name, category: x.category, spot: x.spot, on: x.online && p?.isOn == true, online: x.online, toggleable: p != nil)
            let st = states[x.did]
            d.model = device(x.did)?.model ?? ""
            if x.online, let device = device(x.did) { d.contactClosed = Notifier.snapshot(device, st, power: p?.isOn).contactClosed }
            if d.isVacuum { d.busy = x.online && HouseDeviceState.busy(st, otherwise: d.on) }
            switch x.category {
            case .curtain:
                // 窗帘没有开关属性：按当前位置（0..100，100 = 全开）
                if let pos = HouseDeviceState.curtainPosition(st) { d.level = pos; d.on = x.online && pos > 0.02 }
            case .fridge:
                d.on = x.online && (p?.isOn ?? true)
            case .washer, .waterHeater:
                d.busy = d.on && HouseDeviceState.busy(st, otherwise: x.category == .washer)
            default: break
            }
            return d
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
    /// 自定义布局（非经典四室）→ 用模块合成图；nil / 经典几何 → 手绘整图
    var layout: [HouseLayoutCell]? = nil
    var style: String? = nil
    var decorConfig: HomeHouse = HomeHouse()
    var petsRestOnly = false
    var petDate: Date? = nil
    var petPoses: [String: HousePetPose] = [:]

    private var source: HouseSceneSource? {
        let keys = rooms.reduce(into: [String: String]()) { if $0[$1.module.rawValue] == nil { $0[$1.module.rawValue] = $1.key } }
        return HouseSceneSource.make(layout: layout, phase: phase, style: style, config: decorConfig, roomKeys: keys)
    }
    private var artSize: CGSize { source?.artSize ?? CGSize(width: 960, height: 540) }
    private var displayScale: CGFloat {
        guard let fitWidth else { return 1 }
        return fitWidth / artSize.width
    }

    var body: some View {
        let src = source
        ZStack(alignment: .topLeading) {
            if let src {
                let unlit = src.unlit, lit = src.lit
                art(unlit)
                ForEach(rooms) { room in
                    if let m = src.module(for: room) {
                        HouseRoomLightLayer(module: m, devices: room.devices, lighting: room.lighting,
                                            lit: lit, unlit: unlit, artSize: artSize, phase: phase, style: style, onToggle: edit == nil ? onToggle : nil)
                    }
                }
                ForEach(rooms) { room in
                    if let module = src.module(for: room) {
                        HouseFloorApplianceLayer(module: module, devices: room.devices, phase: phase, artSize: artSize)
                    }
                }
                if (decorConfig.petPrefs?.enabled ?? true), (decorConfig.pets ?? [:]).values.contains(where: { $0.enabled && !$0.deleted }) {
                    HousePetsLayer(source: src, rooms: rooms, layout: layout, style: style, config: decorConfig,
                                   phase: phase, restOnly: petsRestOnly, date: petDate, poses: petPoses)
                }
                ForEach(rooms) { room in
                    if let m = src.module(for: room) {
                        HouseBadgeLayer(module: m, room: room, phase: phase, artSize: artSize, onToggle: edit == nil ? onToggle : nil)
                    }
                }
                if let edit {
                    let labelAt = editLabelPositions(src)
                    ForEach(rooms) { room in
                        if let m = src.module(for: room) {
                            HouseEditSlots(module: m, room: room, artSize: artSize, edit: edit, labelAt: labelAt)
                        }
                    }
                    ForEach(rooms) { room in
                        if let m = src.module(for: room) {
                            HouseEditSlots(module: m, room: room, artSize: artSize, edit: edit, labelAt: labelAt, labelsLayer: true)
                                .allowsHitTesting(false)
                        }
                    }
                }
            } else {
                Theme.bg2.overlay(Text("house-cutaway").font(.caption).foregroundStyle(.tertiary))
            }
            if showLabels {
                ForEach(rooms) { room in
                    if let p = src?.module(for: room)?.label, p.count >= 2 {
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
        guard edit != nil, let src = source else { return [] }
        return rooms.flatMap { room -> [(sel: HouseSelection, rect: CGRect)] in
            guard let m = src.module(for: room) else { return [] }
            return HouseEditSlots.targets(module: m, room: room).map { (sel: $0.sel, rect: $0.rect) }
        }
    }

    private func editLabelPositions(_ src: HouseSceneSource) -> [HouseSelection: CGPoint] {
        var items: [(sel: HouseSelection, rect: CGRect, labelAbove: Bool, text: String)] = []
        var obstacles: [CGRect] = [], roomLabels: [CGRect] = []
        for room in rooms {
            guard let m = src.module(for: room) else { continue }
            for t in HouseEditSlots.targets(module: m, room: room) {
                if let f = t.fixture {
                    let d = room.devices.first { $0.spot == t.sel.spot }
                    items.append((t.sel, t.rect, t.labelAbove, d?.name ?? HouseFixtureNames.title(f)))
                } else {
                    obstacles.append(t.rect)
                }
            }
            if showLabels, let p = m.label, p.count >= 2 {
                let sz = HouseEditSlots.labelSize(room.title, fontSize: 10)
                roomLabels.append(CGRect(x: p[0] - sz.width / 2, y: p[1] - sz.height / 2, width: sz.width, height: sz.height))
            }
        }
        return HouseEditSlots.labelPositions(items, obstacles: obstacles, fixedLabels: roomLabels, bounds: artSize)
    }

    private func art(_ img: NSImage) -> some View {
        Image(nsImage: img).interpolation(.none).resizable().frame(width: artSize.width, height: artSize.height)
    }
}

/// 空调送风：出风口下沿往前下方飘的几股像素点（2 px 格，和底图像素对齐），8 fps；坐标 = 底图像素。
/// 菜单栏面板 / 窗口关掉时视图不在层级里，TimelineView 自然停。
struct HouseAirflow: View {
    let a: CGPoint, b: CGPoint
    let dir: Double
    static let streams = 5, perStream = 6

    var body: some View {
        TimelineView(.periodic(from: .init(timeIntervalSinceReferenceDate: 0), by: 1.0 / 8)) { ctx in
            Canvas { g, _ in Self.draw(g, a: a, b: b, dir: dir, t: ctx.date.timeIntervalSinceReferenceDate) }
        }
    }

    /// 纯函数（同一时刻画出来一样），截图和测试都能复现
    static func particles(a: CGPoint, b: CGPoint, dir: Double, t: Double) -> [(CGPoint, Double)] {
        var out: [(CGPoint, Double)] = []
        for i in 0..<streams {
            let s = (Double(i) + 0.5) / Double(streams)
            let base = CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
            let seed = Double(i) * 0.37
            for j in 0..<perStream {
                // 0 → 1：从出风口飘出去、变淡
                var p = (t * 0.45 + Double(j) / Double(perStream) + seed).truncatingRemainder(dividingBy: 1)
                if p < 0 { p += 1 }
                let d = 4 + p * 26
                let wob = sin(t * 2.1 + Double(i) * 1.7 + p * 6) * 1.6
                let x = base.x + dir * d * 0.85 + wob
                let y = base.y + 2 + d * 0.9
                out.append((CGPoint(x: (x / 2).rounded(.down) * 2, y: (y / 2).rounded(.down) * 2), 0.3 + (1 - p) * 0.65))
            }
        }
        return out
    }

    static func draw(_ g: GraphicsContext, a: CGPoint, b: CGPoint, dir: Double, t: Double) {
        let col = Color(red: 0.70, green: 0.92, blue: 1.0)
        for (p, alpha) in particles(a: a, b: b, dir: dir, t: t) {
            g.fill(Path(CGRect(x: p.x, y: p.y, width: 2, height: 2)), with: .color(col.opacity(alpha)))
        }
    }
}

/// 单个房间：每盏开着的灯按「房间多边形 ∩ 灯具蒙版」露出 lit 底图；关着的灯具本体用 unlit 盖回去。
private struct HouseFloorApplianceLayer: View {
    let module: HouseCutawayModule
    let devices: [HouseDevice]
    let phase: HousePhase
    let artSize: CGSize

    var body: some View {
        // 必须用 Canvas，独立 Image 视图无法合成到 cacheDisplay 截图。
        Canvas { context, _ in
            for light in module.lights where light.isFloorAppliance && light.hidden != true {
                if let device = light.matchedDevice(in: devices), let anchor = light.floorAnchor,
                   let image = HouseAssets.fixture(role: light.role, on: device.on && device.online),
                   let sprite = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    if device.on && device.online {
                        let glow = light.role == "heater" ? Color(red: 1, green: 0.6, blue: 0.3) : Color(red: 0.55, green: 0.9, blue: 1)
                        var glowContext = context
                        glowContext.translateBy(x: anchor.x, y: anchor.y)
                        glowContext.scaleBy(x: (image.size.width + 20) / 2, y: 6)
                        glowContext.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
                                         with: .radialGradient(Gradient(colors: [glow.opacity(phase == .night ? 0.65 : 0.35), glow.opacity(0)]),
                                                               center: .zero, startRadius: 0, endRadius: 1))
                    }
                    var spriteContext = context
                    spriteContext.opacity = device.online ? 1 : 0.45
                    spriteContext.draw(Image(decorative: sprite, scale: 1).interpolation(.none),
                                       in: CGRect(x: anchor.x - image.size.width / 2, y: anchor.y - image.size.height,
                                                  width: image.size.width, height: image.size.height))
                }
            }
        }
        .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct HouseRoomLightLayer: View {
    let module: HouseCutawayModule
    let devices: [HouseDevice]
    let lighting: RoomLighting
    let lit: NSImage
    let unlit: NSImage
    let artSize: CGSize
    var phase: HousePhase = .night
    var style: String? = nil
    var onToggle: ((String) -> Void)?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(module.lights.filter(\.bakesLight)) { light in
                let k = light.strength(lighting)
                if let reveal = light.reveal {
                    image(lit)
                        .mask(revealMask(reveal))
                        .opacity(k)
                        .animation(Motion.smooth, value: k)
                }
                // 灯具本体（灯罩 / 屏幕）一定亮：合成场景的电视 reveal 只是地上的椭圆，盖不到抬高的屏幕
                if let core = light.corePolygon {
                    image(lit)
                        .mask(HousePolygon(points: core).fill(Color.white))
                        .opacity(k)
                        .animation(Motion.smooth, value: k)
                }
            }
            ForEach(module.lights) { light in
                if let core = light.corePolygon {
                    let k = light.strength(lighting)
                    image(unlit)
                        .mask(HousePolygon(points: core).fill(Color.white))
                        .opacity(1 - k)
                        .animation(Motion.smooth, value: k)
                }
            }
            ForEach(module.lights.filter { $0.shouldShowAbsentVariant(in: devices) }) { light in
                if let variant = light.absentVariant, variant.rect.count == 4,
                   let patch = HouseAssets.absentPatch(variant.patch, phase: phase, lit: false, style: style) {
                    ZStack(alignment: .topLeading) {
                        absentPatch(patch, rect: variant.rect)
                        if let litPatch = HouseAssets.absentPatch(variant.patch, phase: phase, lit: true, style: style) {
                            ForEach(module.lights.filter { $0.bakesLight && $0.id != light.id }) { source in
                                let strength = source.strength(lighting)
                                if strength > 0, let reveal = source.reveal {
                                    absentPatch(litPatch, rect: variant.rect)
                                        .mask(revealMask(reveal))
                                        .opacity(strength)
                                }
                            }
                        }
                    }
                    .mask(HouseMultiPolygon(polygons: module.visible ?? [module.region]).fill(Color.white, style: FillStyle(eoFill: true)))
                    .allowsHitTesting(false)
                }
            }
            // 空调送风：动态像素粒子（不烘焙进 lit——同屋的灯开着时 lit 会把烘焙的送风也露出来）
            ForEach(module.lights) { light in
                if light.kind == "ac", light.hidden != true, let v = light.vent, v.count == 2 {
                    let k = light.strength(lighting)
                    if k > 0 {
                        HouseAirflow(a: CGPoint(x: v[0][0], y: v[0][1]), b: CGPoint(x: v[1][0], y: v[1][1]), dir: light.flowDirection)
                            .frame(width: artSize.width, height: artSize.height)
                            .opacity(k)
                            .allowsHitTesting(false)
                    }
                }
            }
            // 窗帘：关合贴片盖住窗户（按开合度只露两侧）；白天关着时房间暗一点（挡住了窗外光）
            ForEach(module.lights.filter { $0.role == "curtain" && $0.hidden != true }) { light in
                if let dev = light.matchedDevice(in: devices), dev.curtainOpen < 0.995,
                   let name = light.patch, let r = light.rect, r.count == 4, let q = light.quad, q.count == 4,
                   let img = HouseAssets.curtainPatch(name, phase: phase, lit: false, style: style) {
                    let closed = 1 - dev.curtainOpen
                    let x0 = q[0][0], x1 = q[1][0], mid = light.mid ?? (q[0][0] + q[1][0]) / 2
                    if phase == .day {
                        HouseMultiPolygon(polygons: module.visible ?? [module.region])
                            .fill(Color(red: 0.08, green: 0.05, blue: 0.02).opacity(0.13 * closed), style: FillStyle(eoFill: true))
                            .allowsHitTesting(false)
                    }
                    ZStack(alignment: .topLeading) {
                        HouseCurtainPatch(image: img, rect: r, x0: x0, x1: x1, mid: mid, closed: closed)
                            .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
                        // 被灯照到的部分换成 lit 贴片：和底图一样按每盏灯的 reveal 蒙版 × 亮度叠上去，颜色和周围一致
                        if let litImg = HouseAssets.curtainPatch(name, phase: phase, lit: true, style: style) {
                            ForEach(module.lights.filter(\.bakesLight)) { l in
                                let k = l.strength(lighting)
                                if k > 0, let rv = l.reveal {
                                    HouseCurtainPatch(image: litImg, rect: r, x0: x0, x1: x1, mid: mid, closed: closed)
                                        .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
                                        .mask(revealMask(rv))
                                        .opacity(k)
                                }
                            }
                        }
                    }
                        .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
                        .mask(HouseMultiPolygon(polygons: module.visible ?? [module.region]).fill(Color.white, style: FillStyle(eoFill: true)))
                        .animation(.easeInOut(duration: 0.6), value: closed)
                        .allowsHitTesting(false)
                }
            }
            // 冰箱 / 热水器 / 洗衣机：显示屏、指示灯、火光、滚筒动画（状态动态画，不烘焙）
            ForEach(module.lights.filter { ["fridge", "water-heater", "washer"].contains($0.role) && $0.hidden != true }) { light in
                if let dev = light.matchedDevice(in: devices) {
                    HouseApplianceOverlay(light: light, on: dev.on && dev.online, busy: dev.busy, online: dev.online, phase: phase)
                        .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
                        .mask(HouseMultiPolygon(polygons: module.visible ?? [module.region]).fill(Color.white, style: FillStyle(eoFill: true)))
                        .allowsHitTesting(false)
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

    private func absentPatch(_ image: NSImage, rect: [Double]) -> some View {
        Image(nsImage: image).resizable().interpolation(.none)
            .frame(width: rect[2], height: rect[3])
            .offset(x: rect[0], y: rect[1])
            .frame(width: artSize.width, height: artSize.height, alignment: .topLeading)
    }

    /// 不用 .blur：--house-snapshot 走 cacheDisplay，图层滤镜不会被渲染；羽化用渐变代替。
    @ViewBuilder private func revealMask(_ r: HouseReveal) -> some View {
        let room = HouseMultiPolygon(polygons: module.visible ?? [module.region]).fill(Color.white, style: FillStyle(eoFill: true))
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
            // 合成场景里被切掉的墙挂设备（空调）：本体不在了，在 alt 地面点画成徽章
            ForEach(module.lights.filter { $0.hidden == true && ($0.alt?.count ?? 0) >= 2 }) { light in
                if let d = room.devices.first(where: { $0.spot == .fixture(light.id) }), let p = light.alt {
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
        case .ac, .fan, .airPurifier, .purifier, .dehumidifier, .humidifier, .vacuum: return Color(red: 0.55, green: 0.9, blue: 1)
        case .heater, .kitchen, .waterHeater: return Color(red: 1, green: 0.6, blue: 0.3)
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
        .animation(Motion.smooth, value: device.on)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// 多个多边形（合成场景的 visible 区域：本模块减去前方房间）
struct HouseMultiPolygon: Shape {
    let polygons: [[[Double]]]
    func path(in r: CGRect) -> Path {
        var p = Path()
        for poly in polygons { p.addPath(HousePolygon(points: poly).path(in: r)) }
        return p
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
        if let poly = light.hitPolygon, poly.count >= 3 {
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
    @EnvironmentObject var m: AppModel
    var rooms: [HouseRoom]
    var phase: HousePhase = .from()
    var showChrome = true
    var onToggle: ((String) -> Void)? = nil
    var edit: HouseEditContext? = nil
    /// 标题栏的白天 / 夜间、设备已开标签（编辑模式下按钮多，隐藏）
    var showStatus = true
    /// 标题栏右侧的按钮（「编辑」/「恢复自动」「完成」）
    var accessory: AnyView? = nil
    /// 自定义布局 → 模块合成图
    var layout: [HouseLayoutCell]? = nil

    private let sceneWidth: CGFloat = 660

    var body: some View {
        VStack(spacing: 0) {
            if showChrome { header }
            if rooms.isEmpty {
                Text(L("这个家里还没有能放进小屋的房间", "No rooms for the house view yet"))
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: sceneWidth, height: 200)
            } else {
                HouseCutawaySceneView(rooms: rooms, phase: phase, showLabels: true, fitWidth: showChrome ? sceneWidth : nil,
                                      onToggle: onToggle, edit: edit, layout: layout, style: m.houseStyle, decorConfig: m.house.homes[m.houseHomeKey] ?? HomeHouse())
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
    static let petsRestOnly = true
    var snapshotDate: Date? = nil
    var snapshotPhase: HousePhase? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let rooms = m.houseRooms
            if !rooms.isEmpty {
                let phase = snapshotPhase ?? HousePhase.from(date: snapshotDate ?? ctx.date)
                VStack(alignment: .leading, spacing: 6) {
                    embedChrome(phase: phase, cozy: rooms.contains { $0.lighting.cozy > 0.35 })
                    if contentWidth > 0 {
                        cutaway(rooms: rooms, phase: phase, width: contentWidth)
                    }
                    HouseDeviceChipRow(rooms: rooms, onToggle: { did in
                        guard let d = m.device(did) else { return }
                        withoutAnimation { m.toggle(d) }
                    }, topPadding: 4)
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
                .help(cozy ? L("设备已开", "Devices on") : L("已关灯", "Lights off"))
                .accessibilityLabel(cozy ? L("设备已开", "Devices on") : L("已关灯", "Lights off"))
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
            .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
            .compositingGroup()
        }
        .buttonStyle(.plain).hoverHighlight()
        .help(L("在窗口中打开小屋", "Open house in a window"))
        .accessibilityLabel(L("放大", "Enlarge"))
    }

    private func cutaway(rooms: [HouseRoom], phase: HousePhase, width: CGFloat) -> some View {
        HouseCutawaySceneView(rooms: rooms, phase: phase, showLabels: false, fitWidth: width, onToggle: { did in
            guard let d = m.device(did) else { return }
            withoutAnimation { m.toggle(d) }
        }, layout: m.houseLayoutCells, style: m.houseStyle, decorConfig: m.house.homes[m.houseHomeKey] ?? HomeHouse(), petsRestOnly: Self.petsRestOnly, petDate: snapshotDate)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke))
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
            .overlay(Capsule().strokeBorder(on ? tint.opacity(0.35) : Theme.stroke, lineWidth: 1))
            .compositingGroup()
        }
        .buttonStyle(.plain).hoverHighlight()
    }
}

// MARK: - 窗口

@MainActor
enum HouseWindow {
    private static var window: NSWindow?
    private static var closeObserver: NSObjectProtocol?

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
        // 关窗时移除观察者，否则每开关一次窗口就多留一个（还持有 model）
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated {
                window?.contentView = nil; window = nil; model.houseUndo.clear(); model.houseNotice = nil
                if let o = closeObserver { NotificationCenter.default.removeObserver(o); closeObserver = nil }
            }
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

enum HouseEditTab: String, CaseIterable { case devices, arrange, style, pets }

struct HousePilotHost: View {
    @EnvironmentObject var m: AppModel
    @State var editing = false
    @State var selection: HouseSelection?
    @State var drag = HouseDragState()
    @State var editTab: HouseEditTab = .devices
    var decorDate: Date? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let rooms = m.houseRooms
            let phase = HousePhase.from(date: ctx.date)
            if editing {
                VStack(spacing: 0) {
                    HStack {
                        Picker("", selection: $editTab) {
                            Text(L("设备", "Devices")).tag(HouseEditTab.devices)
                            Text(L("房间布局", "Room layout")).tag(HouseEditTab.arrange)
                            Text(L("风格与装饰", "Style & decor")).tag(HouseEditTab.style)
                            Text(L("宠物", "Pets")).tag(HouseEditTab.pets)
                        }.pickerStyle(.segmented).frame(width: 460)
                        Spacer()
                        editButtons
                    }
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    Divider()
                    if editTab == .arrange {
                        HouseArrangeView()
                    } else if editTab == .style {
                        HouseStyleView(date: decorDate ?? ctx.date)
                    } else if editTab == .pets {
                        HousePetsEditor(date: decorDate)
                    } else {
                        let resolved = m.houseResolved
                        let edit = context(resolved)
                        HStack(alignment: .top, spacing: 0) {
                            VStack(alignment: .leading, spacing: 0) {
                                HouseFullView(rooms: rooms, phase: phase, onToggle: nil, edit: edit, showStatus: false, accessory: nil, layout: m.houseLayoutCells)
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
                    }
                }
            } else {
                HouseFullView(rooms: rooms, phase: phase, onToggle: { did in
                    guard let d = m.device(did) else { return }
                    withoutAnimation { m.toggle(d) }
                }, accessory: AnyView(editButton), layout: m.houseLayoutCells)
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
            Button(L("恢复自动", "Reset to automatic")) {
                selection = nil
                if editTab == .style { m.houseEdit(L("恢复自动", "Reset to automatic")) { $0.resetDecor(home: m.houseHomeKey) } }
                else { m.houseResetAll() }
            }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(m.house.homes[m.houseHomeKey].map { h in
                    editTab == .style ? (h.decor ?? [:]).values.allSatisfy { $0.item == nil }
                        : h.devices.values.allSatisfy(\.isEmpty) && h.rooms.values.allSatisfy { $0.module == nil }
                } ?? true)
            Button(L("完成", "Done")) { selection = nil; drag = HouseDragState(); editing = false; HouseWindow.resize(editing: false) }
                .buttonStyle(.borderedProminent).controlSize(.small).keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - CLI

extension Snapshot {
    /// 客厅空调开 / 关（其余照演示状态）
    static func acPair(_ rooms: [HouseRoom]) -> [(String, HousePhase, [HouseRoom])] {
        func onIds(_ r: HouseRoom) -> Set<String> {
            Set(r.devices.compactMap { d -> String? in if case .fixture(let id)? = d.spot, d.on { return id }; return nil })
        }
        let on = rooms.map { $0.module == .living ? $0.lit(onIds($0).union(["ac"]), badgesOn: false) : $0 }
        let off = rooms.map { $0.module == .living ? $0.lit(onIds($0).subtracting(["ac"]), badgesOn: false) : $0 }
        return [("house-day-ac-on", .day, on), ("house-day-ac-off", .day, off), ("house-night-ac-on", .night, on), ("house-night-ac-off", .night, off)]
    }

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
            ("house-night-partial", .night, rooms),   // 演示数据的真实状态：客厅落地灯 + 电视 + 墙上空调
            ("house-day-partial", .day, rooms),
            ("house-night-onelamp", .night, oneLamp),
            ("house-night-twolamps", .night, twoLamps),
        ] + acPair(rooms)
        for (name, phase, rs) in exports + partial {
            render(HouseCutawaySceneView(rooms: rs, phase: phase, showLabels: false), out.appendingPathComponent("\(name).png"),
                   size: CGSize(width: 960, height: 540))
        }
        exit(0)
    }
}


// MARK: - 窗帘 / 家电的动态状态

/// 窗帘关合贴片：左右两半从外侧往中间拉，closed = 0（全开，不画）..1（全关）。
/// 墙面竖线在 iso 里仍是竖线，所以按 x 裁就是沿墙裁；裁边对齐 2px 像素格。
struct HouseCurtainPatch: View {
    let image: NSImage
    let rect: [Double]
    let x0: Double, x1: Double, mid: Double
    let closed: Double

    static func visibleRanges(x0: Double, x1: Double, mid: Double, closed: Double) -> [ClosedRange<Double>] {
        HouseDeviceState.curtainVisibleRanges(x0: x0, x1: x1, mid: mid, closed: closed)
    }

    var body: some View {
        let ranges = Self.visibleRanges(x0: x0, x1: x1, mid: mid, closed: closed)
        Image(nsImage: image).interpolation(.none).resizable()
            .frame(width: rect[2], height: rect[3])
            .mask(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(ranges.enumerated()), id: \.offset) { _, rg in
                        Rectangle().frame(width: max(0, rg.upperBound - rg.lowerBound), height: rect[3])
                            .offset(x: rg.lowerBound - rect[0])
                    }
                }
                .frame(width: rect[2], height: rect[3], alignment: .topLeading)
            }
            .offset(x: rect[0], y: rect[1])
    }
}

/// 冰箱 / 热水器 / 洗衣机的显示屏、指示灯、热水器火光、洗衣机滚筒里转动的衣物（2px 像素格，8 fps）
struct HouseApplianceOverlay: View {
    let light: HouseLightSpec
    let on: Bool, busy: Bool, online: Bool
    let phase: HousePhase

    private var animated: Bool { on && busy && (light.role == "washer" || light.role == "water-heater") }

    var body: some View {
        if animated {
            TimelineView(.periodic(from: .init(timeIntervalSinceReferenceDate: 0), by: 1.0 / 8)) { ctx in
                Canvas { g, _ in Self.draw(g, light: light, on: on, busy: busy, phase: phase, t: ctx.date.timeIntervalSinceReferenceDate) }
            }
        } else {
            Canvas { g, _ in Self.draw(g, light: light, on: on, busy: busy, phase: phase, t: 0) }
        }
    }

    static let screenOff = Color(red: 0.10, green: 0.12, blue: 0.14)
    static func displayColor(role: String, on: Bool, busy: Bool) -> Color? {
        guard on else { return screenOff }
        switch role {
        case "fridge": return Color(red: 0.55, green: 0.92, blue: 1.0)
        case "water-heater": return busy ? Color(red: 1.0, green: 0.55, blue: 0.16) : Color(red: 0.45, green: 0.75, blue: 1.0)
        case "washer": return Color(red: 0.5, green: 1.0, blue: 0.72)
        default: return nil
        }
    }

    static func cell(_ x: Double, _ y: Double) -> CGRect { CGRect(x: (x / 2).rounded(.down) * 2, y: (y / 2).rounded(.down) * 2, width: 2, height: 2) }

    /// 洗衣机滚筒里的衣物：门面坐标（px）里绕圆心转的几块颜色，纯函数（截图 / 测试可复现）
    static func drumCells(door: HouseDoor, t: Double) -> [(CGRect, Color)] {
        let cols: [Color] = [Color(red: 0.95, green: 0.55, blue: 0.45), Color(red: 0.55, green: 0.75, blue: 1.0),
                             Color(red: 0.98, green: 0.92, blue: 0.7), Color(red: 0.6, green: 0.9, blue: 0.6)]
        var out: [(CGRect, Color)] = []
        let r = door.r - 1.6
        let ky = door.ry.map { ($0 - 1.6) / max(0.5, r) } ?? 1   // 门玻璃竖向半径 / 横向半径
        for i in 0..<4 {
            let a = t * 2.6 + Double(i) * .pi / 2
            let rr = r * (i % 2 == 0 ? 0.75 : 0.45)
            let fx = cos(a) * rr, fy = sin(a) * rr * ky
            let x = door.c[0] + door.s[0] * fx + door.t[0] * fy
            let y = door.c[1] + door.s[1] * fx + door.t[1] * fy
            out.append((cell(x, y), cols[i]))
        }
        // 泡沫：门下半圈
        for k in 0..<2 {
            let fx = (Double(k) - 0.5) * r * 0.9, fy = -r * 0.7 * ky + sin(t * 5 + Double(k)) * 0.8
            out.append((cell(door.c[0] + door.s[0] * fx + door.t[0] * fy, door.c[1] + door.s[1] * fx + door.t[1] * fy), Color.white.opacity(0.85)))
        }
        return out
    }

    static func draw(_ g: GraphicsContext, light: HouseLightSpec, on: Bool, busy: Bool, phase: HousePhase, t: Double) {
        let night = phase == .night
        if let d = light.display, d.count >= 3, let col = displayColor(role: light.role, on: on, busy: busy) {
            let path = HousePolygon(points: d).path(in: .zero)
            if on {
                // 屏幕的光晕
                let b = path.boundingRect
                let glow = CGRect(x: b.midX - b.width * 0.9, y: b.midY - b.height * 1.1, width: b.width * 1.8, height: b.height * 2.2)
                g.fill(Path(ellipseIn: glow), with: .radialGradient(Gradient(colors: [col.opacity(night ? 0.38 : 0.18), col.opacity(0)]),
                                                                    center: CGPoint(x: b.midX, y: b.midY), startRadius: 0, endRadius: max(glow.width, glow.height) / 2))
            }
            g.fill(path, with: .color(col))
            if light.role == "water-heater", on, busy {
                // 火光：显示窗里几格黄 / 红随机闪
                let b = path.boundingRect
                let seed = Int(t * 8)
                var g = g; g.clip(to: path)   // 圆形表盘：火光格不出表盘
                for i in 0..<3 {
                    let h = (seed &* 31 &+ i &* 17) % 7
                    let x = b.minX + 1 + Double((h * 5 + i * 3) % max(1, Int(b.width) - 2))
                    let y = b.minY + 2 + Double((h + i * 2) % max(1, Int(b.height) - 3))
                    g.fill(Path(cell(x, y)), with: .color(i == 0 ? Color(red: 1, green: 0.95, blue: 0.55) : Color(red: 1, green: 0.78, blue: 0.3)))
                }
            } else if light.role == "fridge", on {
                // 温度数字的两格暗点
                let b = path.boundingRect
                g.fill(Path(cell(b.minX + 1, b.minY + 2)), with: .color(Color(red: 0.2, green: 0.45, blue: 0.6)))
            }
        }
        if let p = light.led, p.count >= 2, on {
            let c = light.role == "water-heater" && busy ? Color(red: 1, green: 0.35, blue: 0.25) : Color(red: 0.45, green: 1, blue: 0.6)
            g.fill(Path(cell(p[0], p[1])), with: .color(c))
        }
        if light.role == "washer", on, busy, let door = light.door {
            for (r, c) in drumCells(door: door, t: t) { g.fill(Path(r), with: .color(c)) }
        }
    }
}
