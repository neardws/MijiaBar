import Foundation
import Testing
@testable import MijiaCore

@Suite struct HouseStylesTests {
    @Test func registry() {
        #expect(HouseStyles.all.map(\.id) == ["cozy-wood", "light-wood", "walnut", "japanese", "modern"])
        #expect(HouseStyles.all.map(\.kind) == [.builtin, .palette, .palette, .art, .art])
        for id in ["japanese", "modern"] {
            #expect(HouseStyles.resolve(id) == id)
            #expect(HouseStyles.info(id).hasOwnCatalog)
            #expect(!HouseStyles.info(id).hasClassicArt)
            #expect(HouseStyles.info(id).parent == nil)
        }
        #expect(HouseStyles.resolve("unknown") == "cozy-wood")
        for id in ["cozy-wood", "light-wood", "walnut"] {
            #expect(!HouseStyles.info(id).hasOwnCatalog)
            #expect(HouseStyles.info(id).hasClassicArt)
        }
    }

    @Test func mergeArtStyleByTimestamp() {
        var older = HouseFile(), newer = HouseFile()
        older.setStyle(home: "demo", style: "modern", now: Date(timeIntervalSince1970: 10))
        newer.setStyle(home: "demo", style: "japanese", now: Date(timeIntervalSince1970: 20))
        for merged in [HouseFile.merge(older, newer), HouseFile.merge(newer, older)] {
            #expect(merged.homes["demo"]?.style == "japanese")
            #expect(merged.homes["demo"]?.styleUpdatedAt == Date(timeIntervalSince1970: 20))
        }
    }

    @Test func stylePackContracts() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let assets = root.appendingPathComponent("assets/house")
        let fm = FileManager.default
        let baselineURL = assets.appendingPathComponent("modules/catalog.json")
        let packs = assets.appendingPathComponent("styles")
        guard fm.fileExists(atPath: baselineURL.path), fm.fileExists(atPath: packs.path) else { return }
        struct Catalog: Decodable {
            struct Module: Decodable {
                struct Light: Decodable { let id: String }
                let lights: [Light]
                let variants: [String: String]
            }
            let modules: [String: Module]
        }
        let decoder = JSONDecoder()
        let baseline = try decoder.decode(Catalog.self, from: Data(contentsOf: baselineURL))
        for pack in try fm.contentsOfDirectory(at: packs, includingPropertiesForKeys: nil) {
            let modules = pack.appendingPathComponent("modules")
            let url = modules.appendingPathComponent("catalog.json")
            guard fm.fileExists(atPath: url.path) else { continue }
            let catalog = try decoder.decode(Catalog.self, from: Data(contentsOf: url))
            #expect(Set(catalog.modules.keys) == Set(baseline.modules.keys))
            for (id, module) in catalog.modules {
                #expect(Set(module.lights.map(\.id)) == Set(baseline.modules[id]?.lights.map(\.id) ?? []))
                for phase in ["day", "night"] {
                    for state in ["unlit", "lit"] {
                        for suffix in ["", "-cut"] {
                            let file = try #require(module.variants["\(phase)-\(state)\(suffix)"])
                            #expect(fm.fileExists(atPath: modules.appendingPathComponent(file).path))
                        }
                    }
                }
            }
        }
    }
}
