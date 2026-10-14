import SwiftUI
import UserNotifications
import MijiaCore

/// macOS 通知：轮询比较状态变化（门窗打开、浸水、有人移动、上线 / 离线、开关变化），去重后发系统通知。
/// 只读状态，不控制设备；不在家时状态照常经云端读取。
@MainActor
final class Notifier: ObservableObject {
    static let shared = Notifier()
    @Published var settings = NotifySettings.load() { didSet { settings.save() } }
    @Published var authorized: Bool?
    var mock = false
    private var last: [String: NotifySnapshot] = [:]
    private var debouncer = NotifyDebouncer()
    private var loop: Task<Void, Never>?
    /// 没有打包成 .app（swift run / 截图模式）时 UNUserNotificationCenter 会崩溃
    private var canNotify: Bool { !mock && Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func snapshot(_ d: Device, _ s: DeviceState?, power: Bool?) -> NotifySnapshot {
        var n = NotifySnapshot(online: d.isOnline, powerOn: power)
        guard let s, let spec = s.spec else { return n }
        func b(_ name: String) -> Bool? { spec.prop(named: name).flatMap { s.values[$0.key]?.boolValue } }
        n.contactClosed = b("contact-state"); n.leak = b("submersion-state"); n.motion = b("motion-state")
        n.noMotionSeconds = spec.prop(named: "no-motion-duration").flatMap { s.values[$0.key]?.doubleValue }
        return n
    }

    /// 每次读到状态 / 刷新设备列表后调用
    func observe(_ d: Device, _ m: AppModel) {
        guard !mock, settings.anyOn else { return }
        let new = Self.snapshot(d, m.states[d.did], power: m.powerInfo(d)?.isOn)
        let old = last[d.did]; last[d.did] = new
        for e in NotifyRules.events(old: old, new: new) {
            guard settings.allows(d.did, e.kind) else { continue }
            // 自己刚操作过的设备不提醒开关变化
            if case .powered = e, let t = m.prefs.devices[d.did]?.lastUsed, Date().timeIntervalSince(t) < 120 { continue }
            if e == .wentOffline, !debouncer.confirmOffline(d.did, online: false) { last[d.did]?.online = true; continue }
            if e != .wentOffline { _ = debouncer.confirmOffline(d.did, online: true) }
            guard debouncer.shouldFire(d.did, e.kind) else { continue }
            post(title: m.displayName(d), body: Self.text(e), id: d.did + "|" + e.kind.rawValue)
        }
    }

    static func text(_ e: NotifyEvent) -> String {
        switch e {
        case .contactOpened: return L("门窗被打开了", "Opened")
        case .leakDetected: return L("检测到浸水！", "Water leak detected!")
        case .leakCleared: return L("浸水已恢复正常", "Leak cleared")
        case .motion: return L("检测到有人移动", "Motion detected")
        case .wentOffline: return L("设备离线了", "Went offline")
        case .cameOnline: return L("设备重新上线", "Back online")
        case .powered(let on): return on ? L("已开启", "Turned on") : L("已关闭", "Turned off")
        }
    }

    func requestPermission() {
        guard canNotify else { authorized = nil; return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { ok, _ in
            Task { @MainActor in Notifier.shared.authorized = ok }
        }
    }
    private func post(title: String, body: String, id: String) {
        guard canNotify else { return }
        let c = UNMutableNotificationContent(); c.title = title; c.body = body; c.sound = .default
        c.threadIdentifier = "mijiabar"
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id + "|" + UUID().uuidString, content: c, trigger: nil))
    }

    /// 后台轮询：传感器每分钟；开关变化时插座 / 空调每 3 分钟；上线 / 离线时每 5 分钟刷新一次设备列表
    func start(_ m: AppModel) {
        guard !mock, loop == nil else { return }
        if settings.anyOn { requestPermission() }
        loop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000); tick += 1
                guard let self, m.session != nil, self.settings.anyOn else { continue }
                let s = self.settings
                let home = m.devices.filter { m.currentHomeId == nil || $0.homeId == m.currentHomeId }
                if s.isOn(.contactOpened) || s.isOn(.leak) || s.isOn(.motion) {
                    for d in home where d.isOnline && d.category == .sensor && !s.muted.contains(d.did) {
                        await m.loadState(d); try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
                if s.isOn(.powerChange), tick % 3 == 0 {
                    for d in home where d.isOnline && (d.category == .plug || d.category == .ac || d.category == .light) && !s.muted.contains(d.did) {
                        await m.loadState(d); try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
                if s.isOn(.offline) || s.isOn(.online), tick % 5 == 0 {
                    await m.refresh(quiet: true)
                    for d in home { if let fresh = m.device(d.did) { self.observe(fresh, m) } }
                }
            }
        }
    }
}

/// 设置 → 通知（和其他设置分组同一外观）
struct NotifySettingsSection: View {
    @EnvironmentObject var m: AppModel
    @ObservedObject var n = Notifier.shared
    @State private var showDevices = false
    func binding(_ k: NotifyKind) -> Binding<Bool> {
        Binding(get: { n.settings.isOn(k) }, set: { on in n.settings.kinds[k] = on; if on { n.requestPermission() } })
    }
    var body: some View {
        SettingsGroup(title: L("通知", "Notifications")) {
            SwitchRow(title: L("门窗打开", "Door / window opened"), isOn: binding(.contactOpened))
            SwitchRow(title: L("检测到浸水", "Water leak"), isOn: binding(.leak))
            SwitchRow(title: L("有人移动", "Motion"), isOn: binding(.motion))
            SwitchRow(title: L("设备离线", "Device offline"), isOn: binding(.offline))
            SwitchRow(title: L("设备重新上线", "Device back online"), isOn: binding(.online))
            SwitchRow(title: L("插座 / 空调 / 灯开关变化", "Plug / AC / light on-off"), isOn: binding(.powerChange))
            if n.authorized == false {
                Text(L("系统设置里关闭了 MijiaBar 的通知，请在「系统设置 → 通知」中打开。", "Notifications are off for MijiaBar in System Settings → Notifications."))
                    .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(isExpanded: $showDevices) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(m.devices.filter { !m.isHidden($0) && [.sensor, .plug, .ac, .light].contains($0.category) }) { d in
                        SwitchRow(title: m.displayName(d), isOn: Binding(get: { !n.settings.muted.contains(d.did) }, set: { on in
                            if on { n.settings.muted.remove(d.did) } else { n.settings.muted.insert(d.did) }
                        }))
                    }
                }.padding(.top, 6)
            } label: { Text(L("按设备开关", "Per device")) }
            Text(L("通过定时读取状态发现变化（传感器每分钟一次），状态在两次读取之间变回去时可能错过；同一设备同类提醒 5 分钟内只发一次。门铃按下目前无法可靠获取，请用米家 App 的提醒。",
                   "Changes are found by polling (sensors every minute), so a state that flips back between reads can be missed; each device sends the same alert at most once per 5 minutes. Doorbell presses can't be detected reliably yet; use the Mi Home app for those."))
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .animation(Motion.smooth, value: showDevices)
    }
}
