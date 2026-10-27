import Foundation
import CoreGraphics
import ImageIO

public struct HousePetRig: Codable, Sendable {
    public struct Action: Codable, Sendable {
        public var fps: Double
        public var loop: Bool
        public var frames: [String: [Int]]
    }
    public struct Lighting: Codable, Sendable {
        public var mul: [Double]
        public var add: [Double]
        public init(mul: [Double] = [1, 1, 1], add: [Double] = [0, 0, 0]) { self.mul = mul; self.add = add }
    }
    public static let patterns = ["solid", "tabby", "tabbyWhite", "bicolor", "calico", "colorpoint"]
    public struct Template: Sendable {
        public let species: String
        public let patterns: [String]
    }
    public static let supported: [String: Template] = [
        "cat-short": .init(species: "cat", patterns: patterns),
        "dog-short": .init(species: "dog", patterns: patterns)
    ]
    public static var allPatterns: [String] { Array(Set(supported.values.flatMap(\.patterns))).sorted() }
    public static func accepts(species: String, rig: String, pattern: String) -> Bool {
        supported[rig]?.species == species && supported[rig]?.patterns.contains(pattern) == true
    }
    public var id: String
    public var species: String
    public var cellPx: Int
    public var frameSize: [Int]
    public var anchor: [Double]
    public var columns: Int
    public var frameCount: Int
    public var patterns: [String]
    public var sheets: [String: String]
    public var actions: [String: Action]
    public var mirror: [String: String]
    public var lighting: [String: Lighting]
    public var regions: [String: Int]

    public static func load(from url: URL) throws -> Self {
        let rig = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard rig.frameSize.count == 2, rig.frameSize.allSatisfy({ (1...256).contains($0) }),
              rig.anchor.count == 2, rig.anchor.allSatisfy(\.isFinite), (1...8).contains(rig.cellPx),
              (1...256).contains(rig.columns), (1...1024).contains(rig.frameCount),
              !rig.actions.isEmpty, !rig.patterns.isEmpty,
              rig.patterns.allSatisfy({ rig.sheets[$0] != nil }),
              rig.sheets.values.allSatisfy({ !$0.contains("/") && !$0.contains("\\") && $0.hasSuffix(".png") }),
              rig.actions.values.allSatisfy({ $0.fps.isFinite && $0.fps > 0 && $0.fps <= 120 && !$0.frames.isEmpty && $0.frames.values.allSatisfy { !$0.isEmpty && $0.allSatisfy { (0..<rig.frameCount).contains($0) } } }),
              rig.lighting.values.allSatisfy({ $0.mul.count == 3 && $0.add.count == 3 && ($0.mul + $0.add).allSatisfy(\.isFinite) }) else { throw HousePetError.resource }
        return rig
    }
    public func frame(action: String, facing: String, elapsed: Double) -> (index: Int, mirrored: Bool) {
        let mirrored = mirror[facing] != nil, direction = mirror[facing] ?? facing
        guard let animation = actions[action] ?? actions["idle"], let frames = animation.frames[direction] ?? animation.frames["SE"], !frames.isEmpty else { return (0, mirrored) }
        let tick = Int(min(Double(Int.max / 2), max(0, elapsed.isFinite ? elapsed : 0) * animation.fps))
        return (frames[animation.loop ? tick % frames.count : min(tick, frames.count - 1)], mirrored)
    }
}

public struct HousePetSheet: Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]
    public init(width: Int, height: Int, rgba: [UInt8]) throws {
        guard width > 0, height > 0, width <= 8192, height <= 8192, rgba.count == width * height * 4 else { throw HousePetError.resource }
        self.width = width; self.height = height; self.rgba = rgba
    }
    public static func load(from url: URL) throws -> Self {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) else { throw HousePetError.resource }
        return try decode(image)
    }
    public static func decode(_ image: CGImage) throws -> Self {
        guard image.width <= 8192, image.height <= 8192, image.bitsPerComponent == 8, image.bitsPerPixel == 32,
              let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { throw HousePetError.resource }
        let alpha = image.alphaInfo
        guard [.first, .last, .noneSkipFirst, .noneSkipLast].contains(alpha) else { throw HousePetError.resource }
        let first = alpha == .first || alpha == .noneSkipFirst
        let little = image.bitmapInfo.intersection(.byteOrderMask) == .byteOrder32Little
        var channels = first ? [1, 2, 3, 0] : [0, 1, 2, 3]
        if little { channels = channels.map { 3 - $0 } }
        let opaque = alpha == .noneSkipFirst || alpha == .noneSkipLast
        guard image.bytesPerRow >= image.width * 4, CFDataGetLength(data) >= image.bytesPerRow * image.height else { throw HousePetError.resource }
        var output = [UInt8](repeating: 0, count: image.width * image.height * 4)
        for row in 0..<image.height {
            for col in 0..<image.width {
                let source = row * image.bytesPerRow + col * 4, target = (row * image.width + col) * 4
                for channel in 0..<4 { output[target + channel] = channel == 3 && opaque ? 255 : bytes[source + channels[channel]] }
            }
        }
        return try .init(width: image.width, height: image.height, rgba: output)
    }
}

