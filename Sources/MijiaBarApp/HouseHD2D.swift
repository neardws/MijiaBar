import SwiftUI
import AppKit
import SceneKit
import MijiaCore

// MARK: - 数据模型

struct HouseDevice: Equatable {
    let did: String, name: String, kind: HouseSlotKind, slot: Int, on: Bool, online: Bool
}
struct HouseRoom: Equatable {
    let title: String, module: HouseModule, devices: [HouseDevice], overflow: Int
}

extension AppModel {
    /// 客厅试点：只取第一个客厅模块
    var houseLivingRoom: HouseRoom? {
        let hid = currentHomeId ?? ""
        let inHome = devices.filter { currentHomeId == nil || $0.homeId == currentHomeId }
        let groups = Dictionary(grouping: inHome) { $0.roomName ?? "" }
        for k in prefs.orderedRooms(home: hid, roomKeys: groups.keys) {
            guard HouseModule.from(roomName: k) == .living, let ds = groups[k] else { continue }
            let r = HouseLayout.assign(prefs.orderedDevices(home: hid, key: k, ds), in: .living)
            let placed = r.placed.map { d, s in
                HouseDevice(did: d.did, name: displayName(d), kind: s.kind, slot: s.index,
                            on: d.isOnline && (powerInfo(d)?.isOn ?? false), online: d.isOnline)
            }
            return HouseRoom(title: k, module: .living, devices: placed, overflow: r.overflow.count)
        }
        return nil
    }
}

// MARK: - SceneKit 场景

@MainActor
final class HouseHD2DScene: NSObject {
    let scene = SCNScene()
    let roomRoot = SCNNode()
    var deviceRoots: [String: SCNNode] = [:]
    private var lightNodes: [String: SCNNode] = [:]
    private var particleNodes: [String: SCNNode] = [:]
    private var tvScreen: SCNNode?
    private var lampLight: SCNLight?
    private var ambientNode = SCNNode()
    private let size = HouseLayout.livingRoomSize

