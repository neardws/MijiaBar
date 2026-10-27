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
/// - 整屋外轮廓描边；画布透明（不再铺底色）；
/// - 错层：每格按 `HouseLevels` 整体上移 elev 像素，地台加厚到全屋最低一格的底面；露出的墙端面按绝对高度算。
public enum HouseComposer {
    public struct Input {
        public var layout: [HouseLayoutCell]
        public var catalog: HouseModuleCatalog
        public var images: [String: HouseModuleImages]
        public var pad: Int
        /// 夜景：墙顶 / 端面 / 壁柱用压暗的木色（和模块夜景调色一致）
        public var night: Bool
        public var wallCaps: HouseWallCapColors?
        public var decor: [HouseDecorImage]
        public init(layout: [HouseLayoutCell], catalog: HouseModuleCatalog, images: [String: HouseModuleImages], pad: Int = 24, night: Bool = false,
                    wallCaps: HouseWallCapColors? = nil, decor: [HouseDecorImage] = []) {
            self.layout = layout; self.catalog = catalog; self.images = images; self.pad = pad; self.night = night
            self.wallCaps = wallCaps
            self.decor = decor
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
        var ox: Int   // 模块 PNG 左上角在画布中的位置（已含错层上移）
        var oy: Int
        /// 地台在模块自带的 slab 之下再加厚多少（= 本格 elev − 全屋最低 elev）
        var ext: Int = 0
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
        let elev = HouseLevels.elevations(cells)
        let base = elev.values.min() ?? 0
        let placed = HouseWallPlanner.plan(cells, tips: tips)
            .sorted { HouseGrid.painterKey(col: $0.cell.col, row: $0.cell.row) < HouseGrid.painterKey(col: $1.cell.col, row: $1.cell.row) }

        // 画布范围：所有剪影
        var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min
        var items: [Item] = []
        for p in placed {
            guard let art = arts[p.cell.module] else { continue }
            let w = HouseGrid.tip(col: p.cell.col, row: p.cell.row)
            let it = Item(placed: p, art: art, ox: w.x - p.tip.x, oy: w.y - p.tip.y - p.elev, ext: p.elev - base)
            for q in silhouette(p, ext: it.ext) {
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

        let pal = Palette(night: input.night, wallCaps: input.wallCaps)
        let doorways = HouseDoorwayPlanner.plan(layout: input.layout, catalog: input.catalog)
        let unlit = render(items, occ: occ, elev: elev, images: input.images, decor: input.decor, doorways: doorways, lit: false, pal: pal, originX: originX, originY: originY, width: width, height: height)
        let lit = render(items, occ: occ, elev: elev, images: input.images, decor: input.decor, doorways: doorways, lit: true, pal: pal, originX: originX, originY: originY, width: width, height: height)

        func visibleShape(_ item: Item) -> CGPath {
            var shape = path(silhouette(item.placed, ext: item.ext), dx: item.ox - originX, dy: item.oy - originY)
            for doorway in doorways where doorway.front == item.placed.cell {
                shape = shape.subtracting(doorwayOpening(doorway, originX: originX, originY: originY))
            }
            return shape
        }
        let shapes = items.map(visibleShape)

        // 场景：锚点转画布坐标；visible = 本模块剪影减去后画模块的剪影（灯光蒙版用，避免透过前屋墙体）
        var sceneMods: [String: Any] = [:]
        var decorSlots: [[String: Any]] = []
        for (i, it) in items.enumerated() {
            let dx = Double(it.ox - originX), dy = Double(it.oy - originY)
            func tx(_ p: [Double]) -> [Double] { [p[0] + dx, p[1] + dy] }
            // 地面上的点（徽章、alt 替代位）如果落在前面（右前 / 左前）邻格的切墙后面——错层时那堵墙更高——
            // 就沿地面挪进房间（floorPointLift），徽章脚不会被墙压住
            let passagePoints = doorways.filter { $0.back == it.placed.cell || $0.front == it.placed.cell }.map { doorway -> [Double] in
                let point = doorwayPoint(doorway, along: doorway.center, elevation: Double(HouseLevels.elevation(it.placed.cell)), originX: originX, originY: originY)
                return [Double(point.x) - dx, Double(point.y) - dy]
            }
            let badgePts = floorBadges(it.art.badges, placed: it.placed, elev: elev).map { clearOfBadges($0, passagePoints, minD: 42) }
            var lights: [[String: Any]] = []
            var altPts: [[Double]] = []
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
                if let a = L.alt, a.count >= 2 {
                    var q = floorPointLift(a, placed: it.placed, elev: elev)
                    if hidden, let a2 = L.alt2, a2.count >= 2 {
                        // alt 被前排切墙挡住要往里挪（挪进房间可能压到家具）→ 用挪动更少的备选位
                        let q2 = floorPointLift(a2, placed: it.placed, elev: elev)
                        if hypot(q2[0] - a2[0], q2[1] - a2[1]) + 2 < hypot(q[0] - a[0], q[1] - a[1]) { q = q2 }
                    }
                    // 吸顶灯的编辑位：离徽章太近时往上（天花板方向）让开；被切的墙挂灯具：alt 是素材里挑好的空地，
                    // 只在合成后徽章位挪得太近时小幅让开（最多 12px），不会被推到床 / 桌子上
                    if L.kind == "ceiling" { q = clearOfBadges(q, badgePts); altPts.append(q) }
                    else if hidden { q = clearOfBadges(q, badgePts, minD: 30, maxUp: 12); altPts.append(q) }
                    q = clearOfBadges(q, passagePoints, minD: 42)
                    d["alt"] = tx(q)
                }
                switch L.reveal {
                case .ellipse(let cx, let cy, let rx, let ry): d["reveal"] = [cx + dx, cy + dy, rx, ry]
                case .room: d["reveal"] = "room"
                case nil: break
                }
                for (k, poly) in [("shade", L.shade), ("screen", L.screen), ("core", L.core), ("vent", L.vent),
                                  ("quad", L.quad), ("display", L.display), ("body", L.body)] where !hidden {
                    if let poly { d[k] = poly.map(tx) }
                }
                if !hidden {
                    // 窗帘贴片 / 家电指示灯：跟着模块平移（墙被切掉时和本体一起不画）
                    if let p = L.patch { d["patch"] = p }
                    if let r = L.rect, r.count == 4 { d["rect"] = [r[0] + dx, r[1] + dy, r[2], r[3]] }
                    if let m = L.mid { d["mid"] = m + dx }
                    if let l = L.led, l.count >= 2 { d["led"] = tx(l) }
                    if let door = L.door {
                        var dd: [String: Any] = ["c": tx(door.c), "s": door.s, "t": door.t, "r": door.r]
                        if let ry = door.ry { dd["ry"] = ry }
                        d["door"] = dd
                    }
                }
                lights.append(d)
            }
            let mine = shapes[i]
            var visible = mine
            var petVisible = mine
            let passages = doorways.filter { $0.back == it.placed.cell || $0.front == it.placed.cell }
            for doorway in passages {
                petVisible = petVisible.union(doorwayOpening(doorway, originX: originX, originY: originY))
            }
            for later in shapes[(i + 1)...] {
                visible = visible.subtracting(later)
                if !passages.isEmpty { petVisible = petVisible.subtracting(later) }
            }
            let key = it.placed.cell.room.isEmpty ? it.placed.cell.module : it.placed.cell.room
            for slot in it.art.decor ?? [] where slot.at.count == 2 {
                let placed = input.decor.first { $0.placement.room == key && $0.placement.slot == slot.id }
                var record: [String: Any] = ["room": key, "slot": slot.id, "surface": slot.surface, "sizes": slot.sizes,
                                             "x": slot.at[0] + dx, "y": slot.at[1] + dy]
                if let wall = slot.wall {
                    record["wall"] = wall
                    if wallIsHidden(wall: wall, anchor: slot.at, segments: it.placed.segments) { record["hidden"] = "wall cut" }
                }
                if let placed {
                    record["item"] = placed.placement.item
                    record["rect"] = [Double(placed.x) + dx, Double(placed.y) + dy, Double(placed.image.width), Double(placed.image.height)]
                } else { record["rect"] = [slot.at[0] + dx - 12, slot.at[1] + dy - 12, 24, 24] }
                decorSlots.append(record)
            }
            var record: [String: Any] = [
                "module": it.placed.cell.module,
                "label": tx(clearLabel(floorPointLift(labelPoint(it.art, segments: it.placed.segments), placed: it.placed, elev: elev), badgePts, alts: altPts)),
                "region": silhouette(it.placed, ext: it.ext).map { [Double($0.x) + dx, Double($0.y) + dy] },
                "level": HouseLevels.effective(it.placed.cell), "elevation": it.placed.elev,
                "visible": polygons(visible),
                "badges": badgePts.map(tx),
                "lights": lights,
                "col": it.placed.cell.col, "row": it.placed.cell.row,
                "walls": it.placed.segments.map { ["side": $0.side.rawValue, "height": $0.height] },
            ]
            if !passages.isEmpty { record["petVisible"] = polygons(petVisible) }
            sceneMods[key] = record
        }
        let scene: [String: Any] = ["size": [width, height], "origin": [originX, originY], "modules": sceneMods, "decorSlots": decorSlots]
        let data = (try? JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys])) ?? Data()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return HouseComposeResult(width: width, height: height, originX: originX, originY: originY, milliseconds: ms,
                                  moduleKeys: items.map(\.placed.cell.module), unlit: unlit, lit: lit, sceneJSON: data)
    }

