import SwiftUI
import MijiaCore

/// 菜单栏速览：读取、格式化，并定时刷新被选中的设备
@MainActor
final class GlanceStore: ObservableObject {
    static let shared = GlanceStore()
    @Published var items: [GlanceItem] = Glance.load() { didSet { Glance.save(items) } }
    var mock = false
    private var loop: Task<Void, Never>?

    func add(_ i: GlanceItem) { guard items.count < Glance.maxItems, !items.contains(i) else { return }; items.append(i) }
    func remove(_ i: GlanceItem) { items.removeAll { $0 == i } }

    /// 每 2 分钟刷新一次被选中的设备（菜单打开时列表本身也会读状态）
    func start(_ m: AppModel) {
        guard !mock, loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if m.session != nil {
                    for did in Set(self.items.map(\.did)) { if let d = m.device(did), d.isOnline { await m.loadState(d) } }
                }
                try? await Task.sleep(nanoseconds: 120_000_000_000)
            }
        }
    }
}

extension GlanceKind {
    var title: String {
        switch self {
        case .temperature: return L("温度", "Temperature")
        case .humidity: return L("湿度", "Humidity")
        case .pm25: return "PM2.5"
        case .acTarget: return L("空调设定温度", "AC target")
        case .power: return L("功率", "Power")
        }
    }
}

extension AppModel {
    /// 设备的某个速览数值；没有读数时为 nil
    func glanceValue(_ i: GlanceItem) -> Double? {
        guard let d = device(i.did), d.isOnline, let s = states[d.did] else { return nil }
        if let ac = ACState.make(s) {
            switch i.kind {
            case .acTarget: return ac.power ? ac.target : nil
            case .temperature: return ac.roomTemp
            case .power: return ac.loadPower
            default: break
            }
        }
        let name: String
        switch i.kind {
        case .temperature: name = "temperature"
        case .humidity: name = "relative-humidity"
        case .pm25: name = "pm2.5-density"
        case .power: name = "electric-power"
        case .acTarget: name = "target-temperature"
        }
        guard let p = s.spec?.prop(named: name) else { return nil }
        return s.values[p.key]?.doubleValue
    }
    /// 这台设备能选哪些速览：有状态时按规格判断，没有时按设备类型猜
    func glanceKinds(_ d: Device) -> [GlanceKind] {
        if let s = states[d.did] {
            if let ac = ACState.make(s) { return [.acTarget] + (ac.roomTemp != nil ? [.temperature] : []) + (ac.loadPower != nil ? [.power] : []) }
            guard let spec = s.spec else { return [] }
            let map: [(String, GlanceKind)] = [("temperature", .temperature), ("relative-humidity", .humidity), ("pm2.5-density", .pm25),
                                               ("target-temperature", .acTarget), ("electric-power", .power)]
            return map.filter { spec.prop(named: $0.0) != nil }.map(\.1)
        }
        switch d.category {
        case .ac: return [.acTarget, .temperature]
        case .sensor: return [.temperature, .humidity]
        case .purifier: return [.pm25]
        case .plug: return [.power]
        default: return []
        }
    }
    /// 菜单栏上显示的文字；没有选任何速览时为 nil（沿用原来的空调温度）
    var glanceText: String? {
        let items = GlanceStore.shared.items
        guard !items.isEmpty else { return nil }
        let parts = items.map { i in glanceValue(i).map { Glance.text(i.kind, $0) } ?? "–" }
        return parts.joined(separator: " ")
    }
}

/// 设置 → 菜单栏速览
struct GlanceSettingsSection: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject var store = GlanceStore.shared
    var body: some View {
        SettingsGroup(title: L("菜单栏速览", "Menu bar glance")) {
            if store.items.isEmpty {
                Text(L("还没有选择。默认显示收藏空调的温度。", "Nothing selected. The favorite AC's temperature is shown by default."))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(store.items, id: \.self) { i in
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(m.device(i.did).map(m.displayName) ?? i.did).lineLimit(1)
                        Text(i.kind.title).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(m.glanceValue(i).map { Glance.text(i.kind, $0) } ?? "–").monospacedDigit().foregroundStyle(.secondary)
                    Button { withAnimation(Motion.smooth) { store.remove(i) } } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.pressable(0.9)).foregroundStyle(.secondary).help(L("移除", "Remove")).accessibilityLabel(L("移除", "Remove"))
                }
                .transition(.pop(0.98, anchor: .top))
            }
            Menu {
                ForEach(m.devices.filter { !m.isHidden($0) && !m.glanceKinds($0).isEmpty }) { d in
                    Menu(m.displayName(d)) {
                        ForEach(m.glanceKinds(d), id: \.self) { k in
                            let item = GlanceItem(did: d.did, kind: k)
                            Button(k.title) { withAnimation(Motion.smooth) { store.add(item) } }.disabled(store.items.contains(item))
                        }
                    }
                }
            } label: {
                Label(LF("添加（最多 %@ 个）", "Add (up to %@)", "\(Glance.maxItems)"), systemImage: "plus")
            }
            .menuStyle(.borderlessButton).fixedSize().disabled(store.items.count >= Glance.maxItems)
            Text(L("例如：26° 58% PM35 36W。每 2 分钟刷新一次所选设备。", "e.g. 26° 58% PM35 36W. Selected devices refresh every 2 minutes."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .animation(Motion.smooth, value: store.items)
    }
}
