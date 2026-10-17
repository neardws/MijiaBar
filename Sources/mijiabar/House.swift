import Foundation
import MijiaCore

// mijiabar house …：读写小屋配置（house.json，格式见 docs/HOUSE.md）。
// 只改小屋怎么摆、不控制设备，所以只要 Agent 接口没关（mode != disabled）就能改；不弹确认框。

let houseUsage = """
用法:
  mijiabar house show [--home H] [--json]           当前小屋：每个房间放了哪些设备、哪些房间 / 设备没进小屋
  mijiabar house slots [--json]                     模块目录：每个模块的灯具位 id、接受的设备类型、徽章位
  mijiabar house hide <设备>                         小屋里不显示这台设备（列表不受影响）
  mijiabar house unhide <设备>                       小屋里显示（即使列表里隐藏了）
  mijiabar house assign <设备> <位置>                位置 = 灯具位 id（如 floor_lamp）| badge | badge:b2 | none | auto
  mijiabar house set <设备> [--visible true|false|auto] [--place <位置>]
  mijiabar house room <房间> <模块>                   模块 = living | bedroom | study | kitchen | bathroom | balcony | generic | none | auto
  mijiabar house layout [--json]                     当前格子布局（nil = 经典四室 / 自动）
  mijiabar house layout set <房间:模块:col:row> ...   设置布局，例如 living室:living:0:1 bedroom室:bedroom:0:0
  mijiabar house layout auto [--home H]              按设备数自动填 3×2
  mijiabar house layout classic [--home H]           恢复经典四室几何（清掉 layout 覆盖，走整图）
  mijiabar house reset [<设备> | --room <房间> | --layout] [--home H]   恢复自动
  mijiabar house sync [icloud | local | <文件夹>]    查看 / 切换 house.json 的存放位置（默认 iCloud Drive，多台 Mac 同步）
  mijiabar house schema                             打印 house.json 的 JSON Schema
设备 = did 或名称；房间 = 米家房间 id 或名称；--json 输出机器可读结果（修改类命令总是输出 JSON）。
"""

@MainActor func houseHomes() async throws -> [(id: String, name: String)] {
    let ds = try await devices()
    var out: [(String, String)] = []
    for d in ds where !out.contains(where: { $0.0 == d.homeId }) { out.append((d.homeId, d.homeName)) }
    return out
}

@MainActor func houseHome(_ q: String?) async throws -> (id: String, name: String) {
    let hs = try await houseHomes()
    if let q {
        if let h = hs.first(where: { $0.id == q || $0.name == q }) { return h }
        throw MijiaError.deviceNotFound(L("家庭 ", "home ") + q)
    }
    if let s = prefs.selectedHome, let h = hs.first(where: { $0.id == s }) { return h }
    guard let h = hs.first else { throw MijiaError.deviceNotFound(L("没有设备", "no devices")) }
    return h
}

@MainActor func houseResolved(home: String) async throws -> ResolvedHouse {
    let ds = try await devices().filter { $0.homeId == home }
    let cfg = HouseStore.load().homes[home]
    return HouseResolver.resolve(devices: ds, config: cfg, isHidden: prefs.isHidden, name: prefs.name, layout: cfg?.layout)
}

func spotString(_ s: HouseSpot?) -> Any {
    switch s { case .fixture(let id): return "fixture:" + id; case .badge(let id): return "badge:" + id; case nil: return NSNull() }
}

@MainActor func houseReport(home: (id: String, name: String)) async throws -> [String: Any] {
    guard policy.canRead else { throw MijiaError.denied("disabled") }
    let r = try await houseResolved(home: home.id)
    let all = try await devices()
    let loc = HouseStore.location
    return [
        "schema": HouseFile.currentSchema,
        "file": HouseStore.url.path, "sync": loc.mode.rawValue,
        "home": ["id": home.id, "name": home.name],
        "rooms": r.rooms.map { room -> [String: Any] in
            ["key": room.key, "title": room.title, "module": room.module.rawValue,
             "devices": room.devices.map { d -> [String: Any] in
                 ["did": d.did, "name": d.name, "category": d.category.rawValue, "online": d.online, "spot": spotString(d.spot), "pinned": d.pinned] }]
        },
        "excluded": r.excluded.map { ["key": $0.key, "title": $0.title, "module": $0.module.rawValue, "reason": $0.reason.rawValue, "devices": $0.deviceCount] },
        "hidden": r.hidden.map { did in ["did": did, "name": all.first { $0.did == did }.map(prefs.name) ?? did] },
    ]
}