    // MARK: - 几何

    /// 房间名牌（地面上的那种）压在徽章上时往上让开到徽章顶上方
    /// 地面房间名标签：不压徽章（脚点在下、图标往上约 56px），也不压 alt 位置框（圆框半径约 25px、上面还有名字）。
    /// 先原地，再左右让开，最后才挪到徽章上方；都不行就保持原地
    static func clearLabel(_ p: [Double], _ badges: [[Double]], alts: [[Double]] = []) -> [Double] {
        func onBadge(_ q: [Double]) -> Bool {
            badges.contains { $0.count >= 2 && abs(q[0] - $0[0]) < 46 && q[1] > $0[1] - 56 && q[1] < $0[1] + 14 }
        }
        func onAlt(_ q: [Double]) -> Bool {
            alts.contains { $0.count >= 2 && abs(q[0] - $0[0]) < 56 && q[1] > $0[1] - 46 && q[1] < $0[1] + 36 }
        }
        if !onBadge(p) && !onAlt(p) { return p }
        var cands: [[Double]] = [p]
        for dx in [52.0, -52, 84, -84] { cands.append([p[0] + dx, p[1]]) }
        for b in badges where b.count >= 2 {
            for dx in [0.0, 52, -52, 84, -84] { cands.append([p[0] + dx, b[1] - 58]) }
        }
        // 两样都避开最好；实在挤（阳台：三个徽章围着一个吸顶灯位）就至少别压徽章——alt 框只在编辑模式出现
        return cands.first { !onBadge($0) && !onAlt($0) } ?? cands.first { !onBadge($0) } ?? p
    }

