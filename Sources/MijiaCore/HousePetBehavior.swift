import Foundation

public struct HousePetContext: Equatable, Sendable {
    public var night: Bool
    public var lights: [String: Bool]
    public var tvRooms: Set<String>
    public var rooms: Set<String>
    public var petIDs: [String]
    public var changedAt: Date?
    public var changedRoom: String?
    public var restOnly: Bool
    public var enabled: Bool
    public var timeZone: TimeZone
    public init(night: Bool = false, lights: [String: Bool] = [:], tvRooms: Set<String> = [], rooms: Set<String> = [],
                petIDs: [String] = [], changedAt: Date? = nil, changedRoom: String? = nil, restOnly: Bool = false,
                enabled: Bool = true, timeZone: TimeZone = .current) {
        self.night = night; self.lights = lights; self.tvRooms = tvRooms; self.rooms = rooms; self.petIDs = petIDs
        self.changedAt = changedAt; self.changedRoom = changedRoom; self.restOnly = restOnly; self.enabled = enabled; self.timeZone = timeZone
    }
}

public struct HousePetPose: Equatable, Sendable {
    public var point: HousePetPoint
    public var facing: String
    public var action: String
    public var frameIndex: Int
    public var mirrored: Bool
    public var jumpLift: Double
    public var module: String
    public var room: String
    public var visible: Bool
    public init(point: HousePetPoint, facing: String = "SE", action: String = "idle", frameIndex: Int = 0,
                mirrored: Bool = false, jumpLift: Double = 0, module: String, room: String, visible: Bool = true) {
        self.point = point; self.facing = facing; self.action = action; self.frameIndex = frameIndex
        self.mirrored = mirrored; self.jumpLift = jumpLift; self.module = module; self.room = room; self.visible = visible
    }
}

public final class HousePetBehavior: @unchecked Sendable {
    private struct Segment {
        var start: Double
        var duration: Double
        var from: HousePetPoint
        var to: HousePetPoint
        var node: Int
        var facing: String
        var action: String
        var rest: HousePetWorld.Spot
    }
    private struct TimedSegment { var start: Double; var duration: Double; var movement: Int }
    private struct Plan {
        var timeline: [TimedSegment]
        var movements: [Segment]
        init(timeline: [TimedSegment], movements: [Segment]) { self.timeline = timeline; self.movements = movements }
        init(segments: [Segment]) {
            movements = segments
            timeline = segments.enumerated().map { .init(start: $0.element.start, duration: $0.element.duration, movement: $0.offset) }
        }
    }
    private struct Route: Hashable { var from: Int; var to: Int }
    private struct TravelTemplate { var reachable: Bool; var timeline: [TimedSegment] }
    private struct RequestKey: Hashable {
        var world: ObjectIdentifier
        var pet: String
        var home: String?
        var day: Date
        var zone: String
        var rooms: Set<String>
        var petIDs: [String]
    }
    private struct PreparedKey { var text: String; var roster: [String]; var rank: Int }
    private let rig: HousePetRig
    private let lock = NSLock()
    private var plans: [String: Plan] = [:]
    private var retainedWorlds: [ObjectIdentifier: HousePetWorld] = [:]
    private var preparedKeys: [RequestKey: PreparedKey] = [:]
    public init(rig: HousePetRig) { self.rig = rig }

    private static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    public func poses(_ pets: [HousePet], world: HousePetWorld, context: HousePetContext, at date: Date,
                      overrides: [String: HousePetPose] = [:]) -> [String: HousePetPose] {
        var result: [String: HousePetPose] = [:]
        for pet in pets { result[pet.id] = overrides[pet.id] ?? pose(pet, world: world, context: context, at: date) }
        guard context.restOnly else { return result }
        var placed = pets.compactMap { overrides[$0.id] }.filter(\.visible).map(\.point)
        for pet in pets.sorted(by: { $0.id < $1.id }) where overrides[pet.id] == nil {
            guard var pose = result[pet.id], pose.visible else { continue }
            if !placed.allSatisfy({ $0.distance(to: pose.point) >= 3 * world.cellSize }) {
                let candidates = world.nodes.filter { $0.room == pose.room && (pet.homeRoom == nil || $0.room == pet.homeRoom) }
                    .sorted {
                        let left = $0.point.distance(to: pose.point), right = $1.point.distance(to: pose.point)
                        return left == right ? $0.id < $1.id : left < right
                    }
                for cells in [3.0, 2.0, 1.0] {
                    if let node = candidates.first(where: { node in placed.allSatisfy { $0.distance(to: node.point) >= cells * world.cellSize } }) {
                        pose.point = node.point; pose.module = node.module; pose.room = node.room; pose.jumpLift = 0
                        break
                    }
                }
                result[pet.id] = pose
            }
            placed.append(pose.point)
        }
        return result
    }

