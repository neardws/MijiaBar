import SwiftUI
import AppKit
import WebKit
import MijiaCore

// MARK: 直播助手（内置 go2rtc，按需启动，只监听 127.0.0.1）
//
// 隐私设计：
// - 只在用户点「看直播」时启动；没有观看者 20 秒后停止；完全退出 App 时结束。
// - 配置文件 ~/Library/Application Support/MijiaBar/go2rtc.yaml 权限 0600，go2rtc 读入后立即删除。
// - 只开启 api / ws / mp4 / xiaomi 模块：没有 RTSP、WebRTC、HomeKit（因此也没有 mDNS）。
// - API 只放行静态播放器脚本和 /api/ws，其他接口（配置、流列表、小米登录）全部不注册。
// - 凭据来自钥匙串里的扫码会话（userId + passToken），不经过界面、不写日志。

enum LiveError: LocalizedError {
    case noHelper, noAuth, noIP, startFailed(String)
    var errorDescription: String? {
        switch self {
        case .noHelper: return L("没有找到内置的直播组件", "Built-in live video helper not found")
        case .noAuth: return L("需要重新扫码授权一次才能看直播", "Scan the QR code once more to enable live video")
        case .noIP: return L("设备列表里没有这台摄像头的局域网地址，请刷新后再试", "No local IP for this camera, refresh the device list and try again")
        case .startFailed(let s): return L("直播组件启动失败：", "Live video helper failed to start: ") + s
        }
    }
}

@MainActor
final class LiveManager: ObservableObject {
    static let shared = LiveManager()
    @Published private(set) var port: Int?
    @Published private(set) var did: String?
    private var proc: Process?
    private var viewers = 0
    private var stopTask: Task<Void, Never>?
    private var startTask: Task<Int, Error>?
    static let streamName = "cam"
    static let idleGrace: UInt64 = 20_000_000_000

    static var configURL: URL { Paths.support.appendingPathComponent("go2rtc.yaml") }
    static var pidURL: URL { Paths.support.appendingPathComponent("go2rtc.pid") }

    static var helperURL: URL? {
        if let p = ProcessInfo.processInfo.environment["MIJIABAR_GO2RTC"] { return URL(fileURLWithPath: p) }
        let u = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/bin/go2rtc")
        return FileManager.default.isExecutableFile(atPath: u.path) ? u : nil
    }

    static func streamURL(_ d: Device, _ s: Session) -> String? {
        guard let ip = d.ip, !ip.isEmpty else { return nil }
        var c = URLComponents()
        c.scheme = "xiaomi"; c.user = s.userId; c.password = s.region; c.host = ip
        c.queryItems = [.init(name: "did", value: d.did), .init(name: "model", value: d.model)]
        return c.string
    }

