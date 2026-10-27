import Foundation
import CoreGraphics
import Testing
@testable import MijiaCore

@Suite struct HousePetOcclusionTests {
    @Test func loadsOptionalOccludersAndValidatesGeometry() throws {
        let source = try HousePetTests.spots()
        let living = try #require(source.sets["cozy"]?["living"])
        #expect(living.occluders?.map(\.id) == ["sofa", "coffee-table"])
        var legacy = living; legacy.occluders = nil
        let decoded = try JSONDecoder().decode(HousePetSpots.Module.self, from: JSONEncoder().encode(legacy))
        #expect(decoded.occluders == nil)
        var invalid = try #require(living.occluders?.first)
        invalid.footprint = [0, 1]
        #expect(!invalid.isValid)
        invalid.footprint = [1, 1, 0, 0]
        #expect(!invalid.isValid)
        invalid.footprint = [0, 0, 1, 1]; invalid.silhouette = [[0, 0], [1], [2, 2]]
        #expect(!invalid.isValid)
        var badSource = source; badSource.sets["cozy"]?["living"]?.occluders = [invalid]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pet-occluders-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(badSource).write(to: url)
        #expect(throws: HousePetError.self) { try HousePetSpots.load(from: url) }
        for style in ["cozy-wood", "light-wood", "walnut", "japanese", "modern"] {
            let artSet = try #require(source.artSets[style])
            let modules = try #require(source.sets[artSet])
            #expect(modules["living"]?.occluders?.count == 2)
            #expect(modules["bedroom"]?.occluders?.first?.id == "bed")
            #expect(modules["bathroom"]?.occluders?.first?.id == "vanity")
        }
    }

    @Test func transformsTipRelativePrismsAndExplicitSilhouettes() throws {
        let source = try HousePetTests.spots(), catalog = try HousePetTests.catalog()
        let tip = HousePetPoint(x: 310, y: 230)
        var definition = try #require(source.sets["cozy"]?["living"]?.occluders?.first)
        definition.silhouette = nil
        let local = definition.polygon(tip: .init(x: 0, y: 0)), scene = definition.polygon(tip: tip)
        #expect(local.count == 6)
        #expect(scene == local.map { [$0[0] + tip.x, $0[1] + tip.y] })
        definition.silhouette = [[0, -10], [20, 0], [0, 10]]
        #expect(definition.polygon(tip: tip) == [[310, 220], [330, 230], [310, 240]])
        let layout = [HouseLayoutCell(room: "a", module: "living", col: 2, row: 1, level: 1)]
        let origin = HousePetPoint(x: -100, y: -200)
        let world = HousePetWorld(layout: layout, catalog: catalog, spots: source, origin: origin)
        let furniture = try #require(world.occluders["a"]?.first)
        #expect(furniture.tip == .init(x: 260, y: 350))
        let offset = HousePetPoint(x: 70, y: 90), art = try #require(catalog.modules["living"])
        let shifted = HousePetWorld(layout: layout, catalog: catalog, spots: source, offsets: ["a": offset])
        #expect(shifted.occluders["a"]?.first?.tip == .init(x: offset.x + Double(art.tip[0]), y: offset.y + Double(art.tip[1])))
    }

    @Test func depthUsesCameraRayAndMatchingPerch() throws {
        let world = try HousePetTests.world()
        let sofa = try #require(world.occluders["a"]?.first)
        func pose(_ u: Double, _ v: Double, z: Double = 0) -> HousePetPose {
            .init(point: HousePetFurniture.project(u, v, tip: sofa.tip, z: z), module: "living", room: "a")
        }
        #expect(sofa.isActive(for: pose(0.1, 0.6)))
        #expect(sofa.isActive(for: pose(-0.1, 0.4)))
        #expect(!sofa.isActive(for: pose(0.6, 1.1)))
        #expect(!sofa.isActive(for: pose(0.375, 0.875)))
        #expect(!sofa.isActive(for: pose(1.5, 0.1)))
        var perched = pose(0.2, 0.55, z: 16)
        #expect(sofa.isActive(for: perched))
        perched.spotID = "a/sofa"
        #expect(!sofa.isActive(for: perched))
        perched.point.y += 1
        #expect(sofa.isActive(for: perched))
        #expect(sofa.isActive(for: pose(0.2, 0.55)))
        var otherRoom = pose(0.1, 0.6); otherRoom.room = "missing"
        #expect(HousePetOcclusion.holes(for: otherRoom, in: world).isEmpty)
        var otherModule = pose(0.1, 0.6); otherModule.module = "bedroom"
        #expect(!sofa.isActive(for: otherModule))
        let bed = try #require(world.spots.first { $0.id == "b/bed" })
        #expect(HousePetOcclusion.holes(for: .init(point: bed.point, module: "bedroom", room: "b", spotID: bed.id), in: world).isEmpty)
        let behavior = HousePetBehavior(rig: try HousePetTests.rig())
        let context = HousePetContext(night: true, restOnly: true, timeZone: TimeZone(secondsFromGMT: 0)!)
        let resting = behavior.pose(HousePet(id: "p_1234", homeRoom: "b"), world: world, context: context,
                                    at: Date(timeIntervalSince1970: 1792270000))
        #expect(resting.spotID == bed.id)
        #expect(HousePetOcclusion.holes(for: resting, in: world).isEmpty)
    }

    @Test func overlappingFurnitureHolesNeverRestorePixels() throws {
        let context = try #require(CGContext(data: nil, width: 30, height: 30, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: 30); context.scaleBy(x: 1, y: -1)
        HousePetOcclusion.clipFurniture([[[5, 5], [20, 5], [20, 20], [5, 20]],
                                         [[10, 10], [25, 10], [25, 25], [10, 25]]], in: context)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        #expect(bytes[15 * context.bytesPerRow + 15 * 4 + 3] == 0)
        #expect(bytes[7 * context.bytesPerRow + 7 * 4 + 3] == 0)
        #expect(bytes[22 * context.bytesPerRow + 22 * 4 + 3] == 0)
        #expect(bytes[2 * context.bytesPerRow + 2 * 4 + 3] == 255)
    }
}
