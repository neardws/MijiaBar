import SwiftUI
import AppKit
import MijiaCore

// MARK: - 客厅小屋试点：预渲染像素底图 + 动态光层（非 3D / SpriteKit）

/// 与底图 `living-room-base.png`（640×359）对齐的归一化锚点；见 `living-room-anchors.json`
enum LivingRoomAnchors {
    static let lamp = CGPoint(x: 0.178, y: 0.31)
    static let tvScreen = CGRect(x: 0.628, y: 0.295, width: 0.21, height: 0.245)
    static let window = CGRect(x: 0.43, y: 0.038, width: 0.26, height: 0.31)
}

/// 设备驱动的灯光强度（0…1）
struct LivingRoomLighting: Equatable {
    var lamp: Double
    var tv: Double
    /// 环境明暗：全关时压低，开灯时略提亮
    var cozy: Double

    static let nightOn = LivingRoomLighting(lamp: 1, tv: 1, cozy: 1)
    static let allOff = LivingRoomLighting(lamp: 0, tv: 0, cozy: 0.1)

    static func merge(lampOn: Bool, tvOn: Bool) -> LivingRoomLighting {
        let l = lampOn ? 1.0 : 0.0, t = tvOn ? 1.0 : 0.0
        let cozy = min(1, 0.15 + l * 0.55 + t * 0.35)
        return LivingRoomLighting(lamp: l, tv: t, cozy: cozy)
    }
}

extension AppModel {
    /// 当前家庭「客厅」模块里的灯 / 电视开关（无电视时 tv 为 false）
    var livingRoomLighting: LivingRoomLighting {
        let hid = currentHomeId ?? ""
        let roomDevices = devices.filter { (currentHomeId == nil || $0.homeId == currentHomeId) && HouseModule.from(roomName: $0.roomName) == .living }
        let ordered = prefs.orderedDevices(home: hid, key: roomDevices.first?.roomName ?? "", roomDevices)
        let placed = HouseLayout.assign(ordered, in: .living).placed
        var lampOn = false, tvOn = false
        for (d, slot) in placed {
            guard d.isOnline, powerInfo(d)?.isOn == true else { continue }
            switch slot.kind {
            case .light: lampOn = true
            case .tv: tvOn = true
            case .ac: break
            }
        }
        return LivingRoomLighting.merge(lampOn: lampOn, tvOn: tvOn)
    }
}

struct LivingRoomHouseView: View {
    var lighting: LivingRoomLighting
    var showChrome = true
    var onToggleLamp: (() -> Void)?
    var onToggleTV: (() -> Void)?

    private static let artSize = CGSize(width: 640, height: 359)
    /// 菜单内嵌时缩到列表宽度；截图用原分辨率
    private var fitWidth: CGFloat { showChrome ? 336 : Self.artSize.width }
    private var fitScale: CGFloat { fitWidth / Self.artSize.width }

