import Foundation
import Testing
@testable import MijiaCore

@Suite struct HousePetDeterminismTests {
    private struct Fingerprint {
        var value: UInt64 = 14695981039346656037
        mutating func add(_ number: UInt64) {
            for shift in stride(from: 0, to: 64, by: 8) { value = (value ^ ((number >> shift) & 255)) &* 1099511628211 }
        }
        mutating func add(_ text: String) {
            add(UInt64(text.utf8.count))
            for byte in text.utf8 { value = (value ^ UInt64(byte)) &* 1099511628211 }
        }
        mutating func add(_ pose: HousePetPose) {
            add(pose.point.x.bitPattern); add(pose.point.y.bitPattern)
            add(pose.facing); add(pose.action); add(UInt64(pose.frameIndex))
            add(pose.mirrored ? 1 : 0); add(pose.jumpLift.bitPattern)
            add(pose.module); add(pose.room); add(pose.visible ? 1 : 0)
        }
    }

    @Test func performanceScheduleFingerprint() throws {
        let world = try HousePetTests.world(), behavior = HousePetBehavior(rig: try HousePetTests.rig())
        let date = Date(timeIntervalSince1970: 1792270000), pets = (0..<3).map { HousePet(id: "p_123\($0)") }
        let context = HousePetContext(petIDs: pets.map(\.id), timeZone: TimeZone(secondsFromGMT: 0)!)
        var fingerprint = Fingerprint()
        for index in 0..<1000 {
            fingerprint.add(behavior.pose(pets[index % 3], world: world, context: context, at: date.addingTimeInterval(Double(index))))
        }
        #expect(fingerprint.value == 787020977557581161)
    }

    @Test func calendarReactionsAndBatchFingerprint() throws {
        let world = try HousePetTests.world(level: 1), behavior = HousePetBehavior(rig: try HousePetTests.rig())
        let pets = [HousePet(id: "p_1234", homeRoom: "a"), HousePet(id: "p_5678", homeRoom: "a")]
        var fingerprint = Fingerprint()
        for zone in ["UTC", "Asia/Shanghai", "America/New_York"] {
            let timeZone = try #require(TimeZone(identifier: zone))
            for timestamp in [1793512800.0, 1772953200, 1792270000] {
                let date = Date(timeIntervalSince1970: timestamp)
                let base = HousePetContext(rooms: ["a"], petIDs: pets.map(\.id), timeZone: timeZone)
                var night = base; night.night = true; night.changedAt = date
                var tv = base; tv.tvRooms = ["a"]; tv.changedAt = date
                var light = base; light.lights = ["a": true]; light.changedAt = date; light.changedRoom = "a"
                var rest = night; rest.restOnly = true
                var disabled = base; disabled.enabled = false
                for context in [base, night, tv, light, rest, disabled] {
                    for offset in [600.0, 0, 1, 0.125, 2, 10, -1, 3600, 300, 7200] {
                        let time = date.addingTimeInterval(offset)
                        for pet in pets { fingerprint.add(behavior.pose(pet, world: world, context: context, at: time)) }
                        var permuted = context; permuted.petIDs = [pets[1].id, pets[0].id, pets[1].id]
                        let batch = behavior.poses(Array(pets.reversed()), world: world, context: permuted, at: time)
                        for pet in pets { fingerprint.add(try #require(batch[pet.id])) }
                    }
                }
                let override = behavior.pose(pets[0], world: world, context: rest, at: date)
                let batch = behavior.poses(pets, world: world, context: rest, at: date, overrides: [pets[1].id: override])
                for pet in pets { fingerprint.add(try #require(batch[pet.id])) }
            }
        }
        fingerprint.add(behavior.pose(.init(id: "missing", homeRoom: "missing"), world: world, at: .init(timeIntervalSince1970: 0)))
        #expect(fingerprint.value == 17687512416024509852)
    }

    @Test func concurrentScheduleFingerprint() async throws {
        let world = try HousePetTests.world(), behavior = HousePetBehavior(rig: try HousePetTests.rig())
        let date = Date(timeIntervalSince1970: 1792270000), pets = (0..<3).map { HousePet(id: "p_123\($0)") }
        let context = HousePetContext(petIDs: pets.map(\.id), timeZone: TimeZone(secondsFromGMT: 0)!)
        let results = await withTaskGroup(of: [(Int, HousePetPose)].self) { group in
            for worker in 0..<8 {
                group.addTask {
                    stride(from: worker, to: 1000, by: 8).map { index in
                        (index, behavior.pose(pets[index % 3], world: world, context: context, at: date.addingTimeInterval(Double(index))))
                    }
                }
            }
            var results: [(Int, HousePetPose)] = []
            for await batch in group { results += batch }
            return results.sorted { $0.0 < $1.0 }
        }
        var fingerprint = Fingerprint()
        for (_, pose) in results { fingerprint.add(pose) }
        #expect(fingerprint.value == 787020977557581161)
    }

    @Test func pathFingerprint() throws {
        var fingerprint = Fingerprint()
        for level in [0, 1] {
            let world = try HousePetTests.world(level: level)
            for from in stride(from: 0, to: world.nodes.count, by: 3) {
                for sample in 0..<4 {
                    let to = (from * 31 + sample * 47) % world.nodes.count
                    for restriction in 0..<3 {
                        let path = world.path(from: from, to: to, room: restriction == 1 ? world.nodes[from].room : nil,
                                              allowedRooms: restriction == 2 ? ["a", "b", "c"] : nil)
                        fingerprint.add(UInt64(from)); fingerprint.add(UInt64(to)); fingerprint.add(UInt64(path.count))
                        for node in path { fingerprint.add(UInt64(node)) }
                    }
                }
            }
        }
        #expect(fingerprint.value == 5314581484295840740)
    }
}
