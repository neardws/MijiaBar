import SwiftUI
import MetalKit
import simd
import MijiaCore

// MARK: - 演示状态（客厅试点）

struct HouseLivingDemo: Equatable {
    var lampOn = true
    var tvOn = true
    var acOn = true
    var acTemp = 26
    var time: Float = 0
}

struct HouseAnchor: Identifiable {
    let id: String
    let label: String
    let icon: String
    let tint: Color
    let world: SIMD3<Float>
}

// MARK: - Metal 顶点 / Uniform

struct HouseVertexIn {
    var position: SIMD4<Float>
    var uv: SIMD2<Float>
    var tint: SIMD4<Float>
    var emissive: Float
    var depthKey: Float
}

struct HouseUniforms {
    var viewProj: simd_float4x4
    var ambientColor: SIMD3<Float>
    var ambientStrength: Float
    var pointLightPos: SIMD3<Float>
    var pointLightColor: SIMD3<Float>
    var pointLightStrength: Float
    var viewportSize: SIMD2<Float>
    var time: Float
    var tvOn: Float
    var lampOn: Float
}

// MARK: - 纹理集

@MainActor
final class HouseTextureSet {
    let wood, plaster, rug, sky, sofa, plant, lampOn, lampOff, ac, tv, tvStand, table, tvGlow: MTLTexture?

    init(device: MTLDevice) {
        wood = HousePix.texture(device, rows: HousePix.woodPlankTile(), scale: 4, label: "wood")
        plaster = HousePix.texture(device, rows: HousePix.plasterTile(), scale: 4, label: "plaster")
        rug = HousePix.texture(device, rows: HousePix.rugTile(), scale: 4, label: "rug")
        sky = HousePix.texture(device, rows: HousePix.nightSky(), scale: 3, label: "sky")
        sofa = HousePix.texture(device, rows: HousePix.sofa, scale: 3, label: "sofa")
        plant = HousePix.texture(device, rows: HousePix.plant, scale: 3, label: "plant")
        lampOn = HousePix.texture(device, rows: HousePix.floorLamp, scale: 3, label: "lampOn")
        lampOff = HousePix.texture(device, rows: HousePix.floorLampOff, scale: 3, label: "lampOff")
        ac = HousePix.texture(device, rows: HousePix.ac, scale: 3, label: "ac")
        tv = HousePix.texture(device, rows: HousePix.tv, scale: 3, label: "tv")
        tvStand = HousePix.texture(device, rows: HousePix.tvStand, scale: 3, label: "tvStand")
        table = HousePix.texture(device, rows: HousePix.coffeeTable, scale: 3, label: "table")
        tvGlow = HousePix.texture(device, rows: HousePix.tvScreenOn(), scale: 4, label: "tvGlow")
    }

    func named(_ n: String) -> MTLTexture? {
        switch n {
        case "wood": wood; case "plaster": plaster; case "rug": rug; case "sky": sky
        case "sofa": sofa; case "plant": plant; case "lampOn": lampOn; case "lampOff": lampOff
        case "ac": ac; case "tv": tv; case "tvStand": tvStand; case "table": table; case "tvGlow": tvGlow
        default: wood
        }
    }
}

struct HouseDraw {
    var verts: [HouseVertexIn]
    var textureName: String
    var blendAdd: Bool
}

// MARK: - 场景几何

enum HouseLivingScene {
    static let tileW: Float = 64, tileH: Float = 32, roomN: Float = 6, wallH: Float = 110

    static func iso(_ gx: Float, _ gy: Float, _ gz: Float = 0) -> SIMD3<Float> {
        SIMD3((gx - gy) * tileW * 0.5, gz - (gx + gy) * tileH * 0.5, (gx + gy) * 0.5 + gz * 0.02)
    }

    static func dim(_ on: Bool) -> Float { on ? 1 : 0.42 }

