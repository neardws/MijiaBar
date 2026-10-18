import Foundation
import CoreGraphics

public struct HouseDecorImage {
    public var placement: HouseDecorPlacement
    public var image: CGImage
    public var anchor: [Double]
    public init(placement: HouseDecorPlacement, image: CGImage, anchor: [Double]) {
        self.placement = placement; self.image = image; self.anchor = anchor
    }
    public var x: Int { Int((placement.at[0] - anchor[0]).rounded()) }
    public var y: Int { Int((placement.at[1] - anchor[1]).rounded()) }
}

enum HouseDecorPixels {
    struct RenderKey: Hashable {
        var sprite: ObjectIdentifier
        var unlit: ObjectIdentifier
        var lit: ObjectIdentifier
        var x: Int
        var y: Int
    }
    struct Rendered {
        var image: CGImage
        var originals: [CGImage]
    }
    final class Buffer: @unchecked Sendable {
        let image: CGImage
        let bytes: [UInt8]
        let sums: [Double]
        init?(_ image: CGImage) {
            self.image = image
            let width = image.width, height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let success = bytes.withUnsafeMutableBytes { data -> Bool in
                guard let context = CGContext(data: data.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
            }
            guard success else { return nil }
            self.bytes = bytes
            var sums = [Double](repeating: 0, count: (width + 1) * (height + 1))
            for row in 0..<height {
                var total = 0.0
                for column in 0..<width {
                    let index = (row * width + column) * 4, alpha = Double(bytes[index + 3])
                    total += alpha > 0 ? (0.2126 * Double(bytes[index]) + 0.7152 * Double(bytes[index + 1]) + 0.0722 * Double(bytes[index + 2])) / alpha : 0
                    sums[(row + 1) * (width + 1) + column + 1] = sums[row * (width + 1) + column + 1] + total
                }
            }
            self.sums = sums
        }
        func luminance(x: Int, y: Int) -> Double {
            let left = max(0, x - 2), right = min(image.width, x + 3)
            let top = max(0, y - 2), bottom = min(image.height, y + 3), stride = image.width + 1
            guard left < right && top < bottom else { return 0 }
            return (sums[bottom * stride + right] - sums[top * stride + right] - sums[bottom * stride + left] + sums[top * stride + left]) / Double((right - left) * (bottom - top))
        }
    }
    final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var buffers: [ObjectIdentifier: Buffer] = [:]
        var rendered: [RenderKey: Rendered] = [:]
        func image(for key: RenderKey) -> CGImage? {
            lock.lock(); defer { lock.unlock() }; return rendered[key]?.image
        }
        func store(_ image: CGImage, for key: RenderKey, originals: [CGImage]) {
            lock.lock(); defer { lock.unlock() }
            if rendered.count >= 256 { rendered.removeAll() }
            rendered[key] = Rendered(image: image, originals: originals)
        }
        func buffer(_ image: CGImage) -> Buffer? {
            lock.lock(); defer { lock.unlock() }
            let key = ObjectIdentifier(image)
            if let buffer = buffers[key] { return buffer }
            guard let buffer = Buffer(image) else { return nil }
            if buffers.count >= 128 { buffers.removeAll() }
            buffers[key] = buffer; return buffer
        }
    }
    static let cache = Cache()
    static func brightened(_ decor: HouseDecorImage, module: HouseModuleImages) -> CGImage {
        let key = RenderKey(sprite: ObjectIdentifier(decor.image), unlit: ObjectIdentifier(module.unlit), lit: ObjectIdentifier(module.lit), x: decor.x, y: decor.y)
        if let image = cache.image(for: key) { return image }
        guard let sprite = cache.buffer(decor.image), let unlit = cache.buffer(module.unlit), let lit = cache.buffer(module.lit) else { return decor.image }
        var bytes = sprite.bytes
        for row in 0..<decor.image.height {
            for column in 0..<decor.image.width {
                let index = (row * decor.image.width + column) * 4, alpha = bytes[index + 3]
                guard alpha > 0 else { continue }
                let x = decor.x + column, y = decor.y + row
                let base = unlit.luminance(x: x, y: y), light = lit.luminance(x: x, y: y)
                let ratio = base > 0 ? min(2.5, max(1, light / base)) : (light > 0 ? 2.5 : 1)
                for channel in 0..<3 { bytes[index + channel] = UInt8(min(Double(alpha), Double(bytes[index + channel]) * ratio)) }
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let image = CGImage(width: decor.image.width, height: decor.image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: decor.image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return decor.image }
        cache.store(image, for: key, originals: [decor.image, module.unlit, module.lit])
        return image
    }
}
