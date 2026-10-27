import Foundation
import Testing
@testable import MijiaCore

private final class StylePackProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable { let data: Data; let status: Int; let error: URLError.Code?; var delay: Double = 0 }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [String: Reply] = [:]
    nonisolated(unsafe) private static var requests: Set<String> = []
    static func started(_ url: URL) -> Bool { lock.lock(); defer { lock.unlock() }; return requests.contains(url.absoluteString) }
    static func register(_ reply: Reply, for url: URL) {
        lock.lock(); defer { lock.unlock() }; replies[url.absoluteString] = reply
    }
    static func unregister(_ url: URL) {
        lock.lock(); defer { lock.unlock() }; replies[url.absoluteString] = nil; requests.remove(url.absoluteString)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let reply = Self.replies[request.url!.absoluteString]
        Self.requests.insert(request.url!.absoluteString)
        Self.lock.unlock()
        guard let reply else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        if let error = reply.error { client?.urlProtocol(self, didFailWithError: URLError(error)); return }
        let deliver: @Sendable () -> Void = { [self] in
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Length": String(reply.data.count)])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.data)
            client?.urlProtocolDidFinishLoading(self)
        }
        if reply.delay > 0 { DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay, execute: deliver) }
        else { deliver() }
    }
    override func stopLoading() {}
}

