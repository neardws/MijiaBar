import SwiftUI
import MijiaCore

// MARK: - 拟物插画（全部用 SwiftUI 绘制，浅色/深色自适应）

/// 磨砂铝（支架、底座、龙头）
let aluminum = LinearGradient(colors: [Color(white: 0.86), Color(white: 0.64)], startPoint: .top, endPoint: .bottom)
/// 黑色玻璃（屏幕、前脸、触控面）
let darkGlass = LinearGradient(colors: [Color(white: 0.20), Color(white: 0.05)], startPoint: .top, endPoint: .bottom)

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

/// 设备色能量粒子：一层柔光 + 白色亮芯（和空调气流、插座电流同一种画法）
func particles(_ ctx: inout GraphicsContext, _ dots: [(CGPoint, Double)], tint: Color, radius r: CGFloat = 2.2) {
    ctx.drawLayer { l in
        l.addFilter(.blur(radius: 3))
        for (c, a) in dots { l.fill(Path(ellipseIn: CGRect(x: c.x - 2.3 * r, y: c.y - 2.3 * r, width: 4.6 * r, height: 4.6 * r)), with: .color(tint.opacity(a * 0.8))) }
    }
    for (c, a) in dots { ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color.white.opacity(a))) }
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
        particles(&ctx, dots, tint: tint)
    }
}

/// 电视：细铝边 + 黑色玻璃屏幕，立在铝质支架上。
/// 开机时屏幕亮起设备色画面、身后带环境光；播放中底部有一条进度条。输入源已在副标题里，画面上不重复。
struct TVArt: View {
    let on: Bool, playing: Bool, tint: Color
    static let screen = CGPoint(x: 110, y: 60)
    var body: some View {
        PowerTimeline(on: on) { _, k in
            ZStack {
                Ambient(tint, k * 0.8, width: 220, height: 120).position(x: 110, y: 58)
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(aluminum).frame(width: 14, height: 18).position(x: 110, y: 118)
                Capsule().appliance(tint, 0).frame(width: 96, height: 8).position(x: 110, y: 128)
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(aluminum).frame(width: 204, height: 118)
                    .shadow(color: k > 0.01 ? tint.opacity(0.45 * k) : .black.opacity(0.22), radius: 5 + 9 * k, y: 4)
                    .position(Self.screen)
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(darkGlass).frame(width: 199, height: 113).position(Self.screen)
                picture.opacity(k).frame(width: 191, height: 105)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous)).position(Self.screen)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.12), .white.opacity(0)], startPoint: .topLeading, endPoint: UnitPoint(x: 0.55, y: 0.55)))
                    .frame(width: 199, height: 113).position(Self.screen)
            }
            .frame(width: 220, height: 136)
        }
        .animation(Motion.smooth, value: playing)
    }

    /// 画面：设备色渐变 + 左上角一团柔光，像一张安静的壁纸
    var picture: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.45), Color(white: 0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [.white.opacity(0.35), .white.opacity(0)], center: UnitPoint(x: 0.28, y: 0.22), startRadius: 0, endRadius: 90)
            if playing {
                Capsule().fill(.white.opacity(0.25)).frame(width: 150, height: 3)
                    .overlay(alignment: .leading) { Capsule().fill(.white.opacity(0.9)).frame(width: 58, height: 3) }
                    .padding(.bottom, 12).transition(.opacity)
            }
        }
    }
}

/// 智能音箱：白色织物机身（一条连续的圆角轮廓），顶部是黑色玻璃触控面。
/// 播放时顶部亮起缓缓旋转的设备色光，亮度跟随音量；不用声波圈。
struct SpeakerArt: View {
    let playing: Bool, volume: Double, tint: Color
    static let box = CGRect(x: 38, y: 10, width: 84, height: 116)
    var body: some View {
        PowerTimeline(on: playing, running: true) { t, k in
            let b = Self.box
            ZStack {
                Ambient(tint, k * (0.45 + 0.4 * volume), width: 170, height: 120).position(x: 80, y: 62)
                RoundedRectangle(cornerRadius: 38, style: .continuous).appliance(tint, k).frame(width: b.width, height: b.height).position(x: b.midX, y: b.midY)
                // 织物网眼
                Canvas { ctx, size in
                    var row = 0
                    for y in stride(from: 26.0, to: size.height - 6, by: 4.2) {
                        let dx = row % 2 == 0 ? 0 : 2.1
                        for x in stride(from: 5.0 + dx, to: size.width - 4, by: 4.2) {
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 0.7, y: y - 0.7, width: 1.4, height: 1.4)), with: .color(.black.opacity(0.07)))
                        }
                        row += 1
                    }
                }
                .frame(width: b.width, height: b.height).clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous)).position(x: b.midX, y: b.midY)
                top(t: t, k: k).position(x: b.midX, y: b.minY + 13)
            }
            .frame(width: 160, height: 136)
        }
    }

    func top(t: Double, k: Double) -> some View {
        let shape = Ellipse()
        return ZStack {
            shape.fill(darkGlass)
            Canvas { ctx, size in
                guard k > 0.01 else { return }
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let a = k * (0.55 + 0.45 * volume)
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 4))
                    for (i, w) in [(0.0, 1.0), (2.1, 0.7), (4.2, 0.5)] {
                        let p = CGPoint(x: c.x + CGFloat(cos(t * 0.9 + i)) * 16, y: c.y + CGFloat(sin(t * 0.9 + i)) * 2.5)
                        l.fill(Path(ellipseIn: CGRect(x: p.x - 13, y: p.y - 5, width: 26, height: 10)), with: .color(tint.opacity(a * w)))
                    }
                }
            }
            shape.stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
        .frame(width: 58, height: 14).clipShape(shape)
    }
}

