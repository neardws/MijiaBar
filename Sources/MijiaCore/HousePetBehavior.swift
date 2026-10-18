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
    private struct Plan { var segments: [Segment] }
    private let rig: HousePetRig
    private let lock = NSLock()
    private var plans: [String: Plan] = [:]
    private var retainedWorlds: [ObjectIdentifier: HousePetWorld] = [:]
    public init(rig: HousePetRig) { self.rig = rig }

    private static func seed(_ text: String) -> UInt64 {
        text.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    public func pose(_ pet: HousePet, world: HousePetWorld, context: HousePetContext = .init(), at date: Date) -> HousePetPose {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = context.timeZone
        let day = calendar.startOfDay(for: date), elapsed = max(0, date.timeIntervalSince(day))
        let rooms = context.rooms.isEmpty ? world.rooms : context.rooms
        guard let first = world.nodes.first(where: { rooms.contains($0.room) && (pet.homeRoom == nil || $0.room == pet.homeRoom) }) else {
            return .init(point: .init(x: 0, y: 0), facing: "SE", action: "idle", frameIndex: 0, mirrored: false, jumpLift: 0, module: "", room: "", visible: false)
        }
        let roster = Array(Set(context.petIDs + [pet.id])).sorted(), rank = roster.firstIndex(of: pet.id) ?? 0
        let identity = ObjectIdentifier(world)
        let key = "\(identity)|\(pet.id)|\(pet.homeRoom ?? "*")|\(day.timeIntervalSince1970)|\(context.timeZone.identifier)|" + rooms.sorted().joined(separator: ",") + "|" + roster.joined(separator: ",")
        lock.lock(); defer { lock.unlock() }
        if plans.count > 24 { plans.removeAll(); retainedWorlds.removeAll() }
        retainedWorlds[identity] = world
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
            var state = Self.seed("\(calendar.component(.year, from: day))-\(calendar.component(.month, from: day))-\(calendar.component(.day, from: day))|\(pet.id)")
            func random(_ count: Int) -> Int { state = state &* 6364136223846793005 &+ 1442695040888963407; return Int((state >> 32) % UInt64(max(1, count))) }
            var segments: [Segment] = [], time = 0.0, current = spots[random(spots.count)]
            func append(_ from: HousePetPoint, _ to: HousePetPoint, _ node: Int, _ facing: String, _ action: String, _ duration: Double, rest: HousePetWorld.Spot) {
                segments.append(.init(start: time, duration: duration, from: from, to: to, node: node, facing: facing, action: action, rest: rest)); time += duration
            }
            while time < 90000 {
                let action = ["idle", "sit", "groom", "lookup", "stretch", "sleep"][random(6)]
                append(current.point, current.point, current.node, current.facing, action, Double(8 + random(53)), rest: current)
                let next = spots[random(spots.count)], path = world.path(from: current.node, to: next.node, room: pet.homeRoom, allowedRooms: rooms)
                guard !path.isEmpty else { continue }
                Self.travel(path: path, from: current.point, target: next, world: world) { from, to, node, facing, action, duration in
                    append(from, to, node, facing, action, duration, rest: next)
                }
                current = next
            }
            return .init(segments: segments)
        }
        let base: Plan
        if let cached = plans[key] { base = cached } else { base = build(); plans[key] = base }
        func segment(_ plan: Plan, _ elapsed: Double) -> Segment {
            var low = 0, high = plan.segments.count
            while low < high { let middle = (low + high) / 2; if plan.segments[middle].start <= elapsed { low = middle + 1 } else { high = middle } }
            return plan.segments[max(0, low - 1)]
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
                    if roster.count > 1 {
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
        for cells in [3.0, 2.0, 1.0] {
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
