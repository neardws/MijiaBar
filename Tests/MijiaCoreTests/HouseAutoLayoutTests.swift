import Foundation
import Testing
@testable import MijiaCore

@Suite struct HouseAutoLayoutTests {
    func device(_ key: String, room: String, model: String = "yeelink.light.demo", online: Bool = true, id: String? = nil) -> Device {
        Device(did: id ?? key, name: room, model: model, isOnline: online, homeId: "demo", homeName: "Demo", roomName: room, roomId: key)
    }
    var classic: [Device] {
        [device("living", room: "客厅"), device("bedroom", room: "卧室"), device("study", room: "书房"), device("entry", room: "玄关")]
    }
    var extras: [Device] {
        [device("kitchen", room: "厨房"), device("bathroom", room: "卫生间"), device("balcony", room: "阳台")]
    }
    func effective(_ devices: [Device], _ config: HomeHouse? = nil, hidden: Bool = false) -> [HouseLayoutCell]? {
        HouseAutoLayout.effective(devices: devices, config: config, isHidden: { _ in hidden })
    }

    @Test func savedWinsIncludingEmptyAndClassic() {
        for layout in [[], HouseLayoutSolver.classicFour, [.init(room: "custom", module: "bathroom", col: 2, row: 1, level: -1)]] {
            var config = HomeHouse(); config.layout = layout
            #expect(effective(classic + extras, config) == layout)
            #expect(HouseAutoLayout.source(config: config, effective: layout) == "saved")
        }
    }

    @Test func onlyClassicStaysClassicAndKitchenTriggers() throws {
        #expect(effective(classic) == nil)
        let config = HomeHouse()
        let layout = try #require(effective(classic + [extras[0]], config))
        #expect(layout.contains { $0.module == "kitchen" })
        #expect(!HouseLayoutSolver.isClassicGeometry(layout))
        #expect(HouseLayoutSolver.validate(layout).isEmpty)
        #expect(config.layout == nil && config.layoutUpdatedAt == nil)
    }

    @Test func hiddenOfflineUnshowableAndExcludedDoNotTrigger() {
        #expect(effective([extras[0]], hidden: true) == nil)
        #expect(effective([device("kitchen", room: "厨房", online: false)]) == nil)
        #expect(effective([device("kitchen", room: "厨房", model: "unknown.device.demo")]) == nil)
        var config = HomeHouse()
        config.devices["kitchen"] = .init(visible: false)
        #expect(effective([extras[0]], config) == nil)
        config.devices["kitchen"] = .init(visible: true)
        #expect(effective([extras[0]], config, hidden: true) != nil)
        config.rooms["kitchen"] = .init(module: "none")
        #expect(effective([extras[0]], config) == nil)
        config.rooms = ["name:厨房": .init(module: "none")]
        #expect(effective([extras[0]], config) == nil)
        #expect(effective([device("unknown", room: "储藏室")]) == nil)
    }

    @Test func overridesAndLegacyNameKeysTrigger() throws {
        let devices = [device("unknown", room: "储藏室")]
        for key in ["unknown", "name:储藏室"] {
            var config = HomeHouse(); config.rooms[key] = .init(module: "bathroom")
            #expect(try #require(effective(devices, config)).first?.module == "bathroom")
        }
    }

    @Test func capacityPriorityReasonsAndOrderIndependence() throws {
        let devices = classic + extras + [device("unknown", room: "储藏室"), device("excluded", room: "厨房")]
        var config = HomeHouse(); config.rooms["excluded"] = .init(module: "none")
        let layout = try #require(effective(devices, config))
        #expect(layout.map(\.module) == ["living", "bedroom", "kitchen", "bathroom", "balcony"])
        #expect(HouseLayoutSolver.validate(layout).isEmpty)
        for offset in devices.indices {
            #expect(effective(Array(devices[offset...] + devices[..<offset]), config) == layout)
        }
        #expect(effective(devices.reversed(), config) == layout)
        let resolved = HouseResolver.resolve(devices: devices, config: config, isHidden: { _ in false }, name: { $0.name })
        #expect(resolved.rooms.count == 5)
        #expect(resolved.excluded.contains { $0.key == "study" && $0.reason == .notInLayout })
        #expect(resolved.excluded.contains { $0.key == "entry" && $0.reason == .notInLayout })
        #expect(resolved.excluded.contains { $0.key == "unknown" && $0.reason == .noArt })
        #expect(resolved.excluded.contains { $0.key == "excluded" && $0.reason == .excluded })
    }