public enum HousePetRecolor {
    public static func pixel(_ encoded: [UInt8], palette: HousePetPalette, lighting: HousePetRig.Lighting) -> [UInt8] {
        guard encoded.count == 4, palette.isValid, lighting.mul.count == 3, lighting.add.count == 3,
              (lighting.mul + lighting.add).allSatisfy(\.isFinite) else { return [0, 0, 0, 0] }
        return pixel(encoded, table: table(palette), lighting: lighting)
    }
    private static func table(_ palette: HousePetPalette) -> [[Double]] {
        func rgb(_ hex: String) -> [Double] {
            let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
            return [Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255]
        }
        let base = rgb(palette.base), closed = zip(base, [0.08, 0.05, 0.06]).map { $0 * 0.30 + $1 * 0.7 }
        var table = [[Double]](repeating: [0, 0, 0], count: 16)
        table[1] = base; table[2] = rgb(palette.second); table[3] = rgb(palette.white)
        table[4] = zip(base, [1, 0.95, 0.88]).map { $0 * 0.7 + $1 * 0.3 }
        table[5] = [0.93, 0.60, 0.64]; table[6] = rgb(palette.eye); table[7] = [0.09, 0.07, 0.09]
        table[8] = [1, 1, 1]; table[9] = closed; table[11] = closed
        return table
    }
    private static func pixel(_ encoded: [UInt8], table: [[Double]], lighting: HousePetRig.Lighting) -> [UInt8] {
        let alpha = encoded[3]
        if alpha == 0 { return [0, 0, 0, 0] }
        if alpha < 255 { return [31, 20, 18, alpha] }
        let region = Int(encoded[0] & 15), outline = (encoded[0] >> 4) & 1 == 1
        let shade = Double(encoded[1]) / 127.5, spec = Double(encoded[2]) / 255
        func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
        let shadowTint = clamp((0.85 - shade) / 0.6), highlightTint = clamp((shade - 1) / 0.4)
        var result: [UInt8] = []
        for channel in 0..<3 {
            let colour = table[region][channel]
            let tint = 1 + shadowTint * ([0.86, 0.89, 1.10][channel] - 1) * 0.7 + highlightTint * ([1.05, 1.02, 0.95][channel] - 1)
            var value = colour * shade * tint + spec * [1, 0.97, 0.92][channel]
            if [6, 7, 8, 9].contains(region) { value = colour }
            if outline { value = (colour * 0.42 * [0.92, 0.88, 0.95][channel] + [0.07, 0.04, 0.05][channel]) * 0.75 }
            result.append(UInt8((clamp(clamp(value) * lighting.mul[channel] + lighting.add[channel]) * 255).rounded()))
        }
        return result + [alpha]
    }
    public static func image(width: Int, height: Int, rgba: [UInt8]) throws -> CGImage {
        guard width > 0, height > 0, rgba.count == width * height * 4,
              let provider = CGDataProvider(data: Data(rgba) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw HousePetError.resource }
        return image
    }
    public static func frames(sheet: HousePetSheet, rig: HousePetRig, palette: HousePetPalette, phase: String) throws -> [CGImage] {
        guard palette.isValid, let lighting = rig.lighting[phase], rig.frameSize.count == 2, rig.columns > 0, rig.frameCount > 0,
              rig.frameSize.allSatisfy({ (1...256).contains($0) }), lighting.mul.count == 3, lighting.add.count == 3,
              (lighting.mul + lighting.add).allSatisfy(\.isFinite) else { throw HousePetError.invalid }
        let width = rig.frameSize[0], height = rig.frameSize[1]
        guard sheet.width == rig.columns * width, sheet.height >= ((rig.frameCount + rig.columns - 1) / rig.columns) * height else { throw HousePetError.resource }
        var recolored = sheet.rgba
        let colours = table(palette)
        for offset in stride(from: 0, to: recolored.count, by: 4) {
            let output = pixel(Array(sheet.rgba[offset..<offset + 4]), table: colours, lighting: lighting)
            recolored.replaceSubrange(offset..<offset + 4, with: output)
        }
        return try (0..<rig.frameCount).map { frame in
            var pixels: [UInt8] = []; pixels.reserveCapacity(width * height * 4)
            for row in 0..<height {
                let start = ((frame / rig.columns * height + row) * sheet.width + frame % rig.columns * width) * 4
                pixels.append(contentsOf: recolored[start..<start + width * 4])
            }
            return try image(width: width, height: height, rgba: pixels)
        }
    }
}

public final class HousePetFrameCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cache: [String: [CGImage]] = [:]
    public init() {}
    public func frames(pet: HousePet, rig: HousePetRig, directory: URL, phase: String) throws -> [CGImage] {
        let key = directory.standardizedFileURL.path + "|" + rig.id + "|" + pet.pattern + "|" + phase + "|" + [pet.palette.base, pet.palette.second, pet.palette.white, pet.palette.eye].joined(separator: ",")
        lock.lock(); defer { lock.unlock() }
        if let frames = cache[key] { return frames }
        guard let file = rig.sheets[pet.pattern], !file.contains("/"), !file.contains("\\") else { throw HousePetError.resource }
        let frames = try HousePetRecolor.frames(sheet: .load(from: directory.appendingPathComponent(file)), rig: rig, palette: pet.palette, phase: phase)
        if cache.count >= 12 { cache.removeAll() }; cache[key] = frames; return frames
    }
    public func clear() { lock.lock(); defer { lock.unlock() }; cache.removeAll() }
}
