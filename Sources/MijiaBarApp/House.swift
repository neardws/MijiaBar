import SwiftUI
import AppKit
import SpriteKit
import CoreImage
import MijiaCore

// MARK: - 「小屋」原型：HD-2D 风格的等距像素小屋（SpriteKit）
// 房间模块固定、按房间名自动匹配；设备按类型放进固定位置。像素图全部由代码生成（无外部素材）。

struct HouseDevice: Equatable {
    let did: String, name: String, kind: HouseSlotKind, slot: Int, on: Bool, online: Bool
}
struct HouseRoom: Equatable {
    let title: String, module: HouseModule, devices: [HouseDevice], overflow: Int
}

extension AppModel {
    /// 当前家庭里能画进小屋的房间（按保存的房间顺序；收藏不影响归属）
    var houseRooms: [HouseRoom] {
        let hid = currentHomeId ?? ""
        let inHome = devices.filter { currentHomeId == nil || $0.homeId == currentHomeId }
        let groups = Dictionary(grouping: inHome) { $0.roomName ?? "" }
        return prefs.orderedRooms(home: hid, roomKeys(groups.keys)).compactMap { k in
            let mod = HouseModule.from(roomName: k)
            guard mod != .generic else { return nil }
            let r = HouseLayout.assign(prefs.orderedDevices(home: hid, key: k, groups[k]!), in: mod)
            let ds = r.placed.map { d, s in
                HouseDevice(did: d.did, name: displayName(d), kind: s.kind, slot: s.index, on: d.isOnline && (powerInfo(d)?.isOn ?? false), online: d.isOnline)
            }
            return HouseRoom(title: k, module: mod, devices: ds, overflow: r.overflow.count)
        }
    }
}

// MARK: 像素图（字符画 → 最近邻放大的纹理）

