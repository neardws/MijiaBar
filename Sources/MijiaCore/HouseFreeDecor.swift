import Foundation

public struct HouseFreeDecorEntry: Codable, Equatable, Sendable {
    public var item: String?
    public var cell: [Int]
    public var updatedAt: Date
    public init(item: String?, cell: [Int], updatedAt: Date = Date()) {
        self.item = item; self.cell = cell; self.updatedAt = updatedAt
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(item, forKey: .item); try container.encode(cell, forKey: .cell); try container.encode(updatedAt, forKey: .updatedAt)
    }
}

public enum HouseFreeDecor {
    public static let maxPerRoom = 4
    public enum Reason: String, Error, Codable, Sendable {
        case notFloorItem, roomFull, blocked, occupied, petSpot, disconnects, unknownRoom, unknownItem
        public var message: String {
            switch self {
            case .notFloorItem: return L("只能自由摆放落地装饰", "Only floor decor can be freely placed")
            case .roomFull: return L("每个房间最多四件自由装饰", "At most four free items per room")
            case .blocked: return L("占地超出可行走区域", "Footprint is outside the walkable floor")
            case .occupied: return L("位置已有装饰", "Position is occupied by decor")
            case .petSpot: return L("请保留宠物休息点入口", "Keep pet resting spot approaches clear")
            case .disconnects: return L("请保留连通的行走通道", "Keep the walking floor connected")
            case .unknownRoom: return L("找不到房间网格", "Room grid not found")
            case .unknownItem: return L("找不到装饰", "Decor item not found")
            }
        }
    }
    public struct Cell: Hashable, Sendable {
        public let col: Int
        public let row: Int
        public init(_ col: Int, _ row: Int) { self.col = col; self.row = row }
        public var array: [Int] { [col, row] }
        public var neighbors: [Cell] { [.init(col - 1, row), .init(col + 1, row), .init(col, row - 1), .init(col, row + 1)] }
    }
    public struct Grid: Sendable {
        public let room: String
        public let module: String
        public let tip: [Int]
        public let scale: Int
        public let walk: [String]
        public let protected: Set<Cell>
        public let doorwayCells: Set<Cell>
        public var cells: Set<Cell> {
            Set(walk.enumerated().flatMap { row, line in line.enumerated().compactMap { col, token in token == "." ? Cell(col, row) : nil } })
        }
        public func px(for cell: Cell, size: String = "S") -> HousePetPoint {
            let half = size == "L" ? 1.0 : 0.5
            let horizontal = (Double(cell.col) + half) / Double(scale), vertical = (Double(cell.row) + half) / Double(scale)
            return .init(x: Double(tip[0]) + 160 * (horizontal - vertical), y: Double(tip[1]) + 66 * (horizontal + vertical))
        }
        public func snap(point: HousePetPoint) -> Cell? {
            cells.sorted { $0.row == $1.row ? $0.col < $1.col : $0.row < $1.row }.min { px(for: $0).distance(to: point) < px(for: $1).distance(to: point) }
        }
    }
    public static func grids(layout: [HouseLayoutCell], catalog: HouseModuleCatalog, spots: HousePetSpots, style: String?) -> [Grid] {
        let modules = spots.sets[spots.artSets[HouseStyles.resolve(style)] ?? "cozy"] ?? [:]
        let doorways = HouseDoorwayPlanner.plan(layout: layout, catalog: catalog)
        return layout.sorted { HouseGrid.painterKey(col: $0.col, row: $0.row) < HouseGrid.painterKey(col: $1.col, row: $1.row) }.compactMap { placed in
            guard let module = modules[placed.module], let art = catalog.modules[placed.module], art.tip.count == 2, spots.cellsPerGrid > 0 else { return nil }
            let grid = Grid(room: HouseDecor.roomKey(placed), module: placed.module, tip: art.tip, scale: spots.cellsPerGrid, walk: module.walk, protected: [], doorwayCells: [])
            let protected = Set(module.spots.filter { ["sleep", "perch"].contains($0.kind) }.compactMap { spot -> Cell? in
                if let from = spot.from, from.count == 2, grid.cells.contains(Cell(from[0], from[1])) { return Cell(from[0], from[1]) }
                guard spot.at.count == 2 else { return nil }
                return grid.snap(point: .init(x: Double(art.tip[0]) + 160 * (spot.at[0] - spot.at[1]), y: Double(art.tip[1]) + 66 * (spot.at[0] + spot.at[1])))
            })
            let doorwayCells = Set(doorways.filter { $0.back == placed || $0.front == placed }.flatMap { doorway in
                let tile = 1.0 / Double(grid.scale)
                let lowerSide = HouseLevels.elevation(placed) < max(HouseLevels.elevation(doorway.back), HouseLevels.elevation(doorway.front))
                let depth = doorway.stairs && lowerSide ? max(tile, doorway.approachDepth) : tile
                let acrossLower = doorway.back == placed ? doorway.boundary - depth : doorway.boundary
                let acrossUpper = doorway.back == placed ? doorway.boundary : doorway.boundary + depth
                return grid.cells.filter { cell in
                    let horizontal = Double(placed.col) + Double(cell.col) * tile
                    let vertical = Double(placed.row) + Double(cell.row) * tile
                    let along = doorway.axis == .u ? vertical : horizontal
                    let across = doorway.axis == .u ? horizontal : vertical
                    return along < doorway.upper - 0.000001 && along + tile > doorway.lower + 0.000001
                        && across < acrossUpper - 0.000001 && across + tile > acrossLower + 0.000001
                }
            })
            return Grid(room: grid.room, module: grid.module, tip: grid.tip, scale: grid.scale, walk: grid.walk, protected: protected, doorwayCells: doorwayCells)
        }
    }
    public static func footprint(cell: [Int], size: String) -> Set<Cell> {
        guard cell.count == 2, cell.allSatisfy({ (0..<8192).contains($0) }) else { return [] }
        let side = size == "L" ? 2 : 1
        return Set((0..<side).flatMap { row in (0..<side).map { col in Cell(cell[0] + col, cell[1] + row) } })
    }
    public static func room(of key: String) -> String { key.lastIndex(of: "/").map { String(key[..<$0]) } ?? "" }
    public static func id(of key: String) -> String { key.split(separator: "/").last.map(String.init) ?? "" }
    public static func nextID(room: String, entries: [String: HouseFreeDecorEntry]) -> String {
        var number = 1
        while entries["\(room)/f\(number)"] != nil { number += 1 }
        return "f\(number)"
    }
    public static func validate(room: String, item id: String, cell: [Int], grids: [Grid], items: HouseDecorCatalog,
                                entries: [String: HouseFreeDecorEntry] = [:], excluding: String? = nil,
                                fixed: [HouseDecorPlacement] = []) -> Reason? {
        guard let grid = grids.first(where: { $0.room == room }) else { return .unknownRoom }
        guard let item = items.items.first(where: { $0.id == id }) else { return .unknownItem }
        guard item.surface == "floor" else { return .notFloorItem }
        let others = entries.filter { $0.key != excluding && self.room(of: $0.key) == room && $0.value.item != nil }
        guard others.count < maxPerRoom else { return .roomFull }
        let footprint = footprint(cell: cell, size: item.size), walk = grid.cells
        guard !footprint.isEmpty, footprint.isSubset(of: walk) else { return .blocked }
        guard footprint.isDisjoint(with: grid.doorwayCells) else { return .blocked }
        let occupied = Set(others.values.flatMap { entry -> Set<Cell> in
            guard let other = items.items.first(where: { $0.id == entry.item }) else { return [] }
            return self.footprint(cell: entry.cell, size: other.size)
        })
        let slots = Set(fixed.filter { $0.room == room && $0.surface == "floor" && !$0.slot.hasPrefix("free:") }.compactMap { placement in
            placement.at.count == 2 ? grid.snap(point: .init(x: placement.at[0], y: placement.at[1])) : nil
        })
        guard footprint.isDisjoint(with: occupied.union(slots)) else { return .occupied }
        guard footprint.isDisjoint(with: grid.protected) else { return .petSpot }
        let remaining = walk.subtracting(occupied).subtracting(footprint)
        guard let first = remaining.first else { return .disconnects }
        var visited: Set<Cell> = [first], queue = [first], index = 0
        while index < queue.count {
            let current = queue[index]; index += 1
            for neighbor in current.neighbors where remaining.contains(neighbor) && visited.insert(neighbor).inserted { queue.append(neighbor) }
        }
        return visited == remaining ? nil : .disconnects
    }
    public static func resolve(entries: [String: HouseFreeDecorEntry], grids: [Grid], items: HouseDecorCatalog,
                               fixed: [HouseDecorPlacement] = []) -> [HouseDecorPlacement] {
        var accepted: [String: HouseFreeDecorEntry] = [:], result: [HouseDecorPlacement] = []
        for key in entries.keys.sorted() {
            guard let entry = entries[key], let id = entry.item,
                  validate(room: room(of: key), item: id, cell: entry.cell, grids: grids, items: items, entries: accepted, fixed: fixed) == nil,
                  let grid = grids.first(where: { $0.room == room(of: key) }), let item = items.items.first(where: { $0.id == id }) else { continue }
            let point = grid.px(for: Cell(entry.cell[0], entry.cell[1]), size: item.size)
            accepted[key] = entry
            result.append(.init(room: grid.room, slot: "free:" + self.id(of: key), item: id, module: grid.module,
                                at: [point.x, point.y], surface: "floor", wall: nil, source: .user, freeCell: entry.cell))
        }
        return result
    }
}