    /// alt 位置框和徽章位至少隔 minD：只往上挪（最多 60px）
    static func clearOfBadges(_ p: [Double], _ badges: [[Double]], minD: Double = 54, maxUp: Double = 60) -> [Double] {
        var q = p
        for _ in 0..<3 {
            for b in badges where b.count >= 2 {
                let dx = q[0] - b[0], dy = q[1] - b[1]
                guard (dx * dx + dy * dy).squareRoot() < minD, abs(dx) < minD else { continue }
                q[1] = min(q[1], b[1] - (minD * minD - dx * dx).squareRoot())
            }
        }
        q[1] = max(q[1], p[1] - maxUp)
        return q
    }

    /// 徽章：挪出前方切墙的遮挡 → 拉开距离 → 再检查一遍遮挡（拉开时可能又横移回墙后），两轮
    static func floorBadges(_ pts: [[Double]], placed: HouseWallPlanner.Placed, elev: [[Int]: Int]) -> [[Double]] {
        var q = pts
        for _ in 0..<2 {
            q = separated(q.map { floorPointLift($0, placed: placed, elev: elev) })
        }
        return q.map { floorPointLift($0, placed: placed, elev: elev) }
    }

    /// 徽章挪进房间后可能挤到一起（一个往 −u、一个往 −v）：两两距离不到 minD 的，沿 x 各让一半
    static func separated(_ pts: [[Double]], minD: Double = 54) -> [[Double]] {
        var q = pts
        for _ in 0..<4 {
            for i in q.indices { for j in q.indices where j > i && q[i].count >= 2 && q[j].count >= 2 {
                let dx = q[j][0] - q[i][0], dy = q[j][1] - q[i][1], d = (dx * dx + dy * dy).squareRoot()
                guard d < minD else { continue }
                let need = (minD * minD - dy * dy).squareRoot() - abs(dx)
                guard need > 0 else { continue }
                let sgn: Double = dx >= 0 ? 1 : -1
                q[i][0] -= sgn * need / 2; q[j][0] += sgn * need / 2
            } }
        }
        return q
    }

