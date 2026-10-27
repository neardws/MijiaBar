import SwiftUI
import AppKit
import MijiaCore

@main
enum Entry {
    static func main() {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.run(dir: a[i + 1], liveQR: a.contains("--live-qr")) }
        } else if let i = a.firstIndex(of: "--art"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.art(dir: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--gif"), i + 1 < a.count {
            let scene = a.firstIndex(of: "--scene").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } ?? "ac"
            MainActor.assumeIsolated { Snapshot.gif(to: a[i + 1], scene: scene) }
        } else if let i = a.firstIndex(of: "--live-test"), i + 2 < a.count {
            #if DEBUG
            MainActor.assumeIsolated { LiveTest.run(out: a[i + 1], model: a[i + 2]) }
            #endif
        } else if a.contains("--hittest") {
            MainActor.assumeIsolated { HitTest.run() }
        } else if let i = a.firstIndex(of: "--icon"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.icon(to: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--house-snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.house(dir: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--house-window-snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.houseWindow(dir: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--house-fixtures-snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.houseFixtures(dir: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--house-absent-variant-snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.houseAbsentVariant(dir: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--house-style-packs-snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.houseStylePacks(dir: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--house-style-snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.houseStyles(dir: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--house-pets-snapshot"), i + 1 < a.count {
            let date = a.firstIndex(of: "--date").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil }
            let photos = a.firstIndex(of: "--photos").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil } ?? ""
            MainActor.assumeIsolated { Snapshot.housePets(dir: a[i + 1], dateString: date, photos: photos.split(separator: ",").map(String.init)) }
        } else if let i = a.firstIndex(of: "--house-free-decor-snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.houseFreeDecor(dir: a[i + 1]) }
        } else if let i = a.firstIndex(of: "--house-decor-snapshot"), i + 1 < a.count {
            let date = a.firstIndex(of: "--date").flatMap { $0 + 1 < a.count ? a[$0 + 1] : nil }
            MainActor.assumeIsolated { Snapshot.houseDecor(dir: a[i + 1], dateString: date) }
        } else {
            MijiaBarApp.main()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        LiveManager.killStale()
        _ = Updater.shared  // 启动 Sparkle（自动检查按 Info.plist / 用户偏好）
    }
    func applicationWillTerminate(_ n: Notification) { MainActor.assumeIsolated { LiveManager.shared.stopNow() } }
}

struct MijiaBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = AppModel()
    var body: some Scene {
        MenuBarExtra {
            RootView().environmentObject(model)
        } label: {
            MenuLabel(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuLabel: View {
    @ObservedObject var model: AppModel
    @ObservedObject var glance = GlanceStore.shared
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.menuIcon)
            if let g = model.glanceText { Text(g).monospacedDigit() } else if let t = model.menuTemp { Text(t) }
        }
    }
}
