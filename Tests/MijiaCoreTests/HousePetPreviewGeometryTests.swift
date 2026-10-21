import Testing
@testable import MijiaCore

@Suite struct HousePetPreviewGeometryTests {
    private func pixels(width: Int, height: Int, opaque: [(Int, Int, UInt8)]) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for (column, row, alpha) in opaque { pixels[(row * width + column) * 4 + 3] = alpha }
        return pixels
    }

    @Test func unionIncludesEveryFrameAndTranslucentPixels() {
        let sit = pixels(width: 12, height: 14, opaque: [(4, 3, 255), (7, 9, 255)])
        let idle = pixels(width: 12, height: 14, opaque: [(2, 5, 255), (8, 10, 1)])
        #expect(HousePetPreviewGeometry.unionBounds(frames: [sit, idle], width: 12, height: 14)
                == .init(x: 1, y: 2, width: 9, height: 10))
        #expect(HousePetPreviewGeometry.unionBounds(frames: [idle, sit], width: 12, height: 14)
                == HousePetPreviewGeometry.unionBounds(frames: [sit, idle], width: 12, height: 14))
    }

    @Test func marginClampsToImageEdges() {
        let topLeft = pixels(width: 8, height: 10, opaque: [(0, 0, 255)])
        let bottomRight = pixels(width: 8, height: 10, opaque: [(7, 9, 255)])
        #expect(HousePetPreviewGeometry.unionBounds(frames: [topLeft], width: 8, height: 10)
                == .init(x: 0, y: 0, width: 2, height: 2))
        #expect(HousePetPreviewGeometry.unionBounds(frames: [bottomRight], width: 8, height: 10)
                == .init(x: 6, y: 8, width: 2, height: 2))
        #expect(HousePetPreviewGeometry.unionBounds(frames: [topLeft, bottomRight], width: 8, height: 10)
                == .init(x: 0, y: 0, width: 8, height: 10))
    }

    @Test func transparentAndInvalidFramesHaveNoCrop() {
        let transparent = [UInt8](repeating: 0, count: 8 * 10 * 4)
        #expect(HousePetPreviewGeometry.unionBounds(frames: [transparent], width: 8, height: 10) == nil)
        #expect(HousePetPreviewGeometry.unionBounds(frames: [], width: 8, height: 10) == nil)
        #expect(HousePetPreviewGeometry.unionBounds(frames: [[255]], width: 8, height: 10) == nil)
        #expect(HousePetPreviewGeometry.unionBounds(frames: [], width: 0, height: 10) == nil)
    }

    @Test func largestIntegerDeviceScaleFits() {
        let scale = HousePetPreviewGeometry.displayScale(width: 20, height: 24, boxWidth: 52, boxHeight: 52)
        #expect(scale == 2)
        #expect(scale * 2 == 4)
        #expect(24 * (scale + 0.5) > 52)
        #expect(HousePetPreviewGeometry.displayScale(width: 20, height: 24, boxWidth: 52, boxHeight: 52, backingScale: 1) == 2)
        #expect(HousePetPreviewGeometry.displayScale(width: 20, height: 24, boxWidth: 52, boxHeight: 52, backingScale: 3) == 2)
        #expect(HousePetPreviewGeometry.displayScale(width: 20, height: 24, boxWidth: 30, boxHeight: 52) == 1.5)
        #expect(HousePetPreviewGeometry.displayScale(width: 20, height: 24, boxWidth: 10, boxHeight: 12) == 0.5)
    }

    @Test func fractionalFallbackFitsBelowOneDevicePixel() {
        let scale = HousePetPreviewGeometry.displayScale(width: 20, height: 24, boxWidth: 8, boxHeight: 6)
        #expect(scale == 0.25)
        #expect(20 * scale <= 8)
        #expect(24 * scale == 6)
    }

    @Test func invalidScaleInputsAreGraceful() {
        #expect(HousePetPreviewGeometry.displayScale(width: 0, height: 24, boxWidth: 52, boxHeight: 52) == 0)
        #expect(HousePetPreviewGeometry.displayScale(width: 20, height: 24, boxWidth: 52, boxHeight: 52, backingScale: 0) == 0)
        #expect(HousePetPreviewGeometry.displayScale(width: 20, height: 24, boxWidth: .infinity, boxHeight: 52) == 0)
    }

    @Test func bundledSitIdleCropIsSubstantiallySmaller() throws {
        let rig = try HousePetTests.rig()
        let indices = HousePetPreviewGeometry.frameIndices(rig: rig, animated: true)
        let expected = Set(try #require(rig.actions["sit"]?.frames["SE"]) + #require(rig.actions["idle"]?.frames["SE"]))
        #expect(Set(indices) == expected)
        for pattern in HousePetRig.patterns {
            let sheet = try HousePetSheet.load(from: HousePetTests.directory.appendingPathComponent(try #require(rig.sheets[pattern])))
            let frames = try HousePetRecolor.frames(sheet: sheet, rig: rig, palette: HousePet(name: "Preview", pattern: pattern).palette, phase: "day")
            let pixels = try indices.map { try HousePetSheet.decode(frames[$0]).rgba }
            let bounds = try #require(HousePetPreviewGeometry.unionBounds(frames: pixels, width: rig.frameSize[0], height: rig.frameSize[1]))
            #expect(bounds.width * bounds.height * 10 <= rig.frameSize[0] * rig.frameSize[1] * 9)
            let scale = HousePetPreviewGeometry.displayScale(width: bounds.width, height: bounds.height, boxWidth: 52, boxHeight: 52)
            let previousScale = 34.0 / Double(max(rig.frameSize[0], rig.frameSize[1]))
            #expect(scale >= previousScale * 1.25)
        }
    }

    @Test func bundledStaticCropIsSmallerAndScalesUpInPatternTile() throws {
        let rig = try HousePetTests.rig()
        let staticIndices = HousePetPreviewGeometry.frameIndices(rig: rig, animated: false)
        let animatedIndices = HousePetPreviewGeometry.frameIndices(rig: rig, animated: true)
        #expect(staticIndices == [rig.frame(action: "sit", facing: "SE", elapsed: 0).index])
        for pattern in HousePetRig.patterns {
            let sheet = try HousePetSheet.load(from: HousePetTests.directory.appendingPathComponent(try #require(rig.sheets[pattern])))
            let frames = try HousePetRecolor.frames(sheet: sheet, rig: rig, palette: HousePet(name: "Preview", pattern: pattern).palette, phase: "day")
            let staticPixels = try staticIndices.map { try HousePetSheet.decode(frames[$0]).rgba }
            let animatedPixels = try animatedIndices.map { try HousePetSheet.decode(frames[$0]).rgba }
            let staticBounds = try #require(HousePetPreviewGeometry.unionBounds(frames: staticPixels, width: rig.frameSize[0], height: rig.frameSize[1]))
            let animatedBounds = try #require(HousePetPreviewGeometry.unionBounds(frames: animatedPixels, width: rig.frameSize[0], height: rig.frameSize[1]))
            #expect(staticBounds.width < animatedBounds.width)
            #expect(staticBounds.height < animatedBounds.height)
            let scale = HousePetPreviewGeometry.displayScale(width: staticBounds.width, height: staticBounds.height,
                                                            boxWidth: 52, boxHeight: 52, backingScale: 2)
            #expect(scale >= 1.5)
            #expect(Double(staticBounds.width) * scale <= 52)
            #expect(Double(staticBounds.height) * scale <= 52)
        }
    }
}