/// 家用摄像机：白色亮面机头 + 黑色玻璃前脸 + 镜头，立在短底座上。
/// 开机时镜头里亮起设备色光圈、状态灯常亮；隐私模式时镜头向下转出玻璃视野（和真机一样），不用图标表达。静止画面不加动画。
struct CameraArt: View {
    let on: Bool, tint: Color
    static let head = CGPoint(x: 100, y: 58)
    var body: some View {
        PowerTimeline(on: on) { _, k in
            ZStack {
                Ambient(tint, k * 0.7, width: 200, height: 120).position(x: 100, y: 62)
                // 接触阴影 + 底座：短立柱 + 圆角托盘，和机头同一种亮面外壳
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.22), .black.opacity(0)], center: .center, startRadius: 0, endRadius: 50))
                    .frame(width: 110, height: 14).position(x: 100, y: 131)
                RoundedRectangle(cornerRadius: 6, style: .continuous).appliance(tint, 0).frame(width: 24, height: 22).position(x: 100, y: 108)
                Capsule().appliance(tint, 0).frame(width: 80, height: 14).position(x: 100, y: 123)
                // 机头：一条连续的圆角轮廓
                RoundedRectangle(cornerRadius: 34, style: .continuous).appliance(tint, k).frame(width: 108, height: 88).position(Self.head)
                visor(k).position(Self.head)
            }
            .frame(width: 200, height: 136)
        }
    }

    /// 前脸黑色玻璃：镜头和状态灯都在玻璃后面。隐私模式时镜头向下转出视野，只剩一块干净的玻璃
    func visor(_ k: Double) -> some View {
        let glass = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack {
            glass.fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.05)], startPoint: .top, endPoint: .bottom))
            ZStack {
                lens(k)
                // 状态灯：常亮，不闪烁
                Circle().fill(Color.white.opacity(0.12)).frame(width: 4, height: 4).offset(x: 27, y: -1)
                Glow(tint, 0.9 * k, diameter: 4, softness: 3).offset(x: 27, y: -1)
            }
            .offset(y: CGFloat(1 - k) * 46)
            // 玻璃上半部的斜向反光 + 顶缘细高光
            glass.fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
            glass.stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
        }
        .frame(width: 82, height: 54)
        .clipShape(glass)
    }

    /// 镜头：铝圈 → 深色镜片 → 开机时带设备色的光圈，左上缘一道弧形高光
    func lens(_ k: Double) -> some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 38, height: 38)
            Circle().stroke(Color.white.opacity(0.22), lineWidth: 0.75).frame(width: 37, height: 37)
            Circle().fill(RadialGradient(colors: [Color(white: 0.10), Color(white: 0.01)], center: .center, startRadius: 1, endRadius: 14))
                .frame(width: 27, height: 27)
            // 镀膜：开机时镜片里透出设备色，中心更深，像真实镜头的多层镜片
            Circle().fill(RadialGradient(colors: [Color(white: 0.02), tint.opacity(0.85), tint.opacity(0.15)], center: .center, startRadius: 2, endRadius: 12))
                .frame(width: 23, height: 23).opacity(k)
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 0.5).frame(width: 15, height: 15)
            Circle().trim(from: 0.56, to: 0.71).stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .frame(width: 19, height: 19)
            Circle().fill(Color.white.opacity(0.35)).frame(width: 2.5, height: 2.5).offset(x: 5, y: 5)
        }
    }
}

