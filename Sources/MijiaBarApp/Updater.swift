import AppKit
import Sparkle

/// Sparkle 2 自动更新：菜单栏应用里只包一层标准控制器。
@MainActor
final class Updater: NSObject {
    static let shared = Updater()
    private let controller: SPUStandardUpdaterController

    private override init() {
        // startingUpdater: true → 按 Info.plist / 用户偏好自动检查
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        super.init()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
