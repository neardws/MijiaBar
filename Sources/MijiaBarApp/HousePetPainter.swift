import AppKit
import SwiftUI
import MijiaCore

@MainActor
final class HousePetPainter {
    static let shared = HousePetPainter()
    let directory: URL?
    let rig: HousePetRig?
    let spots: HousePetSpots?
    let cache = HousePetFrameCache()
    let behavior: HousePetBehavior?
    private var regionFrames: [String: [[UInt8]]] = [:]

    init() {
        let url = AppResources.url("cat-short", "json", subdirectory: "House/pets") ?? AppResources.url("cat-short", "json")
        directory = url?.deletingLastPathComponent()
        rig = url.flatMap { try? HousePetRig.load(from: $0) }
        let spotURL = AppResources.url("pet-spots", "json", subdirectory: "House/pets") ?? AppResources.url("pet-spots", "json")
        spots = spotURL.flatMap { try? HousePetSpots.load(from: $0) }
        behavior = rig.map(HousePetBehavior.init)
    }

    static func transform(rig: HousePetRig, pose: HousePetPose) -> CGAffineTransform {
        let scale = Double(rig.cellPx), direction = pose.mirrored ? -scale : scale
        return CGAffineTransform(a: direction, b: 0, c: 0, d: scale,
                                 tx: pose.point.x - direction * rig.anchor[0],
                                 ty: pose.point.y - pose.jumpLift - scale * rig.anchor[1])
    }

    static func ratio(lit: [Double], unlit: [Double]) -> [Double]? {
        guard lit.count == 3, unlit.count == 3, (lit + unlit).allSatisfy(\.isFinite), unlit.allSatisfy({ $0 > 0 }) else { return nil }
        return zip(lit, unlit).map { min(2.6, max(1, $0 / $1)) }
    }

    static func pixels(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        return success ? bytes : nil
    }

    static func sample(_ image: CGImage, at point: HousePetPoint) -> [Double]? {
        let rect = CGRect(x: floor(point.x) - 4, y: floor(point.y) - 2, width: 9, height: 5)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !rect.isEmpty, let patch = image.cropping(to: rect), let bytes = pixels(patch) else { return nil }
        var sums = [Double](repeating: 0, count: 3), count = 0.0
        for index in stride(from: 0, to: bytes.count, by: 4) where bytes[index + 3] > 0 {
            for channel in 0..<3 { sums[channel] += Double(bytes[index + channel]) / Double(bytes[index + 3]) }
            count += 1
        }
        return count > 0 ? sums.map { $0 / count } : nil
    }