    static func build(state: HouseLivingDemo, textures: HouseTextureSet) -> ([HouseDraw], [HouseAnchor]) {
        var draws: [HouseDraw] = []
        let d = dim(state.lampOn || state.tvOn)
        let N = roomN

        // 地板
        for ix in 0..<Int(N) {
            for iy in 0..<Int(N) {
                let x = Float(ix), y = Float(iy)
                let a = iso(x, y), b = iso(x + 1, y), c = iso(x + 1, y + 1), d0 = iso(x, y + 1)
                let dk = x + y
                draws.append(quad(a, b, c, d0, tex: "wood", tint: SIMD4(d, d, d, 1), depth: dk, uRepeat: 2))
            }
        }
        // 地毯
        let rugPts = [iso(1.6, 2), iso(4.4, 2), iso(4.4, 4.6), iso(1.6, 4.6)]
        draws.append(quad(rugPts[0], rugPts[1], rugPts[2], rugPts[3], tex: "rug", tint: SIMD4(1, 1, 1, 1), depth: 5, uRepeat: 3))

        // 后墙 + 侧墙
        func wall(_ a: SIMD3<Float>, _ b: SIMD3<Float>, h: Float, shade: Float) {
            let topA = a + SIMD3(0, h, 0), topB = b + SIMD3(0, h, 0)
            let s = shade * d
            draws.append(quad(a, b, topB, topA, tex: "plaster", tint: SIMD4(s, s, s * 0.98, 1), depth: a.z, uRepeat: 4))
        }
        wall(iso(0, 0), iso(N, 0), h: wallH, shade: 0.88)
        wall(iso(0, 0), iso(0, N), h: wallH, shade: 0.72)
        // 矮隔断（敞口娃娃屋）
        wall(iso(N, 0), iso(N, N), h: 18, shade: 0.8)
        wall(iso(0, N), iso(N, N), h: 18, shade: 0.76)

        // 窗 + 夜空
        let wa = iso(3.6, 0, 52), wb = iso(5.2, 0, 52)
        let wTopA = wa + SIMD3(0, 40, 0), wTopB = wb + SIMD3(0, 40, 0)
        draws.append(quad(wa, wb, wTopB, wTopA, tex: "sky", tint: SIMD4(0.7, 0.8, 1, 1), depth: 2, uRepeat: 1))

        // 家具
        sprite(&draws, "sofa", gx: 3.2, gy: 4.6, scale: 3, tint: d)
        sprite(&draws, "table", gx: 2.4, gy: 3.2, scale: 3, tint: d)
        sprite(&draws, "plant", gx: 5.3, gy: 0.7, scale: 3, tint: d)
        sprite(&draws, state.lampOn ? "lampOn" : "lampOff", gx: 5.2, gy: 4.2, scale: 3, tint: d, emissive: state.lampOn ? 0.9 : 0)
        sprite(&draws, "tvStand", gx: 0.6, gy: 2.6, scale: 3, tint: d)
        sprite(&draws, "tv", gx: 0.6, gy: 2.6, scale: 3, tint: d, gz: 28, emissive: state.tvOn ? 0.35 : 0)
        if state.tvOn {
            sprite(&draws, "tvGlow", gx: 0.62, gy: 2.65, scale: 2.8, tint: 1, gz: 34, emissive: 1.2, blendAdd: true)
        }
        sprite(&draws, "ac", gx: 2.2, gy: 0.1, scale: 3, tint: d, gz: 82, emissive: state.acOn ? 0.25 : 0)

        // 暖色光池（地面）
        if state.lampOn {
            let p = iso(5.2, 4.2)
            draws.append(glowQuad(center: p, w: 280, h: 160, depth: 3, strength: 0.55))
        }
        if state.tvOn {
            let p = iso(0.8, 3.2)
            draws.append(glowQuad(center: p, w: 220, h: 120, depth: 3.5, strength: 0.35, cool: true))
        }

        // AC 冷气粒子（简化为几个 additive 光点）
        if state.acOn {
            let base = iso(2.2, 0.5, 78)
            for i in 0..<8 {
                let t = state.time + Float(i) * 0.4
                let ox = sin(t * 2 + Float(i)) * 40
                let oy = -fmod(t * 45, 90)
                draws.append(glowQuad(center: base + SIMD3(ox, oy, 0), w: 24, h: 12, depth: 80 + Float(i) * 0.01, strength: 0.5, cool: true))
            }
        }

        draws.sort { $0.verts.first?.depthKey ?? 0 < $1.verts.first?.depthKey ?? 0 }

        let anchors: [HouseAnchor] = [
            HouseAnchor(id: "ac", label: "\(state.acTemp)°", icon: "thermometer.medium", tint: .cyan, world: iso(2.2, 0.1, 95)),
            HouseAnchor(id: "tv", label: L("电源", "POWER"), icon: "power", tint: .green, world: iso(0.6, 2.6, 105)),
            HouseAnchor(id: "lamp", label: state.lampOn ? L("开", "ON") : L("关", "OFF"), icon: "lightbulb.fill", tint: .orange, world: iso(5.2, 4.2, 95)),
        ]
        _ = textures // 保留参数供后续扩展
        return (draws, anchors)
    }

