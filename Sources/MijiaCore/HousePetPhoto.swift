import Foundation
import CoreGraphics
import ImageIO
import Vision
import CoreVideo

public enum HousePetPhoto {
    public struct Diagnostics: Codable, Equatable, Sendable {
        public var white: Double
        public var neutralDark: Double
        public var warm: Double
        public var grey: Double
        public var cream: Double
        public var striped: Bool
        public var maskCoverage: Double
        public var whiteBalanceApplied: Bool
    }
    public struct Result: Codable, Equatable, Sendable {
        public var palette: HousePetPalette
        public var pattern: String
        public var species: String
        public var confidence: Double
        public var diagnostics: Diagnostics
        public var usedVisionMask: Bool = false
        public var usedEyePose: Bool = false
        public func pet(name: String = "") -> HousePet {
            let selected = species.lowercased() == "dog" ? "dog" : "cat"
            return HousePet(name: name, species: selected, rig: selected + "-short", pattern: pattern, palette: palette)
        }
    }
    public struct Analysis {
        public var image: CGImage
        public var mask: [UInt8]
        public var result: Result
    }
    private struct Sample {
        var rgb: [Double]
        var lab: [Double]
        var x: Double
        var y: Double
        var chroma: Double { hypot(lab[1], lab[2]) }
        var white: Bool { lab[0] > 66 && chroma < 18 }
        var neutralDark: Bool { lab[0] < 32 && chroma < 15 }
        var warm: Bool { chroma > 14 && (30...90).contains(atan2(lab[2], lab[1]) * 180 / .pi) && lab[0] > 25 }
    }
    private static func lab(_ rgb: [Double]) -> [Double] {
        let linear = rgb.map { $0 > 0.04045 ? pow(($0 + 0.055) / 1.055, 2.4) : $0 / 12.92 }
        let xyz = [(linear[0] * 0.4124564 + linear[1] * 0.3575761 + linear[2] * 0.1804375) / 0.95047,
                   linear[0] * 0.2126729 + linear[1] * 0.7151522 + linear[2] * 0.0721750,
                   (linear[0] * 0.0193339 + linear[1] * 0.1191920 + linear[2] * 0.9503041) / 1.08883]
        let transformed = xyz.map { $0 > 0.008856 ? pow($0, 1 / 3.0) : 7.787 * $0 + 16 / 116.0 }
        return [116 * transformed[1] - 16, 500 * (transformed[0] - transformed[1]), 200 * (transformed[1] - transformed[2])]
    }
    private static func distance(_ left: [Double], _ right: [Double]) -> Double {
        let lightness = left[0] - right[0], greenRed = left[1] - right[1], blueYellow = left[2] - right[2]
        return lightness * lightness + greenRed * greenRed + blueYellow * blueYellow
    }
    private static func median(_ values: [Double]) -> Double { let sorted = values.sorted(); return sorted[sorted.count / 2] }
    private static func medianRGB(_ samples: [Sample]) -> [Double] { (0..<3).map { channel in median(samples.map { $0.rgb[channel] }) } }
    private static func hex(_ rgb: [Double]) -> String { "#" + rgb.map { String(format: "%02X", Int((min(1, max(0, $0)) * 255).rounded())) }.joined() }
    private static func boost(_ rgb: [Double], saturation: Double, minimum: Double, minimumSaturation: Double = 0) -> [Double] {
        let value = rgb.max()!
        guard value > 0 else { return .init(repeating: minimum, count: 3) }
        let current = (value - rgb.min()!) / value, boosted = min(1, max(minimumSaturation, current * saturation))
        let scale = current > 0 ? boosted / current : 0, raised = max(value, minimum)
        return rgb.map { raised * max(0, 1 - (1 - $0 / value) * scale) }
    }
    private static func neutralizeNearBlack(_ rgb: [Double]) -> [Double] {
        let value = rgb.max()!
        guard value > 0 && value < 0.28 else { return rgb }
        let saturation = (value - rgb.min()!) / value
        guard saturation > 0.18 else { return rgb }
        return rgb.map { value * (1 - (1 - $0 / value) * 0.18 / saturation) }
    }
    public static func eyeColour(_ samples: [[UInt8]]) -> String? {
        let colours = samples.filter { $0.count == 3 }.map { $0.map { Double($0) / 255 } }.filter {
            let value = $0.max()!, saturation = value > 0 ? (value - $0.min()!) / value : 0
            return saturation > 0.18 && (0.22...0.97).contains(value)
        }
        guard !colours.isEmpty else { return nil }
        let rgb = (0..<3).map { channel in median(colours.map { $0[channel] }) }
        return hex(boost(rgb, saturation: 1.4, minimum: 0.50))
    }
    public static func analyze(rgba: [UInt8], width: Int, height: Int, mask: [UInt8]? = nil, eye: String? = nil,
                               species: String = "unknown", eyeSamples: [[UInt8]] = [], extremities: [CGPoint] = []) throws -> Result {
        guard width > 0, height > 0, width <= 8192, height <= 8192, rgba.count == width * height * 4,
              mask == nil || mask?.count == width * height, eye == nil || HousePetPalette(eye: eye!).isValid else { throw HousePetError.invalid }
        var samples: [Sample] = []
        let step = max(1, Int(ceil(sqrt(Double(width * height) / 16000))))
        for row in stride(from: 0, to: height, by: step) {
            for col in stride(from: 0, to: width, by: step) {
                let index = row * width + col
                guard rgba[index * 4 + 3] > 127, mask == nil || mask![index] > 127 else { continue }
                let rgb = (0..<3).map { Double(rgba[index * 4 + $0]) / 255 }
                samples.append(.init(rgb: rgb, lab: lab(rgb), x: (Double(col) + 0.5) / Double(width), y: (Double(row) + 0.5) / Double(height)))
            }
        }
        guard !samples.isEmpty else { throw HousePetError.invalid }
        let bright = samples.filter { $0.lab[0] > 66 }.sorted { $0.lab[0] > $1.lab[0] }
        let highlights = Array(bright.prefix(max(1, Int(ceil(Double(samples.count) * 0.06)))))
        var whiteBalanceApplied = false
        if Double(highlights.count) / Double(samples.count) >= 0.03,
           hypot(lab(medianRGB(highlights))[1], lab(medianRGB(highlights))[2]) <= 22 {
            whiteBalanceApplied = true
            let cast = medianRGB(highlights), target = [0.95, 0.93, 0.90]
            let gains = (0..<3).map { min(1.30, max(0.85, target[$0] / max(0.01, cast[$0]))) }
            for index in samples.indices {
                samples[index].rgb = zip(samples[index].rgb, gains).map { min(1, $0 * $1) }
                samples[index].lab = lab(samples[index].rgb)
            }
        }
        var centers = [samples[0].lab]
        var nearest = [Double](repeating: .infinity, count: samples.count)
        for _ in 1..<5 {
            let center = centers.last!
            for index in samples.indices { nearest[index] = min(nearest[index], distance(samples[index].lab, center)) }
            centers.append(samples[nearest.indices.max { nearest[$0] < nearest[$1] }!].lab)
        }
        var assignments = [Int](repeating: -1, count: samples.count)
        var groups = [[Sample]](repeating: [], count: 5)
        for _ in 0..<16 {
            var changed = false
            groups = .init(repeating: [], count: 5)
            for (index, sample) in samples.enumerated() {
                var cluster = 0, closest = Double.infinity
                for candidate in centers.indices {
                    let delta = distance(sample.lab, centers[candidate])
                    if delta < closest { closest = delta; cluster = candidate }
                }
                if assignments[index] != cluster { changed = true }
                assignments[index] = cluster; groups[cluster].append(sample)
            }
            for cluster in centers.indices where !groups[cluster].isEmpty {
                centers[cluster] = (0..<3).map { channel in groups[cluster].reduce(0) { $0 + $1.lab[channel] } / Double(groups[cluster].count) }
            }
            if !changed { break }
        }
        let whites = samples.filter(\.white), coat = samples.filter { !$0.white }
        let neutralDark = samples.filter(\.neutralDark), warm = samples.filter(\.warm)
        let mostlyNeutralDark = Double(neutralDark.count) / Double(max(1, coat.count)) > 0.5
        let clusters = groups.map { $0.filter { !$0.white } }.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        let dominant = clusters.first ?? samples
        let stripeClusters = groups.map { $0.filter { !$0.white && !(mostlyNeutralDark && $0.neutralDark) } }
            .filter { !$0.isEmpty }.sorted { $0.count > $1.count }
        let baseSample = stripeClusters.first?.first ?? dominant[0]
        let darker = stripeClusters.dropFirst().filter { cluster in
            let sample = cluster[0]
            let hueDelta = abs(atan2(sample.lab[2], sample.lab[1]) - atan2(baseSample.lab[2], baseSample.lab[1]))
            let sameHue = min(hueDelta, 2 * .pi - hueDelta) < 0.55 || (sample.chroma < 12 && baseSample.chroma < 12)
            return sameHue && sample.lab[0] < baseSample.lab[0] - 10 && Double(cluster.count) / Double(max(1, coat.count)) >= 0.10
        }
        var neighbors: [Int: Double] = [:], rough = 0, pairs = 0
        for (index, sample) in samples.enumerated() where !sample.white && !(mostlyNeutralDark && sample.neutralDark) {
            let col = Int(sample.x * Double(width)), row = Int(sample.y * Double(height))
            for neighbor in [row * width + col - step, (row - step) * width + col] {
                if let lightness = neighbors[neighbor] { pairs += 1; if abs(lightness - sample.lab[0]) > 15 { rough += 1 } }
            }
            neighbors[row * width + col] = samples[index].lab[0]
        }
        let striped = !darker.isEmpty || (pairs > 0 && Double(rough) / Double(pairs) > 0.18)
        func fraction(_ filtered: [Sample]) -> Double { Double(filtered.count) / Double(samples.count) }
        let cream = samples.filter { $0.lab[0] > 62 && $0.chroma < 28 }
        let grey = samples.filter { !$0.white && !$0.neutralDark && $0.chroma < 15 }
        let diagnostics = Diagnostics(white: fraction(whites), neutralDark: fraction(neutralDark), warm: fraction(warm),
                                      grey: fraction(grey), cream: fraction(cream), striped: striped,
                                      maskCoverage: mask.map { Double($0.filter { $0 > 127 }.count) / Double(width * height) } ?? 1,
                                      whiteBalanceApplied: whiteBalanceApplied)
        let minX = samples.map(\.x).min()!, maxX = samples.map(\.x).max()!, minY = samples.map(\.y).min()!, maxY = samples.map(\.y).max()!
        let points = samples.filter { $0.lab[0] < 45 }
        func peripheral(_ sample: Sample) -> Bool {
            if !extremities.isEmpty { return extremities.contains { hypot($0.x - sample.x, $0.y - sample.y) < 0.18 } }
            let horizontal = (sample.x - minX) / max(0.001, maxX - minX), vertical = (sample.y - minY) / max(0.001, maxY - minY)
            return horizontal < 0.22 || horizontal > 0.78 || vertical < 0.22 || vertical > 0.78
        }
        let peripheralCount = samples.filter(peripheral).count, peripheralDark = points.filter(peripheral).count
        let concentrated = Double(peripheralDark) / Double(max(1, peripheralCount)) > Double(points.count - peripheralDark) / Double(max(1, samples.count - peripheralCount)) + 0.12
        let pattern: String
        if diagnostics.white >= 0.10 && diagnostics.warm >= 0.012 && diagnostics.neutralDark >= 0.04 && diagnostics.warm < 0.5 { pattern = "calico" }
        else if diagnostics.cream >= 0.45 && fraction(points) >= 0.05 && concentrated { pattern = "colorpoint" }
        else if diagnostics.warm >= 0.35 { pattern = diagnostics.white >= 0.03 ? "tabbyWhite" : "tabby" }
        else if !striped && ((diagnostics.white >= 0.10 && diagnostics.neutralDark >= 0.20) || (diagnostics.white >= 0.05 && diagnostics.neutralDark >= 0.30) || diagnostics.white >= 0.15) { pattern = "bicolor" }
        else if diagnostics.white >= 0.15 && striped { pattern = "tabbyWhite" }
        else { pattern = striped ? "tabby" : "solid" }
        let warmCoat = diagnostics.warm >= 0.35 && pattern != "colorpoint"
        let primary = pattern == "colorpoint" ? cream : pattern == "calico" || warmCoat ? warm : pattern == "bicolor" ? coat : dominant
        var base = medianRGB(primary.isEmpty ? dominant : primary)
        if pattern == "calico" { base = boost(base, saturation: 1.5, minimum: 0.66, minimumSaturation: 0.45) }
        else if warmCoat { base = boost(base, saturation: 1.15, minimum: 0.50) }
        let warmLightness = warm.isEmpty ? 0 : median(warm.map { $0.lab[0] })
        let darkerWarm = clusters.map { $0.filter(\.warm) }.filter { !$0.isEmpty && median($0.map { $0.lab[0] }) < warmLightness - 10 }.first ?? []
        let secondary = pattern == "calico" ? neutralDark : pattern == "colorpoint" ? points : warmCoat ? darkerWarm : darker.first ?? []
        let second = pattern == "bicolor" ? base.map { $0 * 0.7 } : secondary.isEmpty ? base.map { $0 * 0.65 } : medianRGB(secondary)
        var white = whites.isEmpty ? [0.96, 0.94, 0.91] : medianRGB(whites)
        for _ in 0..<32 where lab(white)[0] < 88 { white = white.map { min(1, $0 + 0.01) } }
        let detectedEye = eyeColour(eyeSamples)
        return .init(palette: .init(base: hex(neutralizeNearBlack(base)), second: hex(neutralizeNearBlack(second)), white: hex(white),
                                   eye: eye ?? detectedEye ?? (pattern == "colorpoint" ? "#4E8FE0" : (warmCoat || pattern == "calico" ? "#D8A53C" : (!warm.isEmpty ? "#9CC43E" : "#E9C24A")))),
                     pattern: pattern, species: species, confidence: min(0.95, 0.55 + fraction(dominant) * 0.4), diagnostics: diagnostics)
    }

