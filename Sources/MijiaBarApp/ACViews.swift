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
    var warmth: Double {
        let t = (temp - ac.minT) / max(ac.maxT - ac.minT, 1)
        if ac.isHeating { return max(0.7, t) }
        if ac.isCooling { return min(0.3, t) }
        return t
    }
    var tint: Color { ac.power ? Theme.warm(warmth) : Color(white: 0.45) }

    var topLabel: String {
        if let r = ac.roomTemp { return L("室温 ", "Room ") + "\(PropValue.double(r))°" }
        if let p = ac.loadPower { return L("功率 ", "Power ") + "\(PropValue.double(p)) W" }
        return m.displayName(device)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(topLabel).font(.system(size: 13, weight: .semibold)).contentTransition(.numericText())
                    Text(ac.power ? "\(ac.modeLabel) · \(L("风速", "Fan")) \(ac.fanLabel)" : L("已关机", "Off"))
                        .font(.system(size: 11)).foregroundStyle(.secondary).contentTransition(.numericText())
                }
                Spacer()
                PowerButton(on: ac.power, tint: tint) { m.write(device, ac.powerKey, ac.power ? ac.offValue : ac.onValue) }
                    .help(L("开关（空格）", "Power (Space)"))
            }

            ACIllustration(on: ac.power, tint: tint, mode: ac.airMode, speed: ac.fanSpeed, swing: ac.swing == true)
                .frame(height: 104)

            TempReadout(temp: temp, on: ac.power, tint: tint)

            TempSlider(value: temp, range: ac.minT...ac.maxT, step: ac.step, enabled: ac.tempKey != nil,
                       onChange: { dragTemp = $0 },
                       onCommit: { v in
                           dragTemp = nil
                           if let k = ac.tempKey, v != ac.target { m.write(device, k, ac.tempValue(v)) }
                       })

            HStack(spacing: 8) {
                MenuTile(title: L("模式", "Mode"), value: ac.modeLabel, icon: modeIcon, active: ac.power, tint: tint) {
                    ForEach(ac.modes, id: \.self) { o in
                        Button { if let k = ac.modeKey { m.write(device, k, o.value) } } label: { Text((o.value == ac.mode ? "✓ " : "") + o.label) }
                    }
                }
                MenuTile(title: L("风速", "Fan"), value: ac.fanLabel, icon: "wind", active: ac.power, tint: tint) {
                    ForEach(ac.fans, id: \.self) { o in
                        Button { if let k = ac.fanKey { m.write(device, k, o.value) } } label: { Text((o.value == ac.fan ? "✓ " : "") + o.label) }
                    }
                }
                ToggleTile(title: L("睡眠", "Sleep"), icon: "moon.zzz", isOn: ac.sleep, tint: tint) {
                    if let k = ac.sleepKey { m.write(device, k, .bool(!(ac.sleep ?? false))) }
                }
                ToggleTile(title: L("扫风", "Swing"), icon: "arrow.up.and.down", isOn: ac.swing, tint: tint) {
                    if let k = ac.swingKey { m.write(device, k, (ac.swing ?? false) ? ac.swingOff : ac.swingOn) }
                }
            }
        }
        .padding(18)
        .background {
            let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
            shape.fill(LinearGradient(colors: [tint.opacity(ac.power ? 0.32 : 0.12), Theme.bg2], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .top) {
                    Rectangle().fill(EllipticalGradient(colors: [tint.opacity(0.45), tint.opacity(0)])).frame(width: 340, height: 220).offset(y: -80)
                        .opacity(ac.power ? 1 : 0)
                }
                .clipShape(shape)
                .overlay(shape.stroke(LinearGradient(colors: [ac.power ? tint.opacity(0.45) : Color.white.opacity(0.14), Color.white.opacity(0.04)],
                                                     startPoint: .top, endPoint: .bottom), lineWidth: 1))
        }
        .animation(Motion.smooth, value: ac.power)
        .animation(Motion.smooth, value: warmth)
        .animation(Motion.snappy, value: ac.mode)
        .animation(Motion.snappy, value: ac.fan)
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
            Image(systemName: "power").font(.system(size: size * 0.4, weight: .bold)).foregroundStyle(.white)
                .symbolEffect(.bounce, value: on)
                .frame(width: size, height: size)
                .background {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.12))
                        Circle().fill(tint).opacity(on ? 1 : 0)
                        Circle().fill(LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .center)).opacity(on ? 1 : 0)
                    }
                }
                .shadow(color: on ? tint.opacity(0.6) : .clear, radius: 10)
                .ripple(on, color: on ? tint : .white)
        }
        .buttonStyle(.pressable(0.95)).hoverHighlight()
    }
}