    /// 模块内一个地面点如果被前方邻格的切墙（高 cutH + 两格高差）挡住，就沿地面往房间里面挪
    /// （挡在左前沿 → 往 −v 走，挡在右前沿 → 往 −u 走），直到露在墙顶之上 4px；最多挪到离后沿 0.12 格。
    /// 沿地面走而不是竖直上移：同一房间的几个徽章相对位置不变，不会挤到一起。前方没有邻格（剖面敞开）→ 不动。
    static func floorPointLift(_ pt: [Double], placed p: HouseWallPlanner.Placed, elev: [[Int]: Int]) -> [Double] {
        guard pt.count >= 2 else { return pt }
        let half = Double(HouseGrid.W / 2), fh = Double(HouseGrid.floorH / 2), fw = Double(p.fw)
        let c = p.cell.col, r = p.cell.row
        func wallTop(_ edgeY: Double, _ n: [Int]) -> Double? {
            guard let e = elev[n] else { return nil }
            return edgeY - Double(HouseGrid.cutH + e - p.elev)
        }
        var a = pt[0] - Double(p.tip.x), b = pt[1] - Double(p.tip.y)
        // 左前沿 v = 1：同一 x 上的沿线点 u = 1 + a/(W/2)；墙顶随 x 变，沿 −v 走 t 格时点和墙顶一起变，
        // 点的 y 每格减 fh、同一 x 上的墙顶 y 每格加 fh → 相对每格 2·fh
        do {
            let u = 1 + a / half, v = (b / fh - a / half) / 2
            if u >= 0, u <= fw, let top = wallTop((u + 1) * fh, [c + min(p.fw - 1, Int(u)), r + 1]) {
                let need = b - (top - 4)
                if need > 0 { let t = min(need / (2 * fh), max(0, v - 0.12)); a += t * half; b -= t * fh }
            }
        }
        // 右前沿 u = fw：沿线点 v = fw − a/(W/2)；沿 −u 走
        do {
            let v = fw - a / half, u = (b / fh + a / half) / 2
            if v >= 0, v <= 1, let top = wallTop((fw + v) * fh, [c + p.fw, r]) {
                let need = b - (top - 4)
                if need > 0 { let t = min(need / (2 * fh), max(0, u - 0.12)); a -= t * half; b -= t * fh }
            }
        }
        return [a + Double(p.tip.x), b + Double(p.tip.y)]
    }

