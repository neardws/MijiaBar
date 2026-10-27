import SwiftUI
import MijiaCore

/// 详情卡片内容区的固定宽度：弹窗 360 − 两侧 12 外边距
let cardWidth: CGFloat = 336

/// 读取 MIoT 属性的小工具
struct DC {
    let device: Device
    let state: DeviceState
    var spec: DeviceSpec? { state.spec }
    func p(_ name: String, in svc: String? = nil) -> SpecProperty? {
        spec?.controlServices.filter { svc == nil || $0.name == svc }.lazy.compactMap { $0.prop(name) }.first
    }
    func a(_ name: String, in svc: String? = nil) -> SpecAction? {
        spec?.controlServices.filter { svc == nil || $0.name == svc }.lazy.compactMap { s in s.actions.first { $0.name == name } }.first
    }
    func v(_ p: SpecProperty?) -> PropValue? {
        guard let p, let x = state.values[p.key], x != .null else { return nil }
        return x
    }
    func num(_ p: SpecProperty?) -> Double? { v(p)?.doubleValue }
    func bool(_ p: SpecProperty?) -> Bool? { v(p)?.boolValue }
    /// 译好的显示文本；没有读数返回 nil
    func text(_ p: SpecProperty?) -> String? {
        guard let p, let x = v(p) else { return nil }
        return displayValue(p, x)
    }
    func label(_ p: SpecProperty) -> String { CardModel.label(p, spec) }
}

/// 所有设备详情共用的外壳：头部状态 + 右上角电源 → 拟物插画 → 内容
struct TypeShell<Art: View, Content: View>: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    let tint: Color
    let isOn: Bool
    let title: String
    let subtitle: String
    var powerOn: Bool? = nil
    var onPower: (() -> Void)? = nil
    /// 插画区有可操作内容（如直播画面）时为 true，由插画自己隐藏装饰部分
    var artInteractive = false
    @ViewBuilder let art: () -> Art
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.system(size: Theme.TypeSize.callout, weight: .semibold)).lineLimit(1).contentTransition(.numericText())
                        Text(subtitle).font(.system(size: Theme.TypeSize.caption)).foregroundStyle(.secondary).lineLimit(1).contentTransition(.numericText())
                    }
                    Spacer(minLength: 4)
                    if let onPower {
                        PowerButton(on: powerOn ?? false, tint: tint, action: onPower).help(L("开关（空格）", "Power (Space)"))
                    }
                }
                art().frame(height: 136).frame(maxWidth: .infinity).accessibilityHidden(!artInteractive)
                    .saturation(isOn ? 1 : 0.85).animation(Motion.smooth, value: isOn)
                content().environment(\.cardAccent, isOn ? tint : nil)
            }
            .padding(18)
            .frame(width: cardWidth)
            .background {
                // 与空调卡片一致：开启时顶部柔光 + 色调描边
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                shape.fill(LinearGradient(colors: [tint.opacity(isOn ? 0.24 : 0.06), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .overlay(alignment: .top) {
                        Rectangle().fill(EllipticalGradient(colors: [tint.opacity(0.4), tint.opacity(0)])).frame(width: cardWidth, height: 220).offset(y: -80)
                            .opacity(isOn ? 1 : 0)
                    }
                    .clipShape(shape)
                    .overlay(shape.stroke(LinearGradient(colors: [isOn ? tint.opacity(0.45) : Theme.stroke, Theme.stroke.opacity(0.4)],
                                                         startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .allowsHitTesting(false)   // 同空调卡片：柔光超出卡片，不能挡住点击
            }
            .animation(Motion.smooth, value: isOn)
        }
        .scrollIndicators(.never)
        .frame(width: cardWidth)
        .probe(device.model)
    }
}

/// 大号主数值；没有读数时显示中性占位
/// 详情卡片的强调色：TypeShell 在设备开着时设置，卡片里的大号数值据此做与空调温度一致的色调渐变和光晕
private struct CardAccentKey: EnvironmentKey { static let defaultValue: Color? = nil }
extension EnvironmentValues {
    var cardAccent: Color? { get { self[CardAccentKey.self] } set { self[CardAccentKey.self] = newValue } }
}

struct BigValue: View {
    @Environment(\.cardAccent) private var accent
    let value: String?
    var unit: String = ""
    let caption: String
    var dim = false
    /// 数值本身：数字滚动时按增减方向翻动
    var number: Double? = nil
    var body: some View {
        VStack(spacing: 2) {
            if let value {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value).font(.system(size: value.filter(\.isNumber).count > 4 || value.count > 6 ? 40 : 60, weight: .thin, design: .rounded))
                        .monospacedDigit().contentTransition(number.map { .numericText(value: $0) } ?? .numericText()).lineLimit(1).minimumScaleFactor(0.5)
                        .foregroundStyle(LinearGradient(colors: [.primary, .primary, accent.map { dim ? Color.primary : $0 } ?? .primary], startPoint: .top, endPoint: .bottom))
                        .shadow(color: (dim ? nil : accent)?.opacity(0.4) ?? .clear, radius: 20)
                    if !unit.isEmpty { Text(unit).font(.system(size: 18, weight: .light)).foregroundStyle(.secondary) }
                }
            } else {
                Text(L("暂无读数", "No reading")).font(.system(size: 20, weight: .light)).foregroundStyle(.tertiary).frame(height: 60)
            }
            Text(caption).font(.system(size: Theme.TypeSize.caption)).foregroundStyle(.secondary)
        }
        .opacity(dim ? 0.45 : 1)
        .accessibilityElement(children: .combine)   // 读作「目标温度，24°」而不是两段
        .animation(Motion.snappy, value: value)
        .animation(Motion.smooth, value: dim)
        .frame(maxWidth: .infinity)
    }
}

struct Readout: View {
    let icon: String, text: String, tint: Color
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: Theme.TypeSize.caption)).foregroundStyle(tint)
            Text(text).font(.system(size: Theme.TypeSize.body, weight: .medium)).monospacedDigit().lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Capsule().fill(Theme.tile))
    }
}