@MainActor
enum Pix {
    static let palette: [Character: UInt32] = [
        "k": 0x1a1420, "d": 0x3a2a24, "w": 0x6b4a32, "W": 0x8e6644, "l": 0xb88a5c,     // 木色
        "g": 0x5c6470, "G": 0x8a94a0, "s": 0xc9d0d8, "S": 0xeef1f4,                   // 金属 / 塑料
        "y": 0xffd27a, "Y": 0xfff1c4, "o": 0xe39a4a,                                   // 灯光
        "b": 0x2b3a5c, "B": 0x4a6aa8, "c": 0x7fc4ff,                                   // 屏幕 / 冷色
        "r": 0x8a3b3b, "R": 0xb85a50, "p": 0x6a5a8a, "P": 0x9a88c0,                   // 布艺
        "n": 0x2f5a3a, "N": 0x4f8a52, "m": 0x7cba6a,                                   // 植物
        "t": 0xd8c8a8, "T": 0xf0e6d0,                                                   // 床品
    ]
    static var cache: [String: SKTexture] = [:]
    static func tex(_ name: String, _ rows: [String]) -> SKTexture {
        if let t = cache[name] { return t }
        let h = rows.count, w = rows.map(\.count).max() ?? 1
        var px = [UInt32](repeating: 0, count: w * h)
        for (y, row) in rows.enumerated() {
            for (x, ch) in row.enumerated() {
                guard let c = palette[ch] else { continue }
                // RGBA 小端：A B G R
                px[y * w + x] = 0xff00_0000 | ((c & 0xff) << 16) | (c & 0xff00) | ((c >> 16) & 0xff)
            }
        }
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let t = SKTexture(cgImage: ctx.makeImage()!); t.filteringMode = .nearest
        cache[name] = t; return t
    }
    static func sprite(_ name: String, _ rows: [String], scale: CGFloat = 3) -> SKSpriteNode {
        let n = SKSpriteNode(texture: tex(name, rows)); n.setScale(scale); n.anchorPoint = CGPoint(x: 0.5, y: 0); return n
    }
    /// 柔和的径向光斑（加色混合用）
    static func glow(_ color: NSColor, size: CGFloat = 128) -> SKTexture {
        let key = "glow-\(color.description)-\(size)"
        if let t = cache[key] { return t }
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let g = NSGradient(colors: [color.withAlphaComponent(0.9), color.withAlphaComponent(0.25), color.withAlphaComponent(0)], atLocations: [0, 0.35, 1], colorSpace: .deviceRGB)!
            g.draw(in: NSBezierPath(ovalIn: r), relativeCenterPosition: .zero); return true
        }
        let t = SKTexture(image: img); cache[key] = t; return t
    }
    static func symbol(_ name: String, _ color: NSColor) -> SKTexture {
        let key = "sym-\(name)-\(color.description)"
        if let t = cache[key] { return t }
        let cfg = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold).applying(.init(paletteColors: [color]))
        let t = SKTexture(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) ?? NSImage())
        cache[key] = t; return t
    }

    static let floorLamp = [
        "  yyyyy  ", " yYYYYYy ", "yYYYYYYYy", "oyyyyyyyo", "   kgk   ", "    g    ", "    g    ", "    g    ", "    g    ",
        "    g    ", "    g    ", "    g    ", "    g    ", "    g    ", "    g    ", "    g    ", "   ggg   ", "  gGGGg  ", "  kkkkk  ",
    ]
    static let floorLampOff = floorLamp.map { String($0.map { "yYo".contains($0) ? "G" : $0 }).replacingOccurrences(of: "G", with: "s") }
    static let deskLamp = [" yyyy  ", "yYYYYy ", "oyyyyo ", "  kg   ", "   g   ", "    g  ", "   g   ", "  ggg  ", " kkkkk "]
    static let deskLampOff = deskLamp.map { String($0.map { "yYo".contains($0) ? "s" : $0 }) }
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
    static let bed = [
        "kkkkkkkkkkkkkkkkkkkkkkkkkk", "kWWWWWWWWWWWWWWWWWWWWWWWWk", "kWkkkkkkkkkkkkkkkkkkkkkkWk", "kWkTTTTTTkkTTTTTTkPPPPPkWk",
        "kWkTTTTTTkkTTTTTTkPPPPPkWk", "kWkttttttkkttttttkPPPPPkWk", "kwkPPPPPPPPPPPPPPPPPPPPkwk", "kwkPPPPPPPPPPPPPPPPPPPPkwk",
        "kwkppppppppppppppppppppkwk", "kwkpppppppppppppppppppppwk", "kwkkkkkkkkkkkkkkkkkkkkkkwk", "kwwwwwwwwwwwwwwwwwwwwwwwwk",
        "kkkkkkkkkkkkkkkkkkkkkkkkkk", " kk                    kk ",
    ]
    static let desk = [
        "kkkkkkkkkkkkkkkkkkkkkkkk", "klllllllllllllllllllllllk", "kWWWWWWWWWWWWWWWWWWWWWWk", "kkkkkkkkkkkkkkkkkkkkkkkk",
        " kw kkkkkk        kw    ", " kw kWWWWk        kw    ", " kw kwwwwk        kw    ", " kw kkkkkk        kw    ",
        " kw               kw    ", " kk               kk    ",
    ]
    static let shelf = [
        "kkkkkkkkkkkkkk", "kWWWWWWWWWWWWk", "kwRRbBpPRrnNwk", "kwRRbBpPRrnNwk", "kwRRbBpPRrnNwk", "kWWWWWWWWWWWWk",
        "kwbBBrRtTpPPwk", "kwbBBrRtTpPPwk", "kwbBBrRtTpPPwk", "kWWWWWWWWWWWWk", "kwPpNnRrbBtwwk", "kwPpNnRrbBtwwk",
        "kwPpNnRrbBtwwk", "kWWWWWWWWWWWWk", "kkkkkkkkkkkkkk",
    ]
    static let plant = ["  m N m  ", " mNmNmNm ", "mNnNmNnNm", " NnmNmnN ", "  nNnNn  ", "   nNn   ", "  kkkkk  ", "  kRRRk  ", "  krrrk  ", "   kkk   "]
    static let nightstand = ["kkkkkkkk", "kWWWWWWk", "kwkkkkwk", "kwkllkwk", "kwkkkkwk", "kwwwwwwk", "kkkkkkkk"]
}

// MARK: 场景

final class HouseScene: SKScene {
    var rooms: [HouseRoom] = []
    var tiltShift = true { didSet { applyFilter() } }
    var onToggle: (String) -> Void = { _ in }
    var onOpen: (String) -> Void = { _ in }

    private let world = SKNode()
    private let labels = SKNode()
    private let bg = SKEffectNode()
    static let tileW: CGFloat = 64, tileH: CGFloat = 32, roomN = 6, wallH: CGFloat = 120

