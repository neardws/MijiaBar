import SwiftUI

private struct ForceFocusChromeKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// 仅快照强制显示焦点，不改变真实键盘焦点。
    var forceFocusChrome: Bool {
        get { self[ForceFocusChromeKey.self] }
        set { self[ForceFocusChromeKey.self] = newValue }
    }
}

enum FocusChrome {
    static let lineWidth: CGFloat = 2
    static let outset: CGFloat = 3
    static func visible(focused: Bool, forced: Bool, enabled: Bool) -> Bool { enabled && (focused || forced) }
}

private struct KeyboardFocusChrome<Outline: InsettableShape>: ViewModifier {
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.forceFocusChrome) private var forced
    let shape: Outline
    let enabled: Bool

    func body(content: Content) -> some View {
        content.overlay {
            shape.inset(by: -FocusChrome.outset)
                .stroke(Color.accentColor, lineWidth: FocusChrome.lineWidth)
                .opacity(FocusChrome.visible(focused: focused, forced: forced, enabled: enabled && isEnabled) ? 1 : 0)
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

extension View {
    func keyboardFocusChrome<S: InsettableShape>(_ shape: S, enabled: Bool = true) -> some View {
        modifier(KeyboardFocusChrome(shape: shape, enabled: enabled))
    }

    func detailKeyboardAction(_ action: @escaping () -> Void) -> some View {
        focusable().focusEffectDisabled()
            .onKeyPress(.space) { withoutAnimation(action); return .handled }
            .onKeyPress(.return) { withoutAnimation(action); return .handled }
    }
}
