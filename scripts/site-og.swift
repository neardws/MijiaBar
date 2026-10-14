// 网站分享图（og:image，1200×630）：图标 + MijiaBar + 一排设备插画，与语言无关
// 用法：swift scripts/site-og.swift <插画目录（--art 的输出，PNG）> <输出 PNG>
import AppKit

let args = CommandLine.arguments
guard args.count == 3 else { print("usage: site-og.swift <art-dir> <out.png>"); exit(1) }
let artDir = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let W = 1200.0, H = 630.0, S = 2.0

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * S), pixelsHigh: Int(H * S), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// 背景：浅灰到白，和网站的浅色区块一致
NSGradient(starting: NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), ending: .white)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: 90)

func image(_ url: URL) -> NSImage { NSImage(contentsOf: url) ?? NSImage() }
// 图标（自带 macOS 图标模板的留白和投影）
image(root.appendingPathComponent("docs/assets/icon.png")).draw(in: NSRect(x: (W - 168) / 2, y: H - 64 - 168, width: 168, height: 168))

// 字标
let title = NSAttributedString(string: "MijiaBar", attributes: [
    .font: NSFont.systemFont(ofSize: 76, weight: .semibold), .foregroundColor: NSColor(srgbRed: 0.114, green: 0.114, blue: 0.122, alpha: 1), .kern: -1.2])
let ts = title.size()
title.draw(at: NSPoint(x: (W - ts.width) / 2, y: H - 64 - 168 - 8 - ts.height))

// 一排插画（开机状态）；四边淡出，光晕不留硬边
func faded(_ img: NSImage, _ size: NSSize) -> NSImage {
    NSImage(size: size, flipped: false) { r in
        img.draw(in: r)
        let clear = NSColor.black.withAlphaComponent(0), solid = NSColor.black
        NSGraphicsContext.current?.compositingOperation = .destinationIn
        NSGradient(colorsAndLocations: (clear, 0), (solid, 0.14), (solid, 0.86), (clear, 1))!.draw(in: r, angle: 0)
        NSGradient(colorsAndLocations: (clear, 0), (solid, 0.12), (solid, 0.88), (clear, 1))!.draw(in: r, angle: 90)
        return true
    }
}
let names = ["ac", "fan", "bulb", "plug", "camera"]
let h = 92.0, gap = 28.0
let sizes = names.map { n -> NSSize in NSSize(width: (n == "ac" ? 300.0 : 240.0) / 136 * h, height: h) }
var x = (W - sizes.map(\.width).reduce(0, +) - gap * Double(names.count - 1)) / 2
for (n, s) in zip(names, sizes) {
    faded(image(artDir.appendingPathComponent("\(n)-light.png")), s).draw(in: NSRect(x: x, y: 92, width: s.width, height: s.height))
    x += s.width + gap
}

NSGraphicsContext.restoreGraphicsState()
// 输出 1200×630（2 倍绘制后缩小，边缘更干净）
let small = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                             hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: small)
NSGraphicsContext.current?.imageInterpolation = .high
rep.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.restoreGraphicsState()
try! small.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.path)")
