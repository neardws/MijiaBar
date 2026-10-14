import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers
import MijiaCore

/// 演示数据 + 离屏截图（`MijiaBar --snapshot <dir>`），README 截图由此生成，不含任何真实设备信息
extension AppModel {
    func loadMock() {
        session = Session(userId: "demo", ssecurity: "", serviceToken: "", region: "cn")
        homes = [Home(id: "h1", name: L("我的家", "My Home"), ownerId: "0", rooms: []), Home(id: "h2", name: L("父母家", "Parents"), ownerId: "0", rooms: [])]
        func dev(_ id: String, _ n: String, _ model: String, _ room: String, online: Bool = true) -> Device {
            Device(did: id, name: n, model: model, isOnline: online, homeId: "h1", homeName: "", roomName: room)
        }
        devices = [
            dev("d1", L("客厅空调", "Living room AC"), "lumi.acpartner.mcn02", L("客厅", "Living room")),
            dev("d2", L("卧室空调", "Bedroom AC"), "lumi.acpartner.mcn02", L("主卧", "Bedroom")),
            dev("d3", L("落地灯", "Floor lamp"), "yeelink.light.mbulb3", L("客厅", "Living room")),
            dev("d4", L("循环扇", "Circulator fan"), "xiaomi.fan.p51", L("主卧", "Bedroom")),
            dev("d5", L("智能插座", "Smart plug"), "cuco.plug.v3", L("书房", "Study")),
            dev("d6", L("温湿度计", "Thermometer"), "miaomiaoce.sensor_ht.t2", L("书房", "Study")),
            dev("d7", L("除湿机", "Dehumidifier"), "dmaker.derh.22l", L("书房", "Study")),
            dev("d8", L("旧摄像头", "Old camera"), "chuangmi.camera.v2", L("阳台", "Balcony"), online: false),
            dev("d9", L("旧打印机", "Old printer"), "hannto.printer.honey", L("书房", "Study"), online: false),
            dev("d10", L("客厅摄像机", "Living room camera"), "chuangmi.camera.demo", L("客厅", "Living room")),
            dev("d11", L("智能门铃", "Doorbell"), "madv.cateye.demo", L("门口", "Entrance")),
        ]
        prefs.devices["d1"] = { var p = DevicePrefs(); p.favorite = true; return p }()
        prefs.devices["d2"] = { var p = DevicePrefs(); p.favorite = true; return p }()
        prefs.devices["d3"] = { var p = DevicePrefs(); p.favorite = true; return p }()
        states["d1"] = DeviceState(values: ["power": .string("on"), "mode": .string("cool"), "tar_temp": .int(24), "fan_level": .string("large_fan"),
                                            "ver_swing": .string("on"), "load_power": .double(680)], spec: nil, legacy: true, source: "lan")
        states["d2"] = DeviceState(values: ["power": .string("off"), "mode": .string("heat"), "tar_temp": .int(27), "fan_level": .string("auto_fan"),
                                            "ver_swing": .string("off"), "load_power": .double(1)], spec: nil, legacy: true, source: "lan")
        func P(_ s: Int, _ i: Int, _ t: String, _ f: String, _ acc: [String] = ["read", "write"], range: [Double]? = nil, opts: [ValueOption]? = nil, unit: String? = nil) -> SpecProperty {
            SpecProperty(siid: s, iid: i, type: "urn:miot-spec-v2:property:\(t):0", description: t, format: f, access: acc, unit: unit, range: range, options: opts)
        }
        func S(_ i: Int, _ t: String, _ p: [SpecProperty]) -> SpecService { SpecService(iid: i, type: "urn:miot-spec-v2:service:\(t):0", description: t, properties: p, actions: []) }
        let light = DeviceSpec(type: "urn:miot-spec-v2:device:light:0", description: "Light", services: [
            S(2, "light", [P(2, 1, "on", "bool"), P(2, 2, "brightness", "uint8", range: [1, 100, 1], unit: "percentage"),
                           P(2, 3, "color-temperature", "uint32", range: [2700, 6500, 1], unit: "kelvin"),
                           P(2, 4, "mode", "uint8", opts: [ValueOption(value: 0, description: "Day"), ValueOption(value: 1, description: "Night")])])])
        states["d3"] = DeviceState(values: ["2.1": .bool(true), "2.2": .int(72), "2.3": .int(3800), "2.4": .int(0)], spec: light, legacy: false, source: "cloud")
        let fan = DeviceSpec(type: "", description: "", services: [S(2, "fan", [P(2, 1, "on", "bool"),
            P(2, 2, "fan-level", "uint8", opts: [1, 2, 3, 4].map { ValueOption(value: $0, description: "Level\($0)") }), P(2, 4, "horizontal-swing", "bool")])])
        states["d4"] = DeviceState(values: ["2.1": .bool(false), "2.2": .int(2), "2.4": .bool(true)], spec: fan, legacy: false, source: "cloud")
        let plug = DeviceSpec(type: "", description: "", services: [S(2, "switch", [P(2, 1, "on", "bool")]), S(11, "power-consumption", [P(11, 2, "electric-power", "float", ["read"], unit: "watt")])])
        states["d5"] = DeviceState(values: ["2.1": .bool(true), "11.2": .double(36.5)], spec: plug, legacy: false, source: "cloud")
        let ht = DeviceSpec(type: "", description: "", services: [S(2, "temperature-humidity-sensor", [P(2, 1, "temperature", "float", ["read"], unit: "celsius"), P(2, 2, "relative-humidity", "uint8", ["read"], unit: "percentage")])])
        states["d6"] = DeviceState(values: ["2.1": .double(25.6), "2.2": .int(58)], spec: ht, legacy: false, source: "cloud")
        let derh = DeviceSpec(type: "", description: "", services: [S(2, "dehumidifier", [P(2, 1, "on", "bool"), P(2, 5, "target-humidity", "uint8", range: [40, 70, 5], unit: "percentage")])])
        states["d7"] = DeviceState(values: ["2.1": .bool(false), "2.5": .int(50)], spec: derh, legacy: false, source: "cloud")
        let cam = DeviceSpec(type: "", description: "", services: [S(2, "camera-control", [P(2, 1, "on", "bool"), P(2, 3, "night-shot", "uint8", opts: [ValueOption(value: 0, description: "Auto"), ValueOption(value: 1, description: "Off"), ValueOption(value: 2, description: "On")])])])
        states["d10"] = DeviceState(values: ["2.1": .bool(true), "2.3": .int(0)], spec: cam, legacy: false, source: "cloud")
        let bell = DeviceSpec(type: "", description: "", services: [S(2, "battery", [P(2, 1, "battery-level", "uint8", ["read"], range: [0, 100, 1], unit: "percentage")])])
        states["d11"] = DeviceState(values: ["2.1": .int(64)], spec: bell, legacy: false, source: "cloud")
        for d in devices { if let st = states[d.did], let t = Transport.from(st.source, device: d) { transports[d.did] = t } }
    }
}

