import SwiftUI
import AppKit
import MijiaCore

struct RootView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                if m.session == nil { LoginView() }
                else {
                    switch m.page {
                    case .list: DeviceListView()
                    case .detail(let did): if let d = m.device(did) { DetailView(device: d).id(did) } else { DeviceListView() }
                    case .settings: SettingsView()
                    }
                }
            }
            if let d = m.renaming { RenameOverlay(device: d, text: m.displayName(d)) }
        }
        .overlay(alignment: .bottom) {
            if let t = m.toast {
                Text(t).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.85))).overlay(Capsule().stroke(Theme.stroke))
                    .padding(.bottom, 14).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: m.toast)
        .frame(width: 360, height: 600)
        .preferredColorScheme(.dark)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "house.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.sliderGradient)
            Text(L("登录小米账号", "Sign in to Xiaomi")).font(.system(size: 20, weight: .semibold))
            Text(L("用米家 App 扫码，无需输入密码", "Scan with the Mi Home app — no password needed")).font(.system(size: 12)).foregroundStyle(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Color.white).frame(width: 224, height: 224)
                if let img = m.qrImage {
                    Image(nsImage: img).resizable().interpolation(.none).frame(width: 200, height: 200)
                } else if m.loggingIn {
                    ProgressView().controlSize(.large).colorScheme(.light)
                } else {
                    Button(L("获取二维码", "Get QR code")) { m.startLogin() }.colorScheme(.light)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            Text(m.loginStatus).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(height: 32)
            HStack {
                Text(L("地区", "Region")).font(.system(size: 12)).foregroundStyle(.secondary)
                Picker("", selection: Binding(get: { m.prefs.region }, set: { m.setRegion($0) })) {
                    ForEach(xiaomiRegions, id: \.id) { Text($0.name).tag($0.id) }
                }.labelsHidden().frame(width: 140)
            }
            HStack(spacing: 12) {
                Button { m.startLogin() } label: { Label(L("刷新二维码", "Refresh"), systemImage: "arrow.clockwise") }
                Button { NSApp.terminate(nil) } label: { Label(L("退出", "Quit"), systemImage: "xmark.circle") }
            }.buttonStyle(.borderless).font(.system(size: 12))
            Spacer()
        }
        .padding(20)
        .onAppear { if !m.mock, m.qrImage == nil, !m.loggingIn { m.startLogin() } }
    }
}

// MARK: - 设备列表

struct DeviceListView: View {
    @EnvironmentObject var m: AppModel
    @FocusState private var searchFocused: Bool
    @State private var cursor = 0

    var body: some View {
        let flat = m.flatVisible
        VStack(spacing: 10) {
            header
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("搜索设备、房间、型号", "Search devices, rooms, models"), text: $m.search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { searchFocused = false; cursor = 0 }
                if !m.search.isEmpty { Button { m.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
            }
            .font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))

            if m.devices.isEmpty {
                Spacer()
                if m.refreshing { ProgressView(L("正在获取设备列表…", "Loading devices…")) }
                else { Text(L("还没有设备", "No devices")).foregroundStyle(.secondary) }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(m.sections) { sec in
                                Text(sec.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6).padding(.leading, 4)
                                ForEach(sec.devices) { d in
                                    DeviceRow(device: d, focused: flat.indices.contains(cursor) && flat[cursor] == d.did)
                                        .id(d.did)
                                        .onTapGesture { m.open(d) }
                                }
                            }
                            footer
                        }
                    }
                    .scrollIndicators(.never)
                    .onChange(of: cursor) { _, c in if flat.indices.contains(c) { withAnimation { proxy.scrollTo(flat[c], anchor: .center) } } }
                }
            }
        }
        .padding(12)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { cursor = min(cursor + 1, max(flat.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { cursor = max(cursor - 1, 0); return .handled }
        .onKeyPress(.return) { if flat.indices.contains(cursor), let d = m.device(flat[cursor]) { m.open(d) }; return .handled }
        .onKeyPress(.space) { if !searchFocused, flat.indices.contains(cursor), let d = m.device(flat[cursor]) { m.toggle(d); return .handled }; return .ignored }
        .onKeyPress(KeyEquivalent("/")) { searchFocused = true; return .handled }
    }

    var header: some View {
        HStack(spacing: 8) {
            Menu {
                Button(L("全部家庭", "All homes")) { m.prefs.selectedHome = nil }
                ForEach(m.homes) { h in Button(h.name) { m.prefs.selectedHome = h.id } }
            } label: {
                HStack(spacing: 4) {
                    Text(m.homes.first { $0.id == m.prefs.selectedHome }?.name ?? L("米家", "Mi Home")).font(.system(size: 17, weight: .bold))
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Spacer()
            if m.refreshing { ProgressView().controlSize(.small) }
            IconButton(icon: "arrow.clockwise", help: L("刷新", "Refresh")) { Task { await m.refresh() } }
            IconButton(icon: m.showHidden ? "eye" : "eye.slash", help: L("显示已隐藏设备", "Show hidden")) { m.showHidden.toggle() }
            IconButton(icon: "gearshape", help: L("设置", "Settings")) { m.page = .settings }
        }
    }

    @ViewBuilder var footer: some View {
        if m.hiddenCount > 0 {
            Button { m.showHidden.toggle() } label: {
                Text(m.showHidden ? L("收起已隐藏的设备", "Collapse hidden devices")
                                  : L("已隐藏 \(m.hiddenCount) 台离线或久未使用的设备 · 显示", "\(m.hiddenCount) offline/unused hidden · Show"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10)
            }.buttonStyle(.plain)
        }
    }
}

struct IconButton: View {
    let icon: String; let help: String; let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium)).frame(width: 28, height: 28)
                .background(Circle().fill(Theme.card))
        }.buttonStyle(.plain).help(help)
    }
}

