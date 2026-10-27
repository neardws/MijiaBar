import Foundation

// MARK: - 小屋编辑：拖放校验 + 撤销栈（纯值类型，App 和测试共用）

/// 一次拖放要写进 house.json 的改动（每台设备一条）
public struct HouseDropChange: Equatable, Sendable {
    public let did: String
    /// house.json 的 place 值（"fixture:<id>" | "badge:<id>" | "badge" | "none"）
    public let place: String
    /// 非 nil 时同时改 visible（例如把小屋里隐藏的设备拖进来 = 显示它）
    public let visible: Bool?
    public init(did: String, place: String, visible: Bool? = nil) { self.did = did; self.place = place; self.visible = visible }
}

public enum HouseDropRejection: String, Sendable {
    case otherRoom        // 位置不在设备所属的米家房间
    case incompatible     // 灯具位不接受这类设备
    case notShowable      // 这类设备不进小屋
    case roomNotInHouse   // 目标房间不在小屋里

    public var message: String {
        switch self {
        case .otherRoom: return L("只能放在设备自己的米家房间里", "Devices can only go in their own Mijia room")
        case .incompatible: return L("这个位置放不了这类设备", "This spot doesn't take this kind of device")
        case .notShowable: return L("这类设备不显示在小屋里", "This kind of device isn't shown in the house")
        case .roomNotInHouse: return L("这个房间不在小屋里", "This room isn't in the house")
        }
    }
}

public enum HouseDropVerdict: Equatable, Sendable {
    case accept([HouseDropChange])
    case reject(HouseDropRejection)
    public var isAccepted: Bool { if case .accept = self { return true }; return false }
    public var changes: [HouseDropChange] { if case .accept(let c) = self { return c }; return [] }
}

/// 被拖的设备
public struct HouseDragSource: Equatable, Sendable {
    public let did: String
    public let category: DeviceCategory
    /// HouseResolver.roomKey(device)
    public let roomKey: String
    /// 设备现在在小屋里被隐藏（visible 为 false，或跟随列表隐藏）
    public let hiddenInHouse: Bool
    public init(did: String, category: DeviceCategory, roomKey: String, hiddenInHouse: Bool = false) {
        self.did = did; self.category = category; self.roomKey = roomKey; self.hiddenInHouse = hiddenInHouse
    }
}

public enum HouseEditing {
    public static func placeValue(_ s: HouseSpot) -> String {
        switch s { case .fixture(let id): return "fixture:" + id; case .badge(let id): return "badge:" + id }
    }

    /// 把设备拖到 roomKey 房间的 spot 上：校验 + 算出要写的改动。
    /// 位置上已有别的设备时交换：对方回到被拖设备原来的位置（放得下的话），否则改用徽章。
    public static func planDrop(_ src: HouseDragSource, roomKey: String, spot: HouseSpot, house: ResolvedHouse) -> HouseDropVerdict {
        guard let room = house.rooms.first(where: { $0.key == roomKey }) else { return .reject(.roomNotInHouse) }
        guard src.roomKey == roomKey else { return .reject(.otherRoom) }
        guard HouseCatalog.showable(src.category) else { return .reject(.notShowable) }
        switch spot {
        case .fixture(let id):
            guard let f = HouseCatalog.fixture(room.module, id) else { return .reject(.incompatible) }
            guard f.accepts(src.category) else { return .reject(.incompatible) }
        case .badge(let id):
            guard HouseCatalog.badgeIds(room.module).contains(id) else { return .reject(.incompatible) }
        }
        let current = room.devices.first { $0.did == src.did }?.spot
        if current == spot && !src.hiddenInHouse { return .accept([]) }
        var changes = [HouseDropChange(did: src.did, place: placeValue(spot), visible: src.hiddenInHouse ? true : nil)]
        if let other = room.devices.first(where: { $0.spot == spot && $0.did != src.did }) {
            let back: String
            switch current {
            case .fixture(let g)? where HouseCatalog.fixture(room.module, g)?.accepts(other.category) == true: back = "fixture:" + g
            case .badge(let b)?: back = "badge:" + b
            default: back = "badge"
            }
            changes.append(HouseDropChange(did: other.did, place: back))
        }
        return .accept(changes)
    }

