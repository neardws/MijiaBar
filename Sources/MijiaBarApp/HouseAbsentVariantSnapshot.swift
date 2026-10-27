import AppKit
import MijiaCore
import SwiftUI

extension Snapshot {
    static func absentVariantRooms(_ rooms: [HouseRoom], absent: Bool) -> [HouseRoom] {
        rooms.map { room in
            var room = room
            let fixtures: [String]
            switch room.module {
            case .living: fixtures = ["tv", "ac"]
            case .bedroom: fixtures = ["ac"]
            case .study: fixtures = ["monitor"]
            default: fixtures = []
            }
            for fixture in fixtures where !room.devices.contains(where: { $0.spot == .fixture(fixture) }) {
                room.devices.append(HouseDevice(did: "absent-demo-\(room.module.rawValue)-\(fixture)", name: room.title,
                                                category: fixture == "ac" ? .ac : .tv, spot: .fixture(fixture),
                                                on: false, online: true, toggleable: true))
            }
            room.devices = room.devices.map { device in
                guard case .fixture(let fixture)? = device.spot, fixtures.contains(fixture) else { return device }
                return HouseDevice(did: device.did, name: device.name, category: device.category,
                                   spot: absent ? nil : device.spot, on: false, online: device.online,
                                   toggleable: device.toggleable, level: device.level, busy: device.busy)
            }
            room.lighting = .from(room.devices)
            return room
        }
    }

    static func houseAbsentVariant(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir)
        do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        catch { print("Cannot create snapshot directory: \(error)"); exit(1) }
        let model = AppModel(mock: true)
        let rooms = model.houseRooms
        let positions: [HouseModule: (Int, Int)] = [.living: (0, 0), .bedroom: (0, 1), .study: (2, 0)]
        let layout = rooms.compactMap { room -> HouseLayoutCell? in
            guard let position = positions[room.module] else { return nil }
            return HouseLayoutCell(room: room.key, module: room.module.rawValue, col: position.0, row: position.1, level: 0)
        }
        for (name, cells) in [("classic", Optional<[HouseLayoutCell]>.none), ("composed", Optional(layout))] {
            for phase in [HousePhase.day, .night] {
                guard let source = HouseSceneSource.make(layout: cells, phase: phase, style: "cozy-wood") else {
                    print("Missing \(name) \(phase.assetName) scene"); exit(1)
                }
                for absent in [false, true] {
                    let file = out.appendingPathComponent("\(name)-\(phase.assetName)-\(absent ? "absent" : "present").png")
                    render(HouseCutawaySceneView(rooms: absentVariantRooms(rooms, absent: absent), phase: phase,
                                                showLabels: false, layout: cells, style: "cozy-wood"), file, size: source.artSize)
                    guard FileManager.default.fileExists(atPath: file.path) else { exit(1) }
                }
            }
        }
        exit(0)
    }
}
