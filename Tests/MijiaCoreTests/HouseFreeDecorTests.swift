import Foundation
import Testing
@testable import MijiaCore

@Suite struct HouseFreeDecorTests {
    static func fixture(walk: [String] = Array(repeating: "......", count: 6)) throws -> (HouseModuleCatalog, HouseDecorCatalog, HousePetSpots, [HouseLayoutCell]) {
        var (modules, items, layout) = try HouseDecorTests.fixture()
        modules.modules["test"]?.decor = []
        var large = items.items[0]; large.id = "large"; large.size = "L"; items.items.append(large)
        var bed = items.items[0]; bed.id = "bed"; bed.petSpot = true; items.items.append(bed)
        layout[0].level = 0
        let spots = HousePetSpots(cellsPerGrid: 8, artSets: ["cozy-wood": "cozy"], sets: ["cozy": ["test": .init(grid: [walk[0].count, walk.count], walk: walk,
            spots: [.init(id: "sleep", kind: "sleep", at: [0.0625, 0.0625], from: [0, 0])])]])
        return (modules, items, spots, layout)
    }
    @Test func validationReasonsFootprintAndSnap() throws {
        let (modules, items, spots, layout) = try Self.fixture()
        let grids = HouseFreeDecor.grids(layout: layout, catalog: modules, spots: spots, style: nil)
        let grid = try #require(grids.first)
        func reason(_ item: String = "plant", _ cell: [Int] = [2, 2], room: String = "room", entries: [String: HouseFreeDecorEntry] = [:], fixed: [HouseDecorPlacement] = []) -> HouseFreeDecor.Reason? {
            HouseFreeDecor.validate(room: room, item: item, cell: cell, grids: grids, items: items, entries: entries, fixed: fixed)
        }
        #expect(reason() == nil)
        #expect(reason(room: "missing") == .unknownRoom)
        #expect(reason("missing") == .unknownItem)
        #expect(reason("art") == .notFloorItem)
        #expect(reason("plant", [-1, 0]) == .blocked)
        #expect(reason("plant", [Int.max, 0]) == .blocked)
        #expect(reason("plant", []) == .blocked)
        #expect(reason("large", [5, 5]) == .blocked)
        #expect(reason("plant", [0, 0]) == .petSpot)
        #expect(reason(entries: ["room/f1": .init(item: "large", cell: [1, 1])]) == .occupied)
        let at = grid.px(for: .init(2, 2))
        let fixed = HouseDecorPlacement(room: "room", slot: "floor", item: "plant", module: "test", at: [at.x, at.y], surface: "floor", source: .default)
        #expect(reason(fixed: [fixed]) == .occupied)
        let full = Dictionary(uniqueKeysWithValues: (0..<4).map { ("room/f\($0)", HouseFreeDecorEntry(item: "plant", cell: [$0, 4])) })
        #expect(reason(entries: full) == .roomFull)
        #expect(HouseFreeDecor.validate(room: "room", item: "plant", cell: [2, 2], grids: grids, items: items, entries: full, excluding: "room/f0") == nil)
        #expect(HouseFreeDecor.footprint(cell: [2, 3], size: "L") == Set([.init(2, 3), .init(3, 3), .init(2, 4), .init(3, 4)]))
        for cell in grid.cells { #expect(grid.snap(point: grid.px(for: cell)) == cell) }
        #expect(grid.px(for: .init(2, 2), size: "L").y == Double(grid.tip[1]) + 49.5)
        #expect(HouseFreeDecor.nextID(room: "room", entries: ["room/f1": .init(item: nil, cell: [])]) == "f2")
    }
    @Test func protectsConnectivity() throws {
        let (modules, items, spots, layout) = try Self.fixture(walk: ["....."])
        let grids = HouseFreeDecor.grids(layout: layout, catalog: modules, spots: spots, style: nil)
        #expect(HouseFreeDecor.validate(room: "room", item: "plant", cell: [2, 0], grids: grids, items: items) == .disconnects)
    }
    @Test func protectsDoorwayTilesAndStairs() throws {
        for axis in [HouseDoorway.Axis.u, .v] {
            for level in [-1, 0, 1] {
                for scale in [4, 8, 16] {
                    for fallback in [false, true] {
                        var (modules, items, spots, _) = try Self.fixture(walk: Array(repeating: String(repeating: ".", count: scale), count: scale))
                        spots.cellsPerGrid = scale
                        spots.sets["cozy"]?["test"]?.spots = []
                        let ranges: [String: [[Double]]] = ["nw": [[0.2, 0.8]], "ne": [[0.2, 0.8]], "sw": [[0.2, 0.8]], "se": [[0.2, 0.8]]]
                        modules.modules["test"]?.stairRanges = ["3": ["nw": [], "ne": [], "sw": [], "se": []], "2": ranges]
                        if fallback { modules.modules["test"]?.doorwayRanges = ["nw": [], "ne": [], "sw": [], "se": []] }
                        let layout: [HouseLayoutCell] = [
                            .init(room: "back", module: "test", col: -2, row: 3, level: 0),
                            .init(room: "front", module: "test", col: axis == .u ? -1 : -2, row: axis == .u ? 3 : 4, level: level)
                        ]
                        let doorway = try #require(HouseDoorwayPlanner.plan(layout: layout, catalog: modules).first)
                        #expect(doorway.usedFallback == fallback)
                        let grids = HouseFreeDecor.grids(layout: layout, catalog: modules, spots: spots, style: nil)
                        for grid in grids {
                            let back = grid.room == "back"
                            let lowerSide = level > 0 ? back : !back
                            let depth = level != 0 && lowerSide ? Int(ceil(doorway.approachDepth * Double(scale))) : 1
                            let alongStart = Int(floor(0.35 * Double(scale))), alongEnd = Int(ceil(0.65 * Double(scale)))
                            var expected: Set<HouseFreeDecor.Cell> = []
                            for along in alongStart..<alongEnd {
                                for distance in 0..<depth {
                                    let across = back ? scale - 1 - distance : distance
                                    expected.insert(axis == .u ? .init(across, along) : .init(along, across))
                                }
                            }
                            #expect(grid.doorwayCells == expected)
                            #expect(grid.cells.count == scale * scale)
                            for cell in grid.cells {
                                #expect(grid.snap(point: grid.px(for: cell)) == cell)
                                let reason = HouseFreeDecor.validate(room: grid.room, item: "plant", cell: cell.array, grids: grids, items: items)
                                #expect(reason == (expected.contains(cell) ? .blocked : nil))
                            }
                            for cell in grid.cells where cell.col < scale - 1 && cell.row < scale - 1 {
                                let footprint = HouseFreeDecor.footprint(cell: cell.array, size: "L")
                                if !footprint.isDisjoint(with: expected) {
                                    #expect(HouseFreeDecor.validate(room: grid.room, item: "large", cell: cell.array, grids: grids, items: items) == .blocked)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    @Test func resolutionKeepsDoorwaysClearAfterLayoutChanges() throws {
        let (modules, items, spots, original) = try Self.fixture(walk: Array(repeating: "........", count: 8))
        let entries: [String: HouseFreeDecorEntry] = [
            "room/f1": .init(item: "plant", cell: [7, 3]),
            "room/f2": .init(item: "plant", cell: [7, 1])
        ]
        let single = HouseFreeDecor.grids(layout: original, catalog: modules, spots: spots, style: nil)
        #expect(HouseFreeDecor.resolve(entries: entries, grids: single, items: items).count == 2)
        let layout = original + [HouseLayoutCell(room: "next", module: "test", col: 1, row: 0, level: 1)]
        let grids = HouseFreeDecor.grids(layout: layout, catalog: modules, spots: spots, style: nil)
        let placements = HouseFreeDecor.resolve(entries: entries, grids: grids, items: items)
        #expect(placements.map(\.slot) == ["free:f2"])
        let baseline = HousePetWorld(layout: layout, catalog: modules, spots: spots)
        let world = HousePetWorld(layout: layout, catalog: modules, spots: spots, decor: placements, items: items)
        #expect(world.doorways == baseline.doorways)
        for grid in grids {
            for cell in grid.doorwayCells {
                #expect(world.nodes.contains { $0.room == grid.room && $0.col == cell.col && $0.row == cell.row })
            }
        }
        let start = try #require(world.nodes.first { $0.room == "room" })
        let end = try #require(world.nodes.first { $0.room == "next" })
        #expect(!world.path(from: start.id, to: end.id).isEmpty)
    }
    @Test func protectsNearestSpotAndResolvesConflictsDeterministically() throws {
        let (modules, items, original, layout) = try Self.fixture()
        var spots = original
        spots.sets["cozy"]?["test"]?.spots = [.init(id: "perch", kind: "perch", at: [0.3125, 0.3125], z: 24)]
        let grids = HouseFreeDecor.grids(layout: layout, catalog: modules, spots: spots, style: nil)
        #expect(HouseFreeDecor.validate(room: "room", item: "plant", cell: [2, 2], grids: grids, items: items) == .petSpot)
        let entries: [String: HouseFreeDecorEntry] = ["room/f2": .init(item: "plant", cell: [4, 4]), "room/f1": .init(item: "large", cell: [3, 3]), "room/wall": .init(item: "art", cell: [1, 1])]
        let first = HouseFreeDecor.resolve(entries: entries, grids: grids, items: items)
        #expect(first.map(\.slot) == ["free:f1"])
        #expect(first == HouseFreeDecor.resolve(entries: Dictionary(uniqueKeysWithValues: entries.sorted { $0.key > $1.key }), grids: grids, items: items))
    }
    @Test func realStylesKeepFixedSleepNodesForEveryValidPlacement() throws {
        let items = try HouseDecorTests.catalog()
        let spots = try HousePetSpots.load(from: HouseDecorTests.root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/pets/pet-spots.json"))
        for style in ["cozy-wood", "japanese", "modern"] {
            let catalog = try HouseDecorTests.modules(style)
            for module in ["living", "bedroom"] {
                let layout = [HouseLayoutCell(room: "room", module: module, col: 0, row: 0, level: 0)]
                let grids = HouseFreeDecor.grids(layout: layout, catalog: catalog, spots: spots, style: style)
                let fixed = HouseDecor.resolve(layout: layout, catalog: catalog, items: items)
                let baseline = HousePetWorld(layout: layout, catalog: catalog, spots: spots, style: style)
                let grid = try #require(grids.first)
                var valid = 0
                for cell in grid.cells where HouseFreeDecor.validate(room: "room", item: "cat_bed", cell: cell.array, grids: grids, items: items, fixed: fixed) == nil {
                    valid += 1
                    let placements = HouseFreeDecor.resolve(entries: ["room/f1": .init(item: "cat_bed", cell: cell.array)], grids: grids, items: items, fixed: fixed)
                    let world = HousePetWorld(layout: layout, catalog: catalog, spots: spots, style: style, decor: placements, items: items)
                    for spot in baseline.spots where ["sleep", "perch"].contains(spot.kind) {
                        let retained = try #require(world.spots.first { $0.id == spot.id })
                        #expect(world.nodes[retained.node].point == baseline.nodes[spot.node].point)
                    }
                    let bed = try #require(world.spots.first { $0.id == "room/decor/free:f1" })
                    #expect(world.nodes[bed.node].col != cell.col || world.nodes[bed.node].row != cell.row)
                }
                #expect(valid > 0, "\(style)/\(module) should have valid floor cells")
            }
        }
    }
    @Test func storageMergeResetGCAndOldDecoder() throws {
        let old = try HouseFile.decode(Data(#"{"schema":1,"homes":{"h":{"rooms":{},"unknown":42}}}"#.utf8))
        #expect(old.homes["h"]?.freeDecor == nil)
        var file = old
        let early = Date(timeIntervalSince1970: 100), late = Date(timeIntervalSince1970: 200)
        file.setFreeDecor(home: "h", key: "room/f1", item: "plant", cell: [2, 2], now: early)
        #expect(try HouseFile.decode(file.encoded()) == file)
        struct LegacyHome: Decodable { var rooms: [String: HouseRoomOverride] }
        struct LegacyFile: Decodable { var schema: Int; var homes: [String: LegacyHome] }
        #expect(try JSONDecoder().decode(LegacyFile.self, from: file.encoded()).schema == 1)
        var deleted = file; deleted.resetDecor(home: "h", now: late)
        #expect(HouseFile.merge(deleted, file).homes["h"]?.freeDecor?["room/f1"]?.item == nil)
        #expect(HouseFile.merge(file, deleted) == deleted)
        deleted.prune(now: late.addingTimeInterval(31 * 86400)); #expect(deleted.homes["h"]?.freeDecor?.isEmpty == true)
        file.reset(home: "h", now: late); #expect(file.homes["h"]?.freeDecor?["room/f1"]?.item == nil)
    }
    @Test func resolutionPetBlockersAndSleepSpot() throws {
        let (modules, items, spots, layout) = try Self.fixture()
        let grids = HouseFreeDecor.grids(layout: layout, catalog: modules, spots: spots, style: nil)
        let entries: [String: HouseFreeDecorEntry] = ["room/f1": .init(item: "large", cell: [2, 2]), "room/f2": .init(item: "bed", cell: [4, 4]), "room/bad": .init(item: "plant", cell: [99, 99])]
        let placements = HouseDecor.resolve(layout: layout, catalog: modules, items: items, free: entries, grids: grids)
        #expect(placements.count == 2)
        let large = try #require(placements.first { $0.item == "large" })
        #expect(large.at == [Double(modules.modules["test"]!.tip[0]), Double(modules.modules["test"]!.tip[1]) + 49.5])
        #expect(large.slot == "free:f1" && large.source == .user)
        #expect(HouseDecor.resolve(layout: layout, catalog: modules, prefs: .init(enabled: false), items: items, free: entries, grids: grids).isEmpty)
        let baseline = HousePetWorld(layout: layout, catalog: modules, spots: spots)
        let world = HousePetWorld(layout: layout, catalog: modules, spots: spots, decor: placements, items: items)
        #expect(world.nodes.count == baseline.nodes.count - 5)
        #expect(!world.nodes.contains { HouseFreeDecor.footprint(cell: [2, 2], size: "L").contains(.init($0.col, $0.row)) })
        #expect(world.spots.contains { $0.id == "room/decor/free:f2" && $0.kind == "sleep" })
        let before = try #require(baseline.spots.first { $0.id == "room/sleep" })
        let after = try #require(world.spots.first { $0.id == "room/sleep" })
        #expect(baseline.nodes[before.node].point == world.nodes[after.node].point)
        for node in world.nodes { #expect(!world.path(from: 0, to: node.id).isEmpty) }
    }
    @Test func undoRoundTripAndConcurrentEditInvalidation() throws {
        let before = HouseFile(); var file = before
        file.setFreeDecor(home: "h", key: "room/f1", item: "plant", cell: [2, 2])
        let edit = try #require(HouseEdit.diff(label: "free", home: "h", before: before, after: file))
        #expect(edit.matches(file, side: .after))
        edit.apply(.before, to: &file); #expect(edit.matches(file, side: .before))
        edit.apply(.after, to: &file); #expect(edit.matches(file, side: .after))
        file.setFreeDecor(home: "h", key: "room/f1", item: "plant", cell: [3, 2])
        #expect(!edit.matches(file, side: .after))
    }
}
