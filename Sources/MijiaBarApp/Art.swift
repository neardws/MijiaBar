import SwiftUI
import MijiaCore

// MARK: - 拟物插画（全部用 SwiftUI 绘制，浅色/深色自适应）

private let metal = LinearGradient(colors: [Color(white: 0.92), Color(white: 0.72)], startPoint: .top, endPoint: .bottom)
private let darkBody = LinearGradient(colors: [Color(white: 0.30), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)

/// 柔和光晕：直径 diameter 的圆向外羽化 softness，效果接近 `.blur(radius: softness)`。
/// 用径向渐变而不是 `.blur`：截图（cacheDisplay）画不出模糊，且在 TimelineView 里每帧模糊开销很大。
/// 只占 diameter 的布局尺寸，羽化部分画在外面。
func Glow(_ color: Color, _ opacity: Double, diameter d: CGFloat, softness s: CGFloat) -> some View {
    let r = d / 2 + s
    let solid = max(0, (d / 2 - s) / r)
    return Color.clear.frame(width: d, height: d).overlay(
        Circle().fill(RadialGradient(gradient: Gradient(stops: [.init(color: color.opacity(opacity), location: 0),
                                                                .init(color: color.opacity(opacity), location: solid),
                                                                .init(color: color.opacity(0), location: 1)]),
                                     center: .center, startRadius: 0, endRadius: r))
            .frame(width: 2 * r, height: 2 * r))
}

/// 速度的平滑过渡：从当前速度按指数曲线接近目标速度，位置连续、速度连续（可随时被新目标打断）。
/// 用来做风扇启动加速、关机滑行，以及摆头幅度的渐入渐出。
struct Ramp {
    var t0 = 0.0, p0 = 0.0, v0 = 0.0, v1 = 0.0, tau = 0.5
    func velocity(_ t: Double) -> Double { v1 + (v0 - v1) * exp(-max(0, t - t0) / tau) }
    func position(_ t: Double) -> Double { let d = max(0, t - t0); return p0 + v1 * d + (v0 - v1) * tau * (1 - exp(-d / tau)) }
    /// 从 t 时刻的当前状态出发，换一个目标速度
    mutating func retarget(_ v: Double, at t: Double, tau: Double) { p0 = position(t); v0 = velocity(t); v1 = v; t0 = t; self.tau = tau }
    /// 直接处于目标速度（页面刚打开时用，不播放启动过程）
    mutating func jump(_ v: Double, at t: Double) { p0 = position(t); v0 = v; v1 = v; t0 = t }
    func settled(_ t: Double) -> Bool { abs(velocity(t) - v1) < 1 }
}

/// 落地扇：开机时叶片加速，关机时滑行减速；转速跟随风速，高速时叶片变虚成一个转盘；摆头时扇头左右转动。
/// 灯杆一直连到扇头中心的电机，扇头摆动时也不会和底座脱开。
struct FanArt: View {
    let on: Bool, level: Double, swing: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = Ramp()
    @State private var sway = Ramp()     // 这里 position 不用，velocity 当作摆头幅度 0…1
    @State private var moving = false

    var speed: Double { on ? 200 + 900 * level : 0 }   // 度/秒
    static let hub = CGPoint(x: 70, y: 50)

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !moving)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let v = reduceMotion ? speed : spin.velocity(t)
            let angle = reduceMotion ? 20 : spin.position(t)
            let amp = reduceMotion ? 0 : sway.velocity(t)
            let yaw = amp * sin(t * 0.9) * 28
            let blur = min(1, v / 1100)          // 转得越快叶片越虚
            ZStack {
                // 底座和灯杆：灯杆一直通到电机（扇头中心）
                Capsule().fill(metal).frame(width: 72, height: 12).shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .position(x: 70, y: 124)
                RoundedRectangle(cornerRadius: 3).fill(metal).frame(width: 8, height: 124 - Self.hub.y)
                    .position(x: 70, y: (124 + Self.hub.y) / 2)
                head(angle: angle, blur: blur)
                    .scaleEffect(x: cos(yaw * .pi / 180), y: 1)   // 2D 模拟转向（rotation3DEffect 在截图里位置会错）
                    .position(Self.hub)
            }
            .frame(width: 140, height: 136)
        }
        .onAppear { let t = now; spin.jump(speed, at: t); sway.jump(swing && on ? 1 : 0, at: t); moving = on }
        .onChange(of: speed) { _, v in
            // 加速快、滑行慢：像真的电机一样
            spin.retarget(v, at: now, tau: v > spin.velocity(now) ? 0.45 : 0.8)
            settle()
        }
        .onChange(of: swing && on) { _, s in sway.retarget(s ? 1 : 0, at: now, tau: 0.5); settle() }
        .animation(Motion.smooth, value: on)
    }

    var now: Double { Date().timeIntervalSinceReferenceDate }

    /// 有东西在动就让 TimelineView 跑起来；关机后等滑行结束再停
    func settle() {
        moving = true
        guard !on else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            // 读 @State 里的当前目标，而不是闭包捕获的旧 on：期间又开机了就继续转
            if spin.v1 == 0, sway.v1 == 0, spin.settled(now) { moving = false }
        }
    }

    func head(angle: Double, blur: Double) -> some View {
        ZStack {
            Circle().fill(Color.primary.opacity(0.05))
            Circle().fill(Color(white: 0.55)).frame(width: 28, height: 28)          // 电机
            Circle().fill(tint.opacity(on ? 0.25 * blur : 0))                       // 高速时的转盘残影
            ForEach(0..<3, id: \.self) { i in
                Ellipse()
                    .fill(LinearGradient(colors: [tint.opacity(on ? 0.95 : 0.4), tint.opacity(on ? 0.55 : 0.22)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 26, height: 40).offset(y: -21)
                    .rotationEffect(.degrees(Double(i) * 120 + angle))
                    .opacity(1 - 0.55 * blur)
            }
            ForEach(0..<16, id: \.self) { i in
                Rectangle().fill(Color.primary.opacity(0.16)).frame(width: 1, height: 92).rotationEffect(.degrees(Double(i) * 11.25))
            }
            Circle().stroke(Color(white: 0.6), lineWidth: 3)
            Circle().fill(metal).frame(width: 16, height: 16).shadow(radius: 1)
        }
        .frame(width: 92, height: 92)
    }
}

/// 灯泡：亮度决定光晕的大小和强度，色温决定颜色。开灯时光亮渐入，关灯时更快熄灭；没有循环动画。
struct BulbArt: View {
    let on: Bool, brightness: Double, kelvin: Double?
    var body: some View {
        let col = kelvinColor(kelvin ?? 3500)
        let b = on ? max(0.15, brightness) : 0           // 开着时至少有一点光
        ZStack {
            // 光晕以玻璃泡为中心
            Glow(col, 0.6 * b, diameter: 80 + 70 * b, softness: 30).position(x: 70, y: 48)
            ZStack {
                Circle().fill(Color.primary.opacity(0.07))
                Circle().fill(RadialGradient(colors: [Color.white, col], center: .center, startRadius: 4, endRadius: 46)).opacity(b > 0 ? 0.4 + 0.6 * b : 0)
                Circle().stroke(Color.primary.opacity(on ? 0.06 : 0.25), lineWidth: 1.5)
                filament.stroke(Color.secondary.opacity(0.6), lineWidth: 2)
                filament.stroke(Color(red: 1, green: 0.62, blue: 0.25), lineWidth: 2).opacity(on ? 1 : 0)
                    .shadow(color: on ? Color.orange.opacity(0.8 * b) : .clear, radius: 4)
                Circle().fill(Color.white.opacity(0.5)).frame(width: 14, height: 14).offset(x: -16, y: -16)
            }
            .frame(width: 80, height: 80)
            .shadow(color: col.opacity(0.7 * b), radius: 16)
            .position(x: 70, y: 48)
            // 灯座
            VStack(spacing: 1) {
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(metal).frame(width: 34, height: 6) }
                Capsule().fill(Color(white: 0.4)).frame(width: 16, height: 6)
            }
            .position(x: 70, y: 88 + 14)
        }
        .frame(width: 140, height: 136)
        .animation(on ? Motion.enter : Motion.exit, value: on)
        .animation(Motion.smooth, value: brightness)
        .animation(Motion.smooth, value: kelvin)
    }

    var filament: Path {
        Path { p in p.move(to: CGPoint(x: 26, y: 50)); p.addCurve(to: CGPoint(x: 54, y: 50), control1: CGPoint(x: 34, y: 30), control2: CGPoint(x: 46, y: 30)) }
    }
}