/// 一排读数胶囊（自动过滤掉没有读数的项）
struct ReadoutRow: View {
    let items: [(String, String?)]
    let tint: Color
    var body: some View {
        let shown = items.compactMap { i in i.1.map { (i.0, $0) } }
        if !shown.isEmpty {
            HStack(spacing: 8) { ForEach(Array(shown.enumerated()), id: \.offset) { _, x in Readout(icon: x.0, text: x.1, tint: tint) } }
        }
    }
}

/// 音量控制：− 滑条 + 和静音
struct VolumeControl: View {
    let value: Double?
    let range: ClosedRange<Double>
    let tint: Color
    let enabled: Bool
    let onSet: (Double) -> Void
    @State private var drag: Double?
    var body: some View {
        let cur = drag ?? value ?? range.lowerBound
        VStack(spacing: 6) {
            HStack {
                Text(L("音量", "Volume")).font(.system(size: Theme.TypeSize.caption, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(value == nil && drag == nil ? L("未读取到", "Unknown") : "\(Int(cur))")
                    .font(.system(size: Theme.TypeSize.body, weight: .medium)).monospacedDigit().foregroundStyle(value == nil ? .tertiary : .primary)
            }
            HStack(spacing: 10) {
                stepButton("speaker.minus.fill", -5)
                GradientSlider(value: cur, range: range, step: 1, colors: [tint.opacity(0.35), tint], enabled: enabled && value != nil,
                               minLabel: "", maxLabel: "", onChange: { drag = $0 }, onCommit: { v in drag = nil; onSet(v) }, a11yLabel: L("音量", "Volume"))
                    .frame(height: 24).padding(.top, 10)
                stepButton("speaker.plus.fill", 5)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.lg).fill(Theme.tile))
    }
    func stepButton(_ icon: String, _ d: Double) -> some View {
        Button { if let v = value { onSet(min(range.upperBound, max(range.lowerBound, v + d))) } } label: {
            Image(systemName: icon).font(.system(size: Theme.TypeSize.callout, weight: .semibold)).frame(width: 30, height: 30)
                .background(Circle().fill(Theme.tile))
        }.buttonStyle(.pressable(0.92)).hoverHighlight().disabled(!enabled || value == nil)
    }
}

/// 卡片里的整行主按钮（看直播、重试）：与磁贴同圆角、同描边；不可用时同尺寸的灰色禁用态
struct WideButtonFace: View {
    let title: String, icon: String, tint: Color
    var enabled = true
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
        Label(title, systemImage: icon)
            .font(.system(size: Theme.TypeSize.callout, weight: enabled ? .semibold : .medium))
            .contentTransition(.symbolEffect(.replace))
            .foregroundStyle(enabled ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(shape.fill(enabled ? tint.opacity(0.16) : Theme.tile))
            .overlay(shape.stroke(enabled ? tint.opacity(0.3) : Theme.stroke))
            .contentShape(shape)
            .keyboardFocusChrome(shape, enabled: enabled)
    }
}

struct ActionTile: View {
    let title: String, icon: String, tint: Color
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            TileFace(title: title, value: "", icon: icon, active: active, tint: tint)
        }.buttonStyle(.pressable).detailKeyboardAction(action).accessibilityLabel(title)
    }
}

