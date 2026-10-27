import Foundation
import MijiaCore

func houseDecorArguments(_ arguments: [String]) throws -> [String] {
    var result: [String] = [], seen = Set<String>(), index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "--json" { index += 1; continue }
        if argument.hasPrefix("--") {
            guard ["--home", "--room", "--cell", "--id"].contains(argument), seen.insert(argument).inserted,
                  index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                throw NSError(domain: "HouseDecor", code: 1, userInfo: [NSLocalizedDescriptionKey: L("装饰参数无效", "Invalid decor arguments")])
            }
            index += 2
        } else { result.append(argument); index += 1 }
    }
    return result.isEmpty ? ["list"] : result
}

func houseFreeDecorList(config: HomeHouse, placements: [HouseDecorPlacement], room filter: String? = nil) -> [[String: Any]] {
    (config.freeDecor ?? [:]).keys.sorted().compactMap { key in
        guard let entry = config.freeDecor?[key], let item = entry.item, filter == nil || filter == HouseFreeDecor.room(of: key) else { return nil }
        let placement = placements.first { $0.room == HouseFreeDecor.room(of: key) && $0.slot == "free:" + HouseFreeDecor.id(of: key) }
        var record: [String: Any] = ["key": key, "room": HouseFreeDecor.room(of: key), "item": item, "cell": entry.cell, "at": placement?.at as Any? ?? NSNull()]
        if placement == nil { record["hidden"] = (config.decorPrefs?.enabled ?? true) ? "invalid" : "disabled" }
        return record
    }
}

func houseFreeDecorEdit(action: String, target: String, item: String?, cell: [Int], id: String?, home: String,
                        file: inout HouseFile, layout: [HouseLayoutCell], modules: HouseModuleCatalog?, items: HouseDecorCatalog?,
                        spots: HousePetSpots?) -> [String: Any] {
    let config = file.homes[home] ?? HomeHouse(), entries = config.freeDecor ?? [:]
    let room = action == "place" ? target : HouseFreeDecor.room(of: target)
    let identifier = action == "place" ? (id ?? HouseFreeDecor.nextID(room: room, entries: entries)) : HouseFreeDecor.id(of: target)
    let key = room + "/" + identifier
    func failure(_ reason: HouseFreeDecor.Reason) -> [String: Any] { ["ok": false, "reason": reason.rawValue, "error": reason.message] }
    guard !identifier.isEmpty, identifier.count <= 32, identifier.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
        return ["ok": false, "reason": "invalidID", "error": L("标识只允许短字母数字、连字符和下划线", "Use a short ASCII identifier with letters, digits, hyphens or underscores")]
    }
    if action == "remove" {
        guard let entry = entries[key], entry.item != nil else { return failure(.unknownItem) }
        file.setFreeDecor(home: home, key: key, item: nil, cell: entry.cell)
        return ["ok": true, "key": key, "item": NSNull(), "cell": entry.cell]
    }
    guard action == "place" || action == "move" else { return ["ok": false, "error": L("需要 place、move 或 remove", "Expected place, move or remove")] }
    if action == "place", entries[key]?.item != nil { return failure(.occupied) }
    guard let item = action == "move" ? entries[key]?.item : item else { return failure(.unknownItem) }
    guard let modules, let items, let spots else { return failure(.unknownRoom) }
    let grids = HouseFreeDecor.grids(layout: layout, catalog: modules, spots: spots, style: config.style)
    let fixed = HouseDecor.resolve(layout: layout, catalog: modules, overrides: config.decor ?? [:], prefs: .init(seasonal: config.decorPrefs?.seasonal ?? true), items: items)
    if let reason = HouseFreeDecor.validate(room: room, item: item, cell: cell, grids: grids, items: items, entries: entries,
                                          excluding: action == "move" ? key : nil, fixed: fixed) { return failure(reason) }
    file.setFreeDecor(home: home, key: key, item: item, cell: cell)
    return ["ok": true, "home": home, "key": key, "item": item, "cell": cell]
}
