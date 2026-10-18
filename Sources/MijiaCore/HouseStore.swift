import Foundation

// MARK: - house.json：小屋配置（每个家庭一份覆盖项；没写的都走自动）
//
// 文件格式见 docs/HOUSE.md（schema 1）。App、命令行（mijiabar house …）和 MCP 共用这一个文件；
// 默认放在 iCloud Drive 的 MijiaBar 文件夹，多台 Mac 自动同步。
// 合并规则：每个房间 / 设备一条覆盖项，带 updatedAt，按条目「后写入的赢」；恢复自动 = 写一条字段都为空的墓碑。

public struct HouseRoomOverride: Codable, Equatable, Sendable {
    /// HouseModule 的 rawValue；"none" = 不放进小屋；nil = 自动
    public var module: String?
    public var updatedAt: Date
    public init(module: String?, updatedAt: Date = Date()) { self.module = module; self.updatedAt = updatedAt }
}

public struct HouseDeviceOverride: Codable, Equatable, Sendable {
    /// false = 小屋里不显示；true = 即使列表里隐藏也显示；nil = 跟随列表
    public var visible: Bool?
    /// "fixture:<id>" | "badge" | "badge:<id>"（指定徽章位）| "none"（只在按钮行）| nil = 自动
    public var place: String?
    public var updatedAt: Date
    public init(visible: Bool? = nil, place: String? = nil, updatedAt: Date = Date()) { self.visible = visible; self.place = place; self.updatedAt = updatedAt }
    public var isEmpty: Bool { visible == nil && place == nil }
}

public struct HomeHouse: Codable, Equatable, Sendable {
    public var rooms: [String: HouseRoomOverride] = [:]
    public var devices: [String: HouseDeviceOverride] = [:]
    /// nil = 经典四室 / 自动；非空 = 用户的格子布局（最多 3×2）
    public var layout: [HouseLayoutCell]? = nil
    public var layoutUpdatedAt: Date? = nil
    /// nil = 默认温馨木屋；见 HouseStyles
    public var style: String? = nil
    public var styleUpdatedAt: Date? = nil
    public var decorPrefs: HouseDecorPrefs? = nil
    public var decor: [String: HouseDecorEntry]? = nil
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rooms = try c.decodeIfPresent([String: HouseRoomOverride].self, forKey: .rooms) ?? [:]
        devices = try c.decodeIfPresent([String: HouseDeviceOverride].self, forKey: .devices) ?? [:]
        layout = try c.decodeIfPresent([HouseLayoutCell].self, forKey: .layout)
        layoutUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .layoutUpdatedAt)
        style = try c.decodeIfPresent(String.self, forKey: .style)
        styleUpdatedAt = try c.decodeIfPresent(Date.self, forKey: .styleUpdatedAt)
        decorPrefs = try c.decodeIfPresent(HouseDecorPrefs.self, forKey: .decorPrefs)
        decor = try c.decodeIfPresent([String: HouseDecorEntry].self, forKey: .decor)
    }
}