    override init() {
        super.init()
        scene.background.contents = NSColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1)
        scene.rootNode.addChildNode(roomRoot)
        buildEnvironment()
        buildRoomShell()
        buildFurniture()
    }

    private func buildEnvironment() {
        // 远景光斑（billboard）
        for i in 0..<18 {
            let plane = SCNPlane(width: 0.8 + CGFloat(i % 5) * 0.15, height: 0.8 + CGFloat(i % 3) * 0.1)
            let m = SCNMaterial()
            let colors: [NSColor] = [
                NSColor(red: 1, green: 0.75, blue: 0.4, alpha: 1),
                NSColor(red: 0.45, green: 0.6, blue: 1, alpha: 1),
                NSColor(red: 0.9, green: 0.55, blue: 0.75, alpha: 1),
            ]
            m.diffuse.contents = colors[i % 3].withAlphaComponent(0.35)
            m.emission.contents = colors[i % 3]
            m.emission.intensity = 0.6
            m.lightingModel = .constant
            m.isDoubleSided = true
            m.blendMode = .add
            plane.materials = [m]
            let n = SCNNode(geometry: plane)
            n.position = SCNVector3(Float(-4 + (i % 6)), Float(2 + (i % 4)), Float(-8 - (i % 5)))
            n.constraints = [SCNBillboardConstraint()]
            n.opacity = 0.25
            scene.rootNode.addChildNode(n)
        }

        let amb = SCNLight()
        amb.type = .ambient
        amb.intensity = 120
        amb.color = NSColor(red: 0.55, green: 0.62, blue: 0.85, alpha: 1)
        ambientNode.light = amb
        scene.rootNode.addChildNode(ambientNode)

        let moon = SCNLight()
        moon.type = .directional
        moon.intensity = 450
        moon.color = NSColor(red: 0.75, green: 0.82, blue: 1, alpha: 1)
        moon.castsShadow = true
        moon.shadowMode = .deferred
        moon.shadowRadius = 4
        moon.shadowSampleCount = 8
        let moonN = SCNNode()
        moonN.light = moon
        moonN.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 4, 0)
        moonN.position = SCNVector3(3, 8, -2)
        scene.rootNode.addChildNode(moonN)
    }

    private func buildRoomShell() {
        let floor = SCNBox(width: CGFloat(size), height: 0.08, length: CGFloat(size), chamferRadius: 0)
        let fm = HousePix.tiledMat(HousePix.woodFloorTile())
        fm.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(size) * 1.2, Float(size) * 1.2, 1)
        floor.materials = [fm]
        let floorN = SCNNode(geometry: floor)
        floorN.position = SCNVector3(size / 2, -0.04, size / 2)
        floorN.castsShadow = false
        floorN.receiveShadows = true
        roomRoot.addChildNode(floorN)

        let wallH: CGFloat = 2.4
        let wallM = HousePix.tiledMat(HousePix.plasterWall())
        wallM.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 2, 1)
        func wall(w: CGFloat, l: CGFloat, x: Float, z: Float, rotY: Float) {
            let box = SCNBox(width: w, height: wallH, length: 0.12, chamferRadius: 0)
            box.materials = [wallM]
            let n = SCNNode(geometry: box)
            n.position = SCNVector3(x, Float(wallH / 2), z)
            n.eulerAngles.y = rotY
            n.castsShadow = true
            n.receiveShadows = true
            roomRoot.addChildNode(n)
        }
        wall(CGFloat(size), 0.12, size / 2, 0, 0)           // 后墙
        wall(0.12, CGFloat(size), 0, size / 2, Float.pi / 2) // 左墙
        wall(0.12, CGFloat(size), size, size / 2, Float.pi / 2) // 右墙（矮隔断感）

        // 地毯
        let rug = SCNBox(width: 2.6, height: 0.02, length: 2.4, chamferRadius: 0.02)
        let rm = SCNMaterial()
        rm.diffuse.contents = NSColor(red: 0.55, green: 0.28, blue: 0.26, alpha: 1)
        rm.roughness.contents = 0.95
        rug.materials = [rm]
        let rugN = SCNNode(geometry: rug)
        rugN.position = SCNVector3(3.1, 0.01, 3.3)
        roomRoot.addChildNode(rugN)

        // 窗 + 月光
        let win = SCNBox(width: 1.5, height: 0.9, length: 0.04, chamferRadius: 0)
        let wm = SCNMaterial()
        wm.diffuse.contents = NSColor(red: 0.12, green: 0.18, blue: 0.35, alpha: 1)
        wm.emission.contents = NSColor(red: 0.35, green: 0.45, blue: 0.75, alpha: 1)
        wm.emission.intensity = 0.35
        win.materials = [wm]
        let winN = SCNNode(geometry: win)
        winN.position = SCNVector3(4.2, 1.35, 0.06)
        roomRoot.addChildNode(winN)
    }

    private func buildFurniture() {
        let sofa = HousePix.spritePlane("sofa", HousePix.sofa, width: 2.2)
        sofa.position = SCNVector3(3.2, 0, 4.5)
        sofa.eulerAngles.y = Float.pi
        roomRoot.addChildNode(sofa)

        let stand = HousePix.spritePlane("tvstand", HousePix.tvStand, width: 1.5)
        stand.position = SCNVector3(0.55, 0, 2.5)
        stand.eulerAngles.y = Float.pi / 2
        roomRoot.addChildNode(stand)

        let plant = HousePix.spritePlane("plant", HousePix.plant, width: 0.55)
        plant.position = SCNVector3(5.3, 0, 0.75)
        roomRoot.addChildNode(plant)
    }

    func update(room: HouseRoom?) {
        lightNodes.values.forEach { $0.removeFromParentNode() }
        particleNodes.values.forEach { $0.removeFromParentNode() }
        lightNodes.removeAll(); particleNodes.removeAll()
        for k in Array(deviceRoots.keys) {
            deviceRoots[k]?.removeFromParentNode()
            deviceRoots.removeValue(forKey: k)
        }
        tvScreen?.removeFromParentNode(); tvScreen = nil
        lampLight?.intensity = 0

        guard let room else { return }
        let dim: CGFloat = room.devices.contains(where: { $0.kind == .light && $0.on }) ? 1 : 0.55
        ambientNode.light?.intensity = 80 + 60 * dim

        for d in room.devices {
            let anchor = HouseLayout.livingAnchor(d.kind, slot: d.slot)
            let root = SCNNode()
            root.name = "dev:\(d.did)"
            root.position = SCNVector3(anchor.x, anchor.y, anchor.z)
            roomRoot.addChildNode(root)
            deviceRoots[d.did] = root

            switch d.kind {
            case .light:
                let art = d.on ? HousePix.floorLamp : HousePix.floorLampOff
                let name = d.on ? "lamp-on" : "lamp-off"
                let lamp = HousePix.spritePlane(name, art, width: 0.55, emissive: d.on ? 0.8 : 0)
                lamp.position = SCNVector3(0, 0, 0)
                root.addChildNode(lamp)
                if d.on {
                    let pl = SCNLight()
                    pl.type = .omni
                    pl.intensity = 900
                    pl.color = NSColor(red: 1, green: 0.78, blue: 0.42, alpha: 1)
                    pl.castsShadow = true
                    pl.attenuationStartDistance = 0.5
                    pl.attenuationEndDistance = 5
                    let ln = SCNNode()
                    ln.light = pl
                    ln.position = SCNVector3(0, 0.85, 0)
                    root.addChildNode(ln)
                    lightNodes[d.did] = ln
                    lampLight = pl
                    let pool = SCNPlane(width: 2.2, height: 1.6)
                    let pm = SCNMaterial()
                    pm.diffuse.contents = NSColor(red: 1, green: 0.7, blue: 0.35, alpha: 0.5)
                    pm.lightingModel = .constant
                    pm.blendMode = .add
                    pm.isDoubleSided = true
                    pool.materials = [pm]
                    let poolN = SCNNode(geometry: pool)
                    poolN.eulerAngles.x = -Float.pi / 2
                    poolN.position = SCNVector3(0, 0.02, 0)
                    root.addChildNode(poolN)
                }
            case .ac:
                let ac = HousePix.spritePlane("ac", HousePix.ac, width: 1.1)
                ac.eulerAngles.y = 0
                root.addChildNode(ac)
                if d.on {
                    let ps = SCNParticleSystem()
                    ps.birthRate = 40
                    ps.particleLifeSpan = 1.4
                    ps.particleLifeSpanVariation = 0.4
                    ps.particleSize = 0.04
                    ps.particleSizeVariation = 0.02
                    ps.particleColor = NSColor(red: 0.55, green: 0.82, blue: 1, alpha: 0.85)
                    ps.particleColorVariation = SCNVector4(0.1, 0.1, 0.1, 0.2)
                    ps.emitterShape = SCNBox(width: 0.9, height: 0.02, length: 0.05, chamferRadius: 0)
                    ps.spreadingAngle = 25
                    ps.particleVelocity = 0.35
                    ps.particleVelocityVariation = 0.15
                    ps.blendMode = .additive
                    ps.isLocal = true
                    let pn = SCNNode()
                    pn.position = SCNVector3(0, -0.15, 0.15)
                    pn.addParticleSystem(ps)
                    root.addChildNode(pn)
                    particleNodes[d.did] = pn
                    let cool = SCNLight()
                    cool.type = .omni
                    cool.intensity = 180
                    cool.color = NSColor(red: 0.5, green: 0.78, blue: 1, alpha: 1)
                    let cn = SCNNode()
                    cn.light = cool
                    cn.position = SCNVector3(0, -0.2, 0.3)
                    root.addChildNode(cn)
                    lightNodes[d.did] = cn
                }
            case .tv:
                let tv = HousePix.spritePlane("tv", HousePix.tv, width: 1.05, emissive: d.on ? 1.2 : 0)
                tv.position = SCNVector3(0, 0.55, 0)
                tv.eulerAngles.y = Float.pi / 2
                root.addChildNode(tv)
                tvScreen = tv
                if d.on {
                    let glow = SCNLight()
                    glow.type = .omni
                    glow.intensity = 320
                    glow.color = NSColor(red: 0.45, green: 0.65, blue: 1, alpha: 1)
                    let gn = SCNNode()
                    gn.light = glow
                    gn.position = SCNVector3(0.3, 0.55, 0)
                    root.addChildNode(gn)
                    lightNodes[d.did] = gn
                }
            }
        }
    }

    static func makeCamera(tiltShift: Bool) -> SCNNode {
        let cam = SCNCamera()
        cam.usesOrthographicProjection = false
        cam.fieldOfView = 42
        cam.zNear = 0.1
        cam.zFar = 120
        cam.wantsHDR = true
        cam.wantsExposureAdaptation = false
        cam.exposureOffset = 0.35
        if tiltShift {
            cam.wantsDepthOfField = true
            cam.focusDistance = 11
            cam.fStop = 2.4
            cam.apertureBladeCount = 6
        }
        let n = SCNNode()
        n.camera = cam
        n.position = SCNVector3(9.5, 9.2, 9.5)
        n.look(at: SCNVector3(3, 0.8, 3))
        return n
    }
}