/// 插座：插头插在面板上，电线通向用电器（闪电）。通电时指示灯亮、电流沿电线流动，功率越大流得越快越亮；断电后电流消失。
struct PlugArt: View {
    let on: Bool, watts: Double?, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0…1：按对数换算功率，几瓦和几千瓦都能看出差别
    var load: Double { on ? min(1, log10(1 + max(0, watts ?? 0)) / 3.3) : 0 }

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                // 面板
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(metal).frame(width: 84, height: 84)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.black.opacity(0.1)))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                    .position(x: 62, y: 62)
                Circle().fill(Color.white.opacity(0.85)).frame(width: 60, height: 60).position(x: 62, y: 62)
                // 指示灯（面板上沿）
                Capsule().fill(Color.primary.opacity(0.18)).frame(width: 14, height: 4).position(x: 62, y: 28)
                Capsule().fill(Color.green).frame(width: 14, height: 4).opacity(on ? 1 : 0)
                    .shadow(color: .green.opacity(on ? 0.9 : 0), radius: 4).position(x: 62, y: 28)
                // 电线：从插头底部通到右侧的用电器
                cable.stroke(Color(white: 0.55), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                // dashPhase 只在一个周期（6+10）内循环：直接用 -t×速度 会是上百亿，Core Graphics 每帧都很慢
                cable.stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 10],
                                                      dashPhase: reduceMotion ? 0 : CGFloat(16 - (t * (25 + 140 * load)).truncatingRemainder(dividingBy: 16))))
                    .opacity(on ? 0.45 + 0.55 * load : 0)
                // 插头（盖在插孔上）
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.98), Color(white: 0.84)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 32, height: 38)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.black.opacity(0.12)))
                    .overlay(Capsule().fill(Color.black.opacity(0.08)).frame(width: 18, height: 3).offset(y: -8))
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 2)
                    .position(x: 62, y: 62)
                // 用电器端
                Image(systemName: "bolt.fill").font(.system(size: 20)).foregroundStyle(on ? tint : Color.secondary.opacity(0.5))
                    .shadow(color: on ? tint.opacity(0.4 + 0.6 * load) : .clear, radius: 3 + 7 * load)
                    .position(x: 196, y: 92)
            }
            .frame(width: 220, height: 136)
        }
        .animation(on ? Motion.enter : Motion.exit, value: on)
        .animation(Motion.smooth, value: load)
    }

    /// 从插头底部出线，向右下绕到用电器
    var cable: Path {
        Path { p in p.move(to: CGPoint(x: 62, y: 81)); p.addCurve(to: CGPoint(x: 182, y: 92), control1: CGPoint(x: 62, y: 128), control2: CGPoint(x: 140, y: 92)) }
    }
}

