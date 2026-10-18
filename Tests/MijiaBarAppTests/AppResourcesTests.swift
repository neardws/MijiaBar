import Foundation
import Testing
@testable import MijiaBarApp

@Suite struct AppResourcesTests {
    @Test func missingResourceReturnsNil() {
        #expect(AppResources.url("nonexistent-\(UUID().uuidString)", "png") == nil)
    }

    @Test func missingBundleReturnsNil() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(AppResources.findBundle(in: []) == nil)
        #expect(AppResources.findBundle(in: [directory, directory.appendingPathComponent("absent")]) == nil)
    }

    @Test func realBundleContainsHouseImages() throws {
        let bundle = try #require(AppResources.bundle)
        #expect(bundle.bundleURL.lastPathComponent == "MijiaBar_MijiaBarApp.bundle")
        #expect(AppResources.findBundle(in: [bundle.bundleURL.deletingLastPathComponent()]) != nil)
        #expect(AppResources.url("house-cutaway-day-unlit", "png", subdirectory: "House")
            ?? AppResources.url("house-cutaway-day-unlit", "png") != nil)
        #expect(AppResources.url("module-living-day-unlit", "png", subdirectory: "House/modules")
            ?? AppResources.url("module-living-day-unlit", "png", subdirectory: "modules")
            ?? AppResources.url("module-living-day-unlit", "png") != nil)
    }

    @Test func sourcesAvoidTrappingResourceAccessor() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var checked = 0
        for case let file as URL in files where file.pathExtension == "swift" {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains("Bundle.module"), "Unsafe resource accessor in \(file.path)")
            checked += 1
        }
        #expect(checked > 0)
    }
}