    static func illuminate(_ image: CGImage, lighting: HousePetRig.Lighting, shadowMultiplier: [Double], nightRegions: [UInt8]? = nil,
                           nightPalette: HousePetPalette = .init()) -> CGImage? {
        guard let provider = image.dataProvider?.data, let pointer = CFDataGetBytePtr(provider) else { return nil }
        var bytes = Array(UnsafeBufferPointer(start: pointer, count: CFDataGetLength(provider)))
        var coatStrengths = [Double](repeating: 0, count: 5)
        if nightRegions != nil {
            let colours = ["#FFFFFF", nightPalette.base, nightPalette.second, nightPalette.white, nightPalette.base]
            for (region, hex) in colours.enumerated() {
                let rgb = UInt32(hex.dropFirst(), radix: 16) ?? 0
                let red = Double((rgb >> 16) & 255), green = Double((rgb >> 8) & 255), blue = Double(rgb & 255)
                let luminance = (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
                coatStrengths[region] = min(1, max(0, (0.40 - luminance) / 0.20))
            }
        }
        for row in 0..<image.height {
            for column in 0..<image.width {
                let index = row * image.bytesPerRow + column * 4, alpha = bytes[index + 3]
                guard alpha > 0 else { continue }
                let region = nightRegions?[row * image.width + column] ?? 0
                let coat = alpha == 255 && (1...4).contains(region)
                let luminance = (0.2126 * Double(bytes[index]) + 0.7152 * Double(bytes[index + 1]) + 0.0722 * Double(bytes[index + 2])) / 255
                let darkness = coat ? min(1, max(0, (0.28 - luminance) / 0.16)) * coatStrengths[Int(region)] : 0
                let edge = coat && (row == 0 || pointer[index - image.bytesPerRow + 3] == 0 ||
                    column == 0 || pointer[index - 1] == 0 || column == image.width - 1 || pointer[index + 7] == 0)
                for channel in 0..<3 {
                    let value = Double(bytes[index + channel]) / 255
                    var output = alpha < 255 ? value * shadowMultiplier[channel] : value * lighting.mul[channel] + lighting.add[channel]
                    if coat {
                        output = max(output, [0.12, 0.14, 0.18][channel] * darkness)
                        if edge { output += max(0, [0.34, 0.40, 0.50][channel] - output) * 0.16 * darkness }
                    } else if alpha == 255 && region == 6 {
                        output += max(0, value - output) * 0.12
                    }
                    bytes[index + channel] = UInt8((min(1, max(0, output)) * 255).rounded())
                }
            }
        }
        return try? HousePetRecolor.image(width: image.width, height: image.height, rgba: bytes)
    }

    func regions(pet: HousePet) -> [[UInt8]]? {
        if let frames = regionFrames[pet.pattern] { return frames }
        guard let rig, let directory, let file = rig.sheets[pet.pattern], !file.contains("/"), !file.contains("\\"),
              let sheet = try? HousePetSheet.load(from: directory.appendingPathComponent(file)) else { return nil }
        let width = rig.frameSize[0], height = rig.frameSize[1]
        guard sheet.width >= rig.columns * width, sheet.height >= ((rig.frameCount + rig.columns - 1) / rig.columns) * height else { return nil }
        let frames = (0..<rig.frameCount).map { frame in
            (0..<(width * height)).map { pixel in
                let row = frame / rig.columns * height + pixel / width
                let column = frame % rig.columns * width + pixel % width
                return sheet.rgba[(row * sheet.width + column) * 4] & 15
            }
        }
        regionFrames[pet.pattern] = frames
        return frames
    }

    func frame(pet: HousePet, pose: HousePetPose, night: Bool, lit: Bool, unlitImage: CGImage?, litImage: CGImage?) -> CGImage? {
        guard let rig, let directory, let frames = try? cache.frames(pet: pet, rig: rig, directory: directory, phase: "day"),
              frames.indices.contains(pose.frameIndex) else { return nil }
        let frame = frames[pose.frameIndex]
        let nightLight = rig.lighting["night"] ?? .init()
        var lighting = rig.lighting[night ? (lit ? "nightLit" : "night") : (lit ? "dayLit" : "day")] ?? .init()
        if night, lit, let unlitImage, let litImage,
           let unlitSample = Self.sample(unlitImage, at: pose.point), let litSample = Self.sample(litImage, at: pose.point),
           let ratio = Self.ratio(lit: litSample, unlit: unlitSample) {
            lighting = .init(mul: zip(nightLight.mul, ratio).map(*), add: [0, 0, 0])
        }
        let nightRegions = night ? regions(pet: pet)?[pose.frameIndex] : nil
        return Self.illuminate(frame, lighting: lighting, shadowMultiplier: night ? nightLight.mul : [1, 1, 1],
                               nightRegions: nightRegions, nightPalette: pet.palette)
    }

    func draw(in context: CGContext, pets: [HousePet], world: HousePetWorld, scene: HouseCutawaySceneFile,
              byRoom: Bool = true, context state: HousePetContext, date: Date,
              unlit: CGImage?, lit: CGImage?, poses: [String: HousePetPose] = [:]) {
        guard state.enabled, let rig, let behavior else { return }
        let active = pets.filter { $0.enabled && !$0.deleted }
        let resolved = behavior.poses(active, world: world, context: state, at: date, overrides: poses)
        var ordered: [(HousePet, HousePetPose)] = []
        for pet in active {
            guard let pose = resolved[pet.id] else { continue }
            ordered.append((pet, pose))
        }
        ordered.sort { left, right in
            if left.1.point.y == right.1.point.y { return left.0.id < right.0.id }
            return left.1.point.y < right.1.point.y
        }
        for (pet, pose) in ordered where pose.visible {
            guard let module = scene.modules[byRoom ? pose.room : pose.module],
                  let image = frame(pet: pet, pose: pose, night: state.night, lit: state.lights[pose.room] == true, unlitImage: unlit, litImage: lit) else { continue }
            if let silhouette = Self.silhouette(image, base: pet.palette.base) {
                context.saveGState(); context.concatenate(Self.transform(rig: rig, pose: pose))
                Self.drawImage(silhouette, in: context, rect: CGRect(x: 0, y: 0, width: rig.frameSize[0], height: rig.frameSize[1]))
                context.restoreGState()
            }
            Self.drawFrame(image, in: context, rig: rig, pose: pose, polygons: module.visible ?? [module.region])
        }
    }

    static func silhouette(_ image: CGImage, base: String) -> CGImage? {
        guard var bytes = pixels(image), let value = UInt32(base.dropFirst(), radix: 16) else { return nil }
        let colour = [Int((value >> 16) & 255), Int((value >> 8) & 255), Int(value & 255)].map { UInt8((Double($0) * 0.65).rounded()) }
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha: UInt8 = bytes[offset + 3] == 255 ? 77 : 0
            for channel in 0..<3 { bytes[offset + channel] = alpha == 0 ? 0 : colour[channel] }
            bytes[offset + 3] = alpha
        }
        return try? HousePetRecolor.image(width: image.width, height: image.height, rgba: bytes)
    }

