import Foundation
import Testing
@testable import MijiaCore

@Suite struct HouseAbsentVariantSchemaTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private struct Scene: Decodable {
        struct Module: Decodable { let lights: [HouseModuleLight] }
        let modules: [String: Module]
    }

    @Test func authoredVariantsRoundTripAndCoverFixtures() throws {
        let resource = Self.root.appendingPathComponent("Sources/MijiaBarApp/Resources/House")
        for path in ["Sources/MijiaBarApp/Resources/House/modules/catalog.json", "assets/house/modules/catalog.json",
                     "Sources/MijiaBarApp/Resources/House/house-cutaway.json"] {
            let scene = try JSONDecoder().decode(Scene.self, from: Data(contentsOf: Self.root.appendingPathComponent(path)))
            for (module, fixture) in [("living", "tv"), ("living", "ac"), ("bedroom", "ac"), ("study", "monitor")] {
                let light = try #require(scene.modules[module]?.lights.first { $0.id == fixture })
                let variant = try #require(light.absentVariant)
                #expect(try JSONDecoder().decode(HouseModuleLight.self, from: JSONEncoder().encode(light)) == light)
                #expect(light.patch == nil && light.rect == nil)
                let rect = variant.rect
                #expect(rect.count == 4 && rect[2] > 0 && rect[3] > 0)
                #expect(rect.allSatisfy { $0.truncatingRemainder(dividingBy: 2) == 0 })
                for point in light.core ?? light.screen ?? [] {
                    #expect(point[0] >= rect[0] && point[0] <= rect[0] + rect[2])
                    #expect(point[1] >= rect[1] && point[1] <= rect[1] + rect[3])
                }
                for suffix in ["day-unlit", "day-lit", "night-unlit", "night-lit"] {
                    let name = "\(variant.patch)-\(suffix).png"
                    let url = resource.appendingPathComponent("modules/\(name)")
                    let bytes = try Data(contentsOf: url)
                    let image = try #require(HouseComposer.loadCGImage(from: url))
                    #expect(Double(image.width) == rect[2] && Double(image.height) == rect[3])
                    #expect(bytes.count < 32_768)
                    #expect(try Data(contentsOf: Self.root.appendingPathComponent("assets/house/modules/\(name)")) == bytes)
                }
            }
            for (name, module) in scene.modules {
                if let type = HouseModule(rawValue: name) {
                    #expect(HouseCatalog.fixtureSetProblems(type, lightIds: module.lights.map(\.id)).isEmpty)
                }
            }
        }
        let legacy = try JSONDecoder().decode(HouseModuleLight.self, from: Data(#"{"id":"tv"}"#.utf8))
        #expect(legacy.absentVariant == nil)
    }

    @Test func composerTranslatesNestedRectAndDropsHiddenWallVariant() throws {
        let (catalog, images) = try HouseComposerTests.load("day")
        let layout = [HouseLayoutCell(room: "other", module: "generic", col: 0, row: 0, level: 0),
                      HouseLayoutCell(room: "living", module: "living", col: 1, row: 1, level: 1)]
        let result = HouseComposer.compose(.init(layout: layout, catalog: catalog, images: images))
        let scene = try JSONDecoder().decode(Scene.self, from: result.sceneJSON)
        let original = try #require(catalog.modules["living"]?.lights.first { $0.id == "tv" })
        let emitted = try #require(scene.modules["living"]?.lights.first { $0.id == "tv" })
        let source = try #require(original.absentVariant)
        let destination = try #require(emitted.absentVariant)
        let originalPoint = try #require(original.screen?.first)
        let emittedPoint = try #require(emitted.screen?.first)
        let dx = emittedPoint[0] - originalPoint[0], dy = emittedPoint[1] - originalPoint[1]
        #expect(dx != 0 || dy != 0)
        #expect(destination.patch == source.patch)
        #expect(destination.rect == [source.rect[0] + dx, source.rect[1] + dy, source.rect[2], source.rect[3]])
        #expect(emitted.patch == nil && emitted.rect == nil)
        for hidden in [false, true] {
            var cells = [HouseLayoutCell(room: "bedroom", module: "bedroom", col: 1, row: 0)]
            if hidden { cells.append(.init(room: "other", module: "generic", col: 0, row: 0)) }
            let result = HouseComposer.compose(.init(layout: cells, catalog: catalog, images: images))
            let json = try #require(JSONSerialization.jsonObject(with: result.sceneJSON) as? [String: Any])
            let modules = try #require(json["modules"] as? [String: [String: Any]])
            let lights = try #require(modules["bedroom"]?["lights"] as? [[String: Any]])
            let ac = try #require(lights.first { $0["id"] as? String == "ac" })
            #expect((ac["hidden"] as? Bool == true) == hidden)
            #expect((ac["absentVariant"] == nil) == hidden)
        }
    }
}