func houseSlots() -> [String: Any] {
    var mods: [String: Any] = [:]
    for m in HouseModule.allCases {
        mods[m.rawValue] = [
            "has_art": m.hasArt, "title": m.title,
            "fixtures": HouseCatalog.fixtures(m).map { ["id": $0.id, "accepts": $0.accepts.map(\.rawValue).sorted(), "hints": $0.hints, "hint_required": $0.hintRequired] },
            "badges": HouseCatalog.badgeIds(m),
        ]
    }
    return ["schema": HouseFile.currentSchema, "modules": mods]
}

@MainActor func houseResolveRoom(_ q: String, home: String) async throws -> (key: String, title: String) {
    let ds = try await devices().filter { $0.homeId == home }
    var rooms: [(String, String)] = []
    for d in ds { let k = HouseResolver.roomKey(d); if !rooms.contains(where: { $0.0 == k }) { rooms.append((k, d.roomName ?? "")) } }
    if let r = rooms.first(where: { $0.0 == q || $0.1 == q || "name:" + $0.1 == q }) { return r }
    let m = rooms.filter { $0.1.localizedCaseInsensitiveContains(q) }
    if m.count == 1 { return m[0] }
    throw MijiaError.deviceNotFound(L("房间 ", "room ") + q)
}

func parsePlace(_ s: String) throws -> String? {
    switch s {
    case "auto": return nil
    case "badge", "none": return s
    case _ where s.hasPrefix("badge:"):
        let id = String(s.dropFirst(6))
        guard HouseModule.allCases.contains(where: { HouseCatalog.badgeIds($0).contains(id) }) else {
            throw MijiaError.unknownProperty(L("位置 ", "spot ") + s + L("（可用 mijiabar house slots 查看）", " (see mijiabar house slots)"))
        }
        return s
    default:
        let id = s.hasPrefix("fixture:") ? String(s.dropFirst(8)) : s
        guard HouseModule.allCases.contains(where: { HouseCatalog.fixture($0, id) != nil }) else {
            throw MijiaError.unknownProperty(L("位置 ", "spot ") + s + L("（可用 mijiabar house slots 查看）", " (see mijiabar house slots)"))
        }
        return "fixture:" + id
    }
}

func parseVisible(_ s: String) throws -> Bool? {
    switch s.lowercased() { case "true", "on", "yes", "1", "show": return true; case "false", "off", "no", "0", "hide": return false
    case "auto": return nil; default: throw MijiaError.unknownProperty("--visible " + s) }
}

@MainActor func checkHouseWrite() throws { guard policy.canRead else { throw MijiaError.denied("disabled") } }

/// 改一台设备的覆盖项，返回改后的覆盖项和它现在的位置
@MainActor func houseSetDevice(_ q: String, visible: Bool??, place: String??) async throws -> [String: Any] {
    try checkHouseWrite()
    let d = try await resolve(q)
    if case .some(.some(let p)) = place, p.hasPrefix("fixture:") {
        // 灯具位只能是设备所在房间的模块里、接受这类设备的位置
        let id = String(p.dropFirst(8))
        let r = try await houseResolved(home: d.homeId)
        guard let room = r.rooms.first(where: { $0.key == HouseResolver.roomKey(d) }) else {
            throw MijiaError.unknownProperty(L("这台设备所在的房间没有放进小屋", "this device's room is not in the house"))
        }
        let ok = HouseCatalog.fixtures(room.module).filter { $0.accepts(d.category) }.map(\.id)
        guard ok.contains(id) else {
            throw MijiaError.unknownProperty(LF("位置 %@；%@ 里能放这台设备的灯具位：%@", "spot %@; fixtures in %@ that accept this device: %@",
                                                id, room.module.rawValue, ok.isEmpty ? "-" : ok.joined(separator: ", ")))
        }
    }
    try HouseStore.update { f in
        f.setDevice(home: d.homeId, did: d.did) { o in
            if let v = visible { o.visible = v }
            if let p = place { o.place = p }
        }
    }
    return try await houseDeviceResult(d)
}

