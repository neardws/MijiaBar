public enum HousePetPreviewGeometry {
    public struct Bounds: Equatable, Sendable {
        public let x: Int
        public let y: Int
        public let width: Int
        public let height: Int
        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x; self.y = y; self.width = width; self.height = height
        }
    }

    public static func frameIndices(rig: HousePetRig, animated: Bool) -> [Int] {
        guard animated else { return [rig.frame(action: "sit", facing: "SE", elapsed: 0).index] }
        let direction = rig.mirror["SE"] ?? "SE"
        return Array(Set(["sit", "idle"].flatMap { action -> [Int] in
            guard let animation = rig.actions[action] ?? rig.actions["idle"] else { return [0] }
            let frames = animation.frames[direction] ?? animation.frames["SE"] ?? []
            return frames.isEmpty ? [0] : frames
        })).sorted()
    }

    public static func unionBounds(frames: [[UInt8]], width: Int, height: Int) -> Bounds? {
        guard width > 0, height > 0, width <= Int.max / height / 4 else { return nil }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for pixels in frames {
            guard pixels.count == width * height * 4 else { return nil }
            for row in 0..<height {
                for column in 0..<width where pixels[(row * width + column) * 4 + 3] > 0 {
                    minX = min(minX, column); minY = min(minY, row)
                    maxX = max(maxX, column); maxY = max(maxY, row)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let left = max(0, minX - 1), top = max(0, minY - 1)
        let right = min(width, maxX + 2), bottom = min(height, maxY + 2)
        return .init(x: left, y: top, width: right - left, height: bottom - top)
    }

    public static func displayScale(width: Int, height: Int, boxWidth: Double, boxHeight: Double, backingScale: Double = 2) -> Double {
        guard width > 0, height > 0, boxWidth.isFinite, boxHeight.isFinite, backingScale.isFinite,
              boxWidth > 0, boxHeight > 0, backingScale > 0 else { return 0 }
        let fit = min(boxWidth / Double(width), boxHeight / Double(height))
        let deviceFit = fit * backingScale
        guard deviceFit.isFinite else { return 0 }
        return deviceFit >= 1 ? deviceFit.rounded(.down) / backingScale : fit
    }
}
