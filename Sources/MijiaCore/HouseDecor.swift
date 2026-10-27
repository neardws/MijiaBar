import Foundation

public struct HouseDecorSlot: Codable, Equatable, Sendable {
    public var id: String
    public var surface: String
    public var sizes: [String]
    public var at: [Double]
    public var wall: String? = nil
    public var `default`: String? = nil
    public var holiday: Bool? = nil
    public init(id: String, surface: String, sizes: [String], at: [Double], wall: String? = nil, default item: String? = nil, holiday: Bool? = nil) {
        self.id = id; self.surface = surface; self.sizes = sizes; self.at = at
        self.wall = wall; self.default = item; self.holiday = holiday
    }
}

public struct HouseDecorCatalog: Codable, Equatable, Sendable {
    public struct Season: Codable, Equatable, Sendable {
        public var calendar: String
        public var month: Int
        public var day: Int
        public var window: Int
    }
    public struct Item: Codable, Equatable, Sendable {
        public enum Sprite: Codable, Equatable, Sendable {
            case image(String), walls([String: String])
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let name = try? container.decode(String.self) { self = .image(name) }
                else { self = .walls(try container.decode([String: String].self)) }
            }
            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self { case .image(let name): try container.encode(name); case .walls(let names): try container.encode(names) }
            }
            public func file(wall: String? = nil) -> String? {
                switch self { case .image(let name): return name; case .walls(let names): return wall.flatMap { names[$0] } }
            }
            public var files: [String] { switch self { case .image(let name): return [name]; case .walls(let names): return names.keys.sorted().compactMap { names[$0] } } }
        }
        public var id: String
        public var name: [String: String]
        public var category: String
        public var surface: String
        public var size: String
        public var sprites: [String: Sprite]
        public var anchor: [Double]
        public var petSpot: Bool?
        public var species: [String]?
        public var season: String?
        public var text: Bool?
        public func fits(_ slot: HouseDecorSlot) -> Bool {
            surface == slot.surface && slot.sizes.contains(size) && (surface != "wall" || ["nw", "ne"].contains(slot.wall ?? ""))
        }
    }
    public var schema: Int
    public var seasons: [String: Season]
    public var items: [Item]
    public static func load(from url: URL) throws -> Self { try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
}

public struct HouseDecorPrefs: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var seasonal: Bool
    public var updatedAt: Date
    public init(enabled: Bool = true, seasonal: Bool = true, updatedAt: Date = .distantPast) {
        self.enabled = enabled; self.seasonal = seasonal; self.updatedAt = updatedAt
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        seasonal = try container.decodeIfPresent(Bool.self, forKey: .seasonal) ?? true
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
    }
}

public struct HouseDecorEntry: Codable, Equatable, Sendable {
    public var item: String?
    public var updatedAt: Date
    public init(item: String?, updatedAt: Date = Date()) { self.item = item; self.updatedAt = updatedAt }
}

public enum HouseSeasons {
    public static func activeSeasons(on date: Date, calendar: Calendar = .current, timeZone: TimeZone? = nil,
                                     seasons: [String: HouseDecorCatalog.Season]) -> [String] {
        var days = Calendar(identifier: .gregorian); days.timeZone = timeZone ?? calendar.timeZone
        let today = days.startOfDay(for: date)
        return seasons.keys.sorted().filter { key in
            guard let season = seasons[key], season.window >= 0,
                  ["chinese", "gregorian"].contains(season.calendar) else { return false }
            var eventCalendar = Calendar(identifier: season.calendar == "chinese" ? .chinese : .gregorian)
            eventCalendar.timeZone = days.timeZone
            // 扫描窗口两侧的日历日，自然跨农历年；闰月不算节日。
            for offset in (-season.window)...season.window {
                guard let candidate = days.date(byAdding: .day, value: offset, to: today) else { continue }
                let parts = eventCalendar.dateComponents([.month, .day, .isLeapMonth], from: candidate)
                if parts.month == season.month && parts.day == season.day && parts.isLeapMonth != true { return true }
            }
            return false
        }
    }
}

public struct HouseDecorPlacement: Equatable, Sendable {
    public enum Source: String, Codable, Sendable { case `default`, user, holiday }
    public var room: String
    public var slot: String
    public var item: String
    public var module: String
    public var at: [Double]
    public var surface: String
    public var wall: String?
    public var source: Source
}

public enum HouseDecor {
    public static func roomKey(_ cell: HouseLayoutCell) -> String { cell.room.isEmpty ? cell.module : cell.room }
    public static func hiddenSlots(layout: [HouseLayoutCell], catalog: HouseModuleCatalog) -> Set<String> {
        let cells = layout.compactMap { cell in catalog.modules[cell.module].map { (cell, $0.fw) } }
        let tips = catalog.modules.mapValues { (x: $0.tip[0], y: $0.tip[1]) }
        var hidden = Set<String>()
        for placed in HouseWallPlanner.plan(cells, tips: tips) {
            for slot in catalog.modules[placed.cell.module]?.decor ?? [] {
                if let wall = slot.wall, HouseComposer.wallIsHidden(wall: wall, anchor: slot.at, segments: placed.segments) {
                    hidden.insert("\(roomKey(placed.cell))/\(slot.id)")
                }
            }
        }
        return hidden
    }
    public static func resolve(layout: [HouseLayoutCell], catalog: HouseModuleCatalog, overrides: [String: HouseDecorEntry] = [:],
                               prefs: HouseDecorPrefs = .init(), date: Date = Date(), items: HouseDecorCatalog,
                               calendar: Calendar = .current, includeHidden: Bool = false) -> [HouseDecorPlacement] {
        guard prefs.enabled else { return [] }
        let active = prefs.seasonal ? HouseSeasons.activeSeasons(on: date, calendar: calendar, seasons: items.seasons) : []
        let hidden = hiddenSlots(layout: layout, catalog: catalog)
        var result: [HouseDecorPlacement] = []
        for cell in layout {
            let room = roomKey(cell), slots = catalog.modules[cell.module]?.decor ?? []
            var chosen: [String: (HouseDecorCatalog.Item, HouseDecorPlacement.Source)] = [:]
            for slot in slots {
                let override = overrides["\(room)/\(slot.id)"]?.item
                if override == "none" { continue }
                if let override, let item = items.items.first(where: { $0.id == override && $0.fits(slot) }) { chosen[slot.id] = (item, .user) }
                else if let item = items.items.first(where: { $0.id == slot.default && $0.fits(slot) }) { chosen[slot.id] = (item, .default) }
            }
            for season in active {
                for item in items.items where item.season == season {
                    if let slot = slots.first(where: {
                        $0.holiday == true && overrides["\(room)/\($0.id)"]?.item == nil && item.fits($0)
                            && chosen[$0.id]?.1 != .holiday && !hidden.contains("\(room)/\($0.id)")
                    }) { chosen[slot.id] = (item, .holiday) }
                }
            }
            for slot in slots where includeHidden || !hidden.contains("\(room)/\(slot.id)") {
                guard let (item, source) = chosen[slot.id], slot.at.count == 2 else { continue }
                result.append(.init(room: room, slot: slot.id, item: item.id, module: cell.module, at: slot.at,
                                    surface: slot.surface, wall: slot.wall, source: source))
            }
        }
        return result
    }
}