/// 打印机：白色亮面机身，后面立着一叠纸，前面出纸口。
/// 打印中纸从出纸口缓缓送出、状态灯亮设备色；出错时状态灯变橙色；空闲时灯不亮。
struct PrinterArt: View {
    let busy: Bool, error: Bool, tint: Color
    var body: some View {
        PowerTimeline(on: busy, running: true) { t, k in
            let u = busy ? (t * 0.35).truncatingRemainder(dividingBy: 1) : 0
            let feed = busy ? 6 + CGFloat(u) * 28 : 6
            ZStack {
                Ambient(tint, k * 0.6, width: 200, height: 110).position(x: 100, y: 66)
                sheet(lines: false).frame(width: 84, height: 40).position(x: 100, y: 34)
                RoundedRectangle(cornerRadius: 20, style: .continuous).appliance(tint, k).frame(width: 168, height: 64).position(x: 100, y: 72)
                Capsule().fill(Color.black.opacity(0.06)).frame(width: 140, height: 1.5).position(x: 100, y: 52)
                sheet(lines: true).frame(width: 100, height: feed).position(x: 100, y: 93 + feed / 2)
                    .opacity(u < 0.85 ? 1 : (1 - u) / 0.15)
                Capsule().fill(Color.black.opacity(0.45)).frame(width: 124, height: 4).position(x: 100, y: 92)
                light(k).position(x: 166, y: 56)
            }
            .frame(width: 200, height: 136)
        }
    }
    func sheet(lines: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5).fill(Color(white: 0.99))
            .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(Color.black.opacity(0.08), lineWidth: 0.5))
            .overlay(alignment: .bottom) {
                if lines { VStack(spacing: 3) { ForEach(0..<3, id: \.self) { _ in Capsule().fill(Color.black.opacity(0.12)).frame(width: 64, height: 1.5) } }.padding(.bottom, 4) }
            }
            .clipped()
            .shadow(color: .black.opacity(0.08), radius: 1.5, y: 1)
    }
    @ViewBuilder func light(_ k: Double) -> some View {
        let c = error ? Color.orange : tint
        ZStack {
            Circle().fill(Color.black.opacity(0.12)).frame(width: 5, height: 5)
            Glow(c, 0.9 * (error ? 1 : k), diameter: 5, softness: 3)
        }
    }
}

/// 电饭煲 / 多功能锅：白色亮面锅身 + 浅灰锅盖，前面一块黑色玻璃面板。
/// 烹饪时面板亮起设备色、蒸汽口飘出设备色的柔光粒子（不用波浪线）。
struct CookerArt: View {
    let cooking: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PowerTimeline(on: cooking, running: true) { t, k in
            ZStack {
                Ambient(tint, k * 0.6, width: 180, height: 110).position(x: 90, y: 74)
                Canvas { ctx, _ in steam(&ctx, t: t, k: k) }
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.76)], startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .frame(width: 118, height: 30).position(x: 90, y: 64)
                Capsule().fill(LinearGradient(colors: [Color(white: 0.86), Color(white: 0.68)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 18, height: 6).position(x: 90, y: 49)
                RoundedRectangle(cornerRadius: 30, style: .continuous).appliance(tint, k).frame(width: 136, height: 72).position(x: 90, y: 96)
                Capsule().fill(Color.black.opacity(0.07)).frame(width: 118, height: 1.5).position(x: 90, y: 66)
                panel(k).position(x: 90, y: 100)
            }
            .frame(width: 180, height: 136)
        }
    }
    func panel(_ k: Double) -> some View {
        let shape = Capsule()
        return ZStack {
            shape.fill(darkGlass)
            Capsule().fill(tint).frame(width: 18, height: 3).opacity(k).shadow(color: tint, radius: 3 * k)
            shape.stroke(.white.opacity(0.18), lineWidth: 0.5)
        }
        .frame(width: 48, height: 16)
    }
    /// 蒸汽：从蒸汽口升起、向两侧轻轻散开并渐隐
    func steam(_ ctx: inout GraphicsContext, t: Double, k: Double) {
        guard k > 0.01 else { return }
        let rate = reduceMotion ? 0 : 0.35
        var dots: [(CGPoint, Double)] = []
        for i in 0..<6 {
            let u = (t * rate + Double(i) / 6).truncatingRemainder(dividingBy: 1)
            let side = i % 2 == 0 ? -1.0 : 1.0
            dots.append((CGPoint(x: 90 + CGFloat(side * u * 14 + sin(u * 6 + Double(i)) * 3), y: 44 - CGFloat(u) * 40), k * 0.8 * sin(u * .pi)))
        }
        particles(&ctx, dots, tint: tint)
    }
}

/// 净水器：白色亮面主机 + 一块显示滤芯寿命的玻璃窗，旁边是铝质鹅颈龙头。
/// 滤芯余量用设备色液位表示；不知道是否在出水，所以不画水流。
struct PurifierArt: View {
    let on: Bool, filter: Double?, tint: Color
    var body: some View {
        PowerTimeline(on: on) { _, k in
            let f = max(0, min(1, (filter ?? 0) / 100))
            ZStack {
                Ambient(tint, k * 0.6, width: 200, height: 120).position(x: 90, y: 66)
                faucet.position(x: 100, y: 68)
                Capsule().appliance(tint, 0).frame(width: 24, height: 7).position(x: 136, y: 127)
                RoundedRectangle(cornerRadius: 24, style: .continuous).appliance(tint, k).frame(width: 78, height: 120).position(x: 72, y: 68)
                // 滤芯窗
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.black.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: [tint.opacity(0.65), tint], startPoint: .top, endPoint: .bottom))
                        .frame(height: max(14, 72 * CGFloat(f))).opacity(filter == nil ? 0 : 0.35 + 0.65 * k)
                        .shadow(color: tint.opacity(0.5 * k), radius: 4)
                    Capsule().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .frame(width: 14, height: 72).position(x: 72, y: 76)
                Circle().fill(Color.black.opacity(0.12)).frame(width: 5, height: 5).position(x: 72, y: 26)
                Glow(tint, 0.9 * k, diameter: 5, softness: 3).position(x: 72, y: 26)
            }
            .frame(width: 200, height: 136)
            .animation(Motion.smooth, value: filter)
        }
    }
    var faucet: some View {
        let p = Path { p in
            p.move(to: CGPoint(x: 136, y: 124)); p.addLine(to: CGPoint(x: 136, y: 46))
            p.addCurve(to: CGPoint(x: 166, y: 46), control1: CGPoint(x: 136, y: 24), control2: CGPoint(x: 166, y: 24))
            p.addLine(to: CGPoint(x: 166, y: 56))
        }
        return ZStack {
            p.stroke(aluminum, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
            p.stroke(.white.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).offset(x: -1.5, y: -1)
        }
        .frame(width: 200, height: 136).shadow(color: .black.opacity(0.15), radius: 2, y: 2)
    }
}

