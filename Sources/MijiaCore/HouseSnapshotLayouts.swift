import Foundation

public enum HouseSnapshotLayouts {
    public static let fixtures: [(String, [HouseLayoutCell])] = [
        ("composed", cells([("bedroom", 0, 0), ("bathroom", 1, 0), ("balcony", 2, 0), ("living", 0, 1), ("kitchen", 2, 1)])),
        ("composed2", cells([("kitchen", 0, 0), ("living", 1, 0), ("bathroom", 0, 1), ("bedroom", 1, 1), ("balcony", 2, 1)])),
    ]
    public static let pets = cells([("bedroom", 0, 0), ("study", 1, 0), ("bathroom", 2, 0), ("living", 0, 1), ("kitchen", 2, 1), ("balcony", 2, 2)], level: 0)
    public static let classic = HouseLayoutSolver.classicFour.map { cell in
        HouseLayoutCell(room: cell.module, module: cell.module, col: cell.col, row: cell.row, level: cell.level)
    }
    public static let all = fixtures + [("pets", pets), ("classic-composer", classic)]

    private static func cells(_ entries: [(String, Int, Int)], level: Int? = nil) -> [HouseLayoutCell] {
        entries.map { HouseLayoutCell(room: $0.0, module: $0.0, col: $0.1, row: $0.2, level: level) }
    }
}
