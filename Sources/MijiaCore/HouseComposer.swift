import Foundation
import CoreGraphics
import ImageIO

/// 模块图（同一时段）：全高墙版 + 切墙版（共享墙用）。切墙版缺省时退回全高版。
public struct HouseModuleImages {
    public var unlit: CGImage
    public var lit: CGImage
    public var unlitCut: CGImage?
    public var litCut: CGImage?
    public init(unlit: CGImage, lit: CGImage, unlitCut: CGImage? = nil, litCut: CGImage? = nil) {
        self.unlit = unlit; self.lit = lit; self.unlitCut = unlitCut; self.litCut = litCut
    }
}

/// 把模块按格子叠成整屋 unlit / lit（画家算法，后→前）。布局 / 时段变化时调用一次。
///
/// 规则（docs/HOUSE_MODULES.md）：
/// - 绘制顺序 (row, col) 升序；
/// - 每面共享墙只由前/右格子画，且切到 cutH（模块的切墙版），外墙全高；
/// - 墙顶厚度条、露出的墙端面、相邻模块接缝处的壁柱由合成器统一画（不同模块的墙纸接缝被盖住）；
/// - 整屋外轮廓描边；画布透明（不再铺底色）。
public enum HouseComposer {
    public struct Input {
        public var layout: [HouseLayoutCell]
        public var catalog: HouseModuleCatalog
        public var images: [String: HouseModuleImages]
        public var pad: Int
        /// 夜景：墙顶 / 端面 / 壁柱用压暗的木色（和模块夜景调色一致）
        public var night: Bool
        public init(layout: [HouseLayoutCell], catalog: HouseModuleCatalog, images: [String: HouseModuleImages], pad: Int = 24, night: Bool = false) {
            self.layout = layout; self.catalog = catalog; self.images = images; self.pad = pad; self.night = night
        }
    }

    public static func loadCatalog(from url: URL) throws -> HouseModuleCatalog {
        try JSONDecoder().decode(HouseModuleCatalog.self, from: Data(contentsOf: url))
    }

