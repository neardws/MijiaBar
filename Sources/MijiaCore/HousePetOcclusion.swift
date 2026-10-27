import Foundation
import CoreGraphics

public struct HousePetOccluder: Codable, Sendable {
    public var id: String
    public var kind: String?
    public var footprint: [Double]
    public var z: Double
    public var silhouette: [[Double]]?
    public var perches: [String]?

    var isValid: Bool {
        !id.isEmpty && footprint.count == 4 && footprint.allSatisfy(\.isFinite)
            && footprint[0] < footprint[2] && footprint[1] < footprint[3] && z.isFinite && z > 0
            && (silhouette.map { $0.count >= 3 && $0.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isFinite) } } ?? true)
    }

    public func polygon(tip: HousePetPoint) -> [[Double]] {
        if let silhouette { return silhouette.map { [$0[0] + tip.x, $0[1] + tip.y] } }
        let back = HousePetFurniture.project(footprint[0], footprint[1], tip: tip, z: z)
        let right = HousePetFurniture.project(footprint[2], footprint[1], tip: tip)
        let front = HousePetFurniture.project(footprint[2], footprint[3], tip: tip)
        let left = HousePetFurniture.project(footprint[0], footprint[3], tip: tip)
        return [[back.x, back.y], [right.x, right.y - z], [right.x, right.y],
                [front.x, front.y], [left.x, left.y], [left.x, left.y - z]]
    }
}

public struct HousePetFurniture: Sendable {
    public let definition: HousePetOccluder
    public let module: String
    public let tip: HousePetPoint
    public let polygon: [[Double]]
    private let perches: [HousePetSpots.Spot]

    public init(definition: HousePetOccluder, module: String, tip: HousePetPoint, spots: [HousePetSpots.Spot]) {
        self.definition = definition; self.module = module; self.tip = tip
        polygon = definition.polygon(tip: tip)
        perches = spots.filter { definition.perches?.contains($0.id) == true && abs(($0.z ?? 0) - definition.z) < 0.01 }
    }

    public static func project(_ u: Double, _ v: Double, tip: HousePetPoint, z: Double = 0) -> HousePetPoint {
        .init(x: tip.x + 160 * (u - v), y: tip.y + 66 * (u + v) - z)
    }

    public func isActive(for pose: HousePetPose) -> Bool {
        guard pose.module == module else { return false }
        if perches.contains(where: {
            pose.spotID == pose.room + "/" + $0.id
                && Self.project($0.at[0], $0.at[1], tip: tip, z: $0.z ?? 0).distance(to: pose.point) < 0.01
        }) { return false }
        let difference = (pose.point.x - tip.x) / 160
        let sum = (pose.point.y - tip.y) / 66
        let floorU = (sum + difference) / 2, floorV = (sum - difference) / 2
        let rect = definition.footprint
        let nearU = min(rect[2], rect[3] + difference)
        let farU = max(rect[0], rect[1] + difference)
        guard nearU >= farU else { return false }
        let frontV = nearU - difference
        let frontY = tip.y + 66 * (nearU + frontV)
        return floorU <= nearU && floorV <= frontV && pose.point.y < frontY
    }
}

public enum HousePetOcclusion {
    public static func holes(for pose: HousePetPose, in world: HousePetWorld) -> [[[Double]]] {
        (world.occluders[pose.room] ?? []).filter { $0.isActive(for: pose) }.map(\.polygon)
    }

    public static func clipFurniture(_ polygons: [[[Double]]], in context: CGContext) {
        let bounds = context.boundingBoxOfClipPath
        for polygon in polygons where polygon.count >= 3 {
            let path = CGMutablePath(); path.addRect(bounds)
            path.addLines(between: polygon.map { CGPoint(x: $0[0], y: $0[1]) }); path.closeSubpath()
            context.addPath(path); context.clip(using: .evenOdd)
        }
    }
}