// MARK: - SCNView

final class HouseSCNView: SCNView {
    var onDeviceTap: ((String) -> Void)?
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let hits = hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
        for h in hits {
            var n: SCNNode? = h.node
            while let x = n {
                if let name = x.name, name.hasPrefix("dev:") {
                    onDeviceTap?(String(name.dropFirst(4)))
                    return
                }
                n = x.parent
            }
        }
    }
}

struct HouseScene3DView: NSViewRepresentable {
    let room: HouseRoom?
    var tiltShift: Bool
    var onToggle: (String) -> Void
    @Binding var labelFrames: [String: HouseLabelFrame]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> HouseSCNView {
        let v = HouseSCNView()
        v.antialiasingMode = .multisampling4X
        v.backgroundColor = .clear
        v.autoenablesDefaultLighting = false
        v.allowsCameraControl = false
        v.preferredFramesPerSecond = 60
        let holder = HouseHD2DScene()
        context.coordinator.holder = holder
        v.scene = holder.scene
        let cam = HouseHD2DScene.makeCamera(tiltShift: tiltShift)
        context.coordinator.camNode = cam
        holder.scene.rootNode.addChildNode(cam)
        v.pointOfView = cam
        v.delegate = context.coordinator
        v.onDeviceTap = onToggle
        context.coordinator.view = v
        return v
    }

