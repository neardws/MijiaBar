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

// MARK: - 统一的「产品渲染」风格（与空调插画一致）
// 白色亮面外壳 + 顶部高光描边 + 柔和投影；开机后投影和环境光带上设备色，能量（气流、光、电流）用设备色粒子表达。

/// 家电外壳的亮白渐变（与空调机身相同）
let shellFill = LinearGradient(colors: [Color(white: 0.98), Color(white: 0.80)], startPoint: .top, endPoint: .bottom)

extension Shape {
    /// 家电外壳：亮面渐变 + 顶部高光 + 投影；k 为开机程度（0…1），开机时投影带设备色
    func appliance(_ tint: Color, _ k: Double) -> some View {
        fill(shellFill)
            .overlay(stroke(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .shadow(color: k > 0.01 ? tint.opacity(0.45 * k) : .black.opacity(0.22), radius: 5 + 9 * k, y: 4)
    }
}

/// 设备身后的环境光（椭圆渐变），强度随开机程度 k
func Ambient(_ tint: Color, _ k: Double, width: CGFloat, height: CGFloat) -> some View {
    Rectangle().fill(EllipticalGradient(colors: [tint.opacity(0.55), tint.opacity(0)])).frame(width: width, height: height).opacity(k)
}

/// 和空调插画一致的开关过渡：开机约 0.9 秒渐入、关机约 0.6 秒渐隐。
/// content 收到当前时间 t 和开机程度 k。running：开着时是否需要逐帧刷新；settle：开关后继续刷新多久（渐变、滑行）。
struct PowerTimeline<Content: View>: View {
    let on: Bool
    var running = false
    var settle: TimeInterval = 1
    @ViewBuilder let content: (_ t: Double, _ k: Double) -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var changed = Date.distantPast
    @State private var settling = false

    var body: some View {
        TimelineView(.animation(paused: reduceMotion || !(settling || (on && running)))) { tl in
            content(tl.date.timeIntervalSinceReferenceDate, level(at: tl.date))
        }
        .onChange(of: on) { _, _ in changed = .now; settling = true }
        .task(id: changed) {
            guard settling else { return }
            try? await Task.sleep(nanoseconds: UInt64(settle * 1_000_000_000))
            if !Task.isCancelled { settling = false }
        }
    }

    func level(at d: Date) -> Double {
        if reduceMotion { return on ? 1 : 0 }
        let e = d.timeIntervalSince(changed)
        let x = on ? min(1, max(0, e / 0.9)) : max(0, 1 - e / 0.6)
        return x * x * (3 - 2 * x)   // smoothstep
    }
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

/// 循环扇：白色亮面圆环机头 + 五片叶 + 细格栅，底座立柱连到机头。
/// 开机加速、关机滑行；转速跟随风速，高速时叶片变虚；两侧气流随转速流动，摆头时偏向机头朝向的一侧。
struct FanArt: View {
    let on: Bool, level: Double, swing: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spin = Ramp()
    @State private var sway = Ramp()     // velocity 当作摆头幅度 0…1

    var speed: Double { on ? 200 + 900 * level : 0 }   // 度/秒
    static let hub = CGPoint(x: 110, y: 54)
    var now: Double { Date().timeIntervalSinceReferenceDate }

    var body: some View {
        PowerTimeline(on: on, running: true, settle: 3.5) { t, k in
            let v = reduceMotion ? speed : spin.velocity(t)
            let angle = reduceMotion ? 18 : spin.position(t)
            let amp = reduceMotion ? 0 : sway.velocity(t)
            let s = sin(t * 0.9)
            ZStack {
                Ambient(tint, k, width: 240, height: 120).position(x: 110, y: 66)
                Canvas { ctx, size in airflow(&ctx, t: t, v: v, lean: amp * s) }
                // 底座 + 立柱（立柱伸进机头背后，摆头时也连着）
                Capsule().appliance(tint, k).frame(width: 84, height: 14).position(x: 110, y: 126)
                RoundedRectangle(cornerRadius: 5, style: .continuous).appliance(tint, 0).frame(width: 12, height: 50).position(x: 110, y: 100)
                head(angle: angle, blur: min(1, v / 1100), k: k)
                    .scaleEffect(x: cos(amp * s * 28 * .pi / 180), y: 1)   // 2D 模拟摆头（rotation3DEffect 在截图里位置会错）
                    .position(Self.hub)
            }
            .frame(width: 220, height: 136)
        }
        .onAppear { let t = now; spin.jump(speed, at: t); sway.jump(swing && on ? 1 : 0, at: t) }
        .onChange(of: speed) { _, v in spin.retarget(v, at: now, tau: v > spin.velocity(now) ? 0.45 : 0.8) }   // 加速快、滑行慢
        .onChange(of: swing && on) { _, s in sway.retarget(s ? 1 : 0, at: now, tau: 0.5) }
    }

    func head(angle: Double, blur: Double, k: Double) -> some View {
        ZStack {
            Circle().appliance(tint, k).frame(width: 96, height: 96)                                   // 外圈机壳
            Circle().fill(LinearGradient(colors: [Color(white: 0.80), Color(white: 0.90)], startPoint: .top, endPoint: .bottom))
                .frame(width: 80, height: 80)                                                           // 内腔
            Circle().fill(tint.opacity(on ? 0.22 * blur : 0)).frame(width: 74, height: 74)              // 高速转盘残影
            ForEach(0..<5, id: \.self) { i in
                FanBlade().fill(LinearGradient(colors: [tint.opacity(on ? 0.95 : 0.45), tint.opacity(on ? 0.6 : 0.28)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(Double(i) * 72 + angle))
                    .opacity(1 - 0.55 * blur)
            }
            // 细格栅：同心圆 + 少量辐条
            ForEach([30.0, 50.0, 70.0], id: \.self) { d in Circle().stroke(Color.black.opacity(0.07), lineWidth: 1).frame(width: d, height: d) }
            ForEach(0..<12, id: \.self) { i in Rectangle().fill(Color.black.opacity(0.05)).frame(width: 1, height: 78).rotationEffect(.degrees(Double(i) * 15)) }
            Circle().appliance(tint, 0).frame(width: 22, height: 22)                                   // 中心盖
            Circle().fill(tint).frame(width: 5, height: 5).opacity(k).shadow(color: tint, radius: 3 * k)   // 指示灯
        }
        .frame(width: 96, height: 96)
    }

    /// 机头两侧向外的气流；转得越快越密越快，摆头时偏向一侧
    func airflow(_ ctx: inout GraphicsContext, t: Double, v: Double, lean: Double) {
        let strength = min(1, v / 500)
        guard strength > 0.01 else { return }
        let rate = 0.25 + 0.9 * v / 1100
        var streams: [(Path, Double)] = []
        for side in [-1.0, 1.0] {
            let weight = max(0, min(1, 0.6 + 0.4 * side * lean))
            for (j, y) in [36.0, 54.0, 72.0].enumerated() {
                let phase = (t * rate + Double(j) * 0.31 + (side > 0 ? 0.5 : 0)).truncatingRemainder(dividingBy: 1)
                let x0 = 110 + side * (54 + phase * 44)
                let len = 14 + 10 * strength
                var p = Path()
                for s in 0...8 {
                    let x = x0 + side * len * Double(s) / 8
                    let yy = y + (y - 54) * 0.25 * phase + 2.5 * sin(x / 6 + t * 3)
                    if s == 0 { p.move(to: CGPoint(x: x, y: yy)) } else { p.addLine(to: CGPoint(x: x, y: yy)) }
                }
                streams.append((p, strength * weight * sin(phase * .pi) * 0.85))
            }
        }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 3))
            for (p, a) in streams { l.stroke(p, with: .color(tint.opacity(a * 0.7)), style: StrokeStyle(lineWidth: 5, lineCap: .round)) }
        }
        for (p, a) in streams { ctx.stroke(p, with: .color(tint.opacity(a)), style: StrokeStyle(lineWidth: 2, lineCap: .round)) }
    }
}

/// 风扇叶片（花瓣形，略后掠），以框的中心为轴
struct FanBlade: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -9))
        p.addCurve(to: CGPoint(x: 6, y: -37), control1: CGPoint(x: 15, y: -14), control2: CGPoint(x: 19, y: -32))
        p.addCurve(to: CGPoint(x: 0, y: -9), control1: CGPoint(x: -8, y: -42), control2: CGPoint(x: -9, y: -17))
        return p.offsetBy(dx: r.midX, dy: r.midY)
    }
}

