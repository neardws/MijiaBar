import SwiftUI
import AppKit
import MijiaCore

// MARK: - 非空调设备的统一卡片：与空调卡片同一套布局
// 头部（状态 + 右上角电源）→ 动画主视觉 → 大号主数值 → 渐变滑条 → 读数 → 底部功能按钮 → 更多设置

func unitText(_ p: SpecProperty) -> String {
    switch p.unit {
    case "celsius": return "°C"
    case "percentage": return "%"
    case "kelvin": return "K"
    case "watt": return "W"
    case "kWh": return "kWh"
    case "lux": return "lx"
    case "minutes": return L("分钟", "min")
    case "seconds": return L("秒", "s")
    case "hours": return L("小时", "h")
    case nil, "none": return ""
    default: return p.unit ?? ""
    }
}

func displayValue(_ p: SpecProperty, _ v: PropValue?) -> String {
    guard let v, v != .null else { return "--" }
    if let ops = p.options, let d = v.doubleValue, let o = ops.first(where: { $0.value == Int(d) }) { return trValue(o.description) }
    if p.format == "bool" { return v.boolValue == true ? L("开", "On") : L("关", "Off") }
    return "\(v)"
}

func propIcon(_ name: String) -> String {
    switch name {
    case "mode": return "slider.horizontal.3"
    case "color-temperature": return "thermometer.sun"
    case "brightness": return "sun.max"
    case "horizontal-swing", "horizontal-angle": return "arrow.left.and.right"
    case "vertical-swing": return "arrow.up.and.down"
    case "physical-controls-locked": return "lock"
    case "alarm": return "bell"
    case "indicator-light", "screen": return "light.max"
    case "sleep-mode": return "moon.zzz"
    case "fan-level", "speed-level": return "wind"
    case "countdown-time", "delay": return "timer"
    case "heat-level": return "flame"
    case "target-humidity", "relative-humidity": return "humidity"
    case "temperature", "target-temperature": return "thermometer.medium"
    case "electric-power": return "bolt"
    case "battery-level": return "battery.75"
    case "power-consumption": return "chart.bar.fill"
    case "default-power-on-state": return "arrow.clockwise.circle"
    case "on": return "power"
    case "volume": return "speaker.wave.2"
    default: return "circle.grid.2x2"
    }
}

struct CardModel {
    var power: (key: String, on: PropValue, off: PropValue, isOn: Bool)?
    var primary: SpecProperty?
    var slider: SpecProperty?
    var readouts: [SpecProperty] = []
    var tiles: [SpecProperty] = []
    var rest: [SpecProperty] = []
    var actions: [SpecAction] = []
    var gradient: [Color]
    var tint: Color

    static let primaryNames: [DeviceCategory: [String]] = [
        .light: ["brightness", "color-temperature"],
        .fan: ["fan-level", "speed-level", "fan-percent", "speed"],
        .heater: ["target-temperature", "heat-level", "temperature"],
        .dehumidifier: ["target-humidity", "relative-humidity"],
        .plug: ["electric-power", "power-consumption", "temperature"],
        .sensor: ["temperature", "relative-humidity", "illumination", "battery-level"],
        .speaker: ["volume"], .tv: ["volume"],
        .airPurifier: ["pm2.5-density", "air-quality-index", "fan-level"],
    ]
    static let readoutNames = ["temperature", "relative-humidity", "electric-power", "power-consumption", "battery-level",
                               "illumination", "pm2.5-density", "filter-life-level", "voltage", "electric-current"]
    static let skipTiles: Set<String> = ["fault", "status"]

