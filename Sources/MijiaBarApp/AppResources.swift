import Foundation

enum AppResources {
    private final class BundleAnchor {}

    static let bundle: Bundle? = {
        let anchor = Bundle(for: BundleAnchor.self)
        return findBundle(in: [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent(),
            anchor.bundleURL.deletingLastPathComponent(),
        ].compactMap { $0 })
    }()

    static func findBundle(in candidateDirectories: [URL]) -> Bundle? {
        for directory in candidateDirectories {
            let url = directory.appendingPathComponent("MijiaBar_MijiaBarApp.bundle", isDirectory: true)
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }

    static func url(_ name: String, _ ext: String, subdirectory: String? = nil) -> URL? {
        bundle?.url(forResource: name, withExtension: ext, subdirectory: subdirectory)
    }
}
