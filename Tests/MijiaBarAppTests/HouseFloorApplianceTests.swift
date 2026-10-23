import Foundation
import Testing
import MijiaCore
@testable import MijiaBarApp

@Suite @MainActor struct HouseFloorApplianceTests {
    @Test func floorSpritesAndHitAreas() throws {
        for role in ["fan", "air-purifier", "dehumidifier", "heater"] {
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

    @Test func demoRoomsPlaceAllFourAppliances() throws {
        let model = AppModel(mock: true)
        model.addHouseFixtureDemo()
        for module in [HouseModule.living, .bedroom] {
            let room = try #require(model.houseRooms.first { $0.module == module })
            for (id, category) in [("fan", DeviceCategory.fan), ("air_purifier", .airPurifier), ("dehumidifier", .dehumidifier), ("heater", .heater)] {
                let device = try #require(room.devices.first { $0.category == category && $0.spot == .fixture(id) })
                #expect(device.online && device.toggleable)
                #expect(model.states[device.did] != nil)
            }
        }
        #expect(model.devices.filter { $0.did == "d4" }.count == 1)
    }
}