    /// 把设备从位置上拖走（拖回面板 / 拖到空白处）：灯具位 → 徽章，徽章 → 只在按钮行
    public static func planClear(did: String, house: ResolvedHouse) -> [HouseDropChange] {
        for r in house.rooms {
            guard let d = r.devices.first(where: { $0.did == did }) else { continue }
            switch d.spot {
            case .fixture?: return [HouseDropChange(did: did, place: "badge")]
            case .badge?: return [HouseDropChange(did: did, place: "none")]
            case nil: return []
            }
        }
        return []
    }

    public static func apply(_ changes: [HouseDropChange], to file: inout HouseFile, home: String, now: Date = Date()) {
        for c in changes {
            file.setDevice(home: home, did: c.did, now: now) { o in
                o.place = c.place
                if let v = c.visible { o.visible = v }
            }
        }
    }
}

// MARK: - 撤销栈

/// 一次编辑：只记录改动过的条目在编辑前后的值（不含 updatedAt）。
/// 撤销 = 把「编辑前」的值用新的 updatedAt 写回去，所以和其他 Mac 的改动合并时同样是后写入的赢。
public struct HouseEdit: Equatable, Sendable {
    public struct DeviceValue: Equatable, Sendable {
        public var visible: Bool?
        public var place: String?
        public init(visible: Bool? = nil, place: String? = nil) { self.visible = visible; self.place = place }
        public var isAutomatic: Bool { visible == nil && place == nil }
    }
    public struct Change<T: Equatable & Sendable>: Equatable, Sendable { public let before: T; public let after: T }
    public struct DecorPrefsValue: Equatable, Sendable {
        public let enabled: Bool
        public let seasonal: Bool
        init(_ prefs: HouseDecorPrefs?) { enabled = prefs?.enabled ?? true; seasonal = prefs?.seasonal ?? true }
    }

    public let label: String
    public let home: String
    public let devices: [String: Change<DeviceValue>]
    public let rooms: [String: Change<String?>]
    public let layout: Change<[HouseLayoutCell]?>?
    public let style: Change<String?>?
    public let decor: [String: Change<String?>]
    public let freeDecor: [String: Change<HouseFreeDecorEntry?>]
    public let decorPrefs: Change<DecorPrefsValue>?
    public let pets: [String: Change<HousePet?>]
    public let petPrefs: Change<Bool>?

    public enum Side: Sendable { case before, after }

    static func value(_ f: HouseFile, home: String, did: String) -> DeviceValue {
        let o = f.homes[home]?.devices[did]
        return DeviceValue(visible: o?.visible, place: o?.place)
    }
    static func module(_ f: HouseFile, home: String, room: String) -> String? { f.homes[home]?.rooms[room]?.module }
    static func pet(_ config: HomeHouse?, id: String) -> HousePet? {
        guard var pet = config?.pets?[id], !pet.deleted else { return nil }
        pet.updatedAt = .distantPast; return pet
    }
    static func free(_ config: HomeHouse?, key: String) -> HouseFreeDecorEntry? {
        guard var entry = config?.freeDecor?[key], entry.item != nil else { return nil }
        entry.updatedAt = .distantPast; return entry
    }