struct DeviceRow: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    let focused: Bool
    var body: some View {
        let power = m.powerInfo(device)
        let on = power?.isOn ?? false
        let c = device.category.color
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(on ? c : c.opacity(0.16))
                Image(systemName: device.category.icon).font(.system(size: 14, weight: .medium)).foregroundStyle(on ? Color.white : c)
            }.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(m.displayName(device)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if m.isFavorite(device) { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
                    if m.prefs.devices[device.did]?.hidden == true || (m.showHidden && m.isHidden(device)) {
                        Image(systemName: "eye.slash").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                Text(m.subtitle(device)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if m.busy.contains(device.did) { ProgressView().controlSize(.mini) }
            if let power, device.isOnline {
                Toggle("", isOn: Binding(get: { power.isOn }, set: { _ in m.toggle(device) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(c)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 12).fill(focused ? Color.white.opacity(0.13) : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused ? c.opacity(0.6) : .clear))
        .opacity(device.isOnline ? 1 : 0.5)
        .contentShape(Rectangle())
        .task { m.loadStateIfNeeded(device) }
        .contextMenu { DeviceMenu(device: device) }
    }
}

struct DeviceMenu: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    var body: some View {
        Button(m.isFavorite(device) ? L("取消收藏", "Unfavorite") : L("收藏", "Favorite")) { m.toggleFavorite(device) }
        Button(L("重命名…", "Rename…")) { m.renaming = device }
        Button(m.isHidden(device) ? L("取消隐藏", "Unhide") : L("隐藏", "Hide")) { m.setHidden(device, !m.isHidden(device)) }
        if device.category == .ac { Button(L("在菜单栏显示温度", "Show in menu bar")) { m.prefs.menuBarDid = device.did } }
        Divider()
        Button(m.agent.allowlist.contains(device.did) ? L("移出 Agent 白名单", "Remove from agent allowlist") : L("允许 Agent 控制", "Allow agent control")) {
            if let i = m.agent.allowlist.firstIndex(of: device.did) { m.agent.allowlist.remove(at: i) } else { m.agent.allowlist.append(device.did) }
        }
        Button(L("复制 did", "Copy did")) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(device.did, forType: .string) }
    }
}

struct RenameOverlay: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    @State var text: String
    @FocusState private var focused: Bool
    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { m.renaming = nil }
            VStack(spacing: 12) {
                Text(L("重命名", "Rename")).font(.headline)
                TextField(device.name, text: $text).textFieldStyle(.roundedBorder).focused($focused).onSubmit(save)
                HStack {
                    Button(L("取消", "Cancel")) { m.renaming = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(L("保存", "Save"), action: save).keyboardShortcut(.defaultAction)
                }
            }
            .padding(18).frame(width: 280)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.bg2)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.stroke))
        }
        .onAppear { focused = true }
    }
    func save() { m.rename(device, text); m.renaming = nil }
}

// MARK: - 详情

struct DetailView: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: L("返回", "Back")) { m.back() }
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.displayName(device)).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    Text([device.roomName, device.model].compactMap { $0 }.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                if m.busy.contains(device.did) { ProgressView().controlSize(.small) }
                IconButton(icon: m.isFavorite(device) ? "star.fill" : "star", help: L("收藏", "Favorite")) { m.toggleFavorite(device) }
                Menu { DeviceMenu(device: device) } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28).background(Circle().fill(Theme.card)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if let st = m.states[device.did] {
                if let ac = ACState.make(st) { ACCardView(device: device, ac: ac); Spacer(minLength: 0) }
                else { GenericDetailView(device: device, state: st) }
            } else if let e = m.stateErrors[device.did] {
                Spacer()
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(e).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button(L("重试", "Retry")) { m.stateErrors[device.did] = nil; Task { await m.loadState(device) } }
                Spacer()
            } else if !device.isOnline {
                Spacer(); Text(L("设备离线", "Device offline")).foregroundStyle(.secondary); Spacer()
            } else {
                Spacer(); ProgressView(L("正在读取状态…", "Reading state…")); Spacer()
            }
        }
        .padding(12)
        .focusable().focusEffectDisabled()
        .onKeyPress(.escape) { m.back(); return .handled }
        .onKeyPress(.leftArrow) { adjustTemp(-1) }
        .onKeyPress(.rightArrow) { adjustTemp(1) }
        .onKeyPress(.space) { m.toggle(device); return .handled }
        .task(id: device.did) {
            while !Task.isCancelled {
                await m.loadState(device)
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }
    func adjustTemp(_ d: Double) -> KeyPress.Result {
        guard let st = m.states[device.did], let ac = ACState.make(st), let k = ac.tempKey, let t = ac.target else { return .ignored }
        m.write(device, k, ac.tempValue(min(ac.maxT, max(ac.minT, t + d * ac.step))))
        return .handled
    }
}
