import Foundation

public struct HouseDoorway: Equatable, Sendable {
    public enum Axis: String, Sendable { case u, v }
    public let back: HouseLayoutCell
    public let front: HouseLayoutCell
    public let axis: Axis
    public let boundary: Double
    public let lower: Double
    public let upper: Double
    public var approachDepth: Double = 0.3
    public var usedFallback = false
    public var overlapsWallFixture = false
    public var width: Double { upper - lower }
    public var center: Double { (lower + upper) / 2 }
    public var stairs: Bool { HouseLevels.elevation(back) != HouseLevels.elevation(front) }
    public var wall: String { axis == .u ? "nw" : "ne" }

    public func connects(_ first: String, _ second: String) -> Bool {
        let rear = HouseDecor.roomKey(back), forward = HouseDecor.roomKey(front)
        return (first == rear && second == forward) || (first == forward && second == rear)
    }

    public func contains(along: Double) -> Bool { along >= lower && along <= upper }

    public func floorLift(in cell: HouseLayoutCell, u: Double, v: Double) -> Double {
        guard stairs, cell == back || cell == front,
              HouseLevels.elevation(cell) == min(HouseLevels.elevation(back), HouseLevels.elevation(front)),
              contains(along: axis == .u ? v : u) else { return 0 }
        let distance = abs((axis == .u ? u : v) - boundary)
        return Double(HouseGrid.levelStep) * max(0, 1 - distance / approachDepth)
    }
}

public enum HouseDoorwayPlanner {
    public static let width = 0.3
    public static let stairDepth = 0.3
    public struct UncoveredPair: Equatable, Sendable {
        public let back: HouseLayoutCell
        public let front: HouseLayoutCell
        public let widestClearSpan: Double
    }
    public struct Coverage: Equatable, Sendable {
        public var doorways: [HouseDoorway] = []
        public var uncovered: [UncoveredPair] = []
    }

    public static func ranges(_ art: HouseModuleArt, wall: String, depth: Int = 1, fixturesOnly: Bool = false) -> [ClosedRange<Double>] {
        let length = Double(wall == "nw" || wall == "se" ? art.fh : art.fw)
        let authored = fixturesOnly ? [[0, length]] : (depth > 1 ? art.stairRanges?[String(depth)]?[wall] : art.doorwayRanges?[wall]) ?? art.doorwayRanges?[wall] ?? [[0.12, length - 0.12]]
        var ranges = authored.compactMap { values -> ClosedRange<Double>? in
            guard values.count == 2, values.allSatisfy(\.isFinite) else { return nil }
            let lower = max(fixturesOnly ? 0 : 0.02, values[0]), upper = min(length - (fixturesOnly ? 0 : 0.02), values[1])
            return lower <= upper ? lower...upper : nil
        }
        func exclude(_ lower: Double, _ upper: Double) {
            ranges = ranges.flatMap { range -> [ClosedRange<Double>] in
                guard lower < range.upperBound, upper > range.lowerBound else { return [range] }
                var rest: [ClosedRange<Double>] = []
                if lower > range.lowerBound { rest.append(range.lowerBound...lower) }
                if upper < range.upperBound { rest.append(upper...range.upperBound) }
                return rest
            }
        }
        let tipX = Double(art.tip[0])
        for fixture in art.lights where fixture.wall == wall && ["curtain", "window", "ac", "water-heater"].contains(fixture.role ?? "") {
            let points = fixture.body ?? fixture.quad ?? fixture.shade ?? fixture.core ?? fixture.anchor.map { [$0] } ?? []
            let along = points.filter { $0.count == 2 }.map { wall == "nw" ? (tipX - $0[0]) / 160 : ($0[0] - tipX) / 160 }
            if let lower = along.min(), let upper = along.max() { exclude(lower - 0.08, upper + 0.08) }
        }
        return ranges.sorted { $0.lowerBound < $1.lowerBound }
    }

    public static func plan(layout: [HouseLayoutCell], catalog: HouseModuleCatalog) -> [HouseDoorway] {
        coverage(layout: layout, catalog: catalog).doorways
    }

