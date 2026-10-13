import SwiftUI
import AppKit
import MijiaCore

enum Page: Equatable { case list, detail(String), settings }
struct DeviceSection: Identifiable { let id: String; let title: String; let devices: [Device] }

@MainActor
final class AppModel: ObservableObject {
    @Published var session: Session?
    @Published var homes: [Home] = []
    @Published var devices: [Device] = []
    @Published var prefs: Prefs { didSet { if !mock { prefs.save() } } }
    @Published var agent: AgentPolicy { didSet { if !mock { agent.save() } } }
    @Published var states: [String: DeviceState] = [:]
    @Published var stateErrors: [String: String] = [:]
    @Published var busy: Set<String> = []
    @Published var refreshing = false
    @Published var toast: String?
    @Published var page: Page = .list
    @Published var search = ""
    @Published var showHidden = false
    @Published var qrImage: NSImage?
    @Published var loginStatus = ""
    @Published var loggingIn = false
    @Published var renaming: Device?

    let mock: Bool
    let controller = Controller(cloud: nil)
    private var loginTask: Task<Void, Never>?
    private var loading: Set<String> = []

    init(mock: Bool = false) {
        self.mock = mock
        prefs = mock ? Prefs() : Prefs.load()
        agent = mock ? AgentPolicy() : AgentPolicy.load()
        if mock { loadMock(); return }
        session = Session.load()
        if let s = session { controller.cloud = XiaomiCloud(session: s) }
        if let c = DeviceCache.load() { homes = c.homes; devices = c.devices }
        if session != nil { Task { await refresh() } }
        Task { await menuLoop() }
    }

    // MARK: 查询
    func device(_ did: String) -> Device? { devices.first { $0.did == did } }
    func displayName(_ d: Device) -> String { prefs.name(d) }
    func isFavorite(_ d: Device) -> Bool { prefs.devices[d.did]?.favorite ?? false }
    func isHidden(_ d: Device) -> Bool { prefs.isHidden(d) }

    private func matches(_ d: Device) -> Bool {
        (prefs.selectedHome == nil || d.homeId == prefs.selectedHome) &&
        (search.isEmpty || [displayName(d), d.name, d.model, d.roomName ?? ""].contains { $0.localizedCaseInsensitiveContains(search) })
    }
    var hiddenCount: Int { devices.filter { matches($0) && isHidden($0) }.count }

    var sections: [DeviceSection] {
        let list = devices.filter { matches($0) && (showHidden || !isHidden($0)) }
        var out: [DeviceSection] = []
        let favs = list.filter(isFavorite)
        if !favs.isEmpty { out.append(.init(id: "fav", title: L("收藏", "Favorites"), devices: favs)) }
        let multi = homes.count > 1 && prefs.selectedHome == nil
        let groups = Dictionary(grouping: list.filter { !isFavorite($0) }) { d -> String in
            let r = d.roomName ?? L("未分配房间", "No room")
            return multi ? "\(d.homeName) · \(r)" : r
        }
        for k in groups.keys.sorted() {
            out.append(.init(id: "room-" + k, title: k, devices: groups[k]!.sorted {
                ($0.isOnline ? 0 : 1, displayName($0)) < ($1.isOnline ? 0 : 1, displayName($1)) }))
        }
        return out
    }
    var flatVisible: [String] { sections.flatMap { $0.devices.map(\.did) } }

    func subtitle(_ d: Device) -> String {
        var parts: [String] = []
        if let r = d.roomName { parts.append(r) }
        if !d.isOnline { parts.append(L("离线", "Offline")) }
        else if let s = states[d.did] {
            if let ac = ACState.make(s) {
                parts.append(ac.power ? "\(ac.modeLabel) \(ac.target.map { "\(Int($0))°" } ?? "")" : L("已关机", "Off"))
            } else if let p = powerInfo(d) { parts.append(p.isOn ? L("已开启", "On") : L("已关闭", "Off")) }
            if let t = sensorText(s) { parts.append(t) }
        } else if stateErrors[d.did] != nil { parts.append(L("无法读取", "Unavailable")) }
        else { parts.append(d.model) }
        return parts.joined(separator: " · ")
    }

    func sensorText(_ s: DeviceState) -> String? {
        guard let spec = s.spec else { return nil }
        var out: [String] = []
        if let p = spec.prop(named: "temperature"), let v = s.values[p.key] { out.append("\(v)°C") }
        if let p = spec.prop(named: "relative-humidity"), let v = s.values[p.key] { out.append("\(v)%") }
        return out.isEmpty ? nil : out.joined(separator: " ")
    }

    func powerInfo(_ d: Device) -> (key: String, on: PropValue, off: PropValue, isOn: Bool)? {
        guard let s = states[d.did] else { return nil }
        if s.legacy { return ("power", .string("on"), .string("off"), s.values["power"] == .string("on")) }
        guard let p = s.spec?.mainOnProperty else { return nil }
        return (p.key, .bool(true), .bool(false), s.values[p.key]?.boolValue ?? false)
    }