    init(device: Device, state: DeviceState, power: (key: String, on: PropValue, off: PropValue, isOn: Bool)?) {
        self.power = power
        let cat = device.category
        tint = cat.color
        switch cat {
        case .light: gradient = [Color(red: 0.55, green: 0.45, blue: 0.3), Color(red: 1, green: 0.78, blue: 0.35), Color(red: 1, green: 0.95, blue: 0.82)]
        case .heater: gradient = [Color(red: 0.25, green: 0.55, blue: 1), Color(red: 1, green: 0.85, blue: 0.4), Color(red: 1, green: 0.45, blue: 0.15)]
        case .dehumidifier: gradient = [Color(red: 1, green: 0.7, blue: 0.35), Color(red: 0.4, green: 0.85, blue: 0.95), Color(red: 0.2, green: 0.45, blue: 1)]
        case .fan: gradient = [Color(red: 0.55, green: 0.9, blue: 0.85), .teal, Color(red: 0.2, green: 0.5, blue: 0.9)]
        default: gradient = [cat.color.opacity(0.35), cat.color]
        }
        guard let spec = state.spec else { return }
        let all = spec.controlServices.flatMap(\.properties).filter { ($0.readable || $0.writable) && zhHas($0.name) }
        let pk = power?.key
        let candidates = all.filter { $0.key != pk && $0.format != "string" }
        for n in Self.primaryNames[cat] ?? [] { if let p = candidates.first(where: { $0.name == n }) { primary = p; break } }
        if primary == nil {
            primary = candidates.first { $0.writable && $0.isNumber && ($0.range != nil || $0.options != nil) && !Self.skipTiles.contains($0.name) }
                ?? candidates.first { $0.isNumber && $0.options == nil && !Self.skipTiles.contains($0.name) }
        }
        if let p = primary, p.writable, p.isNumber, (p.range?.count ?? 0) >= 2 || (p.options?.count ?? 0) >= 2 { slider = p }
        var used: Set<String> = [pk, primary?.key].compactMap { $0 }.reduce(into: []) { $0.insert($1) }
        readouts = Self.readoutNames.compactMap { n in all.first { $0.name == n && !used.contains($0.key) && !$0.writable } }.prefix(3).map { $0 }
        readouts.forEach { used.insert($0.key) }
        let tileable = all.filter { p in
            !used.contains(p.key) && p.writable && !Self.skipTiles.contains(p.name) && p.name != primary?.name &&
            (p.format == "bool" || (p.options?.isEmpty == false) || (p.isNumber && (p.range?.count ?? 0) >= 2))
        }
        // 优先常用属性
        let order = ["mode", "color-temperature", "fan-level", "horizontal-swing", "vertical-swing", "sleep-mode", "heat-level", "physical-controls-locked", "alarm", "indicator-light"]
        let sorted = tileable.sorted { (order.firstIndex(of: $0.name) ?? 99) < (order.firstIndex(of: $1.name) ?? 99) }
        var seen: Set<String> = []
        tiles = Array(sorted.filter { seen.insert(Self.label($0, spec)).inserted }.prefix(4))
        tiles.forEach { used.insert($0.key) }
        rest = all.filter { !used.contains($0.key) && !Self.skipTiles.contains($0.name) }
        actions = spec.controlServices.flatMap(\.actions).filter { $0.inputs.isEmpty && zhHas($0.name) }
    }

    /// 属性显示名：非主服务里的 on/mode 用服务名区分（如「指示灯」）
    static func label(_ p: SpecProperty, _ spec: DeviceSpec?) -> String {
        let svc = spec?.services.first { $0.iid == p.siid }
        let main = spec?.mainOnProperty?.siid
        if let svc, p.siid != main, ["on", "mode"].contains(p.name) || svc.name == p.name {
            let s = zhName(svc.name, fallback: svc.description)
            return p.name == "mode" ? s + zhName("mode", fallback: "mode") : s
        }
        return zhName(p.name, fallback: p.description)
    }
    /// 滑条的取值范围（枚举属性用选项值）
    func sliderRange(_ p: SpecProperty) -> (ClosedRange<Double>, Double) {
        if let r = p.range, r.count >= 2 { return (r[0]...max(r[1], r[0] + 1), r.count > 2 && r[2] > 0 ? r[2] : 1) }
        let vals = (p.options ?? []).map { Double($0.value) }
        return ((vals.min() ?? 0)...max(vals.max() ?? 1, (vals.min() ?? 0) + 1), 1)
    }
}

