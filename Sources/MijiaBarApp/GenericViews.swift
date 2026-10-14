import SwiftUI
import MijiaCore

/// 根据 MIoT 规格自动生成控件
struct GenericDetailView: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    let state: DeviceState
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let p = m.powerInfo(device) {
                    let c = device.category.color
                    Button { m.toggle(device) } label: {
                        HStack(spacing: 14) {
                            DeviceGlyph(category: device.category, on: p.isOn, size: 56, animated: true).ripple(p.isOn, color: c)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(p.isOn ? L("已开启", "On") : L("已关闭", "Off")).font(.system(size: 20, weight: .semibold)).contentTransition(.numericText())
                                Text(L("点击或按空格切换", "Click or press Space")).font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "power").font(.system(size: 16, weight: .bold))
                                .foregroundStyle(p.isOn ? AnyShapeStyle(c) : AnyShapeStyle(.primary))
                        }
                        .padding(16)
                        .background {
                            let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
                            shape.fill(LinearGradient(colors: [c.opacity(p.isOn ? 0.22 : 0.06), c.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .overlay(alignment: .topLeading) {
                                    Circle().fill(RadialGradient(colors: [c.opacity(0.4), c.opacity(0)], center: .center, startRadius: 0, endRadius: 100))
                                        .frame(width: 200, height: 200).offset(x: -60, y: -90).opacity(p.isOn ? 1 : 0)
                                }
                                .clipShape(shape)
                                .overlay(shape.stroke(p.isOn ? c.opacity(0.35) : Theme.stroke))
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 20))
                        .animation(Motion.smooth, value: p.isOn)
                    }.buttonStyle(.pressable)
                }
                if let spec = state.spec {
                    let services = spec.controlServices.filter { !$0.properties.isEmpty || !$0.actions.isEmpty }
                    ForEach(services, id: \.iid) { svc in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(zhName(svc.name, fallback: svc.description)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(svc.properties.filter { ($0.readable || $0.writable) && $0.key != spec.mainOnProperty?.key }, id: \.key) { p in
                                PropRow(device: device, prop: p, value: state.values[p.key])
                            }
                            let acts = svc.actions.filter { $0.inputs.isEmpty }
                            if !acts.isEmpty {
                                HStack { ForEach(acts, id: \.key) { a in Button(zhName(a.name, fallback: a.description)) { m.runAction(device, a) } } }
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
                    }
                } else {
                    Text(L("这个型号在 miot-spec.org 上没有公开规格，暂时只能查看。", "No public MIoT spec for this model."))
                        .font(.system(size: 12)).foregroundStyle(.secondary).padding()
                }
                Text(L("数据来源：", "Source: ") + state.source).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }.scrollIndicators(.never)
    }
}

struct PropRow: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    let prop: SpecProperty
    let value: PropValue?
    @State private var local: Double?

    var label: String { zhName(prop.name, fallback: prop.description) }
    var unit: String { switch prop.unit { case "celsius": return "°C"; case "percentage": return "%"; case "kelvin": return "K"; case "watt": return "W"; case nil, "none": return ""; default: return " " + (prop.unit ?? "") } }

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).lineLimit(1)
            Spacer(minLength: 6)
            control
        }
        .frame(minHeight: 22)
        .animation(Motion.snappy, value: value)
    }

    @ViewBuilder var control: some View {
        if prop.writable && prop.format == "bool" {
            Toggle("", isOn: Binding(get: { value?.boolValue ?? false }, set: { m.write(device, prop.key, .bool($0)) }))
                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
        } else if prop.writable, let ops = prop.options, !ops.isEmpty {
            Picker("", selection: Binding(get: { Int(value?.doubleValue ?? -1) }, set: { m.write(device, prop.key, .int($0)) })) {
                ForEach(ops, id: \.value) { Text(trValue($0.description)).tag($0.value) }
            }.labelsHidden().pickerStyle(.menu).fixedSize()
        } else if prop.writable, let r = prop.range, r.count >= 2, prop.isNumber {
            let step = r.count > 2 && r[2] > 0 ? r[2] : 1
            // 不传 step：系统会给每一档画刻度（1…100 就成了一条虚线），在 setter 里自己吸附
            Slider(value: Binding(get: { local ?? value?.doubleValue ?? r[0] }, set: { local = r[0] + (($0 - r[0]) / step).rounded() * step }),
                   in: r[0]...max(r[1], r[0] + step),
                   onEditingChanged: { editing in
                       if !editing, let v = local { m.write(device, prop.key, PropValue.double(v).coerced(to: prop.format)); local = nil }
                   }).frame(width: 130).controlSize(.small)
            Text(PropValue.double(local ?? value?.doubleValue ?? r[0]).description + unit).font(.system(size: 11)).monospacedDigit().frame(width: 52, alignment: .trailing)
                .contentTransition(.numericText(value: local ?? value?.doubleValue ?? r[0]))
        } else {
            Text(display).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1).contentTransition(.numericText())
        }
    }

    var display: String {
        guard let value, value != .null else { return "-" }
        if let ops = prop.options, let v = value.doubleValue, let o = ops.first(where: { $0.value == Int(v) }) { return trValue(o.description) }
        if prop.format == "bool" { return value.boolValue == true ? L("是", "Yes") : L("否", "No") }
        return "\(value)\(unit)"
    }
}

