import SwiftUI
import MijiaCore

/// 按设备类型分发到专门设计的详情页
struct TypeDetailView: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    let state: DeviceState
    var body: some View {
        let dc = DC(device: device, state: state)
        switch device.category {
        case .fan: FanDetail(dc: dc)
        case .humidifier: HumidifierDetail(dc: dc)
        case .vacuum: VacuumDetail(dc: dc)
        case .light: LightDetail(dc: dc)
        case .plug: PlugDetail(dc: dc)
        case .tv: TVDetail(dc: dc)
        case .speaker: SpeakerDetail(dc: dc)
        case .camera: CameraDetail(dc: dc)
        case .printer: PrinterDetail(dc: dc)
        case .kitchen: CookerDetail(dc: dc)
        case .purifier: PurifierDetail(dc: dc)
        case .heater, .dehumidifier: ApplianceDetail(dc: dc)
        case .sensor: SensorDetail(dc: dc)
        default: DeviceCardView(device: device, state: state).frame(width: cardWidth)
        }
    }
}

/// 还没有状态时（读取中、离线、读取失败）的详情卡片：和正常详情页同一个 TypeShell，插画是该设备关着的样子，
/// 读到状态后原地换成真正的卡片，不会从页面中央的转圈跳到一张卡片
struct DeviceStatusCard: View {
    @EnvironmentObject var m: AppModel
    enum Kind: Equatable { case loading, offline, failed(String) }
    let device: Device
    let kind: Kind
    var body: some View {
        let tint = device.category.color
        let title: String = {
            switch kind {
            case .loading: return L("正在读取状态…", "Reading state…")
            case .offline: return L("设备离线", "Device offline")
            case .failed: return L("读取失败", "Couldn't read state")
            }
        }()
        TypeShell(device: device, tint: tint, isOn: false, title: title, subtitle: zhCategory(device.category)) {
            offArt(device, tint: tint)
        } content: {
            switch kind {
            case .loading:
                ProgressView().controlSize(.small).frame(height: 40)
            case .offline:
                Text(L("请检查设备的电源和网络连接", "Check the device's power and network connection"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            case .failed(let e):
                Text(e).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineLimit(4).textSelection(.enabled)
                Button(action: retry) {
                    WideButtonFace(title: L("重试", "Retry"), icon: "arrow.clockwise", tint: tint)
                }
                .buttonStyle(.pressable).hoverHighlight().detailKeyboardAction(retry)
            }
        }
    }
    private func retry() {
        m.stateErrors[device.did] = nil
        Task { await m.loadState(device) }
    }
}

/// 设备关着时的插画（没有读数时用）
@MainActor @ViewBuilder func offArt(_ d: Device, tint: Color) -> some View {
    switch d.category {
    case .ac: ACIllustration(on: false, tint: tint)
    case .fan: FanArt(on: false, level: 0.5, swing: false, tint: tint)
    case .light: BulbArt(on: false, brightness: 0.7, kelvin: nil)
    case .plug: PlugArt(on: false, watts: nil, tint: tint)
    case .tv: TVArt(on: false, playing: false, tint: tint)
    case .speaker: SpeakerArt(playing: false, volume: 0.5, tint: tint)
    case .camera: if d.form == .doorbell { DoorbellArt(on: false, tint: tint) } else { CameraArt(on: false, tint: tint) }
    case .printer: PrinterArt(busy: false, error: false, tint: tint)
    case .kitchen: CookerArt(cooking: false, tint: tint)
    case .purifier: PurifierArt(on: false, filter: nil, tint: tint)
    case .heater, .dehumidifier: ApplianceArt(kind: d.category, on: false, level: 0.3, tint: tint)
    case .humidifier: HumidifierArt(on: false, tint: tint)
    case .vacuum: VacuumArt(on: false, busy: false, tint: tint)
    case .sensor:
        switch d.form {
        case .motion: MotionSensorArt(on: false, tint: tint)
        case .contact: ContactSensorArt(on: false, open: nil, tint: tint)
        case .leak: LeakSensorArt(on: false, wet: nil, tint: tint)
        default: ThermoArt(temp: nil, tint: tint)
        }
    case .other, .curtain, .fridge, .washer, .waterHeater: GenericArt(on: false, tint: tint)
    case .airPurifier: AirPurifierArt(on: false, level: 0.5, tint: tint)
    }
}

extension View {
    /// 底部按钮行：等宽排列
    func tileRow() -> some View { self.frame(maxWidth: .infinity) }
}

@MainActor private func powerHandler(_ m: AppModel, _ d: Device) -> (() -> Void)? {
    guard let p = m.powerInfo(d) else { return nil }
    return { m.write(d, p.key, p.isOn ? p.off : p.on) }
}
private func joined(_ parts: [String?]) -> String { parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }

// MARK: 风扇
struct FanDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.teal
        let on = m.powerInfo(d)?.isOn ?? false
        let level = dc.spec?.controlServices.flatMap(\.properties).first { $0.name == "fan-level" && $0.options != nil } ?? dc.p("fan-level") ?? dc.p("speed-level")
        let swing = dc.p("horizontal-swing")
        TypeShell(device: d, tint: tint, isOn: on, title: on ? L("已开启", "On") : L("已关闭", "Off"),
                  subtitle: joined([L("风扇", "Fan"), dc.text(dc.p("mode", in: "fan")), dc.bool(swing) == true ? L("摆头中", "Oscillating") : nil]),
                  powerOn: on, onPower: powerHandler(m, d)) {
            FanArt(on: on, level: propFraction(level, dc.num(level)), swing: dc.bool(swing) ?? false, tint: tint)
        } content: {
            BigValue(value: dc.text(level), caption: L("风速", "Speed"), dim: !on)
            if let level { PropSlider(dc: dc, prop: level, colors: [Color(red: 0.6, green: 0.92, blue: 0.88), .teal, Color(red: 0.2, green: 0.5, blue: 0.9)], enabled: on) }
            HStack(spacing: 8) {
                PropTile(dc: dc, prop: dc.p("mode", in: "fan"), title: L("模式", "Mode"), icon: "wind", tint: tint)
                PropTile(dc: dc, prop: swing, title: L("摆头", "Oscillate"), icon: "arrow.left.and.right", tint: tint)
                PropTile(dc: dc, prop: dc.p("horizontal-swing-included-angle") ?? dc.p("horizontal-angle"), title: L("摆头角度", "Angle"), icon: "angle", tint: tint)
                PropTile(dc: dc, prop: dc.p("physical-controls-locked"), title: L("童锁", "Child lock"), icon: "lock", tint: tint)
            }
        }
    }
}

