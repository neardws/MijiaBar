import Foundation
import CoreGraphics
import ImageIO
import Vision
import CoreVideo

public enum HousePetPhoto {
    public struct Result: Codable, Equatable, Sendable {
        public var palette: HousePetPalette
        public var pattern: String
        public var species: String
        public var confidence: Double
    }
    private struct Sample {
        var rgb: [Double]
        var lab: [Double]
        var x: Double
        var y: Double
    }
    private static func lab(_ rgb: [Double]) -> [Double] {
        let linear = rgb.map { $0 > 0.04045 ? pow(($0 + 0.055) / 1.055, 2.4) : $0 / 12.92 }
        let xyz = [(linear[0] * 0.4124564 + linear[1] * 0.3575761 + linear[2] * 0.1804375) / 0.95047,
                   linear[0] * 0.2126729 + linear[1] * 0.7151522 + linear[2] * 0.0721750,
                   (linear[0] * 0.0193339 + linear[1] * 0.1191920 + linear[2] * 0.9503041) / 1.08883]
        let transformed = xyz.map { $0 > 0.008856 ? pow($0, 1 / 3.0) : 7.787 * $0 + 16 / 116.0 }
        return [116 * transformed[1] - 16, 500 * (transformed[0] - transformed[1]), 200 * (transformed[1] - transformed[2])]
    }
    private static func distance(_ left: [Double], _ right: [Double]) -> Double { zip(left, right).reduce(0) { $0 + pow($1.0 - $1.1, 2) } }
    public static func analyze(rgba: [UInt8], width: Int, height: Int, mask: [UInt8]? = nil, eye: String? = nil, species: String = "unknown") throws -> Result {
        guard width > 0, height > 0, width <= 8192, height <= 8192, rgba.count == width * height * 4,
              mask == nil || mask?.count == width * height, eye == nil || HousePetPalette(eye: eye!).isValid else { throw HousePetError.invalid }
        var samples: [Sample] = []
        let step = max(1, Int(sqrt(Double(width * height) / 16000)))
        for row in stride(from: 0, to: height, by: step) {
            for col in stride(from: 0, to: width, by: step) {
                let index = row * width + col
                guard rgba[index * 4 + 3] > 127, mask == nil || mask![index] > 127 else { continue }
                let rgb = (0..<3).map { Double(rgba[index * 4 + $0]) / 255 }
                samples.append(.init(rgb: rgb, lab: lab(rgb), x: (Double(col) + 0.5) / Double(width), y: (Double(row) + 0.5) / Double(height)))
            }
        }
        guard let first = samples.first else { throw HousePetError.invalid }
        var centers = [first.lab]
        for _ in 1..<5 {
            centers.append(samples.max { sampleA, sampleB in
                centers.map { distance(sampleA.lab, $0) }.min()! < centers.map { distance(sampleB.lab, $0) }.min()!
            }!.lab)
        }
        var assignments = [Int](repeating: 0, count: samples.count)
        var counts = [Int](repeating: 0, count: 5)
        var colours = [[Double]](repeating: [0, 0, 0], count: 5)
        for _ in 0..<16 {
            var changed = false
            var totals = [[Double]](repeating: [0, 0, 0], count: 5)
            counts = .init(repeating: 0, count: 5); colours = .init(repeating: [0, 0, 0], count: 5)
            for (index, sample) in samples.enumerated() {
                let cluster = (0..<5).min { distance(sample.lab, centers[$0]) < distance(sample.lab, centers[$1]) }!
                if assignments[index] != cluster { changed = true }
                assignments[index] = cluster; counts[cluster] += 1
                for channel in 0..<3 { totals[cluster][channel] += sample.lab[channel]; colours[cluster][channel] += sample.rgb[channel] }
            }
            for cluster in 0..<5 where counts[cluster] > 0 {
                centers[cluster] = totals[cluster].map { $0 / Double(counts[cluster]) }
                colours[cluster] = colours[cluster].map { $0 / Double(counts[cluster]) }
            }
            if !changed { break }
        }
        let clusters = (0..<5).filter { Double(counts[$0]) / Double(samples.count) > 0.025 }.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0] > counts[$1] }
        func fraction(_ indices: [Int]) -> Double { Double(indices.reduce(0) { $0 + counts[$1] }) / Double(samples.count) }
        func white(_ index: Int) -> Bool { let rgb = colours[index]; return rgb.min()! > 0.72 && rgb.max()! - rgb.min()! < 0.12 }
        let whites = clusters.filter(white), coats = clusters.filter { !white($0) }
        let primary = coats.first ?? clusters[0], base = colours[primary]
        let dark = coats.filter { centers[$0][0] < 40 }
        let orange = coats.filter { colours[$0][0] > colours[$0][2] * 1.35 && colours[$0][0] > colours[$0][1] * 1.08 && centers[$0][0] > 35 }
        let sameHueDark = coats.filter { $0 != primary && centers[$0][0] < centers[primary][0] - 10 && abs(atan2(centers[$0][2], centers[$0][1]) - atan2(centers[primary][2], centers[primary][1])) < 0.55 }
        let whiteAmount = fraction(whites)
        var pattern = fraction(sameHueDark) > 0.08 ? "tabby" : "solid"
        if whiteAmount > 0.12 { pattern = pattern == "tabby" ? "tabbyWhite" : "bicolor" }
        let calicoDark = dark.filter { !sameHueDark.contains($0) || hypot(centers[$0][1], centers[$0][2]) < 12 }
        if whiteAmount > 0.12 && !orange.isEmpty && fraction(calicoDark) > 0.08 { pattern = "calico" }
        let creamIndex = clusters.first { colours[$0].min()! > 0.5 && colours[$0][0] - colours[$0][2] > 0.02 && colours[$0][0] - colours[$0][2] < 0.30 }
        let darkIndices = Set(coats.filter { centers[$0][0] < centers[creamIndex ?? primary][0] - 25 })
        var edgeDark = 0, centerDark = 0, edgeCount = 0, centerCount = 0
        for (index, sample) in samples.enumerated() {
            if sample.x < 0.25 || sample.x > 0.75 || sample.y < 0.25 || sample.y > 0.75 {
                edgeCount += 1; if darkIndices.contains(assignments[index]) { edgeDark += 1 }
            } else { centerCount += 1; if darkIndices.contains(assignments[index]) { centerDark += 1 } }
        }
        if creamIndex != nil && fraction(Array(darkIndices)) > 0.08 && Double(edgeDark) / Double(max(1, edgeCount)) > Double(centerDark) / Double(max(1, centerCount)) + 0.12 { pattern = "colorpoint" }
        func hex(_ rgb: [Double], lift: Bool = true) -> String {
            let maximum = rgb.max()!, minimum = rgb.min()!, middle = (maximum + minimum) / 2
            let adjusted = rgb.map { min(1, max(0, lift ? middle + ($0 - middle) * 1.12 + (maximum < 0.85 ? 0.035 : 0) : $0)) }
            return "#" + adjusted.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
        }
        let coat = pattern == "colorpoint" ? colours[creamIndex ?? primary] : base
        let second = (pattern == "colorpoint" ? dark.first : sameHueDark.first ?? coats.dropFirst().first).map { colours[$0] } ?? coat.map { $0 * 0.70 }
        let eyeColour = eye ?? (pattern == "colorpoint" ? "#4E8FE0" : (!orange.isEmpty ? "#9CC43E" : "#E9C24A"))
        return .init(palette: .init(base: hex(coat), second: hex(second), white: whites.first.map { hex(colours[$0], lift: false) } ?? "#F4EEE4", eye: eyeColour),
                     pattern: pattern, species: species, confidence: min(0.95, 0.55 + Double(counts[primary]) / Double(samples.count) * 0.4))
    }

    public static func load(from url: URL, eye: String? = nil, recognizeSpecies: Bool = true) throws -> Result {
        guard url.isFileURL, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 512] as CFDictionary) else { throw HousePetError.invalid }
        let width = image.width, height = image.height
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard drawn else { throw HousePetError.invalid }
        for index in 0..<width * height where rgba[index * 4 + 3] > 0 && rgba[index * 4 + 3] < 255 {
            let alpha = Double(rgba[index * 4 + 3]) / 255
            for channel in 0..<3 { rgba[index * 4 + channel] = UInt8(min(255, (Double(rgba[index * 4 + channel]) / alpha).rounded())) }
        }
        let foreground = HousePetForeground.mask(image: image)
        var species = "unknown"
        if recognizeSpecies {
            let request = VNRecognizeAnimalsRequest()
            if (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil {
                let labels = (request.results ?? []).flatMap(\.labels).sorted { $0.confidence > $1.confidence }
                if let label = labels.first, label.confidence > 0.3 { species = label.identifier.lowercased().contains("cat") ? "cat" : label.identifier.lowercased().contains("dog") ? "dog" : "unknown" }
            }
        }
        return try analyze(rgba: rgba, width: width, height: height, mask: foreground, eye: eye, species: species)
    }
}