    override init(size: CGSize) {
        super.init(size: size)
        anchorPoint = CGPoint(x: 0.5, y: 0.5); scaleMode = .resizeFill
        backgroundColor = NSColor(red: 0.05, green: 0.06, blue: 0.11, alpha: 1)
        addChild(bg); addChild(world)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 网格坐标 → 屏幕坐标（等距投影）
    func iso(_ gx: CGFloat, _ gy: CGFloat, _ z: CGFloat = 0) -> CGPoint {
        CGPoint(x: (gx - gy) * Self.tileW / 2, y: -(gx + gy) * Self.tileH / 2 + z)
    }

    func update(rooms: [HouseRoom]) {
        guard rooms != self.rooms || world.children.isEmpty else { return }
        self.rooms = rooms; rebuild()
    }

    override func didChangeSize(_ oldSize: CGSize) { super.didChangeSize(oldSize); layoutWorld(); buildBackground(); applyFilter() }

    private func rebuild() {
        world.removeAllChildren(); labels.removeAllChildren(); labels.zPosition = 50_000; world.addChild(labels)
        if rooms.isEmpty {
            let l = SKLabelNode(text: L("这个家里还没有能放进小屋的房间（客厅、卧室、书房）", "No living room, bedroom or study in this home yet"))
            l.fontName = NSFont.systemFont(ofSize: 15, weight: .medium).fontName; l.fontSize = 15; l.fontColor = .secondaryLabelColor
            world.addChild(l)
        }
        for (i, r) in rooms.enumerated() { buildRoom(r, cell: HouseLayout.cell(i), count: rooms.count) }
        layoutWorld()
    }

    private func layoutWorld() {
        guard size.width > 0 else { return }
        world.setScale(1); world.position = .zero
        let f = world.calculateAccumulatedFrame()
        guard f.width > 0, f.height > 0 else { return }
        let s = min(size.width * 0.9 / f.width, size.height * 0.86 / f.height, 1.6)
        world.setScale(s)
        world.position = CGPoint(x: -f.midX * s, y: -f.midY * s - size.height * 0.02)
    }

    // 夜景背景：模糊的暖色 / 冷色光斑
    private func buildBackground() {
        bg.removeAllChildren()
        var rng = SeededRandom(seed: 7)
        let cols: [NSColor] = [NSColor(red: 1, green: 0.75, blue: 0.4, alpha: 1), NSColor(red: 0.45, green: 0.6, blue: 1, alpha: 1), NSColor(red: 0.9, green: 0.55, blue: 0.75, alpha: 1)]
        for _ in 0..<26 {
            let n = SKSpriteNode(texture: Pix.glow(cols[Int(rng.next() * 3) % 3], size: 96))
            let d = CGFloat(40 + rng.next() * 150)
            n.size = CGSize(width: d, height: d); n.alpha = CGFloat(0.06 + rng.next() * 0.16); n.blendMode = .add
            n.position = CGPoint(x: (rng.next() - 0.5) * size.width, y: (rng.next() - 0.5) * size.height)
            n.run(.repeatForever(.sequence([.fadeAlpha(by: 0.05, duration: 2 + rng.next() * 2), .fadeAlpha(by: -0.05, duration: 2 + rng.next() * 2)])))
            bg.addChild(n)
        }
        // 上下压暗（暗角）
        for top in [true, false] {
            let img = NSImage(size: NSSize(width: 4, height: 64), flipped: false) { r in
                NSGradient(starting: NSColor.black.withAlphaComponent(top ? 0 : 0.55), ending: NSColor.black.withAlphaComponent(top ? 0.55 : 0))!.draw(in: r, angle: 90); return true
            }
            let v = SKSpriteNode(texture: SKTexture(image: img), size: CGSize(width: size.width, height: size.height * 0.28))
            v.position = CGPoint(x: 0, y: (top ? 1 : -1) * size.height * 0.36); v.zPosition = 9_000
            bg.addChild(v)
        }
    }

    /// 景深：背景光斑整体再模糊一层（整场景的 CIMaskedVariableBlur 在 Retina / 离屏渲染下遮罩坐标对不上，原型先不用）
    private func applyFilter() {
        bg.filter = tiltShift ? CIFilter(name: "CIGaussianBlur", parameters: ["inputRadius": 10]) : nil
        bg.shouldEnableEffects = tiltShift; bg.shouldRasterize = false
    }

    // MARK: 房间

    private func buildRoom(_ r: HouseRoom, cell: (col: Int, row: Int), count: Int) {
        let N = CGFloat(Self.roomN)
        let ox = CGFloat(cell.col) * N, oy = CGFloat(cell.row) * N
        let room = SKNode(); room.zPosition = CGFloat(cell.col + cell.row) * 1000
        world.addChild(room)
        func P(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat = 0) -> CGPoint { iso(ox + x, oy + y, z) }
        let lit = r.devices.contains { $0.kind == .light && $0.on }
        let dim: CGFloat = lit ? 1 : 0.55

        // 地板：木地板格子
        for x in 0..<Self.roomN { for y in 0..<Self.roomN {
            let path = CGMutablePath()
            path.addLines(between: [P(CGFloat(x), CGFloat(y)), P(CGFloat(x + 1), CGFloat(y)), P(CGFloat(x + 1), CGFloat(y + 1)), P(CGFloat(x), CGFloat(y + 1))]); path.closeSubpath()
            let t = SKShapeNode(path: path)
            let base: (CGFloat, CGFloat, CGFloat) = (x + y) % 2 == 0 ? (0.47, 0.33, 0.22) : (0.42, 0.29, 0.19)
            t.fillColor = NSColor(red: base.0 * dim, green: base.1 * dim, blue: base.2 * dim, alpha: 1)
            t.strokeColor = NSColor(white: 0, alpha: 0.18); t.lineWidth = 1; t.isAntialiased = false
            room.addChild(t)
        }}
        // 地毯
        let rugC: NSColor = r.module == .bedroom ? NSColor(red: 0.42, green: 0.36, blue: 0.55, alpha: 1) : r.module == .study ? NSColor(red: 0.25, green: 0.38, blue: 0.32, alpha: 1) : NSColor(red: 0.55, green: 0.28, blue: 0.26, alpha: 1)
        let rug = CGMutablePath(); rug.addLines(between: [P(1.6, 2), P(4.4, 2), P(4.4, 4.6), P(1.6, 4.6)]); rug.closeSubpath()
        let rn = SKShapeNode(path: rug); rn.fillColor = rugC.blended(withFraction: 1 - dim, of: .black)!; rn.strokeColor = NSColor(white: 1, alpha: 0.12); rn.lineWidth = 2; rn.zPosition = 1
        room.addChild(rn)

        // 墙：最外圈是整面墙，内部隔断矮一些
        let wallC = NSColor(red: 0.78, green: 0.72, blue: 0.62, alpha: 1)
        func wall(_ a: CGPoint, _ b: CGPoint, _ h: CGFloat, shade: CGFloat) {
            let p = CGMutablePath(); p.addLines(between: [a, b, CGPoint(x: b.x, y: b.y + h), CGPoint(x: a.x, y: a.y + h)]); p.closeSubpath()
            let w = SKShapeNode(path: p); w.fillColor = wallC.blended(withFraction: shade + (1 - dim) * 0.6, of: .black)!
            w.strokeColor = NSColor(white: 0, alpha: 0.35); w.lineWidth = 1; w.zPosition = 0.5
            room.addChild(w)
            let cap = CGMutablePath(); cap.move(to: CGPoint(x: a.x, y: a.y + h)); cap.addLine(to: CGPoint(x: b.x, y: b.y + h))
            let c = SKShapeNode(path: cap); c.strokeColor = NSColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 0.9); c.lineWidth = 3; c.zPosition = 0.6
            room.addChild(c)
            // 踢脚线
            let sk = CGMutablePath(); sk.addLines(between: [a, b, CGPoint(x: b.x, y: b.y + 6), CGPoint(x: a.x, y: a.y + 6)]); sk.closeSubpath()
            let s = SKShapeNode(path: sk); s.fillColor = NSColor(red: 0.3, green: 0.2, blue: 0.14, alpha: 1); s.strokeColor = .clear; s.zPosition = 0.55
            room.addChild(s)
        }
        wall(P(0, 0), P(N, 0), cell.row == 0 ? Self.wallH : 22, shade: 0.12)
        wall(P(0, 0), P(0, N), cell.col == 0 ? Self.wallH : 22, shade: 0.3)
        // 窗（外墙上）
        if cell.row == 0 {
            let a = P(3.6, 0, 52), b = P(5.2, 0, 52)
            let p = CGMutablePath(); p.addLines(between: [a, b, CGPoint(x: b.x, y: b.y + 40), CGPoint(x: a.x, y: a.y + 40)]); p.closeSubpath()
            let w = SKShapeNode(path: p); w.fillColor = NSColor(red: 0.12, green: 0.18, blue: 0.35, alpha: 1); w.strokeColor = NSColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1); w.lineWidth = 3; w.zPosition = 0.7
            room.addChild(w)
            let moon = SKSpriteNode(texture: Pix.glow(NSColor(red: 0.8, green: 0.88, blue: 1, alpha: 1), size: 32)); moon.size = CGSize(width: 18, height: 18)
            moon.position = CGPoint(x: (a.x + b.x) / 2 + 8, y: (a.y + b.y) / 2 + 28); moon.zPosition = 0.8; moon.blendMode = .add
            room.addChild(moon)
        }
        // 前沿：地板边缘的厚度
        for (a, b) in [(P(0, N), P(N, N)), (P(N, 0), P(N, N))] {
            let p = CGMutablePath(); p.addLines(between: [a, b, CGPoint(x: b.x, y: b.y - 14), CGPoint(x: a.x, y: a.y - 14)]); p.closeSubpath()
            let e = SKShapeNode(path: p); e.fillColor = NSColor(red: 0.22, green: 0.16, blue: 0.13, alpha: 1); e.strokeColor = NSColor(white: 0, alpha: 0.4); e.zPosition = 0.4
            room.addChild(e)
        }