/// 根据属性生成底部按钮：布尔 → 开关；枚举 → 菜单；数值 → 预设菜单
struct PropTile: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    let prop: SpecProperty?
    let title: String
    let icon: String
    let tint: Color
    var body: some View {
        if let p = prop {
            let v = dc.v(p)
            if p.format == "bool" {
                ToggleTile(title: title, icon: icon, isOn: v?.boolValue ?? false, tint: tint) {
                    m.write(dc.device, p.key, .bool(!(v?.boolValue ?? false)))
                }
            } else if let ops = p.options, !ops.isEmpty, p.writable {
                MenuTile(title: title, value: dc.text(p) ?? "—", icon: icon, active: v != nil, tint: tint) {
                    OptionPicker(options: ops.map { (trValue($0.description), $0.value) }, selection: v?.doubleValue.map { Int($0) }) {
                        m.write(dc.device, p.key, .int($0))
                    }
                }
            } else {
                TileFace(title: title, value: (dc.text(p) ?? "—") + unitText(p), icon: icon, active: false, tint: tint)
            }
        }
    }
}

/// 色温 → 显示颜色
func kelvinColor(_ k: Double) -> Color {
    let t = max(0, min(1, (k - 2700) / (6500 - 2700)))
    return Color(red: 1 - 0.18 * t, green: 0.74 + 0.18 * t, blue: 0.42 + 0.58 * t)
}

func propRange(_ p: SpecProperty) -> (ClosedRange<Double>, Double) {
    if let r = p.range, r.count >= 2 { return (r[0]...max(r[1], r[0] + 1), r.count > 2 && r[2] > 0 ? r[2] : 1) }
    let vals = (p.options ?? []).map { Double($0.value) }
    return ((vals.min() ?? 0)...max(vals.max() ?? 1, (vals.min() ?? 0) + 1), 1)
}
func propFraction(_ p: SpecProperty?, _ v: Double?) -> Double {
    guard let p, let v else { return 0 }
    let (r, _) = propRange(p)
    return max(0, min(1, (v - r.lowerBound) / (r.upperBound - r.lowerBound)))
}
func zhHas(_ n: String) -> Bool { !isChinese || zhName(n, fallback: "\u{1}") != "\u{1}" }

struct PropSlider: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    let prop: SpecProperty
    let colors: [Color]
    let enabled: Bool
    @State private var drag: Double?
    var body: some View {
        let (r, step) = propRange(prop)
        let cur = drag ?? dc.num(prop) ?? r.lowerBound
        let u = prop.options == nil ? unitText(prop) : ""
        GradientSlider(value: cur, range: r, step: step, colors: colors, enabled: enabled && dc.v(prop) != nil,
                       minLabel: displayValue(prop, .double(r.lowerBound)) + u, maxLabel: displayValue(prop, .double(r.upperBound)) + u,
                       onChange: { drag = $0 },
                       onCommit: { v in
                           drag = nil
                           if v != dc.num(prop) { m.write(dc.device, prop.key, PropValue.double(v).coerced(to: prop.format)) }
                       },
                       a11yLabel: dc.label(prop))
    }
}

/// 自定义预设菜单按钮
struct PresetTile: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    let prop: SpecProperty?
    let title: String, icon: String, tint: Color
    let presets: [(String, Double)]
    var body: some View {
        if let p = prop {
            let cur = dc.num(p)
            let curLabel = presets.min(by: { abs($0.1 - (cur ?? -1e9)) < abs($1.1 - (cur ?? -1e9)) }).map { $0.0 }
            MenuTile(title: title, value: cur == nil ? "—" : (curLabel ?? "—"), icon: icon, active: cur != nil, tint: tint) {
                ForEach(presets, id: \.1) { label, v in Button(label) { m.write(dc.device, p.key, PropValue.double(v).coerced(to: p.format)) } }
            }
        }
    }
}

func fmt1(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }

extension View {
    /// 布局探针：MIJIABAR_PROBE=1 时打印卡片在窗口中的水平范围，用于验证没有越界裁切
    func probe(_ name: String) -> some View {
        background(GeometryReader { g in
            Color.clear.onAppear {
                if ProcessInfo.processInfo.environment["MIJIABAR_PROBE"] != nil {
                    let f = g.frame(in: .global)
                    print("PROBE \(name) minX=\(f.minX) maxX=\(f.maxX) width=\(f.width)")
                }
            }
        })
    }
}

/// 详情页的主滑条属性（键盘 ←→ 调节用），与各页面上的滑条一一对应
@MainActor func primarySliderProp(_ dc: DC) -> SpecProperty? {
    switch dc.device.category {
    case .fan: return dc.spec?.controlServices.flatMap(\.properties).first { $0.name == "fan-level" && $0.options != nil } ?? dc.p("fan-level") ?? dc.p("speed-level")
    case .light: return dc.p("brightness")
    case .heater: return dc.p("target-temperature")
    case .dehumidifier: return dc.p("target-humidity")
    case .tv, .speaker: return dc.p("volume", in: "speaker") ?? dc.p("volume")
    default: return nil
    }
}
