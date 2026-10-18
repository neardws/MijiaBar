import Testing
@testable import MijiaCore

@Suite struct HouseLayoutSolverTests {
    @Test func rejectsOverlapAndBounds() {
        let bad = [
            HouseLayoutCell(room: "a", module: "bedroom", col: 0, row: 0),
            HouseLayoutCell(room: "b", module: "study", col: 0, row: 0),
        ]
        #expect(HouseLayoutSolver.validate(bad).contains(.overlap))
        let oob = [HouseLayoutCell(room: "a", module: "living", col: 2, row: 0)] // living needs 2 cols
        #expect(HouseLayoutSolver.validate(oob).contains(.outOfBounds))
    }

    @Test func classicGeometry() {
        #expect(HouseLayoutSolver.isClassicGeometry(nil))
        #expect(HouseLayoutSolver.isClassicGeometry(HouseLayoutSolver.classicFour))
        var custom = HouseLayoutSolver.classicFour
        custom[0].col = 1
        #expect(!HouseLayoutSolver.isClassicGeometry(custom))
    }

    @Test func autolayoutPutsLivingFrontLeft() {
        let rooms: [(String, HouseModule, Int)] = [
            ("r1", .living, 5), ("r2", .bedroom, 3), ("r3", .kitchen, 2), ("r4", .bathroom, 1),
        ]
        let layout = HouseLayoutSolver.autolayout(rooms: rooms.map { (key: $0.0, module: $0.1, score: $0.2) })
        #expect(HouseLayoutSolver.validate(layout).isEmpty)
        let living = layout.first { $0.module == "living" }
        #expect(living?.col == 0)
        #expect(layout.count <= 6)
    }

    @Test func setModuleChangesAddsAndRemoves() {
        let base: [HouseLayoutCell] = [
            .init(room: "a", module: "bedroom", col: 0, row: 0),
            .init(room: "b", module: "study", col: 1, row: 0),
            .init(room: "k", module: "kitchen", col: 0, row: 1),
        ]
        // 原地换模块
        let s1 = HouseLayoutSolver.setModule(base, room: "b", module: "bathroom")!
        #expect(s1.first { $0.room == "b" } == .init(room: "b", module: "bathroom", col: 1, row: 0))
        // 换成客厅（占两格）：原地放不下 (1,0)+(2,0) 其实能放 → 原地
        let s2 = HouseLayoutSolver.setModule(base, room: "b", module: "living")!
        #expect(s2.first { $0.room == "b" } == .init(room: "b", module: "living", col: 1, row: 0))
        // 厨房换客厅：(0,1)+(1,1) 空 → 原地
        let s3 = HouseLayoutSolver.setModule(s2, room: "k", module: "living")!
        #expect(HouseLayoutSolver.validate(s3).isEmpty)
        // 新房间加进第一个空位
        let s4 = HouseLayoutSolver.setModule(base, room: "n", module: "balcony")!
        #expect(s4.first { $0.room == "n" } == .init(room: "n", module: "balcony", col: 2, row: 0))
        // 移出
        #expect(HouseLayoutSolver.setModule(base, room: "a", module: nil)!.map(\.room) == ["b", "k"])
        // 满了放不下
        let full = (0..<6).map { HouseLayoutCell(room: "r\($0)", module: "generic", col: $0 % 3, row: $0 / 3) }
        #expect(HouseLayoutSolver.setModule(full, room: "x", module: "bedroom") == nil)
        // 满格时把一间 1x1 换成客厅：原地放不下也没有空位 → nil
        #expect(HouseLayoutSolver.setModule(full, room: "r2", module: "living") == nil)
    }

    @Test func levelsValidateAndToggle() {
        var cells = HouseLayoutSolver.classicFour.enumerated().map { i, c in
            HouseLayoutCell(room: "r\(i)", module: c.module, col: c.col, row: c.row)
        }
        // 自动错层（level 为空）的经典几何仍走整图；显式抬高一格就改走合成
        #expect(HouseLayoutSolver.isClassicGeometry(cells))
        let raised = HouseLayoutSolver.setLevel(cells, room: "r0", level: 1)!
        #expect(raised[0].level == 1 && raised[1].level == nil)
        #expect(!HouseLayoutSolver.isClassicGeometry(raised))
        #expect(HouseLayoutSolver.isClassicGeometry(HouseLayoutSolver.setAllLevels(raised, flat: true)))
        #expect(HouseLayoutSolver.setAllLevels(raised, flat: false).allSatisfy { $0.level == nil })
        #expect(HouseLayoutSolver.setLevel(cells, room: "nope", level: 1) == nil)
        // 越界的级数：setLevel 夹住，validate 报错
        #expect(HouseLayoutSolver.setLevel(cells, room: "r0", level: 9)![0].level == HouseGrid.levelRange.upperBound)
        cells[0].level = 3
        #expect(HouseLayoutSolver.validate(cells).contains(.levelOutOfRange))
    }
}