@MainActor func houseDeviceResult(_ d: Device) async throws -> [String: Any] {
    let r = try await houseResolved(home: d.homeId)
    let o = HouseStore.load().homes[d.homeId]?.devices[d.did]
    let placed = r.rooms.flatMap { room in room.devices.map { (room, $0) } }.first { $0.1.did == d.did }
    var out: [String: Any] = ["ok": true, "did": d.did, "device": prefs.name(d),
                              "visible": o?.visible.map { $0 as Any } ?? NSNull(), "place": o?.place ?? NSNull(),
                              "in_house": placed != nil, "spot": spotString(placed?.1.spot), "file": HouseStore.url.path]
    if let room = placed?.0 { out["room"] = room.title; out["module"] = room.module.rawValue }
    else if r.hidden.contains(d.did) { out["reason"] = "hidden" }
    else if let e = r.excluded.first(where: { $0.key == HouseResolver.roomKey(d) }) { out["reason"] = "room_" + e.reason.rawValue }
    return out
}

@MainActor func houseSetRoom(_ q: String, module: String, home: String?) async throws -> [String: Any] {
    try checkHouseWrite()
    let h = try await houseHome(home)
    let room = try await houseResolveRoom(q, home: h.id)
    let m: String?
    switch module { case "auto": m = nil; case "none": m = "none"
    default:
        guard let mm = HouseModule(rawValue: module) else { throw MijiaError.unknownProperty(L("模块 ", "module ") + module) }
        m = mm.rawValue
    }
    try HouseStore.update { $0.setRoom(home: h.id, key: room.key, module: m) }
    let r = try await houseResolved(home: h.id)
    var out: [String: Any] = ["ok": true, "room": room.title, "key": room.key, "module": m ?? NSNull(), "file": HouseStore.url.path]
    if let placed = r.rooms.first(where: { $0.key == room.key }) { out["in_house"] = true; out["shown_as"] = placed.module.rawValue }
    else { out["in_house"] = false; out["reason"] = r.excluded.first { $0.key == room.key }?.reason.rawValue ?? NSNull() }
    return out
}

@MainActor func houseLayout(pos: [String], rest: [String]) async throws -> [String: Any] {
    let h = try await houseHome(opt(rest, "--home"))
    let file = HouseStore.load()
    let home = file.homes[h.id] ?? HomeHouse()
    let sub = pos.first ?? "show"
    switch sub {
    case "show":
        break
    case "classic":
        try checkHouseWrite()
        try HouseStore.update { $0.setLayout(home: h.id, layout: nil) }
    case "auto":
        try checkHouseWrite()
        let r = try await houseResolved(home: h.id)
        let rooms = r.rooms.map { (key: $0.key, module: $0.module, score: $0.devices.count) }
            + r.excluded.map { (key: $0.key, module: $0.module, score: $0.deviceCount) }
        let layout = HouseLayoutSolver.autolayout(rooms: rooms)
        let problems = HouseLayoutSolver.validate(layout)
        guard problems.isEmpty else { throw MijiaError.unknownProperty("layout: \(problems.map(\.rawValue).joined(separator: ","))") }
        try HouseStore.update { $0.setLayout(home: h.id, layout: layout) }
    case "set":
        try checkHouseWrite()
        var cells: [HouseLayoutCell] = []
        for token in pos.dropFirst() {
            let parts = token.split(separator: ":", maxSplits: 3).map(String.init)
            guard parts.count == 4, let col = Int(parts[2]), let row = Int(parts[3]) else {
                throw MijiaError.unknownProperty(L("布局项 ", "layout cell ") + token + " (room:module:col:row)")
            }
            let room = try await houseResolveRoom(parts[0], home: h.id)
            cells.append(.init(room: room.key, module: parts[1], col: col, row: row))
        }
        let problems = HouseLayoutSolver.validate(cells)
        guard problems.isEmpty else { throw MijiaError.unknownProperty("layout: \(problems.map(\.rawValue).joined(separator: ","))") }
        try HouseStore.update { $0.setLayout(home: h.id, layout: cells) }
    default:
        throw MijiaError.unknownProperty("house layout " + sub)
    }
    let after = HouseStore.load().homes[h.id]
    return [
        "ok": true, "home": h.id,
        "classic": HouseLayoutSolver.isClassicGeometry(after?.layout),
        "layout": after?.layout?.map { ["room": $0.room, "module": $0.module, "col": $0.col, "row": $0.row] } ?? NSNull(),
        "file": HouseStore.url.path,
    ]
}

