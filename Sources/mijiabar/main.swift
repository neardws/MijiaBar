import Foundation
import MijiaCore

// mijiabar —— 给人和 Agent 用的米家命令行 / MCP 服务器
let version = "0.1.4"
setvbuf(stdout, nil, _IOLBF, 0)

func eprint(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }
func fail(_ s: String) -> Never { eprint(s); exit(1) }
func json(_ a: Any) -> String {
    guard JSONSerialization.isValidJSONObject(a), let d = try? JSONSerialization.data(withJSONObject: a, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return "\(a)" }
    return String(data: d, encoding: .utf8) ?? ""
}

let prefs = Prefs.load()
let policy = AgentPolicy.load()
let controller = Controller(cloud: Session.load().map { XiaomiCloud(session: $0) })

func devices(refresh: Bool = false) async throws -> [Device] {
    if !refresh, let c = DeviceCache.load(), !c.devices.isEmpty { return c.devices }
    guard let cloud = controller.cloud else { throw CloudError.notLoggedIn }
    let hs = try await cloud.homes(); var all: [Device] = []
    for h in hs { for d in try await cloud.devices(in: h) where !all.contains(where: { $0.did == d.did }) { all.append(d) } }
    DeviceCache(homes: hs, devices: all, updated: Date()).save()
    return all
}

func resolve(_ q: String) async throws -> Device {
    let ds = try await devices()
    if let d = ds.first(where: { $0.did == q }) { return d }
    if let d = ds.first(where: { prefs.name($0) == q || $0.name == q }) { return d }
    let m = ds.filter { prefs.name($0).localizedCaseInsensitiveContains(q) }
    if m.count == 1 { return m[0] }
    throw MijiaError.deviceNotFound(q + (m.count > 1 ? L("（匹配到多个：", " (ambiguous: ") + m.map { prefs.name($0) }.joined(separator: ", ") + ")" : ""))
}

func deviceInfo(_ d: Device) -> [String: Any] {
    var o: [String: Any] = ["did": d.did, "name": prefs.name(d), "model": d.model, "online": d.isOnline,
                            "category": d.category.rawValue, "home": d.homeName, "hidden": prefs.isHidden(d),
                            "favorite": prefs.devices[d.did]?.favorite ?? false,
                            "agent_writable": policy.canWrite(d.did)]
    if let r = d.roomName { o["room"] = r }
    return o
}

func stateInfo(_ d: Device, _ s: DeviceState) -> [String: Any] {
    var o = deviceInfo(d); o["source"] = s.source
    if s.legacy {
        o["protocol"] = "miio-legacy"
        o["properties"] = Controller.legacyProps.map { k -> [String: Any] in
            ["key": k, "value": s.values[k]?.any ?? NSNull(), "writable": k != "load_power"] }
        if let ac = ACState.make(s) { o["summary"] = ["power": ac.power, "mode": ac.modeLabel, "target_temperature": ac.target ?? NSNull(), "fan": ac.fanLabel] }
    } else if let spec = s.spec {
        o["protocol"] = "miot"
        o["properties"] = spec.controlServices.flatMap { svc in svc.properties.filter { $0.readable || $0.writable }.map { p -> [String: Any] in
            var x: [String: Any] = ["key": p.key, "name": "\(svc.name).\(p.name)", "description": p.description, "format": p.format,
                                    "writable": p.writable, "value": s.values[p.key]?.any ?? NSNull()]
            if let u = p.unit, u != "none" { x["unit"] = u }
            if let r = p.range { x["range"] = r }
            if let ops = p.options { x["options"] = ops.map { ["value": $0.value, "description": $0.description] } }
            return x } }
        o["actions"] = spec.controlServices.flatMap { svc in svc.actions.map { ["key": $0.key, "name": "\(svc.name).\($0.name)", "description": $0.description, "inputs": $0.inputs] } }
    }
    return o
}

/// 属性可以写成 "2.1"、"on"、"air-conditioner.on"；空调伴侣还支持 power/mode/tar_temp/fan_level/ver_swing
func resolveKey(_ d: Device, _ name: String) async throws -> (String, String?) {
    if Controller.isLegacyAC(d.model) {
        let alias = ["on": "power", "target-temperature": "tar_temp", "fan-level": "fan_level", "vertical-swing": "ver_swing"]
        let k = alias[name] ?? name
        guard Controller.legacyProps.contains(k), k != "load_power" else { throw MijiaError.unknownProperty(name) }
        return (k, nil)
    }
    guard let spec = try await controller.specs.spec(for: d.model) else { throw MijiaError.noSpec(d.model) }
    var p = spec.prop(key: name)
    if p == nil { let c = name.split(separator: "."); if c.count == 2 { p = spec.services.first { $0.name == c[0] }?.prop(String(c[1])) } }
    if p == nil { p = spec.prop(named: name) }
    guard let p else { throw MijiaError.unknownProperty(name) }
    guard p.writable else { throw MijiaError.notWritable(name) }
    return (p.key, p.format)
}

