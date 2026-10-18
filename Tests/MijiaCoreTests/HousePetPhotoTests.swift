import Foundation
import CoreGraphics
import CoreVideo
import Testing
@testable import MijiaCore

@Suite struct HousePetPhotoTests {
    private func photo(mask: [UInt8]? = nil, pixel: (Int, Int) -> [UInt8]) throws -> HousePetPhoto.Result {
        let rgba: [UInt8] = (0..<80 * 80).flatMap { pixel($0 % 80, $0 / 80) + [UInt8(255)] }
        return try HousePetPhoto.analyze(rgba: rgba, width: 80, height: 80, mask: mask)
    }
    private func rgb(_ hex: String) -> [Int] {
        let value = UInt32(hex.dropFirst(), radix: 16)!
        return [Int((value >> 16) & 255), Int((value >> 8) & 255), Int(value & 255)]
    }
    @Test func orangeWhiteTabbyKeepsOrangeAndStripes() throws {
        let result = try photo { col, row in row > 58 ? [245, 240, 232] : col % 20 < 5 ? [130, 85, 35] : [225, 145, 55] }
        let base = rgb(result.palette.base)
        #expect(result.pattern == "tabbyWhite")
        #expect(base[0] > 200 && base[0] > base[1] + 40 && base[1] > base[2] + 35)
        #expect(rgb(result.palette.second)[0] < base[0])
        #expect(rgb(result.palette.white).allSatisfy { $0 > 220 })
    }
    @Test func tuxedoHasBlackBaseAndWhiteChest() throws {
        let result = try photo { col, _ in col < 36 ? [245, 240, 232] : [25, 24, 27] }
        #expect(result.pattern == "bicolor")
        #expect(rgb(result.palette.base).allSatisfy { $0 < 40 })
        #expect(rgb(result.palette.white).allSatisfy { $0 > 220 })
    }
    @Test func whiteCalicoKeepsBothPatches() throws {
        let result = try photo { col, _ in col < 48 ? [245, 240, 232] : col < 68 ? [225, 145, 55] : [25, 24, 27] }
        #expect(result.pattern == "calico")
        #expect(rgb(result.palette.base)[0] > 200)
        #expect(rgb(result.palette.second).allSatisfy { $0 < 40 })
    }
    @Test func plainGreyIsNotStriped() throws {
        let result = try photo { _, _ in [128, 128, 128] }
        #expect(result.pattern == "solid")
        #expect(rgb(result.palette.base) == [128, 128, 128])
    }
    @Test func highWhiteCalicoKeepsTinyPaleGingerPatch() throws {
        let result = try photo { col, row in
            let index = row * 80 + col
            return index < 128 ? [210, 180, 150] : index < 640 ? [25, 24, 27] : [245, 240, 232]
        }
        let base = rgb(result.palette.base)
        #expect(result.pattern == "calico")
        #expect(base[0] > 200 && base[0] > base[1] + 25 && base[1] > base[2] + 25)
        #expect(rgb(result.palette.second).allSatisfy { $0 < 40 })
    }
    @Test func orangeWithSixPercentWhiteNeedsNoVisibleStripes() throws {
        let result = try photo { col, row in row * 80 + col < 384 ? [245, 240, 232] : [225, 145, 55] }
        #expect(result.pattern == "tabbyWhite")
        #expect(rgb(result.palette.base)[0] > 200)
    }
    @Test func orangeWithoutWhiteIsTabbyAndSkipsChromaticHighlights() throws {
        let result = try photo { _, _ in [240, 180, 90] }
        #expect(result.pattern == "tabby")
        #expect(rgb(result.palette.base) == [240, 171, 68])
        #expect(rgb(result.palette.second) == [156, 111, 44])
    }
    @Test func tuxedoWithShadingKeepsDarkCoatMedian() throws {
        let result = try photo { col, row in
            let index = row * 80 + col
            return index < 1280 ? [245, 240, 232] : index < 4480 ? (col % 2 == 0 ? [18, 18, 20] : [65, 65, 68]) : [110, 110, 112]
        }
        let base = rgb(result.palette.base), second = rgb(result.palette.second)
        #expect(result.pattern == "bicolor")
        #expect(base.allSatisfy { $0 < 75 })
        #expect(zip(base, second).allSatisfy { abs(Double($0.1) - Double($0.0) * 0.7) <= 1 })
    }
    @Test func blackShadingDoesNotCountAsStripes() throws {
        let result = try photo { col, _ in col % 2 == 0 ? [18, 18, 20] : [65, 65, 68] }
        #expect(result.pattern == "solid")
        #expect(rgb(result.palette.base).allSatisfy { $0 < 75 })
    }
    @Test func tenPercentWhiteTuxedoIsBicolor() throws {
        let result = try photo { col, row in row * 80 + col < 640 ? [245, 240, 232] : [25, 24, 27] }
        #expect(result.pattern == "bicolor")
    }
    @Test func mostlyOrangeWithBlackAndWhiteIsNotCalico() throws {
        let result = try photo { col, row in
            let index = row * 80 + col
            return index < 640 ? [245, 240, 232] : index < 1280 ? [25, 24, 27] : [225, 145, 55]
        }
        #expect(result.pattern == "tabbyWhite")
    }
    @Test func whiteBalanceGainIsCappedAndWhiteIsLifted() throws {
        let result = try photo { col, row in row * 80 + col < 640 ? [164, 164, 164] : [100, 100, 100] }
        #expect(result.pattern == "solid")
        #expect(rgb(result.palette.base) == [130, 130, 130])
        #expect(rgb(result.palette.white).allSatisfy { $0 >= 221 })
    }
    @Test func dimWarmCoatUsesValueFloorAndDarkerFallback() throws {
        let result = try photo { _, _ in [110, 65, 30] }
        #expect(result.pattern == "tabby")
        #expect(rgb(result.palette.base) == [128, 68, 21])
        #expect(rgb(result.palette.second) == [83, 44, 14])
    }
    @Test func creamWithDarkExtremitiesIsColorpoint() throws {
        let result = try photo { col, row in
            (row < 17 && col > 23 && col < 57) || (row > 65 && (col < 20 || col > 60)) || col < 8 ? [43, 35, 32] : [232, 218, 192]
        }
        #expect(result.pattern == "colorpoint")
        #expect(result.palette.eye == "#4E8FE0")
        #expect(rgb(result.palette.base).allSatisfy { $0 > 170 })
    }
    @Test func maskExcludesDominantDarkBackground() throws {
        let mask = (0..<6400).map { index -> UInt8 in (20..<60).contains(index % 80) && (20..<60).contains(index / 80) ? 255 : 0 }
        let result = try photo(mask: mask) { col, row in (20..<60).contains(col) && (20..<60).contains(row) ? [225, 145, 55] : [9, 9, 12] }
        #expect(result.pattern == "tabby")
        #expect(rgb(result.palette.base)[0] > 200)
        #expect(!result.usedVisionMask && !result.usedEyePose)
    }
    @Test func neutralHighlightsRemoveCoolCast() throws {
        let result = try photo { col, _ in col < 20 ? [200, 215, 235] : [185, 130, 70] }
        #expect(result.pattern == "tabbyWhite")
        #expect(rgb(result.palette.base)[0] > 200)
        let white = rgb(result.palette.white)
        #expect(white[0] > white[1] && white[1] > white[2])
    }
    @Test func eyeSamplesRejectPupilsSpecularAndGrey() throws {
        let iris: [[UInt8]] = [[75, 140, 190], [75, 140, 190], [75, 140, 190], [0, 0, 0], [255, 255, 255], [140, 140, 140]]
        let detected = try #require(HousePetPhoto.eyeColour(iris))
        let eye = rgb(detected)
        #expect(eye[2] > eye[1] && eye[1] > eye[0])
        #expect(HousePetPhoto.eyeColour([[0, 0, 0], [255, 255, 255], [120, 120, 120]]) == nil)
        let result = try HousePetPhoto.analyze(rgba: [128, 128, 128, 255], width: 1, height: 1, eyeSamples: iris)
        #expect(result.palette.eye == detected)
    }
    @Test func muddyYellowEyesGainSaturationAndKeepValue() throws {
        #expect(HousePetPhoto.eyeColour([[140, 120, 95]]) == "#8C704D")
        #expect(HousePetPhoto.eyeColour([[90, 75, 45]]) == "#806226")
    }
    @Test func scaledVisionFormatsHonorStrideAndRange() throws {
        for format in [kCVPixelFormatType_OneComponent8, kCVPixelFormatType_OneComponent32Float, kCVPixelFormatType_OneComponent16Half] {
            var optional: CVPixelBuffer?
            #expect(CVPixelBufferCreate(kCFAllocatorDefault, 3, 2, format, nil, &optional) == kCVReturnSuccess)
            let buffer = try #require(optional)
            CVPixelBufferLockBaseAddress(buffer, [])
            let base = try #require(CVPixelBufferGetBaseAddress(buffer)), stride = CVPixelBufferGetBytesPerRow(buffer)
            for row in 0..<2 {
                let pointer = base.advanced(by: row * stride)
                if format == kCVPixelFormatType_OneComponent8 {
                    for (column, value) in [UInt8(0), 128, 255].enumerated() { pointer.assumingMemoryBound(to: UInt8.self)[column] = value }
                } else if format == kCVPixelFormatType_OneComponent32Float {
                    for (column, value) in [Float(-0.1), 0.5, 1.2].enumerated() { pointer.assumingMemoryBound(to: Float.self)[column] = value }
                } else {
                    for (column, value) in [Float16(0), 0.5, 1].enumerated() { pointer.assumingMemoryBound(to: UInt16.self)[column] = value.bitPattern }
                }
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            #expect(HousePetForeground.decode(buffer) == [0, 128, 255, 0, 128, 255])
        }
    }
    @Test func erosionAndAnimalEllipseDropBackgroundEdges() {
        var mask = [UInt8](repeating: 0, count: 10000)
        for row in 20..<80 { for col in 20..<80 { mask[row * 100 + col] = 255 } }
        let eroded = HousePetForeground.erode(mask, width: 100, height: 100)
        #expect(eroded[21 * 100 + 50] == 0 && eroded[50 * 100 + 50] == 255)
        let ellipse = HousePetForeground.ellipse(width: 100, height: 100, animalBounds: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5))
        #expect(ellipse[25 * 100 + 25] == 255 && ellipse[75 * 100 + 25] == 0)
    }