        func place(_ n: SKNode, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat = 0) {
            n.position = P(x, y, z); n.zPosition = 10 + (x + y) * 10; room.addChild(n)
        }
        func furniture(_ name: String, _ art: [String], _ x: CGFloat, _ y: CGFloat, z: CGFloat = 0, scale: CGFloat = 3) {
            let s = Pix.sprite(name, art, scale: scale); s.color = .black; s.colorBlendFactor = 1 - dim; place(s, x, y, z)
        }
        // 家具（固定）
        switch r.module {
        case .living: furniture("sofa", Pix.sofa, 3.2, 4.6); furniture("plant", Pix.plant, 5.3, 0.7)
        case .bedroom: furniture("bed", Pix.bed, 3.2, 3.4); furniture("nightstand", Pix.nightstand, 5.2, 1.3)
        case .study: furniture("desk", Pix.desk, 2.8, 1.4); furniture("shelf", Pix.shelf, 0.7, 4.4); furniture("plant", Pix.plant, 5.2, 5.1)
        case .generic: break
        }

        // 房间名牌
        let tag = SKLabelNode(text: r.title + (r.overflow > 0 ? L(" · 另有 \(r.overflow) 台", " · +\(r.overflow) more") : ""))
        tag.fontName = NSFont.systemFont(ofSize: 13, weight: .semibold).fontName; tag.fontSize = 13; tag.verticalAlignmentMode = .center
        tag.fontColor = NSColor(white: 1, alpha: 0.8)
        let tw = tag.frame.width + 20
        let chip = SKShapeNode(rect: CGRect(x: -tw / 2, y: -11, width: tw, height: 22), cornerRadius: 6)
        chip.fillColor = NSColor(white: 0, alpha: 0.45); chip.strokeColor = .clear; chip.position = P(N - 0.7, N - 0.7); chip.addChild(tag)
        labels.addChild(chip)

