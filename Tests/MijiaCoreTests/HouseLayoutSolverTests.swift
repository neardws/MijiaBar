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
}
