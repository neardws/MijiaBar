import SwiftUI
import Testing
import MijiaCore
@testable import MijiaBarApp

@Suite @MainActor struct TypeDetailTests {
    @Test func dedicatedDemoDevicesAndArt() throws {
        let model = AppModel(mock: true)
        for (category, row) in [(DeviceCategory.humidifier, "humidifier"), (.vacuum, "vacuum"),
                                (.fridge, "fridge"), (.washer, "washer"), (.waterHeater, "water-heater")] {
            let device = try #require(model.devices.first { $0.category == category })
            #expect(device.homeId == "h2")
            #expect(model.states[device.did]?.spec != nil)
            #expect(ArtGallery.rows.filter { $0.0 == row }.count == 1)
        }
        #expect(ArtGallery.rows.count == 23)
        #expect(ArtGallery.size.height == CGFloat(ArtGallery.rows.count * 138))
    }

    @Test func applianceDemoPropertiesAndPower() throws {
        let model = AppModel(mock: true)
        for (category, names) in [(DeviceCategory.fridge, ["target-temperature", "mode", "temperature"]),
                                   (.washer, ["status", "remaining-time", "progress"]),
                                   (.waterHeater, ["target-temperature", "heating", "temperature"])] {
            let device = try #require(model.devices.first { $0.category == category })
            let state = try #require(model.states[device.did])
            let context = DC(device: device, state: state)
            for name in names { #expect(context.v(context.p(name)) != nil) }
            if category != .washer {
                let target = try #require(primarySliderProp(context))
                #expect(target.name == "target-temperature" && target.writable)
            }
            let power = try #require(model.powerInfo(device))
            #expect(power.isOn)
            model.states[device.did]?.values[power.key] = power.off
            #expect(model.powerInfo(device)?.isOn == false)
        }
    }

    @Test func applianceMissingAndReadOnlyProperties() {
        for model in ["viomi.fridge.demo", "xiaomi.washer.demo", "viomi.waterheater.demo"] {
            let device = Device(did: "demo", name: "Demo", model: model, isOnline: true)
            let empty = DC(device: device, state: DeviceState(values: [:], spec: nil, legacy: false, source: "cloud"))
            #expect(primarySliderProp(empty) == nil)
            #expect(empty.p("status") == nil)
            let spec = DeviceSpec.parse(["services": [["iid": 2, "type": "appliance", "properties": [
                ["iid": 1, "type": "target-temperature", "format": "uint8", "access": ["read"], "value-range": [2, 75, 1]]
            ]]]])
            let context = DC(device: device, state: DeviceState(values: ["2.1": .int(4)], spec: spec, legacy: false, source: "cloud"))
            #expect(context.num(context.p("target-temperature")) == 4)
            #expect(primarySliderProp(context) == nil)
        }
    }

    @Test func washerBusyAndWaterHeaterHeating() throws {
        let model = AppModel(mock: true)
        var washer = try #require(model.states["d18"])
        #expect(HouseDeviceState.busy(washer, otherwise: false))
        washer.values["2.2"] = .int(2)
        #expect(!HouseDeviceState.busy(washer, otherwise: false))
        washer.values.removeValue(forKey: "2.2")
        #expect(!HouseDeviceState.busy(washer, otherwise: false))
        let device = try #require(model.devices.first { $0.category == .waterHeater })
        var heater = try #require(model.states[device.did])
        #expect(WaterHeaterDetail(dc: DC(device: device, state: heater)).heating)
        heater.values["2.3"] = .bool(false)
        #expect(!WaterHeaterDetail(dc: DC(device: device, state: heater)).heating)
        heater.values.removeValue(forKey: "2.3")
        #expect(!WaterHeaterDetail(dc: DC(device: device, state: heater)).heating)
        heater.spec = nil
        #expect(!WaterHeaterDetail(dc: DC(device: device, state: heater)).heating)
    }

    @Test func humidifierUsesHumidityKeyboardSlider() throws {
        let model = AppModel(mock: true)
        let device = try #require(model.devices.first { $0.category == .humidifier })
        let state = try #require(model.states[device.did])
        let context = DC(device: device, state: state)
        let target = try #require(primarySliderProp(context))
        #expect(target.name == "target-humidity" && target.writable)
        #expect(context.num(target) == 55)
        #expect(context.num(context.p("relative-humidity")) == 42)
        for name in ["mode", "fan-level", "physical-controls-locked"] { #expect(context.p(name) != nil) }
    }

    @Test func readOnlyHumidityHasNoKeyboardSlider() {
        let spec = DeviceSpec.parse(["services": [["iid": 2, "type": "humidifier", "properties": [
            ["iid": 1, "type": "target-humidity", "format": "uint8", "access": ["read"], "value-range": [30, 80, 5]]
        ]]]])
        let context = DC(device: Device(did: "demo", name: "Demo", model: "deerma.humidifier.demo", isOnline: true),
                         state: DeviceState(values: ["2.1": .int(50)], spec: spec, legacy: false, source: "cloud"))
        #expect(primarySliderProp(context) == nil)
    }

    @Test func actionOnlyVacuumRetainsBatteryAndBusyState() throws {
        let model = AppModel(mock: true)
        let device = try #require(model.devices.first { $0.category == .vacuum })
        var state = try #require(model.states[device.did])
        let context = DC(device: device, state: state)
        #expect(model.powerInfo(device) == nil)
        #expect(context.num(context.p("battery-level")) == 76)
        #expect(HouseDeviceState.busy(state, otherwise: false))
        for command in VacuumCommand.allCases { #expect(command.action(in: context) != nil) }
        state.values["2.1"] = .int(2)
        #expect(!HouseDeviceState.busy(state, otherwise: false))
        state.values.removeValue(forKey: "2.1")
        #expect(!HouseDeviceState.busy(state, otherwise: false))
    }

    @Test func vacuumActionsRequireExposedZeroInputSpecActions() {
        let device = Device(did: "demo", name: "Demo", model: "roborock.vacuum.demo", isOnline: true)
        func context(_ actions: [[String: Any]]) -> DC {
            let spec = DeviceSpec.parse(["services": [["iid": 2, "type": "vacuum", "actions": actions]]])
            return DC(device: device, state: DeviceState(values: [:], spec: spec, legacy: false, source: "cloud"))
        }
        for command in VacuumCommand.allCases {
            #expect(command.action(in: context([])) == nil)
            for name in command.names {
                #expect(command.action(in: context([["iid": 4, "type": name, "in": [1]]])) == nil)
                #expect(command.action(in: context([["iid": 4, "type": name, "in": []]]))?.key == "2.4")
            }
        }
        let fallback = context([["iid": 1, "type": "start-charge", "in": [1]], ["iid": 2, "type": "dock", "in": []]])
        #expect(VacuumCommand.charge.action(in: fallback)?.key == "2.2")
    }
}