struct SettingsView: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                IconButton(icon: "chevron.left", help: L("返回", "Back")) { m.back() }
                Text(L("设置", "Settings")).font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    group(L("账号", "Account")) {
                        row(L("小米 ID", "Xiaomi ID")) { Text(m.session?.userId ?? "-").foregroundStyle(.secondary) }
                        row(L("服务器地区", "Region")) {
                            Picker("", selection: Binding(get: { m.prefs.region }, set: { m.setRegion($0) })) {
                                ForEach(xiaomiRegions, id: \.id) { Text($0.name).tag($0.id) }
                            }.labelsHidden().fixedSize()
                        }
                        ActionRow(title: L("退出登录", "Sign out"), icon: "rectangle.portrait.and.arrow.right", destructive: true) { m.logout() }
                    }
                    group(L("语言", "Language")) {
                        let sug = AppLang.suggested(forRegion: m.prefs.region)
                        row(L("界面语言", "Language")) {
                            Picker("", selection: Binding(get: { m.lang }, set: { m.setLang($0) })) {
                                Section(L("当前地区推荐", "Suggested for region")) { ForEach(sug, id: \.self) { Text($0.nativeName).tag($0) } }
                                let other = AppLang.allCases.filter { !sug.contains($0) }
                                if !other.isEmpty { Section(L("其他", "Other")) { ForEach(other, id: \.self) { Text($0.nativeName).tag($0) } } }
                            }.labelsHidden().fixedSize()
                        }
                        if m.langManual {
                            Button(L("跟随地区默认", "Follow region default")) {
                                UserDefaults.standard.set(false, forKey: "MijiaBarLangManual")
                                if let d = sug.first { m.setLang(d, manual: false) }
                            }
                        }
                    }
                    group(L("设备管理", "Devices")) {
                        SwitchRow(title: L("显示已隐藏的设备", "Show hidden devices"), isOn: Binding(get: { m.showHidden }, set: { _ in m.toggleShowHidden() }))
                        Text(L("默认隐藏：离线设备，以及云端最后在线时间超过 30 天的设备。右键设备可以手动隐藏/取消隐藏、收藏和重命名。",
                               "Hidden by default: offline devices and devices not seen online for 30+ days. Right-click a device to hide, favorite or rename."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    group(L("摄像头直播", "Camera live view")) {
                        let ok = m.mock || m.session?.canLiveStream == true
                        row(L("摄像头登录", "Camera sign-in")) {
                            Label(ok ? L("已授权", "Authorized") : L("未授权", "Not authorized"), systemImage: ok ? "checkmark.seal.fill" : "exclamationmark.circle")
                                .foregroundStyle(ok ? .green : .orange)
                        }
                        if m.loggingIn {
                            if let img = m.qrImage {
                                Image(nsImage: img).resizable().interpolation(.none).frame(width: 140, height: 140).frame(maxWidth: .infinity)
                            }
                            Text(m.loginStatus).font(.system(size: 11)).foregroundStyle(.secondary)
                        } else if !ok {
                            Button(L("重新扫码授权直播", "Scan QR to enable live view")) { m.startLogin() }
                        }
                        Text(L("直播由内置的 go2rtc 在本机播放：只监听 127.0.0.1，按需启动，关闭画面后自动停止。密钥向小米云获取，视频经小米 P2P 从摄像头传来；凭据只保存在钥匙串。Agent / MCP 无法访问摄像头画面。",
                               "Live video is played locally by the built-in go2rtc: it listens on 127.0.0.1 only, starts on demand and stops when you close the player. Keys come from the Xiaomi cloud and video from the camera over Xiaomi P2P; credentials stay in the Keychain. Agents / MCP can't access camera video."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    GlanceSettingsSection()
                    AgentSettingsSection()
                    group(L("软件更新", "Updates")) {
                        SwitchRow(title: L("自动检查更新", "Check for updates automatically"),
                                  isOn: Binding(get: { Updater.shared.automaticallyChecksForUpdates },
                                                set: { Updater.shared.automaticallyChecksForUpdates = $0 }))
                        ActionRow(title: L("检查更新…", "Check for Updates…"), icon: "arrow.triangle.2.circlepath") {
                            Updater.shared.checkForUpdates()
                        }
                        Text(L("更新通过 GitHub Pages 的 appcast 分发，安装包经苹果公证并用 EdDSA 签名。",
                               "Updates come from the GitHub Pages appcast. Packages are notarized by Apple and signed with EdDSA."))
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    group(L("关于", "About")) {
                        row("MijiaBar") { Text(appVersion).foregroundStyle(.secondary) }
                        Link("github.com/neardws/MijiaBar", destination: URL(string: "https://github.com/neardws/MijiaBar")!)
                        Link(L("下载页", "Download site"), destination: URL(string: "https://www.neardws.com/MijiaBar/")!)
                    }
                    // 退出放在最后，和「退出登录」同一种危险操作行
                    SettingsGroup {
                        ActionRow(title: L("完全退出 MijiaBar", "Quit MijiaBar"), icon: "power", destructive: true, shortcut: "⌘Q") { m.quitApp() }
                    }
                }
            }
            .scrollIndicators(.never)
            .animation(Motion.smooth, value: m.agent.mode)
        }
        .padding(12)
        .focusable().focusEffectDisabled()
        .onKeyPress(.escape) { m.back(animated: false); return .handled }
    }

    func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
    func group<C: View>(_ title: String, @ViewBuilder _ c: @escaping () -> C) -> some View { SettingsGroup(title: title, content: c) }
    func row<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View { HStack { Text(t); Spacer(); c() } }
    /// 发布包里读 Info.plist 的版本号；直接运行调试构建时没有
    var appVersion: String { (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).map { "v" + $0 } ?? "dev" }
}

/// 设置页的分组卡片：小标题 + 内容，圆角 14，Theme.card 底色
struct SettingsGroup<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary) }
            content()
        }
        .font(.system(size: 12))
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }
}

