import SwiftUI
import Charts
import MijiaCore

/// 传感器详情页的历史：温湿度 / 光照画折线（最近 24 小时或 7 天，含最低 / 最高），门窗、水浸列出最近的状态变化。
/// 数据 = 本机记录 + 米家云的属性历史（/user/get_user_device_data，取不到时只用本机）。
struct SensorHistoryCard: View {
    enum Style { case line(unit: String), state(on: String, off: String) }
    @EnvironmentObject var m: AppModel
    @ObservedObject var rec = Recorder.shared
    let device: Device
    let metric: String
    let title: String
    let style: Style
    var tint: Color = .mint
    @State private var week = false
    @State private var cloud: [Sample] = []

    var samples: [Sample] {
        let local = rec.series(device.did, metric).samples
        guard !cloud.isEmpty else { return local }
        // 合并：同一分钟内的读数只留一个
        var seen = Set<Int>(); var out: [Sample] = []
        for s in (local + cloud).sorted(by: { $0.t < $1.t }) where seen.insert(Int(s.t / 60)).inserted { out.append(s) }
        return out
    }

    var body: some View {
        let from = Date().addingTimeInterval(week ? -7 * 86400 : -86400).timeIntervalSince1970
        let pts = samples.filter { $0.t >= from }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: "clock.arrow.circlepath").font(.system(size: 12, weight: .semibold))
                Spacer()
                if case .line = style {
                    Picker("", selection: $week) { Text(L("24 小时", "24 h")).tag(false); Text(L("7 天", "7 days")).tag(true) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize().controlSize(.small)
                }
            }
            switch style {
            case .line(let unit): lineBody(pts, unit)
            case .state(let on, let off): stateBody(samples, on, off)
            }
            Text(cloud.isEmpty ? L("本机记录（MijiaBar 运行时）", "Recorded on this Mac while MijiaBar runs")
                               : L("本机记录 + 米家云", "This Mac + Mi Home cloud"))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.tile))
        .task(id: device.did + metric) { cloud = await rec.cloudSamples(device, metric: metric, state: m.states[device.did], model: m) }
        .animation(Motion.smooth, value: week)
    }

    @ViewBuilder func lineBody(_ pts: [Sample], _ unit: String) -> some View {
        if pts.count < 2 {
            empty
        } else {
            let vs = pts.map(\.v)
            HStack(spacing: 14) {
                stat(L("最低", "Low"), vs.min()!, unit); stat(L("最高", "High"), vs.max()!, unit)
                stat(L("平均", "Avg"), vs.reduce(0, +) / Double(vs.count), unit)
            }
            Chart(pts, id: \.t) { s in
                LineMark(x: .value(L("时间", "Time"), s.date), y: .value(unit, s.v)).interpolationMethod(.monotone).foregroundStyle(tint)
                AreaMark(x: .value(L("时间", "Time"), s.date), yStart: .value(unit, vs.min()! - 1), yEnd: .value(unit, s.v))
                    .interpolationMethod(.monotone).foregroundStyle(tint.opacity(0.12))
            }
            .chartYScale(domain: (vs.min()! - 1)...(vs.max()! + 1))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { _ in AxisValueLabel(format: week ? .dateTime.weekday(.abbreviated) : .dateTime.hour()) } }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
            .frame(height: 100)
        }
    }

    @ViewBuilder func stateBody(_ all: [Sample], _ on: String, _ off: String) -> some View {
        let changes = SensorEvents.changes(all).suffix(6).reversed()
        if changes.isEmpty { empty } else {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(changes), id: \.t) { s in
                    HStack(spacing: 8) {
                        Circle().fill(s.v > 0.5 ? tint : Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
                        Text(s.v > 0.5 ? on : off).font(.system(size: 12))
                        Spacer()
                        Text(s.date, format: .relative(presentation: .named)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    var empty: some View {
        Text(L("还没有记录，MijiaBar 运行一段时间后这里会有数据。", "No history yet; it fills in while MijiaBar runs."))
            .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 50)
    }
    func stat(_ t: String, _ v: Double, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(t).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(fmt1((v * 10).rounded() / 10) + unit).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
        }
    }
}
