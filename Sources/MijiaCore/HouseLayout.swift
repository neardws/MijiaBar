import Foundation

/// 「小屋」视图的布局：固定的像素房间模块，按米家房间名自动匹配；每个模块有固定的灯具位（带烘焙局部光）和徽章位。
/// 用户不需要画户型。自动结果可以被 house.json 里的覆盖项改写（见 HouseStore.swift、docs/HOUSE.md）。
public enum HouseModule: String, CaseIterable, Codable, Sendable {
    case living, bedroom, study, kitchen, bathroom, balcony, generic

    /// 按房间名匹配模块（简繁英都认）；认不出的是 generic
    public static func from(roomName: String?) -> HouseModule {
        let n = (roomName ?? "").lowercased()
        func has(_ ks: [String]) -> Bool { ks.contains { n.contains($0) } }
        if has(["客厅", "客廳", "起居", "living", "lounge"]) { return .living }
        if has(["卧", "臥", "睡房", "儿童房", "兒童房", "客房", "bedroom", "kids", "guest room"]) { return .bedroom }
        if has(["书房", "書房", "办公", "辦公", "工作室", "study", "office"]) { return .study }
        if has(["厨房", "廚房", "kitchen"]) { return .kitchen }
        if has(["卫生间", "衛生間", "洗手间", "洗手間", "浴室", "卫浴", "衛浴", "厕所", "廁所", "bath", "toilet", "washroom", "restroom"]) { return .bathroom }
        if has(["阳台", "陽台", "露台", "balcony", "terrace"]) { return .balcony }
        return .generic
    }

    /// 玄关 / 门口类房间用 generic 模块（玄关样式）展示
    public static func isEntryFoyer(roomName: String?) -> Bool {
        let n = (roomName ?? "").lowercased()
        return ["门口", "門口", "玄关", "玄關", "entry", "entrance", "foyer", "hall", "走廊"].contains { n.contains($0) }
    }

    /// Phase 1 只有这 4 个模块有素材（整张剖面里的固定位置）；厨房 / 卫生间 / 阳台在 Phase 2 补
    public var hasArt: Bool { HouseCatalog.artModules.contains(self) }

    public var assetPrefix: String {
        switch self {
        case .living: return "living-room"
        default: return rawValue
        }
    }

    public var title: String {
        switch self {
        case .living: return L("客厅", "Living room")
        case .bedroom: return L("卧室", "Bedroom")
        case .study: return L("书房", "Study")
        case .kitchen: return L("厨房", "Kitchen")
        case .bathroom: return L("卫生间", "Bathroom")
        case .balcony: return L("阳台", "Balcony")
        case .generic: return L("玄关", "Entry")
        }
    }
}

/// 灯具位：素材里画好、烘焙了局部光的灯 / 屏幕 / 空调。id 稳定（house.json 和 house-cutaway.json 都用它）。
public struct HouseFixture: Hashable, Sendable {
    public let id: String
    public let accepts: Set<DeviceCategory>
    /// 设备名包含这些词时优先放进这个位置（例：「床头灯」→ bedside）
    public let hints: [String]
    /// 只有名字命中 hints 才自动放（例：显示器位不能自动放一台电视）
    public let hintRequired: Bool
    public init(_ id: String, _ accepts: Set<DeviceCategory>, hints: [String] = [], hintRequired: Bool = false) {
        self.id = id; self.accepts = accepts; self.hints = hints; self.hintRequired = hintRequired
    }
    public func accepts(_ c: DeviceCategory) -> Bool { accepts.contains(c) }
    public func hinted(_ name: String) -> Bool { let n = name.lowercased(); return hints.contains { n.contains($0) } }
}

public enum HouseCatalog {
    public static let artModules: [HouseModule] = [.living, .bedroom, .study, .generic]

    /// 与 Resources/House/house-cutaway.json 的 lights[].id 一一对应（单元测试会检查）
    public static func fixtures(_ m: HouseModule) -> [HouseFixture] {
        switch m {
        case .living: return [
            HouseFixture("floor_lamp", [.light], hints: ["落地", "floor", "台灯", "檯燈", "lamp"]),
            HouseFixture("sconce", [.light], hints: ["壁灯", "壁燈", "wall", "sconce"]),
            HouseFixture("tv", [.tv], hints: ["电视", "電視", "tv", "投影", "projector"]),
        ]
        case .bedroom: return [
            HouseFixture("bedside", [.light], hints: ["床头", "床頭", "台灯", "檯燈", "bedside", "nightstand", "lamp"]),
            HouseFixture("ac", [.ac]),
        ]
        case .study: return [
            HouseFixture("ceiling", [.light], hints: ["吸顶", "吸頂", "主灯", "主燈", "顶灯", "頂燈", "ceiling"]),
            HouseFixture("monitor", [.light, .tv, .other], hints: ["显示器", "顯示器", "屏幕", "螢幕", "挂灯", "掛燈", "monitor", "display", "screen"], hintRequired: true),
        ]
        case .generic: return [
            HouseFixture("entry_light", [.light]),
        ]
        // 下面三个只有 Phase 2 模块美术（自定义布局合成）；经典整图里没有，hasArt 仍为 false
        case .kitchen: return [
            HouseFixture("pendant", [.light], hints: ["吊灯", "吊燈", "餐", "pendant", "dining"]),
        ]
        case .bathroom: return [
            HouseFixture("ceiling", [.light], hints: ["吸顶", "吸頂", "镜", "鏡", "ceiling", "mirror"]),
        ]
        case .balcony: return [
            HouseFixture("wall_lamp", [.light], hints: ["壁灯", "壁燈", "wall"]),
        ]
        }
    }