// MARK: 灯
struct LightDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, on = m.powerInfo(d)?.isOn ?? false
        let bri = dc.p("brightness"), ct = dc.p("color-temperature")
        let k = dc.num(ct)
        let tint = on ? kelvinColor(k ?? 3500) : Color.yellow
        TypeShell(device: d, tint: Color.orange, isOn: on, title: on ? L("已开灯", "On") : L("已关灯", "Off"),
                  subtitle: joined([L("灯", "Light"), k.map { "\(Int($0))K" }, dc.text(dc.p("mode", in: "light"))]),
                  powerOn: on, onPower: powerHandler(m, d)) {
            BulbArt(on: on, brightness: propFraction(bri, dc.num(bri)), kelvin: k)
        } content: {
            BigValue(value: dc.num(bri).map { "\(Int($0))" }, unit: "%", caption: L("亮度", "Brightness"), dim: !on)
            if let bri { PropSlider(dc: dc, prop: bri, colors: [Color(red: 0.45, green: 0.38, blue: 0.28), Color(red: 1, green: 0.78, blue: 0.35), Color(red: 1, green: 0.96, blue: 0.85)], enabled: on) }
            HStack(spacing: 8) {
                if let ct, let r = ct.range, r.count >= 2 {
                    let clamp = { (v: Double) in min(max(v, r[0]), r[1]) }
                    PresetTile(dc: dc, prop: ct, title: L("色温", "Color temp"), icon: "thermometer.sun", tint: tint,
                               presets: [(L("暖光", "Warm"), clamp(2700)), (L("柔和", "Soft"), clamp(3500)), (L("自然", "Neutral"), clamp(4500)), (L("冷白", "Cool"), clamp(6500))])
                }
                if let mode = dc.p("mode", in: "light"), (mode.options?.count ?? 0) > 1 {
                    PropTile(dc: dc, prop: mode, title: L("场景", "Scene"), icon: "sparkles", tint: tint)
                }
                if let bri {
                    PresetTile(dc: dc, prop: bri, title: L("亮度预设", "Presets"), icon: "sun.max", tint: tint,
                               presets: [(L("夜灯 10%", "10%"), 10), (L("柔光 40%", "40%"), 40), (L("明亮 70%", "70%"), 70), (L("最亮 100%", "100%"), 100)])
                }
            }
        }
    }
}

