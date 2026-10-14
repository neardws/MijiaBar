import SwiftUI
import AppKit
import MijiaCore

enum AirMode { case cool, heat, dry, fan, auto }

extension ACState {
    var airMode: AirMode {
        if isHeating { return .heat }
        if isCooling { return .cool }
        let l = modeLabel.lowercased()
        if modeLabel.contains("除湿") || l.contains("dry") { return .dry }
        if modeLabel.contains("送风") || l.contains("fan") || l.contains("wind") { return .fan }
        return .auto
    }
    /// 0…1：按风速档位在列表中的位置换算，自动档取中间偏上
    var fanSpeed: Double {
        func isAuto(_ s: String) -> Bool { s.contains("自动") || s.lowercased().contains("auto") }
        if isAuto(fanLabel) { return 0.65 }
        let levels = fans.filter { !isAuto($0.label) }
        guard levels.count > 1, let i = levels.firstIndex(where: { $0.value == fan }) else { return 0.6 }
        return 0.3 + 0.7 * Double(i) / Double(levels.count - 1)
    }
}

struct ACCardView: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    let ac: ACState
    @State private var dragTemp: Double?

    var temp: Double { dragTemp ?? ac.target ?? 24 }
    /// 0 = 冷 … 1 = 热：制冷始终偏蓝、制热始终偏橙，其余模式跟随温度
    var warmth: Double {
        let t = (temp - ac.minT) / max(ac.maxT - ac.minT, 1)
        if ac.isHeating { return max(0.9, t) }
        if ac.isCooling { return min(0.12, t) }
        return t
    }
    var tint: Color { ac.power ? Theme.warm(warmth) : Color.secondary }

    /// 标题说明空调在做什么；模式和风速已经在下方按钮里，不再重复
    var title: String {
        guard ac.power else { return L("已关机", "Off") }
        switch ac.airMode {
        case .cool: return L("制冷中", "Cooling")
        case .heat: return L("制热中", "Heating")
        case .dry: return L("除湿中", "Drying")
        case .fan: return L("送风中", "Fan only")
        case .auto: return L("自动运行", "Auto")
        }
    }
    var subtitle: String {
        let parts = [ac.roomTemp.map { L("室温 ", "Room ") + "\(PropValue.double($0))°" },
                     ac.loadPower.map { L("功率 ", "Power ") + "\(PropValue.double($0)) W" }].compactMap { $0 }
        return parts.isEmpty ? L("空调", "Air conditioner") : parts.joined(separator: " · ")
    }

    var body: some View {
        TypeShell(device: device, tint: tint, isOn: ac.power, title: title, subtitle: subtitle, powerOn: ac.power,
                  onPower: { m.write(device, ac.powerKey, ac.power ? ac.offValue : ac.onValue) }) {
            ACIllustration(on: ac.power, tint: tint, mode: ac.airMode, speed: ac.fanSpeed, swing: ac.swing == true)
        } content: {
            BigValue(value: fmt1(ac.step < 1 ? (temp * 2).rounded() / 2 : temp.rounded()) + "°", caption: L("目标温度", "Target temperature"),
                     dim: !ac.power, number: temp)

            TempSlider(value: temp, range: ac.minT...ac.maxT, step: ac.step, enabled: ac.tempKey != nil, on: ac.power,
                       onChange: { dragTemp = $0 },
                       onCommit: { v in
                           dragTemp = nil
                           if let k = ac.tempKey, v != ac.target { m.write(device, k, ac.tempValue(v)) }
                       })
                .help(L("拖动调节，或用 ← → 键", "Drag, or use the ← → keys"))

            HStack(spacing: 8) {
                MenuTile(title: L("模式", "Mode"), value: ac.modeLabel, icon: modeIcon, active: ac.power, tint: tint) {
                    OptionPicker(options: ac.modes.map { ($0.label, $0.value) }, selection: ac.mode) { v in if let k = ac.modeKey { m.write(device, k, v) } }
                }
                MenuTile(title: L("风速", "Fan"), value: ac.fanLabel, icon: "wind", active: ac.power, tint: tint) {
                    OptionPicker(options: ac.fans.map { ($0.label, $0.value) }, selection: ac.fan) { v in if let k = ac.fanKey { m.write(device, k, v) } }
                }
                // 设备不支持的功能直接不显示，剩下的按钮平分宽度
                if ac.sleepKey != nil {
                    ToggleTile(title: L("睡眠", "Sleep"), icon: "moon.zzz", isOn: ac.sleep, tint: tint) {
                        if let k = ac.sleepKey { m.write(device, k, .bool(!(ac.sleep ?? false))) }
                    }
                }
                if ac.swingKey != nil {
                    ToggleTile(title: L("扫风", "Swing"), icon: "arrow.up.and.down", isOn: ac.swing, tint: tint) {
                        if let k = ac.swingKey { m.write(device, k, (ac.swing ?? false) ? ac.swingOff : ac.swingOn) }
                    }
                }
            }
            .animation(Motion.snappy, value: ac.mode)
            .animation(Motion.snappy, value: ac.fan)
            if ac.loadPower != nil { PowerHistoryCard(device: device, tint: tint) }
        }
        .animation(Motion.smooth, value: warmth)
    }

    var modeIcon: String {
        switch ac.airMode {
        case .heat: return "sun.max"
        case .cool: return "snowflake"
        case .dry: return "drop"
        case .fan: return "fan"
        case .auto: return "a.circle"
        }
    }
}