/// 电视：开机时屏幕显示输入源
struct TVArt: View {
    let on: Bool, input: String?, playing: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color(white: 0.1)).frame(width: 196, height: 114)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(on ? AnyShapeStyle(LinearGradient(colors: [tint, Color(hue: (0.7 + 0.05 * sin(t * 0.5)).truncatingRemainder(dividingBy: 1), saturation: 0.6, brightness: 0.8)],
                                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                                 : AnyShapeStyle(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                        .frame(width: 184, height: 102)
                    if on {
                        VStack(spacing: 4) {
                            Image(systemName: playing ? "play.fill" : "tv").font(.system(size: 22, weight: .semibold))
                            if let input { Text(input).font(.system(size: 12, weight: .semibold)) }
                        }.foregroundStyle(.white.opacity(0.92))
                    } else {
                        Rectangle().fill(LinearGradient(colors: [Color.white.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .center)).frame(width: 184, height: 102)
                    }
                    Circle().fill(on ? Color.white.opacity(0.6) : Color.red.opacity(0.8)).frame(width: 3, height: 3).offset(y: 54)
                }
                .shadow(color: on ? tint.opacity(0.45) : .black.opacity(0.2), radius: on ? 14 : 4, y: 3)
                Rectangle().fill(metal).frame(width: 8, height: 10)
                Capsule().fill(metal).frame(width: 90, height: 6)
            }
        }
    }
}