    @Test func animalOverlapWinsOverLargerForegroundInstance() {
        let cat = (0..<10000).map { index -> UInt8 in (5..<40).contains(index % 100) && (5..<40).contains(index / 100) ? 255 : 0 }
        let wall = (0..<10000).map { index -> UInt8 in index % 100 >= 45 ? 255 : 0 }
        let box = CGRect(x: 0.05, y: 0.6, width: 0.35, height: 0.35)
        let animal = HousePetForeground.selection(masks: [wall, cat], width: 100, height: 100, animalBounds: box)
        #expect(animal.usedVisionMask && animal.mask[20 * 100 + 20] == 255 && animal.mask[20 * 100 + 70] == 0)
        let largest = HousePetForeground.selection(masks: [cat, wall], width: 100, height: 100)
        #expect(largest.usedVisionMask && largest.mask[20 * 100 + 70] == 255 && largest.mask[20 * 100 + 20] == 0)
    }

    @Test func implausibleOrMissingMasksUseAnimalEllipse() {
        let box = CGRect(x: 0.05, y: 0.6, width: 0.35, height: 0.35)
        let fallback = HousePetForeground.ellipse(width: 100, height: 100, animalBounds: box)
        for masks in [[], [[UInt8](repeating: 255, count: 10000)], [[UInt8](repeating: 0, count: 10000)], [[255]]] {
            let selected = HousePetForeground.selection(masks: masks, width: 100, height: 100, animalBounds: box)
            #expect(!selected.usedVisionMask && selected.mask == fallback)
        }
    }
}
