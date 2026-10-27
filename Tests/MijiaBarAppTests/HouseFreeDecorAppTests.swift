import Foundation
import Testing
import MijiaCore
@testable import MijiaBarApp

@MainActor @Suite struct HouseFreeDecorAppTests {
    @Test func canvasRoundTripSceneBoundsAndDemoFixture() throws {
        let config = try #require(HouseFreeDecorDemo.config())
        let items = try #require(HouseModuleAssets.decorCatalog)
        let (catalog, images) = try #require(HouseModuleAssets.load(phase: .day, style: "cozy-wood"))
        let layout = HouseFreeDecorDemo.layout
        let decor = HouseModuleAssets.decorations(layout: layout, catalog: catalog, phase: .day, config: config)
        let result = HouseComposer.compose(.init(layout: layout, catalog: catalog, images: images, decor: decor))
        let scene = try JSONDecoder().decode(HouseCutawaySceneFile.self, from: result.sceneJSON)
        #expect(scene.freeDecor?.count == 3)
        let grids = HouseModuleAssets.freeGrids(layout: layout, catalog: catalog, style: config.style)
        let canvas = HouseFreeDecorCanvas(grids: grids, layout: layout, origin: scene.origin ?? [0, 0], config: config, items: items,
                                         fixed: decor.map(\.placement).filter { $0.freeCell == nil })
        let small = try #require(items.items.first { $0.id == "cat_bed" })
        for grid in grids {
            for cell in grid.cells {
                let point = canvas.point(grid: grid, cell: cell)
                let preview = try #require(canvas.preview(at: point, item: small, source: nil))
                #expect(preview.room == grid.room && preview.cell == cell.array)
            }
        }
        for entry in scene.freeDecor ?? [] {
            let image = try #require(decor.first { $0.placement.room == entry.room && $0.placement.slot == "free:" + HouseFreeDecor.id(of: entry.key) })
            let grid = try #require(grids.first { $0.room == entry.room }), offset = canvas.offset(grid)
            #expect(entry.rect == [Double(image.x) + offset.x, Double(image.y) + offset.y, Double(image.image.width), Double(image.image.height)])
            #expect(entry.cell == config.freeDecor?[entry.key]?.cell)
        }
        let spots = try #require(HousePetPainter.shared.spots)
        let baseline = HousePetWorld(layout: layout, catalog: catalog, spots: spots)
        let world = HousePetWorld(layout: layout, catalog: catalog, spots: spots, decor: decor.map(\.placement), items: items)
        let detour = HouseFreeDecorDemo.detour(world: world, baseline: baseline)
        #expect(detour.count > 1)
        #expect(detour.allSatisfy { point in world.nodes.contains { $0.point == point } })
        #expect(canvas.preview(at: .init(x: -1000, y: -1000), item: small, source: nil) == nil)
    }
    @Test func freeChangesInvalidateCompositionAndRespectDisable() throws {
        var config = try #require(HouseFreeDecorDemo.config())
        let before = HouseModuleAssets.decorFingerprint(config, date: .distantPast)
        config.freeDecor?["living/f1"]?.cell = [0, 0]
        #expect(before != HouseModuleAssets.decorFingerprint(config, date: .distantPast))
        config.decorPrefs = .init(enabled: false)
        let (catalog, _) = try #require(HouseModuleAssets.load(phase: .day, style: "cozy-wood"))
        #expect(HouseModuleAssets.decorations(layout: HouseFreeDecorDemo.layout, catalog: catalog, phase: .day, config: config).isEmpty)
    }
}