    var body: some View {
        VStack(spacing: 0) {
            if showChrome { header }
            ZStack {
                baseArt
                nightDim
                windowMoon
                tvGlow
                lampGlow
                warmWash
            }
            .frame(width: Self.artSize.width, height: Self.artSize.height)
            .scaleEffect(fitScale, anchor: .top)
            .frame(width: fitWidth, height: Self.artSize.height * fitScale)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke))
            if showChrome { footer }
        }
        .padding(showChrome ? 12 : 0)
        .background(showChrome ? Theme.bg : .clear)
    }

    private var header: some View {
        HStack {
            Text(L("客厅小屋", "Living room")).font(.system(size: 15, weight: .semibold))
            Spacer()
            statusPill
        }
        .padding(.bottom, 8)
    }

    private var statusPill: some View {
        let on = lighting.lamp > 0.5 || lighting.tv > 0.5
        return HStack(spacing: 4) {
            Circle().fill(on ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
            Text(on ? L("夜灯已开", "Lights on") : L("已关灯", "Lights off")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Theme.tile, in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if onToggleLamp != nil {
                HouseTapChip(icon: "lightbulb.fill", label: L("落地灯", "Floor lamp"), on: lighting.lamp > 0.5, tint: .yellow, action: onToggleLamp!)
            }
            if onToggleTV != nil {
                HouseTapChip(icon: "tv.fill", label: L("电视", "TV"), on: lighting.tv > 0.5, tint: .indigo, action: onToggleTV!)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder private var baseArt: some View {
        if let img = HouseAssets.baseImage {
            Image(nsImage: img).interpolation(.none).resizable().aspectRatio(contentMode: .fill)
        } else {
            Theme.bg2.overlay(Text("living-room-base").font(.caption).foregroundStyle(.tertiary))
        }
    }

    /// 全关时整体压暗（multiply）
    private var nightDim: some View {
        Color.black.opacity((1 - lighting.cozy) * 0.78)
            .blendMode(.multiply)
            .allowsHitTesting(false)
    }

    /// 窗户月光（常开，强度随 cozy 略变）
    private var windowMoon: some View {
        let r = LivingRoomAnchors.window
        let k = 0.3 + lighting.cozy * 0.35
        return Ellipse()
            .fill(RadialGradient(colors: [Color(red: 0.55, green: 0.72, blue: 0.9).opacity(0.5 * k), .clear], center: .center, startRadius: 0, endRadius: 110))
            .frame(width: r.width * Self.artSize.width, height: r.height * Self.artSize.height * 0.75)
            .position(x: r.midX * Self.artSize.width, y: r.midY * Self.artSize.height)
            .blendMode(.screen)
            .opacity(k)
            .allowsHitTesting(false)
    }

    private var tvGlow: some View {
        let k = lighting.tv
        let r = LivingRoomAnchors.tvScreen
        return ZStack {
            Rectangle()
                .fill(LinearGradient(colors: [Color(red: 0.25, green: 0.58, blue: 0.98), Color(red: 0.12, green: 0.38, blue: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(0.88 * k)
            Glow(Theme.cool, 0.6 * k, diameter: 72, softness: 42)
        }
        .frame(width: r.width * Self.artSize.width, height: r.height * Self.artSize.height)
        .position(x: r.midX * Self.artSize.width, y: r.midY * Self.artSize.height)
        .blendMode(.screen)
        .opacity(k)
        .allowsHitTesting(false)
    }

    private var lampGlow: some View {
        let k = lighting.lamp
        let p = LivingRoomAnchors.lamp
        return ZStack {
            Glow(Color(red: 1, green: 0.78, blue: 0.42), 0.75 * k, diameter: 56, softness: 38)
            Glow(Color(red: 1, green: 0.9, blue: 0.65), 0.5 * k, diameter: 200, softness: 64)
        }
        .position(x: p.x * Self.artSize.width, y: p.y * Self.artSize.height)
        .blendMode(.screen)
        .opacity(k)
        .allowsHitTesting(false)
    }

    /// 地面暖反光
    private var warmWash: some View {
        let k = max(lighting.lamp, lighting.tv * 0.65)
        return LinearGradient(colors: [Color(red: 1, green: 0.72, blue: 0.38).opacity(0.4 * k), .clear], startPoint: .bottom, endPoint: .top)
            .frame(height: Self.artSize.height * 0.5)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .blendMode(.screen)
            .allowsHitTesting(false)
    }
}

private struct HouseTapChip: View {
    let icon: String, label: String, on: Bool, tint: Color, action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).foregroundStyle(on ? tint : .secondary)
                Text(label).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(on ? tint.opacity(0.14) : Theme.tile, in: Capsule())
            .overlay(Capsule().stroke(on ? tint.opacity(0.35) : Theme.stroke))
        }
        .buttonStyle(.plain)
        .hoverHighlight()
        .accessibilityLabel(label)
        .accessibilityValue(on ? L("开", "On") : L("关", "Off"))
    }
}

enum HouseAssets {
    static let baseImage: NSImage? = {
        let url = Bundle.module.url(forResource: "living-room-base", withExtension: "png", subdirectory: "House")
            ?? Bundle.module.url(forResource: "living-room-base", withExtension: "png")
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }()
}

// MARK: - 独立窗口

@MainActor
enum HouseWindow {
    private static var window: NSWindow?

    static func open(model: AppModel) {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let root = LivingRoomPilotHost().environmentObject(model)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = L("客厅小屋", "Living room")
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: root)
        w.center()
        window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window?.contentView = nil; window = nil }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 绑定 AppModel：点芯片切换演示设备
private struct LivingRoomPilotHost: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        LivingRoomHouseView(lighting: m.livingRoomLighting, onToggleLamp: toggleLamp, onToggleTV: toggleTV)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func toggleLamp() {
        guard let d = livingDevice(.light) else { return }
        withoutAnimation { m.toggle(d) }
    }
    func toggleTV() {
        guard let d = livingDevice(.tv) else { return }
        withoutAnimation { m.toggle(d) }
    }
    func livingDevice(_ kind: HouseSlotKind) -> Device? {
        let roomDevices = m.devices.filter { (m.currentHomeId == nil || $0.homeId == m.currentHomeId) && HouseModule.from(roomName: $0.roomName) == .living }
        return HouseLayout.assign(m.prefs.orderedDevices(home: m.currentHomeId ?? "", key: roomDevices.first?.roomName ?? "", roomDevices), in: .living).placed
            .first { $0.1.kind == kind }?.0
    }
}

// MARK: - CLI 截图

extension Snapshot {
    static func house(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (name, appearance, lighting) in [
            ("living-room-night", NSAppearance.Name.darkAqua, LivingRoomLighting.nightOn),
            ("living-room-off", NSAppearance.Name.darkAqua, LivingRoomLighting.allOff),
        ] {
            self.appearance = NSAppearance(named: appearance)
            render(LivingRoomHouseView(lighting: lighting, showChrome: false), out.appendingPathComponent("\(name).png"),
                   size: CGSize(width: 640, height: 359))
        }
        exit(0)
    }
}