// MARK: 插座
struct PlugDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.green
        let on = m.powerInfo(d)?.isOn ?? false
        let w = dc.num(dc.p("electric-power"))
        TypeShell(device: d, tint: tint, isOn: on, title: on ? L("通电中", "Powered") : L("已断电", "Off"),
                  subtitle: joined([L("智能插座", "Smart plug"), dc.text(dc.p("fault")).flatMap { $0 == trValue("No Faults") ? nil : $0 }]),
                  powerOn: on, onPower: powerHandler(m, d)) {
            PlugArt(on: on, watts: w, tint: tint)
        } content: {
            BigValue(value: w.map { fmt1($0) }, unit: "W", caption: L("实时功率", "Power"), dim: !on)
            ReadoutRow(items: [("thermometer.medium", dc.num(dc.p("temperature")).map { "\(Int($0))°C" }),
                               ("chart.bar.fill", dc.num(dc.p("power-consumption")).map { L("累计 ", "Total ") + fmt1($0) })], tint: tint)
            HStack(spacing: 8) {
                PropTile(dc: dc, prop: dc.p("on", in: "indicator-light"), title: L("指示灯", "Indicator"), icon: "lightbulb.led", tint: tint)
                PropTile(dc: dc, prop: dc.p("physical-controls-locked"), title: L("童锁", "Child lock"), icon: "lock", tint: tint)
                PresetTile(dc: dc, prop: dc.p("default-power-on-state"), title: L("来电状态", "Power-on"), icon: "arrow.clockwise.circle", tint: tint,
                           presets: [(L("断电", "Off"), 0), (L("通电", "On"), 1), (L("记忆", "Last"), 2)])
            }
            PowerHistoryCard(device: d, tint: tint)
        }
    }
}

// MARK: 电视
struct TVDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.indigo
        let on = d.isOnline
        let playP = dc.p("playing-state")
        let playing = dc.v(playP)?.doubleValue == Double(playP?.options?.first { $0.description.lowercased() == "playing" }?.value ?? -1)
        let vol = dc.p("volume", in: "speaker") ?? dc.p("volume")
        let input = dc.p("input-control")
        TypeShell(device: d, tint: tint, isOn: on, title: on ? (dc.text(playP) ?? L("已开机", "On")) : L("已关机", "Off"),
                  subtitle: joined([L("电视", "TV"), dc.text(input).map { L("信号源 ", "Input ") + $0 }]),
                  powerOn: on, onPower: dc.a("turn-off", in: "television").map { a in { m.runAction(d, a) } }) {
            TVArt(on: on, playing: playing, tint: tint)
        } content: {
            if let vol {
                VolumeControl(value: dc.num(vol), range: propRange(vol).0, tint: tint, enabled: on) { v in m.write(d, vol.key, PropValue.double(v).coerced(to: vol.format)) }
            }
            HStack(spacing: 8) {
                PropTile(dc: dc, prop: input, title: L("信号源", "Input"), icon: "rectangle.connected.to.line.below", tint: tint)
                PropTile(dc: dc, prop: dc.p("mute", in: "speaker"), title: L("静音", "Mute"), icon: "speaker.slash", tint: tint)
                if let a = dc.a(playing ? "pause" : "play", in: "play-control") {
                    ActionTile(title: playing ? L("暂停", "Pause") : L("播放", "Play"), icon: playing ? "pause.fill" : "play.fill", tint: tint) { m.runAction(d, a) }
                }
                PropTile(dc: dc, prop: dc.p("no-disturb"), title: L("免打扰", "Do not disturb"), icon: "moon", tint: tint)
            }
        }
    }
}

