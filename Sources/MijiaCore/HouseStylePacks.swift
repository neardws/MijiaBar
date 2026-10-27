import Foundation
import CryptoKit

public struct HouseStylePackIndex: Codable, Sendable {
    public let schema: Int
    public let packs: [HouseStylePack]

    public init(schema: Int, packs: [HouseStylePack]) { self.schema = schema; self.packs = packs }

    public func pack(_ id: String) -> HouseStylePack? {
        guard schema == 1 else { return nil }
        return packs.first { $0.id == id }
    }
}

public struct HouseStylePack: Codable, Equatable, Sendable {
    public let id: String
    public let version: Int
    public let url: String
    public let sha256: String
    public let size: Int64
    public let minAppVersion: String?

    public init(id: String, version: Int, url: String, sha256: String, size: Int64, minAppVersion: String? = nil) {
        self.id = id; self.version = version; self.url = url; self.sha256 = sha256; self.size = size
        self.minAppVersion = minAppVersion
    }
}

public enum HouseStylePackStatus: Equatable, Sendable {
    case bundled, installed(version: Int), available(size: Int64), downloading(progress: Double), failed(reason: String), unavailable
}

public enum HouseStylePackError: Error, Equatable, LocalizedError {
    case offline, httpStatus(Int), sizeMismatch, hashMismatch, badArchive, unsafePath, manifestMismatch, unsupportedAppVersion
    case invalidBaseURL, busy, installationFailed

    public var errorDescription: String? {
        switch self {
        case .offline: return L("网络不可用，请联网后重试。", "Offline. Connect to the internet and retry.")
        case .httpStatus(let code): return L("下载失败，HTTP 状态码：", "Download failed, HTTP status: ") + String(code)
        case .sizeMismatch: return L("风格包大小不符，请重试。", "Pack size mismatch. Please retry.")
        case .hashMismatch: return L("风格包校验失败，请重试。", "Pack hash mismatch. Please retry.")
        case .badArchive: return L("风格包格式无效。", "Invalid style pack archive.")
        case .unsafePath: return L("风格包包含不安全的路径。", "Style pack contains an unsafe path.")
        case .manifestMismatch: return L("风格包清单不匹配。", "Style pack manifest mismatch.")
        case .unsupportedAppVersion: return L("请先更新应用再安装此风格。", "Update the app before installing this style.")
        case .invalidBaseURL: return L("风格包地址必须使用 HTTPS。", "Style pack URL must use HTTPS.")
        case .busy: return L("此风格正在下载。", "This style is already downloading.")
        case .installationFailed: return L("无法安装或移除风格包。", "Could not install or remove the style pack.")
        }
    }
}

public enum HouseStylePackLocations {
    public static let defaultBaseURL = "https://files.neardws.com/mijiabar/house/styles/"
    public static var installRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MijiaBar/House/styles", isDirectory: true)
    }

    public static func baseURL(environment: [String: String] = ProcessInfo.processInfo.environment,
                               defaults: UserDefaults = .standard, allowLocalHTTP: Bool = false) throws -> URL {
        try validateBaseURL(environment["MIJIABAR_STYLE_PACK_BASE_URL"]
            ?? defaults.string(forKey: "MijiaBarStylePackBaseURL") ?? defaultBaseURL, allowLocalHTTP: allowLocalHTTP)
    }

    public static func validateBaseURL(_ string: String, allowLocalHTTP: Bool = false) throws -> URL {
        guard let url = URL(string: string), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.scheme == "https" || (allowLocalHTTP && url.scheme == "http" && ["localhost", "127.0.0.1"].contains(host))
        else { throw HouseStylePackError.invalidBaseURL }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { throw HouseStylePackError.invalidBaseURL }
        if !components.percentEncodedPath.hasSuffix("/") { components.percentEncodedPath += "/" }
        guard let base = components.url else { throw HouseStylePackError.invalidBaseURL }
        return base
    }

    public static func installedVersion(_ id: String, root: URL = installRoot) -> Int? {
        guard HouseStyles.all.contains(where: { $0.id == id && $0.kind != .builtin }) else { return nil }
        let directory = root.appendingPathComponent(id)
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let data = try? Data(contentsOf: directory.appendingPathComponent(".pack.json")),
              let receipt = try? JSONDecoder().decode(HouseStylePack.self, from: data), receipt.id == id,
              receipt.version > 0,
              let manifestData = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(HousePackManifest.self, from: manifestData),
              manifest.id == id, manifest.version == receipt.version,
              let files = try? FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("modules"), includingPropertiesForKeys: nil),
              files.contains(where: { $0.pathExtension == "png" }) else { return nil }
        return receipt.version
    }

    public static func status(_ id: String, index: HouseStylePackIndex, bundled: Bool, root: URL = installRoot) -> HouseStylePackStatus {
        if bundled || id == HouseStyles.defaultStyle { return .bundled }
        if let version = installedVersion(id, root: root) { return .installed(version: version) }
        if let pack = index.pack(id) { return .available(size: pack.size) }
        return .unavailable
    }
}