/// 灯泡：一体的玻璃轮廓（球面顺滑收进灯颈）+ 细磨砂铝灯头。
/// 光从内部亮起，颜色跟随色温，亮度决定光晕大小和强度；不做任何装饰，灯泡本身不动，
/// 开关只做 0.9 秒亮起 / 0.6 秒熄灭的过渡。
struct BulbArt: View {
    let on: Bool, brightness: Double, kelvin: Double?
    static let glass = CGPoint(x: 70, y: 50)       // 玻璃轮廓框的中心
    static let core = CGPoint(x: 70, y: 45)        // 球心（光晕中心）
    var body: some View {
        let col = kelvinColor(kelvin ?? 3500)
        PowerTimeline(on: on) { _, k in
            let b = k * max(0.15, brightness)       // 开着时至少有一点光
            ZStack {
                Glow(col, 0.55 * b, diameter: 90 + 80 * b, softness: 36).position(Self.core)
                // 灯头：铝质圆柱，三道细螺纹 + 底部触点
                ZStack {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.93), Color(white: 0.74), Color(white: 0.58)],
                                             startPoint: .leading, endPoint: .trailing))
                    VStack(spacing: 5) { ForEach(0..<3, id: \.self) { _ in Rectangle().fill(Color.black.opacity(0.14)).frame(height: 1) } }
                        .padding(.vertical, 4)
                }
                .frame(width: 30, height: 20).position(x: 70, y: 102)
                Capsule().fill(Color(white: 0.30)).frame(width: 12, height: 5).position(x: 70, y: 115)
                // 玻璃
                ZStack {
                    BulbGlass().fill(LinearGradient(colors: [Color(white: 0.89), Color(white: 0.99), Color(white: 0.93)], startPoint: .leading, endPoint: .trailing))
                    BulbGlass().fill(RadialGradient(colors: [Color.white, col.opacity(0.92), col.opacity(0.78)],
                                                    center: UnitPoint(x: 0.5, y: 0.44), startRadius: 1, endRadius: 46))
                        .opacity(k * (0.45 + 0.55 * min(1, b / max(0.15, brightness))))
                    // 细边高光：只在左上缘
                    BulbGlass().stroke(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.6, y: 0.6)), lineWidth: 1.5)
                    BulbGlass().stroke(Color.black.opacity(0.06 * (1 - k)), lineWidth: 0.5)
                }
                .frame(width: 76, height: 86)
                .shadow(color: k > 0.01 ? col.opacity(0.6 * b) : .black.opacity(0.14), radius: 3 + 20 * b, y: k > 0.01 ? 0 : 3)
                .position(Self.glass)
            }
            .frame(width: 140, height: 136)
        }
        .animation(Motion.smooth, value: brightness)
        .animation(Motion.smooth, value: kelvin)
    }
}

