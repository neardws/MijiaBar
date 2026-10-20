import Foundation

public struct HousePetPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public func distance(to point: Self) -> Double { hypot(x - point.x, y - point.y) }
}

public struct HousePetSpots: Codable, Sendable {
    public struct Spot: Codable, Sendable {
        public var id: String
        public var kind: String
        public var at: [Double]
        public var z: Double?
        public var facing: String?
        public var from: [Int]?
    }
    public struct Module: Codable, Sendable {
        public var grid: [Int]
        public var walk: [String]
        public var spots: [Spot]
    }
    public var cellsPerGrid: Int
    public var artSets: [String: String]
    public var sets: [String: [String: Module]]
    public static func load(from url: URL) throws -> Self {
        let spots = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard (1...64).contains(spots.cellsPerGrid), spots.sets.values.allSatisfy({ modules in modules.values.allSatisfy { module in
            module.grid.count == 2 && module.grid.allSatisfy { (1...128).contains($0) } && module.walk.count == module.grid[1]
                && module.walk.allSatisfy { $0.count == module.grid[0] && $0.allSatisfy { $0 == "." || $0 == "#" } }
                && module.spots.allSatisfy { $0.at.count == 2 && $0.at.allSatisfy(\.isFinite) && ($0.z ?? 0).isFinite && ($0.from == nil || $0.from?.count == 2) }
        } }) else { throw HousePetError.resource }
        return spots
    }
}

public final class HousePetWorld: @unchecked Sendable {
    public struct Node: Equatable, Sendable {
        public let id: Int
        public let room: String
        public let module: String
        public let col: Int
        public let row: Int
        public let u: Int
        public let v: Int
        public let elevation: Int
        public let point: HousePetPoint
    }
    public struct Edge: Sendable {
        public let node: Int
        public let jump: Bool
    }
    public struct Spot: Sendable {
        public let id: String
        public let kind: String
        public let node: Int
        public let point: HousePetPoint
        public let facing: String
        public let priority: Int
    }
    public let nodes: [Node]
    public let edges: [[Edge]]
    public let spots: [Spot]
    public let rooms: Set<String>
    public let cellSize: Double
    private let edgeLengths: [[Double]]
    private let lock = NSLock()
    private var paths: [String: [Int]] = [:]