    static func drawFrame(_ image: CGImage, in context: CGContext, rig: HousePetRig, pose: HousePetPose, polygons: [[[Double]]]) {
        let path = CGMutablePath()
        for polygon in polygons where polygon.count >= 3 {
            let points = polygon.filter { $0.count >= 2 }.map { CGPoint(x: $0[0], y: $0[1]) }
            path.addLines(between: points); path.closeSubpath()
        }
        guard !path.isEmpty else { return }
        context.saveGState()
        context.addPath(path); context.clip(using: .evenOdd)
        context.concatenate(transform(rig: rig, pose: pose))
        drawImage(image, in: context, rect: CGRect(x: 0, y: 0, width: rig.frameSize[0], height: rig.frameSize[1]))
        context.restoreGState()
    }

    static func drawImage(_ image: CGImage, in context: CGContext, rect: CGRect) {
        context.saveGState(); context.interpolationQuality = .none
        context.translateBy(x: rect.minX, y: rect.maxY); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size)); context.restoreGState()
    }
}

@MainActor
final class HousePetSceneSession {
    let world: HousePetWorld
    let unlit: CGImage?
    let lit: CGImage?
    init?(source: HouseSceneSource, layout: [HouseLayoutCell]?, style: String?, config: HomeHouse, rooms: [HouseRoom]) {
        guard let spots = HousePetPainter.shared.spots, let (catalog, _) = HouseModuleAssets.load(phase: .day, style: style) else { return nil }
        let cells = source.layout ?? layout ?? HouseLayoutSolver.classicFour.map { cell in
            HouseLayoutCell(room: rooms.first { $0.module.rawValue == cell.module }?.key ?? cell.module, module: cell.module, col: cell.col, row: cell.row)
        }
        var offsets: [String: HousePetPoint] = [:]
        for cell in cells where !source.byRoom {
            guard let art = catalog.modules[cell.module], let module = source.scene.modules[source.byRoom ? cell.room : cell.module],
                  let target = module.region.first, let original = art.region.first, target.count >= 2, original.count >= 2 else { continue }
            offsets[HouseDecor.roomKey(cell)] = .init(x: target[0] - original[0], y: target[1] - original[1])
        }
        let decor = HouseModuleAssets.decorations(layout: cells, catalog: catalog, phase: .day, config: config).map(\.placement)
        let origin = source.scene.origin ?? [0, 0]
        world = HousePetWorld(layout: cells, catalog: catalog, spots: spots, style: HouseStyles.resolve(style),
                              origin: .init(x: origin[0], y: origin[1]), offsets: offsets,
                              decor: decor, items: HouseModuleAssets.decorCatalog)
        unlit = source.unlit.cgImage(forProposedRect: nil, context: nil, hints: nil)
        lit = source.lit.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

struct HousePetsLayer: View {
    let source: HouseSceneSource
    let rooms: [HouseRoom]
    let layout: [HouseLayoutCell]?
    let style: String?
    let config: HomeHouse
    let phase: HousePhase
    var restOnly = false
    var date: Date? = nil
    var poses: [String: HousePetPose] = [:]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    @State private var visible = true
    @State private var session: HousePetSceneSession?
    @State private var changedAt: Date?
    @State private var changedRoom: String?

    static func state(rooms: [HouseRoom], phase: HousePhase, config: HomeHouse, restOnly: Bool) -> HousePetContext {
        let lights = Dictionary(rooms.map { ($0.key, $0.lighting.levels.values.contains { $0 > 0 }) }, uniquingKeysWith: { $0 || $1 })
        let tv = Set(rooms.filter { room in room.devices.contains { $0.on && $0.category == .tv } }.map(\.key))
        return .init(night: phase == .night, lights: lights, tvRooms: tv, rooms: Set(rooms.map(\.key)),
                     petIDs: (config.pets ?? [:]).values.filter { $0.enabled && !$0.deleted }.map(\.id).sorted(),
                     restOnly: restOnly, enabled: config.petPrefs?.enabled ?? true)
    }

    private var fingerprint: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var appearance = config; appearance.pets = nil; appearance.petPrefs = nil
        let encoded = (try? encoder.encode(appearance).base64EncodedString()) ?? ""
        let cells = (try? encoder.encode(source.layout ?? layout).base64EncodedString()) ?? ""
        return encoded + "|" + cells + "|" + phase.assetName + "|" + (style ?? "") + "|\(ObjectIdentifier(source.unlit))|\(ObjectIdentifier(source.lit))"
    }

    var body: some View {
        let paused = reduceMotion || lowPower
        let state = Self.state(rooms: rooms, phase: phase, config: config, restOnly: restOnly || paused)
        TimelineView(.animation(minimumInterval: paused ? 10 : restOnly ? 1.0 / 3 : 1.0 / 8, paused: !visible || date != nil)) { tick in
            let now = date ?? tick.date
            let time = paused ? Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 10) * 10) : now
            Canvas { graphics, _ in
                if let session, let image = image(session: session, state: state, date: time) {
                    graphics.draw(Image(decorative: image, scale: 1), in: CGRect(origin: .zero, size: source.artSize))
                }
            }
        }
        .frame(width: source.artSize.width, height: source.artSize.height)
        .background(HousePetVisibilityProbe(visible: $visible))
        .allowsHitTesting(false).accessibilityHidden(true)
        .task(id: fingerprint) {
            session = HousePetSceneSession(source: source, layout: layout, style: style, config: config, rooms: rooms)
        }
        .onChange(of: state.lights) { old, new in
            changedAt = Date(); changedRoom = new.keys.sorted().first { old[$0] != new[$0] }
        }
        .onChange(of: state.tvRooms) { old, new in changedAt = Date(); changedRoom = old.symmetricDifference(new).sorted().first }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled }
    }

    private func image(session: HousePetSceneSession, state: HousePetContext, date: Date) -> CGImage? {
        guard state.enabled, let context = CGContext(data: nil, width: Int(source.artSize.width), height: Int(source.artSize.height),
                                                    bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: 0, y: source.artSize.height); context.scaleBy(x: 1, y: -1)
        var state = state; state.changedAt = changedAt; state.changedRoom = changedRoom
        HousePetPainter.shared.draw(in: context, pets: Array((config.pets ?? [:]).values), world: session.world, scene: source.scene,
                                    byRoom: source.byRoom, context: state, date: date, unlit: session.unlit, lit: session.lit, poses: poses)
        return context.makeImage()
    }
}

struct HousePetVisibilityProbe: NSViewRepresentable {
    @Binding var visible: Bool
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.changed = { visible = $0 }; return view }
    func updateNSView(_ view: Probe, context: Context) {}
    final class Probe: NSView {
        var changed: ((Bool) -> Void)?
        private var observation: Observation?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = nil
            if let window {
                let token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self, weak window] _ in
                    MainActor.assumeIsolated { self?.changed?(window?.occlusionState.contains(.visible) == true) }
                }
                observation = Observation(token)
            }
            let visible = window?.occlusionState.contains(.visible) == true
            DispatchQueue.main.async { [weak self] in self?.changed?(visible) }
        }
    }
    private final class Observation: @unchecked Sendable {
        let token: NSObjectProtocol
        init(_ token: NSObjectProtocol) { self.token = token }
        deinit { NotificationCenter.default.removeObserver(token) }
    }
}
