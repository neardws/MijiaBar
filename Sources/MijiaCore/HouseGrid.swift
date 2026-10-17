import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// 等距格子（设计稿 §4.3）。row 增大朝前；col 增大朝右。
public enum HouseGrid {
    public static let W = 240
    public static let floorH = 120
    public static let wallH = 150
    public static let floorThick = 12
    public static let px = 2

    public static func tip(col: Int, row: Int) -> (x: Int, y: Int) {
        ((col - row) * (W / 2), (col + row) * (floorH / 2))
    }

    public static func painterKey(col: Int, row: Int) -> (Int, Int) { (col + row, col) }
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

/// 模块目录条目（catalog.json / module-*.json）
public struct HouseModuleArt: Codable, Equatable, Sendable {
    public var footprint: [Int]
    public var size: [Int]
    public var tip: [Int]
    public var region: [[Double]]
    public var label: [Double]
    public var badges: [[Double]]
    public var lights: [HouseModuleLight]
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

/// 合成结果：两张整图 + 转成全局坐标的场景描述（给现有 HouseCutawaySceneView 用）
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
