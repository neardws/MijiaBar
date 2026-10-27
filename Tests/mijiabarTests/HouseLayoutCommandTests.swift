import Foundation
import Testing
import MijiaCore
@testable import mijiabar

@Suite struct HouseLayoutCommandTests {
    @MainActor @Test func mcpGetPreservesSourceAndCellsAndSetRoutesAutoVersusClassic() async throws {
        let devices = [Device(did: "demo", name: "Light", model: "yeelink.light.demo", isOnline: true,
                              homeId: "home", homeName: "Demo", roomName: "Bathroom", roomId: "bathroom")]
        let output = try await callHouseTool("get_house_layout", ["home": "home"]) { position, rest in
            #expect(position == ["show"])
            #expect(rest == ["--home", "home"])
            return houseLayoutReport(home: "home", devices: devices, config: nil, isHidden: { _ in false })
        }
        let report = try #require(output as? [String: Any])
        #expect(report["source"] as? String == "auto")
        #expect((report["layout"] as? [[String: Any]])?.first?["room"] as? String == "bathroom")
        for (arguments, expected) in [(["mode": "auto"] as [String: Any], "auto"), (["mode": "classic"], "classic"), (["cells": NSNull()], "auto")] {
            var routed = false
            _ = try await callHouseTool("set_house_layout", arguments) { position, _ in
                routed = true
                #expect(position == [expected])
                return [:]
            }
            #expect(routed)
        }
    }

    @Test func layoutJSONSharedByCLIAndMCPReportsEffectiveSource() throws {
        let devices = [Device(did: "demo", name: "Light", model: "yeelink.light.demo", isOnline: true,
                              homeId: "home", homeName: "Demo", roomName: "Kitchen", roomId: "kitchen")]
        var saved = HomeHouse(); saved.layout = HouseLayoutSolver.classicFour
        for (config, input, source, classic) in [(HomeHouse(), devices, "auto", false), (HomeHouse(), [], "classic", true), (saved, devices, "saved", true)] {
            let report = houseLayoutReport(home: "home", devices: input, config: config, isHidden: { _ in false })
            let data = try JSONSerialization.data(withJSONObject: report)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(json["source"] as? String == source)
            #expect(json["classic"] as? Bool == classic)
            let cells = try #require(json["layout"] as? [[String: Any]])
            #expect(!cells.isEmpty)
            if source == "auto" { #expect(cells.first?["module"] as? String == "kitchen") }
        }
    }
}
