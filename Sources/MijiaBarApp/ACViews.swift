import SwiftUI
import MijiaCore

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
    var tint: Color { ac.power ? Theme.warm(warmth) : Color.secondary }

    var topLabel: String {
        if let r = ac.roomTemp { return L("室温 ", "Room ") + "\(PropValue.double(r))°" }
        if let p = ac.loadPower { return L("功率 ", "Power ") + "\(PropValue.double(p)) W" }
        return m.displayName(device)
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(topLabel).font(.system(size: 13, weight: .semibold))
                    Text(ac.power ? "\(ac.modeLabel) · \(L("风速", "Fan")) \(ac.fanLabel)" : L("已关机", "Off"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { m.write(device, ac.powerKey, ac.power ? ac.offValue : ac.onValue) } label: {
                    Image(systemName: "power").font(.system(size: 16, weight: .bold)).foregroundStyle(ac.power ? Color.white : Color.primary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(ac.power ? tint : Theme.tile))
                        .shadow(color: ac.power ? tint.opacity(0.6) : .clear, radius: 10)
                }.buttonStyle(.plain).help(L("开关（空格）", "Power (Space)"))
            }

            ACIllustration(on: ac.power, tint: tint).frame(height: 104)

            HStack(alignment: .top, spacing: 2) {
                Text("\(Int(temp.rounded()))").font(.system(size: 80, weight: .thin, design: .rounded))
                    .contentTransition(.numericText()).monospacedDigit()
                Text("°C").font(.system(size: 20, weight: .light)).padding(.top, 16)
            }
            .opacity(ac.power ? 1 : 0.45)
            .animation(.snappy, value: Int(temp.rounded()))

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
        .background(
            RoundedRectangle(cornerRadius: 26)
                .fill(LinearGradient(colors: [tint.opacity(ac.power ? 0.28 : 0.08), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 26).stroke(Theme.stroke))
        .animation(.easeInOut(duration: 0.4), value: ac.power)
        .animation(.easeInOut(duration: 0.4), value: warmth)
    }

    var modeIcon: String {
        if ac.isHeating { return "sun.max" }
        if ac.isCooling { return "snowflake" }
        if ac.modeLabel.contains("除湿") || ac.modeLabel.lowercased().contains("dry") { return "drop" }
        if ac.modeLabel.contains("送风") || ac.modeLabel.lowercased().contains("fan") { return "fan" }
        return "a.circle"
    }
}

struct ACIllustration: View {
    let on: Bool
    let tint: Color
    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.80)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 230, height: 58)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
                RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.22)).frame(width: 190, height: 6).offset(y: 17)
                RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.08)).frame(width: 150, height: 2).offset(y: -6)
                Circle().fill(on ? tint : Color.gray.opacity(0.6)).frame(width: 6, height: 6).offset(x: 96, y: -14)
                    .shadow(color: on ? tint : .clear, radius: 4)
            }
            .shadow(color: on ? tint.opacity(0.55) : .black.opacity(0.3), radius: on ? 16 : 6, y: 4)
            TimelineView(.animation(paused: !on)) { tl in
                Canvas { ctx, size in
                    guard on else { return }
                    let t = tl.date.timeIntervalSinceReferenceDate
                    for i in 0..<7 {
                        let x = size.width / 2 - 90 + CGFloat(i) * 30
                        let phase = (t * 0.7 + Double(i) * 0.23).truncatingRemainder(dividingBy: 1)
                        let len: CGFloat = 16
                        let y0 = CGFloat(phase) * (size.height - len)
                        var p = Path()
                        for k in 0...8 {
                            let yy = y0 + len * CGFloat(k) / 8
                            let xx = x + 3 * CGFloat(sin(Double(yy) / 5 + t * 3 + Double(i)))
                            if k == 0 { p.move(to: CGPoint(x: xx, y: yy)) } else { p.addLine(to: CGPoint(x: xx, y: yy)) }
                        }
                        ctx.stroke(p, with: .color(tint.opacity(0.9 * (1 - phase))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
            }
            .frame(height: 40)
        }
    }
}

struct TempSlider: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    let enabled: Bool
    let onChange: (Double) -> Void
    let onCommit: (Double) -> Void

    func snap(_ f: Double) -> Double {
        let v = range.lowerBound + max(0, min(1, f)) * (range.upperBound - range.lowerBound)
        return (v / step).rounded() * step
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { g in
                let w = g.size.width, knob: CGFloat = 24
                let f = (value - range.lowerBound) / max(range.upperBound - range.lowerBound, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.sliderGradient).frame(height: 8).opacity(enabled ? 1 : 0.3)
                    Circle().fill(Color.white).overlay(Circle().stroke(Color.black.opacity(0.12))).frame(width: knob, height: knob).shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                        .offset(x: CGFloat(f) * (w - knob))
                }
                .frame(height: knob)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in onChange(snap(Double((v.location.x - knob / 2) / (w - knob)))) }
                    .onEnded { v in onCommit(snap(Double((v.location.x - knob / 2) / (w - knob)))) })
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
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).frame(height: 18)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .semibold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(active ? tint.opacity(0.30) : Theme.tile))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 14))
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
        .buttonStyle(.plain).disabled(isOn == nil).opacity(isOn == nil ? 0.45 : 1)
    }
}