/// 音箱：播放时声波扩散
struct SpeakerArt: View {
    let playing: Bool, volume: Double, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !playing)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                if playing {
                    ForEach(0..<3, id: \.self) { i in
                        let ph = (t * 0.7 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Circle().stroke(tint.opacity((1 - ph) * (0.3 + 0.5 * volume)), lineWidth: 2)
                            .frame(width: 70 + 90 * ph, height: 70 + 90 * ph)
                    }
                }
                RoundedRectangle(cornerRadius: 30).fill(darkBody).frame(width: 66, height: 118)
                    .overlay(
                        VStack(spacing: 5) {
                            ForEach(0..<7, id: \.self) { _ in
                                HStack(spacing: 5) { ForEach(0..<5, id: \.self) { _ in Circle().fill(Color.white.opacity(0.18)).frame(width: 4, height: 4) } }
                            }
                        }.padding(.top, 10), alignment: .top)
                    .overlay(Capsule().fill(playing ? tint : Color.white.opacity(0.2)).frame(width: 26, height: 4).padding(.bottom, 12), alignment: .bottom)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            }
        }
    }
}

/// 摄像机：开启时镜头发光、录制灯闪烁；关闭时镜头遮挡
struct CameraArt: View {
    let on: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(metal).frame(width: 100, height: 100).shadow(color: .black.opacity(0.18), radius: 5, y: 3)
                    Circle().fill(Color(white: 0.12)).frame(width: 62, height: 62)
                    if on {
                        Circle().fill(RadialGradient(colors: [tint.opacity(0.9), Color(white: 0.05)], center: .center, startRadius: 2, endRadius: 22)).frame(width: 40, height: 40)
                        Circle().fill(Color.white.opacity(0.6)).frame(width: 8, height: 8).offset(x: -8, y: -8)
                        Circle().fill(Color.red.opacity(sin(t * 3) > 0 ? 0.95 : 0.25)).frame(width: 6, height: 6).offset(y: -40)
                    } else {
                        Capsule().fill(Color(white: 0.45)).frame(width: 62, height: 22)
                        Image(systemName: "eye.slash.fill").font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                Capsule().fill(metal).frame(width: 60, height: 10).padding(.top, 4)
            }
        }
    }
}

/// 打印机：打印中纸张缓缓送出
struct PrinterArt: View {
    let busy: Bool, error: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !busy)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let feed = busy ? CGFloat((t * 0.4).truncatingRemainder(dividingBy: 1)) * 30 : 6
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(Color.white).frame(width: 90, height: 40)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.1))).offset(y: -44)
                RoundedRectangle(cornerRadius: 16).fill(metal).frame(width: 170, height: 70)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                RoundedRectangle(cornerRadius: 2).fill(Color.black.opacity(0.55)).frame(width: 120, height: 5).offset(y: 18)
                RoundedRectangle(cornerRadius: 2).fill(Color.white).frame(width: 96, height: feed)
                    .overlay(VStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Color.gray.opacity(0.4)).frame(width: 70, height: 1.5) } }.clipped())
                    .offset(y: 20 + feed / 2)
                Circle().fill(error ? Color.red : (busy ? tint : Color.green.opacity(0.8))).frame(width: 7, height: 7).offset(x: 68, y: -18)
            }
            .frame(width: 200, height: 136)
        }
    }
}

/// 锅具：烹饪时冒热气
struct CookerArt: View {
    let cooking: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !cooking)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                if cooking {
                    Canvas { ctx, size in
                        for i in 0..<4 {
                            let ph = (t * 0.5 + Double(i) * 0.25).truncatingRemainder(dividingBy: 1)
                            let x = size.width / 2 - 36 + CGFloat(i) * 24
                            var p = Path()
                            for k in 0...10 {
                                let y = 46 - CGFloat(k) * 4 - CGFloat(ph) * 20
                                let xx = x + CGFloat(4 * sin(Double(k) / 2 + t * 2 + Double(i)))
                                if k == 0 { p.move(to: CGPoint(x: xx, y: y)) } else { p.addLine(to: CGPoint(x: xx, y: y)) }
                            }
                            ctx.stroke(p, with: .color(Color.secondary.opacity(0.5 * (1 - ph))), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        }
                    }.frame(width: 160, height: 60).offset(y: -44)
                }
                Capsule().fill(metal).frame(width: 130, height: 12).offset(y: -10)
                Capsule().fill(metal).frame(width: 24, height: 8).offset(y: -18)
                RoundedRectangle(cornerRadius: 22).fill(LinearGradient(colors: [tint.opacity(0.85), tint.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 120, height: 62).offset(y: 30)
                    .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
                Capsule().fill(Color.white.opacity(0.85)).frame(width: 34, height: 12).offset(y: 34)
                Circle().fill(cooking ? Color.orange : Color.gray.opacity(0.5)).frame(width: 5, height: 5).offset(x: 26, y: 34)
            }
            .frame(width: 180, height: 136)
        }
    }
}

