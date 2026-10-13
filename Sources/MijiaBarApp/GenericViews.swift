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
                            Image(systemName: "power").font(.system(size: 16, weight: .bold)).symbolEffect(.bounce, value: p.isOn)
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
            Slider(value: Binding(get: { local ?? value?.doubleValue ?? r[0] }, set: { local = $0 }), in: r[0]...max(r[1], r[0] + step), step: step,
                   onEditingChanged: { editing in
                       if !editing, let v = local { m.write(device, prop.key, PropValue.double(v).coerced(to: prop.format)); local = nil }
                   }).frame(width: 130).controlSize(.small)
            Text("\(PropValue.double(local ?? value?.doubleValue ?? r[0]))\(unit)").font(.system(size: 11)).monospacedDigit().frame(width: 52, alignment: .trailing)
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
                        Button(L("退出登录", "Sign out"), role: .destructive) { m.logout() }
                    }
                    group(L("语言", "Language")) {
                        let sug = AppLang.suggested(forRegion: m.prefs.region)
                        row(L("界面语言", "Language")) {
                            Picker("", selection: Binding(get: { m.lang }, set: { m.setLang($0) })) {
                                Section(L("当前地区推荐", "Suggested for region")) { ForEach(sug, id: \.self) { Text($0.nativeName).tag($0) } }
                                Section(L("其他", "Other")) { ForEach(AppLang.allCases.filter { !sug.contains($0) }, id: \.self) { Text($0.nativeName).tag($0) } }
                            }.labelsHidden().fixedSize()
                        }
                        if !m.lang.isComplete {
                            Text("\(m.lang.nativeName): translation in progress, showing English for now.").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        if m.langManual {
                            Button(L("跟随地区默认", "Follow region default")) {
                                UserDefaults.standard.set(false, forKey: "MijiaBarLangManual")
                                if let d = sug.first { m.setLang(d, manual: false) }
                            }
                        }
                    }
                    group(L("设备管理", "Devices")) {
                        Toggle(L("显示已隐藏的设备", "Show hidden devices"), isOn: Binding(get: { m.showHidden }, set: { _ in m.toggleShowHidden() }))
                        Text(L("默认隐藏：离线设备，以及云端最后在线时间超过 30 天的设备。右键设备可以手动隐藏/取消隐藏、收藏和重命名。",
                               "Hidden by default: offline devices and devices not seen online for 30+ days. Right-click a device to hide, favorite or rename."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    group(L("Agent 接口（CLI / MCP）", "Agent interface (CLI / MCP)")) {
                        Picker(L("权限", "Access"), selection: $m.agent.mode) {
                            Text(L("关闭", "Off")).tag(AgentPolicy.Mode.disabled)
                            Text(L("只读", "Read")).tag(AgentPolicy.Mode.readOnly)
                            Text(L("白名单", "Allowlist")).tag(AgentPolicy.Mode.allowlist)
                            Text(L("全部", "Full")).tag(AgentPolicy.Mode.full)
                        }.pickerStyle(.segmented)
                        Toggle(L("每次写操作弹窗确认", "Confirm every write"), isOn: $m.agent.confirmWrites)
                        if m.agent.mode == .allowlist {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("允许 Agent 控制的设备：", "Devices agents may control:")).font(.system(size: 11)).foregroundStyle(.secondary)
                                ForEach(m.devices.filter { !m.isHidden($0) }) { d in
                                    Toggle(m.displayName(d), isOn: Binding(get: { m.agent.allowlist.contains(d.did) }, set: { on in
                                        if on { m.agent.allowlist.append(d.did) } else { m.agent.allowlist.removeAll { $0 == d.did } }
                                    })).font(.system(size: 12))
                                }
                            }.transition(.pop(0.98, anchor: .top))
                        }
                        Text(m.cliPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button(L("复制 MCP 配置", "Copy MCP config")) { copy(m.mcpConfig); m.showToast(L("已复制", "Copied")) }
                            Button(L("复制 CLI 路径", "Copy CLI path")) { copy(m.cliPath); m.showToast(L("已复制", "Copied")) }
                        }
                    }
                    Button { m.quitApp() } label: {
                        Label(L("完全退出 MijiaBar", "Quit MijiaBar"), systemImage: "power")
                            .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.14)))
                            .foregroundStyle(.red)
                    }.buttonStyle(.plain).help("⌘Q")
                    group(L("关于", "About")) {
                        row("MijiaBar") { Text("v0.1.5-rc1").foregroundStyle(.secondary) }
                        Link("github.com/neardws/MijiaBar", destination: URL(string: "https://github.com/neardws/MijiaBar")!)

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
    func group<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            c()
        }
        .font(.system(size: 12))
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
    }
    func row<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View { HStack { Text(t); Spacer(); c() } }
}