@MainActor func houseReset(device: String?, room: String?, layout: Bool = false, home: String?) async throws -> [String: Any] {
    try checkHouseWrite()
    if let device {
        let d = try await resolve(device)
        try HouseStore.update { $0.reset(home: d.homeId, did: d.did) }
        return try await houseDeviceResult(d)
    }
    let h = try await houseHome(home)
    var key: String?
    if let room { key = try await houseResolveRoom(room, home: h.id).key }
    try HouseStore.update { $0.reset(home: h.id, room: key, layout: layout) }
    return ["ok": true, "home": h.id, "room": key ?? NSNull(), "layout": layout, "file": HouseStore.url.path]
}

func houseSync(_ arg: String?) throws -> [String: Any] {
    if let arg {
        let l: HouseLocation
        switch arg { case "icloud": l = .init(mode: .icloud); case "local": l = .init(mode: .local)
        default: l = .init(mode: .folder, path: (arg as NSString).expandingTildeInPath) }
        if l.mode == .icloud, HouseStore.iCloudDrive == nil { throw MijiaError.unknownProperty(L("这台 Mac 没有开 iCloud Drive", "iCloud Drive is not enabled on this Mac")) }
        try HouseStore.setLocation(l)
    }
    let l = HouseStore.location
    var o: [String: Any] = ["sync": l.mode.rawValue, "file": HouseStore.url.path, "icloud_available": HouseStore.iCloudDrive != nil]
    if let p = l.path { o["folder"] = p }
    if ProcessInfo.processInfo.environment["MIJIABAR_HOUSE_FILE"] != nil { o["overridden_by_env"] = "MIJIABAR_HOUSE_FILE" }
    return o
}

/// house.json 的 JSON Schema（draft 2020-12），和 docs/HOUSE.md 一致
nonisolated(unsafe) let houseSchema: [String: Any] = [
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://github.com/neardws/MijiaBar/blob/main/docs/HOUSE.md",
    "title": "MijiaBar house.json", "type": "object",
    "properties": [
        "schema": ["type": "integer", "const": 1],
        "homes": ["type": "object", "description": "Mi Home home id → overrides", "additionalProperties": ["$ref": "#/$defs/home"]],
    ],
    "$defs": [
        "home": ["type": "object", "properties": [
            "rooms": ["type": "object", "description": "room key (Mi Home room id, or \"name:<room name>\") → override", "additionalProperties": ["$ref": "#/$defs/room"]],
            "devices": ["type": "object", "description": "device did → override", "additionalProperties": ["$ref": "#/$defs/device"]],
        ]],
        "room": ["type": "object", "required": ["updatedAt"], "properties": [
            "module": ["type": ["string", "null"], "enum": HouseModule.allCases.map(\.rawValue) + ["none", NSNull()], "description": "null = automatic"],
            "updatedAt": ["type": "string", "format": "date-time"],
        ]],
        "device": ["type": "object", "required": ["updatedAt"], "properties": [
            "visible": ["type": ["boolean", "null"], "description": "null = follow the device list's hidden state"],
            "place": ["type": ["string", "null"], "pattern": "^(fixture:[a-z_]+|badge(:b[0-9]+)?|none)$", "description": "null = automatic"],
            "updatedAt": ["type": "string", "format": "date-time"],
        ]],
    ],
]

