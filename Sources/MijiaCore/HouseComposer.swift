import Foundation
import CoreGraphics
import ImageIO

/// 把模块瓦片按格子叠成整屋 unlit / lit（画家算法）。布局 / 风格 / 时段变化时调用一次，之后渲染沿用现有蒙版逻辑。
public enum HouseComposer {
    public struct Input {
        public var layout: [HouseLayoutCell]
        public var catalog: HouseModuleCatalog
        public var images: [String: (unlit: CGImage, lit: CGImage)]  // moduleId -> day or night pair already chosen
        public var pad: Int
        public init(layout: [HouseLayoutCell], catalog: HouseModuleCatalog, images: [String: (unlit: CGImage, lit: CGImage)], pad: Int = 24) {
            self.layout = layout; self.catalog = catalog; self.images = images; self.pad = pad
        }
    }

    public static func loadCatalog(from url: URL) throws -> HouseModuleCatalog {
        try JSONDecoder().decode(HouseModuleCatalog.self, from: Data(contentsOf: url))
    }

    public static func loadCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: true] as CFDictionary)
    }

    /// 合成；返回耗时（毫秒）和场景 JSON（modules 的锚点已是画布坐标）。
    public static func compose(_ input: Input) -> HouseComposeResult {
        let t0 = CFAbsoluteTimeGetCurrent()
        var cells: [(HouseLayoutCell, HouseModuleArt)] = []
        for c in input.layout {
            guard let art = input.catalog.modules[c.module] else { continue }
            cells.append((c, art))
        }
        let bounds = canvasBounds(cells.map { ($0.0.col, $0.0.row, $0.1.fw, $0.1.fh) }, pad: input.pad)
        let width = bounds.w, height = bounds.h, ox = bounds.ox, oy = bounds.oy

        let unlit = render(cells: cells, images: input.images, pickLit: false, width: width, height: height, ox: ox, oy: oy)
        let lit = render(cells: cells, images: input.images, pickLit: true, width: width, height: height, ox: ox, oy: oy)

        var sceneMods: [String: Any] = [:]
        for (cell, art) in cells.sorted(by: { HouseGrid.painterKey(col: $0.0.col, row: $0.0.row) < HouseGrid.painterKey(col: $1.0.col, row: $1.0.row) }) {
            let tipW = HouseGrid.tip(col: cell.col, row: cell.row)
            let tipL = (art.tip[0], art.tip[1])
            func tx(_ p: [Double]) -> [Int] {
                [Int(p[0]) - tipL.0 + tipW.x - ox, Int(p[1]) - tipL.1 + tipW.y - oy]
            }
            var lights: [[String: Any]] = []
            for L in art.lights {
                var d: [String: Any] = ["id": L.id, "kind": L.kind ?? "lamp", "role": L.role ?? "light"]
                switch L.reveal {
                case .ellipse(let cx, let cy, let rx, let ry):
                    d["reveal"] = [cx - Double(tipL.0) + Double(tipW.x - ox), cy - Double(tipL.1) + Double(tipW.y - oy), rx, ry]
                case .room:
                    d["reveal"] = "room"
                case nil: break
                }
                for (k, poly) in [("shade", L.shade), ("screen", L.screen), ("core", L.core)] {
                    if let poly { d[k] = poly.map { tx($0) } }
                }
                lights.append(d)
            }
            let key = cell.room.isEmpty ? cell.module : cell.room
            sceneMods[key] = [
                "module": cell.module,
                "label": tx(art.label),
                "region": art.region.map { tx($0) },
                "badges": art.badges.map { tx($0) },
                "lights": lights,
                "col": cell.col, "row": cell.row,
            ]
        }
        let scene: [String: Any] = ["size": [width, height], "origin": [ox, oy], "modules": sceneMods]
        let data = (try? JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys])) ?? Data()
        let ms = (CFAbsoluteTimeGetCurrent() - t0) * 1000
        return HouseComposeResult(width: width, height: height, originX: ox, originY: oy, milliseconds: ms,
                                  moduleKeys: cells.map(\.0.module), unlit: unlit, lit: lit, sceneJSON: data)
    }

    private static func canvasBounds(_ cells: [(Int, Int, Int, Int)], pad: Int) -> (w: Int, h: Int, ox: Int, oy: Int) {
        var pts: [(Int, Int)] = []
        for (col, row, fw, fh) in cells {
            for dc in 0..<fw {
                for dr in 0..<fh {
                    let (tx, ty) = HouseGrid.tip(col: col + dc, row: row + dr)
                    pts.append((tx, ty - HouseGrid.wallH))
                    pts.append((tx + HouseGrid.W, ty + HouseGrid.floorH + HouseGrid.floorThick))
                    pts.append((tx - HouseGrid.W / 2, ty + HouseGrid.floorH / 2))
                    pts.append((tx + HouseGrid.W + HouseGrid.W / 2, ty + HouseGrid.floorH / 2))
                }
            }
        }
        guard !pts.isEmpty else { return (1, 1, 0, 0) }
        let minx = pts.map(\.0).min()! - pad
        let miny = pts.map(\.1).min()! - pad
        let maxx = pts.map(\.0).max()! + pad
        let maxy = pts.map(\.1).max()! + pad
        return (maxx - minx, maxy - miny, minx, miny)
    }

    private static func render(cells: [(HouseLayoutCell, HouseModuleArt)], images: [String: (unlit: CGImage, lit: CGImage)],
                               pickLit: Bool, width: Int, height: Int, ox: Int, oy: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setFillColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let ordered = cells.sorted { HouseGrid.painterKey(col: $0.0.col, row: $0.0.row) < HouseGrid.painterKey(col: $1.0.col, row: $1.0.row) }
        for (cell, art) in ordered {
            guard let pair = images[cell.module] else { continue }
            let img = pickLit ? pair.lit : pair.unlit
            let tipW = HouseGrid.tip(col: cell.col, row: cell.row)
            let tipL = (art.tip[0], art.tip[1])
            let x = tipW.x - tipL.0 - ox
            let y = tipW.y - tipL.1 - oy
            ctx.draw(img, in: CGRect(x: x, y: y, width: img.width, height: img.height))
        }
        return ctx.makeImage()
    }
}

extension HouseComposeResult {
    public func pngData(_ image: CGImage) -> Data? {
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".png")
        guard let dest = CGImageDestinationCreateWithURL(u as CFURL, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return try? Data(contentsOf: u)
    }
}