        // 设备
        for d in r.devices {
            let (x, y, z) = slotPosition(r.module, d, cell: cell)
            let node = deviceNode(d, module: r.module)
            node.name = "dev:\(d.did)"
            place(node, x, y, z)
            let label = labelNode(d)
            label.position = CGPoint(x: node.position.x, y: node.position.y + labelLift(d))
            label.zPosition = room.zPosition + node.zPosition
            labels.addChild(label)
            if d.kind == .light && d.on {
                // 地面的暖色光池
                let pool = SKSpriteNode(texture: Pix.glow(NSColor(red: 1, green: 0.7, blue: 0.35, alpha: 1), size: 128))
                pool.size = CGSize(width: 300, height: 170); pool.position = P(x, y); pool.blendMode = .add; pool.alpha = 0.55; pool.zPosition = 2
                room.addChild(pool)
            }
        }
    }

    private func slotPosition(_ m: HouseModule, _ d: HouseDevice, cell: (col: Int, row: Int)) -> (CGFloat, CGFloat, CGFloat) {
        switch d.kind {
        // 空调挂在整面外墙上；没有外墙的房间挂在矮隔断上方的位置会悬空，所以放低
        case .ac: return cell.row == 0 ? (2.2, 0.1, 82) : cell.col == 0 ? (0.1, 1.6, 82) : (2.2, 0.1, 30)
        case .tv: return (0.6, 2.6, 0)
        case .light:
            switch (m, d.slot) {
            case (.living, 0): return (5.2, 4.2, 0)
            case (.bedroom, 0): return (5.2, 1.3, 21)
            case (.study, 0): return (3.4, 1.2, 30)
            case (.study, _): return (4.6, 4.6, 0)
            default: return (0.9, 0.9, 0)
            }
        }
    }
    private func labelLift(_ d: HouseDevice) -> CGFloat { d.kind == .ac ? 46 : d.kind == .tv ? 104 : 86 }

    private func deviceNode(_ d: HouseDevice, module: HouseModule) -> SKNode {
        let n = SKNode()
        switch d.kind {
        case .light:
            let desk = module != .living && !(module == .study && d.slot == 1) && !(module == .bedroom && d.slot == 1)
            let s = desk ? Pix.sprite(d.on ? "desklamp-on" : "desklamp", d.on ? Pix.deskLamp : Pix.deskLampOff)
                         : Pix.sprite(d.on ? "lamp-on" : "lamp", d.on ? Pix.floorLamp : Pix.floorLampOff)
            n.addChild(s)
            if d.on {
                let g = SKSpriteNode(texture: Pix.glow(NSColor(red: 1, green: 0.78, blue: 0.4, alpha: 1)))
                g.size = CGSize(width: 150, height: 150); g.blendMode = .add; g.position = CGPoint(x: 0, y: s.size.height - 8)
                g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.8, duration: 1.6), .fadeAlpha(to: 1, duration: 1.6)])))
                n.addChild(g)
            }
        case .ac:
            let s = Pix.sprite("ac", Pix.ac); n.addChild(s)
            if d.on {
                let led = SKSpriteNode(color: NSColor(red: 0.5, green: 0.85, blue: 1, alpha: 1), size: CGSize(width: 6, height: 3)); led.position = CGPoint(x: 18, y: 16)
                n.addChild(led)
                let e = SKEmitterNode()
                e.particleTexture = Pix.glow(NSColor(red: 0.55, green: 0.8, blue: 1, alpha: 1), size: 16)
                e.particleBirthRate = 26; e.particleLifetime = 1.8; e.particleLifetimeRange = 0.6
                e.particlePositionRange = CGVector(dx: 54, dy: 4); e.position = CGPoint(x: 0, y: 2)
                e.emissionAngle = -.pi / 2; e.emissionAngleRange = 0.5; e.particleSpeed = 34; e.particleSpeedRange = 14
                e.particleAlpha = 0.85; e.particleAlphaSpeed = -0.45; e.particleScale = 0.5; e.particleScaleRange = 0.3; e.particleScaleSpeed = 0.2
                e.particleColor = NSColor(red: 0.6, green: 0.85, blue: 1, alpha: 1); e.particleColorBlendFactor = 1; e.particleBlendMode = .add
                e.advanceSimulationTime(2)
                n.addChild(e)
            }
        case .tv:
            let stand = Pix.sprite("tvstand", Pix.tvStand); n.addChild(stand)
            let tv = Pix.sprite("tv", Pix.tv); tv.position = CGPoint(x: 0, y: stand.size.height - 4); n.addChild(tv)
            if d.on {
                let scr = SKSpriteNode(color: NSColor(red: 0.5, green: 0.75, blue: 1, alpha: 1), size: CGSize(width: 16 * 3, height: 7 * 3))
                scr.position = CGPoint(x: 0, y: tv.position.y + 3 * 6.5 + 4); scr.blendMode = .add
                let flick = SKAction.repeatForever(.sequence((0..<8).map { i in
                    .group([.fadeAlpha(to: [0.9, 0.6, 1, 0.7, 0.85, 0.55, 0.95, 0.75][i], duration: 0.12),
                            .colorize(with: [NSColor.systemBlue, .systemTeal, .white, .systemCyan][i % 4], colorBlendFactor: 0.6, duration: 0.12)])
                } + [.wait(forDuration: 0.3)]))
                scr.run(flick); n.addChild(scr)
                let g = SKSpriteNode(texture: Pix.glow(NSColor(red: 0.45, green: 0.65, blue: 1, alpha: 1)))
                g.size = CGSize(width: 200, height: 140); g.position = scr.position; g.blendMode = .add; g.alpha = 0.6
                g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.35, duration: 0.15), .fadeAlpha(to: 0.65, duration: 0.25), .fadeAlpha(to: 0.5, duration: 0.2)])))
                n.addChild(g)
            }
        }
        if !d.online {
            for case let s as SKSpriteNode in n.children { s.color = .gray; s.colorBlendFactor = 1 }
            n.alpha = 0.55
        }
        return n
    }

    /// 悬浮名牌：图标 + 名称 + 状态。点名牌打开详情，点设备本身开关
    private func labelNode(_ d: HouseDevice) -> SKNode {
        let n = SKNode(); n.name = "label:\(d.did)"
        let icon: String = d.kind == .light ? (d.on ? "lightbulb.fill" : "lightbulb") : d.kind == .ac ? "air.conditioner.horizontal" : "tv"
        let tint: NSColor = !d.online ? .gray : !d.on ? NSColor(white: 0.75, alpha: 1)
            : d.kind == .light ? NSColor(red: 1, green: 0.8, blue: 0.4, alpha: 1) : d.kind == .ac ? NSColor(red: 0.5, green: 0.78, blue: 1, alpha: 1) : NSColor(red: 0.6, green: 0.7, blue: 1, alpha: 1)
        let state = !d.online ? L("离线", "Offline") : d.on ? L("开", "On") : L("关", "Off")
        let t = SKLabelNode(text: "\(d.name) · \(state)")
        t.fontName = NSFont.systemFont(ofSize: 12, weight: .semibold).fontName; t.fontSize = 12; t.fontColor = .white
        t.verticalAlignmentMode = .center; t.horizontalAlignmentMode = .left
        let w = t.frame.width + 40, h: CGFloat = 24
        let bgN = SKShapeNode(rect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerRadius: h / 2)
        bgN.fillColor = NSColor(red: 0.08, green: 0.08, blue: 0.12, alpha: 0.82); bgN.strokeColor = tint.withAlphaComponent(0.6); bgN.lineWidth = 1
        n.addChild(bgN)
        let ic = SKSpriteNode(texture: Pix.symbol(icon, tint)); ic.size = ic.size.fitting(14); ic.position = CGPoint(x: -w / 2 + 15, y: 0); n.addChild(ic)
        t.position = CGPoint(x: -w / 2 + 27, y: 0); n.addChild(t)
        let tail = SKShapeNode(rect: CGRect(x: -0.5, y: -h / 2 - 10, width: 1, height: 10)); tail.fillColor = tint.withAlphaComponent(0.5); tail.strokeColor = .clear
        n.addChild(tail)
        return n
    }

    // MARK: 交互

    override func mouseDown(with e: NSEvent) {
        let p = e.location(in: self)
        for n in nodes(at: p) {
            var c: SKNode? = n
            while let x = c {
                if let name = x.name {
                    if name.hasPrefix("label:") { onOpen(String(name.dropFirst(6))); return }
                    if name.hasPrefix("dev:") { onToggle(String(name.dropFirst(4))); return }
                }
                c = x.parent
            }
        }
    }
}