/// 取暖器 / 除湿机
struct HumidifierArt: View {
    let on: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Ambient(tint, on ? 0.65 : 0, width: 170, height: 110).position(x: 100, y: 80)
            ForEach(0..<3, id: \.self) { plume in
                Capsule().fill(LinearGradient(colors: [tint.opacity(0), tint.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 5, height: plume == 1 ? 30 : 22)
                    .offset(y: plume == 1 ? -4 : 0)
                    .position(x: CGFloat(88 + plume * 12), y: 24).opacity(on ? 1 : 0)
            }
            RoundedRectangle(cornerRadius: 24).appliance(tint, on ? 1 : 0)
                .frame(width: 96, height: 85).position(x: 100, y: 85)
            Ellipse().fill(shellFill).overlay(Ellipse().stroke(Theme.stroke, lineWidth: 1))
                .frame(width: 90, height: 18).position(x: 100, y: 47)
            Capsule().fill(darkGlass).frame(width: 26, height: 5).position(x: 100, y: 47)
            Capsule().fill(Theme.tile).frame(width: 10, height: 36).position(x: 100, y: 88)
            Capsule().fill(tint.opacity(on ? 0.8 : 0.2)).frame(width: 6, height: 24).position(x: 100, y: 92)
            Circle().fill(on ? tint : Color.secondary.opacity(0.4)).frame(width: 4, height: 4).position(x: 100, y: 116)
        }
        .frame(width: 200, height: 136)
        .animation(reduceMotion ? nil : Motion.smooth, value: on)
    }
}

struct VacuumArt: View {
    let on: Bool, busy: Bool, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            Ambient(tint, on ? 0.6 : 0, width: 180, height: 105).position(x: 100, y: 83)
            ForEach(0..<3, id: \.self) { trail in
                Capsule().fill(tint.opacity(0.35)).frame(width: CGFloat(32 - trail * 7), height: 3)
                    .position(x: 25, y: CGFloat(74 + trail * 12)).opacity(on && busy ? 1 : 0)
            }
            Ellipse().fill(aluminum).frame(width: 132, height: 76).position(x: 105, y: 94)
            Ellipse().appliance(tint, on ? 1 : 0).frame(width: 138, height: 80).position(x: 105, y: 83)
            Ellipse().stroke(Theme.stroke, lineWidth: 2).frame(width: 118, height: 64).position(x: 105, y: 82)
            RoundedRectangle(cornerRadius: 8).fill(darkGlass).frame(width: 34, height: 20).position(x: 105, y: 61)
            Ellipse().fill(shellFill).frame(width: 34, height: 18).position(x: 105, y: 55)
            Ellipse().fill(tint.opacity(on ? 0.8 : 0.15)).frame(width: 20, height: 9).position(x: 105, y: 55)
            Capsule().fill(on ? tint : Color.secondary.opacity(0.4)).frame(width: 15, height: 4).position(x: 105, y: 89)
            Capsule().fill(darkGlass).frame(width: 36, height: 5).position(x: 105, y: 119)
        }
        .frame(width: 200, height: 136)
        .animation(reduceMotion ? nil : Motion.smooth, value: on)
        .animation(reduceMotion ? nil : Motion.smooth, value: busy)
    }
}

struct ApplianceArt: View {
    let kind: DeviceCategory, on: Bool, level: Double, tint: Color
    var body: some View {
        if kind == .heater { HeaterArt(on: on, level: level, tint: tint) } else { DehumidifierArt(on: on, level: level, tint: tint) }
    }
}

