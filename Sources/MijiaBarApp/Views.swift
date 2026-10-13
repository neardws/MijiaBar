import SwiftUI
import AppKit
import MijiaCore

struct RootView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            // 页面栈：列表在底层，详情/设置从右侧推入
            ZStack {
                if m.session == nil {
                    LoginView().transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 1.04))))
                } else {
                    switch m.page {
                    case .list: DeviceListView().transition(.pageBase).zIndex(0)
                    case .detail(let did):
                        Group { if let d = m.device(did) { DetailView(device: d) } else { DeviceListView() } }
                            .id(did).transition(.pageTop).zIndex(1)
                    case .settings: SettingsView().transition(.pageTop).zIndex(1)
                    }
                }
            }
            .animation(Motion.enter, value: m.session == nil)
            if let d = m.renaming {
                RenameOverlay(device: d, text: m.displayName(d))
                    .transition(.asymmetric(insertion: .opacity.animation(Motion.enter), removal: .opacity.animation(Motion.exit))).zIndex(10)
            }
        }
        .animation(Motion.enter, value: m.renaming?.did)
        .overlay(alignment: .bottom) {
            if let t = m.toast {
                Text(t).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.85))).overlay(Capsule().stroke(Theme.stroke))
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .padding(.bottom, 14)
                    // 从底部进、从底部出，保持空间一致
                    .transition(Motion.reduced ? .opacity : .asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).animation(Motion.enter),
                        removal: .move(edge: .bottom).combined(with: .opacity).animation(Motion.exit)))
            }
        }
        .animation(Motion.enter, value: m.toast)
        .frame(width: 360, height: 600)
        .clipped()
        .preferredColorScheme(.dark)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}

// MARK: - 登录