    func updateNSView(_ v: HouseSCNView, context: Context) {
        context.coordinator.onFrames = { labelFrames = $0 }
        if let cam = context.coordinator.camNode?.camera {
            let want = tiltShift
            if cam.wantsDepthOfField != want {
                cam.wantsDepthOfField = want
                cam.focusDistance = want ? 11 : 0
            }
        }
        context.coordinator.holder?.update(room: room)
        context.coordinator.refreshLabels(room: room)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        var holder: HouseHD2DScene?
        weak var view: SCNView?
        var camNode: SCNNode?
        var onFrames: (([String: HouseLabelFrame]) -> Void)?
        private var room: HouseRoom?

        func refreshLabels(room: HouseRoom?) {
            self.room = room
            updateFrames()
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            updateFrames()
        }

        private func updateFrames() {
            guard let view, let holder, let room else { return }
            var out: [String: HouseLabelFrame] = [:]
            for d in room.devices {
                guard let root = holder.deviceRoots[d.did] else { continue }
                let lift = labelLift(d)
                let world = root.convertPosition(SCNVector3(0, lift, 0), to: nil)
                let anchor = project(world, in: view) ?? .zero
                let pillY = anchor.y - 36
                out[d.did] = HouseLabelFrame(device: d, anchor: anchor, pillCenter: CGPoint(x: anchor.x, y: pillY))
            }
            onFrames?(out)
        }

        private func project(_ p: SCNVector3, in view: SCNView) -> CGPoint? {
            let v = view.projectPoint(p)
            guard v.z > 0, v.z < 1 else { return nil }
            return CGPoint(x: CGFloat(v.x), y: CGFloat(view.bounds.height - v.y))
        }
    }
}