/// 所有插画的开/关对照（自检用，不进 README）：没有演示设备的类型也能检查画风是否统一
struct ArtGallery: View {
    static let size = CGSize(width: 480, height: 1794)
    var body: some View {
        let rows: [(String, AnyView, AnyView)] = [
            ("fan", AnyView(FanArt(on: true, level: 0.5, swing: false, tint: .teal)), AnyView(FanArt(on: false, level: 0.5, swing: false, tint: .teal))),
            ("bulb", AnyView(BulbArt(on: true, brightness: 0.7, kelvin: 3800)), AnyView(BulbArt(on: false, brightness: 0.7, kelvin: 3800))),
            ("plug", AnyView(PlugArt(on: true, watts: 36, tint: .green)), AnyView(PlugArt(on: false, watts: 36, tint: .green))),
            ("camera", AnyView(CameraArt(on: true, tint: .purple)), AnyView(CameraArt(on: false, tint: .purple))),
            ("tv", AnyView(TVArt(on: true, playing: true, tint: .indigo)), AnyView(TVArt(on: false, playing: false, tint: .indigo))),
            ("speaker", AnyView(SpeakerArt(playing: true, volume: 0.6, tint: .pink)), AnyView(SpeakerArt(playing: false, volume: 0.6, tint: .pink))),
            ("printer", AnyView(PrinterArt(busy: true, error: false, tint: .blue)), AnyView(PrinterArt(busy: false, error: false, tint: .blue))),
            ("cooker", AnyView(CookerArt(cooking: true, tint: .orange)), AnyView(CookerArt(cooking: false, tint: .orange))),
            ("purifier", AnyView(PurifierArt(on: true, filter: 72, tint: .blue)), AnyView(PurifierArt(on: false, filter: 72, tint: .blue))),
            ("heater", AnyView(ApplianceArt(kind: .heater, on: true, level: 0.6, tint: Theme.heat)), AnyView(ApplianceArt(kind: .heater, on: false, level: 0.6, tint: Theme.heat))),
            ("dehumidifier", AnyView(ApplianceArt(kind: .dehumidifier, on: true, level: 0.4, tint: .cyan)), AnyView(ApplianceArt(kind: .dehumidifier, on: false, level: 0.4, tint: .cyan))),
            ("thermo", AnyView(ThermoArt(temp: 25.6, tint: .mint)), AnyView(ThermoArt(temp: nil, tint: .mint))),
            ("motion", AnyView(MotionSensorArt(on: true, tint: .mint)), AnyView(MotionSensorArt(on: false, tint: .mint))),
        ]
        VStack(spacing: 0) {
            ForEach(rows, id: \.0) { r in
                HStack(spacing: 0) {
                    ForEach([r.1, r.2].indices, id: \.self) { i in
                        ZStack(alignment: .topLeading) {
                            [r.1, r.2][i].frame(width: 240, height: 136)
                            Text("\(r.0) · \(i == 0 ? "on" : "off")").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary).padding(4)
                        }.frame(width: 240, height: 138).clipped()
                    }
                }
            }
        }
        .background(Theme.bg)
    }
}