    /// YAML 双引号字符串。注意：配置解析失败时 go2rtc 会回退到默认配置（监听所有网卡），所以这里只做最保守的转义
    static func q(_ s: String) -> String {
        var o = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\\": o += "\\\\"
            case "\"": o += "\\\""
            case _ where u.value < 0x20 || u.value == 0x7f: o += String(format: "\\x%02X", u.value)
            default: o.unicodeScalars.append(u)
            }
        }
        return o + "\""
    }

    static func freePort() -> Int? {
        let fd = socket(AF_INET, SOCK_STREAM, 0); guard fd >= 0 else { return nil }
        defer { close(fd) }
        var a = sockaddr_in(); a.sin_family = sa_family_t(AF_INET); a.sin_addr.s_addr = inet_addr("127.0.0.1"); a.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let ok = withUnsafeMutablePointer(to: &a) { p in
            p.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        return ok ? Int(UInt16(bigEndian: a.sin_port)) : nil
    }

    /// 观看者进入：确保助手正在为这台设备运行，返回端口
    func acquire(_ d: Device, session: Session?) async throws -> Int {
        viewers += 1; stopTask?.cancel(); stopTask = nil
        if let port, did == d.did, proc?.isRunning == true { return port }
        if let t = startTask, did == d.did { return try await t.value }
        stopNow()
        did = d.did
        let t = Task { try await self.launch(d, session) }
        startTask = t
        defer { startTask = nil }
        do { let p = try await t.value; port = p; return p }
        catch { stopNow(); throw error }
    }

    /// 观看者离开：没人看了就在宽限期后停止
    func release() {
        viewers = max(0, viewers - 1)
        guard viewers == 0 else { return }
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: LiveManager.idleGrace)
            guard !Task.isCancelled else { return }
            self?.stopNow()
        }
    }

    func stopNow() {
        stopTask?.cancel(); stopTask = nil
        if let p = proc, p.isRunning { p.terminate() }
        proc = nil; port = nil; did = nil
        try? FileManager.default.removeItem(at: Self.configURL)
        try? FileManager.default.removeItem(at: Self.pidURL)
    }

    /// 上次异常退出残留的进程
    static func killStale() {
        guard let s = try? String(contentsOf: pidURL, encoding: .utf8), let pid = Int32(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        var buf = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &buf, UInt32(buf.count)) > 0, String(cString: buf).hasSuffix("/go2rtc") { kill(pid, SIGTERM) }
        try? FileManager.default.removeItem(at: pidURL)
    }

    private func launch(_ d: Device, _ s: Session?) async throws -> Int {
        guard let bin = Self.helperURL else { throw LiveError.noHelper }
        guard let s, let pass = s.passToken, !pass.isEmpty else { throw LiveError.noAuth }
        guard let src = Self.streamURL(d, s) else { throw LiveError.noIP }
        guard let port = Self.freePort() else { throw LiveError.startFailed("port") }
        Self.killStale()
        // 监听/模块设置走命令行内联配置（不含任何凭据）：即使下面的文件解析失败也不会回退到默认的全网卡监听
        let level = ProcessInfo.processInfo.environment["MIJIABAR_GO2RTC_LOG"] == nil ? "warn" : "debug"
        let safe = #"{"app":{"modules":["api","ws","mp4","xiaomi"]},"api":{"listen":"127.0.0.1:\#(port)","allow_paths":["/","/api/ws"]},"rtsp":{"listen":""},"webrtc":{"listen":""},"log":{"level":"\#(level)"}}"#
        let yaml = """
        xiaomi:
          \(Self.q(s.userId)): \(Self.q(pass))
        streams:
          \(Self.streamName):
            - \(Self.q(src))

        """
        let cfg = Self.configURL
        FileManager.default.createFile(atPath: cfg.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try Data(yaml.utf8).write(to: cfg)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cfg.path)

        let p = Process()
        p.executableURL = bin
        p.arguments = ["-config", safe, "-config", cfg.path]
        p.currentDirectoryURL = Paths.support
        // 不保留日志（日志里可能有设备地址）；开发时可用 MIJIABAR_GO2RTC_LOG=<文件> 输出
        if let lp = ProcessInfo.processInfo.environment["MIJIABAR_GO2RTC_LOG"] {
            FileManager.default.createFile(atPath: lp, contents: nil, attributes: [.posixPermissions: 0o600])
            p.standardOutput = FileHandle(forWritingAtPath: lp); p.standardError = p.standardOutput
        } else { p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice }
        try p.run()
        proc = p
        try? "\(p.processIdentifier)".write(to: Self.pidURL, atomically: true, encoding: .utf8)
        // 等待 API 就绪（go2rtc 启动时一次性读入配置，之后删除配置文件）
        let probe = URL(string: "http://127.0.0.1:\(port)/video-rtc.js")!
        for _ in 0..<50 {
            if !p.isRunning { break }
            if let (_, r) = try? await URLSession.shared.data(from: probe), (r as? HTTPURLResponse)?.statusCode == 200 {
                try? FileManager.default.removeItem(at: cfg)
                return port
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try? FileManager.default.removeItem(at: cfg)
        let msg = p.isRunning ? "timeout" : "exit \(p.terminationStatus)"
        p.terminate()
        throw LiveError.startFailed(msg)
    }
}

// MARK: 播放器（go2rtc 自带的 video-rtc.js，MSE 模式）

enum LivePhase: Equatable { case starting, loading, live, error(String), paused }

struct LiveWebView: NSViewRepresentable {
    let port: Int
    let onPhase: (LivePhase) -> Void

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onPhase: (LivePhase) -> Void
        init(_ f: @escaping (LivePhase) -> Void) { onPhase = f }
        func userContentController(_ c: WKUserContentController, didReceive msg: WKScriptMessage) {
            guard let s = msg.body as? String else { return }
            DispatchQueue.main.async {
                if s == "live" { self.onPhase(.live) }
                else if s == "loading" { self.onPhase(.loading) }
                else if s.hasPrefix("error:") { self.onPhase(.error(String(s.dropFirst(6)))) }
            }
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(onPhase) }
    /// 自检用：最近创建的播放器
    @MainActor static weak var last: WKWebView?

    func makeNSView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.userContentController.add(context.coordinator, name: "live")
        let w = WKWebView(frame: .zero, configuration: cfg)
        LiveWebView.last = w
        w.setValue(false, forKey: "drawsBackground")
        let html = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}
        live-player,video{display:block;width:100%;height:100%;object-fit:contain;background:#000}</style></head>
        <body><script type="module">
        import {VideoRTC} from './video-rtc.js';
        const post = s => window.webkit.messageHandlers.live.postMessage(s);
        class LivePlayer extends VideoRTC {
          oninit() {
            super.oninit();
            this.video.controls = false; this.video.muted = true;
            this.video.addEventListener('playing', () => post('live'));
            this.video.addEventListener('waiting', () => post('loading'));
          }
          onopen() {
            const r = super.onopen();
            this.onmessage['app'] = m => { if (m.type === 'error') post('error:' + m.value); };
            return r;
          }
        }
        customElements.define('live-player', LivePlayer);
        const p = document.createElement('live-player');
        p.mode = 'mse'; p.media = 'video,audio'; p.background = true;
        document.body.appendChild(p);
        p.src = '/api/ws?src=\(LiveManager.streamName)';
        post('loading');
        </script></body></html>
        """
        w.loadHTMLString(html, baseURL: URL(string: "http://127.0.0.1:\(port)/"))
        return w
    }
    func updateNSView(_ w: WKWebView, context: Context) { context.coordinator.onPhase = onPhase }
    static func dismantleNSView(_ w: WKWebView, coordinator: Coordinator) {
        w.configuration.userContentController.removeScriptMessageHandler(forName: "live")
        w.loadHTMLString("", baseURL: nil)
    }
}

/// 只在所在窗口真正可见时为 true（菜单栏面板收起后自动断开直播）
struct WindowVisibility: NSViewRepresentable {
    let onVisible: (Bool) -> Void
    final class V: NSView {
        var onChange: ((Bool) -> Void)?
        private var obs: [NSObjectProtocol] = []
        override func viewDidMoveToWindow() {
            obs.forEach(NotificationCenter.default.removeObserver); obs = []
            guard let w = window else { onChange?(false); return }
            for n in [NSWindow.didChangeOcclusionStateNotification, NSWindow.willCloseNotification] {
                obs.append(NotificationCenter.default.addObserver(forName: n, object: w, queue: .main) { [weak self] n2 in
                    let closing = n2.name == NSWindow.willCloseNotification
                    MainActor.assumeIsolated { self?.report(closing: closing) }
                })
            }
            DispatchQueue.main.async { [weak self] in self?.report(closing: false) }
        }
        func report(closing: Bool) {
            guard let w = window else { onChange?(false); return }
            onChange?(!closing && w.isVisible)  // 面板收起时窗口被 orderOut，isVisible 变为 false
        }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.onChange = onVisible; return v }
    func updateNSView(_ v: V, context: Context) { v.onChange = onVisible }
}

/// 直播画面 + 状态层；出现时占用助手，消失时释放
struct LivePlayerView: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    var cornerRadius: CGFloat = 14
    @State private var port: Int?
    @State private var phase: LivePhase = .starting
    @State private var visible = false
    @State private var holding = false
    @State private var attempt = 0
    static let maxWatch: UInt64 = 10 * 60 * 1_000_000_000
    /// 自检时允许在演示数据模式下真实启动
    static var realInMock = false

    var body: some View {
        ZStack {
            Color.black
            if let port, visible, phase != .paused {
                LiveWebView(port: port) { phase = $0; if Self.realInMock { print("phase \($0)") } }.id(attempt)
            }
            overlay
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .background(WindowVisibility { v in
            guard v != visible else { return }
            if Self.realInMock { print("visible \(v)") }
            visible = v; v ? start() : stop()
        })
        .onDisappear { stop() }
        .task(id: attempt) {
            // 连续观看 10 分钟自动暂停，节省流量和摄像头电量
            try? await Task.sleep(nanoseconds: Self.maxWatch)
            if !Task.isCancelled, phase == .live { phase = .paused; stop() }
        }
    }

    @ViewBuilder var overlay: some View {
        switch phase {
        case .live:
            VStack { HStack { LiveBadge(); Spacer() }; Spacer() }.padding(8)
        case .starting, .loading:
            VStack(spacing: 6) {
                ProgressView().controlSize(.small).tint(.white)
                Text(phase == .starting ? L("正在启动直播…", "Starting live view…") : L("正在连接摄像头…", "Connecting to camera…"))
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.8))
            }
        case .paused:
            retry(L("直播已自动暂停", "Live view paused"), icon: "pause.circle")
        case .error(let e):
            retry(e.isEmpty ? L("无法播放", "Can't play") : e, icon: "exclamationmark.triangle")
        }
    }
    func retry(_ text: String, icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(.white.opacity(0.8))
            Text(text).font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center).lineLimit(3).padding(.horizontal, 12)
            Button(L("重试", "Retry")) { phase = .starting; attempt += 1; start() }.controlSize(.small)
        }
    }

    func start() {
        if m.mock && !Self.realInMock { phase = .live; return }
        guard visible, !holding else { return }
        holding = true; phase = .starting
        Task {
            do {
                let p = try await LiveManager.shared.acquire(device, session: m.session)
                port = p; if phase == .starting { phase = .loading }
            } catch {
                if Self.realInMock { print("start error \(error.localizedDescription)") }
                phase = .error(error.localizedDescription); holding = false
                LiveManager.shared.release()
            }
        }
    }
    func stop() {
        guard holding else { return }
        holding = false; port = nil
        LiveManager.shared.release()
    }
}

struct LiveBadge: View {
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(.red).frame(width: 6, height: 6).opacity(pulse ? 0.35 : 1)
            Text(L("直播", "LIVE")).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(Capsule().fill(.black.opacity(0.55)))
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
    }
}

/// 详情卡片插画区：看直播时原地替换为画面，右上角「放大」弹出独立窗口
struct CameraLiveArt<Art: View>: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    @Binding var watching: Bool
    @ViewBuilder let art: () -> Art
    var body: some View {
        ZStack {
            if watching {
                LivePlayerView(device: device)
                    .overlay(alignment: .topTrailing) {
                        HStack(spacing: 4) {
                            chip("arrow.up.left.and.arrow.down.right", L("放大", "Enlarge")) {
                                watching = false; LiveWindow.open(device, model: m)
                            }
                            chip("xmark", L("停止直播", "Stop live view")) { withAnimation(Motion.smooth) { watching = false } }
                        }.padding(6)
                    }
                    .transition(.opacity)
            } else {
                art().transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: watching)
    }
    func chip(_ icon: String, _ help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(.black.opacity(0.55)))
        }.buttonStyle(.plain).help(help)
    }
}

/// 「看直播」按钮 + 门铃电量提醒
struct LiveControls: View {
    @EnvironmentObject var m: AppModel
    let device: Device
    @Binding var watching: Bool
    var tint: Color = .purple
    static var snapshotWatching = false
    var isDoorbell: Bool { device.model.contains(".cateye.") }
    var body: some View {
        VStack(spacing: 6) {
            Button {
                if watching { withAnimation(Motion.smooth) { watching = false }; return }
                if !m.mock, m.session?.canLiveStream != true { m.showToast(LiveError.noAuth.localizedDescription); m.openSettings(); return }
                withAnimation(Motion.smooth) { watching = true }
            } label: {
                Label(watching ? L("停止直播", "Stop live view") : L("看直播", "Watch live"), systemImage: watching ? "stop.fill" : "play.rectangle.fill")
                    .font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.16)))
                    .foregroundStyle(tint)
            }.buttonStyle(.plain).disabled(!device.isOnline)
            if isDoorbell {
                Label(L("门铃靠电池供电，看直播会唤醒设备并明显耗电，请尽量短时间观看", "The doorbell runs on battery. Live view wakes it up and drains the battery, keep it short"),
                      systemImage: "battery.25percent")
                    .font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 可调整大小的独立直播窗口
@MainActor
enum LiveWindow {
    static var windows: [String: NSWindow] = [:]
    static func open(_ d: Device, model: AppModel) {
        if let w = windows[d.did] { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let root = LivePlayerView(device: d, cornerRadius: 0).environmentObject(model)
            .frame(minWidth: 320, minHeight: 180).ignoresSafeArea()
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = model.displayName(d)
        w.titlebarAppearsTransparent = true
        w.contentAspectRatio = NSSize(width: 16, height: 9)
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: root)
        w.center()
        windows[d.did] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated {
                windows[d.did]?.contentView = nil
                windows[d.did] = nil
            }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

#if DEBUG
/// 开发自检：`MijiaBarApp --live-test <out.png> <model>`，凭据从环境变量 MIJIABAR_LIVE_YAML 指向的 go2rtc 配置里程序化读取（不打印）
@MainActor
enum LiveTest {
    static func run(out: String, model: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        guard let path = ProcessInfo.processInfo.environment["MIJIABAR_LIVE_YAML"], let text = try? String(contentsOfFile: path, encoding: .utf8) else { print("no yaml"); exit(2) }
        var uid = "", tok = "", inX = false
        for line in text.split(separator: "\n") {
            if line.hasPrefix("xiaomi:") { inX = true; continue }
            if inX, line.hasPrefix("  "), let i = line.firstIndex(of: ":") {
                uid = line[..<i].trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                tok = line[line.index(after: i)...].trimmingCharacters(in: CharacterSet(charactersIn: " \"'")); break
            } else if inX { inX = false }
        }
        guard !uid.isEmpty, !tok.isEmpty, let d = DeviceCache.load()?.devices.first(where: { $0.model == model }) else { print("no creds or device"); exit(2) }
        let m = AppModel(mock: true)
        m.session = Session(userId: uid, ssecurity: "", serviceToken: "", region: "cn", passToken: tok)
        LivePlayerView.realInMock = true
        let w = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 640, height: 360), styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        w.contentView = NSHostingView(rootView: LivePlayerView(device: d, cornerRadius: 0).environmentObject(m))
        w.orderFrontRegardless()
        let end = Date().addingTimeInterval(45)
        var grabbed = false
        func grab() {
            let js = "(()=>{const v=document.querySelector('video');if(!v||!v.videoWidth)return '';const c=document.createElement('canvas');c.width=v.videoWidth;c.height=v.videoHeight;c.getContext('2d').drawImage(v,0,0);return v.videoWidth+'x'+v.videoHeight+'|'+c.toDataURL('image/png');})()"
            LiveWebView.last?.evaluateJavaScript(js) { r, _ in
                guard let s = r as? String, let bar = s.firstIndex(of: "|"), let comma = s.firstIndex(of: ",") else { return }
                if let data = Data(base64Encoded: String(s[s.index(after: comma)...])) {
                    try? data.write(to: URL(fileURLWithPath: out)); print("frame \(s[..<bar]) -> \(out)"); grabbed = true
                }
            }
        }
        while Date() < end && !grabbed {
            RunLoop.main.run(until: Date().addingTimeInterval(1))
            if Date() > end.addingTimeInterval(-38) { grab() }
        }
        // 弹出窗口整体截图（含「直播」角标）
        if let host = w.contentView, let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out.replacingOccurrences(of: ".png", with: "-window.png")))
        }
        LiveManager.shared.stopNow()
        print(grabbed ? "ok" : "timeout")
        exit(grabbed ? 0 : 1)
    }
}
#endif
