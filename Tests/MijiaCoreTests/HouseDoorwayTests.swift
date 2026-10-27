import Foundation
import CoreGraphics
import Testing
@testable import MijiaCore

@Suite struct HouseDoorwayTests {
    @Test func snapshotCoverage() throws {
        let catalog = try HousePetTests.catalog()
        for (name, cells) in HouseSnapshotLayouts.all {
            let coverage = HouseDoorwayPlanner.coverage(layout: cells, catalog: catalog)
            let doors = coverage.doorways
            #expect(coverage.uncovered.isEmpty, "\(name): unresolved furniture-safe doorways")
            for (index, first) in cells.enumerated() {
                for second in cells.dropFirst(index + 1) {
                    let firstArt = catalog.modules[first.module]!, secondArt = catalog.modules[second.module]!
                    let adjoining = ((first.col + firstArt.fw == second.col || second.col + secondArt.fw == first.col)
                        && max(first.row, second.row) < min(first.row + firstArt.fh, second.row + secondArt.fh))
                        || ((first.row + firstArt.fh == second.row || second.row + secondArt.fh == first.row)
                        && max(first.col, second.col) < min(first.col + firstArt.fw, second.col + secondArt.fw))
                    guard adjoining else { continue }
                    let eligible = abs(HouseLevels.elevation(first) - HouseLevels.elevation(second)) <= 48
                    #expect(doors.contains { $0.connects(first.room, second.room) } == eligible, "\(name): \(first.module)-\(second.module)")
                }
            }
            print("DOORWAYS \(name): " + doors.map { "\($0.back.module)-\($0.front.module)=\($0.width), stairs=\($0.stairs), depth=\($0.approachDepth), fallback=\($0.usedFallback), fixtureOverlap=\($0.overlapsWallFixture)" }.joined(separator: "; "))
        }
    }
    static func catalog(width: Int = 1) throws -> HouseModuleCatalog {
        var catalog = try HousePetTests.catalog()
        var art = catalog.modules["generic"]!
        art.footprint = [width, 1]; art.lights = []; art.badges = []; art.decor = nil; art.doorwayRanges = nil; art.stairRanges = nil
        catalog.modules = ["generic": art]
        return catalog
    }

    @Test func fallbackUsesWidestSpanThenMidpoint() throws {
        var catalog = try Self.catalog()
        catalog.modules["generic"]!.doorwayRanges = ["nw": [[0.2, 0.41], [0.6, 0.85]]]
        catalog.modules["generic"]!.badges = [[70, 172]]
        let door = try #require(HouseDoorwayPlanner.plan(layout: Self.pair(), catalog: catalog).first)
        #expect(abs(door.width - 0.25) < 0.000001)
        #expect(abs(door.lower - 0.6) < 0.000001)
        catalog.modules["generic"]!.doorwayRanges = ["nw": [[0.25, 0.375]]]
        let coverage = HouseDoorwayPlanner.coverage(layout: Self.pair(), catalog: catalog)
        let fallback = try #require(coverage.doorways.first)
        #expect(coverage.uncovered.isEmpty)
        #expect(fallback.usedFallback)
        #expect(abs(fallback.width - 0.3) < 0.000001 && fallback.center == 0.5)
        var separated = Self.pair(level: 1); separated[0].level = -1
        #expect(HouseDoorwayPlanner.coverage(layout: separated, catalog: catalog).uncovered.isEmpty)
        #expect(HouseDoorwayPlanner.plan(layout: separated, catalog: catalog).isEmpty)
    }

    @Test func stairsShortenOnlyOnLowerSide() throws {
        var catalog = try Self.catalog()
        catalog.modules["generic"]!.doorwayRanges = ["nw": [[0.2, 0.8]], "se": [[0.2, 0.8]]]
        catalog.modules["generic"]!.stairRanges = ["3": ["nw": [], "se": []], "2": ["nw": [[0.2, 0.8]], "se": [[0.2, 0.8]]]]
        for level in [-1, 1] {
            let door = try #require(HouseDoorwayPlanner.plan(layout: Self.pair(level: level), catalog: catalog).first)
            #expect(door.approachDepth == 0.25 && door.stairs)
            let low = HouseLevels.elevation(door.back) < HouseLevels.elevation(door.front) ? door.back : door.front
            #expect(door.floorLift(in: low, u: door.boundary, v: door.center) == 48)
        }
    }

