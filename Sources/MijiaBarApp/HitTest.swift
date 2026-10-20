import SwiftUI
import AppKit
import MijiaCore

/// 点击自检（--hittest）：用演示数据在真实窗口里合成鼠标点击，验证各页面顶部按钮能收到点击。
/// 只用 mock 数据，不会访问账号或控制任何设备。
@MainActor
enum HitTest {
    static var menuOpened = false
    static func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { n in
            nonisolated(unsafe) let menu = n.object as? NSMenu
            MainActor.assumeIsolated { menuOpened = true }
            Task { @MainActor in menu?.cancelTracking() }
        }
        let m = AppModel(mock: true)
        m.session = Session(userId: "demo", ssecurity: "", serviceToken: "", region: "cn")
        let host = NSHostingView(rootView: RootView().environmentObject(m))
        host.frame = CGRect(x: 0, y: 0, width: 360, height: 560)
        let win = NSPanel(contentRect: host.frame, styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless], backing: .buffered, defer: false)
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: 60, y: 60))
        win.orderFrontRegardless(); win.makeKey()
        func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
        func click(_ x: CGFloat, _ yTop: CGFloat) {
            let p = NSPoint(x: x, y: 560 - yTop)
            for t in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) { win.sendEvent(e) }
                wait(0.05)
            }
            wait(0.6)
        }
        var fails = 0
        func check(_ name: String, _ ok: Bool) { print((ok ? "PASS " : "FAIL ") + name); if !ok { fails += 1 } }
        wait(1.5)
        for did in ["d1", "d3", "d4", "d5"] {
            guard let d = m.device(did) else { continue }
            // 返回
            m.page = .detail(did); wait(1.2); click(25, 25)
            check("detail \(d.model) back", m.page == .list)
            // 收藏
            m.page = .detail(did); wait(1.2)
            let fav = m.isFavorite(d); click(301, 25)
            check("detail \(d.model) star", m.isFavorite(d) != fav)
            if m.isFavorite(d) != fav { m.toggleFavorite(d) }
            // •••
            menuOpened = false; click(335, 25); wait(0.3)
            check("detail \(d.model) menu", menuOpened)
        }
        // 设置页返回
        m.page = .settings; wait(1.2); click(25, 25)
        check("settings back", m.page == .list)
        // 列表页右上角设置按钮
        m.page = .list; wait(1.2)
        var opened = false
        for x in stride(from: CGFloat(340), through: 240, by: -4) { click(x, 25); if m.page == .settings { opened = true; break } }
        check("list settings button", opened)
        print(fails == 0 ? "HITTEST OK" : "HITTEST FAILED \(fails)")
        exit(fails == 0 ? 0 : 1)
    }
}
