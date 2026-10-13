import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import MijiaCore

/// 演示数据 + 离屏截图（`MijiaBar --snapshot <dir>`），README 截图由此生成，不含任何真实设备信息
extension AppModel {
    func loadMock() {
        session = Session(userId: "demo", ssecurity: "", serviceToken: "", region: "cn")
        homes = [Home(id: "h1", name: L("我的家", "My Home"), ownerId: "0", rooms: [])]
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
        ]
        prefs.devices["d1"] = { var p = DevicePrefs(); p.favorite = true; return p }()
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
    }
}

@MainActor
enum Snapshot {
    static func render<V: View>(_ v: V, _ url: URL, size: CGSize = CGSize(width: 360, height: 600)) {
        let host = NSHostingView(rootView: v.frame(width: size.width, height: size.height))
        host.frame = CGRect(origin: .zero, size: size)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
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
        let m = AppModel(mock: true)
        let root = RootView().environmentObject(m)
        m.page = .list; render(root, out.appendingPathComponent("list.png"))
        m.page = .detail("d1"); render(root, out.appendingPathComponent("ac-cool.png"))
        m.page = .detail("d2"); m.states["d2"]?.values["power"] = .string("on"); m.states["d2"]?.values["load_power"] = .double(1260); render(root, out.appendingPathComponent("ac-heat.png"))
        m.page = .detail("d3"); render(root, out.appendingPathComponent("light.png"))
        m.page = .settings; render(root, out.appendingPathComponent("settings.png"))
        m.page = .list; m.showHidden = true; render(root, out.appendingPathComponent("list-hidden.png")); m.showHidden = false
        m.session = nil; m.qrImage = qr("https://github.com/neardws/MijiaBar"); m.loginStatus = L("打开米家 App 扫一扫，并在手机上确认登录", "Scan with the Mi Home app")
        render(root, out.appendingPathComponent("login.png"))
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

    static func icon(to path: String) {
        let v = ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.42, blue: 1), Color(red: 1, green: 0.52, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            RoundedRectangle(cornerRadius: 230, style: .continuous).fill(Color.black.opacity(0.12)).padding(0)
            Image(systemName: "house.fill").font(.system(size: 520, weight: .semibold)).foregroundStyle(.white)
            Image(systemName: "snowflake").font(.system(size: 210, weight: .bold)).foregroundStyle(Color(red: 0.2, green: 0.45, blue: 1)).offset(y: 70)
        }.frame(width: 1024, height: 1024).padding(0)
        let r = ImageRenderer(content: v.frame(width: 1024, height: 1024)); r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            print("icon \(path)")
        }
        exit(0)
    }
}
