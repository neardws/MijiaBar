import SwiftUI
import AppKit
import MijiaCore

enum Page: Equatable { case list, detail(String), settings }
struct Toast: Equatable { let id = UUID(); let text: String; let isError: Bool }
struct DeviceSection: Identifiable { let id: String; let key: String; let title: String; let devices: [Device] }

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
    @Published var toast: Toast?
    @Published var page: Page = .list
    @Published var search = ""
    @Published var showHidden = false
    @Published var qrImage: NSImage?
    @Published var loginStatus = ""
    @Published var loggingIn = false
    @Published var renaming: Device?
    @Published var transports: [String: Transport] = [:]
    /// 是否在家庭局域网（nil = 未知）
    @Published var atHome: Bool?
    /// 小屋配置（house.json，见 docs/HOUSE.md）；文件变了（命令行、Agent、另一台 Mac 同步过来）会自动刷新
    @Published var house = HouseFile()
    private var houseWatcher: HouseFileWatcher?
    /// HouseWindow 本次打开期间的撤销 / 重做（关窗清空）
    @Published var houseUndo = HouseUndoStack()
    @Published var houseNotice: String?

    let mock: Bool
    let controller = Controller(cloud: nil)
    private var loginTask: Task<Void, Never>?
    private var loading: Set<String> = []

    init(mock: Bool = false) {
        self.mock = mock
        prefs = mock ? Prefs() : Prefs.load()
        agent = mock ? AgentPolicy() : AgentPolicy.load()
        Notifier.shared.mock = mock
        GlanceStore.shared.mock = mock
        Recorder.shared.mock = mock
        if mock { loadMock(); return }
        session = Session.load()
        if let s = session { controller.cloud = XiaomiCloud(session: s) }
        if let c = DeviceCache.load() { homes = c.homes; devices = c.devices }
        house = HouseStore.load()
        houseWatcher = HouseFileWatcher(url: HouseStore.url) { [weak self] in
            let f = HouseStore.load()
            Task { @MainActor in
                guard let self, self.house != f else { return }
                self.house = f
                // 外部改动碰到了撤销记录里的条目：清空，避免撤销时把别人的改动改回去
                if self.houseUndo.rebase(on: f) {
                    self.houseFlash(L("house.json 在别处被改过，撤销记录已清空", "house.json changed elsewhere; undo history cleared"))
                }
            }
        }
        controller.onNetworkChange = { [weak self] in Task { @MainActor in self?.updateHome() } }
        updateHome()
        if session != nil { Task { await refresh() } }
        Task { await menuLoop() }
        Notifier.shared.start(self)
        GlanceStore.shared.start(self)
        Recorder.shared.start(self)
    }

    // MARK: 查询
    func device(_ did: String) -> Device? { devices.first { $0.did == did } }
    func displayName(_ d: Device) -> String { prefs.name(d) }
    func isFavorite(_ d: Device) -> Bool { prefs.devices[d.did]?.favorite ?? false }
    func isHidden(_ d: Device) -> Bool { prefs.isHidden(d) }

    /// 当前家庭：用户选的，否则第一个有设备的家庭
    var currentHomeId: String? {
        if let h = prefs.selectedHome, homes.contains(where: { $0.id == h }) { return h }
        return homes.first { h in devices.contains { $0.homeId == h.id } }?.id ?? homes.first?.id
    }
    var currentHomeName: String { homes.first { $0.id == currentHomeId }?.name ?? L("米家", "Mi Home") }
    private func matches(_ d: Device) -> Bool {
        (currentHomeId == nil || d.homeId == currentHomeId) &&
        (search.isEmpty || [displayName(d), d.name, d.model, d.roomName ?? ""].contains { $0.localizedCaseInsensitiveContains(search) })
    }
    var hiddenCount: Int { devices.filter { matches($0) && isHidden($0) }.count }

    var sections: [DeviceSection] {
        let list = devices.filter { matches($0) && (showHidden || !isHidden($0)) }
        let hid = currentHomeId ?? ""
        var out: [DeviceSection] = []
        let favs = prefs.orderedDevices(home: hid, key: Prefs.favoritesKey, list.filter(isFavorite))
        if !favs.isEmpty { out.append(.init(id: "fav", key: Prefs.favoritesKey, title: L("收藏", "Favorites"), devices: favs)) }
        let groups = Dictionary(grouping: list.filter { !isFavorite($0) }) { $0.roomName ?? "" }
        for k in prefs.orderedRooms(home: hid, roomKeys(groups.keys)) {
            out.append(.init(id: "room-" + k, key: k, title: roomTitle(k), devices: prefs.orderedDevices(home: hid, key: k, groups[k]!)))
        }
        return out
    }
    func roomTitle(_ k: String) -> String { k.isEmpty ? L("未分配房间", "No room") : k }
    /// 房间的默认顺序：按名称，「未分配房间」放最后（和 CLI 一致）
    func roomKeys<S: Sequence>(_ ks: S) -> [String] where S.Element == String {
        ks.sorted { ($0.isEmpty ? "~" : $0).localizedStandardCompare($1.isEmpty ? "~" : $1) == .orderedAscending }
    }

    // MARK: 排序（房间上下移动、房间内设备排序；顺序按家庭存在 prefs.json）
    @Published var editingOrder = false
    /// 当前家庭里该分区的完整设备顺序（含隐藏、被搜索过滤掉的设备）
    private func fullOrder(_ key: String) -> [String] {
        let hid = currentHomeId ?? ""
        let inHome = devices.filter { (currentHomeId == nil || $0.homeId == currentHomeId) }
        let ds = key == Prefs.favoritesKey ? inHome.filter(isFavorite) : inHome.filter { !isFavorite($0) && ($0.roomName ?? "") == key }
        return prefs.orderedDevices(home: hid, key: key, ds).map(\.did)
    }
    private func fullRoomOrder() -> [String] {
        let inHome = devices.filter { (currentHomeId == nil || $0.homeId == currentHomeId) && !isFavorite($0) }
        return prefs.orderedRooms(home: currentHomeId ?? "", roomKeys(Set(inHome.map { $0.roomName ?? "" })))
    }
    private func section(_ key: String) -> DeviceSection? { sections.first { $0.key == key } }
    func canMove(_ d: Device, in key: String, _ mv: Ordering.Move) -> Bool {
        guard let ids = section(key)?.devices.map(\.did), let i = ids.firstIndex(of: d.did) else { return false }
        return mv == .down ? i < ids.count - 1 : i > 0
    }
    func canMoveRoom(_ key: String, _ mv: Ordering.Move) -> Bool {
        let ks = sections.filter { $0.id != "fav" }.map(\.key)
        guard let i = ks.firstIndex(of: key) else { return false }
        return mv == .down ? i < ks.count - 1 : i > 0
    }
    private func applyDevices(_ key: String, _ visible: [String]) {
        let full = Ordering.mergeVisible(full: fullOrder(key), visible: visible)
        withAnimation(Motion.smooth) { prefs.setOrder(home: currentHomeId ?? "", key: key, full) }
    }
    private func applyRooms(_ visible: [String]) {
        let full = Ordering.mergeVisible(full: fullRoomOrder(), visible: visible)
        withAnimation(Motion.smooth) { prefs.setOrder(home: currentHomeId ?? "", key: nil, full) }
    }
    func move(_ d: Device, in key: String, _ mv: Ordering.Move) {
        guard let ids = section(key)?.devices.map(\.did) else { return }
        applyDevices(key, Ordering.moved(ids, d.did, mv))
    }
    func drop(_ did: String, onto target: Device, in key: String) {
        guard let ids = section(key)?.devices.map(\.did), ids.contains(did) else { return }
        applyDevices(key, Ordering.dropped(ids, did, onto: target.did))
    }
    func moveRoom(_ key: String, _ mv: Ordering.Move) {
        applyRooms(Ordering.moved(sections.filter { $0.id != "fav" }.map(\.key), key, mv))
    }
    func dropRoom(_ key: String, onto target: String) {
        applyRooms(Ordering.dropped(sections.filter { $0.id != "fav" }.map(\.key), key, onto: target))
    }
    /// 恢复当前家庭的默认顺序
    func resetOrder() { withAnimation(Motion.smooth) { prefs.order?[currentHomeId ?? ""] = nil } }
    var hasCustomOrder: Bool { prefs.order?[currentHomeId ?? ""] != nil }

    struct Summary { var on = 0; var offline = 0; var acs: [(String, Int, Bool)] = []; var env: String? }
    var summary: Summary {
        var s = Summary()
        for d in devices where d.homeId == currentHomeId {
            if !d.isOnline { s.offline += 1; continue }
            guard let st = states[d.did] else { continue }
            if let ac = ACState.make(st) {
                if ac.power { s.on += 1; if s.acs.count < 2, let t = ac.target { s.acs.append((displayName(d), Int(t), ac.isHeating)) } }
            } else if powerInfo(d)?.isOn == true { s.on += 1 }
            if s.env == nil, d.category == .sensor, let t = sensorText(st) { s.env = t }
        }
        return s
    }
    /// 收藏的空调以迷你卡片显示
    var favoriteACs: [Device] { sections.first { $0.id == "fav" }?.devices.filter { $0.category == .ac } ?? [] }
    var flatVisible: [String] { sections.flatMap { $0.devices.map(\.did) } }

    func subtitle(_ d: Device) -> String {
        var parts: [String] = []
        if !d.isOnline { return d.roomName ?? "" }
        else if let s = states[d.did] {
            if let ac = ACState.make(s) {
                parts.append(ac.power ? "\(ac.modeLabel) \(ac.target.map { "\(Int($0))°" } ?? "")" : L("已关机", "Off"))
            } else if let p = powerInfo(d) { parts.append(p.isOn ? L("已开启", "On") : L("已关闭", "Off")) }
            if let t = sensorText(s) { parts.append(t) }
        } else if stateErrors[d.did] != nil { parts.append(L("无法读取", "Unavailable")) }
        else if !d.isOnline { } else { parts.append(L("读取中…", "Loading…")) }
        return parts.isEmpty ? (states[d.did] != nil ? L("在线", "Online") : "") : parts.joined(separator: " · ")
    }

    func sensorText(_ s: DeviceState) -> String? {
        guard let spec = s.spec else { return nil }
        var out: [String] = []
        if let p = spec.prop(named: "temperature"), let v = s.values[p.key] { out.append("\(v)°C") }
        if let p = spec.prop(named: "relative-humidity"), let v = s.values[p.key] { out.append("\(v)%") }
        // 门窗：true 表示贴合（关着）；水浸：true 表示检测到水
        if let p = spec.prop(named: "contact-state"), let v = s.values[p.key]?.boolValue { out.append(v ? L("已关闭", "Closed") : L("已打开", "Open")) }
        if let p = spec.prop(named: "submersion-state"), let v = s.values[p.key]?.boolValue { out.append(v ? L("检测到浸水", "Water detected") : L("无浸水", "No water")) }
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
            Notifier.shared.observe(d, self)
            Recorder.shared.ingest(d, s)
            if let t = Transport.from(s.source, device: d) { transports[d.did] = t }
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
            do { if let t = Transport.from(try await controller.set(d, key: key, value: value), device: d) { transports[d.did] = t } }
            catch {
                states[d.did]?.values[key] = old
                showToast(L("操作失败：", "Failed: ") + error.localizedDescription, error: true)
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
            catch { showToast(L("操作失败：", "Failed: ") + error.localizedDescription, error: true) }
            busy.remove(d.did)
            await loadState(d)
        }
    }

    /// 错误停留更久，并通过 VoiceOver 播报；成功提示只显示，不打断朗读
    func showToast(_ s: String, error: Bool = false) {
        let t = Toast(text: s, isError: error)
        toast = t
        if error { AccessibilityNotification.Announcement(s).post() }
        Task { try? await Task.sleep(nanoseconds: error ? 5_000_000_000 : 3_000_000_000); if toast == t { toast = nil } }
    }
    func handleAuth(_ e: Error) {
        if case CloudError.authExpired = e { showToast(CloudError.authExpired.localizedDescription, error: true) }
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

    func refresh(quiet: Bool = false) async {
        guard !mock, let cloud = controller.cloud else { return }
        if !quiet { refreshing = true }; defer { if !quiet { refreshing = false } }
        do {
            let hs = try await cloud.homes(); var all: [Device] = []
            for h in hs { for d in try await cloud.devices(in: h) where !all.contains(where: { $0.did == d.did }) { all.append(d) } }
            homes = hs; devices = all; updateHome()
            DeviceCache(homes: hs, devices: all, updated: Date()).save()
        } catch {
            if !quiet { showToast(L("刷新失败：", "Refresh failed: ") + error.localizedDescription, error: true) }; handleAuth(error)
        }
    }

    func updateHome() {
        controller.setDeviceIPs(devices.filter { $0.isOnline }.compactMap(\.ip))
        atHome = controller.atHome
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
    @Published var lang: AppLang = currentLang
    /// 用户是否手动选过语言；没选过时切换地区会跟随地区默认语言
    var langManual: Bool { UserDefaults.standard.bool(forKey: "MijiaBarLangManual") }
    func setLang(_ l: AppLang, manual: Bool = true) {
        currentLang = l; lang = l
        UserDefaults.standard.set(l.rawValue, forKey: "MijiaBarLang")
        if manual { UserDefaults.standard.set(true, forKey: "MijiaBarLangManual") }
    }
    /// 完全退出：结束 App 本身（MCP 服务由 Agent 客户端各自启动的 CLI 进程提供，App 不常驻任何后台子进程）
    func quitApp() { NSApp.terminate(nil) }
    func setRegion(_ r: String) {
        prefs.region = r
        if !langManual, let d = AppLang.suggested(forRegion: r).first { setLang(d, manual: false) }
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
