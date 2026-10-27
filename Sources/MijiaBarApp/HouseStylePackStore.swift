import SwiftUI
import MijiaCore

@MainActor final class HouseStylePackStore: ObservableObject {
    static let shared = HouseStylePackStore()
    @Published private(set) var transient: [String: HouseStylePackStatus] = [:]
    @Published private(set) var removalErrors: [String: String] = [:]
    @Published private(set) var revision = 0
    let index: HouseStylePackIndex
    private let installer: HouseStylePackInstaller
    private let mockStatuses: [String: HouseStylePackStatus]?

    init(mockStatuses: [String: HouseStylePackStatus]? = nil) {
        self.mockStatuses = mockStatuses
        installer = HouseStylePackInstaller()
        let url = AppResources.url("style-packs", "json", subdirectory: "House") ?? AppResources.url("style-packs", "json")
        index = url.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(HouseStylePackIndex.self, from: $0) }
            ?? HouseStylePackIndex(schema: 1, packs: [])
    }

    func status(_ id: String) -> HouseStylePackStatus {
        if let mockStatuses { return mockStatuses[id] ?? .unavailable }
        if let state = transient[id] { return state }
        return HouseStylePackLocations.status(id, index: index, bundled: Self.bundled(id) || Self.developmentAssets(id))
    }

    func isAvailable(_ style: String) -> Bool {
        if mockStatuses == nil { return Self.hasAssets(style) }
        switch status(style) {
        case .bundled, .installed: return true
        default: return false
        }
    }

    nonisolated static func hasAssets(_ id: String) -> Bool {
        bundled(id) || HouseStylePackLocations.installedVersion(id) != nil || developmentAssets(id)
    }

    nonisolated static func bundled(_ id: String) -> Bool {
        if id == HouseStyles.defaultStyle { return true }
        if let root = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: root.appendingPathComponent("House/styles/\(id)/modules/module-living-day-unlit.png").path) { return true }
        return ["House/styles/\(id)/modules", "styles/\(id)/modules"].contains {
            AppResources.url("module-living-day-unlit", "png", subdirectory: $0) != nil
        }
    }

    nonisolated static func developmentAssets(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: developmentRoot.appendingPathComponent("\(id)/modules/module-living-day-unlit.png").path)
    }

    nonisolated static var developmentRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("assets/house/styles")
    }

    func download(_ id: String) async -> Bool {
        guard mockStatuses == nil, let pack = index.pack(id) else { return false }
        if case .downloading = transient[id] { return false }
        transient[id] = .downloading(progress: 0)
        do {
            let base = try HouseStylePackLocations.baseURL()
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
            try await installer.install(pack, baseURL: base, appVersion: version) { [weak self] progress in
                Task { @MainActor in
                    guard let self, case .downloading = self.transient[id] else { return }
                    self.transient[id] = .downloading(progress: progress)
                }
            }
            transient[id] = nil
            changed()
            return true
        } catch {
            transient[id] = .failed(reason: error.localizedDescription)
            return false
        }
    }

    func remove(_ id: String) async {
        guard mockStatuses == nil else { return }
        do { try await installer.remove(id); transient[id] = nil; removalErrors[id] = nil; changed() }
        catch { removalErrors[id] = error.localizedDescription }
    }

    private func changed() {
        HouseModuleAssets.clearCache()
        HouseAssets.clearImageCache()
        revision += 1
    }
}
