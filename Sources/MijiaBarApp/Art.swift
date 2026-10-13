import SwiftUI
import MijiaCore

// MARK: - 拟物插画（全部用 SwiftUI 绘制，浅色/深色自适应）

private let metal = LinearGradient(colors: [Color(white: 0.92), Color(white: 0.72)], startPoint: .top, endPoint: .bottom)
private let darkBody = LinearGradient(colors: [Color(white: 0.30), Color(white: 0.12)], startPoint: .top, endPoint: .bottom)

/// 落地扇：叶片转速跟随风速，摆头时左右摇摆
struct FanArt: View {
    let on: Bool, level: Double, swing: Bool, tint: Color
    var body: some View {
        TimelineView(.animation(paused: !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let spin = on ? (t * (200 + 900 * level)).truncatingRemainder(dividingBy: 360) : 20
            let yaw = on && swing ? sin(t * 0.9) * 28 : 0
            ZStack {
                VStack(spacing: 0) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3).fill(metal).frame(width: 8, height: 46)
                    Capsule().fill(metal).frame(width: 74, height: 12).shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
                ZStack {
                    Circle().fill(Color.primary.opacity(0.05))
                    ForEach(0..<3, id: \.self) { i in
                        Ellipse()
                            .fill(LinearGradient(colors: [tint.opacity(on ? 0.95 : 0.35), tint.opacity(on ? 0.55 : 0.2)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 26, height: 40).offset(y: -21)
                            .rotationEffect(.degrees(Double(i) * 120 + spin))
                    }
                    ForEach(0..<16, id: \.self) { i in
                        Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: 92).rotationEffect(.degrees(Double(i) * 11.25))
                    }
                    Circle().stroke(Color(white: 0.6), lineWidth: 3)
                    Circle().fill(metal).frame(width: 16, height: 16).shadow(radius: 1)
                }
                .frame(width: 92, height: 92)
                .rotation3DEffect(.degrees(yaw), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                .offset(y: -18)
            }
            .frame(width: 140, height: 136)
        }
    }
}

/// 灯泡：亮度决定光晕，色温决定颜色
struct BulbArt: View {
    let on: Bool, brightness: Double, kelvin: Double?
    var body: some View {
        let col = kelvinColor(kelvin ?? 3500)
        ZStack {
            Circle().fill(col.opacity(on ? 0.55 * brightness : 0)).frame(width: 150, height: 150).blur(radius: 28)
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(on ? AnyShapeStyle(RadialGradient(colors: [Color.white, col], center: .center, startRadius: 4, endRadius: 46))
                                     : AnyShapeStyle(Color.primary.opacity(0.08)))
                    Circle().stroke(Color.primary.opacity(on ? 0.05 : 0.25), lineWidth: 1.5)
                    Path { p in p.move(to: CGPoint(x: 26, y: 50)); p.addCurve(to: CGPoint(x: 54, y: 50), control1: CGPoint(x: 34, y: 30), control2: CGPoint(x: 46, y: 30)) }
                        .stroke(on ? Color.orange.opacity(0.8) : Color.secondary.opacity(0.6), lineWidth: 2)
                    Circle().fill(Color.white.opacity(0.5)).frame(width: 14, height: 14).offset(x: -16, y: -16)
                }.frame(width: 80, height: 80)
                ForEach(0..<3, id: \.self) { _ in Capsule().fill(metal).frame(width: 34, height: 6).padding(.top, 1) }
                Capsule().fill(Color(white: 0.4)).frame(width: 16, height: 6)
            }
            .shadow(color: on ? col.opacity(0.7) : .clear, radius: 16)
        }
        .animation(.easeInOut(duration: 0.4), value: brightness)
    }
}

/// 插座：通电时电流沿电线流动
struct PlugArt: View {
    let on: Bool, watts: Double?, tint: Color
    var body: some View {
        TimelineView(.animation(paused: !on)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            ZStack {
                RoundedRectangle(cornerRadius: 18).fill(metal).frame(width: 82, height: 82)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.1)))
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2).offset(x: -40)
                Circle().fill(Color.white.opacity(0.9)).frame(width: 58, height: 58).offset(x: -40)
                HStack(spacing: 14) { ForEach(0..<2, id: \.self) { _ in Capsule().fill(Color.black.opacity(0.7)).frame(width: 6, height: 16) } }.offset(x: -40)
                Circle().fill(on ? Color.green : Color.gray.opacity(0.5)).frame(width: 6, height: 6).offset(x: -40, y: 34)
                Path { p in p.move(to: CGPoint(x: 70, y: 68)); p.addCurve(to: CGPoint(x: 150, y: 100), control1: CGPoint(x: 100, y: 68), control2: CGPoint(x: 110, y: 110)) }
                    .stroke(Color(white: 0.55), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                if on {
                    Path { p in p.move(to: CGPoint(x: 70, y: 68)); p.addCurve(to: CGPoint(x: 150, y: 100), control1: CGPoint(x: 100, y: 68), control2: CGPoint(x: 110, y: 110)) }
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 10], dashPhase: CGFloat(-t * (20 + min(watts ?? 0, 2000) / 20))))
                }
                Image(systemName: "bolt.fill").font(.system(size: 22)).foregroundStyle(on ? tint : Color.secondary.opacity(0.5))
                    .offset(x: 50, y: -30).shadow(color: on ? tint : .clear, radius: 8)
            }
            .frame(width: 220, height: 136)
        }
    }
}

/// 电视：开机时屏幕显示输入源
struct TVArt: View {
    let on: Bool, input: String?, playing: Bool, tint: Color
    var body: some View {
        TimelineView(.animation(paused: !on)) { tl in
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
    var body: some View {
        TimelineView(.animation(paused: !playing)) { tl in
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
    var body: some View {
        TimelineView(.animation(paused: !on)) { tl in
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
    var body: some View {
        TimelineView(.animation(paused: !busy)) { tl in
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
    var body: some View {
        TimelineView(.animation(paused: !cooking)) { tl in
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
    var body: some View {
        TimelineView(.animation(paused: !on)) { tl in
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
        }
    }
}

/// 取暖器 / 除湿机：机身 + 热浪或水箱水位
struct ApplianceArt: View {
    let kind: DeviceCategory, on: Bool, level: Double, tint: Color
    var body: some View {
        TimelineView(.animation(paused: !on)) { tl in
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
                        RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.7)).frame(width: 64, height: 48)
                        RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.7)).frame(width: 64, height: CGFloat(48 * level))
                    }.offset(y: 26)
                    Circle().fill(on ? tint : Color.gray.opacity(0.5)).frame(width: 6, height: 6).offset(y: -18)
                }
            }
            .frame(width: 200, height: 136)
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
    }
}