public struct HouseFile: Codable, Equatable, Sendable {
    public static let currentSchema = 1
    public var schema: Int = HouseFile.currentSchema
    public var homes: [String: HomeHouse] = [:]
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        homes = try c.decodeIfPresent([String: HomeHouse].self, forKey: .homes) ?? [:]
    }

    /// 按条目合并两份（例如两台 Mac 同时改了、iCloud 生成了冲突副本）：每条取 updatedAt 新的
    public static func merge(_ a: HouseFile, _ b: HouseFile) -> HouseFile {
        var out = a
        out.schema = max(a.schema, b.schema)
        for (hid, hb) in b.homes {
            var h = out.homes[hid] ?? HomeHouse()
            for (k, v) in hb.rooms where (h.rooms[k]?.updatedAt ?? .distantPast) < v.updatedAt { h.rooms[k] = v }
            for (k, v) in hb.devices where (h.devices[k]?.updatedAt ?? .distantPast) < v.updatedAt { h.devices[k] = v }
            let ta = h.layoutUpdatedAt ?? .distantPast, tb = hb.layoutUpdatedAt ?? .distantPast
            if tb > ta { h.layout = hb.layout; h.layoutUpdatedAt = hb.layoutUpdatedAt }
            let sa = h.styleUpdatedAt ?? .distantPast, sb = hb.styleUpdatedAt ?? .distantPast
            if sb > sa { h.style = hb.style; h.styleUpdatedAt = hb.styleUpdatedAt }
            for (key, entry) in hb.decor ?? [:] where (h.decor?[key]?.updatedAt ?? .distantPast) < entry.updatedAt {
                if h.decor == nil { h.decor = [:] }; h.decor?[key] = entry
            }
            if let prefs = hb.decorPrefs, prefs.updatedAt > (h.decorPrefs?.updatedAt ?? .distantPast) { h.decorPrefs = prefs }
            out.homes[hid] = h
        }
        return out
    }

    /// 删掉 30 天前的墓碑（恢复自动留下的空条目），文件不会一直变大
    public mutating func prune(now: Date = Date(), keep: TimeInterval = 30 * 86400) {
        for (hid, var h) in homes {
            h.rooms = h.rooms.filter { $0.value.module != nil || now.timeIntervalSince($0.value.updatedAt) < keep }
            h.devices = h.devices.filter { !$0.value.isEmpty || now.timeIntervalSince($0.value.updatedAt) < keep }
            h.decor = h.decor?.filter { $0.value.item != nil || now.timeIntervalSince($0.value.updatedAt) < keep }
            homes[hid] = h
        }
    }

    // MARK: 修改（App、命令行、MCP 都走这几个）

    public mutating func setDevice(home: String, did: String, now: Date = Date(), _ f: (inout HouseDeviceOverride) -> Void) {
        var h = homes[home] ?? HomeHouse()
        var o = h.devices[did] ?? HouseDeviceOverride(updatedAt: now)
        f(&o); o.updatedAt = now
        h.devices[did] = o; homes[home] = h
    }
    public mutating func setRoom(home: String, key: String, module: String?, now: Date = Date()) {
        var h = homes[home] ?? HomeHouse()
        h.rooms[key] = HouseRoomOverride(module: module, updatedAt: now); homes[home] = h
    }
    /// 恢复自动：整个家，或只一台设备 / 一个房间
    public mutating func setLayout(home: String, layout: [HouseLayoutCell]?, now: Date = Date()) {
        var h = homes[home] ?? HomeHouse()
        h.layout = layout
        h.layoutUpdatedAt = now
        homes[home] = h
    }
    public mutating func setStyle(home: String, style: String?, now: Date = Date()) {
        var h = homes[home] ?? HomeHouse()
        h.style = style
        h.styleUpdatedAt = now
        homes[home] = h
    }
    public mutating func setDecor(home: String, key: String, item: String?, now: Date = Date()) {
        var config = homes[home] ?? HomeHouse()
        if config.decor == nil { config.decor = [:] }
        config.decor?[key] = HouseDecorEntry(item: item == "auto" ? nil : item, updatedAt: now)
        homes[home] = config
    }
    public mutating func setDecorPrefs(home: String, enabled: Bool? = nil, seasonal: Bool? = nil, now: Date = Date()) {
        var config = homes[home] ?? HomeHouse(), prefs = config.decorPrefs ?? HouseDecorPrefs()
        if let enabled { prefs.enabled = enabled }; if let seasonal { prefs.seasonal = seasonal }
        prefs.updatedAt = now; config.decorPrefs = prefs; homes[home] = config
    }
    public mutating func resetDecor(home: String, now: Date = Date()) {
        for key in homes[home]?.decor?.keys.map({ $0 }) ?? [] { setDecor(home: home, key: key, item: nil, now: now) }
    }
    public mutating func reset(home: String, did: String? = nil, room: String? = nil, layout: Bool = false, style: Bool = false, now: Date = Date()) {
        var h = homes[home] ?? HomeHouse()
        if let did { h.devices[did] = HouseDeviceOverride(updatedAt: now) }
        if let room { h.rooms[room] = HouseRoomOverride(module: nil, updatedAt: now) }
        if layout { h.layout = nil; h.layoutUpdatedAt = now }
        if style { h.style = nil; h.styleUpdatedAt = now }
        if did == nil && room == nil && !layout && !style {
            for k in h.devices.keys { h.devices[k] = HouseDeviceOverride(updatedAt: now) }
            for k in h.rooms.keys { h.rooms[k] = HouseRoomOverride(module: nil, updatedAt: now) }
            h.layout = nil; h.layoutUpdatedAt = now
            h.style = nil; h.styleUpdatedAt = now
            for key in h.decor?.keys.map({ $0 }) ?? [] { h.decor?[key] = HouseDecorEntry(item: nil, updatedAt: now) }
            h.decorPrefs = HouseDecorPrefs(updatedAt: now)
        }
        homes[home] = h
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { d, enc in var c = enc.singleValueContainer(); try c.encode(HouseFile.iso.string(from: d)) }
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            if let s = try? c.decode(String.self), let v = HouseFile.iso.date(from: s) ?? HouseFile.isoPlain.date(from: s) { return v }
            if let t = try? c.decode(Double.self) { return Date(timeIntervalSince1970: t) }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "updatedAt must be an ISO 8601 date")
        }
        return d
    }()
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()
    nonisolated(unsafe) static let isoPlain = ISO8601DateFormatter()

    public func encoded() throws -> Data { try HouseFile.encoder.encode(self) }
    public static func decode(_ d: Data) throws -> HouseFile { try decoder.decode(HouseFile.self, from: d) }
}

// MARK: - 存放位置与同步

/// house.json 放在哪：iCloud Drive（默认，有 iCloud Drive 时）、本机，或用户选的文件夹（Dropbox、Syncthing、NAS…）。
/// 位置本身是每台 Mac 自己的设置，存在 Application Support/MijiaBar/house-location.json。
public struct HouseLocation: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case icloud, local, folder }
    public var mode: Mode
    public var path: String?
    public init(mode: Mode, path: String? = nil) { self.mode = mode; self.path = path }
}