    public static func load(from url: URL, eye: String? = nil, recognizeSpecies: Bool = true) throws -> Result {
        try loadAnalysis(from: url, eye: eye, recognizeSpecies: recognizeSpecies).result
    }

    public static func loadAnalysis(from url: URL, eye: String? = nil, recognizeSpecies: Bool = true) throws -> Analysis {
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
        let handler = VNImageRequestHandler(cgImage: image), animals = VNRecognizeAnimalsRequest()
        try? handler.perform([animals])
        let animal = animals.results?.filter { observation in observation.labels.contains { $0.confidence > 0.3 && ["cat", "dog"].contains($0.identifier.lowercased()) } }
            .max { ($0.labels.first?.confidence ?? 0) < ($1.labels.first?.confidence ?? 0) }
        let box = animal?.boundingBox
        let species = recognizeSpecies ? animal?.labels.first?.identifier.lowercased() ?? "unknown" : "unknown"
        let foreground = HousePetForeground.selection(image: image, animalBounds: box)
        let poseRequest = VNDetectAnimalBodyPoseRequest()
        try? handler.perform([poseRequest])
        let pose = poseRequest.results?.max { left, right in
            func score(_ pose: VNAnimalBodyPoseObservation) -> Double {
                let points = pose.availableJointNames.compactMap { try? pose.recognizedPoint($0) }.filter { $0.confidence > 0.3 }
                return points.reduce(0) { $0 + (box?.contains($1.location) != false ? Double($1.confidence) : 0) }
            }
            return score(left) < score(right)
        }
        var eyes: [[UInt8]] = [], extremities: [CGPoint] = []
        if let pose {
            let joints: [VNAnimalBodyPoseObservation.JointName] = [.leftEye, .rightEye, .leftEarTop, .rightEarTop, .leftFrontPaw, .rightFrontPaw, .leftBackPaw, .rightBackPaw, .tailBottom]
            extremities = joints.compactMap { try? pose.recognizedPoint($0) }.filter { $0.confidence > 0.3 && box?.contains($0.location) != false }.map { CGPoint(x: $0.x, y: 1 - $0.y) }
            if let left = try? pose.recognizedPoint(.leftEye), let right = try? pose.recognizedPoint(.rightEye), left.confidence > 0.3, right.confidence > 0.3,
               box?.contains(left.location) != false, box?.contains(right.location) != false {
                let radius = max(2, 0.16 * hypot((left.x - right.x) * Double(width), (left.y - right.y) * Double(height)))
                for point in [left, right] {
                    let centerX = point.x * Double(width), centerY = (1 - point.y) * Double(height)
                    for row in max(0, Int(centerY - radius))...min(height - 1, Int(centerY + radius)) {
                        for col in max(0, Int(centerX - radius))...min(width - 1, Int(centerX + radius)) where hypot(Double(col) + 0.5 - centerX, Double(row) + 0.5 - centerY) <= radius {
                            let offset = (row * width + col) * 4
                            if rgba[offset + 3] > 127 { eyes.append(Array(rgba[offset..<(offset + 3)])) }
                        }
                    }
                }
            }
        }
        var result = try analyze(rgba: rgba, width: width, height: height, mask: foreground.mask, eye: eye, species: species, eyeSamples: eyes, extremities: extremities)
        result.usedVisionMask = foreground.usedVisionMask
        result.usedEyePose = eye == nil && eyeColour(eyes) != nil
        return .init(image: image, mask: foreground.mask, result: result)
    }
}