/// 净水器：出水时水滴下落，滤芯寿命条
struct PurifierArt: View {
    let on: Bool, filter: Double?, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(metal).frame(width: 70, height: 110).offset(x: -40)
                    .overlay(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.12)).frame(width: 12, height: 70).offset(x: -40, y: 6))
                RoundedRectangle(cornerRadius: 3).fill(tint.opacity(0.85)).frame(width: 12, height: CGFloat(70 * (filter ?? 0.0) / 100)).offset(x: -40, y: 6 + 35 - CGFloat(35 * (filter ?? 0.0) / 100))
                Path { p in p.move(to: CGPoint(x: 110, y: 30)); p.addLine(to: CGPoint(x: 150, y: 30)); p.addLine(to: CGPoint(x: 150, y: 48)) }
                    .stroke(metal, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                if on {
                    ForEach(0..<3, id: \.self) { i in
                        let ph = (t * 1.2 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                        Image(systemName: "drop.fill").font(.system(size: 10)).foregroundStyle(tint.opacity(1 - ph))
                            .offset(x: 40, y: -10 + CGFloat(ph) * 60)
                    }
                }
            }
            .frame(width: 200, height: 136)
            .animation(Motion.smooth, value: filter)
        }
    }
}

/// 取暖器 / 除湿机：机身 + 热浪或水箱水位
struct ApplianceArt: View {
    let kind: DeviceCategory, on: Bool, level: Double, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                if kind == .heater {
                    HStack(spacing: 6) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [on ? tint.opacity(0.9) : Color(white: 0.8), on ? tint.opacity(0.5) : Color(white: 0.65)], startPoint: .top, endPoint: .bottom))
                                .frame(width: 16, height: 86)
                        }
                    }
                    .shadow(color: on ? tint.opacity(0.5) : .black.opacity(0.1), radius: on ? 14 : 4)
                    if on {
                        Canvas { ctx, size in
                            for i in 0..<5 {
                                let ph = (t * 0.5 + Double(i) * 0.2).truncatingRemainder(dividingBy: 1)
                                let x = size.width / 2 - 48 + CGFloat(i) * 24
                                var p = Path()
                                for k in 0...8 {
                                    let y = 30 - CGFloat(k) * 3 - CGFloat(ph) * 16
                                    let xx = x + CGFloat(3 * sin(Double(k) / 2 + t * 3))
                                    if k == 0 { p.move(to: CGPoint(x: xx, y: y)) } else { p.addLine(to: CGPoint(x: xx, y: y)) }
                                }
                                ctx.stroke(p, with: .color(tint.opacity(0.7 * (1 - ph))), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            }
                        }.frame(width: 160, height: 34).offset(y: -62)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 18).fill(metal).frame(width: 96, height: 124)
                        .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
                    VStack(spacing: 3) { ForEach(0..<4, id: \.self) { _ in Capsule().fill(Color.black.opacity(0.18)).frame(width: 60, height: 3) } }.offset(y: -40)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12))).frame(width: 64, height: 48)
                        RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.7)).frame(width: 64, height: CGFloat(48 * level))
                    }.offset(y: 26)
                    Circle().fill(on ? tint : Color.gray.opacity(0.5)).frame(width: 6, height: 6).offset(y: -18)
                }
            }
            .frame(width: 200, height: 136)
            .animation(Motion.smooth, value: level)
        }
    }
}

/// 温度计：水银高度跟随温度
struct ThermoArt: View {
    let temp: Double?, tint: Color
    var body: some View {
        let f = max(0.05, min(1, ((temp ?? 0) + 10) / 50))
        ZStack(alignment: .bottom) {
            Capsule().fill(Color.primary.opacity(0.08)).frame(width: 26, height: 112)
                .overlay(Capsule().stroke(Color.primary.opacity(0.15)))
            Capsule().fill(LinearGradient(colors: [Theme.heat, Theme.cool], startPoint: .top, endPoint: .bottom))
                .frame(width: 12, height: CGFloat(96 * (temp == nil ? 0.05 : f))).padding(.bottom, 14)
            Circle().fill(Theme.cool).frame(width: 34, height: 34).offset(y: 12)
        }
        .frame(height: 136)
        .animation(Motion.smooth, value: temp)
    }
}
