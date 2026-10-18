import AppKit
import MijiaCore

extension HouseModuleAssets {
    static func decorURL(_ file: String) -> URL? {
        let name = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        let ext = URL(fileURLWithPath: file).pathExtension
        for sub in ["House/decor", "decor", "House", ""] {
            if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: sub.isEmpty ? nil : sub) { return url }
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/decor/\(file)")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    static let decorCatalog: HouseDecorCatalog? = decorURL("decor-catalog.json").flatMap { try? HouseDecorCatalog.load(from: $0) }
    @MainActor private static var decorImages: [String: CGImage] = [:]
    @MainActor private static var missingDecor = Set<String>()
    @MainActor static func decorImage(_ file: String) -> CGImage? {
        if let image = decorImages[file] { return image }
        if let url = decorURL(file), let image = HouseComposer.loadCGImage(from: url) { decorImages[file] = image; return image }
        if missingDecor.insert(file).inserted { fputs("HouseModuleAssets: missing decor sprite \(file)\n", stderr) }
        return nil
    }
    @MainActor static func decorations(layout: [HouseLayoutCell], catalog: HouseModuleCatalog, phase: HousePhase,
                                       config: HomeHouse = HomeHouse(), date: Date = Date()) -> [HouseDecorImage] {
        guard let items = decorCatalog else { return [] }
        return HouseDecor.resolve(layout: layout, catalog: catalog, overrides: config.decor ?? [:], prefs: config.decorPrefs ?? .init(), date: date, items: items, includeHidden: true).compactMap { placement in
            guard let item = items.items.first(where: { $0.id == placement.item }), item.anchor.count == 2,
                  let file = item.sprites[phase.assetName]?.file(wall: placement.wall), let image = decorImage(file) else { return nil }
            let anchor = placement.wall == "ne" ? [Double(image.width) - item.anchor[0], item.anchor[1]] : item.anchor
            return HouseDecorImage(placement: placement, image: image, anchor: anchor)
        }
    }
    @MainActor static func decorFingerprint(_ config: HomeHouse, date: Date) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let overrides = (try? encoder.encode(config.decor ?? [:])).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let prefs = config.decorPrefs ?? .init()
        let seasons = decorCatalog.map { HouseSeasons.activeSeasons(on: date, seasons: $0.seasons).joined(separator: ",") } ?? ""
        return "\(prefs.enabled)|\(prefs.seasonal)|\(seasons)|\(overrides)"
    }
}
