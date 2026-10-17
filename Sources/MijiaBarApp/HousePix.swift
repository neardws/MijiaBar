import AppKit
import SceneKit

// MARK: - 像素图（字符画 → 最近邻纹理，供 SceneKit 材质使用）

enum HousePix {
    static let palette: [Character: UInt32] = [
        "k": 0x1a1420, "d": 0x3a2a24, "w": 0x6b4a32, "W": 0x8e6644, "l": 0xb88a5c,
        "g": 0x5c6470, "G": 0x8a94a0, "s": 0xc9d0d8, "S": 0xeef1f4,
        "y": 0xffd27a, "Y": 0xfff1c4, "o": 0xe39a4a,
        "b": 0x2b3a5c, "B": 0x4a6aa8, "c": 0x7fc4ff,
        "r": 0x8a3b3b, "R": 0xb85a50, "p": 0x6a5a8a, "P": 0x9a88c0,
        "n": 0x2f5a3a, "N": 0x4f8a52, "m": 0x7cba6a,
        "t": 0xd8c8a8, "T": 0xf0e6d0,
    ]

    static let floorLamp = [
        "  yyyyy  ", " yYYYYYy ", "yYYYYYYYy", "oyyyyyyyo", "   kgk   ", "    g    ", "    g    ", "    g    ", "    g    ",
        "    g    ", "    g    ", "    g    ", "    g    ", "    g    ", "    g    ", "    g    ", "   ggg   ", "  gGGGg  ", "  kkkkk  ",
    ]
    static let floorLampOff = floorLamp.map { String($0.map { "yYo".contains($0) ? "G" : $0 }) }
    static let ac = [
        "kkkkkkkkkkkkkkkkkkkkkk", "kSSSSSSSSSSSSSSSSSSSSk", "kSSSSSSSSSSSSSSSSScSSk", "kSSSSSSSSSSSSSSSSSSSSk",
        "ksssssssssssssssssssssk", "kGGGGGGGGGGGGGGGGGGGGk", "kgggggggggggggggggggk", " kkkkkkkkkkkkkkkkkkkk ",
    ]
    static let tv = [
        "kkkkkkkkkkkkkkkkkkkk", "kgggggggggggggggggk", "kgbbbbbbbbbbbbbbbbgk", "kgbbbbbbbbbbbbbbbbgk", "kgbbbbbbbbbbbbbbbbgk",
        "kgbbbbbbbbbbbbbbbbgk", "kgbbbbbbbbbbbbbbbbgk", "kgbbbbbbbbbbbbbbbbgk", "kgbbbbbbbbbbbbbbbbgk", "kgggggggggggggggggk",
        "kkkkkkkkkkkkkkkkkkkk", "        kgk         ", "      kkkkkkk       ",
    ]
    static let tvStand = [
        "kkkkkkkkkkkkkkkkkkkkkkkk", "kWWWWWWWWWWWWWWWWWWWWWWk", "kwwwwwwwwwkkwwwwwwwwwwwk", "kwddddddwwkkwwddddddddwk",
        "kwddddddwwkkwwddddddddwk", "kwwwwwwwwwkkwwwwwwwwwwwk", "kkkkkkkkkkkkkkkkkkkkkkkk", " kk                  kk ",
    ]
    static let sofa = [
        "  kkkkkkkkkkkkkkkkkkkk  ", " kRRRRRRRRRRRRRRRRRRRRk ", " kRRRRRRRRRRRRRRRRRRRRk ", "kkRrrrrrrrrrRrrrrrrrrRkk",
        "kRkRRRRRRRRRkRRRRRRRRkRk", "kRkRRRRRRRRRkRRRRRRRRkRk", "kRkrrrrrrrrrkrrrrrrrrkRk", "kRRRRRRRRRRRRRRRRRRRRRRk",
        "krrrrrrrrrrrrrrrrrrrrrrk", "kkkkkkkkkkkkkkkkkkkkkkkk", " kk                  kk ",
    ]
    static let plant = ["  m N m  ", " mNmNmNm ", "mNnNmNnNm", " NnmNmnN ", "  nNnNn  ", "   nNn   ", "  kkkkk  ", "  kRRRk  ", "  krrrk  ", "   kkk   "]

    private static var cache: [String: NSImage] = [:]

    static func image(_ name: String, rows: [String]) -> NSImage {
        if let img = cache[name] { return img }
        let h = rows.count, w = rows.map(\.count).max() ?? 1
        var px = [UInt32](repeating: 0, count: w * h)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = palette[ch] else { continue }
                let r = UInt8(c & 0xff), g = UInt8((c >> 8) & 0xff), b = UInt8((c >> 16) & 0xff)
                px[y * w + x] = 0xff00_0000 | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
            }
        }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h))
        cache[name] = img; return img
    }

    static func mat(_ name: String, rows: [String], scale: CGFloat = 1, emissive: CGFloat = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = image(name, rows: rows)
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.diffuse.wrapS = .clamp
        m.diffuse.wrapT = .clamp
        m.lightingModel = .physicallyBased
        m.roughness.contents = 0.85
        m.metalness.contents = 0.05
        if emissive > 0 {
            m.emission.contents = image(name, rows: rows)
            m.emission.intensity = emissive
        }
        return m
    }

    /// 木地板格子（可平铺）
    static func woodFloorTile() -> NSImage {
        let key = "wood-floor"
        if let img = cache[key] { return img }
        let w = 32, h = 32
        var px = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let stripe = (x / 4 + y / 8) % 2 == 0
                let base: UInt32 = stripe ? 0x6b4a32 : 0x5a3d28
                let grain = UInt32((x * 3 + y * 7) % 5)
                let r = UInt8(min(255, (base & 0xff) + grain))
                let g = UInt8(min(255, ((base >> 8) & 0xff) + grain / 2))
                let b = UInt8(min(255, ((base >> 16) & 0xff) + grain / 3))
                px[y * w + x] = 0xff00_0000 | (UInt32(r) << 16) | (UInt32(g) << 8) | UInt32(b)
            }
        }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h))
        cache[key] = img; return img
    }

    static func plasterWall() -> NSImage {
        let key = "plaster"
        if let img = cache[key] { return img }
        let w = 64, h = 64
        var px = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w {
                let n = (x * 13 + y * 17) % 9
                let v = 200 + n
                px[y * w + x] = 0xff00_0000 | UInt32(v) << 16 | UInt32(v - 8) << 8 | UInt32(v - 18)
            }
        }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let img = NSImage(cgImage: ctx.makeImage()!, size: NSSize(width: w, height: h))
        cache[key] = img; return img
    }

    static func tiledMat(_ img: NSImage) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = img
        m.diffuse.magnificationFilter = .nearest
        m.diffuse.minificationFilter = .nearest
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        m.lightingModel = .physicallyBased
        m.roughness.contents = 0.9
        return m
    }

    static func spritePlane(_ name: String, rows: [String], width: CGFloat, emissive: CGFloat = 0) -> SCNNode {
        let h = CGFloat(rows.count) / CGFloat(rows.map(\.count).max() ?? 1) * width
        let plane = SCNPlane(width: width, height: h)
        plane.materials = [mat(name, rows: rows, emissive: emissive)]
        let n = SCNNode(geometry: plane)
        n.castsShadow = true
        return n
    }
}
