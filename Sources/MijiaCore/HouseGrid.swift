import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// Phase 2 网格几何（v2，见 docs/HOUSE_MODULES.md）。
///
/// 屏幕坐标：`tip(col,row) = ((col-row)·W/2, (col+row)·FH/2)`；row 增大朝前（左下），col 增大朝右（右下）。
/// 每个模块 = 自己的地板 + 两面后墙（NW 左后墙、NE 右后墙）+ 前沿地台。
/// 共享墙只有一个主人：前/右侧的格子（它的后墙）；后方格子从不画前墙（剖面朝镜头敞开）。
/// 共享墙切到 `cutH`（护墙板高度）露出后方房间；外墙保持 `wallH` 全高。
/// 绘制顺序：(row, col) 从小到大 = 从后到前。
public enum HouseGrid {
    public static let W = 320
    public static let floorH = 132
    public static let wallH = 104
    public static let cutH = 40
    public static let slab = 14
    public static let px = 2
    /// 墙顶厚度方向（朝墙后）：NW 墙往左上，NE 墙往右上
    public static let capNW = (x: -10, y: -4)
    public static let capNE = (x: 10, y: -4)

    public static func tip(col: Int, row: Int) -> (x: Int, y: Int) {
        ((col - row) * (W / 2), (col + row) * (floorH / 2))
    }

    /// 从小到大绘制 = 从后到前
    public static func painterKey(col: Int, row: Int) -> (Int, Int) { (row, col) }
}

/// 用户布局里的一格（house.json `layout`）
public struct HouseLayoutCell: Codable, Equatable, Sendable, Hashable {
    public var room: String
    public var module: String
    public var col: Int
    public var row: Int
    public init(room: String, module: String, col: Int, row: Int) {
        self.room = room; self.module = module; self.col = col; self.row = row
    }
}

/// 模块目录条目（catalog.json）。坐标都是模块 PNG 内像素（左上原点）。
public struct HouseModuleArt: Codable, Equatable, Sendable {
    public var footprint: [Int]
    public var size: [Int]
    /// 后墙角落地点（地板菱形后顶点）在 PNG 内的位置
    public var tip: [Int]
    public var region: [[Double]]
    public var label: [Double]
    public var badges: [[Double]]
    public var lights: [HouseModuleLight]
    /// "day-unlit" / "day-lit" / "night-unlit" / "night-lit"，以及切墙版 "…-cut"
    public var variants: [String: String]?
    public var fw: Int { footprint.first ?? 1 }
    public var fh: Int { footprint.count > 1 ? footprint[1] : 1 }
}

public struct HouseModuleLight: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String?
    public var role: String?
    public var reveal: HouseModuleReveal?
    public var shade: [[Double]]?
    public var screen: [[Double]]?
    public var core: [[Double]]?
    /// 灯具装在哪面墙上（"nw"/"ne"）；那面墙被切时灯具本体不可见
    public var wall: String?
    /// 墙挂灯具本体所在点（模块 PNG 内）：用来判断它落在哪一段墙上
    public var anchor: [Double]?
    /// 本体被切掉时的替代位置（地面点）：App 在这里画一个设备徽章（空调）
    public var alt: [Double]?
}

public enum HouseModuleReveal: Codable, Equatable, Sendable {
    case room
    case ellipse(cx: Double, cy: Double, rx: Double, ry: Double)
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self), s == "room" { self = .room; return }
        let v = try c.decode([Double].self)
        guard v.count == 4 else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "reveal") }
        self = .ellipse(cx: v[0], cy: v[1], rx: v[2], ry: v[3])
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .room: try c.encode("room")
        case .ellipse(let cx, let cy, let rx, let ry): try c.encode([cx, cy, rx, ry])
        }
    }
}

public struct HouseModuleCatalog: Codable, Equatable, Sendable {
    public var schema: Int
    public var style: String?
    public var modules: [String: HouseModuleArt]
}

/// 一面后墙的一段（每格一段）。a/b = 模块内地面点；height = wallH 或 cutH。
public struct HouseWallSegment: Equatable, Sendable {
    public enum Side: String, Sendable { case nw, ne }
    public var side: Side
    public var a: (x: Int, y: Int)
    public var b: (x: Int, y: Int)
    public var height: Int
    public static func == (l: Self, r: Self) -> Bool {
        l.side == r.side && l.a == r.a && l.b == r.b && l.height == r.height
    }
}

/// 布局规划：每个模块的墙段高度（共享墙切、外墙全高）。纯逻辑，便于测试。
public enum HouseWallPlanner {
    public struct Placed: Sendable {
        public var cell: HouseLayoutCell
        public var fw: Int
        public var tip: (x: Int, y: Int)
        public var segments: [HouseWallSegment]
    }

    public static func occupancy(_ cells: [(HouseLayoutCell, Int)]) -> Set<[Int]> {
        var s = Set<[Int]>()
        for (c, fw) in cells { for dc in 0..<fw { s.insert([c.col + dc, c.row]) } }
        return s
    }

    /// NW 墙与 (col-1,row) 共享；NE 墙第 i 段与 (col+i,row-1) 共享
    public static func plan(_ cells: [(HouseLayoutCell, Int)], tips: [String: (x: Int, y: Int)]) -> [Placed] {
        let occ = occupancy(cells)
        return cells.map { c, fw in
            let T = tips[c.module] ?? (0, 0)
            var segs: [HouseWallSegment] = []
            let L = (x: T.x - HouseGrid.W / 2, y: T.y + HouseGrid.floorH / 2)
            segs.append(.init(side: .nw, a: T, b: L, height: occ.contains([c.col - 1, c.row]) ? HouseGrid.cutH : HouseGrid.wallH))
            for i in 0..<fw {
                let a = (x: T.x + i * HouseGrid.W / 2, y: T.y + i * HouseGrid.floorH / 2)
                let b = (x: a.x + HouseGrid.W / 2, y: a.y + HouseGrid.floorH / 2)
                segs.append(.init(side: .ne, a: a, b: b, height: occ.contains([c.col + i, c.row - 1]) ? HouseGrid.cutH : HouseGrid.wallH))
            }
            return Placed(cell: c, fw: fw, tip: T, segments: segs)
        }
    }

    /// 某格自己的 NW / NE 墙高（不存在 = 0）
    public static func nwHeight(_ occ: Set<[Int]>, _ col: Int, _ row: Int) -> Int {
        guard occ.contains([col, row]) else { return 0 }
        return occ.contains([col - 1, row]) ? HouseGrid.cutH : HouseGrid.wallH
    }

    public static func neHeight(_ occ: Set<[Int]>, _ col: Int, _ row: Int) -> Int {
        guard occ.contains([col, row]) else { return 0 }
        return occ.contains([col, row - 1]) ? HouseGrid.cutH : HouseGrid.wallH
    }
}

/// 合成结果：两张整图 + 转成全局坐标的场景描述
public struct HouseComposeResult {
    public let width: Int
    public let height: Int
    public let originX: Int
    public let originY: Int
    public let milliseconds: Double
    public let moduleKeys: [String]
#if canImport(CoreGraphics)
    public let unlit: CGImage?
    public let lit: CGImage?
#endif
    public let sceneJSON: Data
}