    /// 比较编辑前后的文件；没有实际改动时返回 nil（不进撤销栈）
    public static func diff(label: String, home: String, before: HouseFile, after: HouseFile) -> HouseEdit? {
        let b = before.homes[home] ?? HomeHouse(), a = after.homes[home] ?? HomeHouse()
        var ds: [String: Change<DeviceValue>] = [:]
        for k in Set(b.devices.keys).union(a.devices.keys) {
            let x = value(before, home: home, did: k), y = value(after, home: home, did: k)
            if x != y { ds[k] = Change(before: x, after: y) }
        }
        var rs: [String: Change<String?>] = [:]
        for k in Set(b.rooms.keys).union(a.rooms.keys) {
            let x = module(before, home: home, room: k), y = module(after, home: home, room: k)
            if x != y { rs[k] = Change(before: x, after: y) }
        }
        let lb = before.homes[home]?.layout, la = after.homes[home]?.layout
        let layoutChange: Change<[HouseLayoutCell]?>? = (lb != la) ? Change(before: lb, after: la) : nil
        let styleChange: Change<String?>? = b.style != a.style ? Change(before: b.style, after: a.style) : nil
        var decor: [String: Change<String?>] = [:]
        for key in Set((b.decor ?? [:]).keys).union((a.decor ?? [:]).keys) {
            let old = b.decor?[key]?.item, new = a.decor?[key]?.item
            if old != new { decor[key] = Change(before: old, after: new) }
        }
        let oldPrefs = DecorPrefsValue(b.decorPrefs), newPrefs = DecorPrefsValue(a.decorPrefs)
        var freeDecor: [String: Change<HouseFreeDecorEntry?>] = [:]
        for key in Set((b.freeDecor ?? [:]).keys).union((a.freeDecor ?? [:]).keys) {
            let old = free(b, key: key), new = free(a, key: key)
            if old != new { freeDecor[key] = Change(before: old, after: new) }
        }
        let prefsChange: Change<DecorPrefsValue>? = oldPrefs != newPrefs ? Change(before: oldPrefs, after: newPrefs) : nil
        var pets: [String: Change<HousePet?>] = [:]
        for id in Set((b.pets ?? [:]).keys).union((a.pets ?? [:]).keys) {
            let old = pet(b, id: id), new = pet(a, id: id)
            if old != new { pets[id] = Change(before: old, after: new) }
        }
        let oldEnabled = b.petPrefs?.enabled ?? true, newEnabled = a.petPrefs?.enabled ?? true
        let petPrefs = oldEnabled != newEnabled ? Change(before: oldEnabled, after: newEnabled) : nil
        if ds.isEmpty && rs.isEmpty && layoutChange == nil && styleChange == nil && decor.isEmpty && freeDecor.isEmpty && prefsChange == nil && pets.isEmpty && petPrefs == nil { return nil }
        return HouseEdit(label: label, home: home, devices: ds, rooms: rs, layout: layoutChange,
                         style: styleChange, decor: decor, freeDecor: freeDecor, decorPrefs: prefsChange, pets: pets, petPrefs: petPrefs)
    }

    /// 文件里这些条目现在是不是还等于 side 那一侧的值（不是的话说明被别处改过，撤销记录作废）
    public func matches(_ f: HouseFile, side: Side) -> Bool {
        let devicesOK = devices.allSatisfy { k, c in HouseEdit.value(f, home: home, did: k) == (side == .before ? c.before : c.after) }
        let roomsOK = rooms.allSatisfy { k, c in HouseEdit.module(f, home: home, room: k) == (side == .before ? c.before : c.after) }
        let layoutOK: Bool = {
            guard let layout else { return true }
            let cur = f.homes[home]?.layout
            return cur == (side == .before ? layout.before : layout.after)
        }()
        let styleOK = style.map { f.homes[home]?.style == (side == .before ? $0.before : $0.after) } ?? true
        let decorOK = decor.allSatisfy { key, change in f.homes[home]?.decor?[key]?.item == (side == .before ? change.before : change.after) }
        let prefsOK = decorPrefs.map { DecorPrefsValue(f.homes[home]?.decorPrefs) == (side == .before ? $0.before : $0.after) } ?? true
        let petsOK = pets.allSatisfy { id, change in Self.pet(f.homes[home], id: id) == (side == .before ? change.before : change.after) }
        let petPrefsOK = petPrefs.map { (f.homes[home]?.petPrefs?.enabled ?? true) == (side == .before ? $0.before : $0.after) } ?? true
        let freeOK = freeDecor.allSatisfy { key, change in Self.free(f.homes[home], key: key) == (side == .before ? change.before : change.after) }
        return devicesOK && roomsOK && layoutOK && styleOK && decorOK && freeOK && prefsOK && petsOK && petPrefsOK
    }