/// 油汀取暖器：一排白色亮面散热片。开机后散热片从底部透出设备色的热，强度跟随目标温度；热量用上升的柔光粒子表达（不用波浪线）。
struct HeaterArt: View {
    let on: Bool, level: Double, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PowerTimeline(on: on, running: true) { t, k in
            let heat = k * (0.4 + 0.6 * level)
            ZStack {
                Ambient(tint, heat, width: 200, height: 120).position(x: 100, y: 70)
                Canvas { ctx, _ in rise(&ctx, t: t, k: k) }
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { _ in
                        let fin = RoundedRectangle(cornerRadius: 9, style: .continuous)
                        fin.fill(shellFill)
                            .overlay(fin.fill(LinearGradient(colors: [tint.opacity(0), tint.opacity(0.8)], startPoint: .top, endPoint: .bottom)).opacity(heat))
                            .overlay(fin.stroke(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                            .frame(width: 18, height: 90)
                    }
                }
                .shadow(color: k > 0.01 ? tint.opacity(0.45 * heat) : .black.opacity(0.22), radius: 5 + 9 * heat, y: 4)
                .position(x: 100, y: 72)
                ForEach([62.0, 138.0], id: \.self) { x in
                    Capsule().fill(aluminum).frame(width: 24, height: 6).position(x: x, y: 124)
                }
            }
            .frame(width: 200, height: 136)
        }
        .animation(Motion.smooth, value: level)
    }
    func rise(_ ctx: inout GraphicsContext, t: Double, k: Double) {
        guard k > 0.01 else { return }
        let rate = reduceMotion ? 0 : 0.25 + 0.3 * level
        var dots: [(CGPoint, Double)] = []
        for i in 0..<7 {
            let u = (t * rate + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            dots.append((CGPoint(x: 49 + CGFloat(i) * 17 + CGFloat(sin(u * 5 + Double(i))) * 2, y: 24 - CGFloat(u) * 22), k * (0.5 + 0.5 * level) * sin(u * .pi)))
        }
        particles(&ctx, dots, tint: tint)
    }
}

/// 除湿机：白色亮面立式机身，顶部出风格栅，正面一个透明水箱。
/// 水位用设备色表示；运行时干燥空气以柔光粒子从顶部升起。
struct DehumidifierArt: View {
    let on: Bool, level: Double, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        PowerTimeline(on: on, running: true) { t, k in
            ZStack {
                Ambient(tint, k * 0.6, width: 200, height: 120).position(x: 100, y: 70)
                Canvas { ctx, _ in rise(&ctx, t: t, k: k) }
                RoundedRectangle(cornerRadius: 26, style: .continuous).appliance(tint, k).frame(width: 100, height: 112).position(x: 100, y: 76)
                VStack(spacing: 4) { ForEach(0..<4, id: \.self) { _ in Capsule().fill(Color.black.opacity(0.10)).frame(width: 60, height: 2) } }
                    .position(x: 100, y: 40)
                Circle().fill(Color.black.opacity(0.12)).frame(width: 5, height: 5).position(x: 100, y: 62)
                Glow(tint, 0.9 * k, diameter: 5, softness: 3).position(x: 100, y: 62)
                tank.position(x: 100, y: 100)
            }
            .frame(width: 200, height: 136)
        }
        .animation(Motion.smooth, value: level)
    }
    var tank: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack(alignment: .bottom) {
            shape.fill(Color.black.opacity(0.06))
            Rectangle().fill(LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                .frame(height: 40 * CGFloat(max(0, min(1, level))))
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.5)).frame(height: 1) }
            shape.stroke(Color.black.opacity(0.08), lineWidth: 0.5)
        }
        .frame(width: 70, height: 40).clipShape(shape)
    }
    func rise(_ ctx: inout GraphicsContext, t: Double, k: Double) {
        guard k > 0.01 else { return }
        let rate = reduceMotion ? 0 : 0.4
        var dots: [(CGPoint, Double)] = []
        for i in 0..<5 {
            let u = (t * rate + Double(i) * 0.41).truncatingRemainder(dividingBy: 1)
            dots.append((CGPoint(x: 76 + CGFloat(i) * 12, y: 20 - CGFloat(u) * 20), k * 0.8 * sin(u * .pi)))
        }
        particles(&ctx, dots, tint: tint)
    }
}

/// 温度计：磨砂玻璃管 + 液柱，液柱颜色沿温度色带取色（和空调一致），高度跟随温度。没有读数时液柱收回、玻璃泡变灰。
struct ThermoArt: View {
    let temp: Double?, tint: Color
    var body: some View {
        let f = max(0.06, min(1, ((temp ?? 0) + 10) / 50))
        let c = temp.map { Theme.warm(max(0, min(1, ($0 - 10) / 25))) } ?? Color(white: 0.7)
        ZStack {
            if temp != nil { Glow(c, 0.35, diameter: 40, softness: 24).position(x: 60, y: 112) }
            // 玻璃管和玻璃泡是一条连续轮廓
            Path { p in
                p.addRoundedRect(in: CGRect(x: 45, y: 6, width: 30, height: 104), cornerSize: CGSize(width: 15, height: 15))
                p.addEllipse(in: CGRect(x: 40, y: 92, width: 40, height: 40))
            }
            .fill(shellFill).shadow(color: .black.opacity(0.18), radius: 4, y: 3)
            Capsule().fill(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0)], startPoint: .top, endPoint: .bottom)).frame(width: 3, height: 70).position(x: 51, y: 50)
            ForEach(0..<5, id: \.self) { i in
                Capsule().fill(Color.black.opacity(0.12)).frame(width: 6, height: 1).position(x: 70, y: 22 + CGFloat(i) * 16)
            }
            Capsule().fill(c).frame(width: 10, height: 8 + 84 * CGFloat(temp == nil ? 0 : f))
                .frame(height: 100, alignment: .bottom).position(x: 60, y: 62)
            Circle().fill(RadialGradient(colors: [c.opacity(0.75), c], center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: 14))
                .frame(width: 26, height: 26).position(x: 60, y: 112)
            Circle().trim(from: 0.56, to: 0.71).stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                .frame(width: 16, height: 16).position(x: 60, y: 112)
        }
        .frame(width: 120, height: 136)
        .animation(Motion.smooth, value: temp)
    }
}