public enum HousePetForeground {
    public static func ellipse(width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { return [] }
        return (0..<width * height).map { index in
            let horizontal = ((Double(index % width) + 0.5) / Double(width) - 0.5) / 0.46
            let vertical = ((Double(index / width) + 0.5) / Double(height) - 0.5) / 0.49
            return horizontal * horizontal + vertical * vertical <= 1 ? 255 : 0
        }
    }
    public static func mask(image: CGImage) -> [UInt8] {
        if #available(macOS 14, *) {
            let request = VNGenerateForegroundInstanceMaskRequest(), handler = VNImageRequestHandler(cgImage: image)
            if (try? handler.perform([request])) != nil, let observation = request.results?.first,
               !observation.allInstances.isEmpty,
               let buffer = try? observation.generateScaledMaskForImage(forInstances: observation.allInstances, from: handler) {
                CVPixelBufferLockBaseAddress(buffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
                if CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8,
                   CVPixelBufferGetWidth(buffer) == image.width, CVPixelBufferGetHeight(buffer) == image.height,
                   let bytes = CVPixelBufferGetBaseAddress(buffer)?.assumingMemoryBound(to: UInt8.self) {
                    let stride = CVPixelBufferGetBytesPerRow(buffer)
                    return (0..<image.width * image.height).map { bytes[($0 / image.width) * stride + $0 % image.width] }
                }
            }
        }
        return ellipse(width: image.width, height: image.height)
    }
}
