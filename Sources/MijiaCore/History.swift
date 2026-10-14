import Foundation

/// 本机历史记录：每台设备每个指标一个文件 ~/Library/Application Support/MijiaBar/history/<did>/<metric>.json。
/// 只在本机，不上传。原始采样保留 31 天，按天汇总（最小 / 最大 / 平均 / 用电量）保留 400 天。
public struct Sample: Codable, Equatable, Sendable {
    public var t: Double; public var v: Double
    public init(t: Double, v: Double) { self.t = t; self.v = v }
    public var date: Date { Date(timeIntervalSince1970: t) }
}

public struct DayStat: Codable, Equatable, Sendable {
    public var min: Double, max: Double, sum: Double, n: Int
    /// 由功率（W）积分得到的用电量，单位 Wh
    public var wh: Double
    public var avg: Double { n > 0 ? sum / Double(n) : 0 }
}

public struct Series: Codable, Equatable, Sendable {
    public var samples: [Sample] = []
    /// "yyyy-MM-dd"（本地时区）→ 当天汇总
    public var daily: [String: DayStat] = [:]
    public init() {}
}

public enum History {
    public static let rawRetention: TimeInterval = 31 * 86400
    public static let dailyRetentionDays = 400
    /// 相邻两个采样间隔超过这个值时不积分（App 没运行、睡眠），避免把空档当成一直在耗电
    public static let maxGap: TimeInterval = 30 * 60

    public static func dayKey(_ d: Date, _ cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    public static func monthKey(_ day: String) -> String { String(day.prefix(7)) }

    /// 两个功率采样之间的用电量（Wh，梯形积分）
    public static func energyWh(_ a: Sample, _ b: Sample) -> Double {
        let dt = b.t - a.t
        guard dt > 0, dt <= maxGap else { return 0 }
        return (Swift.max(a.v, 0) + Swift.max(b.v, 0)) / 2 * dt / 3600
    }

    /// 记一个采样。minInterval 内的重复采样忽略；energy 为 true 时按功率积分出当天用电量。返回是否有变化
    @discardableResult
    public static func record(_ s: inout Series, _ v: Double, at date: Date, minInterval: TimeInterval = 240, energy: Bool = false,
                              cal: Calendar = .current) -> Bool {
        guard v.isFinite else { return false }
        let t = date.timeIntervalSince1970
        if let last = s.samples.last, t - last.t < minInterval { return false }
        let cur = Sample(t: t, v: v)
        let key = dayKey(date, cal)
        var day = s.daily[key] ?? DayStat(min: v, max: v, sum: 0, n: 0, wh: 0)
        day.min = Swift.min(day.min, v); day.max = Swift.max(day.max, v); day.sum += v; day.n += 1
        if energy, let last = s.samples.last { day.wh += energyWh(last, cur) }
        s.daily[key] = day
        s.samples.append(cur)
        prune(&s, now: date, cal: cal)
        return true
    }

    public static func prune(_ s: inout Series, now: Date, cal: Calendar = .current) {
        let cutoff = now.timeIntervalSince1970 - rawRetention
        if let i = s.samples.firstIndex(where: { $0.t >= cutoff }) { if i > 0 { s.samples.removeFirst(i) } } else { s.samples.removeAll() }
        let oldest = dayKey(cal.date(byAdding: .day, value: -dailyRetentionDays, to: now) ?? now, cal)
        s.daily = s.daily.filter { $0.key >= oldest }
    }

    /// 最近 days 天（含今天）每天的值；没有数据的天为 nil
    public static func lastDays(_ daily: [String: Double], days: Int, now: Date = Date(), cal: Calendar = .current) -> [(day: Date, value: Double?)] {
        let today = cal.startOfDay(for: now)
        return (0..<days).reversed().compactMap { i in
            guard let d = cal.date(byAdding: .day, value: -i, to: today) else { return nil }
            return (d, daily[dayKey(d, cal)])
        }
    }
    /// 按月合计（"yyyy-MM" → 合计），用于月度图表
    public static func monthly(_ daily: [String: Double]) -> [String: Double] {
        daily.reduce(into: [:]) { $0[monthKey($1.key), default: 0] += $1.value }
    }
}

/// 读写本机历史文件（权限 0600）
public enum HistoryStore {
    static func url(_ did: String, _ metric: String) -> URL {
        let safe = did.replacingOccurrences(of: "/", with: "_")
        let dir = Paths.support.appendingPathComponent("history/\(safe)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(metric).json")
    }
    public static func load(_ did: String, _ metric: String) -> Series {
        guard let d = try? Data(contentsOf: url(did, metric)) else { return Series() }
        return (try? JSONDecoder().decode(Series.self, from: d)) ?? Series()
    }
    public static func save(_ s: Series, _ did: String, _ metric: String) {
        let u = url(did, metric)
        guard let d = try? JSONEncoder().encode(s) else { return }
        try? d.write(to: u, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: u.path)
    }
    /// 删除全部本机历史
    public static func clearAll() { try? FileManager.default.removeItem(at: Paths.support.appendingPathComponent("history")) }
}

/// 米家云的历史接口（非公开接口，可能随时变化；失败时只用本机记录）
extension XiaomiCloud {
    /// 统计数据，如插座每天 / 每月用电量。dataType：stat_hour_v3、stat_day_v3、stat_week_v3、stat_month_v3；key 为 "siid.piid"
    public func statistics(did: String, key: String, dataType: String, from: Date, to: Date, limit: Int) async throws -> [Sample] {
        let r = try await call("/v2/user/statistics", ["did": did, "key": key, "data_type": dataType, "limit": limit,
                                                        "time_start": Int(from.timeIntervalSince1970), "time_end": Int(to.timeIntervalSince1970)])
        return Self.parseSamples(r)
    }
    /// 设备上报的属性 / 事件历史。type："prop" 或 "event"；key 为 "siid.piid"（事件为 "siid.eiid"）
    public func deviceData(did: String, key: String, type: String, from: Date, to: Date, limit: Int = 1000) async throws -> [Sample] {
        let r = try await call("/user/get_user_device_data", ["did": did, "key": key, "type": type, "limit": limit,
                                                               "time_start": Int(from.timeIntervalSince1970), "time_end": Int(to.timeIntervalSince1970)])
        return Self.parseSamples(r)
    }
    /// 兼容几种返回格式：[{time, value}]、{result: [...]}；value 可能是数字、"12.3" 或 "[12.3]"
    public static func parseSamples(_ r: Any) -> [Sample] {
        let list = (r as? [[String: Any]]) ?? ((r as? [String: Any])?["result"] as? [[String: Any]]) ?? []
        func num(_ a: Any?) -> Double? {
            if let n = a as? NSNumber { return n.doubleValue }
            guard var s = a as? String else { return nil }
            s = s.trimmingCharacters(in: CharacterSet(charactersIn: "[] \"")); if let c = s.split(separator: ",").first { s = String(c) }
            if s == "true" { return 1 }; if s == "false" { return 0 }
            return Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")))
        }
        return list.compactMap { x in
            guard let t = num(x["time"]), let v = num(x["value"]) else { return nil }
            return Sample(t: t, v: v)
        }.sorted { $0.t < $1.t }
    }
}