struct PowerButton: View {
    let on: Bool
    let tint: Color
    var size: CGFloat = 40
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "power").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(on ? Color.white : Color.primary)
                .frame(width: size, height: size)
                .background {
                    ZStack {
                        Circle().fill(Theme.tile)
                        Circle().fill(tint).opacity(on ? 1 : 0)
                        Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)).opacity(on ? 1 : 0)
                    }
                }
                .shadow(color: on ? tint.opacity(0.6) : .clear, radius: 10)
                .ripple(on, color: on ? tint : .secondary)
        }
        .buttonStyle(.pressable(0.95)).hoverHighlight()
        .powerAccessibility(on)
    }
}

/// 空调插画：与风扇、灯泡同一套「产品渲染」风格。
/// 气流是从出风口扇形铺开的柔和气帘和流线（不再是波浪线），随模式、风速、扫风变化。
struct ACIllustration: View {
    let on: Bool
    let tint: Color
    var mode: AirMode = .auto
    var speed: Double = 0.6
    var swing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PowerTimeline(on: on, running: true) { t, k in
            VStack(spacing: 0) {
                unit(t: t, k: k)
                Canvas { ctx, size in draw(&ctx, size, t: t, k: k) }.frame(height: 72)
            }
            .frame(width: 300, height: 136)
        }
    }

    /// 扫风时导风板和气流一起上下摆动（-1…1）
    func sway(_ t: Double) -> Double { swing && !reduceMotion ? sin(t * 1.1) : 0 }

    func unit(t: Double, k: Double) -> some View {
        // 导风板开合角度（度），扫风时摆动；按正弦换算成可见高度
        let flap = (36 + 20 * sway(t)) * k
        let flapH = 2 + 5 * sin(flap * .pi / 180)
        let shell = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            shell.appliance(tint, k).overlay(shell.stroke(Color.black.opacity(0.08))).frame(width: 230, height: 58)
            RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.07)).frame(width: 150, height: 2).offset(y: -6)
            // 出风口 + 导风板
            RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.22)).frame(width: 190, height: 6 + 2 * k).offset(y: 17 + k)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient(colors: [Color(white: 0.70), Color(white: 0.96)], startPoint: .top, endPoint: .bottom))
                .frame(width: 186 - 4 * k, height: flapH)
                .offset(y: 19 + 2 * k + flapH / 2)
                .opacity(k)
            // 指示灯
            Circle().fill(on ? tint : Color.gray.opacity(0.6)).frame(width: 5, height: 5).offset(x: 98, y: -14)
                .shadow(color: on ? tint : .clear, radius: 3)
        }
        .frame(height: 64)
        .background { Ambient(tint, k * 0.85, width: 320, height: 120).offset(y: 30) }
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double, k: Double) {
        guard k > 0.01 else { return }
        let cx = Double(size.width) / 2, h = Double(size.height)
        let tilt = 0.28 * sway(t)               // 扫风带来的整体偏转
        let rate = 0.3 + 0.7 * speed            // 气流速度
        let reach = (0.55 + 0.45 * speed) * h   // 风越大吹得越远
        let half = 92.0                          // 出风口半宽
        // 出风口上任一点的水平位置：越往下越向外扩散，并随扫风偏转
        func x(_ u: Double, _ y: Double) -> Double { cx + u * (half + 0.55 * y) + y * tan(tilt) }

        // 气帘：从出风口铺开、向下渐隐的一层淡色
        var curtain = Path()
        curtain.move(to: CGPoint(x: x(-1, 0), y: 0)); curtain.addLine(to: CGPoint(x: x(1, 0), y: 0))
        curtain.addLine(to: CGPoint(x: x(1, reach), y: reach)); curtain.addLine(to: CGPoint(x: x(-1, reach), y: reach)); curtain.closeSubpath()
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 8))   // 边缘羽化，像一团空气而不是一块梯形
            l.fill(curtain, with: .linearGradient(Gradient(colors: [tint.opacity(0.34 * k), tint.opacity(0)]),
                                                  startPoint: CGPoint(x: cx, y: 0), endPoint: CGPoint(x: cx, y: reach)))
        }

        // 流线：沿扩散方向向下滑动的细线，两端渐隐
        let n = 9, len = 16 + 14 * speed
        for i in 0..<n {
            let u = (Double(i) / Double(n - 1)) * 2 - 1
            let ph = (t * rate + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            let y0 = ph * reach, y1 = min(reach, y0 + len)
            let a = k * sin(ph * .pi) * (1 - 0.35 * abs(u))
            var p = Path()
            p.move(to: CGPoint(x: x(u, y0), y: y0)); p.addLine(to: CGPoint(x: x(u, y1), y: y1))
            let shade = GraphicsContext.Shading.linearGradient(Gradient(colors: [tint.opacity(0), tint.opacity(0.85 * a), tint.opacity(0)]),
                                                               startPoint: CGPoint(x: x(u, y0), y: y0), endPoint: CGPoint(x: x(u, y1), y: y1))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 3))
                l.stroke(p, with: shade, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            }
            ctx.opacity = 0.7
            ctx.stroke(p, with: shade, style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            ctx.opacity = 1
        }

        // 模式粒子：制冷冰晶、制热暖光、除湿水滴，顺着气流方向飘出
        guard mode == .cool || mode == .heat || mode == .dry else { return }
        func frac(_ v: Double) -> Double { v - floor(v) }
        for i in 0..<12 {
            let seed = Double(i) * 12.9898
            let r1 = frac(sin(seed) * 43758.5453), r2 = frac(sin(seed * 1.7) * 24634.6345)
            let ph = frac(t * rate * (0.5 + 0.4 * r2) + r1)
            let y = (mode == .dry ? ph * ph : ph) * reach
            let px = x(r2 * 2 - 1, y), a = k * sin(ph * .pi)
            switch mode {
            case .cool:
                let s = 2.2 + 1.6 * r2, tw = 0.6 + 0.4 * sin(t * 5 + seed)
                ctx.fill(sparkle(CGPoint(x: px, y: y), s), with: .color(Color(red: 0.88, green: 0.96, blue: 1).opacity(a * tw)))
            case .heat:
                let r = 1.2 + 1.2 * r2
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 1.5))
                    l.fill(Path(ellipseIn: CGRect(x: px - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 1, green: 0.8, blue: 0.5).opacity(a * 0.9)))
                }
            default:
                ctx.fill(Path(ellipseIn: CGRect(x: px - 1.3, y: y - 1.8, width: 2.6, height: 3.6)), with: .color(Color(red: 0.55, green: 0.85, blue: 1).opacity(a * 0.85)))
            }
        }
    }

    func sparkle(_ c: CGPoint, _ s: Double) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - s))
        p.addQuadCurve(to: CGPoint(x: c.x + s, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + s), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x - s, y: c.y), control: c)
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - s), control: c)
        return p
    }
}

