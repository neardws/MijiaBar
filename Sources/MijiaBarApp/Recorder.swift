import SwiftUI
import MijiaCore

/// 本机历史记录：每次读到设备状态时记下关心的数值（功率等），并按设置的间隔在后台轮询这些设备。
/// 数据只写在本机 Application Support/MijiaBar/history，不上传；设置里可以关闭或清除。
@MainActor
final class Recorder: ObservableObject {
    static let shared = Recorder()
    static let enabledKey = "MijiaBarRecordHistory"
    static let intervalKey = "MijiaBarRecordInterval"   // 分钟
    var enabled: Bool { UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true }
    var interval: TimeInterval { Double(max(UserDefaults.standard.integer(forKey: Self.intervalKey), 5)) * 60 }

    @Published private(set) var revision = 0
    private var cache: [String: Series] = [:]
    var mock = false

    struct Metric { let name: String; let value: Double; let energy: Bool }

    /// 从状态里取出要记录的数值
    static func metrics(_ d: Device, _ s: DeviceState) -> [Metric] {
        var out: [Metric] = []
        if let w = powerWatts(d, s) { out.append(Metric(name: "power", value: w, energy: true)) }
        return out
    }
    static func powerWatts(_ d: Device, _ s: DeviceState) -> Double? {
        if let ac = ACState.make(s) { return ac.loadPower }
        guard d.category == .plug, let p = s.spec?.prop(named: "electric-power") else { return nil }
        return s.values[p.key]?.doubleValue
    }
    /// 后台轮询哪些设备：插座、空调伴侣（有功率读数的）
    static func shouldPoll(_ d: Device) -> Bool { d.isOnline && (d.category == .plug || d.category == .ac) }

    func series(_ did: String, _ metric: String) -> Series {
        let k = did + "|" + metric
        if let s = cache[k] { return s }
        let s = mock ? Series() : HistoryStore.load(did, metric); cache[k] = s; return s
    }
    func ingest(_ d: Device, _ s: DeviceState, at date: Date = Date()) {
        guard enabled, !mock else { return }
        for m in Self.metrics(d, s) {
            var ser = series(d.did, m.name)
            if History.record(&ser, m.value, at: date, energy: m.energy) {
                cache[d.did + "|" + m.name] = ser; HistoryStore.save(ser, d.did, m.name); revision += 1
            }
        }
    }
    /// 只给截图 / 演示用：塞入一段假数据
    func seed(_ did: String, _ metric: String, _ s: Series) { cache[did + "|" + metric] = s; revision += 1 }
    func clearAll() { cache.removeAll(); HistoryStore.clearAll(); cloud.removeAll(); revision += 1 }

    // MARK: 米家云统计（缓存 30 分钟；失败记为空，之后只用本机数据）
    private var cloud: [String: (at: Date, data: [String: Double]?)] = [:]
    func cloudDailyEnergy(_ d: Device, state: DeviceState?, model m: AppModel) async -> [String: Double]? {
        guard !mock, let cloudAPI = m.controller.cloud, let key = state?.spec?.prop(named: "power-consumption")?.key else { return nil }
        if let c = cloud[d.did], Date().timeIntervalSince(c.at) < 1800 { return c.data }
        var data: [String: Double]? = nil
        if let pts = try? await cloudAPI.statistics(did: d.did, key: key, dataType: "stat_day_v3",
                                                   from: Date().addingTimeInterval(-370 * 86400), to: Date(), limit: 370), !pts.isEmpty {
            var dd: [String: Double] = [:]
            for p in pts { dd[History.dayKey(p.date)] = p.v }
            // 有的设备按 Wh 上报：一天超过 100 时按 Wh 换算成 kWh
            if (dd.values.max() ?? 0) > 100 { dd = dd.mapValues { $0 / 1000 } }
            data = dd
        }
        cloud[d.did] = (Date(), data); revision += 1
        return data
    }

    // MARK: 后台轮询
    private var loop: Task<Void, Never>?
    func start(_ m: AppModel) {
        guard !mock, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                try? await Task.sleep(nanoseconds: UInt64(self.interval * 1_000_000_000))
                guard self.enabled, m.session != nil else { continue }
                for d in m.devices where Self.shouldPoll(d) && (m.currentHomeId == nil || d.homeId == m.currentHomeId) {
                    await m.loadState(d)
                    try? await Task.sleep(nanoseconds: 300_000_000)   // 错开请求
                }
            }
        }
    }
}