/// 应用图标的图形（`--icon` 生成 AppIcon，登录页也用它），按 size 等比缩放
struct AppMark: View {
    let size: CGFloat
    var body: some View {
        let u = size / 1024
        let shape = RoundedRectangle(cornerRadius: 230 * u, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.16, green: 0.42, blue: 1), Color(red: 1, green: 0.52, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(Color.black.opacity(0.12))
            Image(systemName: "house.fill").font(.system(size: 520 * u, weight: .semibold)).foregroundStyle(.white)
            Image(systemName: "snowflake").font(.system(size: 210 * u, weight: .bold)).foregroundStyle(Color(red: 0.2, green: 0.45, blue: 1)).offset(y: 70 * u)
        }
        .frame(width: size, height: size)
    }
}

@MainActor
enum Snapshot {
    static var appearance = NSAppearance(named: .darkAqua)
    static func render<V: View>(_ v: V, _ url: URL, size: CGSize = CGSize(width: 360, height: 560)) {
        let host = NSHostingView(rootView: v.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = appearance
        win.contentView = host
        win.setFrameOrigin(NSPoint(x: 40, y: 40))
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        host.layoutSubtreeIfNeeded()
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
            print("wrote \(url.path)")
        }
        win.orderOut(nil)
    }

    static func qr(_ s: String) -> NSImage {
        let f = CIFilter.qrCodeGenerator(); f.message = Data(s.utf8)
        let img = f.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let rep = NSCIImageRep(ciImage: img); let n = NSImage(size: rep.size); n.addRepresentation(rep); return n
    }