private struct HousePackManifest: Decodable {
    let id: String
    let version: Int
    let minAppVersion: String?
}

private final class HousePackDownloadDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public actor HouseStylePackInstaller {
    private let root: URL
    private let session: URLSession
    private var active: Set<String> = []

    public init(root: URL = HouseStylePackLocations.installRoot, session: URLSession? = nil) {
        self.root = root
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 90
        configuration.httpShouldSetCookies = false
        self.session = session ?? URLSession(configuration: configuration)
    }

    public func install(_ pack: HouseStylePack, baseURL: URL, appVersion: String,
                        allowLocalHTTP: Bool = false, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard HouseStyles.all.contains(where: { $0.id == pack.id && $0.kind != .builtin }), pack.version > 0,
              pack.url == "\(pack.id)/\(pack.version).zip", pack.size > 0, pack.size <= 100_000_000,
              pack.sha256.count == 64, pack.sha256.allSatisfy({ $0.isHexDigit && $0.isASCII }) else { throw HouseStylePackError.badArchive }
        let base = try HouseStylePackLocations.validateBaseURL(baseURL.absoluteString, allowLocalHTTP: allowLocalHTTP)
        try Self.checkVersion(pack.minAppVersion, appVersion)
        guard active.insert(pack.id).inserted else { throw HouseStylePackError.busy }
        defer { active.remove(pack.id) }
        let fm = FileManager.default
        let staging = root.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }
        let delegate = HousePackDownloadDelegate()
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            var request = URLRequest(url: base.appendingPathComponent(pack.url))
            request.timeoutInterval = 60
            let (bytes, response) = try await session.bytes(for: request, delegate: delegate)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw HouseStylePackError.badArchive }
            guard http.statusCode == 200 else { throw HouseStylePackError.httpStatus(http.statusCode) }
            let archive = staging.appendingPathComponent("pack.zip")
            try Data().write(to: archive)
            let file = try FileHandle(forWritingTo: archive)
            defer { try? file.close() }
            try await withTaskCancellationHandler {
                var buffer = Data(), received: Int64 = 0
                for try await byte in bytes {
                    received += 1
                    guard received <= pack.size else { throw HouseStylePackError.sizeMismatch }
                    buffer.append(byte)
                    if buffer.count == 65_536 {
                        try Task.checkCancellation()
                        try file.write(contentsOf: buffer)
                        buffer.removeAll(keepingCapacity: true)
                        progress(Double(received) / Double(pack.size))
                    }
                }
                try Task.checkCancellation()
                try file.write(contentsOf: buffer)
                progress(Double(received) / Double(pack.size))
            } onCancel: { bytes.task.cancel() }
            try file.close()
            let data = try Data(contentsOf: archive, options: .mappedIfSafe)
            guard data.count == pack.size else { throw HouseStylePackError.sizeMismatch }
            guard Self.sha256(data) == pack.sha256.lowercased() else { throw HouseStylePackError.hashMismatch }
            try HouseStylePackArchive.validate(data)
            let content = staging.appendingPathComponent("content", isDirectory: true)
            try fm.createDirectory(at: content, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", archive.path, content.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(30)
            while process.isRunning {
                if Date() > deadline || Task.isCancelled { process.terminate(); throw HouseStylePackError.badArchive }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard process.terminationStatus == 0 else { throw HouseStylePackError.badArchive }
            guard let manifestData = try? Data(contentsOf: content.appendingPathComponent("manifest.json")),
                  let manifest = try? JSONDecoder().decode(HousePackManifest.self, from: manifestData),
                  manifest.id == pack.id, manifest.version == pack.version else { throw HouseStylePackError.manifestMismatch }
            try Self.checkVersion(manifest.minAppVersion, appVersion)
            try JSONEncoder().encode(pack).write(to: content.appendingPathComponent(".pack.json"), options: .atomic)
            try Task.checkCancellation()
            let destination = root.appendingPathComponent(pack.id)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: content)
            } else {
                try fm.moveItem(at: content, to: destination)
            }
            progress(1)
        } catch let error as HouseStylePackError { throw error }
        catch let error as URLError {
            if [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .timedOut].contains(error.code) {
                throw HouseStylePackError.offline
            }
            throw HouseStylePackError.installationFailed
        } catch { throw HouseStylePackError.installationFailed }
    }

    public func remove(_ id: String) throws {
        guard HouseStyles.all.contains(where: { $0.id == id && $0.kind != .builtin }) else { throw HouseStylePackError.unsafePath }
        guard !active.contains(id) else { throw HouseStylePackError.busy }
        let directory = root.appendingPathComponent(id)
        if FileManager.default.fileExists(atPath: directory.path) {
            do { try FileManager.default.removeItem(at: directory) }
            catch { throw HouseStylePackError.installationFailed }
        }
    }

    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    private static func checkVersion(_ minimum: String?, _ current: String) throws {
        if let minimum, current.compare(minimum, options: .numeric) == .orderedAscending {
            throw HouseStylePackError.unsupportedAppVersion
        }
    }
}