    public static func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }

    struct Item {
        var placed: HouseWallPlanner.Placed
        var art: HouseModuleArt
        var ox: Int   // 模块 PNG 左上角在画布中的位置
        var oy: Int
    }

    public static func compose(_ input: Input) -> HouseComposeResult {
        let t0 = CFAbsoluteTimeGetCurrent()
        var cells: [(HouseLayoutCell, Int)] = []
        var arts: [String: HouseModuleArt] = [:]
        var tips: [String: (x: Int, y: Int)] = [:]
        for c in input.layout {
            guard let art = input.catalog.modules[c.module] else { continue }
            cells.append((c, art.fw)); arts[c.module] = art
            tips[c.module] = (art.tip[0], art.tip[1])
        }
        let occ = HouseWallPlanner.occupancy(cells)
        let placed = HouseWallPlanner.plan(cells, tips: tips)
            .sorted { HouseGrid.painterKey(col: $0.cell.col, row: $0.cell.row) < HouseGrid.painterKey(col: $1.cell.col, row: $1.cell.row) }

        // 画布范围：所有剪影
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var items: [Item] = []
        for p in placed {
            guard let art = arts[p.cell.module] else { continue }
            let w = HouseGrid.tip(col: p.cell.col, row: p.cell.row)
            let it = Item(placed: p, art: art, ox: w.x - p.tip.x, oy: w.y - p.tip.y)
            for q in silhouette(p) {
                minX = min(minX, q.x + it.ox); maxX = max(maxX, q.x + it.ox)
                minY = min(minY, q.y + it.oy); maxY = max(maxY, q.y + it.oy)
            }
            items.append(it)
        }
        guard !items.isEmpty else {
            return HouseComposeResult(width: 1, height: 1, originX: 0, originY: 0, milliseconds: 0, moduleKeys: [],
                                      unlit: nil, lit: nil, sceneJSON: Data("{}".utf8))
        }
        let pad = input.pad
        let originX = minX - pad, originY = minY - pad - 6
        var width = maxX + pad - originX, height = maxY + pad - originY
        width += width % 2; height += height % 2

        let pal = Palette(night: input.night)
        let unlit = render(items, occ: occ, images: input.images, lit: false, pal: pal, originX: originX, originY: originY, width: width, height: height)
        let lit = render(items, occ: occ, images: input.images, lit: true, pal: pal, originX: originX, originY: originY, width: width, height: height)

        // 场景：锚点转画布坐标；visible = 本模块剪影减去后画模块的剪影（灯光蒙版用，避免透过前屋墙体）
        var sceneMods: [String: Any] = [:]
        for (i, it) in items.enumerated() {
            let dx = Double(it.ox - originX), dy = Double(it.oy - originY)
            func tx(_ p: [Double]) -> [Double] { [p[0] + dx, p[1] + dy] }
            var lights: [[String: Any]] = []
            for L in it.art.lights {
                var d: [String: Any] = ["id": L.id, "kind": L.kind ?? "lamp", "role": L.role ?? "light"]
                var hidden = false
                if let wall = L.wall {
                    hidden = isHidden(L, wall: wall, segments: it.placed.segments)
                    d["wall"] = wall
                    if hidden {
                        // 本体随墙一起被切掉：不再给本体多边形；灯光本身照旧（光池在地面上，来自全高版 lit 图）。
                        // App 把灯具位 / 设备徽章挪到 alt 地面点
                        d["hidden"] = true
                    }
                }
                // alt：墙挂灯具被切时的地面替代位；吸顶灯（没有本体）的编辑位落点
                if let a = L.alt, a.count >= 2 { d["alt"] = tx(a) }
                switch L.reveal {
                case .ellipse(let cx, let cy, let rx, let ry): d["reveal"] = [cx + dx, cy + dy, rx, ry]
                case .room: d["reveal"] = "room"
                case nil: break
                }
                for (k, poly) in [("shade", L.shade), ("screen", L.screen), ("core", L.core)] where !hidden {
                    if let poly { d[k] = poly.map(tx) }
                }
                lights.append(d)
            }
            let mine = path(silhouette(it.placed), dx: it.ox - originX, dy: it.oy - originY)
            var visible = mine
            for later in items[(i + 1)...] {
                visible = visible.subtracting(path(silhouette(later.placed), dx: later.ox - originX, dy: later.oy - originY))
            }
            let key = it.placed.cell.room.isEmpty ? it.placed.cell.module : it.placed.cell.room
            sceneMods[key] = [
                "module": it.placed.cell.module,
                "label": tx(it.art.label),
                "region": silhouette(it.placed).map { [Double($0.x) + dx, Double($0.y) + dy] },
                "visible": polygons(visible),
                "badges": it.art.badges.map(tx),
                "lights": lights,
                "col": it.placed.cell.col, "row": it.placed.cell.row,
                "walls": it.placed.segments.map { ["side": $0.side.rawValue, "height": $0.height] },
            ]
        }
        let scene: [String: Any] = ["size": [width, height], "origin": [originX, originY], "modules": sceneMods]
        let data = (try? JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys])) ?? Data()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return HouseComposeResult(width: width, height: height, originX: originX, originY: originY, milliseconds: ms,
                                  moduleKeys: items.map(\.placed.cell.module), unlit: unlit, lit: lit, sceneJSON: data)
    }

    // MARK: - 几何

    /// 模块剪影（模块内坐标，左上原点）：两面后墙按实际高度 + 地板 + 前沿地台
    static func silhouette(_ p: HouseWallPlanner.Placed) -> [(x: Int, y: Int)] {
        let T = p.tip, fw = p.fw
        let W = HouseGrid.W, FH = HouseGrid.floorH, S = HouseGrid.slab
        let R = (x: T.x + fw * W / 2, y: T.y + fw * FH / 2)
        let F = (x: T.x + (fw - 1) * W / 2, y: T.y + (fw + 1) * FH / 2)
        let L = (x: T.x - W / 2, y: T.y + FH / 2)
        let nw = p.segments.first { $0.side == .nw }?.height ?? HouseGrid.wallH
        let ne = p.segments.filter { $0.side == .ne }
        var pts: [(x: Int, y: Int)] = [(L.x, L.y - nw), (T.x, T.y - max(nw, ne.first?.height ?? 0))]
        for s in ne {
            pts.append((s.a.x, s.a.y - s.height))
            pts.append((s.b.x, s.b.y - s.height))
        }
        pts += [R, (R.x, R.y + S), (F.x, F.y + S), (L.x, L.y + S), L]
        return pts
    }

    static func path(_ pts: [(x: Int, y: Int)], dx: Int, dy: Int) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts.map { CGPoint(x: $0.x + dx, y: $0.y + dy) })
        p.closeSubpath()
        return p
    }

    static func polygons(_ path: CGPath) -> [[[Double]]] {
        var out: [[[Double]]] = []
        var cur: [[Double]] = []
        path.applyWithBlock { el in
            let e = el.pointee
            switch e.type {
            case .moveToPoint:
                if cur.count > 2 { out.append(cur) }
                cur = [[Double(e.points[0].x), Double(e.points[0].y)]]
            case .addLineToPoint:
                cur.append([Double(e.points[0].x), Double(e.points[0].y)])
            case .addQuadCurveToPoint:
                cur.append([Double(e.points[1].x), Double(e.points[1].y)])
            case .addCurveToPoint:
                cur.append([Double(e.points[2].x), Double(e.points[2].y)])
            case .closeSubpath:
                if cur.count > 2 { out.append(cur) }
                cur = []
            @unknown default: break
            }
        }
        if cur.count > 2 { out.append(cur) }
        return out
    }

    // MARK: - 渲染

    /// 墙顶 / 端面 / 壁柱的木色（取自经典整图的深色木饰条）；夜景按经典 day→night 的平均比例压暗
    struct Palette {
        let capTop, capEdge, endFace, pilaster, outline: CGColor
        init(night: Bool) {
            func c(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
                let k = night ? (0.46, 0.42, 0.44) : (1.0, 1.0, 1.0)
                return CGColor(red: r * k.0 / 255, green: g * k.1 / 255, blue: b * k.2 / 255, alpha: 1)
            }
            capTop = c(108, 66, 38); capEdge = c(38, 20, 11); endFace = c(72, 42, 24); pilaster = c(62, 36, 20)
            outline = CGColor(red: 10 / 255, green: 7 / 255, blue: 5 / 255, alpha: 0.92)
        }
    }

    /// 左上原点坐标 → CG 坐标
    final class Canvas {
        let ctx: CGContext
        let h: CGFloat
        init?(width: Int, height: Int) {
            guard let c = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            ctx = c; h = CGFloat(height)
            ctx.interpolationQuality = .none
            ctx.setShouldAntialias(false)
        }
        func pt(_ x: Int, _ y: Int) -> CGPoint { CGPoint(x: CGFloat(x), y: h - CGFloat(y)) }
        func poly(_ pts: [(x: Int, y: Int)], fill: CGColor, stroke: CGColor? = nil, lineWidth: CGFloat = 1) {
            let p = CGMutablePath()
            p.addLines(between: pts.map { pt($0.x, $0.y) })
            p.closeSubpath()
            ctx.addPath(p); ctx.setFillColor(fill); ctx.fillPath()
            if let stroke {
                ctx.addPath(p); ctx.setStrokeColor(stroke); ctx.setLineWidth(lineWidth); ctx.strokePath()
            }
        }
        func image(_ img: CGImage, x: Int, y: Int) {
            ctx.draw(img, in: CGRect(x: CGFloat(x), y: h - CGFloat(y + img.height), width: CGFloat(img.width), height: CGFloat(img.height)))
        }
    }

    /// 模块图：全高版为底，被切的墙段上方竖条换成切墙版（两版像素对齐）
    /// 墙挂灯具是否被切掉：找到 anchor 所在的那一段墙（按 x 范围）；没有 anchor 时看这一侧任一段。
    static func isHidden(_ L: HouseModuleLight, wall: String, segments: [HouseWallSegment]) -> Bool {
        let side: HouseWallSegment.Side = wall == "nw" ? .nw : .ne
        let segs = segments.filter { $0.side == side }
        if let a = L.anchor, a.count >= 2,
           let s = segs.first(where: { Double(min($0.a.x, $0.b.x)) <= a[0] && a[0] <= Double(max($0.a.x, $0.b.x)) }) {
            return s.height < HouseGrid.wallH
        }
        return segs.contains { $0.height < HouseGrid.wallH }
    }

    static func moduleImage(_ it: Item, _ imgs: HouseModuleImages, lit: Bool) -> CGImage {
        let full = lit ? imgs.lit : imgs.unlit
        guard let cut = lit ? imgs.litCut : imgs.unlitCut,
              it.placed.segments.contains(where: { $0.height < HouseGrid.wallH }),
              let c = Canvas(width: full.width, height: full.height) else { return full }
        c.image(full, x: 0, y: 0)
        let ne = it.placed.segments.filter { $0.side == .ne }
        for s in it.placed.segments where s.height < HouseGrid.wallH {
            // 竖条：两端点之间、地面边线以上；最左 / 最右段延伸到画布边
            var x0 = min(s.a.x, s.b.x), x1 = max(s.a.x, s.b.x)
            let y0 = s.a.x <= s.b.x ? s.a.y : s.b.y, y1 = s.a.x <= s.b.x ? s.b.y : s.a.y
            if s.side == .nw { x0 = 0 }
            if s.side == .ne, let last = ne.last, last == s { x1 = full.width }
            let strip: [(x: Int, y: Int)] = [(x0, 0), (x1, 0), (x1, y1), (x0, y0)]
            c.ctx.saveGState()
            let p = CGMutablePath()
            p.addLines(between: strip.map { c.pt($0.x, $0.y) }); p.closeSubpath()
            c.ctx.addPath(p); c.ctx.clip()
            c.ctx.clear(CGRect(x: 0, y: 0, width: full.width, height: full.height))
            c.image(cut, x: 0, y: 0)
            c.ctx.restoreGState()
        }
        return c.ctx.makeImage() ?? full
    }

    static func render(_ items: [Item], occ: Set<[Int]>, images: [String: HouseModuleImages], lit: Bool, pal: Palette,
                       originX: Int, originY: Int, width: Int, height: Int) -> CGImage? {
        guard let c = Canvas(width: width, height: height) else { return nil }
        func add(_ p: (x: Int, y: Int), _ q: (x: Int, y: Int)) -> (x: Int, y: Int) { (p.x + q.x, p.y + q.y) }

        // 外轮廓（所有剪影外扩描边）
        for it in items {
            let pts = silhouette(it.placed).map { (x: $0.x + it.ox - originX, y: $0.y + it.oy - originY) }
            c.poly(pts, fill: pal.outline, stroke: pal.outline, lineWidth: 5)
        }
        for it in items {
            let ox = it.ox - originX, oy = it.oy - originY
            func o(_ p: (x: Int, y: Int)) -> (x: Int, y: Int) { (p.x + ox, p.y + oy) }
            let p = it.placed, T = p.tip
            // 墙顶厚度条 / 端面 / 壁柱都在墙面“后方”（沿墙顶厚度方向偏移），先画，再盖模块图：
            // 靠墙摆的高家具（书架、落地灯、冰箱）自然挡住它们，不会被一条墙顶横杠切过去
            let col = p.cell.col, row = p.cell.row, fw = p.fw
            // 墙顶厚度条
            for s in p.segments {
                let off = s.side == .nw ? HouseGrid.capNW : HouseGrid.capNE
                let ua = (x: s.a.x, y: s.a.y - s.height), ub = (x: s.b.x, y: s.b.y - s.height)
                c.poly([o(ua), o(ub), o(add(ub, off)), o(add(ua, off))], fill: pal.capTop, stroke: pal.capEdge)
            }
            let hn = p.segments.first { $0.side == .nw }?.height ?? HouseGrid.wallH
            let ne = p.segments.filter { $0.side == .ne }
            let he = ne.first?.height ?? HouseGrid.wallH
            let hc = max(hn, he)
            let uT = (x: T.x, y: T.y - hc)
            c.poly([o(uT), o(add(uT, HouseGrid.capNW)), o(add(add(uT, HouseGrid.capNW), HouseGrid.capNE)), o(add(uT, HouseGrid.capNE))],
                   fill: pal.capTop, stroke: pal.capEdge)
            // 露出的墙端面：本墙比延续墙高的部分
            func endFace(_ at: (x: Int, y: Int), from lo: Int, to hi: Int, _ off: (x: Int, y: Int)) {
                guard hi > lo else { return }
                let a = (x: at.x, y: at.y - lo), b = (x: at.x, y: at.y - hi)
                c.poly([o(a), o(b), o(add(b, off)), o(add(a, off))], fill: pal.endFace, stroke: pal.capEdge)
            }
            let L = (x: T.x - HouseGrid.W / 2, y: T.y + HouseGrid.floorH / 2)
            let R = (x: T.x + fw * HouseGrid.W / 2, y: T.y + fw * HouseGrid.floorH / 2)
            endFace(L, from: HouseWallPlanner.nwHeight(occ, col, row + 1), to: hn, HouseGrid.capNW)
            endFace(R, from: HouseWallPlanner.neHeight(occ, col + fw, row), to: ne.last?.height ?? HouseGrid.wallH, HouseGrid.capNE)
            for (s0, s1) in zip(ne, ne.dropFirst()) where s0.height > s1.height {
                endFace(s0.b, from: s1.height, to: s0.height, HouseGrid.capNE)
            }
            // 后方邻居的墙在本格后角结束且比本墙高 → 它的端面朝前露出
            endFace(T, from: hn, to: HouseWallPlanner.nwHeight(occ, col, row - 1), HouseGrid.capNW)
            endFace(T, from: he, to: HouseWallPlanner.neHeight(occ, col - 1, row), HouseGrid.capNE)
            // 和邻居墙相接：壁柱盖住两张图的接缝
            if occ.contains([col - 1, row]) || occ.contains([col, row - 1]) {
                let x = T.x + ox, y = T.y + oy
                c.poly([(x - 3, y - hc), (x + 3, y - hc), (x + 3, y), (x - 3, y)], fill: pal.pilaster, stroke: pal.capEdge)
            }
            if let imgs = images[it.placed.cell.module] {
                c.image(moduleImage(it, imgs, lit: lit), x: ox, y: oy)
            }
        }
        return c.ctx.makeImage()
    }
}

extension HouseComposeResult {
    public func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