    public func apply(_ side: Side, to f: inout HouseFile, now: Date = Date()) {
        for (k, c) in devices {
            let v = side == .before ? c.before : c.after
            if v.isAutomatic { f.reset(home: home, did: k, now: now) }
            else { f.setDevice(home: home, did: k, now: now) { $0.visible = v.visible; $0.place = v.place } }
        }
        for (k, c) in rooms { f.setRoom(home: home, key: k, module: side == .before ? c.before : c.after, now: now) }
        if let layout {
            f.setLayout(home: home, layout: side == .before ? layout.before : layout.after, now: now)
        }
        if let style { f.setStyle(home: home, style: side == .before ? style.before : style.after, now: now) }
        for (key, change) in decor { f.setDecor(home: home, key: key, item: side == .before ? change.before : change.after, now: now) }
        for (key, change) in freeDecor {
            let value = side == .before ? change.before : change.after
            f.setFreeDecor(home: home, key: key, item: value?.item, cell: value?.cell ?? [], now: now)
        }
        if let decorPrefs {
            let value = side == .before ? decorPrefs.before : decorPrefs.after
            f.setDecorPrefs(home: home, enabled: value.enabled, seasonal: value.seasonal, now: now)
        }
        for (id, change) in pets {
            var value = (side == .before ? change.before : change.after) ?? f.homes[home]?.pets?[id] ?? HousePet(id: id)
            value.deleted = (side == .before ? change.before : change.after) == nil; value.updatedAt = now
            if f.homes[home] == nil { f.homes[home] = HomeHouse() }
            if f.homes[home]?.pets == nil { f.homes[home]?.pets = [:] }
            f.homes[home]?.pets?[id] = value
        }
        if let petPrefs { f.setPetPrefs(home: home, enabled: side == .before ? petPrefs.before : petPrefs.after, now: now) }
    }

    func canApplyPets(_ side: Side, to file: HouseFile) -> Bool {
        var active = Set((file.homes[home]?.pets ?? [:]).values.filter { !$0.deleted }.map(\.id))
        let previous = active.count
        for (id, change) in pets {
            if (side == .before ? change.before : change.after) == nil { active.remove(id) }
            else { active.insert(id) }
        }
        return active.count <= max(previous, HouseFile.petLimit)
    }
}

/// HouseWindow 一次会话里的撤销 / 重做。
/// 外部改动（命令行、Agent、其他 Mac）只要没碰撤销记录里的条目就保留记录；碰到了就清空，避免把别人的改动撤掉。
public struct HouseUndoStack: Equatable, Sendable {
    public private(set) var undos: [HouseEdit] = []
    public private(set) var redos: [HouseEdit] = []
    public var limit = 100
    public init() {}

    public var canUndo: Bool { !undos.isEmpty }
    public var canRedo: Bool { !redos.isEmpty }
    public var undoLabel: String? { undos.last?.label }
    public var redoLabel: String? { redos.last?.label }

    public enum Outcome: Equatable, Sendable { case applied(HouseEdit), stale, empty }

    public mutating func record(_ e: HouseEdit?) {
        guard let e else { return }
        undos.append(e)
        if undos.count > limit { undos.removeFirst(undos.count - limit) }
        redos.removeAll()
    }

    public mutating func undo(_ f: inout HouseFile, now: Date = Date()) -> Outcome {
        guard let e = undos.last else { return .empty }
        guard e.matches(f, side: .after), e.canApplyPets(.before, to: f) else { clear(); return .stale }
        e.apply(.before, to: &f, now: now)
        undos.removeLast(); redos.append(e)
        return .applied(e)
    }

    public mutating func redo(_ f: inout HouseFile, now: Date = Date()) -> Outcome {
        guard let e = redos.last else { return .empty }
        guard e.matches(f, side: .before), e.canApplyPets(.after, to: f) else { clear(); return .stale }
        e.apply(.after, to: &f, now: now)
        redos.removeLast(); undos.append(e)
        return .applied(e)
    }

    /// house.json 被外部改了：最近一步还对得上就保留，否则清空（返回是否清空了）
    @discardableResult
    public mutating func rebase(on f: HouseFile) -> Bool {
        var dropped = false
        if let u = undos.last, !u.matches(f, side: .after) { undos.removeAll(); dropped = true }
        if let r = redos.last, !r.matches(f, side: .before) { redos.removeAll(); dropped = true }
        return dropped
    }

    public mutating func clear() { undos.removeAll(); redos.removeAll() }
}