    public func pose(_ pet: HousePet, world: HousePetWorld, context: HousePetContext = .init(), at date: Date) -> HousePetPose {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = context.timeZone
        let day = calendar.startOfDay(for: date), elapsed = max(0, date.timeIntervalSince(day))
        let rooms = context.rooms.isEmpty ? world.rooms : context.rooms
        guard let first = world.nodes.first(where: { rooms.contains($0.room) && (pet.homeRoom == nil || $0.room == pet.homeRoom) }) else {
            return .init(point: .init(x: 0, y: 0), facing: "SE", action: "idle", frameIndex: 0, mirrored: false, jumpLift: 0, module: "", room: "", visible: false)
        }
        let identity = ObjectIdentifier(world)
        lock.lock(); defer { lock.unlock() }
        if plans.count > 24 { plans.removeAll(); retainedWorlds.removeAll(); preparedKeys.removeAll() }
        retainedWorlds[identity] = world
        let request = RequestKey(world: identity, pet: pet.id, home: pet.homeRoom, day: day, zone: context.timeZone.identifier, rooms: rooms, petIDs: context.petIDs)
        let prepared: PreparedKey
        if let cached = preparedKeys[request] { prepared = cached } else {
            let roster = Array(Set(context.petIDs + [pet.id])).sorted()
            let text = "\(identity)|\(pet.id)|\(pet.homeRoom ?? "*")|\(day.timeIntervalSince1970)|\(context.timeZone.identifier)|" + rooms.sorted().joined(separator: ",") + "|" + roster.joined(separator: ",")
            prepared = .init(text: text, roster: roster, rank: roster.firstIndex(of: pet.id) ?? 0)
            if preparedKeys.count >= 24 { preparedKeys.removeAll() }
            preparedKeys[request] = prepared
        }
        let key = prepared.text, roster = prepared.roster, rank = prepared.rank
        func reservedSpots() -> [HousePetWorld.Spot] {
            var separated: [HousePetWorld.Spot] = []
            for room in rooms.sorted() {
                var candidates = world.spots.filter { world.nodes[$0.node].room == room && $0.kind != "light" }
                for node in world.nodes where node.room == room {
                    candidates.append(.init(id: "~\(node.id)", kind: "sit", node: node.id, point: node.point, facing: "SE", priority: 4))
                }
                separated += Self.separatedSpots(candidates, count: roster.count, cellSize: world.cellSize)
            }
            let own = separated.enumerated().filter { $0.offset % roster.count == rank }.map(\.element)
                .filter { pet.homeRoom == nil || world.nodes[$0.node].room == pet.homeRoom }
            return own.isEmpty ? [.init(id: "fallback", kind: "sit", node: first.id, point: first.point, facing: "SE", priority: 4)] : own
        }
        func build() -> Plan {
            let spots = reservedSpots()
            var templates: [Route: TravelTemplate] = [:]
            var state = Self.seed("\(calendar.component(.year, from: day))-\(calendar.component(.month, from: day))-\(calendar.component(.day, from: day))|\(pet.id)")
            func random(_ count: Int) -> Int { state = state &* 6364136223846793005 &+ 1442695040888963407; return Int((state >> 32) % UInt64(max(1, count))) }
            var timeline: [TimedSegment] = [], movements: [Segment] = [], time = 0.0, currentIndex = random(spots.count)
            timeline.reserveCapacity(min(32768, max(4096, world.nodes.count * 192)))
            var stationary = [Int](repeating: -1, count: spots.count * 6)
            while time < 90000 {
                let current = spots[currentIndex]
                let actionIndex = random(6), stationaryIndex = currentIndex * 6 + actionIndex
                let duration = Double(8 + random(53))
                if stationary[stationaryIndex] < 0 {
                    stationary[stationaryIndex] = movements.count
                    movements.append(.init(start: 0, duration: 0, from: current.point, to: current.point, node: current.node,
                                           facing: current.facing, action: ["idle", "sit", "groom", "lookup", "stretch", "sleep"][actionIndex], rest: current))
                }
                timeline.append(.init(start: time, duration: duration, movement: stationary[stationaryIndex])); time += duration
                let nextIndex = random(spots.count), next = spots[nextIndex], route = Route(from: currentIndex, to: nextIndex)
                let template: TravelTemplate
                if let cached = templates[route] { template = cached } else {
                    let path = world.path(from: current.node, to: next.node, room: pet.homeRoom, allowedRooms: rooms)
                    var moves: [TimedSegment] = []
                    moves.reserveCapacity(path.count + 1)
                    Self.travel(path: path, from: current.point, target: next, world: world) { from, to, node, facing, action, duration in
                        moves.append(.init(start: 0, duration: duration, movement: movements.count))
                        movements.append(.init(start: 0, duration: duration, from: from, to: to, node: node, facing: facing, action: action, rest: next))
                    }
                    template = .init(reachable: !path.isEmpty, timeline: moves); templates[route] = template
                }
                guard template.reachable else { continue }
                for var move in template.timeline {
                    move.start = time; timeline.append(move); time += move.duration
                }
                currentIndex = nextIndex
            }
            return .init(timeline: timeline, movements: movements)
        }
        let base: Plan
        if let cached = plans[key] { base = cached } else { base = build(); plans[key] = base }
        func segment(_ plan: Plan, _ elapsed: Double) -> Segment {
            var low = 0, high = plan.timeline.count
            while low < high { let middle = (low + high) / 2; if plan.timeline[middle].start <= elapsed { low = middle + 1 } else { high = middle } }
            let timed = plan.timeline[max(0, low - 1)]
            var result = plan.movements[timed.movement]; result.start = timed.start; result.duration = timed.duration
            return result
        }
        var selected = segment(base, elapsed), localTime = elapsed
        let change = context.changedAt ?? day
        if date >= change {
            let startTime = max(0, change.timeIntervalSince(day)), start = segment(base, startTime)
            let room = world.nodes[start.node].room
            let nightSleep = context.night && context.lights[room] != true
            let tv = pet.homeRoom.map { context.tvRooms.contains($0) } ?? !context.tvRooms.intersection(rooms).isEmpty
            let light = context.changedRoom == room && context.changedAt != nil
            if nightSleep || tv || light {
                let reactionKey = key + "|reaction|\(startTime)|\(nightSleep)|\(tv)|\(light)|" + context.tvRooms.sorted().joined(separator: ",") + "|" + context.lights.keys.sorted().map { "\($0)=\(context.lights[$0]!)" }.joined(separator: ",")
                let reaction: Plan
                if let cached = plans[reactionKey] { reaction = cached } else {
                    let targetKind = nightSleep ? "sleep" : tv ? "tv" : "light"
                    let available = world.spots.filter { rooms.contains(world.nodes[$0.node].room) && (pet.homeRoom == nil || world.nodes[$0.node].room == pet.homeRoom) }
                        .filter { targetKind == "sleep" ? ["sleep", "perch"].contains($0.kind) : $0.kind == targetKind && (targetKind == "tv" ? context.tvRooms.contains(world.nodes[$0.node].room) : world.nodes[$0.node].room == room) }
                        .sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority < $1.priority }
                    var target = available.first(where: { !world.path(from: start.node, to: $0.node, room: pet.homeRoom, allowedRooms: rooms).isEmpty }) ?? start.rest
                    var distinct: [HousePetWorld.Spot] = []
                    if targetKind == "sleep" && roster.count > 1 {
                        let reachable = available.filter { !world.path(from: start.node, to: $0.node, room: pet.homeRoom, allowedRooms: rooms).isEmpty }
                            .sorted {
                                let leftDark = context.lights[world.nodes[$0.node].room] != true, rightDark = context.lights[world.nodes[$1.node].room] != true
                                if leftDark != rightDark { return leftDark }
                                return $0.priority == $1.priority ? $0.id < $1.id : $0.priority < $1.priority
                            }
                        for cells in [5.0, 3.0] {
                            distinct = []
                            for candidate in reachable where distinct.allSatisfy({ $0.point.distance(to: candidate.point) >= cells * world.cellSize - 0.001 }) {
                                distinct.append(candidate)
                            }
                            if distinct.count >= roster.count { break }
                        }
                    }
                    if distinct.count >= roster.count { target = distinct[rank] }
                    else if roster.count > 1 {
                        let near = world.nodes.filter { rooms.contains($0.room) && (pet.homeRoom == nil || $0.room == pet.homeRoom) }
                            .sorted { $0.point.distance(to: target.point) == $1.point.distance(to: target.point) ? $0.id < $1.id : $0.point.distance(to: target.point) < $1.point.distance(to: target.point) }
                        var candidates = [target]
                        for node in near where node.room == world.nodes[target.node].room && !world.path(from: target.node, to: node.id, room: pet.homeRoom, allowedRooms: rooms).isEmpty {
                            candidates.append(.init(id: target.id, kind: target.kind, node: node.id, point: node.point, facing: target.facing, priority: target.priority))
                        }
                        let separated = Self.separatedSpots(candidates, count: roster.count, cellSize: world.cellSize)
                        if separated.indices.contains(rank) { target = separated[rank] }
                    }
                    let path = world.path(from: start.node, to: target.node, room: pet.homeRoom, allowedRooms: rooms)
                    var segments: [Segment] = [], time = startTime
                    func append(_ from: HousePetPoint, _ to: HousePetPoint, _ node: Int, _ facing: String, _ action: String, _ duration: Double) {
                        segments.append(.init(start: time, duration: duration, from: from, to: to, node: node, facing: facing, action: action, rest: target)); time += duration
                    }
                    let progress = min(1, max(0, (startTime - start.start) / start.duration))
                    let point = HousePetPoint(x: start.from.x + (start.to.x - start.from.x) * progress, y: start.from.y + (start.to.y - start.from.y) * progress)
                    if light && !nightSleep && !tv { append(point, point, start.node, start.facing, "lookup", 2) }
                    if !path.isEmpty {
                        Self.travel(path: path, from: point, target: target, world: world, append: append)
                    } else { target = start.rest }
                    append(target.point, target.point, target.node, target.facing, nightSleep ? "sleep" : "sit", 200000)
                    reaction = .init(segments: segments); plans[reactionKey] = reaction
                }
                selected = segment(reaction, elapsed)
            }
        }
        if context.restOnly {
            selected.from = selected.rest.point; selected.to = selected.rest.point; selected.node = selected.rest.node
            if !["idle", "sit", "sleep"].contains(selected.action) { selected.action = "sit" }
            selected.facing = selected.rest.facing
        }
        localTime = max(0, elapsed - selected.start)
        let progress = min(1, localTime / max(0.001, selected.duration)), node = world.nodes[selected.node]
        let frame = rig.frame(action: selected.action, facing: selected.facing, elapsed: localTime)
        return .init(point: .init(x: selected.from.x + (selected.to.x - selected.from.x) * progress, y: selected.from.y + (selected.to.y - selected.from.y) * progress),
                     facing: selected.facing, action: selected.action, frameIndex: frame.index, mirrored: frame.mirrored,
                     jumpLift: selected.action == "jump" ? 4 * 28 * progress * (1 - progress) : 0, module: node.module, room: node.room,
                     visible: pet.enabled && !pet.deleted && context.enabled)
    }

    static func separatedSpots(_ candidates: [HousePetWorld.Spot], count: Int, cellSize: Double) -> [HousePetWorld.Spot] {
        var selected: [HousePetWorld.Spot] = []
        for cells in [5.0, 3.0, 2.0, 1.0] {
            selected = []
            for candidate in candidates where selected.allSatisfy({ $0.point.distance(to: candidate.point) >= cellSize * cells - 0.001 }) {
                selected.append(candidate)
            }
            if selected.count >= count { break }
        }
        return selected
    }

    private static func travel(path: [Int], from start: HousePetPoint, target: HousePetWorld.Spot, world: HousePetWorld,
                               append: (HousePetPoint, HousePetPoint, Int, String, String, Double) -> Void) {
        guard let first = path.first else { return }
        var current = start
        func move(to point: HousePetPoint, node: Int, jump: Bool, facing: String) {
            let distance = current.distance(to: point)
            if distance > 0.01 { append(current, point, node, facing, jump ? "jump" : "walk", jump ? 0.5 : distance / 36) }; current = point
        }
        move(to: world.nodes[first].point, node: first, jump: abs(start.y - world.nodes[first].point.y) > 24, facing: target.facing)
        for (left, right) in zip(path, path.dropFirst()) {
            let from = world.nodes[left], to = world.nodes[right]
            let facing = to.u > from.u ? "SE" : to.u < from.u ? "NW" : to.v > from.v ? "SW" : "NE"
            move(to: to.point, node: right, jump: world.edges[left].contains { $0.node == right && $0.jump }, facing: facing)
        }
        move(to: target.point, node: target.node, jump: abs(target.point.y - world.nodes[target.node].point.y) > 24, facing: target.facing)
    }
}