struct HouseLabelFrame: Equatable {
    let device: HouseDevice
    let anchor: CGPoint
    let pillCenter: CGPoint
}

private func labelLift(_ d: HouseDevice) -> Float {
    switch d.kind {
    case .ac: return 0.55
    case .tv: return 1.15
    case .light: return 1.05
    }
}

// MARK: - SwiftUI

struct HouseView: View {
    @EnvironmentObject var m: AppModel
    @State private var tilt = true
    @State private var detail: String?
    @State private var labelFrames: [String: HouseLabelFrame] = [:]

    var body: some View {
        ZStack {
            HouseScene3DView(room: m.houseLivingRoom, tiltShift: tilt,
                             onToggle: { did in if let d = m.device(did) { m.toggle(d) } },
                             labelFrames: $labelFrames)
            HouseLabelOverlay(frames: labelFrames, room: m.houseLivingRoom,
                              onOpen: { detail = $0 })
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            IconButton(icon: tilt ? "camera.aperture" : "camera", help: L("移轴景深", "Tilt-shift"), tint: tilt ? Theme.cool : nil) { tilt.toggle() }
                .padding(10)
        }
        .sheet(item: Binding(get: { detail.map { IdentStr(id: $0) } }, set: { detail = $0?.id })) { x in
            if let d = m.device(x.id) {
                ScrollView { DetailView(device: d).padding(12) }
                    .frame(width: 360, height: 560).background(Theme.bg)
                    .onChange(of: m.page) { _, p in if case .detail = p {} else { detail = nil } }
                    .onAppear { m.open(d, animated: false) }
            }
        }
        .frame(minWidth: 560, minHeight: 380)
    }
}

private struct IdentStr: Identifiable { let id: String }

