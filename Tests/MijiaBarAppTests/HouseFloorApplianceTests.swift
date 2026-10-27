import Foundation
import Testing
import MijiaCore
@testable import MijiaBarApp

@Suite @MainActor struct HouseFloorApplianceTests {
    @Test func floorSpritesAndHitAreas() throws {
        for role in ["fan", "air-purifier", "dehumidifier", "heater", "humidifier", "vacuum"] {
            let data = try JSONSerialization.data(withJSONObject: [
                "id": role.replacingOccurrences(of: "-", with: "_"), "kind": role, "role": role,
                "anchor": [100, 200], "body": [[90, 160], [110, 160], [110, 200], [90, 200]],
            ])
            var light = try JSONDecoder().decode(HouseLightSpec.self, from: data)
            #expect(light.isFloorAppliance && !light.bakesLight && light.corePolygon == nil)
            #expect(light.hitPolygon == light.body)
            #expect(light.floorAnchor == CGPoint(x: 100, y: 200))
            light.anchor = [105, 205]
            #expect(light.floorAnchor == CGPoint(x: 105, y: 205))
            light.anchor = nil
            #expect(light.floorAnchor == CGPoint(x: 100, y: 200))
            light.body = nil
            #expect(light.floorAnchor == nil)
            let on = try #require(HouseAssets.fixture(role: role, on: true))
            let off = try #require(HouseAssets.fixture(role: role, on: false))
            #expect(on.size == off.size && on.size.width > 0 && on.size.height > 0)
            #expect(on.tiffRepresentation != off.tiffRepresentation)
        }
    }

    @Test func demoRoomsPlaceAllSixAppliances() throws {
        let model = AppModel(mock: true)
        model.addHouseFixtureDemo()
        for module in [HouseModule.living, .bedroom] {
            let room = try #require(model.houseRooms.first { $0.module == module })
            for (id, category) in [("fan", DeviceCategory.fan), ("air_purifier", .airPurifier), ("dehumidifier", .dehumidifier), ("heater", .heater), ("humidifier", .humidifier), ("vacuum", .vacuum)] {
                let device = try #require(room.devices.first { $0.category == category && $0.spot == .fixture(id) })
                #expect(device.online && device.toggleable)
                if [.humidifier, .vacuum].contains(category) { #expect(device.on) }
                #expect(model.states[device.did] != nil)
            }
        }
        #expect(model.devices.filter { $0.did == "d4" }.count == 1)
    }

    @Test func newCategoriesHaveBadgeFallbackArt() throws {
        for category in [DeviceCategory.humidifier, .vacuum] {
            let on = try #require(HouseAssets.badge(category, on: true))
            let off = try #require(HouseAssets.badge(category, on: false))
            #expect(on.size == off.size && on.size.width == 12 && on.size.height == 12)
            #expect(on.tiffRepresentation != off.tiffRepresentation)
        }
    }

    @Test func newFloorBodiesMatchSpritesWithoutOverlap() throws {
        let scene = try #require(HouseAssets.cutawayScene())
        for module in ["living", "bedroom"] {
            let room = try #require(scene.modules[module])
            for role in ["humidifier", "vacuum"] {
                let light = try #require(room.lights.first { $0.role == role })
                let anchor = try #require(light.floorAnchor)
                let sprite = try #require(HouseAssets.fixture(role: role, on: true))
                let bounds = CGRect(x: anchor.x - sprite.size.width / 2, y: anchor.y - sprite.size.height,
                                    width: sprite.size.width, height: sprite.size.height)
                let body = try #require(light.body)
                let expected: [[Double]] = [[Double(bounds.minX), Double(bounds.minY)], [Double(bounds.maxX), Double(bounds.minY)],
                                            [Double(bounds.maxX), Double(bounds.maxY)], [Double(bounds.minX), Double(bounds.maxY)]]
                #expect(body == expected)
                for other in room.lights where other.isFloorAppliance && other.id != light.id {
                    let otherAnchor = try #require(other.floorAnchor)
                    let otherSprite = try #require(HouseAssets.fixture(role: other.role, on: true))
                    let otherBounds = CGRect(x: otherAnchor.x - otherSprite.size.width / 2, y: otherAnchor.y - otherSprite.size.height,
                                             width: otherSprite.size.width, height: otherSprite.size.height)
                    #expect(!bounds.intersects(otherBounds))
                }
            }
        }
    }
}