/// 人体传感器：白色亮面圆形机身 + 磨砂菲涅尔透镜，立在小底座上。在线时透镜里透出设备色、身后带环境光；静止画面不加动画。
struct MotionSensorArt: View {
    let on: Bool, tint: Color
    var body: some View {
        PowerTimeline(on: on) { _, k in
            ZStack {
                Ambient(tint, k * 0.6, width: 180, height: 120).position(x: 80, y: 60)
                RoundedRectangle(cornerRadius: 5, style: .continuous).appliance(tint, 0).frame(width: 18, height: 24).position(x: 80, y: 110)
                Capsule().appliance(tint, 0).frame(width: 60, height: 10).position(x: 80, y: 124)
                Circle().appliance(tint, k).frame(width: 92, height: 92).position(x: 80, y: 58)
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(white: 0.99), Color(white: 0.86)], center: UnitPoint(x: 0.4, y: 0.35), startRadius: 0, endRadius: 30))
                    Circle().fill(RadialGradient(colors: [tint.opacity(0.55), tint.opacity(0)], center: .center, startRadius: 0, endRadius: 26)).opacity(k)
                    ForEach(1..<5, id: \.self) { i in Circle().stroke(Color.black.opacity(0.05), lineWidth: 0.75).frame(width: CGFloat(i) * 12, height: CGFloat(i) * 12) }
                    Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                }
                .frame(width: 56, height: 56).position(x: 80, y: 58)
            }
            .frame(width: 160, height: 136)
        }
    }
}

/// 可视门铃：竖长的白色亮面机身，上部黑色玻璃后面是镜头（和摄像机同一种镜头），下部是磨砂圆形按键和一圈指示灯环。
/// 在线时灯环常亮设备色、镜头透出设备色，身后带环境光；和摄像机一样静止画面不加动画。
struct DoorbellArt: View {
    let on: Bool, tint: Color
    var body: some View {
        PowerTimeline(on: on) { _, k in
            ZStack {
                Ambient(tint, k * 0.6, width: 170, height: 130).position(x: 80, y: 66)
                RoundedRectangle(cornerRadius: 27, style: .continuous).appliance(tint, k).frame(width: 54, height: 116).position(x: 80, y: 68)
                window(k).position(x: 80, y: 39)
                // 麦克风孔
                HStack(spacing: 3.5) { ForEach(0..<4, id: \.self) { _ in Circle().fill(Color.black.opacity(0.14)).frame(width: 2, height: 2) } }
                    .position(x: 80, y: 71)
                // 按键：灰色底环上亮起设备色灯环（常亮），中间是磨砂圆面
                Circle().stroke(Color.black.opacity(0.08), lineWidth: 3).frame(width: 32, height: 32).position(x: 80, y: 99)
                Circle().stroke(tint, lineWidth: 3).frame(width: 32, height: 32).opacity(k).shadow(color: tint, radius: 6 * k).position(x: 80, y: 99)
                Circle().fill(RadialGradient(colors: [Color(white: 0.99), Color(white: 0.86)], center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 14))
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    .frame(width: 24, height: 24).position(x: 80, y: 99)
            }
            .frame(width: 160, height: 136)
        }
    }