/// 灯泡玻璃：上部是圆，两侧沿切线顺滑收窄到灯颈（一条连续轮廓）
struct BulbGlass: Shape {
    func path(in r: CGRect) -> Path {
        let R = r.width / 2
        let c = CGPoint(x: r.midX, y: r.minY + R)
        let neck = r.width * 0.21                  // 灯颈半宽
        func at(_ deg: Double) -> CGPoint { CGPoint(x: c.x + R * CGFloat(cos(deg * .pi / 180)), y: c.y + R * CGFloat(sin(deg * .pi / 180))) }
        let l = at(150), rt = at(30)
        var p = Path()
        p.move(to: CGPoint(x: c.x - neck, y: r.maxY))
        p.addCurve(to: l, control1: CGPoint(x: c.x - neck, y: r.maxY - r.height * 0.1), control2: CGPoint(x: l.x + R * 0.18, y: l.y + R * 0.31))
        for i in 1...60 { p.addLine(to: at(150 + 240 * Double(i) / 60)) }          // 经过顶部到右侧
        p.addCurve(to: CGPoint(x: c.x + neck, y: r.maxY), control1: CGPoint(x: rt.x - R * 0.18, y: rt.y + R * 0.31), control2: CGPoint(x: c.x + neck, y: r.maxY - r.height * 0.1))
        p.closeSubpath()
        return p
    }
}