    // 菜单栏：收藏的空调显示温度
    var menuDevice: Device? {
        if let did = prefs.menuBarDid, let d = device(did) { return d }
        return devices.first { isFavorite($0) && $0.category == .ac } ?? devices.first { $0.category == .ac && $0.isOnline }
    }
    var menuTemp: String? {
        guard let d = menuDevice, let s = states[d.did], let ac = ACState.make(s), ac.power, let t = ac.roomTemp ?? ac.target else { return nil }
        return "\(Int(t.rounded()))°"
    }
    var menuIcon: String {
        guard let d = menuDevice, let s = states[d.did], let ac = ACState.make(s), ac.power else { return "house" }
        return ac.isHeating ? "sun.max" : "snowflake"
    }
    private func menuLoop() async {
        while true {
            if let d = menuDevice, d.isOnline { await loadState(d) }
            try? await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }

    // MARK: 状态读写
    func loadStateIfNeeded(_ d: Device) {
        guard !mock, d.isOnline, states[d.did] == nil, stateErrors[d.did] == nil else { return }
        Task { await loadState(d) }
    }
    func loadState(_ d: Device) async {
        guard !mock, !loading.contains(d.did) else { return }
        loading.insert(d.did); defer { loading.remove(d.did) }
        do {
            let s = try await controller.readState(d)
            if !busy.contains(d.did) { states[d.did] = s }
            stateErrors[d.did] = nil
        } catch {
            stateErrors[d.did] = error.localizedDescription
            handleAuth(error)
        }
    }

    /// 乐观更新：先改界面，失败再回滚
    func write(_ d: Device, _ key: String, _ value: PropValue) {
        let old = states[d.did]?.values[key]
        states[d.did]?.values[key] = value
        updatePrefs(d) { $0.lastUsed = Date() }
        if mock { return }
        busy.insert(d.did)
        Task {
            do { try await controller.set(d, key: key, value: value) }
            catch {
                states[d.did]?.values[key] = old
                showToast(L("操作失败：", "Failed: ") + error.localizedDescription)
                handleAuth(error)
            }
            busy.remove(d.did)
        }
    }
    func toggle(_ d: Device) { if let p = powerInfo(d) { write(d, p.key, p.isOn ? p.off : p.on) } }
    func runAction(_ d: Device, _ a: SpecAction) {
        guard !mock else { return }
        busy.insert(d.did)
        Task {
            do { _ = try await controller.action(d, key: a.key, inputs: []); showToast(L("已执行", "Done")) }
            catch { showToast(L("操作失败：", "Failed: ") + error.localizedDescription) }
            busy.remove(d.did)
            await loadState(d)
        }
    }

    func showToast(_ s: String) {
        toast = s
        Task { try? await Task.sleep(nanoseconds: 3_000_000_000); if toast == s { toast = nil } }
    }
    func handleAuth(_ e: Error) {
        if case CloudError.authExpired = e { showToast(CloudError.authExpired.localizedDescription) }
    }

    // MARK: 管理
    func updatePrefs(_ d: Device, _ f: (inout DevicePrefs) -> Void) { var p = prefs.devices[d.did] ?? DevicePrefs(); f(&p); prefs.devices[d.did] = p }
    func toggleFavorite(_ d: Device) { withAnimation(Motion.smooth) { updatePrefs(d) { $0.favorite = !($0.favorite ?? false) } } }
    func setHidden(_ d: Device, _ h: Bool) { withAnimation(Motion.smooth) { updatePrefs(d) { $0.hidden = h } } }
    func toggleShowHidden() { withAnimation(Motion.smooth) { showHidden.toggle() } }
    func rename(_ d: Device, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        updatePrefs(d) { $0.alias = n.isEmpty || n == d.name ? nil : n }
    }
    // 点击导航带推入动画，返回比进入快；键盘导航（↩ / Esc）瞬间切换
    func open(_ d: Device, animated: Bool = true) { navigate(.detail(d.did), animated ? Motion.enter : nil) }
    func back(animated: Bool = true) { navigate(.list, animated ? Motion.exit : nil) }
    func openSettings() { navigate(.settings, Motion.enter) }
    private func navigate(_ p: Page, _ a: Animation?) {
        if let a { withAnimation(a) { page = p } } else { withoutAnimation { page = p } }
    }

    func refresh() async {
        guard !mock, let cloud = controller.cloud else { return }
        refreshing = true; defer { refreshing = false }
        do {
            let hs = try await cloud.homes(); var all: [Device] = []
            for h in hs { for d in try await cloud.devices(in: h) where !all.contains(where: { $0.did == d.did }) { all.append(d) } }
            homes = hs; devices = all
            DeviceCache(homes: hs, devices: all, updated: Date()).save()
        } catch {
            showToast(L("刷新失败：", "Refresh failed: ") + error.localizedDescription); handleAuth(error)
        }
    }

    // MARK: 登录
    func startLogin() {
        loginTask?.cancel()
        qrImage = nil; loggingIn = true; loginStatus = L("正在获取二维码…", "Fetching QR code…")
        loginTask = Task {
            do {
                let ql = QRLogin()
                let t = try await ql.start()
                qrImage = NSImage(data: try await ql.image(t))
                loginStatus = L("打开米家 App 扫一扫，并在手机上确认登录", "Scan with the Mi Home app and confirm")
                let s = try await ql.wait(t, region: prefs.region)
                s.save(); session = s; controller.cloud = XiaomiCloud(session: s)
                loggingIn = false; qrImage = nil; loginStatus = ""
                await refresh()
            } catch {
                if Task.isCancelled { return }
                loggingIn = false; loginStatus = error.localizedDescription
            }
        }
    }
    func setRegion(_ r: String) {
        prefs.region = r
        if var s = session { s.region = r; s.save(); session = s; controller.cloud = XiaomiCloud(session: s); states = [:]; Task { await refresh() } }
    }
    func logout() {
        Session.clear(); DeviceCache.clear()
        session = nil; controller.cloud = nil; devices = []; homes = []; states = [:]; stateErrors = [:]; page = .list
    }

    var cliPath: String { mock ? "/Applications/MijiaBar.app/Contents/Resources/bin/mijiabar" : Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/mijiabar").path }
    var mcpConfig: String {
        """
        {
          "mcpServers": {
            "mijia": { "command": "\(cliPath)", "args": ["mcp"] }
          }
        }
        """
    }
}
