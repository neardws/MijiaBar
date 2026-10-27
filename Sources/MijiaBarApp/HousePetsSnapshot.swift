import AppKit
import ImageIO
import SwiftUI
import MijiaCore

@MainActor
enum HousePetDemo {
    static var pets: [HousePet] {
        [HousePet(id: "p_100001", name: "橘子", pattern: "tabbyWhite"),
         HousePet(id: "p_100002", name: "煤球", pattern: "bicolor", palette: .init(base: "#2E2B30", second: "#1C1A1E", white: "#F2F0EC", eye: "#E9C24A")),
         HousePet(id: "p_100003", name: "花花", pattern: "calico", palette: .init(base: "#E59A45", second: "#2F2A2C", white: "#F5F0E8", eye: "#7DB2C8"))]
    }

    static func layout(model: AppModel) -> [HouseLayoutCell] {
        return HouseSnapshotLayouts.pets.map { cell in
            let module = HouseModule(rawValue: cell.module)!
            let key = model.devices.first { HouseModule.from(roomName: $0.roomName) == module }.map(HouseResolver.roomKey) ?? "style-\(module.rawValue)"
            return HouseLayoutCell(room: key, module: module.rawValue, col: cell.col, row: cell.row, level: cell.level)
        }
    }

    static func pose(world: HousePetWorld, rig: HousePetRig, module: String, action: String, facing: String = "SE", frame: Int = 0) -> HousePetPose? {
        let candidates = world.spots.filter { world.nodes[$0.node].module == module }
        let preferred = module == "bedroom" && ["sleep", "groom"].contains(action) ? "bed" : module == "living" && action == "sit" ? "rug" : nil
        let spot = preferred.flatMap { id in candidates.first { $0.id.hasSuffix("/" + id) } }
            ?? candidates.first { action == "sleep" ? $0.kind == "sleep" : $0.kind == "sit" }
            ?? candidates.first
        guard let node = spot.map({ world.nodes[$0.node] }) ?? world.nodes.first(where: { $0.module == module }) else { return nil }
        var point = spot?.point ?? node.point
        if action == "walk", let edge = world.edges[node.id].first(where: { world.nodes[$0.node].room == node.room && !$0.jump }) {
            let target = world.nodes[edge.node].point
            point = .init(x: (node.point.x + target.x) / 2, y: (node.point.y + target.y) / 2)
        }
        let frames = rig.actions[action]?.frames[rig.mirror[facing] ?? facing] ?? [0]
        return .init(point: point, facing: facing, action: action, frameIndex: frames[min(frame, frames.count - 1)],
                     mirrored: rig.mirror[facing] != nil, jumpLift: action == "jump" ? Double(rig.cellPx) * 10 : 0, module: node.module, room: node.room)
    }
}

extension Snapshot {
    static func housePets(dir: String, dateString: String?, photos: [String]) {
        NSApplication.shared.setActivationPolicy(.accessory)
        do { try writeHousePets(dir: dir, dateString: dateString, photos: photos) }
        catch { fputs("house pets snapshot: \(error)\n", stderr); exit(1) }
        exit(0)
    }

    private static func writeHousePets(dir: String, dateString: String?, photos: [String]) throws {
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]; formatter.timeZone = .current
        let selected = dateString ?? "2026-07-01"
        let parsed = formatter.date(from: selected) ?? ISO8601DateFormatter().date(from: selected)
        guard let date = parsed, let rig = HousePetPainter.shared.rig else { throw HousePetError.resource }
        let model = AppModel(mock: true); model.addHouseFixtureDemo()
        let layout = HousePetDemo.layout(model: model), pets = HousePetDemo.pets
        let home = model.houseHomeKey
        model.houseEdit("snapshot") { file in
            file.setLayout(home: home, layout: layout)
            file.setDecorPrefs(home: home, enabled: true, seasonal: false, now: date)
            for pet in pets { try? file.setPet(home: home, pet: pet) }
        }
        var config = model.house.homes[home] ?? HomeHouse()