struct TempReadout: View {
    let temp: Double
    let on: Bool
    let tint: Color
    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            Text("\(Int(temp.rounded()))").font(.system(size: 80, weight: .thin, design: .rounded))
                .contentTransition(.numericText(value: temp)).monospacedDigit()
            Text("°C").font(.system(size: 20, weight: .light)).padding(.top, 16)
        }
        .foregroundStyle(LinearGradient(colors: [.white, .white, on ? tint : .white], startPoint: .top, endPoint: .bottom))
        .shadow(color: on ? tint.opacity(0.4) : .clear, radius: 20)
        .opacity(on ? 1 : 0.45)
        .animation(Motion.snappy, value: Int(temp.rounded()))
    }
}

/// 空调插画：导风板随开关/扫风摆动，出风气流随模式、风速变化
struct ACIllustration: View {
    let on: Bool
    let tint: Color
    var mode: AirMode = .auto
    var speed: Double = 0.6
    var swing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var changed = Date.distantPast
    @State private var alive = true

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !alive)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let k = intensity(at: tl.date)
            VStack(spacing: 2) {
                unit(t: t, k: k)
                Canvas { ctx, size in draw(&ctx, size, t: t, k: k) }.frame(height: 40)
            }
        }
        .onChange(of: on) { _, _ in changed = .now }
        .task(id: on) {
            if on { alive = true; return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !Task.isCancelled { alive = false }
        }
    }

    /// 开机时气流渐入，关机时渐隐
    func intensity(at d: Date) -> Double {
        if reduceMotion { return on ? 1 : 0 }
        let e = d.timeIntervalSince(changed)
        return on ? min(1, max(0, e / 0.9)) : max(0, 1 - e / 0.6)
    }

    func unit(t: Double, k: Double) -> some View {
        // 导风板开合角度（度），扫风时上下摆动；按正弦换算成可见高度
        let flap = (swing && !reduceMotion ? 32 + 22 * sin(t * 1.1) : 36) * k
        let flapH = 2 + 5 * sin(flap * .pi / 180)
        let body = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return ZStack {
            body.fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.80)], startPoint: .top, endPoint: .bottom))
                .overlay(body.stroke(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                .frame(width: 230, height: 58)
                .shadow(color: on ? tint.opacity(0.5 * k) : .black.opacity(0.3), radius: on ? 6 + 10 * k : 6, y: 4)
            RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.08)).frame(width: 150, height: 2).offset(y: -6)
            // 出风口 + 导风板
            RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.22)).frame(width: 190, height: 6 + 2 * k).offset(y: 17 + k)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(LinearGradient(colors: [Color(white: 0.70), Color(white: 0.95)], startPoint: .top, endPoint: .bottom))
                .frame(width: 186 - 4 * k, height: flapH)
                .offset(y: 19 + 2 * k + flapH / 2)
                .opacity(k)
            // 指示灯
            Circle().fill(on ? tint : Color.gray.opacity(0.6)).frame(width: 6, height: 6).offset(x: 96, y: -14)
                .shadow(color: on ? tint : .clear, radius: 4)
        }
        .background {
            Rectangle().fill(EllipticalGradient(colors: [tint.opacity(0.55), tint.opacity(0)])).frame(width: 320, height: 110).offset(y: 24)
                .opacity(k * 0.85)
        }
    }

    func draw(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double, k: Double) {
        guard k > 0.01 else { return }
        let cx = Double(size.width) / 2, h = Double(size.height)
        let sway = swing && !reduceMotion ? 0.32 * sin(t * 1.1) : 0
        let rate = 0.35 + 0.75 * speed
        let len = 14 + 8 * speed
        var streams: [(Path, Double)] = []
        for i in 0..<7 {
            let fi = Double(i) - 3
            let angle = sway + fi * 0.05
            for j in 0..<(speed > 0.75 ? 2 : 1) {
                let phase = (t * rate + Double(i) * 0.23 + Double(j) * 0.5).truncatingRemainder(dividingBy: 1)
                let y0 = phase * (h - len)
                var p = Path()
                for s in 0...10 {
                    let y = y0 + len * Double(s) / 10
                    let x = cx + fi * 30 + y * tan(angle) + 3 * sin(y / 5 + t * 3 + Double(i))
                    if s == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                }
                streams.append((p, k * 0.9 * sin(phase * .pi)))
            }
        }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 3))
            for (p, a) in streams { l.stroke(p, with: .color(tint.opacity(a * 0.7)), style: StrokeStyle(lineWidth: 5, lineCap: .round)) }
        }
        for (p, a) in streams { ctx.stroke(p, with: .color(tint.opacity(a)), style: StrokeStyle(lineWidth: 2, lineCap: .round)) }

        // 模式粒子：制冷冰晶、制热暖光、除湿水滴
        guard mode == .cool || mode == .heat || mode == .dry else { return }
        func frac(_ x: Double) -> Double { x - floor(x) }
        for i in 0..<12 {
            let seed = Double(i) * 12.9898
            let r1 = frac(sin(seed) * 43758.5453), r2 = frac(sin(seed * 1.7) * 24634.6345)
            let ph = frac(t * rate * (0.5 + 0.4 * r2) + r1)
            let y = (mode == .dry ? ph * ph : ph) * h
            let x = cx + (r2 - 0.5) * 200 + y * tan(sway + (r1 - 0.5) * 0.5) + 4 * sin(t * 2 + seed)
            let a = k * sin(ph * .pi)
            switch mode {
            case .cool:
                let s = 2.2 + 1.8 * r2, tw = 0.55 + 0.45 * sin(t * 6 + seed)
                ctx.fill(sparkle(CGPoint(x: x, y: y), s), with: .color(Color(red: 0.85, green: 0.95, blue: 1).opacity(a * tw)))
            case .heat:
                let r = 1.2 + 1.2 * r2
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 1.5))
                    l.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 1, green: 0.78, blue: 0.45).opacity(a * 0.9)))
                }
            default:
                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.3, y: y - 1.8, width: 2.6, height: 3.6)), with: .color(Color(red: 0.55, green: 0.85, blue: 1).opacity(a * 0.85)))
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
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void
    /// 拖动中滑块 1:1 跟手（不吸附），松手后再吸附到档位
    @State private var dragFraction: Double?
    @State private var hovering = false
    @State private var lastStep: Double?

    func snap(_ f: Double) -> Double {
        let v = range.lowerBound + max(0, min(1, f)) * (range.upperBound - range.lowerBound)
        return (v / step).rounded() * step
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
                        Capsule().fill(Color.white.opacity(enabled ? 0.12 : 0.06))
                        Capsule().fill(Theme.sliderGradient)
                            .mask(alignment: .leading) { Rectangle().frame(width: x + knob / 2) }
                            .opacity(enabled ? 1 : 0.3)
                    }
                    .frame(height: 8)
                    .scaleEffect(x: 1, y: dragging || hovering ? 1.25 : 1)
                    ZStack {
                        Circle().fill(.white).shadow(color: .black.opacity(dragging ? 0.4 : 0.3), radius: dragging ? 6 : 4, y: 1)
                        Circle().fill(Theme.warm(f)).frame(width: 9, height: 9)
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
            HStack {
                Text("\(Int(range.lowerBound))°"); Spacer(); Text(L("← → 微调", "← → adjust")); Spacer(); Text("\(Int(range.upperBound))°")
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
                .symbolEffect(.bounce, value: value)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background {
            ZStack {
                shape.fill(Color.white.opacity(hovering ? 0.11 : 0.07))
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
    }
}