struct TempSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let enabled: Bool
    /// 空调关机时色带褪色（仍可预设温度）
    var on = true
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void
    /// 拖动中滑块 1:1 跟手（不吸附），松手后再吸附到档位
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
                let x = CGFloat(f) * (w - knob)
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.tile.opacity(enabled ? 1 : 0.5))
                        Capsule().fill(Theme.sliderGradient)
                            .mask(alignment: .leading) { Rectangle().frame(width: x + knob / 2) }
                            .saturation(on ? 1 : 0).opacity(!enabled ? 0.3 : on ? 1 : 0.45)
                    }
                    .frame(height: 8)
                    .scaleEffect(x: 1, y: dragging || hovering ? 1.25 : 1)
                    ZStack {
                        Circle().fill(Color.white).overlay(Circle().stroke(Color.black.opacity(0.12))).shadow(color: .black.opacity(dragging ? 0.4 : 0.3), radius: dragging ? 6 : 4, y: 1)
                        Circle().fill(on ? Theme.warm(f) : Color.secondary).frame(width: 9, height: 9)
                            .scaleEffect(dragging || hovering ? 1 : 0.6).opacity(dragging || hovering ? 1 : 0)
                    }
                    .frame(width: knob, height: knob)
                    .background {
                        Circle().fill(RadialGradient(colors: [Theme.warm(f).opacity(0.7), Theme.warm(f).opacity(0)], center: .center, startRadius: 8, endRadius: 22))
                            .frame(width: 44, height: 44).scaleEffect(dragging ? 1 : 0.8).opacity(dragging ? 1 : 0)
                    }
                    .scaleEffect(dragging ? 1.08 : 1)
                    .offset(x: x)
                }
                .frame(height: knob)
                .animation(dragging ? nil : Motion.snappy, value: f)
                .animation(Motion.press, value: dragging)
                .animation(Motion.snappy, value: hovering)
                .animation(Motion.smooth, value: on)
                .contentShape(Rectangle())
                .onHover { hovering = $0 && enabled }
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let raw = max(0, min(1, Double((v.location.x - knob / 2) / (w - knob))))
                        dragFraction = raw
                        let s = snap(raw)
                        // 每跨过一个档位给触控板一次轻触反馈，与数字变化同一帧
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
            .accessibilityLabel(L("目标温度", "Target temperature"))
            .accessibilityValue(PropValue.double(value).description + "°C")
            .accessibilityAdjustableAction { dir in
                guard enabled else { return }
                onCommit(min(range.upperBound, max(range.lowerBound, value + (dir == .increment ? step : -step))))
            }
            HStack {
                Text(fmt1(range.lowerBound) + "°"); Spacer(); Text(fmt1(range.upperBound) + "°")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct TileFace: View {
    let title: String, value: String, icon: String
    let active: Bool, tint: Color
    @State private var hovering = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).frame(height: 18)
                .contentTransition(.symbolEffect(.replace))
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background {
            ZStack {
                shape.fill(hovering ? Theme.hover : Theme.tile)
                shape.fill(tint.opacity(0.30)).opacity(active ? 1 : 0)
            }
        }
        .overlay(shape.stroke(active ? tint.opacity(0.4) : Theme.stroke))
        .shadow(color: active ? tint.opacity(0.22) : .clear, radius: 8, y: 2)
        .contentShape(shape)
        .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
        .animation(Motion.snappy, value: value)
        .animation(Motion.smooth, value: active)
    }
}

struct MenuTile<Content: View>: View {
    let title: String, value: String, icon: String
    let active: Bool, tint: Color
    @ViewBuilder let content: () -> Content
    var body: some View {
        Menu { content() } label: { TileFace(title: title, value: value, icon: icon, active: active, tint: tint) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel(title).accessibilityValue(value)
    }
}

struct ToggleTile: View {
    let title: String, icon: String
    let isOn: Bool?
    let tint: Color
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            TileFace(title: title, value: isOn == nil ? L("不支持", "N/A") : (isOn! ? L("开", "On") : L("关", "Off")),
                     icon: icon, active: isOn == true, tint: tint)
        }
        .buttonStyle(.pressable).disabled(isOn == nil).opacity(isOn == nil ? 0.45 : 1)
        .accessibilityLabel(title)
        .accessibilityValue(isOn == nil ? L("不支持", "Not supported") : (isOn! ? L("开", "On") : L("关", "Off")))
    }
}