    private static func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                             tex: String, tint: SIMD4<Float>, depth: Float, uRepeat: Float, emissive: Float = 0, blendAdd: Bool = false) -> HouseDraw {
        let uv: (SIMD3<Float>, SIMD2<Float>) -> HouseVertexIn = { p, t in
            HouseVertexIn(position: SIMD4(p.x, p.y, p.z, 1), uv: t, tint: tint, emissive: emissive, depthKey: depth)
        }
        let verts = [
            uv(a, SIMD2(0, uRepeat)), uv(b, SIMD2(uRepeat, uRepeat)), uv(c, SIMD2(uRepeat, 0)),
            uv(a, SIMD2(0, uRepeat)), uv(c, SIMD2(uRepeat, 0)), uv(d, SIMD2(0, 0)),
        ]
        return HouseDraw(verts: verts, textureName: tex, blendAdd: blendAdd)
    }

    private static func sprite(_ draws: inout [HouseDraw], _ tex: String, gx: Float, gy: Float, scale: Float, tint: Float, gz: Float = 0, emissive: Float = 0, blendAdd: Bool = false) {
        let w: Float = 22 * scale, h: Float = 28 * scale
        let base = iso(gx, gy, gz)
        let a = base + SIMD3(-w * 0.5, 0, 0)
        let b = base + SIMD3(w * 0.5, 0, 0)
        let c = b + SIMD3(0, h, 0)
        let d = a + SIMD3(0, h, 0)
        let t = SIMD4(tint, tint, tint, 1)
        draws.append(quad(a, b, c, d, tex: tex, tint: t, depth: gx + gy + gz * 0.01, uRepeat: 1, emissive: emissive, blendAdd: blendAdd))
    }

    private static func glowQuad(center: SIMD3<Float>, w: Float, h: Float, depth: Float, strength: Float, cool: Bool = false) -> HouseDraw {
        let a = center + SIMD3(-w * 0.5, -h * 0.5, 0)
        let b = center + SIMD3(w * 0.5, -h * 0.5, 0)
        let c = b + SIMD3(0, h, 0)
        let d = a + SIMD3(0, h, 0)
        let col: SIMD4<Float> = cool ? SIMD4(0.4, 0.65, 1, strength) : SIMD4(1, 0.72, 0.35, strength)
        func v(_ p: SIMD3<Float>, _ t: SIMD2<Float>) -> HouseVertexIn {
            HouseVertexIn(position: SIMD4(p.x, p.y, p.z, 1), uv: t, tint: col, emissive: 1, depthKey: depth)
        }
        return HouseDraw(verts: [
            v(a, SIMD2(0, 1)), v(b, SIMD2(1, 1)), v(c, SIMD2(1, 0)),
            v(a, SIMD2(0, 1)), v(c, SIMD2(1, 0)), v(d, SIMD2(0, 0)),
        ], textureName: "wood", blendAdd: true)
    }
}

// MARK: - 渲染器

@MainActor
final class HouseMetalRenderer: NSObject, MTKViewDelegate {
    /// 最近一次 `init` 失败原因（stderr 也会打印）
    static var lastInitError: String?

