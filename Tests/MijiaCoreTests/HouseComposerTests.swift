import Foundation
import Testing
import CoreGraphics
@testable import MijiaCore

@Suite struct HouseComposerTests {
    static let modulesDir: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("assets/house/modules")
    }()

    static func load(_ phase: String = "night") throws -> (HouseModuleCatalog, [String: HouseModuleImages]) {
        let cat = try HouseComposer.loadCatalog(from: modulesDir.appendingPathComponent("catalog.json"))
        var images: [String: HouseModuleImages] = [:]
        func img(_ v: [String: String], _ k: String) -> CGImage? {
            v[k].flatMap { HouseComposer.loadCGImage(from: modulesDir.appendingPathComponent($0)) }
        }
        for (id, art) in cat.modules {
            guard let v = art.variants, let u = img(v, "\(phase)-unlit"), let l = img(v, "\(phase)-lit") else { continue }
            images[id] = HouseModuleImages(unlit: u, lit: l, unlitCut: img(v, "\(phase)-unlit-cut"), litCut: img(v, "\(phase)-lit-cut"))
        }
        return (cat, images)
    }

    static let layouts: [String: [HouseLayoutCell]] = [
        "two": [.init(room: "a", module: "bedroom", col: 0, row: 0), .init(room: "b", module: "kitchen", col: 1, row: 0)],
        "three": [.init(room: "a", module: "bedroom", col: 0, row: 0), .init(room: "b", module: "study", col: 1, row: 0),
                  .init(room: "c", module: "living", col: 0, row: 1)],
        "four": [.init(room: "a", module: "bedroom", col: 0, row: 0), .init(room: "b", module: "study", col: 1, row: 0),
                 .init(room: "c", module: "living", col: 0, row: 1), .init(room: "d", module: "kitchen", col: 2, row: 1)],
        "six": [.init(room: "a", module: "bedroom", col: 0, row: 0), .init(room: "b", module: "study", col: 1, row: 0),
                .init(room: "e", module: "bathroom", col: 2, row: 0), .init(room: "c", module: "living", col: 0, row: 1),
                .init(room: "d", module: "kitchen", col: 2, row: 1)],
        "six-cells": [.init(room: "a", module: "bedroom", col: 0, row: 0), .init(room: "b", module: "study", col: 1, row: 0),
                      .init(room: "e", module: "bathroom", col: 2, row: 0), .init(room: "f", module: "generic", col: 0, row: 1),
                      .init(room: "g", module: "balcony", col: 1, row: 1), .init(room: "d", module: "kitchen", col: 2, row: 1)],
    ]

    @Test func composesLayoutsUnder30ms() throws {
        let (cat, images) = try Self.load()
        #expect(images.count == 7)
        var times: [String: Double] = [:]
        for (name, layout) in Self.layouts.sorted(by: { $0.key < $1.key }) {
            _ = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images))
            let r = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images))
            times[name] = r.milliseconds
            #expect(r.unlit != nil && r.lit != nil)
            #expect(r.milliseconds < 30, "\(name) compose took \(r.milliseconds) ms")
        }
        print("HouseComposer ms: " + times.sorted { $0.key < $1.key }.map { "\($0.key)=\(String(format: "%.2f", $0.value))" }.joined(separator: " "))
    }

    @Test func sharedWallsHaveOneOwnerAndAreCut() {
        let six = Self.layouts["six-cells"]!
        let cells = six.map { ($0, 1) }
        let tips = Dictionary(uniqueKeysWithValues: six.map { ($0.module, (x: 200, y: 140)) })
        let plan = HouseWallPlanner.plan(cells, tips: tips)
        func seg(_ room: String, _ side: HouseWallSegment.Side) -> Int {
            plan.first { $0.cell.room == room }!.segments.first { $0.side == side }!.height
        }
        // 后排：外墙全高
        #expect(seg("a", .nw) == HouseGrid.wallH && seg("a", .ne) == HouseGrid.wallH)
        #expect(seg("b", .nw) == HouseGrid.cutH)   // 与 a 共享 → b 拥有并切低
        #expect(seg("b", .ne) == HouseGrid.wallH)
        // 前排：NE 墙与后排共享 → 切低；col 0 的 NW 是外墙
        #expect(seg("f", .nw) == HouseGrid.wallH && seg("f", .ne) == HouseGrid.cutH)
        #expect(seg("g", .nw) == HouseGrid.cutH && seg("g", .ne) == HouseGrid.cutH)
    }

    @Test func livingSpanningTwoCellsCutsOnlyCoveredSegment() {
        let layout = [HouseLayoutCell(room: "a", module: "bedroom", col: 0, row: 0),
                      HouseLayoutCell(room: "l", module: "living", col: 0, row: 1)]
        let plan = HouseWallPlanner.plan([(layout[0], 1), (layout[1], 2)], tips: ["bedroom": (0, 0), "living": (0, 0)])
        let ne = plan[1].segments.filter { $0.side == .ne }.map(\.height)
        #expect(ne == [HouseGrid.cutH, HouseGrid.wallH])
    }

    @Test func painterOrderIsBackToFront() throws {
        let (cat, images) = try Self.load()
        let r = HouseComposer.compose(.init(layout: Self.layouts["six"]!, catalog: cat, images: images))
        // moduleKeys 按绘制顺序：先整排 row 0（col 升序），再 row 1
        #expect(r.moduleKeys == ["bedroom", "study", "bathroom", "living", "kitchen"])
    }

    @Test func visibleRegionsDoNotOverlap() throws {
        let (cat, images) = try Self.load()
        let r = HouseComposer.compose(.init(layout: Self.layouts["six-cells"]!, catalog: cat, images: images))
        let scene = try #require(try JSONSerialization.jsonObject(with: r.sceneJSON) as? [String: Any])
        let mods = try #require(scene["modules"] as? [String: [String: Any]])
        var paths: [CGPath] = []
        for (_, m) in mods {
            let polys = try #require(m["visible"] as? [[[Double]]])
            let p = CGMutablePath()
            for poly in polys { p.addLines(between: poly.map { CGPoint(x: $0[0], y: $0[1]) }); p.closeSubpath() }
            paths.append(p)
        }
        for i in paths.indices {
            for j in paths.indices where j > i {
                let inter = paths[i].intersection(paths[j]).boundingBoxOfPath
                let area = inter.isNull ? 0 : inter.width * inter.height
                #expect(area < 40, "regions \(i) and \(j) overlap \(area)")
            }
        }
    }

    /// 墙挂灯具只在“它所在的那一段墙”被切时才算隐藏；隐藏后不给本体多边形，空调给 alt 徽章位
    @Test func wallFixturesHideOnlyWithTheirSegment() throws {
        let (cat, images) = try Self.load()
        func lights(_ layout: [HouseLayoutCell], _ room: String) throws -> [[String: Any]] {
            let r = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images))
            let j = try JSONSerialization.jsonObject(with: r.sceneJSON) as! [String: Any]
            let mods = j["modules"] as! [String: Any]
            return (mods[room] as! [String: Any])["lights"] as! [[String: Any]]
        }
        // 卧室的空调挂在 NW 墙；左边有房间 → NW 墙被切 → 空调隐藏、给 alt
        let ac = try lights([.init(room: "g", module: "generic", col: 0, row: 0),
                             .init(room: "b", module: "bedroom", col: 1, row: 0)], "b").first { $0["id"] as? String == "ac" }!
        #expect(ac["hidden"] as? Bool == true)
        #expect(ac["core"] == nil)
        #expect((ac["alt"] as? [Double])?.count == 2)
        // 左边没房间 → 空调可见
        let ac2 = try lights([.init(room: "b", module: "bedroom", col: 0, row: 0)], "b").first { $0["id"] as? String == "ac" }!
        #expect(ac2["hidden"] == nil)
        #expect(ac2["core"] != nil)
        // 客厅壁灯在 NE 第 0 段；只有第 1 段后面有房间 → 壁灯不隐藏
        let sc = try lights([.init(room: "s", module: "study", col: 1, row: 0),
                             .init(room: "l", module: "living", col: 0, row: 1)], "l").first { $0["id"] as? String == "sconce" }!
        #expect(sc["hidden"] == nil)
        // 第 0 段后面也有房间 → 隐藏
        let sc2 = try lights([.init(room: "a", module: "bedroom", col: 0, row: 0), .init(room: "s", module: "study", col: 1, row: 0),
                              .init(room: "l", module: "living", col: 0, row: 1)], "l").first { $0["id"] as? String == "sconce" }!
        #expect(sc2["hidden"] as? Bool == true)
        #expect(sc2["shade"] == nil)
        // 壁灯被切时给地面 alt 点（App 把灯具位 / 设备徽章挪过去）
        #expect((sc2["alt"] as? [Double])?.count == 2)
    }

    @Test func gridTipMovesRightAndForward() {
        let a = HouseGrid.tip(col: 0, row: 0)
        let b = HouseGrid.tip(col: 1, row: 0)
        let c = HouseGrid.tip(col: 0, row: 1)
        #expect(b.x > a.x && b.y > a.y)
        #expect(c.x < a.x && c.y > a.y)
    }

    /// HOUSE_COMPOSE_OUT=/path swift test --filter writesSpikeImages → 各布局 day/night × unlit/lit PNG
    @Test func writesSpikeImages() throws {
        guard let out = ProcessInfo.processInfo.environment["HOUSE_COMPOSE_OUT"] else { return }
        let dir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines: [String] = []
        for phase in ["day", "night"] {
            let (cat, images) = try Self.load(phase)
            for (name, layout) in Self.layouts {
                _ = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images, night: phase == "night"))
                let r = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images, night: phase == "night"))
                lines.append("\(name) \(phase) \(r.width)x\(r.height) \(String(format: "%.2f", r.milliseconds)) ms")
                for (kind, img) in [("unlit", r.unlit), ("lit", r.lit)] {
                    guard let img, let data = r.pngData(img) else { continue }
                    try data.write(to: dir.appendingPathComponent("\(name)-\(phase)-\(kind).png"))
                }
                try r.sceneJSON.write(to: dir.appendingPathComponent("\(name)-\(phase).json"))
            }
        }
        try lines.sorted().joined(separator: "\n").write(to: dir.appendingPathComponent("timings.txt"), atomically: true, encoding: .utf8)
    }
}
