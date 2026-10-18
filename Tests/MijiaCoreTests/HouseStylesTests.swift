import Foundation
import CoreGraphics
import Testing
@testable import MijiaCore

@Suite struct HouseStylesTests {
    @Test func wallCapParsing() {
        let colors = HouseWallCapColors(data: Data(##"{"wallCap":"#E8e4DE","wallCapSide":"#B9B3AA"}"##.utf8))
        #expect(colors.top == 0xE8E4DE)
        #expect(colors.side == 0xB9B3AA)
        for json in ["{}", "null", "[]", "invalid", #"{"wallCap":42,"wallCapSide":null}"#] {
            let colors = HouseWallCapColors(data: Data(json.utf8))
            #expect(colors.top == nil)
            #expect(colors.side == nil)
        }
        for hex in ["E8E4DE", "#FFF", "#12345678", "#GG0000", "#-12345", "#１２３４５６"] {
            let colors = HouseWallCapColors(data: Data("{\"wallCap\":\"\(hex)\",\"wallCapSide\":\"#B9B3AA\"}".utf8))
            #expect(colors.top == nil)
            #expect(colors.side == 0xB9B3AA)
        }
    }

    @Test func wallCapPaletteDefaults() {
        let absent = HouseWallCapColors(data: Data("{}".utf8))
        let modern = HouseWallCapColors(data: Data(##"{"wallCap":"#E8E4DE","wallCapSide":"#B9B3AA"}"##.utf8))
        for night in [false, true] {
            let original = HouseComposer.Palette(night: night)
            let unchanged = HouseComposer.Palette(night: night, wallCaps: absent)
            #expect(original.capTop == unchanged.capTop)
            #expect(original.capEdge == unchanged.capEdge)
            #expect(original.endFace == unchanged.endFace)
            #expect(original.pilaster == unchanged.pilaster)
            let updated = HouseComposer.Palette(night: night, wallCaps: modern)
            let factors = night ? [0.46, 0.42, 0.44] : [1.0, 1.0, 1.0]
            let expectedTop = zip([232.0, 228.0, 222.0], factors).map { CGFloat($0 * $1 / 255) } + [1]
            let expectedSide = zip([185.0, 179.0, 170.0], factors).map { CGFloat($0 * $1 / 255) } + [1]
            #expect(updated.capTop.components == expectedTop)
            #expect(updated.capEdge.components == expectedSide)
            #expect(updated.endFace == updated.capEdge)
            #expect(updated.pilaster == updated.capEdge)
            #expect(updated.slabSW == original.slabSW)
        }
    }

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