func confirm(_ msg: String) -> Bool {
    let script = "display dialog \"\(msg.replacingOccurrences(of: "\"", with: "'"))\" with title \"MijiaBar · Agent\" buttons {\"\(L("拒绝", "Deny"))\", \"\(L("允许", "Allow"))\"} default button 2 cancel button 1 giving up after 60"
    let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript"); p.arguments = ["-e", script]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    guard (try? p.run()) != nil else { return false }
    p.waitUntilExit()
    let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return p.terminationStatus == 0 && out.contains(L("允许", "Allow")) && !out.contains("gave up:true")
}

func checkWrite(_ d: Device, _ what: String) throws {
    guard policy.canWrite(d.did) else {
        throw MijiaError.denied(L("当前 Agent 模式为「\(policy.mode.rawValue)」，请在 MijiaBar 设置里开启写权限或把设备加入白名单",
                                  "agent mode is \(policy.mode.rawValue); enable writes or allowlist the device in MijiaBar settings"))
    }
    if policy.confirmWrites, !confirm(L("Agent 请求控制「\(prefs.name(d))」：\(what)", "Agent wants to control \"\(prefs.name(d))\": \(what)")) {
        throw MijiaError.denied(L("用户拒绝", "user declined"))
    }
}

func listDevices(all: Bool, refresh: Bool) async throws -> [[String: Any]] {
    guard policy.canRead else { throw MijiaError.denied("disabled") }
    return try await devices(refresh: refresh).filter { all || !prefs.isHidden($0) }.map(deviceInfo)
}
func getState(_ q: String) async throws -> [String: Any] {
    guard policy.canRead else { throw MijiaError.denied("disabled") }
    let d = try await resolve(q)
    return stateInfo(d, try await controller.readState(d))
}
func setProperty(_ q: String, _ prop: String, _ value: PropValue) async throws -> [String: Any] {
    let d = try await resolve(q)
    let (key, format) = try await resolveKey(d, prop)
    let v = format.map { value.coerced(to: $0) } ?? value
    try checkWrite(d, "\(prop) = \(v)")
    try await controller.set(d, key: key, value: v)
    return ["ok": true, "device": prefs.name(d), "key": key, "value": v.any]
}
func runAction(_ q: String, _ act: String, _ inputs: [Any]) async throws -> [String: Any] {
    let d = try await resolve(q)
    guard let spec = try await controller.specs.spec(for: d.model) else { throw MijiaError.noSpec(d.model) }
    var a = spec.action(key: act)
    if a == nil { let c = act.split(separator: "."); if c.count == 2 { a = spec.services.first { $0.name == c[0] }?.actions.first { $0.name == c[1] } } }
    if a == nil { a = spec.action(named: act) }
    guard let a else { throw MijiaError.unknownProperty(act) }
    try checkWrite(d, L("动作 ", "action ") + act)
    let r = try await controller.action(d, key: a.key, inputs: inputs)
    return ["ok": true, "device": prefs.name(d), "action": a.key, "result": PropValue(r).any]
}

// MARK: - MCP (stdio JSON-RPC)

let mcpTools: [[String: Any]] = [
    ["name": "list_devices", "description": "列出米家设备（默认不含已隐藏的离线/久未使用设备）。List Mi Home devices.",
     "inputSchema": ["type": "object", "properties": ["include_hidden": ["type": "boolean"], "refresh": ["type": "boolean", "description": "从小米云重新拉取"]]]],
    ["name": "get_device_state", "description": "读取设备当前状态与可写属性/动作（含 key、取值范围、选项）。Read device state.",
     "inputSchema": ["type": "object", "properties": ["device": ["type": "string", "description": "did 或设备名"]], "required": ["device"]]],
    ["name": "set_property", "description": "设置设备属性。property 可用 key（如 2.1）、名称（如 on、target-temperature）。受 MijiaBar 的 Agent 权限控制。",
     "inputSchema": ["type": "object", "properties": ["device": ["type": "string"], "property": ["type": "string"], "value": ["description": "bool / number / string"]], "required": ["device", "property", "value"]]],
    ["name": "run_action", "description": "执行 MIoT 动作（如 2.1 或 toggle）。受 Agent 权限控制。",
     "inputSchema": ["type": "object", "properties": ["device": ["type": "string"], "action": ["type": "string"], "params": ["type": "array"]], "required": ["device", "action"]]],
]

