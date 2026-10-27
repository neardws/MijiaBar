import Foundation
import Testing
import MijiaCore
@testable import MijiaBarApp

@MainActor @Suite struct HouseAutoRoomsTests {
    @Test func effectiveCellsReachSceneDecorAndPetWorldWithoutSaving() throws {
        let model = AppModel(mock: true)
        model.addHouseFixtureDemo()
        let home = model.houseHomeKey
        let layout = try #require(model.houseLayoutCells)
        #expect(model.house.homes[home]?.layout == nil)
        #expect(layout.contains { $0.module == "kitchen" })
        #expect(Set(model.houseResolved.rooms.map(\.key)) == Set(layout.map(\.room)))
        let source = try #require(HouseSceneSource.make(layout: layout, phase: .day, style: model.houseStyle))
        #expect(source.byRoom)
        #expect(source.layout == layout)
        #expect(Set(source.scene.modules.keys) == Set(layout.map(\.room)))
        let decorRooms = Set((source.scene.decorSlots ?? []).map(\.room))
        #expect(decorRooms.isSubset(of: Set(layout.map(\.room))))
        let session = try #require(HousePetSceneSession(source: source, layout: model.houseLayoutCells,
                                                       style: model.houseStyle, config: HomeHouse(), rooms: model.houseRooms))
        let petRooms = Set(session.world.nodes.map(\.room))
        #expect(petRooms == Set(layout.map(\.room)))
        let classic = model.houseClassicLayout
        model.houseEdit("classic") { $0.setLayout(home: home, layout: classic) }
        #expect(model.houseLayoutCells == nil)
        #expect(model.houseResolved.rooms.allSatisfy { HouseCatalog.classicModules.contains($0.module) })
        model.houseUndoStep(redo: false)
        #expect(model.houseLayoutCells == layout)
        #expect(model.house.homes[home]?.layout == nil)
    }

    @Test func runtimeLoaderHasExtraModulesInEveryStyleAndPhase() throws {
        for style in HouseStyles.all {
            for phase in [HousePhase.day, .night] {
                let (catalog, images) = try #require(HouseModuleAssets.load(phase: phase, style: style.id))
                for module in ["kitchen", "bathroom", "balcony"] {
                    #expect(catalog.modules[module] != nil)
                    #expect(images[module] != nil, "\(style.id)/\(module)/\(phase)")
                }
            }
        }
    }
}
