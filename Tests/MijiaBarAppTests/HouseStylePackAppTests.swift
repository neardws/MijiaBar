import Foundation
import Testing
import MijiaCore
@testable import MijiaBarApp

@MainActor @Suite struct HouseStylePackAppTests {
    @Test func bakedIndexAndMockStatus() throws {
        let store = HouseStylePackStore(mockStatuses: [
            "cozy-wood": .bundled, "modern": .installed(version: 1), "japanese": .available(size: 12_300_000),
            "walnut": .downloading(progress: 0.4), "light-wood": .failed(reason: "fixture"),
        ])
        #expect(store.index.schema == 1)
        #expect(Set(store.index.packs.map(\.id)) == ["japanese", "modern", "light-wood", "walnut"])
        #expect(store.index.packs.allSatisfy { $0.size > 0 && $0.sha256.count == 64 })
        #expect(store.isAvailable("cozy-wood"))
        #expect(store.isAvailable("modern"))
        #expect(!store.isAvailable("japanese"))
        #expect(!store.isAvailable("walnut"))
        #expect(!store.isAvailable("light-wood"))
    }

    @Test func missingPackAndIncompleteInstallFallBackToCozy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "module-living-day-unlit"
        let baseline = try #require(HouseModuleAssets.resourceURL(name, "png", style: "cozy-wood"))
        for id in ["japanese", "modern", "light-wood", "walnut"] {
            let directory = root.appendingPathComponent("\(id)/modules")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("unfinished".utf8).write(to: directory.appendingPathComponent("\(name).png"))
            #expect(HouseModuleAssets.resourceURL(name, "png", style: id, fallbackToDefault: false, installedRoot: root, developmentRoot: nil) == nil)
            #expect(HouseModuleAssets.resourceURL(name, "png", style: id, installedRoot: root, developmentRoot: nil) == baseline)
        }
    }

    @Test func installedBeforeDevelopmentAssetsAndMissingModuleFallback() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let installed = root.appendingPathComponent("installed"), development = root.appendingPathComponent("dev")
        for directory in [installed, development] {
            let modules = directory.appendingPathComponent("modern/modules")
            try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: modules.appendingPathComponent("fixture.png"))
        }
        let pack = HouseStylePack(id: "modern", version: 1, url: "modern/1.zip", sha256: String(repeating: "a", count: 64), size: 42)
        try JSONEncoder().encode(pack).write(to: installed.appendingPathComponent("modern/.pack.json"))
        try Data("{\"id\":\"modern\",\"version\":1}".utf8).write(to: installed.appendingPathComponent("modern/manifest.json"))
        #expect(HouseModuleAssets.resourceURL("fixture", "png", style: "modern", installedRoot: installed, developmentRoot: development) == installed.appendingPathComponent("modern/modules/fixture.png"))
        let name = "module-living-day-unlit"
        #expect(HouseModuleAssets.resourceURL(name, "png", style: "modern", installedRoot: installed, developmentRoot: nil) == HouseModuleAssets.resourceURL(name, "png", style: "cozy-wood"))
    }
}
