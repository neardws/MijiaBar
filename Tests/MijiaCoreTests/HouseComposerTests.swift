import Foundation
import Testing
import CoreGraphics
@testable import MijiaCore

@Suite struct HouseComposerTests {
    static let modulesDir: URL = {
        // Tests run from package root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("assets/house/modules")
    }()

    func load() throws -> (HouseModuleCatalog, [String: (CGImage, CGImage)]) {
        let cat = try HouseComposer.loadCatalog(from: Self.modulesDir.appendingPathComponent("catalog.json"))
        var images: [String: (CGImage, CGImage)] = [:]
        for (id, art) in cat.modules {
            guard let variants = art.variants,
                  let u = variants["night-unlit"], let l = variants["night-lit"],
                  let ui = HouseComposer.loadCGImage(from: Self.modulesDir.appendingPathComponent(u)),
                  let li = HouseComposer.loadCGImage(from: Self.modulesDir.appendingPathComponent(l)) else { continue }
            images[id] = (ui, li)
        }
        return (cat, images)
    }

    @Test func composesThreeLayoutsUnder30ms() throws {
        let (cat, images) = try load()
        #expect(images.count >= 4)
        let layouts: [[HouseLayoutCell]] = [
            [
                .init(room: "r1", module: "living", col: 0, row: 0),
                .init(room: "r2", module: "bedroom", col: 2, row: 0),
            ],
            [
                .init(room: "r2", module: "bedroom", col: 0, row: 0),
                .init(room: "r3", module: "study", col: 1, row: 0),
                .init(room: "r1", module: "living", col: 0, row: 1),
            ],
            [
                .init(room: "r2", module: "bedroom", col: 0, row: 0),
                .init(room: "r3", module: "study", col: 1, row: 0),
                .init(room: "r1", module: "living", col: 0, row: 1),
                .init(room: "r4", module: "generic", col: 2, row: 1),
            ],
        ]
        var times: [Double] = []
        for layout in layouts {
            // warm-up
            _ = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images))
            let r = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images))
            times.append(r.milliseconds)
            #expect(r.unlit != nil && r.lit != nil)
            #expect(r.width > 100 && r.height > 100)
            #expect(r.milliseconds < 30, "compose took \(r.milliseconds) ms")
        }
        let med = times.sorted()[times.count / 2]
        print("HouseComposer times ms: \(times.map { String(format: "%.2f", $0) }) median=\(String(format: "%.2f", med))")
        #expect(med < 30)
    }

    @Test func gridTipMovesRightAndForward() {
        let a = HouseGrid.tip(col: 0, row: 0)
        let b = HouseGrid.tip(col: 1, row: 0)
        let c = HouseGrid.tip(col: 0, row: 1)
        #expect(b.x > a.x && b.y > a.y)
        #expect(c.x < a.x && c.y > a.y)
    }

    @Test func loadsCatalogAndComposesKitchenLayout() throws {
        let (cat, images) = try load()
        #expect(cat.modules["kitchen"] != nil)
        #expect(images["kitchen"] != nil)
        let layout = [
            HouseLayoutCell(room: "a", module: "bedroom", col: 0, row: 0),
            HouseLayoutCell(room: "b", module: "study", col: 1, row: 0),
            HouseLayoutCell(room: "c", module: "living", col: 0, row: 1),
            HouseLayoutCell(room: "d", module: "kitchen", col: 2, row: 1),
        ]
        let r = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images))
        #expect(r.lit != nil)
        #expect(r.milliseconds < 30)
        if let lit = r.lit, let data = r.pngData(lit) {
            let out = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("hp2chk/compose-test.png")
            try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: out)
            print("wrote \(out.path)")
        }
    }
}