private extension CGSize {
    func fitting(_ h: CGFloat) -> CGSize { height > 0 ? CGSize(width: width * h / height, height: h) : self }
}

struct SeededRandom {
    var s: UInt64
    init(seed: UInt64) { s = seed }
    mutating func next() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat((s >> 33) % 10_000) / 10_000 }
}

// MARK: SwiftUI

struct HouseSceneView: NSViewRepresentable {
    let rooms: [HouseRoom]
    var tiltShift: Bool
    var onToggle: (String) -> Void
    var onOpen: (String) -> Void
    func makeNSView(context: Context) -> SKView {
        let v = SKView(); v.preferredFramesPerSecond = 30; v.ignoresSiblingOrder = false; v.allowsTransparency = false
        v.presentScene(HouseScene(size: CGSize(width: 900, height: 600)))
        return v
    }
    func updateNSView(_ v: SKView, context: Context) {
        guard let s = v.scene as? HouseScene else { return }
        s.onToggle = onToggle; s.onOpen = onOpen
        if s.tiltShift != tiltShift { s.tiltShift = tiltShift }
        s.update(rooms: rooms)
    }
}

struct HouseView: View {
    @EnvironmentObject var m: AppModel
    @State private var tilt = true
    @State private var detail: String?
    var body: some View {
        HouseSceneView(rooms: m.houseRooms, tiltShift: tilt,
                       onToggle: { did in if let d = m.device(did) { m.toggle(d) } },
                       onOpen: { did in detail = did })
            .ignoresSafeArea()
            .overlay(alignment: .topTrailing) {
                IconButton(icon: tilt ? "camera.aperture" : "camera", help: L("移轴景深", "Tilt-shift"), tint: tilt ? Theme.cool : nil) { tilt.toggle() }
                    .padding(10)
            }
            .sheet(item: Binding(get: { detail.map { IdentStr(id: $0) } }, set: { detail = $0?.id })) { x in
                if let d = m.device(x.id) {
                    ScrollView { DetailView(device: d).padding(12) }
                        .frame(width: 360, height: 560).background(Theme.bg)
                        .onChange(of: m.page) { _, p in if case .detail = p {} else { detail = nil } }
                        .onAppear { m.open(d, animated: false) }
                }
            }
            .frame(minWidth: 560, minHeight: 380)
    }
}
private struct IdentStr: Identifiable { let id: String }

