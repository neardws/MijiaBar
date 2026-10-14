import AppKit
import Sparkle

/// Sparkle 2 自动更新：菜单栏应用里只包一层标准控制器。
/// 调试构建 / 截图（没有 .app 包、没有 SUFeedURL）时不启动 Sparkle，避免弹出错误窗口卡住。
@MainActor
final class Updater: NSObject {
    static let shared = Updater()
    private let controller: SPUStandardUpdaterController?

    private override init() {
        let bundled = Bundle.main.bundlePath.hasSuffix(".app") && Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = bundled ? SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil) : nil
        super.init()
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}