func callTool(_ name: String, _ a: [String: Any]) async throws -> Any {
    switch name {
    case "list_devices": return try await listDevices(all: a["include_hidden"] as? Bool ?? false, refresh: a["refresh"] as? Bool ?? false)
    case "get_device_state": return try await getState(anyString(a["device"]))
    case "set_property": return try await setProperty(anyString(a["device"]), anyString(a["property"]), PropValue(a["value"]))
    case "run_action": return try await runAction(anyString(a["device"]), anyString(a["action"]), a["params"] as? [Any] ?? [])
    default: throw MijiaError.unknownProperty(name)
    }
}

func mcp() async {
    while let line = readLine() {
        guard let d = line.data(using: .utf8), let req = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
        guard let id = req["id"] else { continue }
        let params = req["params"] as? [String: Any] ?? [:]
        var resp: [String: Any] = ["jsonrpc": "2.0", "id": id]
        switch req["method"] as? String ?? "" {
        case "initialize":
            resp["result"] = ["protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                              "capabilities": ["tools": [String: Any]()], "serverInfo": ["name": "mijiabar", "version": version]]
        case "tools/list": resp["result"] = ["tools": mcpTools]
        case "tools/call":
            do {
                let r = try await callTool(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
                resp["result"] = ["content": [["type": "text", "text": json(r)]]]
            } catch {
                resp["result"] = ["content": [["type": "text", "text": L("错误：", "Error: ") + error.localizedDescription]], "isError": true]
            }
        case "ping": resp["result"] = [String: Any]()
        default: resp["error"] = ["code": -32601, "message": "Method not found"]
        }
        if let out = try? JSONSerialization.data(withJSONObject: resp), let s = String(data: out, encoding: .utf8) { print(s) }
    }
}

// MARK: - CLI

let usage = """
mijiabar \(version) — 米家设备命令行 / MCP

用法:
  mijiabar list [--all] [--refresh]          列出设备（默认隐藏离线/久未使用）
  mijiabar get <设备>                         读取状态（设备 = did 或名称）
  mijiabar set <设备> <属性> <值>              设置属性，例: set 客厅空调 tar_temp 26 / set 台灯 on true
  mijiabar action <设备> <动作> [JSON数组]     执行 MIoT 动作
  mijiabar mcp                               以 stdio MCP 服务器运行
  mijiabar lan-get --ip IP --token T [--model M]  只读：直接走局域网读取（调试用）

写操作受 MijiaBar 设置 → Agent 接口 的权限控制（默认只读）。
"""

func opt(_ args: [String], _ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first ?? "help" {
    case "list":
        let r = try await listDevices(all: args.contains("--all"), refresh: args.contains("--refresh"))
        if args.contains("--json") { print(json(r)) } else {
            for d in r { print("\((d["online"] as? Bool ?? false) ? "●" : "○") \(d["name"] ?? "")\t\(d["model"] ?? "")\t\(d["room"] ?? "")\t\(d["did"] ?? "")") }
        }
    case "get": guard args.count >= 2 else { fail(usage) }; print(json(try await getState(args[1])))
    case "set": guard args.count >= 4 else { fail(usage) }; print(json(try await setProperty(args[1], args[2], PropValue.parse(args[3]))))
    case "action":
        guard args.count >= 3 else { fail(usage) }
        let ins = args.count > 3 ? (try? JSONSerialization.jsonObject(with: Data(args[3].utf8))) as? [Any] ?? [] : []
        print(json(try await runAction(args[1], args[2], ins)))
    case "mcp": await mcp()
    case "lan-get":
        guard let ip = opt(args, "--ip"), let tk = opt(args, "--token") else { fail(usage) }
        let model = opt(args, "--model") ?? "lumi.acpartner.mcn02"
        let d = Device(did: "lan", name: ip, model: model, ip: ip, token: tk)
        print(json(stateInfo(d, try await Controller(cloud: nil).readState(d))))
    case "version", "--version": print(version)
    default: print(usage)
    }
} catch { fail(L("错误：", "Error: ") + error.localizedDescription) }