// MARK: 音箱
struct SpeakerDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.pink
        let playP = dc.p("playing-state")
        let playing = dc.v(playP)?.doubleValue == Double(playP?.options?.first { $0.description.lowercased() == "playing" }?.value ?? -1)
        let vol = dc.p("volume", in: "speaker") ?? dc.p("volume")
        TypeShell(device: d, tint: tint, isOn: playing, title: dc.text(playP) ?? (d.isOnline ? L("在线", "Online") : L("离线", "Offline")),
                  subtitle: joined([L("智能音箱", "Speaker"), dc.bool(dc.p("mute", in: "speaker")) == true ? L("已静音", "Muted") : nil])) {
            SpeakerArt(playing: playing, volume: propFraction(vol, dc.num(vol)), tint: tint)
        } content: {
            if let vol {
                VolumeControl(value: dc.num(vol), range: propRange(vol).0, tint: tint, enabled: d.isOnline) { v in m.write(d, vol.key, PropValue.double(v).coerced(to: vol.format)) }
            }
            HStack(spacing: 8) {
                if let a = dc.a("previous") { ActionTile(title: L("上一首", "Previous"), icon: "backward.fill", tint: tint) { m.runAction(d, a) } }
                if let a = dc.a(playing ? "pause" : "play", in: "play-control") {
                    ActionTile(title: playing ? L("暂停", "Pause") : L("播放", "Play"), icon: playing ? "pause.fill" : "play.fill", tint: tint, active: playing) { m.runAction(d, a) }
                }
                if let a = dc.a("next") { ActionTile(title: L("下一首", "Next"), icon: "forward.fill", tint: tint) { m.runAction(d, a) } }
                PropTile(dc: dc, prop: dc.p("mute", in: "speaker"), title: L("静音", "Mute"), icon: "speaker.slash", tint: tint)
            }
        }
    }
}

// MARK: 摄像机 / 门铃
struct CameraDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    @State private var watching = LiveControls.snapshotWatching
    var body: some View {
        let d = dc.device, tint = Color.purple
        let pw = m.powerInfo(d)
        let on = pw?.isOn ?? d.isOnline
        TypeShell(device: d, tint: tint, isOn: on, title: on ? L("监控中", "Watching") : L("隐私模式", "Privacy mode"),
                  subtitle: joined([d.form == .doorbell ? L("智能门铃", "Doorbell") : L("摄像机", "Camera"), dc.text(dc.p("status", in: "video-doorbell"))]),
                  powerOn: on, onPower: powerHandler(m, d), artInteractive: true) {
            CameraLiveArt(device: d, watching: $watching) {
                if d.form == .doorbell { DoorbellArt(on: on, tint: tint) } else { CameraArt(on: on, tint: tint) }
            }
        } content: {
            LiveControls(device: d, watching: $watching, tint: tint)
            ReadoutRow(items: [("sdcard.fill", dc.text(dc.p("status", in: "memory-card-management")).map { L("存储卡 ", "SD ") + $0 }),
                               ("battery.75percent", dc.num(dc.p("battery-level")).map { L("电量 ", "Battery ") + "\(Int($0))%" })], tint: tint)
            HStack(spacing: 8) {
                PropTile(dc: dc, prop: dc.p("night-shot"), title: L("夜视", "Night"), icon: "moon.stars", tint: tint)
                PropTile(dc: dc, prop: dc.p("motion-detection", in: "motion-detection"), title: L("移动侦测", "Motion"), icon: "figure.walk.motion", tint: tint)
                PropTile(dc: dc, prop: dc.p("recording-mode"), title: L("录制", "Record"), icon: "record.circle", tint: tint)
                PropTile(dc: dc, prop: dc.p("on", in: "indicator-light"), title: L("指示灯", "Indicator"), icon: "lightbulb.led", tint: tint)
            }
        }
    }
}

