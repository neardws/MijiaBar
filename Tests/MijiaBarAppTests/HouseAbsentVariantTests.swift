import Foundation
import Testing
import MijiaCore
@testable import MijiaBarApp

@Suite struct HouseAbsentVariantTests {
    private struct Modules: Decodable { let modules: [String: HouseCutawayModule] }
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    static func light() throws -> HouseLightSpec {
        try JSONDecoder().decode(HouseLightSpec.self, from: Data(#"{"id":"tv","kind":"screen","role":"tv","absentVariant":{"patch":"absent-living-tv","rect":[304,164,74,88]}}"#.utf8))
    }

    @Test func visibilityRequiresVariantVisibleWallAndEmptySlot() throws {
        let light = try Self.light()
        #expect(light.shouldShowAbsentVariant(in: []))
        for spot in [HouseSpot.fixture("tv"), .fixture("ac"), .badge("b1"), nil] {
            for online in [true, false] {
                for on in [true, false] {
                    let device = HouseDevice(did: "test", name: "test", category: .tv, spot: spot, on: on, online: online, toggleable: true)
                    #expect(light.shouldShowAbsentVariant(in: [device]) == (spot != .fixture("tv")))
                }
            }
        }
        var hidden = light
        hidden.hidden = true
        #expect(!hidden.shouldShowAbsentVariant(in: []))
        hidden.hidden = false
        #expect(hidden.shouldShowAbsentVariant(in: []))
        hidden.absentVariant = nil
        #expect(!hidden.shouldShowAbsentVariant(in: []))
    }

    @MainActor @Test func classicAndModulePatchesDecodeAndLoadWithPaletteFallback() throws {
        for classic in [false, true] {
            let path = classic ? "house-cutaway.json" : "modules/catalog.json"
            let data = try Data(contentsOf: Self.root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/\(path)"))
            let scene = try JSONDecoder().decode(Modules.self, from: data)
            for (room, fixture) in [("living", "tv"), ("living", "ac"), ("bedroom", "ac"), ("study", "monitor")] {
                let light = try #require(scene.modules[room]?.lights.first { $0.id == fixture })
                let variant = try #require(light.absentVariant)
                #expect(variant.patch == "absent-\(classic ? "classic-" : "")\(room)-\(fixture)")
                #expect(light.shouldShowAbsentVariant(in: []))
                for style in ["cozy-wood", "light-wood", "walnut"] {
                    for phase in [HousePhase.day, .night] {
                        for lit in [false, true] {
                            let image = try #require(HouseAssets.absentPatch(variant.patch, phase: phase, lit: lit, style: style))
                            #expect(image.size.width == variant.rect[2] && image.size.height == variant.rect[3])
                        }
                    }
                }
            }
        }
    }

    @MainActor @Test func snapshotPairsOnlyRemoveFixtureAssignments() throws {
        let device = HouseDevice(did: "d14", name: "demo", category: .tv, spot: .fixture("tv"), on: true, online: true, toggleable: true)
        let rooms = [HouseRoom(key: "living", title: "demo", module: .living, devices: [device], lighting: .from([device]))]
        let present = Snapshot.absentVariantRooms(rooms, absent: false)
        let absent = Snapshot.absentVariantRooms(present, absent: true)
        #expect(present[0].devices.map(\.did) == absent[0].devices.map(\.did))
        #expect(present[0].devices.compactMap(\.spot) == [.fixture("tv"), .fixture("ac")])
        #expect(absent[0].devices.allSatisfy { $0.spot == nil })
        let light = try Self.light()
        #expect(!light.shouldShowAbsentVariant(in: present[0].devices))
        #expect(light.shouldShowAbsentVariant(in: absent[0].devices))
        #expect(absent[0].lighting.level("tv") == 0)
    }
}