    public static func fixture(_ m: HouseModule, _ id: String) -> HouseFixture? { fixtures(m).first { $0.id == id } }

    /// 徽章位：没有专属灯具的设备（风扇、插座、净化器、传感器……）用像素小图标放在地上
    public static func badgeCount(_ m: HouseModule) -> Int {
        switch m {
        case .living: return 4
        case .bedroom: return 3
        case .study: return 3
        case .generic: return 3
        case .kitchen, .bathroom, .balcony: return 3
        }
    }
    public static func badgeIds(_ m: HouseModule) -> [String] { (0..<badgeCount(m)).map { "b\($0 + 1)" } }

    /// 能进小屋的设备类型（other 认不出是什么，不画）
    public static func showable(_ c: DeviceCategory) -> Bool { c != .other }
}

/// 设备在小屋里的位置
public enum HouseSpot: Hashable, Sendable {
    case fixture(String)
    case badge(String)
    public var id: String { switch self { case .fixture(let s): return s; case .badge(let s): return s } }
}

public struct ResolvedHouseDevice: Hashable, Sendable {
    public let did: String
    public let name: String
    public let category: DeviceCategory
    public let online: Bool
    /// nil = 只在设备按钮行出现（位置满了，或用户设成 none）
    public let spot: HouseSpot?
    /// 用户在 house.json 里指定过位置
    public let pinned: Bool
}

public struct ResolvedHouseRoom: Hashable, Sendable, Identifiable {
    public var id: String { key }
    public let key: String
    public let title: String
    public let module: HouseModule
    public let devices: [ResolvedHouseDevice]
    public var placed: [ResolvedHouseDevice] { devices.filter { $0.spot != nil } }
    public var chipsOnly: [ResolvedHouseDevice] { devices.filter { $0.spot == nil } }
    public func device(at spot: HouseSpot) -> ResolvedHouseDevice? { devices.first { $0.spot == spot } }
}

public struct ExcludedHouseRoom: Hashable, Sendable, Identifiable {
    public enum Reason: String, Sendable {
        case noArt          // 模块还没有素材（厨房 / 卫生间 / 阳台 / 其他房间）
        case spotTaken      // 同类模块已经放了另一个房间
        case excluded       // 用户设成不放进小屋
        case unassigned     // 米家里没分配房间
        case notInLayout    // 自定义布局里没放这个房间
    }
    public var id: String { key }
    public let key: String
    public let title: String
    public let module: HouseModule
    public let reason: Reason
    public let deviceCount: Int
}

public struct ResolvedHouse: Hashable, Sendable {
    public let rooms: [ResolvedHouseRoom]
    public let excluded: [ExcludedHouseRoom]
    /// 不在小屋里显示的设备（列表里隐藏，或 house.json 里 visible = false）
    public let hidden: [String]
    public static let empty = ResolvedHouse(rooms: [], excluded: [], hidden: [])
}

/// 自动布局 + 用户覆盖 → 最终小屋。纯函数：同样的输入一定得到同样的结果（不依赖列表顺序）。
public enum HouseResolver {
    /// 房间 key：米家房间 id；没有 id 时用 "name:<房间名>"；没分配房间是 ""
    public static func roomKey(_ d: Device) -> String {
        if let id = d.roomId, !id.isEmpty { return id }
        if let n = d.roomName, !n.isEmpty { return "name:" + n }
        return ""
    }

