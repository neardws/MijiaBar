import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import MijiaCore

enum HousePetFiles {
    static func rig(_ id: String = "cat-short") throws -> (HousePetRig, URL) {
        guard HousePetRig.supported[id] != nil else { throw HousePetError.invalid }
        for root in HouseDecorFiles.roots {
            for path in ["pets", ""] {
                let directory = root.appendingPathComponent(path)
                if let rig = try? HousePetRig.load(from: directory.appendingPathComponent(id + ".json")), rig.id == id { return (rig, directory) }
            }
        }
        throw HousePetError.resource
    }
}

func housePetArguments(_ args: [String]) throws -> [String] {
    let flags = ["--home", "--photo", "--name", "--species", "--rig", "--pattern", "--palette", "--room", "--enabled", "--out", "--action", "--phase"]
    var positionals: [String] = [], seen = Set<String>(), index = 0
    while index < args.count {
        let argument = args[index]
        if argument == "--json" { index += 1; continue }
        if flags.contains(argument) {
            guard seen.insert(argument).inserted, index + 1 < args.count, !args[index + 1].hasPrefix("--") else { throw HousePetError.invalid }
            index += 2
        } else {
            guard !argument.hasPrefix("--") else { throw HousePetError.invalid }
            positionals.append(argument); index += 1
        }
    }
    let operation = positionals.first ?? "list"
    let allowed: Set<String>
    switch operation {
    case "list", "on", "off": allowed = ["--home"]
    case "add": allowed = ["--home", "--photo", "--name", "--species", "--rig", "--pattern", "--palette", "--room", "--enabled"]
    case "set": allowed = ["--home", "--photo", "--name", "--species", "--rig", "--pattern", "--palette", "--room", "--enabled"]
    case "remove": allowed = ["--home"]
    case "preview": allowed = ["--home", "--out", "--action", "--phase"]
    case "analyze": allowed = []
    default: throw HousePetError.invalid
    }
    guard seen.isSubset(of: allowed), positionals.count == (["set", "remove", "preview", "analyze"].contains(operation) ? 2 : 1) || positionals.isEmpty else { throw HousePetError.invalid }
    return positionals.isEmpty ? ["list"] : positionals
}

func housePetJSON<T: Encodable>(_ value: T) throws -> Any {
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    return try JSONSerialization.jsonObject(with: encoder.encode(value))
}

func housePetDiagnosticsText(_ diagnostics: [String: Any]) -> String {
    let data = try? JSONSerialization.data(withJSONObject: diagnostics, options: [.sortedKeys])
    return "diagnostics: " + (data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
}

func housePetPreview(pet: HousePet, rig: HousePetRig, directory: URL, output: URL, action: String? = nil, phase: String = "day") throws -> Int {
    guard action == nil || rig.actions[action!] != nil else { throw HousePetError.invalid }
    let frames = try HousePetFrameCache().frames(pet: pet, rig: rig, directory: directory, phase: phase)
    let indices = action.flatMap { rig.actions[$0] }.map { animation in animation.frames.keys.sorted().flatMap { animation.frames[$0] ?? [] } } ?? Array(frames.indices)
    let columns = min(rig.columns, indices.count), rows = (indices.count + columns - 1) / columns
    let width = rig.frameSize[0] * rig.cellPx, height = rig.frameSize[1] * rig.cellPx
    guard let context = CGContext(data: nil, width: columns * width, height: rows * height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw HousePetError.resource }
    context.interpolationQuality = .none
    for (index, frame) in indices.enumerated() {
        context.draw(frames[frame], in: CGRect(x: index % columns * width, y: (rows - 1 - index / columns) * height, width: width, height: height))
    }
    guard let image = context.makeImage(), let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw HousePetError.invalid }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw HousePetError.invalid }
    return indices.count
}

@MainActor func housePets(pos: [String], rest: [String]) async throws -> [String: Any] {
    guard policy.canRead else { throw MijiaError.denied("disabled") }
    do { return try await housePetsOperation(pos: pos, rest: rest) }
    catch { return ["ok": false, "error": error.localizedDescription] }
}