/// 开关行：文字在左、系统开关在右（和其他行一样左右对齐）
struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.switch).controlSize(.mini)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .trailing)
            .overlay(alignment: .leading) { Text(title).lineLimit(1).allowsHitTesting(false).accessibilityHidden(true) }
    }
}

/// 操作行：整行可点，按压/悬停反馈与其他按钮一致；危险操作用红色
struct ActionRow: View {
    let title: String, icon: String
    var destructive = false
    var shortcut: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(Color.secondary) }
            }
            .foregroundStyle(destructive ? AnyShapeStyle(.red) : AnyShapeStyle(.primary))
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(0.98)).hoverHighlight()
    }
}

/// 一段可直接粘贴给 Claude Code / Codex / Cursor 等 Agent 的安装说明，Agent 读完即可自行完成配置
struct AgentPromptBox: View {
    let text: String
    let onCopy: (String) -> Void
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("把下面这段话粘贴给 Claude Code、Codex、Cursor 等 Agent，它会自己完成安装和配置。",
                       "Paste this into Claude Code, Codex, Cursor or any other agent — it will install and configure itself."))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text(text).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.tile))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.stroke))
            Button {
                onCopy(text)
                withAnimation(Motion.snappy) { copied = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { withAnimation(Motion.snappy) { copied = false } }
            } label: {
                Label(copied ? L("已复制", "Copied") : L("复制安装说明", "Copy setup instructions"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(copied ? 0.25 : 0.15)))
            }
            .buttonStyle(.pressable).hoverHighlight()
        }
    }
}

/// 设置 → Agent 接口：权限 + 一段可直接粘贴给 Agent 的安装说明
struct AgentSettingsSection: View {
    @EnvironmentObject var m: AppModel
    var body: some View {
        SettingsGroup(title: L("Agent 接口（CLI / MCP）", "Agent interface (CLI / MCP)")) {
            Picker(L("权限", "Access"), selection: $m.agent.mode) {
                Text(L("关闭", "Off")).tag(AgentPolicy.Mode.disabled)
                Text(L("只读", "Read")).tag(AgentPolicy.Mode.readOnly)
                Text(L("白名单", "Allowlist")).tag(AgentPolicy.Mode.allowlist)
                Text(L("全部", "Full")).tag(AgentPolicy.Mode.full)
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
            SwitchRow(title: L("每次写操作弹窗确认", "Confirm every write"), isOn: $m.agent.confirmWrites)
            if m.agent.mode == .allowlist {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L("允许 Agent 控制的设备：", "Devices agents may control:")).font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(m.devices.filter { !m.isHidden($0) }) { d in
                        SwitchRow(title: m.displayName(d), isOn: Binding(get: { m.agent.allowlist.contains(d.did) }, set: { on in
                            if on { m.agent.allowlist.append(d.did) } else { m.agent.allowlist.removeAll { $0 == d.did } }
                        }))
                    }
                }.transition(.pop(0.98, anchor: .top))
            }
            AgentPromptBox(text: agentSetupPrompt(cli: m.cliPath)) { copy($0); m.showToast(L("已复制，粘贴给你的 Agent 即可", "Copied — paste it into your agent")) }
        }
        .animation(Motion.smooth, value: m.agent.mode)
    }
    func copy(_ s: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(s, forType: .string) }
}