struct DeviceCardView: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    let state: DeviceState
    @State private var drag: Double?

    /// 规格驱动的通用卡片（没有专门页面的设备）：和其他详情页一样用 TypeShell + BigValue + Readout + 磁贴
    var body: some View {
        let c = CardModel(device: device, state: state, power: m.powerInfo(device))
        let isOn = c.power?.isOn ?? device.isOnline
        let tint = c.tint
        let primaryValue: Double? = c.primary.flatMap { state.values[$0.key]?.doubleValue }
        TypeShell(device: device, tint: tint, isOn: isOn, title: statusTitle(c, isOn), subtitle: statusLine(c),
                  powerOn: c.power?.isOn, onPower: c.power.map { p in { m.write(device, p.key, p.isOn ? p.off : p.on) } }) {
            if device.category == .airPurifier {
                let fan = state.spec?.controlServices.flatMap(\.properties).first { $0.name == "fan-level" }
                AirPurifierArt(on: isOn, level: fan.map { propFraction($0, state.values[$0.key]?.doubleValue) } ?? 0.5, tint: tint)
            } else {
                GenericArt(on: isOn, tint: tint)
            }
        } content: {
            if let p = c.primary {
                BigValue(value: drag.map { displayValue(p, .double($0)) } ?? displayValue(p, state.values[p.key]),
                         unit: p.options == nil ? unitText(p) : "", caption: zhName(p.name, fallback: p.description), dim: !isOn,
                         number: p.options == nil ? (drag ?? primaryValue) : nil)
                    .animation(drag == nil ? Motion.snappy : nil, value: drag ?? primaryValue ?? 0)   // 拖动时 1:1 跟手，不加动画
            }
            if let s = c.slider {
                let (r, step) = c.sliderRange(s)
                GradientSlider(value: drag ?? primaryValue ?? r.lowerBound, range: r, step: step, colors: c.gradient, enabled: isOn,
                               minLabel: displayValue(s, .double(r.lowerBound)) + (s.options == nil ? unitText(s) : ""),
                               maxLabel: displayValue(s, .double(r.upperBound)) + (s.options == nil ? unitText(s) : ""),
                               onChange: { drag = $0 },
                               onCommit: { v in drag = nil; if v != primaryValue { m.write(device, s.key, PropValue.double(v).coerced(to: s.format)) } },
                               a11yLabel: zhName(s.name, fallback: s.description))
            }
            if !c.readouts.isEmpty {
                HStack(spacing: 8) {
                    ForEach(c.readouts, id: \.key) { p in
                        Readout(icon: propIcon(p.name), text: displayValue(p, state.values[p.key]) + unitText(p), tint: tint).help(CardModel.label(p, state.spec))
                    }
                }
            }
            if !c.tiles.isEmpty {
                HStack(spacing: 8) { ForEach(c.tiles, id: \.key) { p in tile(p, tint: tint, isOn: isOn) } }
            }
            if !c.rest.isEmpty || !c.actions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("更多", "More")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    ForEach(c.rest, id: \.key) { p in PropRow(device: device, prop: p, value: state.values[p.key]) }
                    if !c.actions.isEmpty {
                        HStack { ForEach(c.actions, id: \.key) { a in Button(zhName(a.name, fallback: a.description)) { m.runAction(device, a) } } }
                    }
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.tile))
            }
            if state.spec == nil {
                Text(L("这个型号在 miot-spec.org 上没有公开规格，暂时只能查看在线状态。", "No public MIoT spec for this model."))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }

    func statusTitle(_ c: CardModel, _ isOn: Bool) -> String {
        if let p = c.power { return p.isOn ? L("已开启", "On") : L("已关闭", "Off") }
        return device.isOnline ? L("在线", "Online") : L("离线", "Offline")
    }
    func statusLine(_ c: CardModel) -> String {
        var parts = [zhCategory(device.category)]
        if let p = c.tiles.first(where: { $0.name == "mode" }) { parts.append(displayValue(p, state.values[p.key])) }
        if let r = c.readouts.first { parts.append(displayValue(r, state.values[r.key]) + unitText(r)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder func tile(_ p: SpecProperty, tint: Color, isOn: Bool) -> some View {
        let title = CardModel.label(p, state.spec)
        let v = state.values[p.key]
        if p.format == "bool" {
            ToggleTile(title: title, icon: propIcon(p.name), isOn: v?.boolValue ?? false, tint: tint) {
                m.write(device, p.key, .bool(!(v?.boolValue ?? false)))
            }
        } else if let ops = p.options, !ops.isEmpty {
            MenuTile(title: title, value: displayValue(p, v), icon: propIcon(p.name), active: isOn, tint: tint) {
                OptionPicker(options: ops.map { (trValue($0.description), $0.value) }, selection: v?.doubleValue.map { Int($0) }) {
                    m.write(device, p.key, .int($0))
                }
            }
        } else if let r = p.range, r.count >= 2 {
            let presets = presetValues(p, r)
            MenuTile(title: title, value: displayValue(p, v) + unitText(p), icon: propIcon(p.name), active: isOn, tint: tint) {
                ForEach(presets, id: \.1) { label, val in
                    Button(label) { m.write(device, p.key, PropValue.double(val).coerced(to: p.format)) }
                }
            }
        }
    }

    func presetValues(_ p: SpecProperty, _ r: [Double]) -> [(String, Double)] {
        if p.name == "color-temperature" {
            return [(L("暖光", "Warm"), 2700.0), (L("自然光", "Neutral"), 4000.0), (L("冷白", "Cool"), 6500.0)]
                .map { ($0.0 + " \(Int(min(max($0.1, r[0]), r[1])))K", min(max($0.1, r[0]), r[1])) }
        }
        let step = r.count > 2 && r[2] > 0 ? r[2] : 1
        return (0...4).map { i in
            let v = ((r[0] + (r[1] - r[0]) * Double(i) / 4) / step).rounded() * step
            return ("\(PropValue.double(v))\(unitText(p))", v)
        }
    }
}

func zhCategory(_ c: DeviceCategory) -> String {
    switch c {
    case .ac: return L("空调", "Air conditioner")
    case .plug: return L("插座 / 开关", "Plug / switch")
    case .light: return L("灯", "Light")
    case .fan: return L("风扇", "Fan")
    case .heater: return L("取暖器", "Heater")
    case .dehumidifier: return L("除湿机", "Dehumidifier")
    case .sensor: return L("传感器", "Sensor")
    case .tv: return L("电视", "TV")
    case .camera: return L("摄像机", "Camera")
    case .speaker: return L("音箱", "Speaker")
    case .kitchen: return L("厨房电器", "Kitchen")
    case .printer: return L("打印机", "Printer")
    case .purifier: return L("净水器", "Water purifier")
    case .other: return L("设备", "Device")
    case .airPurifier: return L("空气净化器", "Air purifier")
    }
}

struct GradientSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let colors: [Color]
    let enabled: Bool
    let minLabel: String, maxLabel: String
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void
    var a11yLabel = ""
    /// 拖动中 1:1 跟手，松手后吸附到档位；跨档时触控板轻触反馈（与 PR #1 的 TempSlider 一致）
    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var lastStep: Double?

    func snap(_ f: Double) -> Double {
        let v = range.lowerBound + max(0, min(1, f)) * (range.upperBound - range.lowerBound)
        return min(range.upperBound, max(range.lowerBound, (v / step).rounded() * step))
    }
    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width, knob: CGFloat = 24
                let dragging = dragFraction != nil
                let f = dragFraction ?? max(0, min(1, (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 1)))
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)).frame(height: 8).opacity(enabled ? 1 : 0.3)
                        .scaleEffect(x: 1, y: dragging || hovering ? 1.25 : 1)
                    Circle().fill(Color.white).overlay(Circle().stroke(Color.black.opacity(0.12)))
                        .frame(width: knob, height: knob).shadow(color: .black.opacity(dragging ? 0.4 : 0.3), radius: dragging ? 6 : 4, y: 1)
                        .scaleEffect(dragging ? 1.08 : 1)
                        .offset(x: CGFloat(f) * (w - knob))
                }
                .frame(height: knob)
                .animation(dragging ? nil : Motion.snappy, value: f)
                .animation(Motion.press, value: dragging)
                .animation(Motion.snappy, value: hovering)
                .contentShape(Rectangle())
                .onHover { hovering = $0 && enabled }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let raw = max(0, min(1, Double((v.location.x - knob / 2) / (w - knob))))
                        dragFraction = raw
                        let s = snap(raw)
                        if s != lastStep, lastStep != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                        lastStep = s
                        onChange(s)
                    }
                    .onEnded { v in
                        let s = snap(Double((v.location.x - knob / 2) / (w - knob)))
                        dragFraction = nil; lastStep = nil
                        onCommit(s)
                    })
                .allowsHitTesting(enabled)
            }
            .frame(height: 24)
            .accessibilityElement()
            .accessibilityLabel(a11yLabel)
            .accessibilityValue(PropValue.double(value).description)
            .accessibilityAdjustableAction { dir in
                guard enabled else { return }
                onCommit(min(range.upperBound, max(range.lowerBound, value + (dir == .increment ? step : -step))))
            }
            HStack { Text(minLabel); Spacer(); Text(maxLabel) }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