    public init(layout: [HouseLayoutCell], catalog: HouseModuleCatalog, spots source: HousePetSpots, style: String = "cozy-wood",
                origin: HousePetPoint = .init(x: 0, y: 0), offsets: [String: HousePetPoint] = [:],
                decor: [HouseDecorPlacement] = [], items: HouseDecorCatalog? = nil) {
        let scale = max(1, source.cellsPerGrid)
        cellSize = hypot(160, 66) / Double(scale)
        let modules = source.sets[source.artSets[style] ?? "cozy"] ?? [:]
        var nodes: [Node] = [], edges: [[Edge]] = [], spots: [Spot] = []
        var nodeMap: [String: Int] = [:]
        func key(_ room: String, _ col: Int, _ row: Int) -> String { "\(room)/\(col)/\(row)" }
        func point(_ at: [Double], cell: HouseLayoutCell, art: HouseModuleArt, height: Double = 0) -> HousePetPoint {
            let room = HouseDecor.roomKey(cell), tip = HouseGrid.tip(col: cell.col, row: cell.row)
            let offset = offsets[room] ?? .init(x: Double(tip.x - art.tip[0]) - origin.x, y: Double(tip.y - art.tip[1] - HouseLevels.elevation(cell)) - origin.y)
            return .init(x: offset.x + Double(art.tip[0]) + 160 * (at[0] - at[1]), y: offset.y + Double(art.tip[1]) + 66 * (at[0] + at[1]) - height)
        }
        for cell in layout {
            guard let module = modules[cell.module], let art = catalog.modules[cell.module], module.grid.count == 2 else { continue }
            let room = HouseDecor.roomKey(cell)
            for (row, line) in module.walk.enumerated() {
                for (col, token) in line.enumerated() where token == "." {
                    let id = nodes.count; nodeMap[key(room, col, row)] = id
                    nodes.append(.init(id: id, room: room, module: cell.module, col: col, row: row,
                                       u: cell.col * scale + col, v: cell.row * scale + row, elevation: HouseLevels.elevation(cell),
                                       point: point([(Double(col) + 0.5) / Double(scale), (Double(row) + 0.5) / Double(scale)], cell: cell, art: art)))
                    edges.append([])
                }
            }
        }
        for node in nodes {
            for delta in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                if let other = nodeMap[key(node.room, node.col + delta.0, node.row + delta.1)] { edges[node.id].append(.init(node: other, jump: false)) }
            }
        }
        for (leftIndex, leftCell) in layout.enumerated() {
            guard let leftArt = catalog.modules[leftCell.module] else { continue }
            for rightCell in layout.dropFirst(leftIndex + 1) {
                guard let rightArt = catalog.modules[rightCell.module], abs(HouseLevels.elevation(leftCell) - HouseLevels.elevation(rightCell)) <= 48 else { continue }
                let horizontal = (leftCell.col + leftArt.fw == rightCell.col || rightCell.col + rightArt.fw == leftCell.col)
                    && max(leftCell.row, rightCell.row) < min(leftCell.row + leftArt.fh, rightCell.row + rightArt.fh)
                let vertical = (leftCell.row + leftArt.fh == rightCell.row || rightCell.row + rightArt.fh == leftCell.row)
                    && max(leftCell.col, rightCell.col) < min(leftCell.col + leftArt.fw, rightCell.col + rightArt.fw)
                guard horizontal || vertical else { continue }
                let leftNodes = nodes.filter { $0.room == HouseDecor.roomKey(leftCell) }, rightNodes = nodes.filter { $0.room == HouseDecor.roomKey(rightCell) }
                for left in leftNodes {
                    for right in rightNodes {
                        let du = abs(left.u - right.u), dv = abs(left.v - right.v)
                        if (horizontal && dv == 0 && du <= 2) || (vertical && du == 0 && dv <= 2) {
                            edges[left.id].append(.init(node: right.id, jump: true)); edges[right.id].append(.init(node: left.id, jump: true))
                        }
                    }
                }
            }
        }
        func nearest(_ point: HousePetPoint, room: String) -> Int? {
            nodes.filter { $0.room == room }.min { $0.point.distance(to: point) < $1.point.distance(to: point) }?.id
        }
        for cell in layout {
            guard let module = modules[cell.module], let art = catalog.modules[cell.module] else { continue }
            let room = HouseDecor.roomKey(cell)
            for spot in module.spots where spot.at.count == 2 {
                let target = point(spot.at, cell: cell, art: art, height: spot.z ?? 0)
                let approach = spot.from.flatMap { $0.count == 2 ? nodeMap[key(room, $0[0], $0[1])] : nil }
                if let node = approach ?? nearest(point(spot.at, cell: cell, art: art), room: room) {
                    spots.append(.init(id: room + "/" + spot.id, kind: spot.kind, node: node, point: target, facing: spot.facing ?? "SE",
                                       priority: spot.kind == "perch" || spot.id.contains("bed") || spot.id.contains("sofa") ? 1 : 2))
                }
            }
            for placement in decor where placement.room == room && placement.at.count == 2 && items?.items.first(where: { $0.id == placement.item })?.petSpot == true {
                let floor = HousePetPoint(x: placement.at[0] - Double(art.tip[0]), y: placement.at[1] - Double(art.tip[1]))
                let uv = [(floor.x / 160 + floor.y / 66) / 2, (floor.y / 66 - floor.x / 160) / 2]
                if let node = nearest(point(uv, cell: cell, art: art), room: room) {
                    spots.append(.init(id: room + "/decor/" + placement.slot, kind: "sleep", node: node, point: nodes[node].point, facing: "SE", priority: 0))
                }
            }
            for light in art.lights {
                guard let pool = light.pool, pool.count >= 2 else { continue }
                let dx = pool[0] - Double(art.tip[0]), dy = pool[1] - Double(art.tip[1])
                let uv = [(dx / 160 + dy / 66) / 2, (dy / 66 - dx / 160) / 2]
                if let node = nearest(point(uv, cell: cell, art: art), room: room) {
                    spots.append(.init(id: room + "/light/" + light.id, kind: "light", node: node, point: nodes[node].point, facing: "SE", priority: 2))
                }
            }
            if !spots.contains(where: { nodes[$0.node].room == room && ["sleep", "perch"].contains($0.kind) }), let node = nodes.first(where: { $0.room == room }) {
                spots.append(.init(id: room + "/sleep", kind: "sleep", node: node.id, point: node.point, facing: "SE", priority: 3))
            }
        }
        self.nodes = nodes; self.edges = edges; self.spots = spots.sorted { $0.id < $1.id }; rooms = Set(nodes.map(\.room))
        edgeLengths = edges.enumerated().map { index, neighbors in
            neighbors.map { nodes[index].point.distance(to: nodes[$0.node].point) }
        }
    }

    public func path(from: Int, to: Int, room: String? = nil, allowedRooms: Set<String>? = nil) -> [Int] {
        guard nodes.indices.contains(from), nodes.indices.contains(to), room == nil || (nodes[from].room == room && nodes[to].room == room),
              allowedRooms == nil || (allowedRooms!.contains(nodes[from].room) && allowedRooms!.contains(nodes[to].room)) else { return [] }
        let key = "\(from):\(to):\(room ?? "*"):" + (allowedRooms?.sorted().joined(separator: ",") ?? "*")
        lock.lock(); let cached = paths[key]; lock.unlock()
        if let cached { return cached }
        var state = [SearchNode](repeating: .init(), count: nodes.count)
        let restrictRooms = allowedRooms.map { !$0.isSuperset(of: rooms) } ?? false
        if room != nil || restrictRooms {
            for node in nodes { state[node.id].allowed = (room == nil || node.room == room) && (!restrictRooms || allowedRooms!.contains(node.room)) }
        }
        var heap = [Int](repeating: 0, count: nodes.count)
        let result = state.withUnsafeMutableBufferPointer { state in
            heap.withUnsafeMutableBufferPointer { heap -> [Int] in
                var open = Frontier(heap: heap, state: state)
                state[from].cost = 0
                open.insert(from, score: nodes[from].point.distance(to: nodes[to].point))
                while let current = open.pop() {
                    if current == to { break }
                    for (index, edge) in edges[current].enumerated() where state[edge.node].allowed {
                        let nextCost = state[current].cost + edgeLengths[current][index]
                        if nextCost < state[edge.node].cost {
                            state[edge.node].cost = nextCost; state[edge.node].previous = current
                            if state[edge.node].heuristic < 0 { state[edge.node].heuristic = nodes[edge.node].point.distance(to: nodes[to].point) }
                            open.insert(edge.node, score: nextCost + state[edge.node].heuristic)
                        }
                    }
                }
                guard state[to].cost < .infinity else { return [] }
                var current = to, result = [to]
                while current != from, state[current].previous >= 0 {
                    current = state[current].previous; result.append(current)
                }
                result.reverse(); return result
            }
        }
        lock.lock(); if paths.count >= 4096 { paths.removeAll() }; paths[key] = result; lock.unlock()
        return result
    }

    private struct SearchNode {
        var allowed = true
        var cost = Double.infinity
        var previous = -1
        var heuristic = -1.0
        var position = -1
        var score = Double.infinity
    }

    private struct Frontier {
        let heap: UnsafeMutableBufferPointer<Int>
        let state: UnsafeMutableBufferPointer<SearchNode>
        var count = 0
        func precedes(_ left: Int, _ right: Int) -> Bool {
            state[left].score == state[right].score ? left < right : state[left].score < state[right].score
        }
        func swap(_ left: Int, _ right: Int) {
            let saved = heap[left]; heap[left] = heap[right]; heap[right] = saved
            state[heap[left]].position = left; state[heap[right]].position = right
        }
        mutating func insert(_ node: Int, score: Double) {
            state[node].score = score
            if state[node].position < 0 { state[node].position = count; heap[count] = node; count += 1 }
            var index = state[node].position
            while index > 0 {
                let parent = (index - 1) / 2
                guard precedes(heap[index], heap[parent]) else { break }
                swap(index, parent); index = parent
            }
        }
        mutating func pop() -> Int? {
            guard count > 0 else { return nil }
            let first = heap[0]; count -= 1
            let last = heap[count]; state[first].position = -1
            if count > 0 {
                heap[0] = last; state[last].position = 0
                var index = 0
                while index * 2 + 1 < count {
                    let left = index * 2 + 1, right = left + 1
                    let child = right < count && precedes(heap[right], heap[left]) ? right : left
                    guard precedes(heap[child], heap[index]) else { break }
                    swap(index, child); index = child
                }
            }
            return first
        }
    }
}