@MainActor func houseCommand(_ args: [String]) async throws {
    let sub = args.first ?? "show"
    let rest = Array(args.dropFirst())
    let asJSON = args.contains("--json")
    let pos = { () -> [String] in
        var out: [String] = []; var i = 0
        while i < rest.count { if ["--home", "--room", "--visible", "--place"].contains(rest[i]) { i += 2; continue }; if rest[i] != "--json" { out.append(rest[i]) }; i += 1 }
        return out
    }()
    switch sub {
    case "show":
        let r = try await houseReport(home: try await houseHome(opt(rest, "--home")))
        if asJSON { print(json(r)); return }
        let home = r["home"] as? [String: Any] ?? [:]
        print("\(home["name"] ?? "") · \(r["file"] ?? "") (\(r["sync"] ?? ""))")
        for room in r["rooms"] as? [[String: Any]] ?? [] {
            print("\n▸ \(room["title"] ?? "") [\(room["module"] ?? "")]")
            for d in room["devices"] as? [[String: Any]] ?? [] {
                let spot = (d["spot"] as? String) ?? L("仅按钮", "chip only")
                print("  \((d["online"] as? Bool ?? false) ? "●" : "○") \(d["name"] ?? "")\t\(spot)\((d["pinned"] as? Bool ?? false) ? " 📌" : "")\t\(d["did"] ?? "")")
            }
        }
        let ex = r["excluded"] as? [[String: Any]] ?? []
        if !ex.isEmpty { print("\n" + L("没进小屋的房间：", "Rooms not in the house:")); for e in ex { print("  \(e["title"] ?? "") (\(e["reason"] ?? ""), \(e["devices"] ?? 0))") } }
        let hid = r["hidden"] as? [[String: Any]] ?? []
        if !hid.isEmpty { print("\n" + L("隐藏：", "Hidden: ") + hid.map { "\($0["name"] ?? "")" }.joined(separator: ", ")) }
    case "slots":
        let s = houseSlots()
        if asJSON { print(json(s)); return }
        for m in HouseModule.allCases {
            let fx = HouseCatalog.fixtures(m)
            print("\(m.rawValue)\(m.hasArt ? "" : L("（暂无素材）", " (no art yet)")): " + fx.map { "\($0.id)[\($0.accepts.map(\.rawValue).sorted().joined(separator: "/"))]" }.joined(separator: ", ")
                  + " · badges ×\(HouseCatalog.badgeCount(m))")
        }
    case "hide", "unhide":
        guard let q = pos.first else { fail(houseUsage) }
        print(json(try await houseSetDevice(q, visible: .some(sub == "unhide"), place: nil)))
    case "assign":
        guard pos.count >= 2 else { fail(houseUsage) }
        print(json(try await houseSetDevice(pos[0], visible: nil, place: .some(try parsePlace(pos[1])))))
    case "set":
        guard let q = pos.first else { fail(houseUsage) }
        let v = try opt(rest, "--visible").map { try parseVisible($0) }
        let p = try opt(rest, "--place").map { try parsePlace($0) }
        guard v != nil || p != nil else { fail(houseUsage) }
        print(json(try await houseSetDevice(q, visible: v, place: p)))
    case "room":
        guard pos.count >= 2 else { fail(houseUsage) }
        print(json(try await houseSetRoom(pos[0], module: pos[1], home: opt(rest, "--home"))))
    case "layout":
        print(json(try await houseLayout(pos: pos, rest: rest)))
    case "reset":
        print(json(try await houseReset(device: pos.first, room: opt(rest, "--room"), layout: rest.contains("--layout"), home: opt(rest, "--home"))))
    case "sync":
        let r = try houseSync(pos.first)
        if asJSON || pos.first != nil { print(json(r)) } else { print("\(r["sync"] ?? "") · \(r["file"] ?? "")") }
    case "schema": print(json(houseSchema))
    default: print(houseUsage)
    }
}

// MARK: - MCP