struct LoginView: View {
    @EnvironmentObject var m: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "house.circle.fill").font(.system(size: 44)).foregroundStyle(Theme.sliderGradient)
                .shadow(color: Theme.cool.opacity(0.5), radius: 14)
                .phaseAnimator([false, true]) { v, up in v.offset(y: up && !reduceMotion ? -3 : 0) } animation: { _ in .easeInOut(duration: 1.6) }
                .staggerIn(0)
            Text(L("登录小米账号", "Sign in to Xiaomi")).font(.system(size: 20, weight: .semibold)).staggerIn(1)
            Text(L("用米家 App 扫码，无需输入密码", "Scan with the Mi Home app — no password needed")).font(.system(size: 12)).foregroundStyle(.secondary).staggerIn(2)
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white).frame(width: 224, height: 224)
                if let img = m.qrImage {
                    Image(nsImage: img).resizable().interpolation(.none).frame(width: 200, height: 200)
                        .overlay(ScanLine())
                        .transition(.pop())
                } else if m.loggingIn {
                    ProgressView().controlSize(.large).colorScheme(.light).transition(.opacity)
                } else {
                    Button(L("获取二维码", "Get QR code")) { m.startLogin() }.colorScheme(.light).transition(.opacity)
                }
            }
            .overlay {
                if m.qrImage != nil {
                    ViewfinderCorners(length: 16).stroke(Theme.sliderGradient, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .frame(width: 208, height: 208)
                        .transition(.pop(1.05))
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
            .animation(Motion.enter, value: m.qrImage)
            .animation(Motion.enter, value: m.loggingIn)
            .staggerIn(3)
            Text(m.loginStatus).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(height: 32)
                .contentTransition(.opacity).animation(Motion.snappy, value: m.loginStatus)
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

/// 二维码上自上而下循环扫过的光带
struct ScanLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { tl in
            GeometryReader { g in
                let p = (tl.date.timeIntervalSinceReferenceDate / 2.6).truncatingRemainder(dividingBy: 1)
                let band: CGFloat = 40
                VStack(spacing: 0) {
                    LinearGradient(colors: [Theme.cool.opacity(0), Theme.cool.opacity(0.18)], startPoint: .top, endPoint: .bottom).frame(height: band)
                    Capsule().fill(Theme.cool).frame(height: 2).shadow(color: Theme.cool, radius: 4)
                }
                .offset(y: CGFloat(p) * (g.size.height + band) - band)
                .opacity(reduceMotion ? 0 : sin(p * .pi))
            }
        }
        .clipped().allowsHitTesting(false)
    }
}

/// 取景框四角
struct ViewfinderCorners: Shape {
    var length: CGFloat = 24
    func path(in r: CGRect) -> Path {
        var p = Path()
        for (c, dx, dy) in [(CGPoint(x: r.minX, y: r.minY), 1.0, 1.0), (CGPoint(x: r.maxX, y: r.minY), -1.0, 1.0),
                            (CGPoint(x: r.minX, y: r.maxY), 1.0, -1.0), (CGPoint(x: r.maxX, y: r.maxY), -1.0, -1.0)] {
            p.move(to: CGPoint(x: c.x, y: c.y + dy * length))
            p.addLine(to: c)
            p.addLine(to: CGPoint(x: c.x + dx * length, y: c.y))
        }
        return p
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
                Image(systemName: "magnifyingglass").foregroundStyle(searchFocused ? AnyShapeStyle(Theme.cool) : AnyShapeStyle(.secondary))
                    .symbolEffect(.bounce, value: searchFocused)
                TextField(L("搜索设备、房间、型号", "Search devices, rooms, models"), text: $m.search)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .onSubmit { searchFocused = false; cursor = 0 }
                if !m.search.isEmpty {
                    Button { m.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.pressable(0.9)).foregroundStyle(.secondary)
                        .transition(.pop(0.9))
                }
            }
            .font(.system(size: 13)).padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(searchFocused ? Color.white.opacity(0.09) : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.cool.opacity(searchFocused ? 0.55 : 0)))
            .animation(Motion.snappy, value: searchFocused)

            if m.devices.isEmpty {
                Spacer()
                if m.refreshing { ProgressView(L("正在获取设备列表…", "Loading devices…")).transition(.opacity) }
                else { Text(L("还没有设备", "No devices")).foregroundStyle(.secondary).transition(.opacity) }
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(m.sections) { sec in
                                Text(sec.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6).padding(.leading, 4)
                                    .transition(.opacity)
                                ForEach(sec.devices) { d in
                                    DeviceRow(device: d, focused: flat.indices.contains(cursor) && flat[cursor] == d.did)
                                        .transition(.pop(0.97, anchor: .top))
                                        .id(d.did)
                                        .onTapGesture { m.open(d) }
                                }
                            }
                            footer
                        }
                    }
                    .scrollIndicators(.never)
                    // 键盘导航：焦点和滚动都瞬间到位
                    .onChange(of: cursor) { _, c in if flat.indices.contains(c) { proxy.scrollTo(flat[c], anchor: .center) } }
                }
            }
        }
        .padding(12)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { cursor = min(cursor + 1, max(flat.count - 1, 0)); return .handled }
        .onKeyPress(.upArrow) { cursor = max(cursor - 1, 0); return .handled }
        .onKeyPress(.return) { if flat.indices.contains(cursor), let d = m.device(flat[cursor]) { m.open(d, animated: false) }; return .handled }
        .onKeyPress(.space) { if !searchFocused, flat.indices.contains(cursor), let d = m.device(flat[cursor]) { withoutAnimation { m.toggle(d) }; return .handled }; return .ignored }
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
            IconButton(icon: "arrow.clockwise", help: L("刷新", "Refresh"), spinning: m.refreshing) { Task { await m.refresh() } }
            IconButton(icon: m.showHidden ? "eye" : "eye.slash", help: L("显示已隐藏设备", "Show hidden")) { m.toggleShowHidden() }
            IconButton(icon: "gearshape", help: L("设置", "Settings")) { m.openSettings() }
        }
    }

    @ViewBuilder var footer: some View {
        if m.hiddenCount > 0 {
            Button { m.toggleShowHidden() } label: {
                Text(m.showHidden ? L("收起已隐藏的设备", "Collapse hidden devices")
                                  : L("已隐藏 \(m.hiddenCount) 台离线或久未使用的设备 · 显示", "\(m.hiddenCount) offline/unused hidden · Show"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .contentTransition(.numericText())
            }.buttonStyle(.plain).hoverHighlight()
        }
    }
}

struct IconButton: View {
    let icon: String; let help: String
    var spinning = false
    var tint: Color? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13, weight: .medium))
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary))
                .contentTransition(.symbolEffect(.replace))
                .modifier(Spin(active: spinning))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.card))
                .animation(Motion.snappy, value: icon)
        }.buttonStyle(.pressable(0.95)).hoverHighlight().help(help)
    }
}

