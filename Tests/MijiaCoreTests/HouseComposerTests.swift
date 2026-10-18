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
            // 取三次里最快的一次：CI 机器上并行测试会偶尔抢走 CPU
            let runs = (0..<3).map { _ in HouseComposer.compose(.init(layout: layout, catalog: cat, images: images)) }
            let r = runs.min { $0.milliseconds < $1.milliseconds }!
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
        #expect((ac2["vent"] as? [[Double]])?.count == 2)   // 送风由 App 按 vent 动态画；隐藏时没有 vent
        #expect(ac["vent"] == nil)
        // 客厅空调在 NW 外墙（沙发上方）：最左列可见；左边有房间时隐藏、给 alt
        let lac = try lights([.init(room: "a", module: "bedroom", col: 0, row: 0), .init(room: "l", module: "living", col: 0, row: 1)], "l")
            .first { $0["id"] as? String == "ac" }!
        #expect(lac["hidden"] == nil && lac["vent"] != nil)
        let lac2 = try lights([.init(room: "g", module: "generic", col: 0, row: 1), .init(room: "l", module: "living", col: 1, row: 1)], "l")
            .first { $0["id"] as? String == "ac" }!
        #expect(lac2["hidden"] as? Bool == true && (lac2["alt"] as? [Double])?.count == 2)
        // 书房空调在 NE 外墙（窗右侧）：第一排可见；后面有房间时隐藏
        let sac = try lights([.init(room: "s", module: "study", col: 0, row: 0)], "s").first { $0["id"] as? String == "ac" }!
        #expect(sac["hidden"] == nil && sac["vent"] != nil)
        let sac2 = try lights([.init(room: "b", module: "bedroom", col: 0, row: 0), .init(room: "s", module: "study", col: 0, row: 1)], "s")
            .first { $0["id"] as? String == "ac" }!
        #expect(sac2["hidden"] as? Bool == true)
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

    /// 错层：抬高的格子整体上移 elev，地台加厚到最低一格的底面；剪影 / 场景坐标跟着走
    @Test func splitLevelsShiftModulesAndThickenSlabs() throws {
        let (cat, images) = try Self.load()
        func scene(_ layout: [HouseLayoutCell]) throws -> [String: [String: Any]] {
            let r = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images))
            let j = try #require(try JSONSerialization.jsonObject(with: r.sceneJSON) as? [String: Any])
            return try #require(j["modules"] as? [String: [String: Any]])
        }
        func top(_ m: [String: Any]) -> Double { (m["region"] as! [[Double]]).map { $0[1] }.min()! }
        func bottom(_ m: [String: Any]) -> Double { (m["region"] as! [[Double]]).map { $0[1] }.max()! }
        func label(_ m: [String: Any]) -> [Double] { m["label"] as! [Double] }
        let flat = try scene([.init(room: "a", module: "bedroom", col: 0, row: 0, level: 0),
                              .init(room: "l", module: "living", col: 0, row: 1, level: 0)])
        let up = try scene([.init(room: "a", module: "bedroom", col: 0, row: 0, level: 1),
                            .init(room: "l", module: "living", col: 0, row: 1, level: 0)])
        #expect(up["a"]?["elevation"] as? Int == HouseGrid.levelStep)
        #expect(up["a"]?["level"] as? Int == 1 && up["l"]?["level"] as? Int == 0)
        // 卧室相对客厅上移一级：墙顶、标签都高一级（levelStep）；底边（加厚的地台）和客厅一样落到同一个地面
        let dTop = (top(flat["a"]!) - top(flat["l"]!)) - (top(up["a"]!) - top(up["l"]!))
        #expect(abs(dTop - Double(HouseGrid.levelStep)) < 0.5)
        let dLab = (label(flat["a"]!)[1] - label(flat["l"]!)[1]) - (label(up["a"]!)[1] - label(up["l"]!)[1])
        #expect(abs(dLab - Double(HouseGrid.levelStep)) < 0.5)
        #expect(abs((bottom(up["a"]!) - top(up["a"]!)) - (bottom(flat["a"]!) - top(flat["a"]!)) - Double(HouseGrid.levelStep)) < 0.5)
        // 自动图案：level 为空 → 后排左格 +1、前排左格 0
        let auto = try scene([.init(room: "a", module: "bedroom", col: 0, row: 0), .init(room: "l", module: "living", col: 0, row: 1)])
        #expect(auto["a"]?["level"] as? Int == 1 && auto["l"]?["level"] as? Int == 0)
        // 前方邻格更高 → 本格徽章往里挪同样的高差（不会被高出来的切墙压住）；前方更低 → 不动
        func badges(_ m: [String: Any]) -> [[Double]] { m["badges"] as! [[Double]] }
        let lowBack = try scene([.init(room: "a", module: "bedroom", col: 0, row: 0, level: 0),
                                 .init(room: "l", module: "living", col: 0, row: 1, level: 1)])
        let fb = badges(flat["a"]!).map { $0[1] - top(flat["a"]!) }, lb = badges(lowBack["a"]!).map { $0[1] - top(lowBack["a"]!) }
        let ub = badges(up["a"]!).map { $0[1] - top(up["a"]!) }
        #expect(zip(fb, lb).allSatisfy { $0 >= $1 - 0.01 } && zip(fb, lb).contains { $0 > $1 + 1 })
        #expect(zip(fb, ub).allSatisfy { $0 <= $1 + 0.01 })
    }

    /// 后格比前格高两级：前格切墙（40）挡不住高出来的那截地台——那里要画出石砌基座（不透明、偏灰），不能是透明或描边色
    @Test func raisedRoomShowsStonePlinthAboveFrontCutWall() throws {
        let (cat, images) = try Self.load("day")
        func pixel(_ img: CGImage, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            var px = [UInt8](repeating: 0, count: 4)
            let ctx = CGContext(data: &px, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: -x, y: y - img.height + 1, width: img.width, height: img.height))
            return (Int(px[0]), Int(px[1]), Int(px[2]), Int(px[3]))
        }
        let r = HouseComposer.compose(.init(layout: [.init(room: "a", module: "bedroom", col: 0, row: 0, level: 1),
                                                     .init(room: "l", module: "living", col: 0, row: 1, level: -1)],
                                            catalog: cat, images: images))
        let img = try #require(r.unlit)
        // 卧室前沿（v=1）u=0.5 处的地面点；卧室比客厅高 2·levelStep，客厅切墙顶在它下方 2·step − cutH
        let tipX = -r.originX, tipY = -r.originY - HouseGrid.levelStep
        let ex = tipX - HouseGrid.W / 4, ey = tipY + 3 * HouseGrid.floorH / 4
        let gap = 2 * HouseGrid.levelStep - HouseGrid.cutH
        #expect(gap > HouseGrid.slab + 8)
        let p = pixel(img, ex, ey + HouseGrid.slab + (gap - HouseGrid.slab) / 2)
        #expect(p.a == 255)
        #expect(abs(p.r - p.b) < 50 && p.r > 30)   // 石头偏灰；木地台 / 墙纸都偏橙
    }

    /// 地面房间名标签不压徽章位；除了挤的阳台，也不压吸顶灯 / 被切灯具的 alt 位置框（含 App 里前右格放玄关的布局）
    @Test func floorLabelsClearBadgesAndAltSpots() throws {
        let (cat, images) = try Self.load("day")
        var all = Self.layouts
        all["six-entrance"] = Self.layouts["six"]!.map { var c = $0; if c.room == "d" { c.module = "generic" }; return c }
        for (name, layout) in all {
            let r = HouseComposer.compose(.init(layout: layout, catalog: cat, images: images))
            let j = try #require(try JSONSerialization.jsonObject(with: r.sceneJSON) as? [String: Any])
            let mods = try #require(j["modules"] as? [String: [String: Any]])
            for (room, m) in mods {
                let l = try #require(m["label"] as? [Double])
                for b in (m["badges"] as? [[Double]]) ?? [] {
                    #expect(!(abs(l[0] - b[0]) < 46 && l[1] > b[1] - 56 && l[1] < b[1] + 14), "\(name)/\(room) label on badge")
                }
                for L in (m["lights"] as? [[String: Any]]) ?? [] {
                    // 阳台太挤（三徽章围着吸顶灯位），只保证不压徽章
                    guard m["module"] as? String != "balcony",
                          let a = L["alt"] as? [Double], (L["kind"] as? String) == "ceiling" || (L["hidden"] as? Bool) == true else { continue }
                    #expect(!(abs(l[0] - a[0]) < 56 && l[1] > a[1] - 46 && l[1] < a[1] + 36), "\(name)/\(room) label \(l) on alt spot \(a); badges \((m["badges"] as? [[Double]]) ?? [])")
                }
            }
        }
    }

    @Test func levelPatternAndClamp() {
        #expect(HouseLevels.auto(col: 0, row: 0) == 1 && HouseLevels.auto(col: 2, row: 1) == -1 && HouseLevels.auto(col: 5, row: 5) == 0)
        #expect(HouseLevels.effective(.init(room: "x", module: "generic", col: 0, row: 0, level: 7)) == HouseGrid.levelRange.upperBound)
        // 任意相邻两格（自动图案）最多差两级；一级高过切墙（台阶侧面看得见），两级仍低于整面墙高
        for r in 0..<2 { for c in 0..<3 {
            for (dc, dr) in [(1, 0), (0, 1)] where c + dc < 3 && r + dr < 2 {
                #expect(abs(HouseLevels.auto(col: c, row: r) - HouseLevels.auto(col: c + dc, row: r + dr)) <= 2)
            }
        } }
        #expect(HouseGrid.levelStep > HouseGrid.cutH)
        #expect((HouseGrid.levelRange.upperBound - HouseGrid.levelRange.lowerBound) * HouseGrid.levelStep < HouseGrid.wallH)
    }

    @Test func layoutCellLevelIsOptionalInJSON() throws {
        let old = try JSONDecoder().decode(HouseLayoutCell.self, from: Data(#"{"room":"a","module":"bedroom","col":0,"row":0}"#.utf8))
        #expect(old.level == nil)
        let enc = String(decoding: try JSONEncoder().encode(old), as: UTF8.self)
        #expect(!enc.contains("level"))
        var c = old; c.level = -1
        let back = try JSONDecoder().decode(HouseLayoutCell.self, from: try JSONEncoder().encode(c))
        #expect(back.level == -1)
    }

    /// HOUSE_COMPOSE_OUT=/path swift test --filter writesSpikeImages → 各布局 day/night × unlit/lit PNG
    @Test func writesSpikeImages() throws {
        guard let out = ProcessInfo.processInfo.environment["HOUSE_COMPOSE_OUT"] else { return }
        let dir = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var lines: [String] = []
        for phase in ["day", "night"] {
            let (cat, images) = try Self.load(phase)
            // 默认（自动错层）+ 平铺对照（-flat）
            let all = Self.layouts.flatMap { name, layout in
                [(name, layout), (name + "-flat", layout.map { var c = $0; c.level = 0; return c })]
            }
            for (name, layout) in all {
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