    /// `layout`：用户自定义布局（非经典四室）。给了就走模块合成：布局里的每个格子就是一个房间（模块按格子），
    /// 7 种模块都有素材；不在布局里的房间记为 notInLayout。nil = 经典四室整图（每种模块一个位置）。
    public static func resolve(devices: [Device], config: HomeHouse?, isHidden: (Device) -> Bool, name: (Device) -> String,
                               layout: [HouseLayoutCell]? = nil) -> ResolvedHouse {
        if let layout, !HouseLayoutSolver.isClassicGeometry(layout) {
            return resolveComposed(devices: devices, config: config ?? HomeHouse(), layout: layout, isHidden: isHidden, name: name)
        }
        let cfg = config ?? HomeHouse()
        let groups = Dictionary(grouping: devices, by: roomKey)
        var hidden: [String] = []

        func visible(_ d: Device) -> Bool {
            if let v = cfg.devices[d.did]?.visible { return v }
            return !isHidden(d)
        }
        func roomOverride(_ key: String, _ sample: Device?) -> HouseRoomOverride? {
            if let o = cfg.rooms[key], o.module != nil { return o }
            if let n = sample?.roomName, let o = cfg.rooms["name:" + n], o.module != nil { return o }   // 旧 key 兼容
            return nil
        }

        struct Cand { let key: String; let title: String; let module: HouseModule; let pinned: Bool; let score: Int; let count: Int }
        var cands: [Cand] = []
        var excluded: [ExcludedHouseRoom] = []
        for (key, ds) in groups {
            let title = ds.first?.roomName.flatMap { $0.isEmpty ? nil : $0 } ?? L("未分配房间", "Unassigned")
            let shown = ds.filter { visible($0) && HouseCatalog.showable($0.category) }
            let o = roomOverride(key, ds.first)
            if o?.module == "none" {
                excluded.append(.init(key: key, title: title, module: HouseModule.from(roomName: ds.first?.roomName), reason: .excluded, deviceCount: shown.count))
                continue
            }
            let mod: HouseModule
            if let raw = o?.module, let m = HouseModule(rawValue: raw) { mod = m }
            else if key.isEmpty {
                excluded.append(.init(key: key, title: title, module: .generic, reason: .unassigned, deviceCount: shown.count)); continue
            } else {
                let n = ds.first?.roomName
                let m = HouseModule.from(roomName: n)
                if m == .generic && !HouseModule.isEntryFoyer(roomName: n) {
                    excluded.append(.init(key: key, title: title, module: .generic, reason: .noArt, deviceCount: shown.count)); continue
                }
                mod = m
            }
            guard mod.hasArt else {
                excluded.append(.init(key: key, title: title, module: mod, reason: .noArt, deviceCount: shown.count)); continue
            }
            let fits = shown.filter { d in HouseCatalog.fixtures(mod).contains { $0.accepts(d.category) } }.count
            cands.append(Cand(key: key, title: title, module: mod, pinned: o != nil, score: fits * 100 + shown.count, count: shown.count))
        }

        // 每个模块位置只放一个房间：手动指定的优先，其次能放进灯具位的设备多的，最后按 key
        var rooms: [ResolvedHouseRoom] = []
        for mod in HouseCatalog.artModules {
            let cs = cands.filter { $0.module == mod }.sorted {
                if $0.pinned != $1.pinned { return $0.pinned }
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.key < $1.key
            }
            guard let win = cs.first else { continue }
            for c in cs.dropFirst() { excluded.append(.init(key: c.key, title: c.title, module: mod, reason: .spotTaken, deviceCount: c.count)) }
            let ds = groups[win.key] ?? []
            for d in ds where !visible(d) { hidden.append(d.did) }
            rooms.append(ResolvedHouseRoom(key: win.key, title: win.title, module: mod,
                                           devices: place(ds.filter { visible($0) && HouseCatalog.showable($0.category) }, in: mod, cfg: cfg, name: name)))
        }
        // 没进小屋的房间里，用户明确隐藏的设备也报告出来
        for e in excluded { for d in groups[e.key] ?? [] where !visible(d) { hidden.append(d.did) } }

        excluded.sort { ($0.reason.rawValue, $0.title, $0.key) < ($1.reason.rawValue, $1.title, $1.key) }
        return ResolvedHouse(rooms: rooms, excluded: excluded, hidden: hidden.sorted())
    }