    /// 黑色玻璃窗：圆角和机身同心（27 − 6），镜头在玻璃后面，上半部斜向反光 + 顶缘细高光
    func window(_ k: Double) -> some View {
        let glass = RoundedRectangle(cornerRadius: 21, style: .continuous)
        return ZStack {
            glass.fill(darkGlass)
            CameraArt(on: on, tint: tint).lens(k).scaleEffect(0.82)
            glass.fill(LinearGradient(colors: [.white.opacity(0.10), .white.opacity(0)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.5)))
            glass.stroke(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
        }
        .frame(width: 42, height: 46)
        .clipShape(glass)
    }
}

/// 门窗传感器：主机和磁铁两块白色亮面长条并排。门窗打开时两块分开、缝隙里透出设备色的光；关上时贴在一起。
/// 主机的状态灯在线时常亮；开合变化时用 Motion.smooth 移动，静止画面不加动画。open 为 nil 表示还不知道（按关着画）。
struct ContactSensorArt: View {
    let on: Bool, open: Bool?, tint: Color
    var body: some View {
        PowerTimeline(on: on) { _, k in
            let isOpen = open == true
            let gap: CGFloat = isOpen ? 26 : 5
            let mainW: CGFloat = 38, magW: CGFloat = 20
            let x0 = 80 - (mainW + gap + magW) / 2
            let mx = x0 + mainW / 2
            ZStack {
                Ambient(tint, k * 0.5, width: 170, height: 120).position(x: 80, y: 68)
                // 缝隙里的光：只在打开时出现
                Capsule().fill(LinearGradient(colors: [tint.opacity(0), tint.opacity(0.9), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: 84).shadow(color: tint, radius: 8)
                    .position(x: x0 + mainW + gap / 2, y: 68).opacity(isOpen ? k : 0)
                RoundedRectangle(cornerRadius: 11, style: .continuous).appliance(tint, k).frame(width: mainW, height: 100).position(x: mx, y: 68)
                // 状态灯和电池盖接缝
                Circle().fill(Color.black.opacity(0.10)).frame(width: 4, height: 4).position(x: mx, y: 30)
                Glow(tint, 0.9 * k, diameter: 4, softness: 3).position(x: mx, y: 30)
                Capsule().fill(Color.black.opacity(0.06)).frame(width: 22, height: 1).position(x: mx, y: 100)
                RoundedRectangle(cornerRadius: 8, style: .continuous).appliance(tint, 0).frame(width: magW, height: 70).position(x: x0 + mainW + gap + magW / 2, y: 68)
            }
            .frame(width: 160, height: 136)
            .animation(Motion.smooth, value: open)
        }
    }
}

/// 水浸传感器：小而薄的白色亮面圆饼（顶面 + 侧面表现厚度，比例不要像扫地机器人），底部露出两枚金属探针。
/// 检测到浸水时身下出现一摊水（两圈静止的波纹）、状态灯变成橙色警示；平时状态灯在线常亮设备色。静止画面不加动画。
struct LeakSensorArt: View {
    let on: Bool, wet: Bool?, tint: Color
    static let water = Color(red: 0.35, green: 0.68, blue: 1.0)
    var body: some View {
        PowerTimeline(on: on) { _, k in
            let isWet = wet == true
            ZStack {
                Ambient(isWet ? Self.water : tint, k * 0.5, width: 170, height: 110).position(x: 80, y: 74)
                // 一摊水
                ZStack {
                    Ellipse().fill(RadialGradient(colors: [Self.water.opacity(0.55), Self.water.opacity(0.16)], center: .center, startRadius: 0, endRadius: 74))
                        .frame(width: 140, height: 32)
                    Ellipse().stroke(Color.white.opacity(0.55), lineWidth: 0.75).frame(width: 110, height: 24)
                    Ellipse().stroke(Color.white.opacity(0.35), lineWidth: 0.75).frame(width: 128, height: 29)
                }
                .position(x: 80, y: 103).opacity(isWet ? 1 : 0)
                Ellipse().fill(RadialGradient(colors: [.black.opacity(0.22), .black.opacity(0)], center: .center, startRadius: 0, endRadius: 40))
                    .frame(width: 90, height: 14).position(x: 80, y: 102).opacity(isWet ? 0.5 : 1)
                ForEach([-16.0, 16.0], id: \.self) { dx in Capsule().fill(aluminum).frame(width: 4, height: 6).position(x: 80 + dx, y: 102) }
                // 侧面：顶面椭圆向下延伸的厚度，比顶面暗
                Path { p in
                    p.addRect(CGRect(x: 38, y: 68, width: 84, height: 16))
                    p.addEllipse(in: CGRect(x: 38, y: 67, width: 84, height: 34))
                }
                .fill(LinearGradient(colors: [Color(white: 0.86), Color(white: 0.70)], startPoint: .top, endPoint: .bottom))
                .shadow(color: k > 0.01 && !isWet ? tint.opacity(0.35 * k) : .black.opacity(0.18), radius: 5, y: 3)
                // 顶面：亮面 + 顶缘细高光
                Ellipse().fill(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
                    .frame(width: 84, height: 34).position(x: 80, y: 68)
                Circle().fill(Color.black.opacity(0.10)).frame(width: 4, height: 4).position(x: 80, y: 77)
                Glow(isWet ? .orange : tint, 0.9 * k, diameter: 4, softness: 3).position(x: 80, y: 77)
            }
            .frame(width: 160, height: 136)
            .animation(Motion.smooth, value: wet)
        }
    }
}

/// 通用智能设备（没有专门插画的类型）：白色亮面方形主机，正面一个磨砂圆形按键，下方一条指示灯带。
/// 开机时灯带亮起设备色、身后带环境光；不画镜头之类会被误认成具体设备的部件，静止画面不加动画。
struct GenericArt: View {
    let on: Bool, tint: Color
    var body: some View {
        PowerTimeline(on: on) { _, k in
            ZStack {
                Ambient(tint, k * 0.6, width: 200, height: 120).position(x: 80, y: 68)
                RoundedRectangle(cornerRadius: 30, style: .continuous).appliance(tint, k).frame(width: 104, height: 104).position(x: 80, y: 68)
                Circle().fill(RadialGradient(colors: [Color(white: 0.99), Color(white: 0.85)], center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 26))
                    .overlay(Circle().stroke(Color.black.opacity(0.08), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
                    .frame(width: 44, height: 44).position(x: 80, y: 58)
                Capsule().fill(Color.black.opacity(0.08)).frame(width: 52, height: 5).position(x: 80, y: 98)
                Capsule().fill(tint).frame(width: 52, height: 5).opacity(k).shadow(color: tint, radius: 5 * k).position(x: 80, y: 98)
            }
            .frame(width: 160, height: 136)
        }
    }
}

/// 空气净化器：白色圆柱机身（左右明暗表现圆柱体）、一圈细密的进风孔，顶部是圆形出风格栅和一圈指示灯环。
/// 开机时灯环亮起设备色、净化后的空气以设备色柔光粒子从顶部升起，速度和亮度跟随风速。正面不画圆形深色部件，避免像摄像头。
struct AirPurifierArt: View {
    let on: Bool, level: Double, tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    static let box = CGRect(x: 44, y: 22, width: 72, height: 108)
    /// 圆柱的左右明暗
    static let cylinder = LinearGradient(stops: [.init(color: Color(white: 0.80), location: 0), .init(color: Color(white: 0.98), location: 0.38),
                                                 .init(color: Color(white: 0.93), location: 0.7), .init(color: Color(white: 0.76), location: 1)],
                                         startPoint: .leading, endPoint: .trailing)
    var body: some View {
        PowerTimeline(on: on, running: true) { t, k in
            let b = Self.box
            let body = UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 16, bottomTrailingRadius: 16, topTrailingRadius: 8, style: .continuous)
            ZStack {
                Ambient(tint, k * (0.45 + 0.35 * level), width: 190, height: 120).position(x: 80, y: 70)
                Canvas { ctx, _ in rise(&ctx, t: t, k: k) }
                body.fill(Self.cylinder)
                    .shadow(color: k > 0.01 ? tint.opacity(0.45 * k) : .black.opacity(0.22), radius: 5 + 9 * k, y: 4)
                    .frame(width: b.width, height: b.height).position(x: b.midX, y: b.midY)
                // 进风孔：越靠两侧越淡，像绕着圆柱一圈
                Canvas { ctx, size in
                    var row = 0
                    for y in stride(from: 3.0, to: size.height - 2, by: 4.4) {
                        let dx = row % 2 == 0 ? 0 : 2.2
                        for x in stride(from: 2.0 + dx, to: size.width - 1, by: 4.4) {
                            let edge = abs(x / size.width - 0.5) * 2
                            ctx.fill(Path(ellipseIn: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6)), with: .color(.black.opacity(0.13 * (1 - edge * edge))))
                        }
                        row += 1
                    }
                }
                .frame(width: b.width - 6, height: b.height - 34).position(x: b.midX, y: b.minY + 22 + (b.height - 34) / 2)
                // 顶部：机身顶面（椭圆）、出风格栅、指示灯环
                Ellipse().fill(LinearGradient(colors: [Color(white: 0.99), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                    .overlay(Ellipse().stroke(Color.black.opacity(0.06), lineWidth: 0.5))
                    .frame(width: b.width, height: 18).position(x: b.midX, y: b.minY)
                Ellipse().stroke(tint, lineWidth: 2).frame(width: 56, height: 12).opacity(k).shadow(color: tint, radius: 3 * k).position(x: b.midX, y: b.minY)
                Ellipse().fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                    .overlay(grille).frame(width: 50, height: 10).clipShape(Ellipse()).position(x: b.midX, y: b.minY)
            }
            .frame(width: 160, height: 136)
        }
        .animation(Motion.smooth, value: level)
    }
    /// 出风格栅：几道横向细缝
    var grille: some View {
        VStack(spacing: 1.6) { ForEach(0..<4, id: \.self) { _ in Rectangle().fill(Color.black.opacity(0.18)).frame(height: 0.8) } }
    }
    func rise(_ ctx: inout GraphicsContext, t: Double, k: Double) {
        guard k > 0.01 else { return }
        let rate = reduceMotion ? 0 : 0.3 + 0.5 * level
        var dots: [(CGPoint, Double)] = []
        for i in 0..<5 {
            let u = (t * rate + Double(i) * 0.37).truncatingRemainder(dividingBy: 1)
            dots.append((CGPoint(x: 60 + CGFloat(i) * 10 + CGFloat(sin(u * 5 + Double(i))) * 2, y: Self.box.minY - 2 - CGFloat(u) * 20), k * (0.5 + 0.5 * level) * sin(u * .pi)))
        }
        particles(&ctx, dots, tint: tint)
    }
}
