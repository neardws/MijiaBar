import Foundation
import CoreGraphics
import Testing
@testable import MijiaCore

@Suite struct HousePetTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let directory = root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/pets")
    static func rig() throws -> HousePetRig { try .load(from: directory.appendingPathComponent("cat-short.json")) }
    static func spots() throws -> HousePetSpots { try .load(from: directory.appendingPathComponent("pet-spots.json")) }
    static func catalog() throws -> HouseModuleCatalog { try HouseComposer.loadCatalog(from: root.appendingPathComponent("assets/house/modules/catalog.json")) }
    static func world(level: Int = 0) throws -> HousePetWorld {
        .init(layout: [.init(room: "a", module: "living", col: 0, row: 0, level: 0),
                       .init(room: "b", module: "bedroom", col: 2, row: 0, level: level),
                       .init(room: "c", module: "study", col: 0, row: 1, level: 0),
                       .init(room: "d", module: "kitchen", col: 1, row: 1, level: 0),
                       .init(room: "e", module: "bathroom", col: 2, row: 1, level: level)],
              catalog: try catalog(), spots: try spots())
    }

    @Test func goldenRecolorAndEncodedPixels() throws {
        struct Golden: Decodable {
            struct Sample: Decodable { var pattern: String; var x: Int; var y: Int; var encoded: [UInt8]; var rgba: [UInt8]; var palette: HousePetPalette; var lighting: String }
            var samples: [Sample]
        }
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: Self.root.appendingPathComponent("Tests/Fixtures/pets/cat-short-golden.json")))
        let rig = try Self.rig()
        var sheets: [String: HousePetSheet] = [:]
        for pattern in rig.patterns { sheets[pattern] = try .load(from: Self.directory.appendingPathComponent(rig.sheets[pattern]!)) }
        #expect(golden.samples.count > 10)
        for sample in golden.samples {
            let output = HousePetRecolor.pixel(sample.encoded, palette: sample.palette, lighting: try #require(rig.lighting[sample.lighting]))
            #expect(zip(output, sample.rgba).allSatisfy { abs(Int($0) - Int($1)) <= 2 })
            let sheet = try #require(sheets[sample.pattern]), offset = (sample.y * sheet.width + sample.x) * 4
            #expect(Array(sheet.rgba[offset..<offset + 4]) == sample.encoded)
        }
        for sheet in sheets.values {
            #expect(stride(from: 3, to: sheet.rgba.count, by: 4).contains { sheet.rgba[$0] > 0 && sheet.rgba[$0] < 255 })
            #expect(stride(from: 3, to: sheet.rgba.count, by: 4).contains { sheet.rgba[$0] == 255 })
        }
    }

    @Test func rawDecoderHonorsByteOrderAndStride() throws {
        for (alpha, order, bytes) in [(CGImageAlphaInfo.first, CGBitmapInfo.byteOrder32Big, [UInt8](arrayLiteral: 102, 10, 0, 0, 0, 0, 0, 0)),
                                      (.first, .byteOrder32Little, [0, 0, 10, 102, 0, 0, 0, 0]),
                                      (.last, .byteOrder32Big, [10, 0, 0, 102, 0, 0, 0, 0]),
                                      (.last, .byteOrder32Little, [102, 0, 0, 10, 0, 0, 0, 0])] {
            let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
            let image = try #require(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: order.union(.init(rawValue: alpha.rawValue)),
                                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
            #expect(try HousePetSheet.decode(image).rgba == [10, 0, 0, 102])
        }
    }

    @Test func framesMirrorAndCache() throws {
        let rig = try Self.rig(), cache = HousePetFrameCache(), pet = HousePet(id: "p_1234")
        let frames = try cache.frames(pet: pet, rig: rig, directory: Self.directory, phase: "day")
        #expect(frames.count == rig.frameCount)
        #expect(frames[0].width == rig.frameSize[0]); #expect(frames[0].height == rig.frameSize[1])
        #expect(frames[0].shouldInterpolate == false)
        #expect(try cache.frames(pet: pet, rig: rig, directory: Self.directory, phase: "day")[0] === frames[0])
        for (left, right) in [("SW", "SE"), ("NW", "NE")] {
            #expect(rig.frame(action: "walk", facing: left, elapsed: 1).index == rig.frame(action: "walk", facing: right, elapsed: 1).index)
            #expect(rig.frame(action: "walk", facing: left, elapsed: 1).mirrored)
            #expect(!rig.frame(action: "walk", facing: right, elapsed: 1).mirrored)
        }
        #expect(rig.frame(action: "jump", facing: "SE", elapsed: 100).index == rig.actions["jump"]?.frames["SE"]?.last)
    }

    @Test func oldDecodingMergeTombstonesAndLimit() throws {
        let old = try HouseFile.decode(Data(#"{"homes":{"h":{}}}"#.utf8))
        #expect(old.homes["h"]?.pets == nil); #expect(old.homes["h"]?.petPrefs == nil)
        let minimal = try JSONDecoder().decode(HousePet.self, from: Data("{}".utf8))
        #expect(minimal.enabled && !minimal.deleted && minimal.rig == "cat-short" && minimal.palette.isValid)
        #expect(try JSONDecoder().decode(HousePetPrefs.self, from: Data("{}".utf8)).enabled)
        let now = Date(timeIntervalSince1970: 1800000000)
        var first = old
        for index in 0..<3 { try first.setPet(home: "h", pet: .init(id: "p_100\(index)", updatedAt: now)) }
        #expect(throws: HousePetError.self) { try first.setPet(home: "h", pet: .init(id: "p_abcd")) }
        var second = first, removed = try #require(first.homes["h"]?.pets?["p_1000"])
        removed.deleted = true; removed.updatedAt = now.addingTimeInterval(10)
        try second.setPet(home: "h", pet: removed); second.setPetPrefs(home: "h", enabled: false, now: now)
        try second.setPet(home: "h", pet: .init(id: "p_abcd", updatedAt: now))
        let merged = HouseFile.merge(first, second)
        #expect(merged.homes["h"]?.pets?[removed.id]?.deleted == true)
        #expect(merged.homes["h"]?.petPrefs?.enabled == false)
        #expect(HouseFile.merge(second, first) == merged)
        var pruned = merged; pruned.prune(now: now.addingTimeInterval(86400 * 60))
        #expect(pruned.homes["h"]?.pets?[removed.id]?.deleted == true)
        #expect(try HouseFile.decode(merged.encoded()) == merged)
        var missingDate = HouseFile(); missingDate.homes["h"] = .init(); missingDate.homes["h"]?.pets = ["p_0000": .init(id: "p_0000", updatedAt: .distantPast)]
        #expect(HouseFile.merge(.init(), missingDate).homes["h"]?.pets?.count == 1)
    }

    static func photo(_ pixel: (Int, Int) -> [UInt8]) throws -> HousePetPhoto.Result {
        var rgba: [UInt8] = []
        for row in 0..<64 { for col in 0..<64 { rgba += pixel(col, row) + [255] } }
        return try HousePetPhoto.analyze(rgba: rgba, width: 64, height: 64)
    }
    @Test func syntheticPhotoPatterns() throws {
        let orange: [UInt8] = [210, 140, 65], white: [UInt8] = [245, 240, 232], black: [UInt8] = [28, 26, 30]
        let tabby = try Self.photo { _, _ in orange }
        #expect(tabby.pattern == "tabby"); #expect(tabby.palette.eye == "#D8A53C")
        #expect(try Self.photo { col, _ in col < 22 ? white : orange }.pattern == "tabbyWhite")
        #expect(try Self.photo { col, _ in col < 32 ? white : black }.pattern == "bicolor")
        #expect(try Self.photo { col, _ in col < 21 ? white : col < 42 ? orange : black }.pattern == "calico")
        let pointed = try Self.photo { col, row in col < 12 || col > 52 || row < 10 ? black : [232, 218, 192] }
        #expect(pointed.pattern == "colorpoint"); #expect(pointed.palette.eye == "#4E8FE0")
        #expect(try Self.photo { col, _ in col < 16 ? [130, 85, 35] : orange }.pattern == "tabby")
        #expect(try Self.photo { col, _ in col < 16 ? white : col < 32 ? [130, 85, 35] : orange }.pattern == "tabbyWhite")
        #expect(try Self.photo { _, _ in orange } == tabby)
        let override = try HousePetPhoto.analyze(rgba: [210, 140, 65, 255], width: 1, height: 1, eye: "#010203")
        #expect(override.palette.eye == "#010203")
        #expect(throws: HousePetError.self) { try HousePetPhoto.analyze(rgba: [0, 0, 0, 255], width: 1, height: 1, mask: [0]) }
        #expect(HousePetForeground.ellipse(width: 64, height: 64)[32 * 64 + 32] == 255)
        #expect(HousePetForeground.ellipse(width: 64, height: 64)[0] == 0)
    }

    @Test func walkGridsAndSpots() throws {
        let source = try Self.spots()
        for modules in source.sets.values {
            for module in modules.values {
                let rows = module.walk.map(Array.init)
                #expect(rows.flatMap { $0 }.filter { $0 == "." }.count >= 12)
                for spot in module.spots {
                    let col = Int(spot.at[0] * Double(source.cellsPerGrid)), row = Int(spot.at[1] * Double(source.cellsPerGrid))
                    if let from = spot.from {
                        #expect(from.count == 2 && rows.indices.contains(from[1]) && rows[from[1]].indices.contains(from[0]) && rows[from[1]][from[0]] == ".")
                    } else { #expect(rows.indices.contains(row) && rows[row].indices.contains(col) && rows[row][col] == ".") }
                }
            }
        }
    }

    @Test func pathsAcrossThreeByTwoAndLevels() throws {
        for level in [0, 1] {
            let world = try Self.world(level: level), from = try #require(world.nodes.first { $0.room == "c" }), to = try #require(world.nodes.first { $0.room == "b" })
            let path = world.path(from: from.id, to: to.id)
            #expect(path.count > 2)
            #expect(zip(path, path.dropFirst()).contains { left, right in world.edges[left].contains { $0.node == right && $0.jump } })
            #expect(world.path(from: from.id, to: to.id, room: "c").isEmpty)
        }
        let catalog = try Self.catalog(), spots = try Self.spots()
        let layout: [HouseLayoutCell] = [.init(room: "a", module: "study", col: 0, row: 0, level: -1), .init(room: "b", module: "bedroom", col: 1, row: 0, level: 1)]
        let blocked = HousePetWorld(layout: layout, catalog: catalog, spots: spots)
        #expect(blocked.path(from: 0, to: try #require(blocked.nodes.first { $0.room == "b" }).id).isEmpty)
        let shifted = HousePetWorld(layout: layout, catalog: catalog, spots: spots, origin: .init(x: -24, y: -100))
        #expect(shifted.nodes[0].point.x == blocked.nodes[0].point.x + 24)
        #expect(shifted.nodes[0].point.y == blocked.nodes[0].point.y + 100)
    }

    @Test func behaviorDeterminismReactionsAndRestOnly() throws {
        let world = try Self.world(), behavior = HousePetBehavior(rig: try Self.rig()), date = Date(timeIntervalSince1970: 1792270000)
        let pet = HousePet(id: "p_1234", homeRoom: "a"), context = HousePetContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(behavior.pose(pet, world: world, context: context, at: date) == HousePetBehavior(rig: try Self.rig()).pose(pet, world: world, context: context, at: date))
        let dark = HousePetContext(night: true, changedAt: date, timeZone: context.timeZone)
        let sleeping = behavior.pose(pet, world: world, context: dark, at: date.addingTimeInterval(600))
        #expect(sleeping.action == "sleep" && sleeping.room == "a")
        let tv = HousePetContext(tvRooms: ["a"], changedAt: date, timeZone: context.timeZone)
        #expect(behavior.pose(pet, world: world, context: tv, at: date.addingTimeInterval(600)).action == "sit")
        let light = HousePetContext(lights: ["a": true], changedAt: date, changedRoom: "a", timeZone: context.timeZone)
        #expect(behavior.pose(pet, world: world, context: light, at: date.addingTimeInterval(1)).action == "lookup")
        for offset in stride(from: 0, to: 5000, by: 13) {
            var rest = context; rest.restOnly = true
            let pose = behavior.pose(pet, world: world, context: rest, at: date.addingTimeInterval(Double(offset)))
            #expect(["idle", "sit", "sleep"].contains(pose.action)); #expect(pose.jumpLift == 0); #expect(pose.room == "a")
        }
    }

    @Test func posePerformanceIncludingColdPlansAndPathing() throws {
        let world = try Self.world(), behavior = HousePetBehavior(rig: try Self.rig()), date = Date(timeIntervalSince1970: 1792270000)
        let pets = (0..<3).map { HousePet(id: "p_123\($0)") }
        let context = HousePetContext(petIDs: pets.map(\.id), timeZone: TimeZone(secondsFromGMT: 0)!)
        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<1000 { _ = behavior.pose(pets[index % 3], world: world, context: context, at: date.addingTimeInterval(Double(index))) }
        let duration = CFAbsoluteTimeGetCurrent() - start
        print("HousePet pose ms: \(String(format: "%.2f", duration * 1000))")
        let budget = ProcessInfo.processInfo.environment["CI"] == nil ? 0.3 : 1.5
        #expect(duration < budget, "1000 cold pose queries took \(duration)s (budget \(budget)s)")
    }

    @Test func decorSleepPriorityAndLightPoolReactions() throws {
        let catalog = try Self.catalog(), source = try Self.spots()
        let items = try HouseDecorCatalog.load(from: Self.root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/decor/decor-catalog.json"))
        let layout: [HouseLayoutCell] = [.init(room: "balcony", module: "balcony", col: 0, row: 0, level: 0)]
        let decor = HouseDecor.resolve(layout: layout, catalog: catalog, items: items)
        #expect(decor.contains { $0.item == "cat_bed" })
        let world = HousePetWorld(layout: layout, catalog: catalog, spots: source, decor: decor, items: items)
        let sleep = try #require(world.spots.first { $0.priority == 0 })
        let light = try #require(world.spots.first { $0.kind == "light" })
        let behavior = HousePetBehavior(rig: try Self.rig()), pet = HousePet(id: "p_1234", homeRoom: "balcony")
        let date = Date(timeIntervalSince1970: 1792270000)
        let night = HousePetContext(night: true, changedAt: date)
        #expect(behavior.pose(pet, world: world, context: night, at: date.addingTimeInterval(300)).point == sleep.point)
        let lit = HousePetContext(lights: ["balcony": true], changedAt: date, changedRoom: "balcony")
        let pose = behavior.pose(pet, world: world, context: lit, at: date.addingTimeInterval(300))
        #expect(pose.point == light.point && pose.action == "sit")
    }

    @Test func nightSleepSpreadsRosterOverDistinctSpots() throws {
        let world = try Self.world(), rig = try Self.rig(), behavior = HousePetBehavior(rig: rig)
        let pets = ["p_1232", "p_1230", "p_1231"].map { HousePet(id: $0) }
        let spots = world.spots.filter { ["sleep", "perch"].contains($0.kind) }
            .sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority < $1.priority }
        let top = try #require(spots.first), date = Date(timeIntervalSince1970: 1792270000)
        let lowest = try #require(pets.min { $0.id < $1.id })
        for restOnly in [true, false] {
            let context = HousePetContext(night: true, lights: Dictionary(uniqueKeysWithValues: world.rooms.map { ($0, false) }),
                                          rooms: world.rooms, petIDs: pets.map(\.id), changedAt: date, restOnly: restOnly,
                                          timeZone: TimeZone(secondsFromGMT: 0)!)
            let time = date.addingTimeInterval(600)
            let poses = pets.map { behavior.pose($0, world: world, context: context, at: time) }
            for (pet, pose) in zip(pets, poses) {
                #expect(pose.visible && pose.action == "sleep")
                #expect(spots.contains { $0.point == pose.point })
                #expect(pose == HousePetBehavior(rig: rig).pose(pet, world: world, context: context, at: time))
            }
            #expect(behavior.pose(lowest, world: world, context: context, at: time).point == top.point)
            for left in 0..<2 { for right in (left + 1)..<3 {
                #expect(poses[left].point != poses[right].point)
                #expect(poses[left].point.distance(to: poses[right].point) >= 3 * world.cellSize - 0.001)
            } }
            #expect(behavior.poses(pets, world: world, context: context, at: time) == Dictionary(uniqueKeysWithValues: zip(pets.map(\.id), poses)))
        }
    }

    @Test func multiplePetsStaySeparatedAtRest() throws {
        let world = try Self.world(), behavior = HousePetBehavior(rig: try Self.rig())
        let pets = (0..<3).map { HousePet(id: "p_123\($0)", homeRoom: "a") }
        let date = Date(timeIntervalSince1970: 1792270000)
        for night in [false, true] {
            let context = HousePetContext(night: night, petIDs: pets.map(\.id), changedAt: date, restOnly: true)
            for offset in stride(from: 0, to: 1800, by: 17) {
                let poses = pets.map { behavior.pose($0, world: world, context: context, at: date.addingTimeInterval(Double(offset))) }
                for left in 0..<2 { for right in (left + 1)..<3 { #expect(poses[left].point.distance(to: poses[right].point) >= world.cellSize * 3 - 0.001) } }
            }
        }
    }

    @Test func reactionPetsKeepThreeCellsForTVAndLight() throws {
        let world = try Self.world(), behavior = HousePetBehavior(rig: try Self.rig())
        let pets = (0..<3).map { HousePet(id: "p_123\($0)", homeRoom: "a") }, date = Date(timeIntervalSince1970: 1792270000)
        for tv in [false, true] {
            let context = HousePetContext(lights: ["a": !tv], tvRooms: tv ? ["a"] : [], petIDs: pets.map(\.id), changedAt: date, changedRoom: "a", restOnly: true)
            let poses = pets.map { behavior.pose($0, world: world, context: context, at: date.addingTimeInterval(300)) }
            for left in 0..<2 { for right in (left + 1)..<3 { #expect(poses[left].point.distance(to: poses[right].point) >= world.cellSize * 3 - 0.001) } }
        }
    }

    @Test func spacingFallsBackOnlyForSmallRooms() {
        for (extent, spacing) in [(12, 5), (10, 5), (9, 3), (6, 3), (5, 2), (4, 2), (3, 1), (2, 1)] {
            let spots = (0...extent).map { HousePetWorld.Spot(id: "\($0)", kind: "sit", node: $0, point: .init(x: Double($0) * 10, y: 0), facing: "SE", priority: 1) }
            let selected = HousePetBehavior.separatedSpots(spots, count: 3, cellSize: 10)
            #expect(selected.count >= 3)
            for left in selected.indices { for right in selected.indices where right > left {
                #expect(selected[left].point.distance(to: selected[right].point) >= Double(spacing * 10))
            } }
            #expect(selected[0].point.distance(to: selected[1].point) == Double(spacing * 10))
        }
    }

    @Test func restOnlyRosterNeverPilesAtNight() throws {
        let world = try Self.world(), rig = try Self.rig()
        let behavior = HousePetBehavior(rig: rig), fresh = HousePetBehavior(rig: rig)
        let pets = ["p_100001", "p_100002", "p_100003"].sorted().map { HousePet(id: $0) }
        var violations = 0, moved = 0
        for day in 0..<30 {
            let date = Date(timeIntervalSince1970: 1792270000 + Double(day) * 86400)
            for changedAt in [nil, date] as [Date?] {
                let context = HousePetContext(night: true, lights: ["a": true], rooms: world.rooms,
                                              petIDs: pets.map(\.id), changedAt: changedAt, restOnly: true,
                                              timeZone: TimeZone(secondsFromGMT: 0)!)
                let time = date.addingTimeInterval(600)
                let singles = pets.map { behavior.pose($0, world: world, context: context, at: time) }
                let poses = behavior.poses(pets, world: world, context: context, at: time)
                #expect(poses == fresh.poses(Array(pets.reversed()), world: world, context: context, at: time))
                var placed: [HousePetPoint] = []
                for (index, pet) in pets.enumerated() {
                    let pose = try #require(poses[pet.id]), original = singles[index]
                    #expect(pose.visible)
                    if pose.point != original.point {
                        moved += 1
                        #expect(pose.room == original.room)
                        #expect(world.nodes.contains { $0.point == pose.point && $0.room == pose.room && $0.module == pose.module })
                        if world.nodes.contains(where: { node in
                            node.room == original.room && (pet.homeRoom == nil || node.room == pet.homeRoom)
                                && placed.allSatisfy { $0.distance(to: node.point) >= 3 * world.cellSize }
                        }) {
                            #expect(placed.allSatisfy { $0.distance(to: pose.point) >= 3 * world.cellSize - 0.001 })
                        }
                        var expected = original
                        expected.point = pose.point; expected.module = pose.module; expected.room = pose.room
                        #expect(pose == expected)
                    }
                    for other in pets.indices where other > index {
                        if singles[index].visible && singles[other].visible,
                           singles[index].point.distance(to: singles[other].point) < 3 * world.cellSize - 0.001 { violations += 1 }
                        let otherPose = try #require(poses[pets[other].id])
                        if pose.visible && otherPose.visible {
                            #expect(pose.point.distance(to: otherPose.point) >= 2 * world.cellSize - 0.001)
                        }
                    }
                    if pose.visible { placed.append(pose.point) }
                }
            }
        }
        #expect(violations > 0)
        #expect(moved > 0)
    }

    @Test func rosterPosesMatchSinglePosesWhenAnimated() throws {
        let world = try Self.world(), behavior = HousePetBehavior(rig: try Self.rig())
        let pets = ["p_100001", "p_100002", "p_100003"].map { HousePet(id: $0) }
        let date = Date(timeIntervalSince1970: 1792270000)
        for night in [false, true] {
            let context = HousePetContext(night: night, lights: ["a": true], rooms: world.rooms,
                                          petIDs: pets.map(\.id), changedAt: date, restOnly: false,
                                          timeZone: TimeZone(secondsFromGMT: 0)!)
            for offset in [0.0, 1, 10, 600, 3600] {
                let time = date.addingTimeInterval(offset)
                let expected = Dictionary(uniqueKeysWithValues: pets.map { ($0.id, behavior.pose($0, world: world, context: context, at: time)) })
                #expect(behavior.poses(pets, world: world, context: context, at: time) == expected)
            }
        }
    }

    @Test func restOnlyRosterRespectsHomeRoomAndOverrides() throws {
        let world = try Self.world(), behavior = HousePetBehavior(rig: try Self.rig())
        let pets = ["p_100001", "p_100002"].map { HousePet(id: $0, homeRoom: "a") }
        let date = Date(timeIntervalSince1970: 1792270000)
        let context = HousePetContext(night: true, rooms: world.rooms, petIDs: pets.map(\.id), restOnly: true,
                                      timeZone: TimeZone(secondsFromGMT: 0)!)
        let original = behavior.pose(pets[0], world: world, context: context, at: date)
        let overrides = [pets[1].id: original]
        let poses = behavior.poses(pets, world: world, context: context, at: date, overrides: overrides)
        #expect(poses[pets[1].id] == original)
        let moved = try #require(poses[pets[0].id])
        #expect(moved.point != original.point && moved.room == "a")
        let nearest = try #require(world.nodes.filter { $0.room == "a" && $0.point.distance(to: original.point) >= 3 * world.cellSize }
            .sorted {
                let left = $0.point.distance(to: original.point), right = $1.point.distance(to: original.point)
                return left == right ? $0.id < $1.id : left < right
            }.first)
        var expected = original
        expected.point = nearest.point; expected.module = nearest.module; expected.room = nearest.room
        #expect(moved == expected)
        var hidden = original; hidden.visible = false
        #expect(behavior.poses(pets, world: world, context: context, at: date, overrides: [pets[1].id: hidden])[pets[0].id] == original)
    }

    @Test func masksAndMissingRoomSafety() throws {
        let photo = try HousePetPhoto.analyze(rgba: [255, 255, 255, 255, 20, 20, 20, 255], width: 2, height: 1, mask: [0, 255])
        #expect(photo.pattern == "solid"); #expect(photo.palette.eye == "#E9C24A")
        let world = try Self.world(), behavior = HousePetBehavior(rig: try Self.rig()), date = Date(timeIntervalSince1970: 1792270000)
        #expect(!behavior.pose(.init(id: "p_1234", homeRoom: "missing"), world: world, at: date).visible)
        #expect(!behavior.pose(.init(id: "p_1234", enabled: false), world: world, at: date).visible)
        let before = behavior.pose(.init(id: "p_1234"), world: world, at: date)
        let future = HousePetContext(night: true, changedAt: date.addingTimeInterval(60))
        #expect(behavior.pose(.init(id: "p_1234"), world: world, context: future, at: date) == before)
        #expect(world.path(from: 0, to: try #require(world.nodes.first { $0.room == "b" }).id, allowedRooms: ["a"]).isEmpty)
    }

    @Test func invalidAssetsAreRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pet-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var rig = try Self.rig(); rig.sheets["solid"] = "../escape.png"
        try JSONEncoder().encode(rig).write(to: url)
        #expect(throws: HousePetError.self) { try HousePetRig.load(from: url) }
        rig = try Self.rig(); rig.actions["sit"]?.frames["SE"] = [rig.frameCount]
        try JSONEncoder().encode(rig).write(to: url)
        #expect(throws: HousePetError.self) { try HousePetRig.load(from: url) }
        var source = try Self.spots(); source.cellsPerGrid = 0
        try JSONEncoder().encode(source).write(to: url)
        #expect(throws: HousePetError.self) { try HousePetSpots.load(from: url) }
    }
}