    let device: MTLDevice
    let queue: MTLCommandQueue
    let textures: HouseTextureSet
    var state = HouseLivingDemo()
    var anchors: [HouseAnchor] = []
    var viewProj = matrix_identity_float4x4
    var viewportSize = SIMD2<Float>(1200, 800)

    private let housePipeline: MTLRenderPipelineState
    private let addPipeline: MTLRenderPipelineState
    private let bgPipeline: MTLRenderPipelineState
    private let bloomThresh: MTLRenderPipelineState
    private let blurH: MTLRenderPipelineState
    private let blurV: MTLRenderPipelineState
    private let composite: MTLRenderPipelineState
    private let sampler: MTLSamplerState

    var sceneTex: MTLTexture?
    private var bloomTex: MTLTexture?
    private var bloomBlur: MTLTexture?

    init?(view: MTKView) {
        Self.lastInitError = nil
        guard let dev = view.device ?? MTLCreateSystemDefaultDevice() else {
            Self.fail("MTLCreateSystemDefaultDevice() returned nil")
            return nil
        }
        guard let q = dev.makeCommandQueue() else {
            Self.fail("makeCommandQueue() returned nil")
            return nil
        }
        let (loaded, loadErr) = HouseMetalLibrary.load(device: dev)
        guard let lib = loaded else {
            Self.fail(loadErr ?? "HouseMetalLibrary.load returned nil")
            return nil
        }
        device = dev; queue = q; view.device = dev
        textures = HouseTextureSet(device: dev)

        let sampDesc = MTLSamplerDescriptor()
        sampDesc.minFilter = .nearest; sampDesc.magFilter = .nearest
        sampDesc.sAddressMode = .repeat; sampDesc.tAddressMode = .repeat
        guard let samp = dev.makeSamplerState(descriptor: sampDesc) else {
            Self.fail("makeSamplerState(nearest) returned nil")
            return nil
        }
        sampler = samp

        func pipe(_ frag: String, blend: Bool, fullscreen: Bool) -> MTLRenderPipelineState? {
            let vName = fullscreen ? "fullscreen_vertex" : "house_vertex"
            guard let v = lib.makeFunction(name: vName) else {
                Self.fail("Metal function missing: \(vName)")
                return nil
            }
            guard let f = lib.makeFunction(name: frag) else {
                Self.fail("Metal function missing: \(frag)")
                return nil
            }
            let d = MTLRenderPipelineDescriptor()
            d.vertexFunction = v; d.fragmentFunction = f
            d.colorAttachments[0].pixelFormat = .bgra8Unorm
            if blend {
                d.colorAttachments[0].isBlendingEnabled = true
                d.colorAttachments[0].rgbBlendOperation = .add
                d.colorAttachments[0].alphaBlendOperation = .add
                d.colorAttachments[0].sourceRGBBlendFactor = .one
                d.colorAttachments[0].destinationRGBBlendFactor = .one
                d.colorAttachments[0].sourceAlphaBlendFactor = .one
                d.colorAttachments[0].destinationAlphaBlendFactor = .one
            }
            do { return try dev.makeRenderPipelineState(descriptor: d) }
            catch {
                Self.fail("makeRenderPipelineState(\(frag)): \(error)")
                return nil
            }
        }

        guard let main = pipe("house_fragment", blend: false, fullscreen: false),
              let add = pipe("house_fragment", blend: true, fullscreen: false),
              let bg = pipe("bokeh_background", blend: false, fullscreen: true),
              let bt = pipe("bloom_threshold", blend: false, fullscreen: true),
              let bh = pipe("blur_pass", blend: false, fullscreen: true),
              let comp = pipe("composite_tiltshift", blend: false, fullscreen: true) else { return nil }
        housePipeline = main; addPipeline = add; bgPipeline = bg
        bloomThresh = bt; blurH = bh; blurV = bh; composite = comp
        super.init()
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        rebuildTargets(size: view.drawableSize)
    }

    private static func fail(_ message: String) {
        lastInitError = message
        fputs("house-metal renderer init failed: \(message)\n", stderr)
    }