struct HouseLabelOverlay: View {
    let frames: [String: HouseLabelFrame]
    let room: HouseRoom?
    var onOpen: (String) -> Void

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                for f in frames.values.sorted(by: { $0.pillCenter.y < $1.pillCenter.y }) {
                    var path = Path()
                    path.move(to: f.anchor)
                    path.addLine(to: CGPoint(x: f.pillCenter.x, y: f.pillCenter.y + 10))
                    ctx.stroke(path, with: .color(pillTint(f.device).opacity(0.45)), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
            ForEach(sortedFrames, id: \.device.did) { f in
                HousePill(device: f.device)
                    .position(f.pillCenter)
                    .onTapGesture { onOpen(f.device.did) }
            }
            if room == nil {
                Text(L("这个家里还没有客厅", "No living room in this home yet"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let room {
                Text(room.title + (room.overflow > 0 ? L(" · 另有 \(room.overflow) 台", " · +\(room.overflow) more") : ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .position(x: geo.size.width * 0.82, y: geo.size.height * 0.88)
            }
        }
    }

    private var sortedFrames: [HouseLabelFrame] { frames.values.sorted { $0.pillCenter.y < $1.pillCenter.y } }

    private func pillTint(_ d: HouseDevice) -> Color {
        if !d.online { return .gray }
        if !d.on { return Color(white: 0.75) }
        switch d.kind {
        case .light: return Color(red: 1, green: 0.8, blue: 0.4)
        case .ac: return Color(red: 0.5, green: 0.78, blue: 1)
        case .tv: return Color(red: 0.6, green: 0.7, blue: 1)
        }
    }
}

struct HousePill: View {
    let device: HouseDevice
    var body: some View {
        let tint = pillColor
        let state = !device.online ? L("离线", "Offline") : device.on ? L("开", "On") : L("关", "Off")
        let icon = device.kind == .light ? "lightbulb.fill" : device.kind == .ac ? "air.conditioner.horizontal" : "tv"
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text("\(device.name) · \(state)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Capsule().fill(Color(red: 0.08, green: 0.08, blue: 0.12, opacity: 0.82)))
        .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
    }
    private var pillColor: Color {
        if !device.online { return .gray }
        if !device.on { return Color(white: 0.75) }
        switch device.kind {
        case .light: return Color(red: 1, green: 0.8, blue: 0.4)
        case .ac: return Color(red: 0.5, green: 0.78, blue: 1)
        case .tv: return Color(red: 0.6, green: 0.7, blue: 1)
        }
    }
}

@MainActor
enum HouseWindow {
    static var window: NSWindow?
    static func open(model: AppModel) {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = L("小屋", "House")
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: HouseView().environmentObject(model))
        w.center(); window = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { window?.contentView = nil; window = nil }
        }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - 截图

enum HouseSnapshot {
    @MainActor static func image(_ room: HouseRoom?, size: CGSize = CGSize(width: 1200, height: 800), tiltShift: Bool = true) -> CGImage? {
        let v = HouseSCNView(frame: CGRect(origin: .zero, size: size))
        v.antialiasingMode = .multisampling4X
        v.autoenablesDefaultLighting = false
        let holder = HouseHD2DScene()
        holder.update(room: room)
        v.scene = holder.scene
        let cam = HouseHD2DScene.makeCamera(tiltShift: tiltShift)
        holder.scene.rootNode.addChildNode(cam)
        v.pointOfView = cam
        let win = NSWindow(contentRect: v.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = v; win.setFrameOrigin(NSPoint(x: 40, y: 40)); win.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        defer { win.orderOut(nil) }
        guard let img = v.snapshot().cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return img
    }

    @MainActor static func write(_ img: CGImage?, _ url: URL) {
        guard let img else { print("house snapshot failed"); return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }
}

extension Snapshot {
    /// `MijiaBarApp --house-snapshot <dir>`：HD-2D 客厅试点截图
    static func house(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let m = AppModel(mock: true)
        func dev(_ id: String, _ n: String, _ model: String, _ room: String) -> Device {
            Device(did: id, name: n, model: model, homeId: "h1", homeName: "", roomName: room)
        }
        m.devices.append(dev("x1", L("电视", "TV"), "xiaomi.tv.demo", L("客厅", "Living room")))
        let onSpec = DeviceSpec(type: "", description: "", services: [SpecService(iid: 2, type: "urn:miot-spec-v2:service:light:0", description: "", properties: [
            SpecProperty(siid: 2, iid: 1, type: "urn:miot-spec-v2:property:on:0", description: "on", format: "bool", access: ["read", "write"], unit: nil, range: nil, options: nil)], actions: [])])
        func set(_ id: String, _ on: Bool) {
            if id == "d1" || id == "d2" { m.states[id]?.values["power"] = .string(on ? "on" : "off"); return }
            if m.states[id] == nil { m.states[id] = DeviceState(values: [:], spec: onSpec, legacy: false, source: "cloud") }
            m.states[id]?.values["2.1"] = .bool(on)
        }
        for (id, on) in [("d1", true), ("d3", true), ("x1", true)] { set(id, on) }
        let room = m.houseLivingRoom
        HouseSnapshot.write(HouseSnapshot.image(room), out.appendingPathComponent("house-hd2d-night.png"))
        for id in ["d1", "d3", "x1"] { set(id, false) }
        HouseSnapshot.write(HouseSnapshot.image(m.houseLivingRoom), out.appendingPathComponent("house-hd2d-off.png"))
        exit(0)
    }
}
