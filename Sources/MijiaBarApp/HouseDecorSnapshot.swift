import AppKit
import ImageIO
import SwiftUI
import MijiaCore

extension Snapshot {
    static func houseDecor(dir: String, dateString: String?) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir)
        do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        catch { fputs("house decor snapshot: \(error)\n", stderr); exit(1) }
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        func date(_ string: String) -> Date? {
            guard let value = formatter.date(from: string), formatter.string(from: value) == string else { return nil }; return value
        }
        guard let today = date(dateString ?? "2026-07-01"), let catalog = HouseModuleAssets.decorCatalog else {
            fputs("house decor snapshot: invalid date or missing decor catalog\n", stderr); exit(1)
        }
        let model = AppModel(mock: true); model.addHouseFixtureDemo()
        let modules: [HouseModule] = [.bedroom, .study, .bathroom, .living, .kitchen, .balcony]
        let positions = [(0, 0), (1, 0), (2, 0), (0, 1), (2, 1), (2, 2)]
        let layout = zip(modules, positions).map { module, position in
            let room = model.devices.first { HouseModule.from(roomName: $0.roomName) == module }.map(HouseResolver.roomKey) ?? "style-\(module.rawValue)"
            return HouseLayoutCell(room: room, module: module.rawValue, col: position.0, row: position.1, level: 0)
        }
        func write(_ image: CGImage, _ name: String) {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { exit(1) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { exit(1) }
            do { try (data as Data).write(to: out.appendingPathComponent(name + ".png")) }
            catch { fputs("house decor snapshot: \(error)\n", stderr); exit(1) }
        }
        func canvas(width: Int, height: Int) -> CGContext {
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
            context.interpolationQuality = .none; return context
        }
        func label(_ text: String, x: Double, y: Double, context: CGContext) {
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
            let size = (text as NSString).size(withAttributes: attributes)
            let point = NSPoint(x: max(0, min(x, Double(context.width) - size.width)), y: max(0, min(y, Double(context.height) - size.height)))
            (text as NSString).draw(at: point, withAttributes: attributes)
            NSGraphicsContext.restoreGraphicsState()
        }
        func render(style: String, prefix: String, config: HomeHouse, date: Date, phases: [HousePhase] = [.day, .night], overlay: Bool = false) {
            for phase in phases {
                guard let (modules, images) = HouseModuleAssets.load(phase: phase, style: style) else {
                    fputs("house decor snapshot: missing modules \(style)\n", stderr); exit(1)
                }
                let decor = HouseModuleAssets.decorations(layout: layout, catalog: modules, phase: phase, config: config, date: date)
                let result = HouseComposer.compose(.init(layout: layout, catalog: modules, images: images, night: phase == .night,
                                                        wallCaps: HouseModuleAssets.wallCaps(style: style), decor: decor))
                guard let image = phase == .day ? result.unlit : result.lit else { exit(1) }
                guard image.width == result.width, image.height == result.height else {
                    fputs("house decor snapshot: composer pixel size mismatch\n", stderr); exit(1)
                }
                write(image, prefix + "-\(phase.assetName)-\(phase == .day ? "unlit" : "lit")")
                if overlay && phase == .day {
                    let context = canvas(width: image.width, height: image.height)
                    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                    if let scene = try? JSONDecoder().decode(HouseCutawaySceneFile.self, from: result.sceneJSON) {
                        for slot in scene.decorSlots ?? [] {
                            let rect = CGRect(x: slot.rect[0], y: Double(image.height) - slot.rect[1] - slot.rect[3], width: slot.rect[2], height: slot.rect[3])
                            context.setStrokeColor((slot.item == nil ? NSColor.white : NSColor.systemYellow).cgColor)
                            context.setLineWidth(2); context.setLineDash(phase: 0, lengths: slot.item == nil ? [4, 3] : [])
                            context.stroke(rect)
                            label("\(slot.room)/\(slot.slot)" + (slot.hidden == nil ? "" : " (wall cut)"), x: rect.minX, y: rect.maxY + 2, context: context)
                        }
                    }
                    if let marked = context.makeImage() { write(marked, "decor-slots-\(style)-day") }
                    do { try result.sceneJSON.write(to: out.appendingPathComponent("decor-slots-\(style).json")) }
                    catch { fputs("house decor snapshot: \(error)\n", stderr); exit(1) }
                }
            }
        }
        for style in ["cozy-wood", "japanese", "modern"] {
            guard let (modules, _) = HouseModuleAssets.load(phase: .day, style: style) else { exit(1) }
            var shown = Set<Int>()
            let slots = layout.flatMap { cell in (modules.modules[cell.module]?.decor ?? []).map { (room: cell.room, slot: $0) } }
            let hidden = HouseDecor.hiddenSlots(layout: layout, catalog: modules), regular = catalog.items.filter { $0.category != "holiday" }
            do {
                var config = HomeHouse(), cursor = 0, assigned: [Int: Int] = [:]
                config.decorPrefs = HouseDecorPrefs(seasonal: false)
                func assign(_ item: Int, visited: inout Set<Int>) -> Bool {
                    for index in slots.indices where !hidden.contains("\(slots[index].room)/\(slots[index].slot.id)") && regular[item].fits(slots[index].slot) {
                        guard visited.insert(index).inserted else { continue }
                        if let previous = assigned[index], !assign(previous, visited: &visited) { continue }
                        assigned[index] = item; return true
                    }
                    return false
                }
                let order = regular.indices.filter { !shown.contains($0) } + regular.indices.filter { shown.contains($0) }
                for item in order { var visited = Set<Int>(); _ = assign(item, visited: &visited) }
                for index in slots.indices {
                    let slot = slots[index], fitting = regular.indices.filter { regular[$0].fits(slot.slot) }
                    guard !fitting.isEmpty else { fputs("house decor snapshot: no fitting item for \(slot.room)/\(slot.slot.id)\n", stderr); continue }
                    let item = regular[assigned[index] ?? fitting[cursor % fitting.count]]; cursor += 1
                    if config.decor == nil { config.decor = [:] }
                    config.decor?["\(slot.room)/\(slot.slot.id)"] = .init(item: item.id, updatedAt: today)
                }
                shown.formUnion(assigned.values)
                render(style: style, prefix: "\(style)-decor", config: config, date: today, overlay: true)
                let home = model.houseHomeKey
                model.houseEdit("snapshot") { file in
                    file.setLayout(home: home, layout: layout)
                    file.setStyle(home: home, style: style)
                    file.setDecorPrefs(home: home, enabled: true, seasonal: false)
                    file.resetDecor(home: home)
                    for (key, entry) in config.decor ?? [:] { file.setDecor(home: home, key: key, item: entry.item, now: today) }
                }
                let previousAppearance = Snapshot.appearance
                for (suffix, appearance) in [("", NSAppearance.Name.darkAqua), ("-light", .aqua)] {
                    Snapshot.appearance = NSAppearance(named: appearance)
                    Snapshot.render(HousePilotHost(editing: true, editTab: .style, decorDate: today).environmentObject(model),
                                    out.appendingPathComponent("edit-decor-\(style)\(suffix).png"), size: HouseWindow.editSize)
                }
                Snapshot.appearance = previousAppearance
            }
            for index in regular.indices where !shown.contains(index) { fputs("house decor snapshot: no visible fitting slot for \(regular[index].id) style=\(style)\n", stderr) }
            var config = HomeHouse(); config.decorPrefs = HouseDecorPrefs(enabled: false)
            render(style: style, prefix: "\(style)-nodecor", config: config, date: today)
        }
        for (season, day) in [("spring", "2027-02-06"), ("xmas", "2026-12-25"), ("midautumn", "2026-09-25"), ("halloween", "2026-10-31")] {
            render(style: "cozy-wood", prefix: "cozy-wood-holiday-\(season)", config: HomeHouse(), date: date(day)!)
        }
        render(style: "japanese", prefix: "japanese-holiday-xmas", config: HomeHouse(), date: date("2026-12-25")!, phases: [.night])

        let sprites = catalog.items.map { item in
            ["day", "night"].map { phase in
                (item.surface == "wall" ? [Optional("nw"), Optional("ne")] : [nil]).compactMap { wall in
                    item.sprites[phase]?.file(wall: wall).flatMap { HouseModuleAssets.decorImage($0) }
                }
            }
        }
        let phaseWidth = max(120, sprites.flatMap { $0 }.flatMap { $0 }.map { $0.width * 3 + 24 }.max() ?? 0)
        let tileWidth = phaseWidth * 2
        let tileHeight = max(160, sprites.flatMap { $0 }.map { $0.reduce(0) { $0 + $1.height * 3 + 12 } + 48 }.max() ?? 0)
        let columns = 4, rows = (catalog.items.count + columns - 1) / columns
        let sheet = canvas(width: columns * tileWidth, height: max(1, rows) * tileHeight)
        sheet.setFillColor(NSColor(white: 0.45, alpha: 1).cgColor)
        sheet.fill(CGRect(x: 0, y: 0, width: sheet.width, height: sheet.height))
        for (index, item) in catalog.items.enumerated() {
            let left = (index % columns) * tileWidth, top = (index / columns) * tileHeight
            for (phaseIndex, phase) in ["day", "night"].enumerated() {
                var offset = 24
                for image in sprites[index][phaseIndex] {
                    let width = image.width * 3, height = image.height * 3
                    let x = left + phaseIndex * tileWidth / 2 + (tileWidth / 2 - width) / 2
                    let y = sheet.height - top - offset - height
                    sheet.draw(image, in: CGRect(x: x, y: y, width: width, height: height))
                    offset += height + 12
                }
                label(phase, x: Double(left + phaseIndex * tileWidth / 2 + 8), y: Double(sheet.height - top - 16), context: sheet)
            }
            label(item.id, x: Double(left + 8), y: Double(sheet.height - top - tileHeight + 8), context: sheet)
        }
        if let image = sheet.makeImage() { write(image, "decor-catalog-sheet") }
        exit(0)
    }
}