@MainActor private func housePetsOperation(pos: [String], rest: [String]) async throws -> [String: Any] {
    let operation = pos.first ?? "list"
    guard ["list", "add", "set", "remove", "preview", "analyze", "on", "off"].contains(operation),
          pos.count == (["set", "remove", "preview", "analyze"].contains(operation) ? 2 : 1) || pos.isEmpty else { throw HousePetError.invalid }
    if operation == "analyze" {
        let result = try HousePetPhoto.load(from: URL(fileURLWithPath: pos[1]))
        return ["ok": true, "analysis": try housePetJSON(result)]
    }
    let file = HouseStore.load(), requested = opt(rest, "--home")
    let home: String
    if let requested, file.homes[requested] != nil { home = requested }
    else { home = try await houseHome(requested).id }
    let config = file.homes[home] ?? HomeHouse()
    let pets = (config.pets ?? [:]).values.filter { !$0.deleted }.sorted { $0.id < $1.id }
    func resolve(_ config: HomeHouse, query: String) throws -> HousePet {
        let values = (config.pets ?? [:]).values.filter { !$0.deleted }
        if let exact = values.first(where: { $0.id == query }) { return exact }
        let matches = values.filter { $0.name == query }
        guard matches.count == 1 else { throw HousePetError.invalid }; return matches[0]
    }
    if operation == "list" {
        let rig = try HousePetFiles.rig().0
        return ["ok": true, "home": home, "pets": try housePetJSON(pets), "prefs": try housePetJSON(config.petPrefs ?? .init()),
                "patterns": HousePetRig.allPatterns, "rigs": HousePetRig.supported.keys.sorted(), "species": ["cat", "dog"],
                "actions": rig.actions.keys.sorted(), "limit": HouseFile.petLimit]
    }
    if operation == "on" || operation == "off" {
        try HouseStore.update { $0.setPetPrefs(home: home, enabled: operation == "on") }
        return ["ok": true, "enabled": operation == "on"]
    }
    if operation == "preview" {
        guard let output = opt(rest, "--out"), !output.isEmpty else { throw HousePetError.invalid }
        let pet = try resolve(config, query: pos[1]), (rig, directory) = try HousePetFiles.rig(pet.rig)
        let phase = opt(rest, "--phase") ?? "day", action = opt(rest, "--action")
        let count = try housePetPreview(pet: pet, rig: rig, directory: directory, output: URL(fileURLWithPath: output), action: action, phase: phase)
        return ["ok": true, "out": output, "frames": count]
    }
    var pet = operation == "add" ? HousePet() : try resolve(config, query: pos[1])
    var detected: HousePetPhoto.Result?
    if let photo = opt(rest, "--photo") {
        detected = try HousePetPhoto.load(from: URL(fileURLWithPath: photo))
        pet.palette = detected!.palette; pet.pattern = detected!.pattern
        if operation == "add" {
            let appearance = detected!.pet(); pet.species = appearance.species; pet.rig = appearance.rig
        }
    }
    if let species = opt(rest, "--species") { pet.species = species; pet.rig = species + "-short" }
    if let rig = opt(rest, "--rig") { pet.rig = rig }
    if let name = opt(rest, "--name") { pet.name = name }
    if let pattern = opt(rest, "--pattern") { pet.pattern = pattern }
    if let palette = opt(rest, "--palette") {
        var keys = Set<String>()
        for field in palette.split(separator: ",", omittingEmptySubsequences: false) {
            let pair = field.split(separator: "=", omittingEmptySubsequences: false)
            guard pair.count == 2, keys.insert(String(pair[0])).inserted else { throw HousePetError.invalid }
            switch pair[0] {
            case "base": pet.palette.base = String(pair[1])
            case "second": pet.palette.second = String(pair[1])
            case "white": pet.palette.white = String(pair[1])
            case "eye": pet.palette.eye = String(pair[1])
            default: throw HousePetError.invalid
            }
        }
    }
    if let room = opt(rest, "--room") {
        if ["auto", "null", ""].contains(room) { pet.homeRoom = nil }
        else {
            let homeDevices = config.layout == nil ? try await devices().filter { $0.homeId == home } : []
            let effective = HouseAutoLayout.effective(devices: homeDevices, config: config, isHidden: prefs.isHidden)
            if effective?.contains(where: { HouseDecor.roomKey($0) == room }) == true { pet.homeRoom = room }
            else {
                let rooms = try await houseResolved(home: home).rooms
                guard let match = rooms.first(where: { $0.key == room || $0.title == room }) else { throw HousePetError.invalid }
                pet.homeRoom = match.key
            }
        }
    }
    if let enabled = opt(rest, "--enabled") {
        guard ["true", "false"].contains(enabled) else { throw HousePetError.invalid }; pet.enabled = enabled == "true"
    }
    pet.deleted = operation == "remove"; pet.updatedAt = Date()
    let updated = pet
    try HouseStore.update { current in
        if operation != "add" {
            let latest = try resolve(current.homes[home] ?? .init(), query: updated.id)
            guard latest.updatedAt == (config.pets?[updated.id]?.updatedAt) else { throw HousePetError.invalid }
        } else if current.homes[home]?.pets?[updated.id] != nil { throw HousePetError.invalid }
        try current.setPet(home: home, pet: updated)
    }
    var result: [String: Any] = ["ok": true, "home": home, "pet": try housePetJSON(pet)]
    if let detected { result["detected"] = try housePetJSON(detected) }
    return result
}
