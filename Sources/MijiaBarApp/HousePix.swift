import AppKit
import Metal

/// 小屋 HD-2D：程序生成的像素纹理（最近邻采样）
enum HousePix {
    static let palette: [Character: UInt32] = [
        "k": 0x1a1420, "d": 0x3a2a24, "w": 0x6b4a32, "W": 0x8e6644, "l": 0xb88a5c,
        "g": 0x5c6470, "G": 0x8a94a0, "s": 0xc9d0d8, "S": 0xeef1f4,
        "y": 0xffd27a, "Y": 0xfff1c4, "o": 0xe39a4a,
        "b": 0x2b3a5c, "B": 0x4a6aa8, "c": 0x7fc4ff,
        "r": 0x8a3b3b, "R": 0xb85a50, "p": 0x6a5a8a, "P": 0x9a88c0,
        "n": 0x2f5a3a, "N": 0x4f8a52, "m": 0x7cba6a,
        "t": 0xd8c8a8, "T": 0xf0e6d0,
        "h": 0x9a9088, "H": 0xb8b0a4, "a": 0x706860, "A": 0x585048,
        "u": 0x3d3530, "U": 0x2a2420, "i": 0x1e1a18,
    ]

    static func rgba(_ c: UInt32) -> UInt8 { UInt8(c & 0xff) }
    static func rgb(_ c: UInt32) -> (UInt8, UInt8, UInt8) { (rgba(c), UInt8((c >> 8) & 0xff), UInt8((c >> 16) & 0xff)) }

    static func image(rows: [String], scale: Int = 1) -> CGImage? {
        var w = rows.map(\.count).max() ?? 1
        let h = rows.count
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = palette[ch] else { continue }
                let (r, g, b) = rgb(c)
                let i = (y * w + x) * 4
                px[i] = r; px[i + 1] = g; px[i + 2] = b; px[i + 3] = 255
            }
        }
        var outW = w, outH = h
        if scale > 1 {
            var big = [UInt8](repeating: 0, count: w * scale * h * scale * 4)
            let bw = w * scale, bh = h * scale
            for y in 0..<bh {
                for x in 0..<bw {
                    let si = ((y / scale) * w + x / scale) * 4
                    let j = (y * bw + x) * 4
                    big[j] = px[si]; big[j + 1] = px[si + 1]; big[j + 2] = px[si + 2]; big[j + 3] = px[si + 3]
                }
            }
            px = big; outW = bw; outH = bh
        }
        let ctx = CGContext(data: &px, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: outW * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()
    }

    static func texture(_ device: MTLDevice, rows: [String], scale: Int = 1, label: String) -> MTLTexture? {
        guard let img = image(rows: rows, scale: scale) else { return nil }
        return texture(device, cg: img, label: label)
    }

    static func texture(_ device: MTLDevice, cg: CGImage, label: String) -> MTLTexture? {
        let w = cg.width, h = cg.height
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        td.usage = [.shaderRead]
        guard let tex = device.makeTexture(descriptor: td) else { return nil }
        tex.label = label
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: data, bytesPerRow: w * 4)
        return tex
    }

    /// 木地板条（可平铺）
    static func woodPlankTile() -> [String] {
        var rows = [String]()
        for y in 0..<16 {
            let dark = y % 4 == 0
            var row = ""
            for x in 0..<16 {
                let seam = x == 0 || x == 8
                let grain = (x * 3 + y * 7) % 5 == 0
                if seam { row += "d" }
                else if grain { row += dark ? "w" : "W" }
                else { row += dark ? "l" : "w" }
            }
            rows.append(row)
        }
        return rows
    }

    static func plasterTile() -> [String] {
        (0..<16).map { y in
            (0..<16).map { x in
                let n = (x * 13 + y * 17) % 11
                if n == 0 { return "a" }
                if n == 1 { return "h" }
                return "H"
            }.joined()
        }
    }

    static func rugTile() -> [String] {
        (0..<16).map { y in
            (0..<16).map { x in
                let edge = x == 0 || y == 0 || x == 15 || y == 15
                let pat = (x / 2 + y / 2) % 2 == 0
                if edge { return "r" }
                return pat ? "R" : "p"
            }.joined()
        }
    }

    static func nightSky() -> [String] {
        (0..<12).map { y in
            (0..<20).map { x in
                let star = (x * 7 + y * 11) % 23 == 0
                return star ? "c" : "b"
            }.joined()
        }
    }

    static func tvScreenOn() -> [String] {
        (0..<8).map { y in
            (0..<14).map { x in
                let band = y < 3 ? "c" : y < 6 ? "B" : "b"
                let hill = x > 4 && x < 10 && y > 4 ? "m" : band
                return hill
            }.joined()
        }
    }

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
    static let coffeeTable = [
        "kkkkkkkkkkkkkk", "kWWWWWWWWWWWWk", "kwwwwwwwwwwwwk", "kwwwwwwwwwwwwk", "kWWWWWWWWWWWWk",
        "k    k    k   k", "k    k    k   k", "kkkkkkkkkkkkkk",
    ]
}
