import SwiftUI
import AppKit
import MijiaCore

extension Snapshot {
    static func uiPolish(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let output = URL(fileURLWithPath: dir)
        do { try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true) }
        catch { print("ui-polish-snapshot: \(error)"); exit(1) }
        let model = AppModel(mock: true)
        guard let device = model.devices.first(where: { $0.category == .light }), let state = model.states[device.did] else {
            print("ui-polish-snapshot: missing mock light"); exit(1)
        }
        for (suffix, name, scheme) in [("light", NSAppearance.Name.aqua, ColorScheme.light), ("dark", .darkAqua, .dark)] {
            appearance = NSAppearance(named: name)
            render(TypeDetailView(device: device, state: state).padding(12)
                .frame(maxHeight: .infinity, alignment: .top).background(Theme.bg)
                .environmentObject(model).environment(\.colorScheme, scheme),
                output.appendingPathComponent("ui-polish-detail-\(suffix).png"))
            let focusSuffix = suffix == "light" ? "" : "-dark"
            render(HStack(spacing: 28) {
                PowerButton(on: true, tint: Theme.cool, action: {})
                PowerButton(on: false, tint: Theme.cool, action: {})
                PowerButton(on: false, tint: Theme.cool, action: {}).disabled(true)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.bg)
                .environment(\.colorScheme, scheme).environment(\.forceFocusChrome, true),
                output.appendingPathComponent("ui-polish-focus-power\(focusSuffix).png"), size: CGSize(width: 360, height: 120))
            render(UIPolishFocusTiles().padding(18).background(Theme.bg)
                .environment(\.colorScheme, scheme).environment(\.forceFocusChrome, true),
                output.appendingPathComponent("ui-polish-focus-tile\(focusSuffix).png"), size: CGSize(width: 360, height: 260))
        }
        exit(0)
    }
}

private struct UIPolishFocusTiles: View {
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ToggleTile(title: L("开关", "Power"), icon: "power", isOn: true, tint: Theme.cool, action: {})
                MenuTile(title: L("模式", "Mode"), value: L("自动", "Auto"), icon: "a.circle", active: false, tint: Theme.cool) {
                    Button(L("自动", "Auto")) {}
                }
                ActionTile(title: L("重试", "Retry"), icon: "arrow.clockwise", tint: Theme.cool, action: {})
            }
            Button {} label: { WideButtonFace(title: L("看直播", "Watch live"), icon: "play.fill", tint: .purple) }
                .buttonStyle(.pressable).detailKeyboardAction({})
            Button {} label: { WideButtonFace(title: L("重试", "Retry"), icon: "arrow.clockwise", tint: .purple, enabled: false) }
                .buttonStyle(.pressable).detailKeyboardAction({}).disabled(true)
        }
    }
}