    public static func coverage(layout: [HouseLayoutCell], catalog: HouseModuleCatalog) -> Coverage {
        let cells = layout.filter { catalog.modules[$0.module] != nil }.sorted {
            if $0.row != $1.row { return $0.row < $1.row }
            if $0.col != $1.col { return $0.col < $1.col }
            return HouseDecor.roomKey($0) < HouseDecor.roomKey($1)
        }
        var result = Coverage()
        for (index, first) in cells.enumerated() {
            for second in cells.dropFirst(index + 1) {
                guard abs(HouseLevels.elevation(first) - HouseLevels.elevation(second)) <= HouseGrid.levelStep,
                      let firstArt = catalog.modules[first.module], let secondArt = catalog.modules[second.module] else { continue }
                let back: HouseLayoutCell, front: HouseLayoutCell, axis: HouseDoorway.Axis
                if first.col + firstArt.fw == second.col || second.col + secondArt.fw == first.col {
                    axis = .u; back = first.col < second.col ? first : second; front = first.col < second.col ? second : first
                } else if first.row + firstArt.fh == second.row || second.row + secondArt.fh == first.row {
                    axis = .v; back = first.row < second.row ? first : second; front = first.row < second.row ? second : first
                } else { continue }
                let backArt = catalog.modules[back.module]!, frontArt = catalog.modules[front.module]!
                let backStart = Double(axis == .u ? back.row : back.col), frontStart = Double(axis == .u ? front.row : front.col)
                let spanStart = max(backStart, frontStart)
                let spanEnd = min(backStart + Double(axis == .u ? backArt.fh : backArt.fw), frontStart + Double(axis == .u ? frontArt.fh : frontArt.fw))
                guard spanEnd > spanStart else { continue }
                let middle = (spanStart + spanEnd) / 2
                var candidates: [(center: Double, width: Double, depth: Double)] = []
                let stairs = HouseLevels.elevation(back) != HouseLevels.elevation(front)
                for depth in stairs ? [3, 2, 1] : [1] {
                    let rearDepth = stairs && HouseLevels.elevation(back) < HouseLevels.elevation(front) ? depth : 1
                    let forwardDepth = stairs && HouseLevels.elevation(front) < HouseLevels.elevation(back) ? depth : 1
                    for rear in ranges(backArt, wall: axis == .u ? "se" : "sw", depth: rearDepth) {
                        for forward in ranges(frontArt, wall: axis == .u ? "nw" : "ne", depth: forwardDepth) {
                            let lower = max(spanStart, rear.lowerBound + backStart, forward.lowerBound + frontStart)
                            let upper = min(spanEnd, rear.upperBound + backStart, forward.upperBound + frontStart)
                            let available = min(width, upper - lower)
                            if available >= 0.2 - 0.000001 { candidates.append((min(max(middle, lower + available / 2), upper - available / 2), available, min(stairDepth, Double(depth) / 8))) }
                        }
                    }
                }
                let preferred = candidates.sorted(by: {
                    if abs($0.width - $1.width) > 0.000001 { return $0.width > $1.width }
                    if $0.depth != $1.depth { return $0.depth > $1.depth }
                    if abs($0.center - middle) != abs($1.center - middle) { return abs($0.center - middle) < abs($1.center - middle) }
                    return $0.center < $1.center
                }).first
                let fallbackWidth = min(width, spanEnd - spanStart)
                var fixtureSafeCenters: [Double] = []
                if preferred == nil {
                    for rear in ranges(backArt, wall: axis == .u ? "se" : "sw", fixturesOnly: true) {
                        for forward in ranges(frontArt, wall: axis == .u ? "nw" : "ne", fixturesOnly: true) {
                            let lower = max(spanStart, rear.lowerBound + backStart, forward.lowerBound + frontStart)
                            let upper = min(spanEnd, rear.upperBound + backStart, forward.upperBound + frontStart)
                            if upper - lower >= fallbackWidth - 0.000001 {
                                fixtureSafeCenters.append(min(max(middle, lower + fallbackWidth / 2), upper - fallbackWidth / 2))
                            }
                        }
                    }
                }
                let fallbackCenter = fixtureSafeCenters.sorted {
                    abs($0 - middle) == abs($1 - middle) ? $0 < $1 : abs($0 - middle) < abs($1 - middle)
                }.first ?? middle
                let choice = preferred ?? (center: fallbackCenter, width: fallbackWidth, depth: stairDepth)
                result.doorways.append(.init(back: back, front: front, axis: axis, boundary: Double(axis == .u ? front.col : front.row), lower: choice.center - choice.width / 2, upper: choice.center + choice.width / 2, approachDepth: stairs ? choice.depth : stairDepth, usedFallback: preferred == nil, overlapsWallFixture: preferred == nil && fixtureSafeCenters.isEmpty))
            }
        }
        return result
    }
}