// MARK: 打印机
struct PrinterDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.blue
        let st = dc.p("status", in: "printer")
        let raw = dc.v(st).flatMap { v in st?.options?.first { Double($0.value) == v.doubleValue }?.description.lowercased() }
        TypeShell(device: d, tint: tint, isOn: raw == "processing", title: dc.text(st) ?? (d.isOnline ? L("在线", "Online") : L("离线", "Offline")),
                  subtitle: L("打印机", "Printer")) {
            PrinterArt(busy: raw == "processing", error: raw == "error", tint: tint)
        } content: {
            BigValue(value: dc.text(st), caption: L("打印机状态", "Status"))
            ReadoutRow(items: [("doc.on.doc.fill", dc.num(dc.p("printed-page")).map { L("已打印 ", "Printed ") + "\(Int($0)) " + L("页", "pages") })], tint: tint)
            HStack(spacing: 8) {
                PropTile(dc: dc, prop: dc.p("auto-sleep-mode"), title: L("自动休眠", "Auto sleep"), icon: "zzz", tint: tint)
            }
            Text(L("墨水余量需要在米家 App 中查看", "Ink levels are only available in the Mi Home app")).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

// MARK: 厨房电器（多功能锅、电磁炉、料理机等）
struct CookerDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.orange
        let st = dc.p("status")
        let raw = dc.v(st).flatMap { v in st?.options?.first { Double($0.value) == v.doubleValue }?.description.lowercased() } ?? ""
        let cooking = ["default", "cooking", "heating", "keepwarm", "keep warm", "boiling", "working", "busy"].contains(raw)
        let left = dc.num(dc.p("left-time"))
        TypeShell(device: d, tint: tint, isOn: cooking, title: dc.text(st) ?? (d.isOnline ? L("在线", "Online") : L("离线", "Offline")),
                  subtitle: joined([L("厨房电器", "Kitchen"), dc.text(dc.p("mode"))])) {
            CookerArt(cooking: cooking, tint: tint)
        } content: {
            if let left, left > 0 { BigValue(value: "\(Int(left))", unit: L("分钟", "min"), caption: L("剩余时间", "Remaining")) }
            else { BigValue(value: dc.text(st), caption: L("当前状态", "Status")) }
            ReadoutRow(items: [("thermometer.medium", dc.num(dc.p("temperature")).map { "\(Int($0))°C" }),
                               ("target", dc.num(dc.p("target-temperature")).map { L("目标 ", "Target ") + "\(Int($0))°C" }),
                               ("flame.fill", dc.num(dc.p("heat-level")).map { L("火力 ", "Heat ") + "\(Int($0))" })], tint: tint)
            HStack(spacing: 8) {
                PropTile(dc: dc, prop: dc.p("mode"), title: L("模式", "Mode"), icon: "fork.knife", tint: tint)
                PropTile(dc: dc, prop: dc.p("alarm"), title: L("提示音", "Sound"), icon: "bell", tint: tint)
            }
        }
    }
}