    func rebuildTargets(size: CGSize) {
        let w = max(Int(size.width), 1), h = max(Int(size.height), 1)
        viewportSize = SIMD2(Float(w), Float(h))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        sceneTex = device.makeTexture(descriptor: desc)
        bloomTex = device.makeTexture(descriptor: desc)
        bloomBlur = device.makeTexture(descriptor: desc)
        updateCamera()
    }

    func updateCamera() {
        let aspect = viewportSize.x / max(viewportSize.y, 1)
        let ortho = simd_orthographic(-420 * aspect, 420 * aspect, -320, 320, -500, 500)
        let view = simd_float4x4([
            SIMD4(1, 0, 0, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(-20, 40, 0, 1),
        ])
        viewProj = ortho * view
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { rebuildTargets(size: size) }

    func draw(in view: MTKView) {
        state.time += 1 / 30
        if view.drawableSize.width > 0, view.drawableSize.height > 0,
           (sceneTex == nil || Int(viewportSize.x) != Int(view.drawableSize.width)) {
            rebuildTargets(size: view.drawableSize)
        }
        guard let cmd = queue.makeCommandBuffer(),
              let scene = sceneTex, let bloom = bloomTex, let blur = bloomBlur else { return }
        renderFrame(cmd: cmd, scene: scene, bloom: bloom, blur: blur)
        if let drawable = view.currentDrawable, let rpd = view.currentRenderPassDescriptor {
            rpd.colorAttachments[0].loadAction = .clear
            if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
                enc.setRenderPipelineState(composite)
                enc.setFragmentTexture(scene, index: 0)
                enc.setFragmentTexture(bloom, index: 1)
                enc.setFragmentSamplerState(sampler, index: 0)
                var vp = viewportSize
                enc.setFragmentBytes(&vp, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
                enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
                enc.endEncoding()
            }
            cmd.present(drawable)
        }
        cmd.commit()
    }

    func renderFrame(cmd: MTLCommandBuffer, scene: MTLTexture, bloom: MTLTexture, blur: MTLTexture) {
        let (draws, anc) = HouseLivingScene.build(state: state, textures: textures)
        anchors = anc
        if let enc = cmd.makeRenderCommandEncoder(descriptor: offscreenPass(scene)) {
            drawBackground(enc: enc, time: state.time)
            drawScene(enc: enc, draws: draws)
            enc.endEncoding()
        }
        if let enc = cmd.makeRenderCommandEncoder(descriptor: pass(bloom, load: .clear)) {
            enc.setRenderPipelineState(bloomThresh)
            enc.setFragmentTexture(scene, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }
        var dir = SIMD2<Float>(1, 0)
        if let enc = cmd.makeRenderCommandEncoder(descriptor: pass(blur, load: .clear)) {
            enc.setRenderPipelineState(blurH)
            enc.setFragmentTexture(bloom, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setFragmentBytes(&dir, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }
        dir = SIMD2(0, 1)
        if let enc = cmd.makeRenderCommandEncoder(descriptor: pass(bloom, load: .load)) {
            enc.setRenderPipelineState(blurV)
            enc.setFragmentTexture(blur, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setFragmentBytes(&dir, length: MemoryLayout<SIMD2<Float>>.size, index: 0)
            enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            enc.endEncoding()
        }
    }

    private func offscreenPass(_ tex: MTLTexture) -> MTLRenderPassDescriptor {
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = tex
        p.colorAttachments[0].loadAction = .clear
        p.colorAttachments[0].storeAction = .store
        p.colorAttachments[0].clearColor = MTLClearColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 1)
        return p
    }

    private func pass(_ tex: MTLTexture, load: MTLLoadAction) -> MTLRenderPassDescriptor {
        let p = MTLRenderPassDescriptor()
        p.colorAttachments[0].texture = tex
        p.colorAttachments[0].loadAction = load
        p.colorAttachments[0].storeAction = .store
        return p
    }

    private func drawBackground(enc: MTLRenderCommandEncoder, time: Float) {
        enc.setRenderPipelineState(bgPipeline)
        var t = time
        enc.setFragmentBytes(&t, length: MemoryLayout<Float>.size, index: 0)
        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }

    private func drawScene(enc: MTLRenderCommandEncoder, draws: [HouseDraw]) {
        var u = uniforms()
        for draw in draws {
            guard !draw.verts.isEmpty, let tex = textures.named(draw.textureName) else { continue }
            enc.setRenderPipelineState(draw.blendAdd ? addPipeline : housePipeline)
            enc.setFragmentTexture(tex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
            enc.setVertexBytes(draw.verts, length: MemoryLayout<HouseVertexIn>.stride * draw.verts.count, index: 0)
            enc.setVertexBytes(&u, length: MemoryLayout<HouseUniforms>.size, index: 1)
            enc.setFragmentBytes(&u, length: MemoryLayout<HouseUniforms>.size, index: 1)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: draw.verts.count)
        }
    }

    private func uniforms() -> HouseUniforms {
        let lamp = isoLight()
        return HouseUniforms(
            viewProj: viewProj,
            ambientColor: SIMD3(0.55, 0.52, 0.48),
            ambientStrength: state.lampOn ? 0.22 : 0.12,
            pointLightPos: lamp,
            pointLightColor: SIMD3(1, 0.78, 0.45),
            pointLightStrength: 1.4,
            viewportSize: viewportSize,
            time: state.time,
            tvOn: state.tvOn ? 1 : 0,
            lampOn: state.lampOn ? 1 : 0
        )
    }

    private func isoLight() -> SIMD3<Float> {
        HouseLivingScene.iso(5.2, 4.2, 70)
    }

    func project(_ w: SIMD3<Float>, viewSize: CGSize) -> CGPoint? {
        let p = viewProj * SIMD4(w, 1)
        guard p.w != 0 else { return nil }
        let ndc = SIMD2(p.x, p.y)
        return CGPoint(x: (CGFloat(ndc.x) + 1) * 0.5 * viewSize.width,
                       y: (1 - CGFloat(ndc.y)) * 0.5 * viewSize.height)
    }

    func renderStillFrames(_ count: Int = 18) {
        rebuildTargets(size: CGSize(width: CGFloat(viewportSize.x), height: CGFloat(viewportSize.y)))
        guard let scene = sceneTex, let bloom = bloomTex, let blur = bloomBlur else { return }
        for _ in 0..<count {
            state.time += 1 / 30
            guard let cmd = queue.makeCommandBuffer() else { continue }
            renderFrame(cmd: cmd, scene: scene, bloom: bloom, blur: blur)
            cmd.commit()
            cmd.waitUntilCompleted()
        }
    }
}

private func simd_orthographic(_ left: Float, _ right: Float, _ bottom: Float, _ top: Float, _ near: Float, _ far: Float) -> simd_float4x4 {
    let rl = 1 / (right - left), tb = 1 / (top - bottom), fn = 1 / (far - near)
    return simd_float4x4(columns: (
        SIMD4(2 * rl, 0, 0, 0),
        SIMD4(0, 2 * tb, 0, 0),
        SIMD4(0, 0, -2 * fn, 0),
        SIMD4(-(right + left) * rl, -(top + bottom) * tb, -(far + near) * fn, 1)
    ))
}

private extension MTLTexture {
    func cgImage(device: MTLDevice, queue: MTLCommandQueue) -> CGImage? {
        let w = width, h = height, row = w * 4
        var data = [UInt8](repeating: 0, count: row * h)
        getBytes(&data, bytesPerRow: row, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        return ctx?.makeImage()
    }
}

// MARK: - SwiftUI

struct HouseMetalView: NSViewRepresentable {
    var state: HouseLivingDemo
    @Binding var anchors: [HouseAnchor]
    var onRenderer: ((HouseMetalRenderer) -> Void)?

    func makeNSView(context: Context) -> MTKView {
        let v = MTKView()
        v.preferredFramesPerSecond = 30
        if let r = HouseMetalRenderer(view: v) { context.coordinator.renderer = r }
        return v
    }

    func updateNSView(_ v: MTKView, context: Context) {
        guard let r = context.coordinator.renderer else { return }
        r.state = state
        onRenderer?(r)
        DispatchQueue.main.async { anchors = r.anchors }
    }

    func makeCoordinator() -> Coord { Coord() }
    final class Coord { var renderer: HouseMetalRenderer? }
}

struct HousePillOverlay: View {
    let anchors: [HouseAnchor]
    let project: (SIMD3<Float>) -> CGPoint?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ForEach(anchors) { a in
                    if let p = project(a.world) {
                        HousePill(label: a.label, icon: a.icon, tint: a.tint)
                            .position(x: p.x, y: p.y - 18)
                        Path { path in
                            path.move(to: CGPoint(x: p.x, y: p.y - 6))
                            path.addLine(to: CGPoint(x: p.x, y: p.y))
                        }
                        .stroke(a.tint.opacity(0.45), lineWidth: 1)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct HousePill: View {
    let label: String, icon: String, tint: Color
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(tint)
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(.black.opacity(0.82), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.55), lineWidth: 1))
    }
}

struct HouseLivingMetalScreen: View {
    @State private var state = HouseLivingDemo()
    @State private var anchors: [HouseAnchor] = []
    @State private var renderer: HouseMetalRenderer?

    var body: some View {
        ZStack {
            HouseMetalView(state: state, anchors: $anchors) { renderer = $0 }
            if let r = renderer {
                HousePillOverlay(anchors: anchors) {
                    r.project($0, viewSize: CGSize(width: CGFloat(r.viewportSize.x), height: CGFloat(r.viewportSize.y)))
                }
            }
        }
        .background(Theme.bg)
    }
}

// MARK: - 截图 CLI

enum HouseMetalSnapshot {
    static var lastFailure: String?

    @MainActor static func render(state: HouseLivingDemo, size: CGSize = CGSize(width: 1200, height: 800)) -> CGImage? {
        lastFailure = nil
        let view = MTKView(frame: CGRect(origin: .zero, size: size))
        view.drawableSize = size
        guard let r = HouseMetalRenderer(view: view) else {
            lastFailure = HouseMetalRenderer.lastInitError ?? "HouseMetalRenderer init returned nil"
            return nil
        }
        r.state = state
        r.rebuildTargets(size: size)
        r.renderStillFrames(24)
        guard let tex = r.sceneTex else {
            lastFailure = "sceneTex nil after renderStillFrames"
            return nil
        }
        guard let img = tex.cgImage(device: r.device, queue: r.queue) else {
            lastFailure = "failed to read sceneTex bytes into CGImage"
            return nil
        }
        return img
    }

    @MainActor static func write(_ img: CGImage?, _ url: URL) {
        guard let img else {
            let reason = lastFailure ?? HouseMetalRenderer.lastInitError ?? "unknown"
            fputs("house-metal snapshot failed (\(url.lastPathComponent)): \(reason)\n", stderr)
            return
        }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: url)
        print("wrote \(url.path)")
    }
}

extension Snapshot {
    /// `MijiaBarApp --house-snapshot <dir>`：Metal HD-2D 客厅试点
    static func houseSnapshot(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var ok = true
        let night = HouseLivingDemo(lampOn: true, tvOn: true, acOn: true, acTemp: 26)
        if let img = HouseMetalSnapshot.render(state: night) {
            HouseMetalSnapshot.write(img, out.appendingPathComponent("house-hd2d-night.png"))
        } else {
            HouseMetalSnapshot.write(nil, out.appendingPathComponent("house-hd2d-night.png"))
            ok = false
        }
        let off = HouseLivingDemo(lampOn: false, tvOn: false, acOn: false, acTemp: 26)
        if let img = HouseMetalSnapshot.render(state: off) {
            HouseMetalSnapshot.write(img, out.appendingPathComponent("house-hd2d-off.png"))
        } else {
            HouseMetalSnapshot.write(nil, out.appendingPathComponent("house-hd2d-off.png"))
            ok = false
        }
        exit(ok ? 0 : 1)
    }
}