public enum HousePetForeground {
    public static func ellipse(width: Int, height: Int, animalBounds: CGRect? = nil) -> [UInt8] {
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { return [] }
        let bounds = animalBounds ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return (0..<width * height).map { index in
            let horizontal = ((Double(index % width) + 0.5) / Double(width) - bounds.midX) / max(0.001, bounds.width * 0.46)
            let vertical = (1 - (Double(index / width) + 0.5) / Double(height) - bounds.midY) / max(0.001, bounds.height * 0.49)
            return horizontal * horizontal + vertical * vertical <= 1 ? 255 : 0
        }
    }
    private static func decodeHalf(_ bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16, exponent = UInt32((bits >> 10) & 0x1F)
        var mantissa = UInt32(bits & 0x03FF)
        if exponent == 0 {
            guard mantissa != 0 else { return Float(bitPattern: sign) }
            var normalizedExponent: UInt32 = 113
            while mantissa & 0x0400 == 0 { mantissa <<= 1; normalizedExponent -= 1 }
            return Float(bitPattern: sign | (normalizedExponent << 23) | ((mantissa & 0x03FF) << 13))
        }
        if exponent == 0x1F { return Float(bitPattern: sign | 0x7F800000 | (mantissa << 13)) }
        return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
    }
    public static func decode(_ buffer: CVPixelBuffer) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly); defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer), stride = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        guard [kCVPixelFormatType_OneComponent8, kCVPixelFormatType_OneComponent32Float, kCVPixelFormatType_OneComponent16Half].contains(format) else { return nil }
        return (0..<width * height).map { index in
            let row = base.advanced(by: index / width * stride), column = index % width
            let value: Float
            if format == kCVPixelFormatType_OneComponent8 { value = Float(row.assumingMemoryBound(to: UInt8.self)[column]) / 255 }
            else if format == kCVPixelFormatType_OneComponent32Float { value = row.assumingMemoryBound(to: Float.self)[column] }
            else { value = decodeHalf(row.assumingMemoryBound(to: UInt16.self)[column]) }
            return value.isFinite ? UInt8((min(1, max(0, value)) * 255).rounded()) : 0
        }
    }
    public static func erode(_ mask: [UInt8], width: Int, height: Int) -> [UInt8] {
        guard width > 0, height > 0, mask.count == width * height else { return [] }
        let radius = max(1, Int((Double(min(width, height)) * 0.025).rounded())), stride = width + 1
        var sums = [Int](repeating: 0, count: stride * (height + 1))
        for row in 0..<height {
            for col in 0..<width {
                sums[(row + 1) * stride + col + 1] = (mask[row * width + col] > 127 ? 0 : 1) + sums[row * stride + col + 1] + sums[(row + 1) * stride + col] - sums[row * stride + col]
            }
        }
        return mask.indices.map { index in
            let col = index % width, row = index / width
            guard col >= radius, row >= radius, col + radius < width, row + radius < height else { return 0 }
            let left = col - radius, right = col + radius + 1, top = row - radius, bottom = row + radius + 1
            return sums[bottom * stride + right] - sums[top * stride + right] - sums[bottom * stride + left] + sums[top * stride + left] == 0 ? 255 : 0
        }
    }
    public static func mask(image: CGImage) -> [UInt8] { selection(image: image).mask }
    public static func selection(image: CGImage, animalBounds: CGRect? = nil) -> (mask: [UInt8], usedVisionMask: Bool) {
        let request = VNGenerateForegroundInstanceMaskRequest(), handler = VNImageRequestHandler(cgImage: image)
        var masks: [[UInt8]] = []
        if (try? handler.perform([request])) != nil, let observation = request.results?.first {
            for instance in observation.allInstances {
                guard let buffer = try? observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler),
                      CVPixelBufferGetWidth(buffer) == image.width, CVPixelBufferGetHeight(buffer) == image.height,
                      let pixels = decode(buffer) else { continue }
                masks.append(pixels)
            }
        }
        return selection(masks: masks, width: image.width, height: image.height, animalBounds: animalBounds)
    }
    static func selection(masks: [[UInt8]], width: Int, height: Int, animalBounds: CGRect? = nil) -> (mask: [UInt8], usedVisionMask: Bool) {
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { return ([], false) }
        var best: [UInt8]?, bestScore = -1.0, bestArea = 0
        for pixels in masks where pixels.count == width * height {
            var area = 0, overlap = 0
            for index in pixels.indices where pixels[index] > 127 {
                area += 1
                if animalBounds?.contains(CGPoint(x: (Double(index % width) + 0.5) / Double(width), y: 1 - (Double(index / width) + 0.5) / Double(height))) == true { overlap += 1 }
            }
            let boxArea = (animalBounds?.width ?? 0) * (animalBounds?.height ?? 0) * Double(pixels.count)
            let score = animalBounds == nil ? Double(area) : Double(overlap) / max(1, Double(area) + boxArea - Double(overlap))
            if score > bestScore || (score == bestScore && area > bestArea) { best = pixels; bestScore = score; bestArea = area }
        }
        if let best {
            let coverage = Double(best.filter { $0 > 127 }.count) / Double(best.count)
            let eroded = erode(best, width: width, height: height)
            let remaining = Double(eroded.filter { $0 > 127 }.count) / Double(best.count)
            if (0.03...0.92).contains(coverage), remaining >= 0.03 { return (eroded, true) }
        }
        return (ellipse(width: width, height: height, animalBounds: animalBounds), false)
    }
}