        func canvas(_ width: Int, _ height: Int) throws -> CGContext {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw HousePetError.resource }
            context.translateBy(x: 0, y: Double(height)); context.scaleBy(x: 1, y: -1); context.interpolationQuality = .none
            return context
        }
        func write(_ image: CGImage, _ name: String) throws {
            guard let destination = CGImageDestinationCreateWithURL(out.appendingPathComponent(name + ".png") as CFURL, "public.png" as CFString, 1, nil) else { throw HousePetError.resource }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw HousePetError.resource }
        }
        func label(_ text: String, at point: CGPoint, in context: CGContext) {
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            (text as NSString).draw(at: point, withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.labelColor])
            NSGraphicsContext.restoreGraphicsState()
        }
        func composed(style: String, phase: HousePhase, cells: [HouseLayoutCell]) throws -> (HouseSceneSource, HousePetSceneSession) {
            guard let source = HouseModuleAssets.composedScene(layout: cells, phase: phase, style: style, config: config, date: date),
                  let session = HousePetSceneSession(source: source, layout: cells, style: style, config: config, rooms: model.houseRooms) else { throw HousePetError.resource }
            return (source, session)
        }
        func render(source: HouseSceneSource, session: HousePetSceneSession, night: Bool, lights: Bool,
                    roster: [HousePet], poses: [String: HousePetPose]) throws -> CGImage {
            guard let base = lights ? session.lit : session.unlit else { throw HousePetError.resource }
            let context = try canvas(base.width, base.height)
            HousePetPainter.drawImage(base, in: context, rect: CGRect(x: 0, y: 0, width: base.width, height: base.height))
            let state = HousePetContext(night: night, lights: Dictionary(uniqueKeysWithValues: session.world.rooms.map { ($0, lights) }),
                                        rooms: session.world.rooms, petIDs: roster.map(\.id))
            HousePetPainter.shared.draw(in: context, pets: roster, world: session.world, scene: source.scene, context: state,
                                        date: date, unlit: session.unlit, lit: session.lit, poses: poses)
            guard let image = context.makeImage() else { throw HousePetError.resource }; return image
        }
        for style in ["cozy-wood", "japanese", "modern"] {
            config.style = style
            model.houseEdit("snapshot") { $0.setStyle(home: home, style: style) }
            for phase in [HousePhase.day, .night] {
                let (source, session) = try composed(style: style, phase: phase, cells: layout)
                var poses: [String: HousePetPose] = [:]
                poses[pets[0].id] = HousePetDemo.pose(world: session.world, rig: rig, module: "living", action: "sit", facing: "SE")
                poses[pets[1].id] = HousePetDemo.pose(world: session.world, rig: rig, module: "study", action: "walk", frame: 2)
                poses[pets[2].id] = HousePetDemo.pose(world: session.world, rig: rig, module: "bedroom", action: phase == .night ? "sleep" : "groom")
                for lights in [false, true] {
                    let name = "pets-\(style)-\(phase.assetName)-\(lights ? "lit" : "unlit")"
                    let image = try render(source: source, session: session, night: phase == .night, lights: lights, roster: pets, poses: poses)
                    try write(image, name)
                    let larger = try canvas(image.width * 2, image.height * 2)
                    HousePetPainter.drawImage(image, in: larger, rect: CGRect(x: 0, y: 0, width: image.width * 2, height: image.height * 2))
                    if let image = larger.makeImage() { try write(image, name + "-2x") }
                }
                if phase == .day { try worldOverlay(source: source, session: session, style: style, canvas: canvas, write: write) }
            }
            let (source, session) = try composed(style: style, phase: .day, cells: [.init(room: "actions", module: "living", col: 0, row: 0, level: 0)])
            let actions = [("idle", "SE"), ("walk", "SE"), ("walk", "NE"), ("sit", "SE"), ("groom", "SE"), ("lookup", "NE"), ("sleep", "SE"), ("stretch", "SE"), ("jump", "SE")]
            let width = Int(source.artSize.width), height = Int(source.artSize.height) + 28
            let sheet = try canvas(width * 3, height * 3)
            for (index, action) in actions.enumerated() {
                guard let pose = HousePetDemo.pose(world: session.world, rig: rig, module: "living", action: action.0, facing: action.1, frame: 2) else { throw HousePetError.resource }
                let pet = pets[index % pets.count]
                let image = try render(source: source, session: session, night: false, lights: false, roster: [pet], poses: [pet.id: pose])
                let rect = CGRect(x: index % 3 * width, y: index / 3 * height, width: width, height: height - 28)
                HousePetPainter.drawImage(image, in: sheet, rect: rect)
                label(action.0 + " " + action.1, at: CGPoint(x: rect.minX + 12, y: rect.maxY + 4), in: sheet)
            }
            if let image = sheet.makeImage() { try write(image, "pets-actions-\(style)") }
        }
        model.houseEdit("snapshot") { $0.setStyle(home: home, style: "cozy-wood") }
        let previousAppearance = appearance
        defer { appearance = previousAppearance }
        for (name, value) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            appearance = NSAppearance(named: value)
            Snapshot.render(HousePilotHost(editing: true, editTab: .pets, decorDate: date).environmentObject(model),
                            out.appendingPathComponent("pets-editor-\(name).png"), size: CGSize(width: 1041, height: 1440))
        }
        appearance = NSAppearance(named: .aqua)
        for (name, hour) in [("day", 10), ("night", 22)] {
            let time = Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
            Snapshot.render(HouseListEmbed(snapshotDate: time, snapshotPhase: name == "day" ? .day : .night).environmentObject(model).padding(12).background(Theme.bg),
                            out.appendingPathComponent("pets-menubar-\(name).png"), size: CGSize(width: 360, height: 340))
        }
        for (index, file) in photos.enumerated() {
            let draft = try HousePetPhotoDraft.load(URL(fileURLWithPath: file))
            let pet = HousePet(pattern: draft.result.pattern, palette: draft.result.palette)
            let frameScale = 9, petWidth = rig.frameSize[0] * frameScale, petHeight = rig.frameSize[1] * frameScale
            let photoWidth = Int((320 * Double(draft.image.width) / Double(draft.image.height)).rounded())
            let height = max(480, petHeight + 70), width = photoWidth + 270 + petWidth * 3
            let card = try canvas(width, height)
            card.setFillColor(NSColor.windowBackgroundColor.cgColor); card.fill(CGRect(x: 0, y: 0, width: width, height: height))
            HousePetPainter.drawImage(draft.image, in: card, rect: CGRect(x: 0, y: 20, width: photoWidth, height: 320))
            label("→", at: CGPoint(x: photoWidth + 12, y: 140), in: card)
            let names = ["solid": L("纯色 / Solid", "纯色 / Solid"), "tabby": L("虎斑 / Tabby", "虎斑 / Tabby"),
                         "tabbyWhite": L("虎斑加白 / Tabby & white", "虎斑加白 / Tabby & white"), "bicolor": L("双色 / Bicolor", "双色 / Bicolor"),
                         "calico": L("三花 / Calico", "三花 / Calico"), "colorpoint": L("重点色 / Colorpoint", "重点色 / Colorpoint")]
            label(names[pet.pattern] ?? pet.pattern, at: CGPoint(x: photoWidth + 35, y: 45), in: card)
            let maskPixels = draft.mask.flatMap { [$0, $0, $0, UInt8(255)] }
            let maskImage = try HousePetRecolor.image(width: draft.image.width, height: draft.image.height, rgba: maskPixels)
            HousePetPainter.drawImage(maskImage, in: card, rect: CGRect(x: 12, y: 352, width: photoWidth / 3, height: 106))
            for (offset, hex) in [pet.palette.base, pet.palette.second, pet.palette.white, pet.palette.eye].enumerated() {
                card.setFillColor(NSColor(HousePetAppearanceFields.color(hex)).cgColor)
                card.fill(CGRect(x: photoWidth + 55 + offset * 42, y: 85, width: 32, height: 32))
                label(hex, at: CGPoint(x: photoWidth + 55, y: 130 + offset * 22), in: card)
            }
            for (offset, action) in ["sit", "walk", "sleep"].enumerated() {
                let pose = HousePetPose(point: .init(x: 0, y: 0), action: action, frameIndex: rig.frame(action: action, facing: "SE", elapsed: 0.5).index, module: "", room: "")
                guard let frame = HousePetPainter.shared.frame(pet: pet, pose: pose, night: false, lit: false, unlitImage: nil, litImage: nil) else { throw HousePetError.resource }
                HousePetPainter.drawImage(frame, in: card, rect: CGRect(x: photoWidth + 270 + offset * petWidth, y: 20 + max(0, (320 - petHeight) / 2), width: petWidth, height: petHeight))
            }
            if let image = card.makeImage() { try write(image, "photo-\(index + 1)") }
        }
    }

    private static func worldOverlay(source: HouseSceneSource, session: HousePetSceneSession, style: String,
                                     canvas: (Int, Int) throws -> CGContext, write: (CGImage, String) throws -> Void) throws {
        guard let base = session.unlit else { throw HousePetError.resource }
        let context = try canvas(base.width, base.height)
        HousePetPainter.drawImage(base, in: context, rect: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        context.setFillColor(CGColor(red: 0, green: 0.9, blue: 0.5, alpha: 0.7))
        for node in session.world.nodes { context.fillEllipse(in: CGRect(x: node.point.x - 2, y: node.point.y - 2, width: 4, height: 4)) }
        context.setFillColor(CGColor(red: 1, green: 0.6, blue: 0, alpha: 1))
        for spot in session.world.spots { context.fillEllipse(in: CGRect(x: spot.point.x - 4, y: spot.point.y - 4, width: 8, height: 8)) }
        if let first = session.world.nodes.first {
            let reachable = session.world.nodes.reversed().first { !session.world.path(from: first.id, to: $0.id).isEmpty }
            if let reachable {
                let path = session.world.path(from: first.id, to: reachable.id).map { session.world.nodes[$0].point }
                context.setStrokeColor(CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 1)); context.setLineWidth(3)
                context.addLines(between: path.map { CGPoint(x: $0.x, y: $0.y) }); context.strokePath()
            }
        }
        if let image = context.makeImage() { try write(image, "pets-world-\(style)") }
    }
}