    @Test func winnersUsePinsThenFitThenKeyAndPlacementStaysStable() throws {
        let first = device("a", room: "厨房"), second = device("b", room: "厨房")
        let devices = classic + [first, second]
        #expect(effective(devices)?.first { $0.module == "kitchen" }?.room == "a")
        var config = HomeHouse(); config.rooms["b"] = .init(module: "kitchen")
        #expect(effective(devices, config)?.first { $0.module == "kitchen" }?.room == "b")
        let more = device("b", room: "厨房", id: "b2")
        #expect(effective(devices + [more])?.first { $0.module == "kitchen" }?.room == "b")
        let base = try #require(effective(classic + extras))
        #expect(effective(classic + extras + [device("bathroom", room: "卫生间", id: "extra")]) == base)
    }

    @Test func explicitClassicAndReset() {
        let devices = classic + extras
        let marker = HouseAutoLayout.classic(devices: devices, config: nil, isHidden: { _ in false })
        #expect(HouseLayoutSolver.isClassicGeometry(marker))
        #expect(Set(marker.map(\.room)) == Set(classic.map { HouseResolver.roomKey($0) }))
        var file = HouseFile(); file.setLayout(home: "demo", layout: marker)
        let resolved = HouseResolver.resolve(devices: devices, config: file.homes["demo"], isHidden: { _ in false }, name: { $0.name })
        #expect(resolved.rooms.map(\.module) == HouseCatalog.classicModules)
        #expect(resolved.excluded.filter { [.kitchen, .bathroom, .balcony].contains($0.module) }.allSatisfy { $0.reason == .notInLayout })
        file.reset(home: "demo", layout: true)
        #expect(effective(devices, file.homes["demo"])?.contains { $0.module == "kitchen" } == true)
    }

    @Test func scoreChoosesRemainingRoomsButLivingAndBedroomStay() throws {
        let devices = classic + extras + [device("study", room: "书房", id: "study-extra")]
        let layout = try #require(effective(devices))
        #expect(Set(layout.map(\.module)) == ["living", "bedroom", "kitchen", "bathroom", "study"])
        let withoutLiving = try #require(effective((classic + extras).filter { $0.roomId != "living" }))
        #expect(withoutLiving.count == 6)
        #expect(HouseLayoutSolver.validate(withoutLiving).isEmpty)
    }

    @Test func fixtureFitOutranksBadgeCountAndLegacyExclusionSurvivesComposition() {
        let devices = [device("fixture", room: "厨房", model: "viomi.fridge.demo"),
                       device("badges", room: "厨房", model: "cuco.plug.demo", id: "badge1"),
                       device("badges", room: "厨房", model: "cuco.plug.demo", id: "badge2")]
        #expect(effective(devices)?.first?.room == "fixture")
        var config = HomeHouse(); config.rooms["name:厨房"] = .init(module: "none")
        let resolved = HouseResolver.resolve(devices: devices + [extras[1]], config: config, isHidden: { _ in false }, name: { $0.name })
        #expect(resolved.rooms.map(\.module) == [.bathroom])
        #expect(resolved.excluded.count == 2)
        #expect(resolved.excluded.allSatisfy { $0.reason == .excluded })
    }

    @Test func emptyClassicSlotsHaveDistinctEditableIdentities() throws {
        let marker = HouseAutoLayout.classic(devices: [extras[0]], config: nil, isHidden: { _ in false })
        #expect(HouseLayoutSolver.isClassicGeometry(marker))
        #expect(Set(marker.map(\.room)).count == 4)
        let edited = try #require(HouseLayoutSolver.setLevel(marker, room: marker[0].room, level: 1))
        #expect(edited.filter { $0.level == 1 }.count == 1)
    }

    @Test func allMappedRoomsRemainCandidatesOnceAnotherRoomTriggersComposition() throws {
        var config = HomeHouse()
        for device in classic { config.devices[device.did] = .init(visible: false) }
        let layout = try #require(effective(classic + [extras[0]], config))
        #expect(Set(layout.map(\.module)) == ["living", "bedroom", "study", "generic", "kitchen"])
        let resolved = HouseResolver.resolve(devices: classic + [extras[0]], config: config, isHidden: { _ in false }, name: { $0.name })
        #expect(resolved.rooms.filter { $0.module != .kitchen }.allSatisfy { $0.devices.isEmpty })
    }
}
