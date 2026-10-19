import Foundation
import MijiaCore

enum HouseDecorFiles {
    static var roots: [URL] {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent()
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("MijiaBar/House")
        var roots = [support, repo.appendingPathComponent("assets/house"), repo.appendingPathComponent("Sources/MijiaBarApp/Resources/House")]
        for parent in [Bundle.main.resourceURL, Optional(executable), Optional(executable.appendingPathComponent("../Resources").standardizedFileURL)] {
            guard let parent else { continue }
            roots += [parent.appendingPathComponent("House"), parent]
            let bundles = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
            for bundle in bundles where bundle.lastPathComponent == "MijiaBar_MijiaBarApp.bundle" {
                for path in ["", "Contents/Resources"] { roots += [bundle.appendingPathComponent(path), bundle.appendingPathComponent(path + "/House")] }
            }
        }
        return roots
    }
    static func items() -> HouseDecorCatalog? {
        for root in roots {
            for path in ["decor/decor-catalog.json", "decor-catalog.json"] {
                if let catalog = try? HouseDecorCatalog.load(from: root.appendingPathComponent(path)) { return catalog }
            }
        }
        return nil
    }
    static func modules(style: String?) -> HouseModuleCatalog? {
        let id = HouseStyles.resolve(style), own = HouseStyles.info(id).hasOwnCatalog
        for root in roots {
            let paths = own ? ["styles/\(id)/modules/catalog.json"] : ["modules/catalog.json", "catalog.json"]
            for path in paths {
                if let catalog = try? HouseComposer.loadCatalog(from: root.appendingPathComponent(path)) { return catalog }
            }
        }
        return nil
    }
}

@MainActor func houseDecor(pos: [String], rest: [String]) async throws -> [String: Any] {
    do { return try await houseDecorOperation(pos: pos, rest: rest) }
    catch { return ["ok": false, "error": error.localizedDescription] }
}

@MainActor private func houseDecorOperation(pos: [String], rest: [String]) async throws -> [String: Any] {
    let sub = pos.first ?? "list", items = HouseDecorFiles.items()
    if sub == "items" {
        guard let items else { return ["ok": false, "error": L("找不到装饰目录", "Decor catalog not found")] }
        return ["ok": true, "catalog": try JSONSerialization.jsonObject(with: JSONEncoder().encode(items))]
    }
    let file = HouseStore.load(), requestedHome = opt(rest, "--home")
    let home: (id: String, name: String)
    if let requestedHome, file.homes[requestedHome] != nil { home = (requestedHome, requestedHome) }
    else { home = try await houseHome(requestedHome) }
    let config = file.homes[home.id] ?? HomeHouse()
    let modules = HouseDecorFiles.modules(style: config.style)
    let layout: [HouseLayoutCell]
    if let cells = config.layout { layout = cells }
    else if !HouseStyles.info(config.style).hasClassicArt {
        let rooms = try await houseResolved(home: home.id).rooms
        layout = HouseLayoutSolver.classicFour.map { cell in
            .init(room: rooms.first { $0.module.rawValue == cell.module }?.key ?? cell.module, module: cell.module, col: cell.col, row: cell.row, level: 0)
        }
    } else { layout = [] }
    func error(_ message: String) -> [String: Any] { ["ok": false, "error": message] }
    switch sub {
    case "set":
        guard pos.count == 3 else { return error(L("需要 room/slot 和 item|none|auto", "Expected room/slot and item|none|auto")) }
        let key = pos[1], itemID = pos[2]
        guard let slot = layout.lazy.compactMap({ cell in
            modules?.modules[cell.module]?.decor?.first { "\(HouseDecor.roomKey(cell))/\($0.id)" == key }
        }).first else {
            return error(L("找不到装饰位置：", "Decor slot not found: ") + key)
        }
        if !["none", "auto"].contains(itemID) {
            guard let item = items?.items.first(where: { $0.id == itemID }), item.fits(slot) else {
                return error(L("装饰不存在或不适合位置：", "Unknown item or incompatible slot: ") + itemID)
            }
        }
        try HouseStore.update { $0.setDecor(home: home.id, key: key, item: itemID) }
        return ["ok": true, "home": home.id, "slot": key, "item": itemID]
    case "on", "off":
        try HouseStore.update { $0.setDecorPrefs(home: home.id, enabled: sub == "on") }
        return ["ok": true, "enabled": sub == "on"]
    case "seasonal":
        guard pos.count == 2, ["on", "off"].contains(pos[1]) else { return error(L("需要 on 或 off", "Expected on or off")) }
        try HouseStore.update { $0.setDecorPrefs(home: home.id, seasonal: pos[1] == "on") }
        return ["ok": true, "seasonal": pos[1] == "on"]
    case "reset":
        try HouseStore.update { $0.resetDecor(home: home.id) }
        return ["ok": true, "home": home.id]
    case "list": break
    default: return error(L("未知装饰命令：", "Unknown decor command: ") + sub)
    }
    let prefs = config.decorPrefs ?? HouseDecorPrefs(), now = Date(), filter = opt(rest, "--room")
    let placements = items.flatMap { items in modules.map { HouseDecor.resolve(layout: layout, catalog: $0, overrides: config.decor ?? [:], prefs: prefs, date: now, items: items, includeHidden: true) } } ?? []
    let hidden = modules.map { HouseDecor.hiddenSlots(layout: layout, catalog: $0) } ?? []
    var slots: [[String: Any]] = []
    for cell in layout where filter == nil || filter == HouseDecor.roomKey(cell) {
        for slot in modules?.modules[cell.module]?.decor ?? [] {
            let room = HouseDecor.roomKey(cell), key = "\(room)/\(slot.id)"
            let placement = placements.first { $0.room == room && $0.slot == slot.id }
            var record: [String: Any] = ["room": room, "slot": slot.id, "surface": slot.surface, "sizes": slot.sizes,
                                         "wall": slot.wall as Any? ?? NSNull(), "item": placement?.item as Any? ?? NSNull(),
                                         "source": placement?.source.rawValue as Any? ?? NSNull()]
            if hidden.contains(key) { record["hidden"] = "wall cut" }
            slots.append(record)
        }
    }
    let overrides = (config.decor ?? [:]).filter { filter == nil || $0.key.hasPrefix(filter! + "/") }
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    return ["ok": true, "home": home.id, "slots": slots, "prefs": try JSONSerialization.jsonObject(with: encoder.encode(prefs)),
            "activeSeasons": items.map { HouseSeasons.activeSeasons(on: now, seasons: $0.seasons) } ?? [],
            "overrides": try JSONSerialization.jsonObject(with: encoder.encode(overrides)),
            "catalogAvailable": modules != nil, "itemsAvailable": items != nil]
}