// MARK: 净水器
struct PurifierDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.blue
        let all = dc.spec?.controlServices.flatMap(\.properties) ?? []
        let tds = all.filter { $0.name.contains("tds") }
        let filters = all.filter { $0.name.contains("filter-life") }
        let minFilter = filters.compactMap { dc.num($0) }.min()
        TypeShell(device: d, tint: tint, isOn: d.isOnline, title: d.isOnline ? L("正常运行", "Running") : L("离线", "Offline"), subtitle: L("净水器", "Water purifier")) {
            PurifierArt(on: d.isOnline, filter: minFilter, tint: tint)
        } content: {
            BigValue(value: (tds.first { $0.name.contains("out") } ?? tds.first).flatMap { dc.num($0) }.map { "\(Int($0))" }, unit: "ppm", caption: L("净水 TDS", "Pure water TDS"))
            ReadoutRow(items: [("drop", tds.first { $0.name.contains("in") }.flatMap { dc.num($0) }.map { L("原水 ", "Tap ") + "\(Int($0))" }),
                               ("aqi.medium", minFilter.map { L("滤芯 ", "Filter ") + "\(Int($0))%" })], tint: tint)
            if dc.spec == nil {
                Text(L("这个型号没有公开的 MIoT 规格，只能显示在线状态", "No public MIoT spec; only online state is available")).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }
}

struct HumidifierDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let device = dc.device, tint = device.category.color
        let on = m.powerInfo(device)?.isOn ?? false
        let target = dc.p("target-humidity")
        TypeShell(device: device, tint: tint, isOn: on, title: on ? L("运行中", "Running") : L("已关闭", "Off"),
                  subtitle: joined([L("加湿器", "Humidifier"), dc.text(dc.p("mode"))]),
                  powerOn: on, onPower: powerHandler(m, device)) {
            HumidifierArt(on: on, tint: tint)
        } content: {
            if let target {
                BigValue(value: dc.num(target).map { "\(Int($0))" }, unit: "%", caption: L("目标湿度", "Target humidity"), dim: !on)
                if target.writable { PropSlider(dc: dc, prop: target, colors: [Theme.heat, .cyan, Theme.cool], enabled: on) }
            }
            ReadoutRow(items: [("humidity.fill", dc.num(dc.p("relative-humidity")).map { L("湿度 ", "Humidity ") + "\(Int($0))%" })], tint: tint)
            HStack(spacing: 8) {
                PropTile(dc: dc, prop: dc.p("mode"), title: L("模式", "Mode"), icon: "slider.horizontal.3", tint: tint)
                PropTile(dc: dc, prop: dc.p("fan-level"), title: L("风速", "Fan"), icon: "wind", tint: tint)
                PropTile(dc: dc, prop: dc.p("physical-controls-locked"), title: L("童锁", "Child lock"), icon: "lock", tint: tint)
            }
        }
    }
}

enum VacuumCommand: CaseIterable {
    case start, stop, charge
    var names: [String] {
        switch self {
        case .start: return ["start-sweep", "start"]
        case .stop: return ["stop-sweeping", "stop"]
        case .charge: return ["start-charge", "charge", "dock"]
        }
    }
    var title: String {
        switch self {
        case .start: return L("开始清扫", "Start cleaning")
        case .stop: return L("停止", "Stop")
        case .charge: return L("回充", "Dock")
        }
    }
    var icon: String {
        switch self {
        case .start: return "play.fill"
        case .stop: return "stop.fill"
        case .charge: return "house.fill"
        }
    }
    func action(in dc: DC) -> SpecAction? {
        let actions = dc.spec?.controlServices.flatMap(\.actions) ?? []
        return names.lazy.compactMap { name in actions.first { $0.name == name && $0.inputs.isEmpty } }.first
    }
}

struct VacuumDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let device = dc.device, tint = device.category.color
        let power = m.powerInfo(device)
        let on = power?.isOn ?? device.isOnline
        let working = on && HouseDeviceState.busy(dc.state, otherwise: false)
        let status = dc.text(dc.p("status"))
        TypeShell(device: device, tint: tint, isOn: on,
                  title: !on ? L("已关闭", "Off") : status ?? (working ? L("运行中", "Running") : L("待机", "Idle")),
                  subtitle: L("扫地机", "Vacuum"), powerOn: power?.isOn, onPower: powerHandler(m, device)) {
            VacuumArt(on: on, busy: working, tint: tint)
        } content: {
            if let battery = dc.p("battery-level") {
                BigValue(value: dc.num(battery).map { "\(Int($0))" }, unit: "%", caption: L("电量", "Battery"), dim: !on)
            }
            HStack(spacing: 8) {
                ForEach(VacuumCommand.allCases, id: \.self) { command in
                    if let action = command.action(in: dc) {
                        ActionTile(title: command.title, icon: command.icon, tint: tint) { m.runAction(device, action) }
                            .disabled(!device.isOnline || m.busy.contains(device.did))
                    }
                }
            }
        }
    }
}