    static func run(dir: String, liveQR: Bool) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir); try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        if CommandLine.arguments.contains("--real") {
            // 真实登录数据（只读），用于本机自检，不要提交
            let m = AppModel()
            let root = RootView().environmentObject(m)
            func wait(_ secs: Double, until: () -> Bool = { false }) {
                let end = Date().addingTimeInterval(secs)
                while Date() < end && !until() { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            }
            appearance = NSAppearance(named: .aqua)
            m.page = .list
            render(root, out.appendingPathComponent("warmup.png")); wait(10)
            var picks: [Device] = []
            for c in [DeviceCategory.ac, .light, .plug, .fan, .sensor, .heater, .dehumidifier, .speaker, .camera, .tv, .printer, .purifier, .other, .kitchen] {
                if let d = m.devices.first(where: { $0.category == c && $0.isOnline && $0.homeId == m.currentHomeId }) ?? m.devices.first(where: { $0.category == c && $0.isOnline }) ?? m.devices.first(where: { $0.category == c }) { picks.append(d) }
            }
            for d in picks where m.states[d.did] == nil {
                var done = false
                Task { await m.loadState(d); done = true }
                wait(15) { done }
            }
            for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
                appearance = NSAppearance(named: name)
                m.page = .list; render(root, out.appendingPathComponent("real-list-\(suffix).png"))
                for d in picks { m.page = .detail(d.did); render(root, out.appendingPathComponent("real-\(d.category.rawValue)-\(suffix).png")) }
            }
            print(picks.map { "\($0.category.rawValue)=\($0.model)" }.joined(separator: " "))
            exit(0)
        }
        let m = AppModel(mock: true)
        let root = RootView().environmentObject(m)
        for (suffix, name) in [("light", NSAppearance.Name.aqua), ("dark", NSAppearance.Name.darkAqua)] {
            appearance = NSAppearance(named: name)
            func f(_ n: String) -> URL { out.appendingPathComponent("\(n)-\(suffix).png") }
            m.session = Session(userId: "demo", ssecurity: "", serviceToken: "", region: "cn")
            m.page = .list; m.showHidden = false; render(root, f("list"))
            m.page = .detail("d1"); render(root, f("ac-cool"))
            m.page = .detail("d2"); m.states["d2"]?.values["power"] = .string("on"); m.states["d2"]?.values["load_power"] = .double(1260); render(root, f("ac-heat"))
            m.states["d2"]?.values["power"] = .string("off")
            m.page = .detail("d3"); render(root, f("light"))
            m.page = .detail("d5"); render(root, f("plug"))
            m.page = .detail("d4"); m.states["d4"]?.values["2.1"] = .bool(true); render(root, f("fan"))
            m.states["d4"]?.values["2.1"] = .bool(false)   // 还原，否则深色那一轮的列表会多算一台开启
            m.page = .detail("d10"); render(root, f("camera"))
            m.atHome = false; render(root, f("camera-away")); m.atHome = nil
            LiveControls.snapshotWatching = true
            render(root, f("camera-live")); m.page = .detail("d11"); render(root, f("doorbell-live"))
            LiveControls.snapshotWatching = false
            render(ArtGallery(), f("art-gallery"), size: ArtGallery.size)
            m.page = .settings; render(root, f("settings")); render(AgentSettingsSection().padding(12).frame(maxHeight: .infinity, alignment: .top).background(Theme.bg).environmentObject(m), f("agent"), size: CGSize(width: 360, height: 420))
            m.page = .list; m.showHidden = true; render(root, f("list-hidden")); m.showHidden = false
            m.session = nil; m.qrImage = qr("https://github.com/neardws/MijiaBar"); m.loginStatus = L("打开米家 App 扫一扫，并在手机上确认登录", "Scan with the Mi Home app")
            render(root, f("login"))
        }
        if liveQR {
            // 真实请求 account.xiaomi.com 拿二维码（不轮询、不登录），验证二维码页面能渲染
            var done = false
            Task {
                do {
                    let ql = QRLogin(); let t = try await ql.start()
                    m.qrImage = NSImage(data: try await ql.image(t)); m.loginStatus = "live QR: " + t.qrURL.host!
                } catch { m.loginStatus = "live QR error: \(error.localizedDescription)" }
                done = true
            }
            while !done { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
            print(m.loginStatus)
            render(root, out.appendingPathComponent("login-live.png"))
        }
        exit(0)
    }

    /// 录一段空调卡片动画（制冷 → 制热 → 关机 → 开机），README 动图由此生成
    /// scene: ac（默认，README 动图）、fan、light、plug —— 用来逐帧检查各类设备的状态动画
    static func gif(to path: String, scene: String = "ac", fps: Double = 20) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let m = AppModel(mock: true)
        let size = CGSize(width: 360, height: 560)
        let host = NSHostingView(rootView: RootView().environmentObject(m).frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let d1 = m.device("d1"), let d2 = m.device("d2"), let d3 = m.device("d3"), let d4 = m.device("d4"), let d5 = m.device("d5") else { exit(1) }
        // (时间点, 动作)
        let scripts: [String: [(Double, () -> Void)]] = [
            "ac": [
                (0.4, { m.open(d1) }),
                (2.6, { m.write(d1, "mode", .string("heat")); m.write(d1, "tar_temp", .int(28)) }),
                (4.4, { m.write(d1, "ver_swing", .string("off")) }),
                (5.4, { m.toggle(d1) }),
                (6.6, { m.toggle(d1) }),
                (8.2, { m.back() }),
                (9.2, { m.open(d2) }),
            ],
            // 风扇：开机加速 → 调到最高档 → 停止摆头 → 关机滑行
            "fan": [(0.4, { m.open(d4) }), (1.2, { m.toggle(d4) }), (3.4, { m.write(d4, "2.2", .int(4)) }),
                    (5.2, { m.write(d4, "2.4", .bool(false)) }), (6.6, { m.toggle(d4) })],
            // 灯：调暗 → 冷白 → 关灯 → 开灯
            "light": [(0.4, { m.open(d3) }), (1.6, { m.write(d3, "2.2", .int(20)) }), (3.0, { m.write(d3, "2.3", .int(6500)) }),
                      (4.6, { m.toggle(d3) }), (6.2, { m.toggle(d3) })],
            // 插座：大功率 → 断电 → 通电 → 小功率
            "plug": [(0.4, { m.open(d5) }), (1.8, { m.write(d5, "11.2", .double(1800)) }), (3.6, { m.toggle(d5) }),
                     (5.0, { m.toggle(d5) }), (6.6, { m.write(d5, "11.2", .double(3)) })],
        ]
        guard let script = scripts[scene] else { print("unknown scene \(scene); use ac, fan, light or plug"); exit(1) }
        // 截图本身较慢，按每帧实际耗时写入延迟，回放速度与真实一致
        var frames: [(CGImage, Double)] = []
        let total = scene == "ac" ? 10.4 : 9.0, start = Date()
        var next = 0, last = start
        while Date().timeIntervalSince(start) < total {
            while next < script.count, script[next].0 <= Date().timeIntervalSince(start) { script[next].1(); next += 1 }
            RunLoop.main.run(until: Date().addingTimeInterval(1 / fps))
            host.layoutSubtreeIfNeeded()
            // 1x 分辨率，控制动图体积
            if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                          samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
                rep.size = size
                host.cacheDisplay(in: host.bounds, to: rep)
                let now = Date()
                if let img = rep.cgImage { frames.append((img, now.timeIntervalSince(last))) }
                last = now
            }
        }
        guard let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else { exit(1) }
        CGImageDestinationSetProperties(dst, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (f, delay) in frames {
            CGImageDestinationAddImage(dst, f, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFUnclampedDelayTime: delay, kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        CGImageDestinationFinalize(dst)
        print("gif \(path) (\(frames.count) frames)")
        exit(0)
    }

    static func icon(to path: String) {
        let v = AppMark(size: 1024)
        let r = ImageRenderer(content: v.frame(width: 1024, height: 1024)); r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("icon \(path)")
        }
        exit(0)
    }
}