    static func resolveComposed(devices: [Device], config cfg: HomeHouse, layout: [HouseLayoutCell],
                                isHidden: (Device) -> Bool, name: (Device) -> String) -> ResolvedHouse {
        let groups = Dictionary(grouping: devices, by: roomKey)
        func visible(_ d: Device) -> Bool {
            if let v = cfg.devices[d.did]?.visible { return v }
            return !isHidden(d)
        }
        var hidden: [String] = []
        var rooms: [ResolvedHouseRoom] = []
        var seen: Set<String> = []
        for cell in layout.sorted(by: { ($0.row, $0.col) < ($1.row, $1.col) }) {
            guard !cell.room.isEmpty, !seen.contains(cell.room), cfg.rooms[cell.room]?.module != "none" else { continue }
            seen.insert(cell.room)
            let ds = groups[cell.room] ?? []
            let mod = HouseModule(rawValue: cell.module) ?? .generic
            let title = ds.first?.roomName.flatMap { $0.isEmpty ? nil : $0 }
                ?? (cell.room.hasPrefix("name:") ? String(cell.room.dropFirst(5)) : mod.title)
            for d in ds where !visible(d) { hidden.append(d.did) }
            rooms.append(ResolvedHouseRoom(key: cell.room, title: title, module: mod,
                                           devices: place(ds.filter { visible($0) && HouseCatalog.showable($0.category) }, in: mod, cfg: cfg, name: name)))
        }
        var excluded: [ExcludedHouseRoom] = []
        for (key, ds) in groups where !seen.contains(key) {
            let title = ds.first?.roomName.flatMap { $0.isEmpty ? nil : $0 } ?? L("未分配房间", "Unassigned")
            let shown = ds.filter { visible($0) && HouseCatalog.showable($0.category) }
            let reason: ExcludedHouseRoom.Reason = key.isEmpty ? .unassigned : cfg.rooms[key]?.module == "none" ? .excluded : .notInLayout
            excluded.append(.init(key: key, title: title, module: HouseModule.from(roomName: ds.first?.roomName), reason: reason, deviceCount: shown.count))
            for d in ds where !visible(d) { hidden.append(d.did) }
        }
        excluded.sort { ($0.reason.rawValue, $0.title, $0.key) < ($1.reason.rawValue, $1.title, $1.key) }
        return ResolvedHouse(rooms: rooms, excluded: excluded, hidden: hidden.sorted())
    }

    /// 一个房间内：用户指定 → 名字命中灯具位 → 按类型放进空灯具位 → 徽章位 → 只在按钮行
    static func place(_ input: [Device], in mod: HouseModule, cfg: HomeHouse, name: (Device) -> String) -> [ResolvedHouseDevice] {
        let ds = input.sorted { $0.did < $1.did }
        let fixtures = HouseCatalog.fixtures(mod)
        var spot: [String: HouseSpot] = [:]          // did → spot
        var taken: Set<HouseSpot> = []
        var pinned: Set<String> = []
        var chipOnly: Set<String> = []
        var wantsBadge: [Device] = []

        // 1. 用户指定（后写入的覆盖先写入的）
        let explicit = ds.compactMap { d -> (Device, String, Date)? in
            guard let o = cfg.devices[d.did], let p = o.place else { return nil }
            return (d, p, o.updatedAt)
        }.sorted { ($0.2, $0.0.did) > ($1.2, $1.0.did) }
        for (d, p, _) in explicit {
            if p == "none" { chipOnly.insert(d.did); pinned.insert(d.did); continue }
            if p == "badge" { wantsBadge.append(d); pinned.insert(d.did); continue }
            if p.hasPrefix("badge:") {   // 指定某个徽章位（拖放）；位置不存在或被占用时退回任意徽章位
                let id = String(p.dropFirst("badge:".count))
                if HouseCatalog.badgeIds(mod).contains(id), !taken.contains(.badge(id)) {
                    spot[d.did] = .badge(id); taken.insert(.badge(id))
                } else { wantsBadge.append(d) }
                pinned.insert(d.did); continue
            }
            if p.hasPrefix("fixture:") {
                let id = String(p.dropFirst("fixture:".count))
                if let f = HouseCatalog.fixture(mod, id), f.accepts(d.category), !taken.contains(.fixture(id)) {
                    spot[d.did] = .fixture(id); taken.insert(.fixture(id)); pinned.insert(d.did)
                }
            }
        }
        func free(_ d: Device) -> Bool { spot[d.did] == nil && !chipOnly.contains(d.did) && !wantsBadge.contains(where: { $0.did == d.did }) }
        // 2. 名字命中
        for d in ds where free(d) {
            if let f = fixtures.first(where: { !taken.contains(.fixture($0.id)) && $0.accepts(d.category) && $0.hinted(name(d)) }) {
                spot[d.did] = .fixture(f.id); taken.insert(.fixture(f.id))
            }
        }
        // 3. 按类型
        for d in ds where free(d) {
            if let f = fixtures.first(where: { !taken.contains(.fixture($0.id)) && !$0.hintRequired && $0.accepts(d.category) }) {
                spot[d.did] = .fixture(f.id); taken.insert(.fixture(f.id))
            }
        }
        // 4. 徽章：用户指定的优先，其余按类型、did
        let rest = ds.filter { free($0) }.sorted { ($0.category.rawValue, $0.did) < ($1.category.rawValue, $1.did) }
        var badges = HouseCatalog.badgeIds(mod).filter { !taken.contains(.badge($0)) }[...]
        for d in wantsBadge + rest {
            guard let b = badges.popFirst() else { break }
            spot[d.did] = .badge(b)
        }
        return ds.map { d in
            ResolvedHouseDevice(did: d.did, name: name(d), category: d.category, online: d.isOnline, spot: spot[d.did], pinned: pinned.contains(d.did))
        }
    }
}