// MARK: 取暖器 / 除湿机
struct ApplianceDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, heater = d.category == .heater
        let tint = heater ? Theme.heat : Color.cyan
        let on = m.powerInfo(d)?.isOn ?? false
        let target = heater ? dc.p("target-temperature") : dc.p("target-humidity")
        let hum = dc.num(dc.p("relative-humidity"))
        let tankFull = dc.bool(dc.p("tank-full") ?? dc.p("water-tank-full"))
        TypeShell(device: d, tint: tint, isOn: on, title: on ? L("运行中", "Running") : L("已关闭", "Off"),
                  subtitle: joined([heater ? L("取暖器", "Heater") : L("除湿机", "Dehumidifier"), dc.text(dc.p("mode")), tankFull == true ? L("水箱已满", "Tank full") : nil]),
                  powerOn: on, onPower: powerHandler(m, d)) {
            ApplianceArt(kind: d.category, on: on, level: heater ? propFraction(target, dc.num(target)) : (tankFull == true ? 1 : max(0.15, (hum ?? 40) / 100 * 0.6)), tint: tint)
        } content: {
            BigValue(value: dc.num(target).map { "\(Int($0))" }, unit: heater ? "°C" : "%", caption: heater ? L("目标温度", "Target") : L("目标湿度", "Target humidity"), dim: !on)
            if let target { PropSlider(dc: dc, prop: target, colors: heater ? [Theme.cool, Color(red: 1, green: 0.85, blue: 0.4), Theme.heat] : [Theme.heat, .cyan, Theme.cool], enabled: on) }
            ReadoutRow(items: [("thermometer.medium", dc.num(dc.p("temperature")).map { L("室温 ", "Room ") + "\(PropValue.double($0))°C" }),
                               ("humidity.fill", hum.map { L("湿度 ", "Humidity ") + "\(Int($0))%" })], tint: tint)
            HStack(spacing: 8) {
                PropTile(dc: dc, prop: dc.p("mode"), title: L("模式", "Mode"), icon: "slider.horizontal.3", tint: tint)
                PropTile(dc: dc, prop: heater ? dc.p("heat-level") : dc.p("fan-level"), title: heater ? L("档位", "Level") : L("风速", "Fan"), icon: heater ? "flame" : "wind", tint: tint)
                PropTile(dc: dc, prop: dc.p("physical-controls-locked"), title: L("童锁", "Child lock"), icon: "lock", tint: tint)
                PropTile(dc: dc, prop: dc.p("alarm"), title: L("提示音", "Sound"), icon: "bell", tint: tint)
            }
        }
    }
}

