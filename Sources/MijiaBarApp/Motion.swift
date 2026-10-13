import SwiftUI
import AppKit
import MijiaCore

/// 统一的动效参数。原则：
/// - 菜单栏应用一天打开几十次，动效要克制：快（< 300ms）、无回弹，只为反馈和状态服务
/// - 键盘触发的操作（↑↓、↩、Esc、←→）不做动画
/// - 退出比进入快；系统开启「减弱动态效果」时只保留淡入淡出
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// 按压反馈
    static let press = Animation.spring(duration: 0.16, bounce: 0)
    /// 悬停、颜色、小的状态变化
    static let snappy = Animation.spring(duration: 0.2, bounce: 0)
    /// 设备状态变化（开关、模式、色调）
    static let smooth = Animation.spring(duration: 0.3, bounce: 0)
    /// 进入：页面推入、弹窗、提示
    static let enter = Animation.spring(duration: 0.28, bounce: 0)
    /// 退出：比进入更快
    static let exit = Animation.spring(duration: 0.2, bounce: 0)
    static func stagger(_ i: Int) -> Animation { enter.delay(Double(min(i, 8)) * 0.05) }
}

/// 不带动画地改状态（键盘操作用）
func withoutAnimation(_ body: () -> Void) {
    var t = Transaction(); t.disablesAnimations = true
    withTransaction(t, body)
}

// MARK: - 页面切换

struct PageShift: ViewModifier {
    let x: CGFloat, scale: CGFloat, opacity: Double
    func body(content: Content) -> some View { content.offset(x: x).scaleEffect(scale).opacity(opacity) }
}

extension AnyTransition {
    /// 底层页面（列表）：进出都朝左侧轻微视差
    static var pageBase: AnyTransition {
        Motion.reduced ? .opacity : .modifier(active: PageShift(x: -32, scale: 0.98, opacity: 0), identity: PageShift(x: 0, scale: 1, opacity: 1))
    }
    /// 上层页面（详情 / 设置）：从右侧推入，返回时向右退出，移动途中半透明
    static var pageTop: AnyTransition {
        Motion.reduced ? .opacity : .modifier(active: PageShift(x: 64, scale: 1, opacity: 0), identity: PageShift(x: 0, scale: 1, opacity: 1))
    }
    /// 出现时从 0.95 淡入（不从 0 放大），消失时更快
    static func pop(_ scale: CGFloat = 0.95, anchor: UnitPoint = .center) -> AnyTransition {
        let t: AnyTransition = Motion.reduced ? .opacity : .opacity.combined(with: .scale(scale: scale, anchor: anchor))
        return .asymmetric(insertion: t.animation(Motion.enter), removal: t.animation(Motion.exit))
    }
}

// MARK: - 交互反馈

/// 按下时轻微缩小（0.95–0.98），立即响应
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(_ scale: CGFloat) -> PressableStyle { PressableStyle(scale: scale) }
}

/// 悬停只提亮，不放大（悬停一天几十次，位移只会显得浮躁）
struct HoverHighlight: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content.brightness(hovering ? 0.08 : 0)
            .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
    }
}

/// 首次出现时依次淡入（只用于登录这类低频页面）
struct StaggerIn: ViewModifier {
    let index: Int
    @State private var shown: Bool
    init(index: Int, enabled: Bool) { self.index = index; _shown = State(initialValue: !enabled || Motion.reduced) }
    func body(content: Content) -> some View {
        content.opacity(shown ? 1 : 0).offset(y: shown ? 0 : 8)
            .onAppear { if !shown { withAnimation(Motion.stagger(index)) { shown = true } } }
    }
}

/// 开关时向外扩散一圈涟漪，确认操作已生效
struct Ripple: ViewModifier {
    let trigger: Bool
    let color: Color
    struct Frame { var scale: CGFloat = 1; var opacity: Double = 0 }
    func body(content: Content) -> some View {
        content.background {
            Circle().stroke(color, lineWidth: 1.5)
                .keyframeAnimator(initialValue: Frame(), trigger: trigger) { v, f in v.scaleEffect(f.scale).opacity(f.opacity) } keyframes: { _ in
                    KeyframeTrack(\.scale) { LinearKeyframe(1, duration: 0.01); CubicKeyframe(1.6, duration: 0.45) }
                    KeyframeTrack(\.opacity) { LinearKeyframe(Motion.reduced ? 0 : 0.6, duration: 0.01); CubicKeyframe(0, duration: 0.45) }
                }
                .allowsHitTesting(false)
        }
    }
}

/// 持续旋转（刷新中）。转得快一点，加载显得更快
struct Spin: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.symbolEffect(.rotate, options: .speed(1.8), isActive: active)
        } else {
            TimelineView(.animation(paused: !active)) { tl in
                content.rotationEffect(.degrees(active ? (tl.date.timeIntervalSinceReferenceDate * 540).truncatingRemainder(dividingBy: 360) : 0))
            }
        }
    }
}

extension View {
    func hoverHighlight() -> some View { modifier(HoverHighlight()) }
    func staggerIn(_ index: Int, enabled: Bool = true) -> some View { modifier(StaggerIn(index: index, enabled: enabled)) }
    func ripple(_ trigger: Bool, color: Color) -> some View { modifier(Ripple(trigger: trigger, color: color)) }
}

// MARK: - 设备图标

/// 设备圆形图标：开启时填充、换成实心符号。
/// 列表里保持静止；详情页（animated）里才让风扇转动、空调/取暖器出风波纹，表示设备正在运行
struct DeviceGlyph: View {
    let category: DeviceCategory
    let on: Bool
    var size: CGFloat = 34
    var animated = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let c = category.color
        ZStack {
            Circle().fill(c.opacity(0.16))
            Circle().fill(c).opacity(on ? 1 : 0)
            Circle().fill(LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .center)).opacity(on ? 1 : 0)
            symbol.font(.system(size: size * 0.41, weight: .medium)).foregroundStyle(on ? Color.white : c)
        }
        .frame(width: size, height: size)
        .background {
            // 静态光晕放在 background 里，不参与布局
            if animated {
                Circle().fill(RadialGradient(colors: [c.opacity(0.6), c.opacity(0)], center: .center, startRadius: size * 0.35, endRadius: size * 0.72))
                    .frame(width: size * 1.5, height: size * 1.5)
                    .opacity(on ? 1 : 0)
            }
        }
        .shadow(color: on ? c.opacity(0.4) : .clear, radius: animated ? 10 : 5)
        .animation(Motion.smooth, value: on)
    }

    @ViewBuilder var symbol: some View {
        let live = on && animated && !reduceMotion
        let spin = live && category == .fan
        let waves = live && [.ac, .heater, .dehumidifier].contains(category)
        let img = Image(systemName: on ? Self.filled(category.icon) : category.icon)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: waves)
        if #available(macOS 15, *) {
            img.symbolEffect(.rotate, options: .speed(1.2), isActive: spin)
        } else {
            TimelineView(.animation(paused: !spin)) { tl in
                img.rotationEffect(.degrees(spin ? (tl.date.timeIntervalSinceReferenceDate * 240).truncatingRemainder(dividingBy: 360) : 0))
            }
        }
    }

    static func filled(_ name: String) -> String {
        NSImage(systemSymbolName: name + ".fill", accessibilityDescription: nil) != nil ? name + ".fill" : name
    }
}