/// 智能插座：白色亮面插座本体 + 指示灯，插着一个插头，电线通向用电器徽标。
/// 通电时指示灯亮、电流粒子沿电线流向用电器，功率越大越快越亮；断电后 0.6 秒渐隐。
struct PlugArt: View {
    let on: Bool, watts: Double?, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0…1：按对数换算功率，几瓦和几千瓦都能看出差别
    var load: Double { on ? min(1, log10(1 + max(0, watts ?? 0)) / 3.3) : 0 }
    static let unit = CGPoint(x: 68, y: 62)
    static let badge = CGPoint(x: 192, y: 98)
    // 电线：从插头底部向下再弯向用电器（三次贝塞尔）
    static let c0 = CGPoint(x: 68, y: 86), c1 = CGPoint(x: 68, y: 128), c2 = CGPoint(x: 140, y: 98), c3 = CGPoint(x: 176, y: 98)

    var body: some View {
        PowerTimeline(on: on, running: true) { t, k in
            ZStack {
                Ambient(tint, k * (0.6 + 0.4 * load), width: 200, height: 120).position(x: 100, y: 70)
                // 插座本体
                RoundedRectangle(cornerRadius: 22, style: .continuous).appliance(tint, k).frame(width: 80, height: 80).position(Self.unit)
                // 指示灯（右上角）
                Circle().fill(Color.primary.opacity(0.15)).frame(width: 7, height: 7).position(x: 96, y: 34)
                Circle().fill(tint).frame(width: 7, height: 7).opacity(k).shadow(color: tint, radius: 4 * k).position(x: 96, y: 34)
                // 电线
                cable.stroke(Color(white: 0.62), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                cable.stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, lineCap: .round)).offset(y: -1)
                Canvas { ctx, _ in current(&ctx, t: t, k: k) }
                // 插头（插在插孔上）
                RoundedRectangle(cornerRadius: 9, style: .continuous).appliance(tint, 0).frame(width: 34, height: 40).position(x: 68, y: 66)
                Capsule().fill(Color.black.opacity(0.08)).frame(width: 18, height: 3).position(x: 68, y: 56)
                // 用电器徽标
                Circle().appliance(tint, k * load).frame(width: 32, height: 32).position(Self.badge)
                Image(systemName: "bolt.fill").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(k > 0.01 ? AnyShapeStyle(tint) : AnyShapeStyle(Color(white: 0.6)))
                    .position(Self.badge)
            }
            .frame(width: 220, height: 136)
        }
        .animation(Motion.smooth, value: load)
    }

    var cable: Path { Path { p in p.move(to: Self.c0); p.addCurve(to: Self.c3, control1: Self.c1, control2: Self.c2) } }

    static func point(_ u: Double) -> CGPoint {
        let a = 1 - u
        func f(_ p0: CGFloat, _ p1: CGFloat, _ p2: CGFloat, _ p3: CGFloat) -> CGFloat {
            CGFloat(a * a * a) * p0 + CGFloat(3 * a * a * u) * p1 + CGFloat(3 * a * u * u) * p2 + CGFloat(u * u * u) * p3
        }
        return CGPoint(x: f(c0.x, c1.x, c2.x, c3.x), y: f(c0.y, c1.y, c2.y, c3.y))
    }

    /// 沿电线流动的电流粒子：数量、速度、亮度都跟随功率
    func current(_ ctx: inout GraphicsContext, t: Double, k: Double) {
        guard k > 0.01 else { return }
        let n = 3 + Int(4 * load)
        let rate = reduceMotion ? 0 : 0.25 + 0.75 * load
        var dots: [(CGPoint, Double)] = []
        for i in 0..<n {
            let u = (t * rate + Double(i) / Double(n)).truncatingRemainder(dividingBy: 1)
            dots.append((Self.point(u), k * (0.55 + 0.45 * load) * sin(u * .pi)))
        }
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 3))
            for (c, a) in dots { l.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)), with: .color(tint.opacity(a * 0.8))) }
        }
        for (c, a) in dots { ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.2, y: c.y - 2.2, width: 4.4, height: 4.4)), with: .color(Color.white.opacity(a))) }
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