@Suite struct HouseStylePacksTests {
    private func fixture(manifestID: String = "modern", symlink: Bool = false) throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("modules"), withIntermediateDirectories: true)
        try Data("{\"id\":\"\(manifestID)\",\"version\":1}".utf8).write(to: root.appendingPathComponent("manifest.json"))
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aP1kAAAAASUVORK5CYII=")!
        if symlink { try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("modules/art.png").path, withDestinationPath: "../manifest.json") }
        else { try png.write(to: root.appendingPathComponent("modules/art.png")) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-X", "-0", "-y", "fixture.zip", "manifest.json", "modules/art.png"]
        try process.run(); process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        return try Data(contentsOf: root.appendingPathComponent("fixture.zip"))
    }

    private func pack(_ data: Data, size: Int64? = nil, hash: String? = nil, minimum: String? = nil) -> HouseStylePack {
        HouseStylePack(id: "modern", version: 1, url: "modern/1.zip", sha256: hash ?? HouseStylePackInstaller.sha256(data),
                       size: size ?? Int64(data.count), minAppVersion: minimum)
    }

    private func install(_ data: Data, pack selected: HouseStylePack? = nil, status: Int = 200,
                         error: URLError.Code? = nil, check: (URL, HouseStylePackInstaller) async throws -> Void = { _, _ in }) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = URL(string: "https://style-pack.invalid/\(UUID().uuidString)/")!
        let selected = selected ?? pack(data)
        let url = base.appendingPathComponent(selected.url)
        StylePackProtocol.register(.init(data: data, status: status, error: error), for: url)
        defer { StylePackProtocol.unregister(url) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StylePackProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let installer = HouseStylePackInstaller(root: root, session: session)
        defer {
            let remaining = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
            #expect(!remaining.contains { $0.hasPrefix(".install-") })
        }
        try await installer.install(selected, baseURL: base, appVersion: "1.0")
        try await check(root, installer)
    }

    @Test func successInstallRemoveAndReceipt() async throws {
        let data = try fixture()
        try await install(data) { root, installer in
            #expect(HouseStylePackLocations.installedVersion("modern", root: root) == 1)
            let index = HouseStylePackIndex(schema: 1, packs: [pack(data)])
            #expect(HouseStylePackLocations.status("modern", index: index, bundled: false, root: root) == .installed(version: 1))
            #expect(HouseStylePackLocations.status("modern", index: index, bundled: true, root: root) == .bundled)
            try await installer.remove("modern")
            #expect(HouseStylePackLocations.status("modern", index: index, bundled: false, root: root) == .available(size: Int64(data.count)))
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("modern").path))
        }
        try await install(data) { root, _ in
            try FileManager.default.removeItem(at: root.appendingPathComponent("modern/.pack.json"))
            #expect(HouseStylePackLocations.installedVersion("modern", root: root) == nil)
        }
    }

    @Test func sizeMismatch() async throws {
        let data = try fixture()
        await #expect(throws: HouseStylePackError.sizeMismatch) { try await install(data, pack: pack(data, size: Int64(data.count + 1))) }
        await #expect(throws: HouseStylePackError.sizeMismatch) { try await install(data, pack: pack(data, size: Int64(data.count - 1))) }
    }

    @Test func hashMismatch() async throws {
        let data = try fixture()
        await #expect(throws: HouseStylePackError.hashMismatch) { try await install(data, pack: pack(data, hash: String(repeating: "0", count: 64))) }
    }

    @Test func http404() async throws {
        let data = try fixture()
        await #expect(throws: HouseStylePackError.httpStatus(404)) { try await install(data, status: 404) }
    }

    @Test func offline() async throws {
        let data = try fixture()
        await #expect(throws: HouseStylePackError.offline) { try await install(data, error: .notConnectedToInternet) }
    }

    @Test func manifestMismatch() async throws {
        let data = try fixture(manifestID: "japanese")
        await #expect(throws: HouseStylePackError.manifestMismatch) { try await install(data) }
    }

    @Test func unsupportedVersion() async throws {
        let data = try fixture()
        await #expect(throws: HouseStylePackError.unsupportedAppVersion) { try await install(data, pack: pack(data, minimum: "2.0")) }
    }

    @Test func rejectsTraversalAndSymlink() async throws {
        var data = try fixture()
        let original = Data("modules/art.png".utf8), unsafe = Data("../evilfile.png".utf8)
        #expect(original.count == unsafe.count)
        while let range = data.range(of: original) { data.replaceSubrange(range, with: unsafe) }
        await #expect(throws: HouseStylePackError.unsafePath) { try await install(data) }
        let link = try fixture(symlink: true)
        await #expect(throws: HouseStylePackError.unsafePath) { try await install(link) }
    }

    @Test func baseURLValidation() throws {
        #expect(try HouseStylePackLocations.validateBaseURL("https://example.invalid/styles").absoluteString == "https://example.invalid/styles/")
        for value in ["http://example.invalid/", "http://localhost/", "file:///tmp/", "https://user:pass@example.invalid/", "https://example.invalid/?query=1"] {
            #expect(throws: HouseStylePackError.invalidBaseURL) { try HouseStylePackLocations.validateBaseURL(value) }
        }
        for host in ["localhost", "127.0.0.1"] {
            #expect(try HouseStylePackLocations.validateBaseURL("http://\(host):8080/", allowLocalHTTP: true).scheme == "http")
        }
        #expect(throws: HouseStylePackError.invalidBaseURL) { try HouseStylePackLocations.validateBaseURL("http://example.invalid/", allowLocalHTTP: true) }
    }

    @Test func indexDecodeAndStatus() throws {
        let data = try fixture()
        let index = try JSONDecoder().decode(HouseStylePackIndex.self, from: JSONEncoder().encode(HouseStylePackIndex(schema: 1, packs: [pack(data)])))
        #expect(index.pack("modern") == pack(data))
        #expect(HouseStylePackIndex(schema: 2, packs: [pack(data)]).pack("modern") == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        #expect(HouseStylePackLocations.status("modern", index: index, bundled: false, root: root) == .available(size: Int64(data.count)))
        #expect(HouseStylePackLocations.status("cozy-wood", index: index, bundled: false, root: root) == .bundled)
        #expect(HouseStylePackLocations.status("unknown", index: index, bundled: false, root: root) == .unavailable)
    }

    @Test func concurrentInstallReplacementAndFailurePreservesExisting() async throws {
        let data = try fixture(), selected = pack(data)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let base = URL(string: "https://style-pack.invalid/\(UUID().uuidString)/")!
        let url = base.appendingPathComponent(selected.url)
        StylePackProtocol.register(.init(data: data, status: 200, error: nil, delay: 0.15), for: url)
        defer { StylePackProtocol.unregister(url) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StylePackProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let installer = HouseStylePackInstaller(root: root, session: session)
        let first = Task { try await installer.install(selected, baseURL: base, appVersion: "1.0") }
        for _ in 0..<100 where !StylePackProtocol.started(url) { try await Task.sleep(for: .milliseconds(1)) }
        #expect(StylePackProtocol.started(url))
        await #expect(throws: HouseStylePackError.busy) { try await installer.install(selected, baseURL: base, appVersion: "1.0") }
        await #expect(throws: HouseStylePackError.busy) { try await installer.remove("modern") }
        try await first.value
        let receipt = root.appendingPathComponent("modern/.pack.json")
        let previous = try Data(contentsOf: receipt)
        try Data("old".utf8).write(to: root.appendingPathComponent("modern/old.txt"))
        try await installer.install(selected, baseURL: base, appVersion: "1.0")
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("modern/old.txt").path))
        #expect(HouseStylePackLocations.installedVersion("modern", root: root) == 1)
        let bad = pack(data, hash: String(repeating: "0", count: 64))
        await #expect(throws: HouseStylePackError.hashMismatch) { try await installer.install(bad, baseURL: base, appVersion: "1.0") }
        #expect(try JSONDecoder().decode(HouseStylePack.self, from: Data(contentsOf: receipt)) == JSONDecoder().decode(HouseStylePack.self, from: previous))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == ["modern"])
    }

    @Test func rejectsMalformedAndUnexpectedEntries() async throws {
        let original = try fixture()
        await #expect(throws: HouseStylePackError.badArchive) { try await install(original.dropLast()) }
        for name in ["/absolute/a.png", "modules/art.exe", "modules/a:b.png"] {
            var data = original
            let search = Data("modules/art.png".utf8), replacement = Data(name.utf8)
            #expect(search.count == replacement.count)
            while let range = data.range(of: search) { data.replaceSubrange(range, with: replacement) }
            await #expect(throws: HouseStylePackError.unsafePath) { try await install(data) }
        }
    }

    @Test func generatedPacksMatchBakedIndexAndInstall() async throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-c", "import runpy,sys; from pathlib import Path; runpy.run_path(sys.argv[1])['build'](Path(sys.argv[2]))",
                             repository.appendingPathComponent("scripts/build-style-packs.py").path, output.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(20)
        while process.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        guard !process.isRunning else { process.terminate(); Issue.record("Pack build timed out"); return }
        #expect(process.terminationStatus == 0)
        let generated = try Data(contentsOf: output.appendingPathComponent("index.json"))
        #expect(try generated == Data(contentsOf: repository.appendingPathComponent("Sources/MijiaBarApp/Resources/House/style-packs.json")))
        let index = try JSONDecoder().decode(HouseStylePackIndex.self, from: generated)
        for entry in index.packs {
            let data = try Data(contentsOf: output.appendingPathComponent(entry.url))
            #expect(Int64(data.count) == entry.size)
            #expect(HouseStylePackInstaller.sha256(data) == entry.sha256)
            try await install(data, pack: entry) { root, _ in
                #expect(HouseStylePackLocations.installedVersion(entry.id, root: root) == entry.version)
                #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("\(entry.id)/src").path))
            }
        }
    }
}
