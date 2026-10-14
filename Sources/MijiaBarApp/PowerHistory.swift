import SwiftUI
import Charts
import MijiaCore

/// 插座 / 空调伴侣详情页里的用电统计：按天（最近 14 天）或按月（最近 12 个月）的柱状图和 kWh 估算
struct PowerHistoryCard: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject var rec = Recorder.shared
    let device: Device
    var tint: Color = .green
    @State private var monthly = false
    @State private var cloudDaily: [String: Double]?

    var localDaily: [String: Double] { rec.series(device.did, "power").daily.mapValues { $0.wh / 1000 } }
    var daily: [String: Double] { cloudDaily ?? localDaily }

    var body: some View {
        let d = daily
        let today = d[History.dayKey(Date())] ?? 0
        let thisMonth = History.monthly(d)[String(History.dayKey(Date()).prefix(7))] ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(L("用电统计", "Energy"), systemImage: "chart.bar.xaxis").font(.system(size: 12, weight: .semibold))
                Spacer()
                Picker("", selection: $monthly) {
                    Text(L("按天", "Daily")).tag(false); Text(L("按月", "Monthly")).tag(true)
                }.pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
            }
            HStack(spacing: 14) {
                stat(L("今天", "Today"), today)
                stat(L("本月", "This month"), thisMonth)
            }
            if d.isEmpty {
                Text(L("还没有记录。MijiaBar 运行时会定时记下功率，几小时后这里就有数据。", "No data yet. MijiaBar records power while it runs; check back in a few hours."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 80)
            } else {
                chart(d).frame(height: 110)
            }
            Text(cloudDaily != nil ? L("数据来自米家云", "From Mi Home cloud")
                                   : L("估算：由本机定时记录的功率计算，Mac 睡眠或 App 未运行时不计入", "Estimate from power readings recorded on this Mac; time while asleep or not running isn't counted"))
                .font(.system(size: 10)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.tile))
        .task(id: device.did) { cloudDaily = await rec.cloudDailyEnergy(device, state: m.states[device.did], model: m) }
        .animation(Motion.smooth, value: monthly)
    }

    func stat(_ title: String, _ kwh: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(kwhText(kwh)).font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }

    @ViewBuilder func chart(_ d: [String: Double]) -> some View {
        if monthly {
            let months = History.monthly(d).sorted { $0.key < $1.key }.suffix(12)
            Chart(Array(months), id: \.key) { e in
                BarMark(x: .value(L("月", "Month"), String(e.key.suffix(2))), y: .value("kWh", e.value)).foregroundStyle(tint.gradient).cornerRadius(3)
            }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
        } else {
            let days = History.lastDays(d, days: 14)
            Chart(days, id: \.day) { e in
                BarMark(x: .value(L("日期", "Day"), e.day, unit: .day), y: .value("kWh", e.value ?? 0)).foregroundStyle(tint.gradient).cornerRadius(3)
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 3)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
        }
    }
}

func kwhText(_ v: Double) -> String { (v < 10 ? String(format: "%.2f", v) : String(format: "%.1f", v)) + " kWh" }

/// 设置 → 历史记录
struct HistorySettingsSection: View {
    @EnvironmentObject var m: AppModel
    @AppStorage(Recorder.enabledKey) private var enabled = true
    @AppStorage(Recorder.intervalKey) private var interval = 5
    @State private var confirmClear = false
    var body: some View {
        SettingsGroup(title: L("历史记录", "History")) {
            SwitchRow(title: L("在本机记录功率等读数", "Record readings on this Mac"), isOn: $enabled)
            HStack {
                Text(L("记录间隔", "Interval")); Spacer()
                Picker("", selection: $interval) {
                    ForEach([5, 10, 15, 30], id: \.self) { Text(LF("%@ 分钟", "%@ min", "\($0)")).tag($0) }
                }.labelsHidden().fixedSize().disabled(!enabled)
            }
            Text(L("只保存在本机（~/Library/Application Support/MijiaBar/history），原始读数保留 31 天、每日汇总保留 400 天。间隔越短，用电估算越准，但请求更多。",
                   "Stored only on this Mac (~/Library/Application Support/MijiaBar/history): raw readings for 31 days, daily totals for 400 days. Shorter intervals give better estimates but make more requests."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ActionRow(title: L("清除历史记录…", "Clear history…"), icon: "trash", destructive: true) { confirmClear = true }
                .confirmationDialog(L("清除所有本机历史记录？", "Clear all local history?"), isPresented: $confirmClear) {
                    Button(L("清除", "Clear"), role: .destructive) { Recorder.shared.clearAll(); m.showToast(L("已清除历史记录", "History cleared")) }
                }
        }
    }
}
