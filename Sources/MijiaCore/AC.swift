import Foundation

public struct ACOption: Hashable { public let label: String; public let value: PropValue }

/// 中英文常见取值翻译
public func trValue(_ en: String) -> String {
    guard isChinese else { return currentLang == .en ? en : (trValueTable[en.lowercased()].map { $0[currentLang.trIndex] } ?? tr(en, currentLang) ?? en) }
    let m = ["auto": "自动", "cool": "制冷", "cooling": "制冷", "heat": "制热", "heating": "制热", "dry": "除湿", "dehumidify": "除湿",
             "fan": "送风", "wind": "送风", "low": "低", "medium": "中", "middle": "中", "high": "高", "sleep": "睡眠", "silent": "静音",
             "favorite": "喜爱", "straight wind": "直吹", "natural wind": "自然风", "level1": "一档", "level2": "二档", "level3": "三档", "level4": "四档",
             "playing": "播放中", "pause": "已暂停", "paused": "已暂停", "stop": "已停止", "stopped": "已停止", "idle": "空闲", "busy": "忙碌",
             "initializing": "初始化中", "processing": "打印中", "off": "关", "on": "开", "error": "故障", "standby": "待机", "default": "默认",
             "timer": "预约中", "completed": "已完成", "hotpot": "火锅", "cooking": "烹饪", "soup": "煲汤", "porridge": "煮粥", "noodles": "煮面",
             "keepwarm": "保温", "keep warm": "保温", "lighting": "照明", "night light": "夜灯", "tv": "电视", "warmth": "暖光", "ct": "色温",
             "normal": "正常", "non existent": "未插卡", "full": "已满", "formatting": "格式化中", "ejected": "已弹出", "fixing": "修复中",
             "no record": "不录制", "motion record": "移动时录制", "all record": "一直录制", "single cycle": "单曲循环", "no faults": "无故障",
             "over temperature": "过热", "overload": "过载", "delay": "延迟"]
    return m[en.lowercased()].map { L($0, $0) } ?? en
}

/// 把不同协议的空调抽象成统一状态，供 UI 渲染
public struct ACState {
    public var power = false
    public var powerKey = "power"
    public var onValue: PropValue = .string("on"), offValue: PropValue = .string("off")
    public var modeKey: String?; public var mode: PropValue?; public var modes: [ACOption] = []
    public var tempKey: String?; public var target: Double?; public var minT = 16.0, maxT = 30.0, step = 1.0; public var tempIsFloat = false
    public var fanKey: String?; public var fan: PropValue?; public var fans: [ACOption] = []
    public var swingKey: String?; public var swing: Bool?; public var swingOn: PropValue = .bool(true), swingOff: PropValue = .bool(false)
    public var sleepKey: String?; public var sleep: Bool?
    public var roomTemp: Double?; public var loadPower: Double?

    public var modeLabel: String { modes.first { $0.value == mode }?.label ?? (mode?.description ?? "-") }
    public var fanLabel: String { fans.first { $0.value == fan }?.label ?? (fan?.description ?? "-") }
    public var isHeating: Bool { [L("制热", "Heat"), trValue("heat")].contains(modeLabel) || modeLabel.contains("制热") || modeLabel.lowercased().contains("heat") }
    public var isCooling: Bool { [L("制冷", "Cool"), trValue("cool")].contains(modeLabel) || modeLabel.contains("制冷") || modeLabel.lowercased().contains("cool") }
    public func tempValue(_ v: Double) -> PropValue { tempIsFloat ? .double(v) : .int(Int(v.rounded())) }

    public static func make(_ s: DeviceState) -> ACState? {
        if s.legacy { return legacy(s.values) }
        guard let spec = s.spec else { return nil }
        return miot(s.values, spec)
    }

    static func legacy(_ v: [String: PropValue]) -> ACState {
        var a = ACState()
        a.power = v["power"]?.boolValue ?? false
        a.modeKey = "mode"; a.mode = v["mode"]
        a.modes = [("auto", "自动", "Auto"), ("cool", "制冷", "Cool"), ("dry", "除湿", "Dry"), ("heat", "制热", "Heat"), ("wind", "送风", "Fan")]
            .map { ACOption(label: L($0.1, $0.2), value: .string($0.0)) }
        a.tempKey = "tar_temp"; a.target = v["tar_temp"]?.doubleValue
        a.fanKey = "fan_level"; a.fan = v["fan_level"]
        a.fans = [("auto_fan", "自动", "Auto"), ("small_fan", "低", "Low"), ("medium_fan", "中", "Medium"), ("large_fan", "高", "High")]
            .map { ACOption(label: L($0.1, $0.2), value: .string($0.0)) }
        a.swingKey = "ver_swing"; a.swing = v["ver_swing"].map { $0 == .string("on") }
        a.swingOn = .string("on"); a.swingOff = .string("off")
        a.loadPower = v["load_power"]?.doubleValue
        return a
    }

    static func miot(_ v: [String: PropValue], _ spec: DeviceSpec) -> ACState? {
        guard let svc = spec.services.first(where: { $0.name == "air-conditioner" }), let on = svc.prop("on") else { return nil }
        var a = ACState()
        a.power = v[on.key]?.boolValue ?? false; a.powerKey = on.key; a.onValue = .bool(true); a.offValue = .bool(false)
        if let m = svc.prop("mode") {
            a.modeKey = m.key; a.mode = v[m.key]
            a.modes = (m.options ?? []).map { ACOption(label: trValue($0.description), value: .int($0.value)) }
        }
        if let t = svc.prop("target-temperature") {
            a.tempKey = t.key; a.target = v[t.key]?.doubleValue; a.tempIsFloat = t.format == "float"
            if let r = t.range, r.count >= 2 { a.minT = r[0]; a.maxT = r[1]; if r.count > 2 { a.step = max(r[2], 0.5) } }
        }
        let fanSvc = spec.services.first { $0.name == "fan-control" } ?? svc
        if let f = fanSvc.prop("fan-level") {
            a.fanKey = f.key; a.fan = v[f.key]
            a.fans = (f.options ?? []).map { ACOption(label: trValue($0.description), value: .int($0.value)) }
        }
        if let s = fanSvc.prop("vertical-swing") ?? spec.prop(named: "vertical-swing") { a.swingKey = s.key; a.swing = v[s.key]?.boolValue }
        if let s = spec.prop(named: "sleep-mode"), s.format == "bool" { a.sleepKey = s.key; a.sleep = v[s.key]?.boolValue }
        if let e = spec.services.first(where: { $0.name == "environment" })?.prop("temperature") { a.roomTemp = v[e.key]?.doubleValue }
        if let p = spec.prop(named: "electric-power") { a.loadPower = v[p.key]?.doubleValue }
        return a
    }
}