struct DeviceRow: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    let focused: Bool
    @State private var hovering = false
    var body: some View {
        let power = m.powerInfo(device)
        let on = power?.isOn ?? false
        let c = device.category.color
        let fav = m.isFavorite(device)
        let busy = m.busy.contains(device.did)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 10) {
            DeviceGlyph(category: device.category, on: on)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(m.displayName(device)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    if fav {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                            .transition(.pop(0.9))
                    }
                    if m.prefs.devices[device.did]?.hidden == true || (m.showHidden && m.isHidden(device)) {
                        Image(systemName: "eye.slash").font(.system(size: 9)).foregroundStyle(.secondary).transition(.opacity)
                    }
                }
                Text(m.subtitle(device)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            if busy { ProgressView().controlSize(.mini).transition(.opacity) }
            if let power, device.isOnline {
                Toggle("", isOn: Binding(get: { power.isOn }, set: { _ in m.toggle(device) }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden().tint(c)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(shape.fill(focused ? Color.white.opacity(0.13) : hovering ? Color.white.opacity(0.09) : Theme.card))
        .overlay(shape.stroke(focused ? c.opacity(0.6) : .clear))
        .opacity(device.isOnline ? 1 : 0.5)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.snappy) { hovering = h } }
        .animation(Motion.smooth, value: on)
        .animation(Motion.smooth, value: fav)
        .animation(Motion.snappy, value: busy)
        .animation(Motion.smooth, value: m.subtitle(device))
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
    @State private var shown = false
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
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.bg2)).overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.stroke))
            .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
            .scaleEffect(shown || Motion.reduced ? 1 : 0.96)
        }
        .onAppear { focused = true; withAnimation(Motion.enter) { shown = true } }
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
                if m.busy.contains(device.did) { ProgressView().controlSize(.small).transition(.opacity) }
                IconButton(icon: m.isFavorite(device) ? "star.fill" : "star", help: L("收藏", "Favorite"), tint: m.isFavorite(device) ? .yellow : nil) {
                    m.toggleFavorite(device)
                }
                .symbolEffect(.bounce, value: m.isFavorite(device))
                Menu { DeviceMenu(device: device) } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28).background(Circle().fill(Theme.card)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().hoverHighlight()
            }
            .animation(Motion.snappy, value: m.busy.contains(device.did))
            if let st = m.states[device.did] {
                if let ac = ACState.make(st) { ACCardView(device: device, ac: ac).transition(.opacity.combined(with: .scale(scale: 0.97))); Spacer(minLength: 0) }
                else { GenericDetailView(device: device, state: st).transition(.opacity.combined(with: .scale(scale: 0.97))) }
            } else if let e = m.stateErrors[device.did] {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange).symbolEffect(.bounce, value: e)
                    Text(e).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button(L("重试", "Retry")) { m.stateErrors[device.did] = nil; Task { await m.loadState(device) } }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                Spacer()
            } else if !device.isOnline {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "wifi.slash").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(L("设备离线", "Device offline")).foregroundStyle(.secondary)
                }.transition(.opacity)
                Spacer()
            } else {
                Spacer(); ProgressView(L("正在读取状态…", "Reading state…")).transition(.opacity); Spacer()
            }
        }
        .animation(Motion.smooth, value: m.states[device.did] != nil)
        .animation(Motion.smooth, value: m.stateErrors[device.did])
        .padding(12)
        .focusable().focusEffectDisabled()
        .onKeyPress(.escape) { m.back(animated: false); return .handled }
        .onKeyPress(.leftArrow) { adjustTemp(-1) }
        .onKeyPress(.rightArrow) { adjustTemp(1) }
        .onKeyPress(.space) { withoutAnimation { m.toggle(device) }; return .handled }
        .task(id: device.did) {
            while !Task.isCancelled {
                await m.loadState(device)
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }
    func adjustTemp(_ d: Double) -> KeyPress.Result {
        guard let st = m.states[device.did], let ac = ACState.make(st), let k = ac.tempKey, let t = ac.target else { return .ignored }
        withoutAnimation { m.write(device, k, ac.tempValue(min(ac.maxT, max(ac.minT, t + d * ac.step)))) }
        return .handled
    }
}
