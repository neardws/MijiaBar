import Foundation
import AppKit
import ImageIO
import Testing
import MijiaCore
@testable import MijiaBarApp

@MainActor @Suite struct HouseDecorEditorTests {
    static func slot(surface: String = "floor", sizes: [String] = ["L"], wall: String? = nil) -> HouseDecorSceneSlot {
        HouseDecorSceneSlot(room: "living", slot: "corner", surface: surface, wall: wall,
                            sizes: sizes, x: 120, y: 160, item: nil, hidden: nil, rect: [108, 148, 24, 24])
    }

    @Test func sceneSlotCompatibilityUsesSurfaceSizeAndWall() throws {
        let catalog = try #require(HouseModuleAssets.decorCatalog)
        let plant = try #require(catalog.items.first { $0.id == "monstera" })
        #expect(plant.fits(Self.slot().decorSlot))
        #expect(!plant.fits(Self.slot(surface: "table").decorSlot))
        #expect(!plant.fits(Self.slot(sizes: ["S"]).decorSlot))
        let wall = try #require(catalog.items.first { $0.surface == "wall" })
        #expect(wall.fits(Self.slot(surface: "wall", sizes: [wall.size], wall: "nw").decorSlot))
        #expect(!wall.fits(Self.slot(surface: "wall", sizes: [wall.size]).decorSlot))
        #expect(Self.slot().key == "living/corner")
        #expect(Self.slot().decorSlot.at == [120, 160])
    }

    @Test func decorResetAndPreferencesUndoWithoutChangingStyle() {
        let model = AppModel(mock: true), home = model.houseHomeKey
        model.houseEdit("seed") {
            $0.setStyle(home: home, style: "modern")
            $0.setDecor(home: home, key: "living/corner", item: "monstera")
        }
        model.houseEdit("preferences") { $0.setDecorPrefs(home: home, seasonal: false) }
        #expect(model.house.homes[home]?.decorPrefs?.seasonal == false)
        model.houseUndoStep(redo: false)
        #expect(model.house.homes[home]?.decorPrefs?.seasonal ?? true)
        model.houseEdit("reset decor") { $0.resetDecor(home: home) }
        #expect(model.house.homes[home]?.decor?["living/corner"]?.item == nil)
        #expect(model.house.homes[home]?.style == "modern")
        model.houseUndoStep(redo: false)
        #expect(model.house.homes[home]?.decor?["living/corner"]?.item == "monstera")
        model.houseUndoStep(redo: true)
        #expect(model.house.homes[home]?.decor?["living/corner"]?.item == nil)
        #expect(model.house.homes[home]?.style == "modern")
    }

    @Test func cancelledDragDoesNotEditAndClearsSession() throws {
        let drag = HouseDecorDrag()
        drag.item = try #require(HouseModuleAssets.decorCatalog?.items.first)
        drag.source = "living/corner"
        var removed = false
        drag.remove = { _ in removed = true }
        drag.end(at: .zero, operation: [], cancelled: true)
        #expect(!removed)
        #expect(drag.item == nil && drag.source == nil && drag.payload == nil)
    }

    @Test func droppingOutsideRemovesButInsideAndSuccessfulDropDoNot() throws {
        let window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 200, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        let view = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        window.contentView = view
        let drag = HouseDecorDrag()
        drag.sceneView = view
        var removals: [String] = []
        drag.remove = { removals.append($0) }
        let item = try #require(HouseModuleAssets.decorCatalog?.items.first)
        for (point, operation) in [(NSPoint(x: 100, y: 100), NSDragOperation()), (NSPoint(x: -100, y: -100), .move)] {
            drag.item = item; drag.source = "living/corner"
            drag.end(at: point, operation: operation, cancelled: false)
            #expect(removals.isEmpty)
        }
        drag.item = item; drag.source = "living/corner"
        drag.end(at: NSPoint(x: -100, y: -100), operation: [], cancelled: false)
        #expect(removals == ["living/corner"])
        #expect(drag.item == nil && drag.source == nil)
    }

    @Test func compositionExportsNativePixelsAndKeepsDayNightPlacements() throws {
        let layout = [HouseLayoutCell(room: "living", module: "living", col: 0, row: 0, level: 0)]
        var config = HomeHouse()
        config.decorPrefs = .init(seasonal: false)
        config.decor = ["living/corner": .init(item: "monstera")]
        for style in ["cozy-wood", "japanese", "modern"] {
            var placements: [[String: String]] = []
            for phase in [HousePhase.day, .night] {
                let (catalog, images) = try #require(HouseModuleAssets.load(phase: phase, style: style))
                let decor = HouseModuleAssets.decorations(layout: layout, catalog: catalog, phase: phase, config: config)
                let result = HouseComposer.compose(.init(layout: layout, catalog: catalog, images: images, decor: decor))
                let image = try #require(result.unlit)
                let data = try #require(result.pngData(image))
                let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
                let exported = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
                #expect(exported.width == result.width && exported.height == result.height)
                let scene = try JSONDecoder().decode(HouseCutawaySceneFile.self, from: result.sceneJSON)
                #expect(scene.size == [Double(exported.width), Double(exported.height)])
                placements.append(Dictionary(uniqueKeysWithValues: decor.map { ($0.placement.slot, $0.placement.item) }))
            }
            #expect(placements[0] == placements[1], "Day/night decor differs for \(style)")
        }
    }
}