/// 可调整大小的独立「小屋」窗口
@MainActor
enum HouseWindow {
    static var window: NSWindow?
    static func open(model: AppModel) {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = L("小屋", "House")
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: HouseView().environmentObject(model))
        w.center(); window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window?.contentView = nil; window = nil }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: 截图（演示数据）

enum HouseSnapshot {
    @MainActor static func image(_ rooms: [HouseRoom], size: CGSize = CGSize(width: 1200, height: 800)) -> CGImage? {
        let v = SKView(frame: CGRect(origin: .zero, size: size)); v.ignoresSiblingOrder = false
        let win = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = v; win.setFrameOrigin(NSPoint(x: 40, y: 40)); win.orderFrontRegardless()
        let s = HouseScene(size: size); v.presentScene(s); s.update(rooms: rooms)
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        defer { win.orderOut(nil) }
        return v.texture(from: s, crop: CGRect(origin: CGPoint(x: -size.width / 2, y: -size.height / 2), size: size))?.cgImage()
    }
    @MainActor static func write(_ img: CGImage?, _ url: URL) {
        guard let img else { print("house snapshot failed"); return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url); print("wrote \(url.path)")
    }
}

extension Snapshot {
    /// `MijiaBarApp --house-snapshot <dir>`：小屋原型截图。临时加一台演示电视、书房台灯、卧室灯（只在这次截图里）
    static func house(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir); try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let m = AppModel(mock: true)
        func dev(_ id: String, _ n: String, _ model: String, _ room: String) -> Device { Device(did: id, name: n, model: model, homeId: "h1", homeName: "", roomName: room) }
        m.devices += [dev("x1", L("电视", "TV"), "xiaomi.tv.demo", L("客厅", "Living room")),
                      dev("x2", L("台灯", "Desk lamp"), "yeelink.light.demo", L("书房", "Study")),
                      dev("x3", L("床头灯", "Bedside lamp"), "yeelink.light.demo2", L("主卧", "Bedroom"))]
        let onSpec = DeviceSpec(type: "", description: "", services: [SpecService(iid: 2, type: "urn:miot-spec-v2:service:light:0", description: "", properties: [
            SpecProperty(siid: 2, iid: 1, type: "urn:miot-spec-v2:property:on:0", description: "on", format: "bool", access: ["read", "write"], unit: nil, range: nil, options: nil)], actions: [])])
        func set(_ id: String, _ on: Bool) {
            if id == "d1" || id == "d2" { m.states[id]?.values["power"] = .string(on ? "on" : "off"); return }
            if m.states[id] == nil { m.states[id] = DeviceState(values: [:], spec: onSpec, legacy: false, source: "cloud") }
            m.states[id]?.values["2.1"] = .bool(on)
        }
        for (id, on) in [("d1", true), ("d2", false), ("d3", true), ("x1", true), ("x2", true), ("x3", false)] { set(id, on) }
        HouseSnapshot.write(HouseSnapshot.image(m.houseRooms), out.appendingPathComponent("house-proto-night.png"))
        for id in ["d1", "d3", "x1", "x2"] { set(id, false) }
        HouseSnapshot.write(HouseSnapshot.image(m.houseRooms), out.appendingPathComponent("house-proto-off.png"))
        for (id, on) in [("d1", true), ("d3", true), ("x1", true), ("x2", true)] { set(id, on) }
        // 窗口 + 菜单栏头部按钮
        appearance = NSAppearance(named: .darkAqua)
        m.page = .list
        let shot = HouseSnapshot.image(m.houseRooms, size: CGSize(width: 960, height: 600)).map { NSImage(cgImage: $0, size: NSSize(width: 960, height: 600)) }
        let combo = HStack(alignment: .top, spacing: 24) {
            RootView().environmentObject(m).frame(width: 360, height: 560).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .topTrailing) { Circle().stroke(Theme.cool, lineWidth: 2).frame(width: 30, height: 30).allowsHitTesting(false).offset(x: -HouseSnapshot.headerOffset, y: 9) }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([Color.red, .yellow, .green], id: \.self) { Circle().fill($0).frame(width: 12, height: 12) }
                    Spacer(); Text(L("小屋", "House")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary); Spacer().frame(width: 60)
                }.padding(.horizontal, 12).frame(height: 28).background(Color(white: 0.16))
                if let shot { Image(nsImage: shot).resizable().frame(width: 960, height: 600) }
            }.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }.padding(24).background(Color(white: 0.1))
        render(combo, out.appendingPathComponent("house-proto-window.png"), size: CGSize(width: 1392, height: 676))
        exit(0)
    }
}
extension HouseSnapshot { static let headerOffset: CGFloat = 128 }