    @Test func snapshotPetWalksAcrossDoorwayWithoutJumping() throws {
        let world = HousePetWorld(layout: HouseSnapshotLayouts.pets, catalog: try HousePetTests.catalog(), spots: try HousePetTests.spots())
        let start = try #require(world.nodes.first { node in
            node.room == "bedroom" && world.edges[node.id].contains { !$0.jump && world.nodes[$0.node].room == "study" }
        })
        let crossing = try #require(world.edges[start.id].first { !$0.jump && world.nodes[$0.node].room == "study" })
        let destination = try #require(world.edges[crossing.node].first { world.nodes[$0.node].room == "study" })
        let route = world.path(from: start.id, to: destination.node)
        #expect(route.count >= 3)
        #expect(route.last == destination.node)
        #expect(zip(route, route.dropFirst()).allSatisfy { left, right in world.edges[left].contains { $0.node == right && !$0.jump } })
    }

    static func pair(axis: HouseDoorway.Axis = .u, level: Int = 0) -> [HouseLayoutCell] {
        [.init(room: "rear", module: "generic", col: 0, row: 0, level: 0),
         .init(room: "front", module: "generic", col: axis == .u ? 1 : 0, row: axis == .v ? 1 : 0, level: level)]
    }

    static func world(axis: HouseDoorway.Axis = .u, level: Int = 0) throws -> HousePetWorld {
        let module = HousePetSpots.Module(grid: [8, 8], walk: Array(repeating: "........", count: 8), spots: [])
        let spots = HousePetSpots(cellsPerGrid: 8, artSets: ["cozy-wood": "test"], sets: ["test": ["generic": module]])
        return HousePetWorld(layout: pair(axis: axis, level: level), catalog: try catalog(), spots: spots)
    }

    @Test func deterministicIntersectionsAndWidth() throws {
        var catalog = try Self.catalog()
        catalog.modules["generic"]!.doorwayRanges = ["se": [[0.2, 0.7]], "nw": [[0.3, 0.8]]]
        let layout = Self.pair()
        let plan = HouseDoorwayPlanner.plan(layout: layout, catalog: catalog)
        #expect(plan == HouseDoorwayPlanner.plan(layout: layout.reversed(), catalog: catalog))
        let doorway = try #require(plan.first)
        #expect(plan.count == 1)
        #expect(abs(doorway.width - 0.3) < 0.000001)
        #expect(doorway.lower >= 0.3 && doorway.upper <= 0.7)
        #expect(doorway.center == 0.5)
        catalog.modules["generic"]!.doorwayRanges = ["nw": []]
        #expect(HouseDoorwayPlanner.plan(layout: layout, catalog: catalog).first?.usedFallback == true)
        catalog.modules["generic"]!.doorwayRanges = ["nw": [[0.1, 0.2]], "se": [[0.8, 0.9]]]
        #expect(HouseDoorwayPlanner.plan(layout: layout, catalog: catalog).first?.center == 0.5)
    }

    @Test func everyAdjoiningPairFlatAndSplitLevels() throws {
        let catalog = try Self.catalog()
        for split in [false, true] {
            let cells = (0..<2).flatMap { row in (0..<3).map { col in
                HouseLayoutCell(room: "\(row)-\(col)", module: "generic", col: col, row: row, level: split ? (row + col) % 2 : 0)
            } }
            let doors = HouseDoorwayPlanner.plan(layout: cells, catalog: catalog)
            #expect(doors.count == 7)
            #expect(doors.allSatisfy { $0.stairs == split && abs($0.width - 0.3) < 0.000001 })
        }
        for axis in [HouseDoorway.Axis.u, .v] {
            var cells = Self.pair(axis: axis, level: 1); cells[0].level = -1
            #expect(HouseDoorwayPlanner.plan(layout: cells, catalog: catalog).isEmpty)
            cells[1].level = 0
            #expect(HouseDoorwayPlanner.plan(layout: cells, catalog: catalog).count == 1)
        }
    }

    @Test func partialTwoCellSpanAndNonAdjacentRooms() throws {
        var catalog = try Self.catalog()
        var wide = catalog.modules["generic"]!; wide.footprint = [2, 1]
        catalog.modules["wide"] = wide
        let cells: [HouseLayoutCell] = [.init(room: "back", module: "generic", col: 1, row: 0, level: 0),
                                       .init(room: "wide", module: "wide", col: 0, row: 1, level: 0)]
        let doorway = try #require(HouseDoorwayPlanner.plan(layout: cells, catalog: catalog).first)
        #expect(doorway.axis == .v && doorway.lower >= 1.12 && doorway.upper <= 1.88)
        var apart = Self.pair(); apart[1].row = 1
        #expect(HouseDoorwayPlanner.plan(layout: apart, catalog: catalog).isEmpty)
    }

    @Test func legacyCatalogAndFixtureExclusions() throws {
        var catalog = try Self.catalog()
        let encoded = try JSONEncoder().encode(catalog)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("doorwayRanges"))
        let legacy = try JSONDecoder().decode(HouseModuleCatalog.self, from: encoded)
        #expect(HouseDoorwayPlanner.plan(layout: Self.pair(), catalog: legacy).count == 1)
        let fixture = try JSONDecoder().decode(HouseModuleLight.self, from: Data("""
        {"id":"fixture","role":"ac","wall":"nw","anchor":[154,130],"body":[[148,120],[160,120],[160,140],[148,140]]}
        """.utf8))
        catalog.modules["generic"]!.lights = [fixture]
        let ranges = HouseDoorwayPlanner.ranges(catalog.modules["generic"]!, wall: "nw")
        #expect(ranges.allSatisfy { !$0.contains(0.2) })
        let plan = HouseDoorwayPlanner.plan(layout: Self.pair(), catalog: catalog)
        #expect(plan.count == 1 && plan.allSatisfy { !$0.contains(along: 0.2) })
    }

    @Test func shippedCatalogsHaveUsableAuthoredRanges() throws {
        let root = HousePetTests.root
        let paths = ["assets/house/modules/catalog.json", "Sources/MijiaBarApp/Resources/House/modules/catalog.json"]
            + ["light-wood", "walnut", "japanese", "modern"].map { "assets/house/styles/\($0)/modules/catalog.json" }
        for path in paths {
            let catalog = try HouseComposer.loadCatalog(from: root.appendingPathComponent(path))
            for art in catalog.modules.values {
                #expect(Set(art.doorwayRanges?.keys.map { $0 } ?? []) == ["nw", "ne", "sw", "se"])
                for intervals in art.doorwayRanges?.values ?? [:].values {
                    #expect(intervals.contains { $0.count == 2 && $0[1] - $0[0] >= 0.3 - 0.000001 })
                }
            }
            let cells: [HouseLayoutCell] = [.init(room: "back", module: "bedroom", col: 0, row: 0, level: 1),
                                           .init(room: "front", module: "study", col: 1, row: 0, level: 0)]
            let world = HousePetWorld(layout: cells, catalog: catalog, spots: try HousePetTests.spots())
            let doorway = try #require(world.doorways.first)
            #expect(doorway.stairs && doorway.lower >= 0.625)
            #expect(world.edges.joined().contains { $0.stairs && !$0.jump })
        }
        let source = try HouseComposer.loadCatalog(from: root.appendingPathComponent(paths[0]))
        let bundled = try HouseComposer.loadCatalog(from: root.appendingPathComponent(paths[1]))
        #expect(source == bundled)
    }

    @Test func midpointFallbackNudgesOnlyForSharedWallBodies() throws {
        var catalog = try Self.catalog()
        catalog.modules["generic"]!.doorwayRanges = ["nw": []]
        var fixture = try JSONDecoder().decode(HouseModuleLight.self, from: Data("""
        {"id":"fixture","role":"ac","wall":"nw","body":[[116,100],[132,100],[132,120],[116,120]]}
        """.utf8))
        catalog.modules["generic"]!.lights = [fixture]
        let nudged = try #require(HouseDoorwayPlanner.plan(layout: Self.pair(), catalog: catalog).first)
        #expect(nudged.usedFallback && !nudged.overlapsWallFixture && nudged.center != 0.5)
        #expect(nudged.lower >= 0 && nudged.upper <= 1)
        fixture.wall = "ne"
        catalog.modules["generic"]!.lights = [fixture]
        #expect(HouseDoorwayPlanner.plan(layout: Self.pair(), catalog: catalog).first?.center == 0.5)
        fixture.wall = "nw"; fixture.role = "light"
        catalog.modules["generic"]!.lights = [fixture]
        #expect(HouseDoorwayPlanner.plan(layout: Self.pair(), catalog: catalog).first?.center == 0.5)
        fixture.role = "curtain"; fixture.body = [[20, 100], [200, 100], [200, 140], [20, 140]]
        catalog.modules["generic"]!.lights = [fixture]
        let forced = try #require(HouseDoorwayPlanner.plan(layout: Self.pair(), catalog: catalog).first)
        #expect(forced.usedFallback && forced.overlapsWallFixture && forced.center == 0.5)
    }

    @Test func everySnapshotDoorwayHasWalkingAccess() throws {
        let catalog = try HousePetTests.catalog(), source = try HousePetTests.spots()
        for (name, layout) in HouseSnapshotLayouts.all {
            let world = HousePetWorld(layout: layout, catalog: catalog, spots: source)
            for doorway in world.doorways {
                let rear = HouseDecor.roomKey(doorway.back), front = HouseDecor.roomKey(doorway.front)
                let start = try #require(world.nodes.first { node in
                    node.room == rear && world.edges[node.id].contains { !$0.jump && world.nodes[$0.node].room == front }
                }, "\(name): \(rear)-\(front)")
                let crossing = try #require(world.edges[start.id].first { !$0.jump && world.nodes[$0.node].room == front })
                #expect(crossing.stairs == doorway.stairs)
                for entry in [start.id, crossing.node] {
                    var queue = [entry], visited: Set<Int> = [entry], cursor = 0, reachedFloor = false
                    while cursor < queue.count {
                        let current = queue[cursor]; cursor += 1
                        let node = world.nodes[current]
                        let walk = source.sets["cozy"]![node.module]!.walk.map(Array.init)
                        if walk[node.row][node.col] == "." { reachedFloor = true; break }
                        for edge in world.edges[current] where !edge.jump && world.nodes[edge.node].room == node.room {
                            if visited.insert(edge.node).inserted { queue.append(edge.node) }
                        }
                    }
                    #expect(reachedFloor, "\(name): doorway connects to existing room floor")
                }
                #expect(world.path(from: start.id, to: crossing.node) == [start.id, crossing.node])
            }
        }
    }

    @Test func walkStairEdgesAndJumpCost() throws {
        for axis in [HouseDoorway.Axis.u, .v] {
            for level in [-1, 0, 1] {
                let world = try Self.world(axis: axis, level: level)
                let cross = world.nodes.flatMap { node in world.edges[node.id].filter { world.nodes[$0.node].room != node.room } }
                #expect(cross.contains { !$0.jump && $0.stairs == (level != 0) })
                #expect(cross.contains { $0.jump })
                for node in world.nodes {
                    for edge in world.edges[node.id] where !edge.jump && world.nodes[edge.node].room != node.room {
                        #expect(world.doorways[0].contains(along: (Double(axis == .u ? node.v : node.u) + 0.5) / 8))
                    }
                }
            }
        }
        let world = try Self.world()
        let from = try #require(world.nodes.first { $0.room == "rear" && $0.col == 7 && $0.row == 1 })
        let to = try #require(world.nodes.first { $0.room == "front" && $0.col == 0 && $0.row == 1 })
        #expect(world.edges[from.id].contains { $0.node == to.id && $0.jump })
        let route = world.path(from: from.id, to: to.id)
        #expect(route.count > 2)
        #expect(zip(route, route.dropFirst()).allSatisfy { left, right in world.edges[left].contains { $0.node == right && !$0.jump } })
    }

    @Test func stairsUseWalkingSpeedAndGradualElevation() throws {
        for level in [-1, 1] {
            let world = try Self.world(level: level), doorway = world.doorways[0]
            let lowCell = level == 1 ? doorway.back : doorway.front
            let direction = level == 1 ? -1.0 : 1.0
            let lifts = [0.3, 0.2, 0.1, 0.0].map { doorway.floorLift(in: lowCell, u: doorway.boundary + direction * $0, v: doorway.center) }
            #expect(zip(lifts, lifts.dropFirst()).allSatisfy { $0 < $1 })
            #expect(abs(lifts.last! - 48) < 0.000001)
            let from = try #require(world.nodes.first { node in world.edges[node.id].contains( where: \.stairs) })
            let edge = try #require(world.edges[from.id].first { $0.stairs }), to = world.nodes[edge.node]
            let target = HousePetWorld.Spot(id: "test", kind: "sit", node: to.id, point: to.point, facing: "SE", priority: 1)
            var actions: [String] = [], durations: [Double] = []
            HousePetBehavior.travel(path: [from.id, to.id], from: from.point, target: target, world: world) { start, end, _, _, action, duration in
                actions.append(action); durations.append(duration)
                #expect(abs(duration - start.distance(to: end) / 36) < 0.000001)
            }
            #expect(actions == ["walk"] && durations.count == 1)
        }
    }

    @Test func composerCutsRealPixelsInBothPhases() throws {
        for phase in ["day", "night"] {
            let (original, images) = try HouseComposerTests.load(phase)
            var catalog = try Self.catalog()
            catalog.modules["generic"]!.variants = original.modules["generic"]!.variants
            for axis in [HouseDoorway.Axis.u, .v] {
                for level in [-1, 0, 1] {
                    let cells = Self.pair(axis: axis, level: level)
                    let with = HouseComposer.compose(.init(layout: cells, catalog: catalog, images: images, night: phase == "night"))
                    var shifted = catalog
                    shifted.modules["generic"]!.doorwayRanges = ["nw": [[0.02, 0.32]], "ne": [[0.02, 0.32]], "sw": [[0.02, 0.32]], "se": [[0.02, 0.32]]]
                    let without = HouseComposer.compose(.init(layout: cells, catalog: shifted, images: images, night: phase == "night"))
                    #expect(with.width == without.width && with.height == without.height)
                    let doorway = try #require(HouseDoorwayPlanner.plan(layout: cells, catalog: catalog).first)
                    let point = HouseComposer.doorwayPoint(doorway, along: doorway.center, elevation: Double(HouseLevels.elevation(doorway.front)) + 20,
                                                          originX: with.originX, originY: with.originY)
                    let scene = try #require(JSONSerialization.jsonObject(with: with.sceneJSON) as? [String: Any])
                    let modules = try #require(scene["modules"] as? [String: [String: Any]])
                    func contains(_ polygons: [[[Double]]]) -> Bool {
                        let path = CGMutablePath()
                        for polygon in polygons {
                            path.addLines(between: polygon.map { CGPoint(x: $0[0], y: $0[1]) }); path.closeSubpath()
                        }
                        return path.contains(CGPoint(x: point.x, y: point.y), using: .evenOdd)
                    }
                    for room in ["rear", "front"] {
                        #expect(contains(try #require(modules[room]?["petVisible"] as? [[[Double]]])))
                    }
                    #expect(!contains(try #require(modules["front"]?["visible"] as? [[[Double]]])))
                    for (opened, closed) in [(with.unlit, without.unlit), (with.lit, without.lit)] {
                        let first = try #require(opened), second = try #require(closed)
                        let firstData = try #require(first.dataProvider?.data), secondData = try #require(second.dataProvider?.data)
                        let firstBytes = try #require(CFDataGetBytePtr(firstData)), secondBytes = try #require(CFDataGetBytePtr(secondData))
                        let offset = point.y * first.bytesPerRow + point.x * 4
                        #expect((0..<4).contains { firstBytes[offset + $0] != secondBytes[offset + $0] })
                    }
                }
            }
        }
    }

    @Test func doorwayDetailsRemainVisibleAfterComposition() throws {
        for phase in ["day", "night"] {
            let (original, images) = try HouseComposerTests.load(phase)
            var catalog = try Self.catalog()
            catalog.modules["generic"]!.variants = original.modules["generic"]!.variants
            let palette = HouseComposer.Palette(night: phase == "night")
            for axis in [HouseDoorway.Axis.u, .v] {
                for level in [-1, 0, 1] {
                    let cells = Self.pair(axis: axis, level: level)
                    let result = HouseComposer.compose(.init(layout: cells, catalog: catalog, images: images, night: phase == "night"))
                    let doorway = try #require(HouseDoorwayPlanner.plan(layout: cells, catalog: catalog).first)
                    let low = Double(min(HouseLevels.elevation(doorway.back), HouseLevels.elevation(doorway.front)))
                    let high = Double(max(HouseLevels.elevation(doorway.back), HouseLevels.elevation(doorway.front)))
                    for image in [result.unlit, result.lit] {
                        let pixels = try #require(image)
                        let data = try #require(pixels.dataProvider?.data), bytes = try #require(CFDataGetBytePtr(data))
                        func check(_ color: CGColor, along: Double, across: Double = 0, elevation: Double, radius: Int = 2) {
                            let position = HouseComposer.doorwayPoint(doorway, along: along, across: across, elevation: elevation,
                                                                     originX: result.originX, originY: result.originY)
                            let swatch = HouseComposer.Canvas(width: 4, height: 4)!
                            swatch.poly([(0, 0), (4, 0), (4, 4), (0, 4)], fill: color)
                            let swatchData = swatch.ctx.makeImage()!.dataProvider!.data!
                            let expected = CFDataGetBytePtr(swatchData)!
                            var count = 0
                            for row in max(0, position.y - radius)...min(pixels.height - 1, position.y + radius) {
                                for column in max(0, position.x - radius)...min(pixels.width - 1, position.x + radius) {
                                    let offset = row * pixels.bytesPerRow + column * 4
                                    if (0..<3).allSatisfy({ abs(Int(bytes[offset + $0]) - Int(expected[$0])) < 2 }) { count += 1 }
                                }
                            }
                            #expect(count >= 2, "\(phase) \(axis) level \(level): missing detail at \(along),\(across),\(elevation)")
                        }
                        for along in [doorway.lower, doorway.upper] {
                            check(palette.jamb, along: along, elevation: high + 20)
                            check(palette.doorwayEdge, along: along, elevation: high + 20)
                        }
                        check(palette.tread, along: doorway.center, elevation: high + 1)
                        if doorway.stairs {
                            let direction = HouseLevels.elevation(doorway.front) < HouseLevels.elevation(doorway.back) ? 1.0 : -1.0
                            for step in 0..<3 {
                                let outer = direction * Double(3 - step) * doorway.approachDepth / 3
                                let middle = direction * (Double(3 - step) - 0.5) * doorway.approachDepth / 3
                                check(palette.tread, along: doorway.center, across: middle, elevation: low + Double(step + 1) * 16)
                                check(palette.riser, along: doorway.center, across: outer, elevation: low + Double(step) * 16 + (direction < 0 ? 2 : 8))
                            }
                        }
                    }
                }
            }
        }
    }
}
