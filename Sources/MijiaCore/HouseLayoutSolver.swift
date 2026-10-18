import Foundation

/// 3×2 格子布局：校验、自动摆放、经典四室判定。
public enum HouseLayoutSolver {
    public static let maxCols = 3
    public static let maxRows = 2
    public static let maxCells = 6

    public enum Problem: String, Sendable, Equatable {
        case outOfBounds
        case overlap
        case tooMany
        case holeOrNonRect  // spike: only reject overlap/bounds; L-shape allowed later
        case unknownModule
        case livingNeedsTwo
    }

    /// 每个格子占用的 (col,row) 集合（客厅占 col..col+1）
    public static func occupied(_ layout: [HouseLayoutCell], footprint: (String) -> (Int, Int) = defaultFootprint) -> [String: Set<SIMD2<Int>>] {
        var out: [String: Set<SIMD2<Int>>] = [:]
        for c in layout {
            let (fw, fh) = footprint(c.module)
            var s: Set<SIMD2<Int>> = []
            for dc in 0..<fw { for dr in 0..<fh { s.insert(SIMD2(c.col + dc, c.row + dr)) } }
            out[c.room] = s
        }
        return out
    }

    public static func defaultFootprint(_ module: String) -> (Int, Int) {
        module == "living" ? (2, 1) : (1, 1)
    }

    public static func validate(_ layout: [HouseLayoutCell], footprint: (String) -> (Int, Int) = defaultFootprint) -> [Problem] {
        var problems: [Problem] = []
        if layout.count > maxCells { problems.append(.tooMany) }
        var taken: [SIMD2<Int>: String] = [:]
        for c in layout {
            let (fw, fh) = footprint(c.module)
            if c.module == "living" && fw < 2 { problems.append(.livingNeedsTwo) }
            for dc in 0..<fw {
                for dr in 0..<fh {
                    let p = SIMD2(c.col + dc, c.row + dr)
                    if p.x < 0 || p.y < 0 || p.x >= maxCols || p.y >= maxRows { problems.append(.outOfBounds) }
                    if let other = taken[p], other != c.room { problems.append(.overlap) }
                    taken[p] = c.room
                }
            }
            if HouseModule(rawValue: c.module) == nil { problems.append(.unknownModule) }
        }
        return Array(Set(problems.map(\.rawValue))).compactMap(Problem.init(rawValue:))
    }

    /// 自定义布局里给一个房间换模块 / 加进来 / 移出（Devices 标签的房间菜单用）。
    /// module == nil → 移出布局；房间已在布局里 → 原地换模块，放不下（例如换成占两格的客厅）就挪到第一个空位；
    /// 不在布局里 → 放到第一个空位（按行、列顺序）。没有空位返回 nil。
    public static func setModule(_ layout: [HouseLayoutCell], room: String, module: String?) -> [HouseLayoutCell]? {
        var rest = layout.filter { $0.room != room }
        guard let module else { return rest }
        if let cur = layout.first(where: { $0.room == room }) {
            var cell = cur; cell.module = module
            if validate(rest + [cell]).isEmpty {
                return layout.map { $0.room == room ? cell : $0 }
            }
        }
        guard let spot = firstFree(rest, module: module, room: room) else { return nil }
        rest.append(spot)
        return rest
    }

    /// 第一个能放下这个模块的空位（行优先）
    public static func firstFree(_ layout: [HouseLayoutCell], module: String, room: String) -> HouseLayoutCell? {
        for row in 0..<maxRows {
            for col in 0..<maxCols {
                let c = HouseLayoutCell(room: room, module: module, col: col, row: row)
                if validate(layout + [c]).isEmpty { return c }
            }
        }
        return nil
    }

    /// 经典四室预设（和 Phase 1 整图房间位对应）：后排卧室+书房，前排客厅(2)+玄关
    public static let classicFour: [HouseLayoutCell] = [
        .init(room: "", module: "bedroom", col: 0, row: 0),
        .init(room: "", module: "study", col: 1, row: 0),
        .init(room: "", module: "living", col: 0, row: 1),
        .init(room: "", module: "generic", col: 2, row: 1),
    ]

    /// 布局的模块几何是否就是经典四室（忽略 room id）——是则走整图回退
    public static func isClassicGeometry(_ layout: [HouseLayoutCell]?) -> Bool {
        guard let layout, layout.count == 4 else { return layout == nil }
        let norm = Set(layout.map { "\($0.module):\($0.col),\($0.row)" })
        let classic = Set(classicFour.map { "\($0.module):\($0.col),\($0.row)" })
        return norm == classic
    }

    /// 自动布局：按设备数排序填 3×2；客厅优先前排左边占 2 格
    public static func autolayout(rooms: [(key: String, module: HouseModule, score: Int)]) -> [HouseLayoutCell] {
        var cells: [HouseLayoutCell] = []
        var free: Set<SIMD2<Int>> = []
        for c in 0..<maxCols { for r in 0..<maxRows { free.insert(SIMD2(c, r)) } }

        func place(_ key: String, _ mod: HouseModule, fw: Int, fh: Int) -> Bool {
            for r in 0..<maxRows {
                for c in 0...(maxCols - fw) {
                    let need = (0..<fw).flatMap { dc in (0..<fh).map { dr in SIMD2(c + dc, r + dr) } }
                    guard need.allSatisfy({ free.contains($0) }) else { continue }
                    for p in need { free.remove(p) }
                    cells.append(.init(room: key, module: mod.rawValue, col: c, row: r))
                    return true
                }
            }
            return false
        }

        let sorted = rooms.sorted { $0.score > $1.score }
        // living first if present
        if let living = sorted.first(where: { $0.module == .living }) {
            _ = place(living.key, .living, fw: 2, fh: 1)
        }
        for r in sorted where r.module != .living {
            let (fw, fh) = defaultFootprint(r.module.rawValue)
            _ = place(r.key, r.module, fw: fw, fh: fh)
            if cells.count >= maxCells { break }
        }
        return cells
    }
}
