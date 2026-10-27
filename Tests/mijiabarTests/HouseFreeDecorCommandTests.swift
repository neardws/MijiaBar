import Foundation
import Testing
import MijiaCore
@testable import mijiabar

@Suite struct HouseFreeDecorCommandTests {
    @Test func parsesFreeCommandsAndRejectsMalformedFlags() throws {
        #expect(try houseDecorArguments(["place", "living room", "cat_bed", "--cell", "2,3", "--id", "f1", "--home", "h", "--json"]) == ["place", "living room", "cat_bed"])
        #expect(try houseDecorArguments(["move", "room/f1", "--cell", "3,4"]) == ["move", "room/f1"])
        #expect(try houseDecorArguments(["remove", "room/f1"]) == ["remove", "room/f1"])
        for args in [["place", "room", "cat_bed", "--cell"], ["move", "room/f1", "--oops", "2"], ["list", "--id", "a", "--id", "b"]] {
            #expect(throws: (any Error).self) { try houseDecorArguments(args) }
        }
    }
    @Test func placeMoveRemoveAndValidationJSON() throws {
        let modules = try #require(HouseDecorFiles.modules(style: "cozy-wood")), items = try #require(HouseDecorFiles.items()), spots = try #require(HouseDecorFiles.spots())
        let layout = [HouseLayoutCell(room: "room", module: "living", col: 0, row: 0, level: 0)]
        let grids = HouseFreeDecor.grids(layout: layout, catalog: modules, spots: spots, style: nil)
        let fixed = HouseDecor.resolve(layout: layout, catalog: modules, items: items)
        let cells = try #require(grids.first).cells.filter { HouseFreeDecor.validate(room: "room", item: "cat_bed", cell: $0.array, grids: grids, items: items, fixed: fixed) == nil }
        #expect(cells.count >= 2)
        let candidates = cells.sorted { $0.row == $1.row ? $0.col < $1.col : $0.row < $1.row }
        var file = HouseFile()
        func run(_ action: String, target: String = "room/f1", item: String? = nil, cell: [Int] = []) -> [String: Any] {
            houseFreeDecorEdit(action: action, target: target, item: item, cell: cell, id: nil, home: "h", file: &file, layout: layout, modules: modules, items: items, spots: spots)
        }
        let placed = run("place", target: "room", item: "cat_bed", cell: candidates[0].array)
        #expect(placed["ok"] as? Bool == true && placed["key"] as? String == "room/f1")
        var config = try #require(file.homes["h"])
        let placements = HouseFreeDecor.resolve(entries: config.freeDecor ?? [:], grids: grids, items: items, fixed: fixed)
        let listed = houseFreeDecorList(config: config, placements: placements)
        #expect(listed.first?["cell"] as? [Int] == candidates[0].array)
        #expect(listed.first?["at"] as? [Double] == placements.first?.at)
        #expect(listed.first?["hidden"] == nil)
        #expect(houseFreeDecorList(config: config, placements: [], room: "other").isEmpty)
        #expect(houseFreeDecorList(config: config, placements: []).first?["hidden"] as? String == "invalid")
        config.decorPrefs = .init(enabled: false)
        #expect(houseFreeDecorList(config: config, placements: []).first?["hidden"] as? String == "disabled")
        let invalid = run("move", cell: [-1, 0]); #expect(invalid["reason"] as? String == "blocked")
        #expect(file.homes["h"]?.freeDecor?["room/f1"]?.cell == candidates[0].array)
        let moved = run("move", cell: candidates[1].array)
        #expect(moved["ok"] as? Bool == true)
        #expect(file.homes["h"]?.freeDecor?["room/f1"]?.cell == candidates[1].array)
        let removed = run("remove"); #expect(removed["ok"] as? Bool == true)
        #expect(file.homes["h"]?.freeDecor?["room/f1"]?.item == nil)
        #expect(houseFreeDecorList(config: file.homes["h"]!, placements: []).isEmpty)
        for result in [placed, invalid, moved, removed] { #expect(JSONSerialization.isValidJSONObject(result)) }
        #expect(run("move", cell: [2, 2])["reason"] as? String == "unknownItem")
        #expect(JSONSerialization.isValidJSONObject(houseSchema))
        #expect(JSONSerialization.isValidJSONObject(houseMCPTools))
    }
}