public enum HouseStore {
    public static let fileName = "house.json"

    /// iCloud Drive 根目录（非沙盒 App 可以直接读写，不需要 iCloud 权限 / 描述文件）
    public static var iCloudDrive: URL? {
        let u = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: u.path, isDirectory: &dir) && dir.boolValue ? u : nil
    }

    public static var location: HouseLocation {
        if let l = loadJSON(HouseLocation.self, "house-location.json") { return l }
        return HouseLocation(mode: iCloudDrive != nil ? .icloud : .local)
    }

    /// 实际文件路径。环境变量 MIJIABAR_HOUSE_FILE 优先（测试 / 脚本用）
    public static var url: URL { url(for: location) }

    public static func url(for l: HouseLocation) -> URL {
        if let p = ProcessInfo.processInfo.environment["MIJIABAR_HOUSE_FILE"], !p.isEmpty { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        switch l.mode {
        case .icloud:
            if let d = iCloudDrive { return d.appendingPathComponent("MijiaBar").appendingPathComponent(fileName) }
            return Paths.support.appendingPathComponent(fileName)
        case .local: return Paths.support.appendingPathComponent(fileName)
        case .folder:
            let p = ((l.path ?? "") as NSString).expandingTildeInPath
            return p.isEmpty ? Paths.support.appendingPathComponent(fileName) : URL(fileURLWithPath: p).appendingPathComponent(fileName)
        }
    }

    /// 换位置：把旧位置的内容合并进新位置（不删旧文件），再记住新位置
    @discardableResult
    public static func setLocation(_ l: HouseLocation) throws -> URL {
        let old = load(at: url)
        let new = url(for: l)
        _ = try update(at: new) { $0 = HouseFile.merge($0, old) }
        saveJSON(l, "house-location.json")
        return new
    }

    public static func load() -> HouseFile { load(at: url) }

    /// 读取，并合并同目录下的冲突副本（「house 2.json」「house (conflicted copy …).json」）和 iCloud 的冲突版本
    public static func load(at url: URL) -> HouseFile {
        var out = HouseFile()
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &err) { u in
            out = readMerged(u)
        }
        return out
    }

    /// 读取 → 修改 → 原子写回，全程加文件协调锁（同一台 Mac 上 App 和命令行同时写不会互相覆盖）
    @discardableResult
    public static func update(at url: URL = HouseStore.url, _ f: (inout HouseFile) -> Void) throws -> HouseFile {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var result = HouseFile(); var failure: Error?
        var err: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: .forMerging, error: &err) { u in
            do {
                var file = readMerged(u)
                f(&file)
                file.schema = max(file.schema, HouseFile.currentSchema)
                file.prune()
                try file.encoded().write(to: u, options: .atomic)
                for c in conflictCopies(of: u) { try? FileManager.default.removeItem(at: c) }
                if let vs = NSFileVersion.unresolvedConflictVersionsOfItem(at: u) { for v in vs { v.isResolved = true }; try? NSFileVersion.removeOtherVersionsOfItem(at: u) }
                result = file
            } catch { failure = error }
        }
        if let e = err ?? failure { throw e }
        return result
    }

    static func readMerged(_ u: URL) -> HouseFile {
        var out = (try? Data(contentsOf: u)).flatMap { try? HouseFile.decode($0) } ?? HouseFile()
        for c in conflictCopies(of: u) {
            if let d = try? Data(contentsOf: c), let f = try? HouseFile.decode(d) { out = HouseFile.merge(out, f) }
        }
        for v in NSFileVersion.unresolvedConflictVersionsOfItem(at: u) ?? [] {
            if let d = try? Data(contentsOf: v.url), let f = try? HouseFile.decode(d) { out = HouseFile.merge(out, f) }
        }
        return out
    }

    static func conflictCopies(of u: URL) -> [URL] {
        let dir = u.deletingLastPathComponent(), base = u.deletingPathExtension().lastPathComponent
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { n in
            n != u.lastPathComponent && n.hasSuffix(".json") && n.hasPrefix(base + " ")
        }.sorted().map { dir.appendingPathComponent($0) }
    }
}

/// 监视 house.json 所在目录（原子写入会换掉文件本身，所以监视目录），变化后防抖回调。
/// iCloud 下载新版本、命令行改了配置、另一台 Mac 同步过来，App 都会马上刷新。
public final class HouseFileWatcher: @unchecked Sendable {
    private var source: DispatchSourceFileSystemObject?
    private var timer: DispatchSourceTimer?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "mijiabar.house.watch")
    private let onChange: @Sendable () -> Void

    public init(url: URL, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        if fd >= 0 {
            let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: queue)
            s.setEventHandler { [weak self] in self?.fire() }
            s.setCancelHandler { close(fd) }
            s.resume(); source = s
        }
        // 兜底：有些同步工具不触发目录事件
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 60, repeating: 60)
        t.setEventHandler { [weak self] in self?.onChange() }
        t.resume(); timer = t
    }

    private func fire() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = w
        queue.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    public func cancel() { source?.cancel(); timer?.cancel(); source = nil; timer = nil }
    deinit { cancel() }
}