nonisolated(unsafe) let houseMCPTools: [[String: Any]] = [
    ["name": "get_house", "description": "读取小屋（菜单栏里的像素剖面）当前布局：每个房间放了哪些设备、在哪个灯具位 / 徽章位，哪些房间和设备没进小屋。Read the house cutaway layout.",
     "inputSchema": ["type": "object", "properties": ["home": ["type": "string", "description": "家庭 id 或名称（默认当前家庭）"]]]],
    ["name": "get_house_slots", "description": "小屋模块目录：每个模块的灯具位 id 和接受的设备类型。List house modules and fixture slot ids.",
     "inputSchema": ["type": "object", "properties": [String: Any]()]],
    ["name": "set_house_device", "description": "设置一台设备在小屋里的显示和位置（只改小屋，不控制设备）。visible: true/false/\"auto\"；place: 灯具位 id | badge | badge:<id> | none | auto。",
     "inputSchema": ["type": "object", "properties": ["device": ["type": "string"], "visible": ["description": "true | false | \"auto\""], "place": ["type": "string"]], "required": ["device"]]],
    ["name": "set_house_room", "description": "设置米家房间在小屋里用哪个模块：living | bedroom | study | kitchen | bathroom | balcony | generic | none | auto。",
     "inputSchema": ["type": "object", "properties": ["room": ["type": "string"], "module": ["type": "string"], "home": ["type": "string"]], "required": ["room", "module"]]],
    ["name": "get_house_layout", "description": "当前小屋格子布局。classic=true 表示走 Phase 1 整图。",
     "inputSchema": ["type": "object", "properties": ["home": ["type": "string"]]]],
    ["name": "set_house_layout", "description": "设置格子布局。cells 为 [{room,module,col,row}]；传 null 或 mode=classic 恢复经典四室；mode=auto 自动填 3×2。",
     "inputSchema": ["type": "object", "properties": ["home": ["type": "string"], "mode": ["type": "string"], "cells": ["type": "array"]], "required": []]],
    ["name": "reset_house", "description": "把小屋恢复自动：整个家、一台设备或一个房间。",
     "inputSchema": ["type": "object", "properties": ["home": ["type": "string"], "device": ["type": "string"], "room": ["type": "string"]]]],
]

@MainActor func callHouseTool(_ name: String, _ a: [String: Any]) async throws -> Any? {
    switch name {
    case "get_house": return try await houseReport(home: try await houseHome(a["home"] as? String))
    case "get_house_slots": return houseSlots()
    case "set_house_device":
        var vis: Bool?? = nil
        if let v = a["visible"] {
            if v is NSNull { vis = .some(nil) } else if let b = v as? Bool { vis = .some(b) } else { vis = .some(try parseVisible(anyString(v))) }
        }
        var place: String?? = nil
        if let p = a["place"] as? String { place = .some(try parsePlace(p)) }
        guard vis != nil || place != nil else { throw MijiaError.unknownProperty("visible / place") }
        return try await houseSetDevice(anyString(a["device"]), visible: vis, place: place)
    case "set_house_room": return try await houseSetRoom(anyString(a["room"]), module: anyString(a["module"]), home: a["home"] as? String)
    case "get_house_layout":
        var rest1: [String] = []; if let h = a["home"] as? String { rest1 = ["--home", h] }
        return try await houseLayout(pos: ["show"], rest: rest1)
    case "set_house_layout":
        var rest2: [String] = []; if let h = a["home"] as? String { rest2 = ["--home", h] }
        if let mode = a["mode"] as? String, mode == "classic" || mode == "auto" {
            return try await houseLayout(pos: [mode], rest: rest2)
        }
        if a["cells"] == nil || a["cells"] is NSNull {
            return try await houseLayout(pos: ["classic"], rest: rest2)
        }
        guard let cells = a["cells"] as? [[String: Any]] else { throw MijiaError.unknownProperty("cells") }
        var tokens = ["set"]
        for c in cells {
            tokens.append("\(c["room"] ?? ""):\(c["module"] ?? ""):\(c["col"] ?? 0):\(c["row"] ?? 0)")
        }
        return try await houseLayout(pos: tokens, rest: rest2)
    case "reset_house": return try await houseReset(device: a["device"] as? String, room: a["room"] as? String, home: a["home"] as? String)
    default: return nil
    }
}
