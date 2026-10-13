import SwiftUI
import AppKit
import MijiaCore

@main
enum Entry {
    static func main() {
        let a = CommandLine.arguments
        if let i = a.firstIndex(of: "--snapshot"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.run(dir: a[i + 1], liveQR: a.contains("--live-qr")) }
        } else if let i = a.firstIndex(of: "--icon"), i + 1 < a.count {
            MainActor.assumeIsolated { Snapshot.icon(to: a[i + 1]) }
        } else {
            MijiaBarApp.main()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.setActivationPolicy(.accessory) }
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
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: model.menuIcon)
            if let t = model.menuTemp { Text(t) }
        }
    }
}