    /// 模块剪影（模块内坐标，左上原点）：两面后墙按实际高度 + 地板 + 前沿地台（错层时再加厚 ext）
    static func silhouette(_ p: HouseWallPlanner.Placed, ext: Int = 0) -> [(x: Int, y: Int)] {
        let T = p.tip, fw = p.fw
        let W = HouseGrid.W, FH = HouseGrid.floorH, S = HouseGrid.slab + max(0, ext)
        let R = (x: T.x + fw * W / 2, y: T.y + fw * FH / 2)
        let F = (x: T.x + (fw - 1) * W / 2, y: T.y + (fw + 1) * FH / 2)
        let L = (x: T.x - W / 2, y: T.y + FH / 2)
        let nw = p.segments.first { $0.side == .nw }?.height ?? HouseGrid.wallH
        let ne = p.segments.filter { $0.side == .ne }
        // 后角：两面墙各自的高度（NW 被切矮时不能连一条斜线到 NE 墙顶——平地时那块三角藏在左后邻居的墙后面，
        // 错层时邻居矮了就会露出一块描边色的三角）
        var pts: [(x: Int, y: Int)] = [(L.x, L.y - nw), (T.x, T.y - nw)]
        if let h = ne.first?.height, h != nw { pts.append((T.x, T.y - h)) }
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
        func stone(_ base: (Double, Double, Double), _ jitter: Double) -> CGColor {
            let k = night ? (0.46, 0.42, 0.44) : (1.0, 1.0, 1.0)
            return CGColor(red: min(255, base.0 * (1 + jitter)) * k.0 / 255, green: min(255, base.1 * (1 + jitter)) * k.1 / 255,
                           blue: min(255, base.2 * (1 + jitter)) * k.2 / 255, alpha: 1)
        }
        let capTop, capEdge, endFace, pilaster, outline, slabSW, slabSE, slabLine: CGColor
        let tread, riser, jamb, doorwayEdge: CGColor
        /// 石砌基座：两种朝向的石块底色 / 灰缝 / 压顶木条下的阴影；石块按位置做 ±明暗抖动
        let stoneSW: (Double, Double, Double), stoneSE: (Double, Double, Double), mortarSW, mortarSE, plinthShadow, ground: CGColor
        let night: Bool
        init(night: Bool, wallCaps: HouseWallCapColors? = nil) {
            self.night = night
            func c(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
                let k = night ? (0.46, 0.42, 0.44) : (1.0, 1.0, 1.0)
                return CGColor(red: r * k.0 / 255, green: g * k.1 / 255, blue: b * k.2 / 255, alpha: 1)
            }
            func custom(_ rgb: UInt32?) -> CGColor? {
                rgb.map { c(Double(($0 >> 16) & 255), Double(($0 >> 8) & 255), Double($0 & 255)) }
            }
            capTop = custom(wallCaps?.top) ?? c(108, 66, 38)
            capEdge = custom(wallCaps?.side) ?? c(38, 20, 11)
            endFace = custom(wallCaps?.side) ?? c(72, 42, 24)
            pilaster = custom(wallCaps?.side) ?? c(62, 36, 20)
            tread = c(191, 132, 72)
            riser = c(120, 72, 36)
            jamb = c(53, 29, 16)
            doorwayEdge = c(25, 14, 8)
            // 错层加厚的地台：和模块自带前沿地台同色系（取自模块图地台中段），SW 面亮一点、SE 面暗一点
            slabSW = c(46, 25, 10); slabSE = c(33, 18, 7); slabLine = c(66, 38, 18)
            stoneSW = (104, 90, 76); stoneSE = (72, 62, 53)
            mortarSW = c(54, 45, 37); mortarSE = c(40, 34, 28); plinthShadow = c(28, 18, 10); ground = c(24, 16, 10)
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
    /// 房间名标签位（模块 PNG 内）：默认贴在左后墙（NW）上沿；那面墙被切矮（标签会飘到后面房间上）
    /// 或墙上挂着灯具/空调时，改贴右后墙（NE）；两面都切了放模块给的地面空地（floorLabel），没有就放地板中心。
    public static func labelPoint(_ art: HouseModuleArt, segments: [HouseWallSegment]) -> [Double] {
        let full = { (side: HouseWallSegment.Side) in !segments.contains { $0.side == side && $0.height < HouseGrid.wallH } }
        let busy = { (side: String) in art.lights.contains { $0.wall == side } }
        let t = (x: Double(art.tip.first ?? 186), y: Double(art.tip.count > 1 ? art.tip[1] : 124))
        let fw = Double(art.fw), fh = Double(art.fh)
        func P(_ u: Double, _ v: Double, _ z: Double) -> [Double] {
            [t.x + (u - v) * Double(HouseGrid.W) / 2, t.y + (u + v) * Double(HouseGrid.floorH) / 2 - z]
        }
        let ne = P(fw * 0.45, 0.02, 98)
        if full(.nw), !busy("nw") { return art.label }
        if full(.ne), !busy("ne") { return ne }
        if full(.nw) { return art.label }
        if full(.ne) { return ne }
        return art.floorLabel ?? P(fw * 0.5, fh * 0.5, 0)
    }

    static func isHidden(_ L: HouseModuleLight, wall: String, segments: [HouseWallSegment]) -> Bool {
        wallIsHidden(wall: wall, anchor: L.anchor, segments: segments)
    }

    public static func wallIsHidden(wall: String, anchor: [Double]?, segments: [HouseWallSegment]) -> Bool {
        let side: HouseWallSegment.Side = wall == "nw" ? .nw : .ne
        let segs = segments.filter { $0.side == side }
        if let a = anchor, a.count >= 2,
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

    /// 石砌基座的一面：a→b 是地面前沿（屏幕上斜线），从沿线往下 top…top+depth 像素。
    /// 一层 10px，石块 26px 宽、隔层错半块；灰缝 1px；顶上 2px 压顶阴影、底下 2px 地线。
    /// SW 面朝左前（迎光，亮），SE 面朝右前（暗）。像素风：不抗锯齿，石块明暗按位置哈希抖动。
    /// 石块纹理（未剪切的平面图块）：按 (朝向, 昼夜, seed) 缓存——lit / unlit 两遍和每次重排都复用，
    /// 合成时只做一次剪切贴图，不再逐块填几百个多边形
    final class PlinthTiles: @unchecked Sendable {
        private let lock = NSLock()
        private var tiles: [String: CGImage] = [:]
        func tile(sw: Bool, pal: Palette, seed: Int) -> CGImage? {
            let key = "\(sw ? 1 : 0)-\(pal.night ? 1 : 0)-\(seed)"
            lock.lock(); defer { lock.unlock() }
            if let t = tiles[key] { return t }
            guard let t = HouseComposer.stoneTile(sw: sw, pal: pal, seed: seed) else { return nil }
            tiles[key] = t
            return t
        }
    }
    static let plinthTiles = PlinthTiles()
    static let plinthTileW = 2 * HouseGrid.W / 2 + 26, plinthTileH = 2 * HouseGrid.levelStep + 8

    /// 平面石墙：灰缝底色上 10px 一层、26px 一块、隔层错半块，每块按 seed/层/列哈希 ±8% 明暗，上沿一条高光。
    /// 坐标从基座顶（压顶阴影上沿）算起，第一层从 3px 开始（上面 3px 是阴影）
    static func stoneTile(sw: Bool, pal: Palette, seed: Int) -> CGImage? {
        let w = plinthTileW, h = plinthTileH
        guard let c = Canvas(width: w, height: h) else { return nil }
        func rect(_ xa: Int, _ xb: Int, _ y0: Int, _ y1: Int, _ col: CGColor) {
            guard xb > xa, y1 > y0 else { return }
            c.poly([(xa, y0), (xb, y0), (xb, y1), (xa, y1)], fill: col)
        }
        rect(0, w, 0, h, sw ? pal.mortarSW : pal.mortarSE)
        let course = 10, blockW = 26
        var k = 0, cy = 3
        while cy < h {
            let ce = cy + course
            var bx = k % 2 == 0 ? 0 : -blockW / 2
            var j = 0
            while bx < w {
                let xa = max(0, bx), xb = min(w, bx + blockW)
                var hh = UInt32(truncatingIfNeeded: (seed &* 73856093) ^ (k &* 19349663) ^ (j &* 83492791))
                hh ^= hh >> 13; hh = hh &* 0x5bd1e995; hh ^= hh >> 15
                let jitter = (Double(hh % 1000) / 1000 - 0.5) * 0.16
                rect(xa + 1, xb, cy + 1, ce, pal.stone(sw ? pal.stoneSW : pal.stoneSE, jitter))
                // 石块上沿一条高光（迎光面更明显）
                rect(xa + 1, xb, cy + 1, cy + 2, pal.stone(sw ? pal.stoneSW : pal.stoneSE, jitter + (sw ? 0.14 : 0.07)))
                bx += blockW; j += 1
            }
            cy = ce; k += 1
        }
        return c.ctx.makeImage()
    }

    /// 基座一面：a→b 是这面上沿所在的地台前沿（斜线），往下 top…top+depth。平面石块纹理沿前沿斜率剪切贴上，
    /// 再画压顶阴影（3px）和地线（2px）
    static func plinth(_ c: Canvas, from a: (x: Int, y: Int), to b: (x: Int, y: Int), top: Int, depth: Int, sw: Bool, pal: Palette, seed: Int) {
        guard depth > 0, b.x != a.x else { return }
        let x0 = min(a.x, b.x), x1 = max(a.x, b.x)
        let slope = Double(b.y - a.y) / Double(b.x - a.x)
        func yEdge(_ x: Int) -> Int { a.y + Int((Double(x - a.x) * slope).rounded()) }
        func band(_ xa: Int, _ xb: Int, _ y0: Int, _ y1: Int, _ col: CGColor) {
            guard xb > xa, y1 > y0 else { return }
            c.poly([(xa, yEdge(xa) + y0), (xb, yEdge(xb) + y0), (xb, yEdge(xb) + y1), (xa, yEdge(xa) + y1)], fill: col)
        }
        let y0 = top, y1 = top + depth
        if let tile = plinthTiles.tile(sw: sw, pal: pal, seed: seed) {
            let ctx = c.ctx
            ctx.saveGState()
            let clip = CGMutablePath()
            clip.addLines(between: [c.pt(x0, yEdge(x0) + y0), c.pt(x1, yEdge(x1) + y0), c.pt(x1, yEdge(x1) + y1), c.pt(x0, yEdge(x0) + y1)])
            clip.closeSubpath()
            ctx.addPath(clip); ctx.clip()
            // 纹理像素 (tx, 自上而下 ty) → 画布 (x0+tx, yEdge(x0)+top+slope*tx+ty)；CG 坐标 y 朝上
            let th = CGFloat(tile.height)
            let yE0 = Double(yEdge(x0) + y0)
            ctx.concatenate(CGAffineTransform(a: 1, b: CGFloat(-slope), c: 0, d: 1, tx: CGFloat(x0), ty: c.h - CGFloat(yE0) - th))
            ctx.draw(tile, in: CGRect(x: 0, y: 0, width: CGFloat(tile.width), height: th))
            ctx.restoreGState()
        }
        band(x0, x1, y0, y0 + 3, pal.plinthShadow)     // 模块地台下沿的阴影
        band(x0, x1, y1 - 2, y1, pal.ground)           // 地线
    }

    static func doorwayPoint(_ doorway: HouseDoorway, along: Double, across: Double = 0, elevation: Double,
                             originX: Int, originY: Int) -> (x: Int, y: Int) {
        let u = doorway.axis == .u ? doorway.boundary + across : along
        let v = doorway.axis == .v ? doorway.boundary + across : along
        return (Int((160 * (u - v)).rounded()) - originX, Int((66 * (u + v) - elevation).rounded()) - originY)
    }

    static func doorwayOpening(_ doorway: HouseDoorway, originX: Int, originY: Int) -> CGPath {
        let elevation = Double(min(HouseLevels.elevation(doorway.front), HouseLevels.elevation(doorway.back)))
        let topElevation = Double(max(HouseLevels.elevation(doorway.front), HouseLevels.elevation(doorway.back)))
        let start = doorwayPoint(doorway, along: doorway.lower, elevation: elevation - 2, originX: originX, originY: originY)
        let end = doorwayPoint(doorway, along: doorway.upper, elevation: elevation - 2, originX: originX, originY: originY)
        let offset = doorway.axis == .u ? HouseGrid.capNW : HouseGrid.capNE
        let topStart = (x: start.x, y: start.y - HouseGrid.cutH - 4 - Int(topElevation - elevation))
        let topEnd = (x: end.x, y: end.y - HouseGrid.cutH - 4 - Int(topElevation - elevation))
        let face = path([start, end, topEnd, topStart], dx: 0, dy: 0)
        let cap = path([(topStart.x, topStart.y + 4), (topEnd.x, topEnd.y + 4), (topEnd.x + offset.x, topEnd.y + offset.y),
                        (topStart.x + offset.x, topStart.y + offset.y)], dx: 0, dy: 0)
        return face.union(cap)
    }

    static func drawDoorway(_ doorway: HouseDoorway, on canvas: Canvas, pal: Palette, originX: Int, originY: Int) {
        let frontElevation = Double(HouseLevels.elevation(doorway.front))
        let backElevation = Double(HouseLevels.elevation(doorway.back))
        func point(_ along: Double, _ across: Double, _ elevation: Double) -> (x: Int, y: Int) {
            doorwayPoint(doorway, along: along, across: across, elevation: elevation, originX: originX, originY: originY)
        }
        let sillElevation = max(frontElevation, backElevation) + 1
        canvas.poly([point(doorway.lower, -0.035, sillElevation), point(doorway.upper, -0.035, sillElevation),
                     point(doorway.upper, 0.035, sillElevation), point(doorway.lower, 0.035, sillElevation)], fill: pal.tread, stroke: pal.doorwayEdge, lineWidth: 1)
        if doorway.stairs {
            let low = min(frontElevation, backElevation), direction = frontElevation < backElevation ? 1.0 : -1.0
            for along in [doorway.lower, doorway.upper] {
                canvas.poly([point(along, direction * doorway.approachDepth, low), point(along, direction * doorway.approachDepth, low + 16),
                             point(along, 0, low + 48), point(along, 0, low)], fill: pal.riser, stroke: pal.doorwayEdge, lineWidth: 1)
            }
            for step in 0..<3 {
                let outer = direction * Double(3 - step) * doorway.approachDepth / 3
                let inner = direction * Double(2 - step) * doorway.approachDepth / 3
                let bottom = low + Double(step) * 16, top = bottom + 16
                let start = point(doorway.lower, outer, top), end = point(doorway.upper, outer, top)
                canvas.poly([point(doorway.lower, outer, bottom), point(doorway.upper, outer, bottom), end, start], fill: pal.riser, stroke: pal.doorwayEdge)
                canvas.poly([start, end, point(doorway.upper, inner, top), point(doorway.lower, inner, top)], fill: pal.tread, stroke: pal.doorwayEdge)
            }
        }
        for along in [doorway.lower, doorway.upper] {
            let bottom = point(along, 0, min(frontElevation, backElevation)), top = point(along, 0, max(frontElevation, backElevation) + Double(HouseGrid.cutH))
            canvas.poly([(bottom.x - 1, bottom.y), (top.x - 1, top.y), (top.x + 2, top.y), (bottom.x + 2, bottom.y)], fill: pal.jamb, stroke: pal.doorwayEdge, lineWidth: 1)
        }
    }

    static func render(_ items: [Item], occ: Set<[Int]>, elev: [[Int]: Int] = [:], images: [String: HouseModuleImages], decor: [HouseDecorImage] = [], doorways: [HouseDoorway] = [], lit: Bool, pal: Palette,
                       originX: Int, originY: Int, width: Int, height: Int) -> CGImage? {
        guard let c = Canvas(width: width, height: height) else { return nil }
        func add(_ p: (x: Int, y: Int), _ q: (x: Int, y: Int)) -> (x: Int, y: Int) { (p.x + q.x, p.y + q.y) }
        func clipDoorways(_ item: Item) {
            let openings = doorways.filter { $0.front == item.placed.cell }
            guard !openings.isEmpty else { return }
            var keep: CGPath = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
            for doorway in openings { keep = keep.subtracting(doorwayOpening(doorway, originX: originX, originY: originY)) }
            var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(height))
            if let clipped = keep.copy(using: &flip) { c.ctx.addPath(clipped); c.ctx.clip() }
        }

        // 外轮廓（所有剪影外扩描边）
        for it in items {
            c.ctx.saveGState(); clipDoorways(it)
            let pts = silhouette(it.placed, ext: it.ext).map { (x: $0.x + it.ox - originX, y: $0.y + it.oy - originY) }
            c.poly(pts, fill: pal.outline, stroke: pal.outline, lineWidth: 5)
            c.ctx.restoreGState()
        }
        for it in items {
            c.ctx.saveGState(); clipDoorways(it)
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
            // 邻格的墙顶换算到本格地面坐标（错层：绝对高度 = 墙高 + 那格的 elev）；邻格不存在 → 本格地面
            let e = p.elev
            func nwTop(_ c: Int, _ r: Int) -> Int {
                let h = HouseWallPlanner.nwHeight(occ, c, r)
                return h > 0 ? max(0, h + (elev[[c, r]] ?? 0) - e) : 0
            }
            func neTop(_ c: Int, _ r: Int) -> Int {
                let h = HouseWallPlanner.neHeight(occ, c, r)
                return h > 0 ? max(0, h + (elev[[c, r]] ?? 0) - e) : 0
            }
            endFace(L, from: nwTop(col, row + 1), to: hn, HouseGrid.capNW)
            endFace(R, from: neTop(col + fw, row), to: ne.last?.height ?? HouseGrid.wallH, HouseGrid.capNE)
            for (s0, s1) in zip(ne, ne.dropFirst()) where s0.height > s1.height {
                endFace(s0.b, from: s1.height, to: s0.height, HouseGrid.capNE)
            }
            // 后方邻居的墙在本格后角结束且比本墙高（墙更高或地面更高）→ 它的端面朝前露出
            // 邻格地面更高时，它的墙从它的地面才开始（下面是它的地台，由它自己画）
            func floorRel(_ c: Int, _ r: Int) -> Int { max(0, (elev[[c, r]] ?? e) - e) }
            endFace(T, from: max(hn, floorRel(col, row - 1)), to: nwTop(col, row - 1), HouseGrid.capNW)
            endFace(T, from: max(he, floorRel(col - 1, row)), to: neTop(col - 1, row), HouseGrid.capNE)
            // 错层加厚的地台（模块图自带 slab 之下）：前沿两面画成石砌基座，先画，被前面的格子盖住的部分自然看不见；
            // 后面高的格子露在前面矮格切墙上方的那一截就是台阶侧面
            if it.ext > 0 {
                let F = (x: T.x + (fw - 1) * HouseGrid.W / 2, y: T.y + (fw + 1) * HouseGrid.floorH / 2)
                plinth(c, from: o(L), to: o(F), top: HouseGrid.slab - 1, depth: it.ext + 1, sw: true, pal: pal, seed: col * 7 + row * 13)
                plinth(c, from: o(F), to: o(R), top: HouseGrid.slab - 1, depth: it.ext + 1, sw: false, pal: pal, seed: col * 7 + row * 13 + 5)
            }
            // 和邻居墙相接：壁柱盖住两张图的接缝
            if occ.contains([col - 1, row]) || occ.contains([col, row - 1]) {
                let x = T.x + ox, y = T.y + oy
                c.poly([(x - 3, y - hc), (x + 3, y - hc), (x + 3, y), (x - 3, y)], fill: pal.pilaster, stroke: pal.capEdge)
            }
            if let imgs = images[it.placed.cell.module] {
                c.image(moduleImage(it, imgs, lit: lit), x: ox, y: oy)
                let room = HouseDecor.roomKey(it.placed.cell)
                func rank(_ surface: String) -> Int { surface == "rug" ? 0 : surface == "wall" ? 1 : 2 }
                let decorations = decor.filter { $0.placement.room == room && $0.placement.module == it.placed.cell.module }.sorted {
                    let left = rank($0.placement.surface), right = rank($1.placement.surface)
                    if left != right { return left < right }
                    if $0.placement.at[1] != $1.placement.at[1] { return $0.placement.at[1] < $1.placement.at[1] }
                    return $0.placement.slot < $1.placement.slot
                }
                for decoration in decorations {
                    if let wall = decoration.placement.wall, wallIsHidden(wall: wall, anchor: decoration.placement.at, segments: it.placed.segments) { continue }
                    let image = lit ? HouseDecorPixels.brightened(decoration, module: imgs) : decoration.image
                    c.image(image, x: ox + decoration.x, y: oy + decoration.y)
                }
            }
            c.ctx.restoreGState()
            for doorway in doorways where doorway.front == it.placed.cell {
                drawDoorway(doorway, on: c, pal: pal, originX: originX, originY: originY)
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