// MARK: 传感器
struct SensorDetail: View {
    @EnvironmentObject var m: AppModel
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.mint
        let t = dc.num(dc.p("temperature")), h = dc.num(dc.p("relative-humidity"))
        if dc.p("contact-state") != nil || d.form == .contact { ContactSensorDetail(dc: dc) }
        else if dc.p("submersion-state") != nil || d.form == .leak { LeakSensorDetail(dc: dc) }
        else if dc.p("temperature") == nil { MotionSensorDetail(dc: dc) } else {
        TypeShell(device: d, tint: tint, isOn: d.isOnline, title: d.isOnline ? L("在线", "Online") : L("离线", "Offline"), subtitle: L("传感器", "Sensor")) {
            ThermoArt(temp: t, tint: tint)
        } content: {
            HStack {
                BigValue(value: t.map { fmt1($0) }, unit: "°C", caption: L("温度", "Temperature"))
                if h != nil || dc.p("relative-humidity") != nil { BigValue(value: h.map { "\(Int($0))" }, unit: "%", caption: L("湿度", "Humidity")) }
            }
            ReadoutRow(items: [("battery.75percent", dc.num(dc.p("battery-level")).map { L("电量 ", "Battery ") + "\(Int($0))%" })], tint: tint)
            if dc.p("temperature") != nil { SensorHistoryCard(device: d, metric: "temperature", title: L("温度记录", "Temperature history"), style: .line(unit: "°C"), tint: .orange) }
            if dc.p("relative-humidity") != nil { SensorHistoryCard(device: d, metric: "humidity", title: L("湿度记录", "Humidity history"), style: .line(unit: "%"), tint: .blue) }
            if d.isBLE && t == nil {
                Text(L("蓝牙设备的读数经网关同步，可能有延迟", "BLE readings sync via gateway and may be delayed")).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        }
    }
}

/// 人体 / 门窗等无温度的传感器
struct MotionSensorDetail: View {
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.mint
        let lux = dc.num(dc.p("illumination"))
        TypeShell(device: d, tint: tint, isOn: d.isOnline, title: d.isOnline ? L("在线", "Online") : L("离线", "Offline"), subtitle: L("传感器", "Sensor")) {
            MotionSensorArt(on: d.isOnline, tint: tint)
        } content: {
            BigValue(value: lux.map { "\(Int($0))" }, unit: "lux", caption: L("光照", "Illuminance"))
            ReadoutRow(items: [("battery.75percent", dc.num(dc.p("battery-level")).map { L("电量 ", "Battery ") + "\(Int($0))%" })], tint: tint)
            if dc.p("illumination") != nil { SensorHistoryCard(device: d, metric: "illumination", title: L("光照记录", "Illuminance history"), style: .line(unit: " lux"), tint: .yellow) }
            Text(L("人体移动事件请在米家 App 中查看", "Motion events are shown in the Mi Home app")).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}

/// 门窗传感器：标题说门窗开着还是关着（contact-state 为 true 表示两块贴合，即关着）
struct ContactSensorDetail: View {
    let dc: DC
    var body: some View {
        let d = dc.device, tint = Color.mint
        let open = dc.bool(dc.p("contact-state")).map { !$0 }
        let title = !d.isOnline ? L("离线", "Offline") : open.map { $0 ? L("已打开", "Open") : L("已关闭", "Closed") } ?? L("在线", "Online")
        TypeShell(device: d, tint: tint, isOn: d.isOnline, title: title, subtitle: L("门窗传感器", "Door & window sensor")) {
            ContactSensorArt(on: d.isOnline, open: open, tint: tint)
        } content: {
            ReadoutRow(items: [("battery.75percent", dc.num(dc.p("battery-level")).map { L("电量 ", "Battery ") + "\(Int($0))%" })], tint: tint)
            SensorHistoryCard(device: d, metric: "contact", title: L("开合记录", "Open / close history"), style: .state(on: L("关闭", "Closed"), off: L("打开", "Opened")), tint: tint)
        }
    }
}

/// 水浸传感器：检测到浸水时整张卡片换成橙色警示
struct LeakSensorDetail: View {
    let dc: DC
    var body: some View {
        let d = dc.device
        let wet = dc.bool(dc.p("submersion-state"))
        let tint = wet == true ? Color.orange : Color.mint
        let title = !d.isOnline ? L("离线", "Offline") : wet.map { $0 ? L("检测到浸水", "Water detected") : L("无浸水", "No water") } ?? L("在线", "Online")
        TypeShell(device: d, tint: tint, isOn: d.isOnline, title: title, subtitle: L("水浸传感器", "Water leak sensor")) {
            LeakSensorArt(on: d.isOnline, wet: wet, tint: tint)
        } content: {
            ReadoutRow(items: [("battery.75percent", dc.num(dc.p("battery-level")).map { L("电量 ", "Battery ") + "\(Int($0))%" })], tint: tint)
            SensorHistoryCard(device: d, metric: "leak", title: L("浸水记录", "Leak history"), style: .state(on: L("检测到浸水", "Water detected"), off: L("恢复正常", "Dry again")), tint: .orange)
        }
    }
}
