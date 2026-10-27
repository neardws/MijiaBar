import AppKit
import ImageIO
import SwiftUI
import MijiaCore

@MainActor enum HouseFreeDecorDemo {
    static let layout: [HouseLayoutCell] = [.init(room: "living", module: "living", col: 0, row: 1, level: 0),
                                          .init(room: "bedroom", module: "bedroom", col: 0, row: 0, level: 0)]
    static func config() -> HomeHouse? {
        guard let (catalog, _) = HouseModuleAssets.load(phase: .day, style: "cozy-wood"), let items = HouseModuleAssets.decorCatalog else { return nil }
        let grids = HouseModuleAssets.freeGrids(layout: layout, catalog: catalog, style: "cozy-wood")
        var config = HomeHouse(); config.style = "cozy-wood"; config.layout = layout; config.decorPrefs = .init(seasonal: false); config.freeDecor = [:]
        let fixed = HouseDecor.resolve(layout: layout, catalog: catalog, prefs: .init(seasonal: false), items: items)
        for (room, item) in [("living", "monstera"), ("bedroom", "cat_bed"), ("living", "succulent")] {
            guard let grid = grids.first(where: { $0.room == room }) else { return nil }
            let candidates = grid.cells.sorted {
                let left = abs($0.col - 7) + abs($0.row - 5), right = abs($1.col - 7) + abs($1.row - 5)
                return left == right ? ($0.row == $1.row ? $0.col < $1.col : $0.row < $1.row) : left < right
            }
            guard let cell = candidates.first(where: { HouseFreeDecor.validate(room: room, item: item, cell: $0.array, grids: grids, items: items, entries: config.freeDecor ?? [:], fixed: fixed) == nil }) else { return nil }
            let key = room + "/" + HouseFreeDecor.nextID(room: room, entries: config.freeDecor ?? [:])
            config.freeDecor?[key] = .init(item: item, cell: cell.array, updatedAt: Date(timeIntervalSince1970: 0))
        }
        return config
    }
    static func detour(world: HousePetWorld, baseline: HousePetWorld) -> [HousePetPoint] {
        func key(_ node: HousePetWorld.Node) -> String { "\(node.room)/\(node.col)/\(node.row)" }
        let original = Dictionary(uniqueKeysWithValues: baseline.nodes.map { (key($0), $0.id) })
        let surviving = Set(world.nodes.map(key))
        for start in world.nodes {
            guard let from = original[key(start)] else { continue }
            for end in world.nodes.reversed() where end.room == start.room && end.id != start.id {
                guard let to = original[key(end)] else { continue }
                let before = baseline.path(from: from, to: to, room: start.room)
                guard before.contains(where: { !surviving.contains(key(baseline.nodes[$0])) }) else { continue }
                let after = world.path(from: start.id, to: end.id, room: start.room)
                if !after.isEmpty { return after.map { world.nodes[$0].point } }
            }
        }
        return []
    }
}

extension Snapshot {
    static func houseFreeDecor(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let out = URL(fileURLWithPath: dir), date = Date(timeIntervalSince1970: 1782878400)
        guard let config = HouseFreeDecorDemo.config(), let items = HouseModuleAssets.decorCatalog,
              let spots = HousePetPainter.shared.spots else { fputs("free decor snapshot: missing fixture/resources\n", stderr); exit(1) }
        do { try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        catch { fputs("free decor snapshot: \(error)\n", stderr); exit(1) }
        func write(_ image: CGImage, _ name: String) {
            guard let destination = CGImageDestinationCreateWithURL(out.appendingPathComponent(name + ".png") as CFURL, "public.png" as CFString, 1, nil) else { exit(1) }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { exit(1) }
        }
        for phase in [HousePhase.day, .night] {
            guard let (catalog, images) = HouseModuleAssets.load(phase: phase, style: "cozy-wood") else { exit(1) }
            let decor = HouseModuleAssets.decorations(layout: HouseFreeDecorDemo.layout, catalog: catalog, phase: phase, config: config, date: date)
            let result = HouseComposer.compose(.init(layout: HouseFreeDecorDemo.layout, catalog: catalog, images: images, night: phase == .night,
                                                    wallCaps: HouseModuleAssets.wallCaps(style: "cozy-wood"), decor: decor))
            guard let image = phase == .day ? result.unlit : result.lit else { exit(1) }
            write(image, "free-decor-after-" + phase.assetName)
            do { try result.sceneJSON.write(to: out.appendingPathComponent("free-decor-" + phase.assetName + ".json")) } catch { exit(1) }
            guard phase == .day else { continue }
            var before = config; before.freeDecor = nil
            let prior = HouseComposer.compose(.init(layout: HouseFreeDecorDemo.layout, catalog: catalog, images: images,
                decor: HouseModuleAssets.decorations(layout: HouseFreeDecorDemo.layout, catalog: catalog, phase: .day, config: before, date: date)))
            if let image = prior.unlit { write(image, "free-decor-before-day") }
            let grids = HouseModuleAssets.freeGrids(layout: HouseFreeDecorDemo.layout, catalog: catalog, style: "cozy-wood")
            let context = HouseFreeDecorCanvas(grids: grids, layout: HouseFreeDecorDemo.layout, origin: [Double(result.originX), Double(result.originY)], config: config, items: items, fixed: decor.map(\.placement).filter { $0.freeCell == nil })
            func canvas() -> CGContext {
                guard let canvas = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
                canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                canvas.translateBy(x: 0, y: CGFloat(image.height)); canvas.scaleBy(x: 1, y: -1); return canvas
            }
            let gridCanvas = canvas()
            for grid in grids {
                let occupied = Set((config.freeDecor ?? [:]).filter { HouseFreeDecor.room(of: $0.key) == grid.room }.values.flatMap { entry in
                    HouseFreeDecor.footprint(cell: entry.cell, size: items.items.first { $0.id == entry.item }?.size ?? "S")
                })
                for (row, line) in grid.walk.enumerated() {
                    for (col, token) in line.enumerated() {
                        let cell = HouseFreeDecor.Cell(col, row), point = context.point(grid: grid, cell: cell)
                        let color: NSColor = occupied.contains(cell) ? .systemYellow : (token == "#" || grid.protected.contains(cell) ? .systemRed : .systemGreen)
                        let width = 160.0 / Double(grid.scale), height = 66.0 / Double(grid.scale)
                        gridCanvas.beginPath(); gridCanvas.move(to: CGPoint(x: point.x, y: point.y - height))
                        gridCanvas.addLines(between: [CGPoint(x: point.x + width, y: point.y), CGPoint(x: point.x, y: point.y + height), CGPoint(x: point.x - width, y: point.y)])
                        gridCanvas.closePath(); gridCanvas.setFillColor(color.withAlphaComponent(0.35).cgColor); gridCanvas.setStrokeColor(color.cgColor)
                        gridCanvas.drawPath(using: .fillStroke)
                    }
                }
            }
            if let image = gridCanvas.makeImage() { write(image, "free-decor-grid-day") }
            let world = HousePetWorld(layout: HouseFreeDecorDemo.layout, catalog: catalog, spots: spots,
                                      origin: .init(x: Double(result.originX), y: Double(result.originY)), decor: decor.map(\.placement), items: items)
            let petCanvas = canvas(); petCanvas.setStrokeColor(NSColor.systemGreen.withAlphaComponent(0.5).cgColor)
            for node in world.nodes {
                for edge in world.edges[node.id] {
                    let target = world.nodes[edge.node]
                    petCanvas.move(to: CGPoint(x: node.point.x, y: node.point.y)); petCanvas.addLine(to: CGPoint(x: target.point.x, y: target.point.y)); petCanvas.strokePath()
                }
                petCanvas.setFillColor(NSColor.systemGreen.cgColor); petCanvas.fillEllipse(in: CGRect(x: node.point.x - 2, y: node.point.y - 2, width: 4, height: 4))
            }
            let baseline = HousePetWorld(layout: HouseFreeDecorDemo.layout, catalog: catalog, spots: spots,
                                         origin: .init(x: Double(result.originX), y: Double(result.originY)))
            let route = HouseFreeDecorDemo.detour(world: world, baseline: baseline)
            guard route.count > 1 else { fputs("free decor snapshot: no demonstrable detour\n", stderr); exit(1) }
            petCanvas.setStrokeColor(NSColor.systemBlue.cgColor); petCanvas.setLineWidth(3)
            petCanvas.addLines(between: route.map { CGPoint(x: $0.x, y: $0.y) }); petCanvas.strokePath()
            if let image = petCanvas.makeImage() { write(image, "free-decor-pets-day") }
            if let key = config.freeDecor?.keys.sorted().first, let entry = config.freeDecor?[key], let item = entry.item {
                Snapshot.render(HouseFreeDecorNumericPanel(context: context, key: key, save: { _, _, _ in }, remove: {},
                    room: HouseFreeDecor.room(of: key), item: item, col: entry.cell[0], row: entry.cell[1]),
                    out.appendingPathComponent("free-decor-editor.png"), size: CGSize(width: 330, height: 330))
            }
        }
        let model = AppModel(mock: true); model.addHouseFixtureDemo()
        model.houseEdit("snapshot") { $0.homes[model.houseHomeKey] = config }
        Snapshot.render(HouseListEmbed(snapshotDate: date, snapshotPhase: .day).environmentObject(model).padding(12).background(Theme.bg),
                        out.appendingPathComponent("free-decor-menubar-day.png"), size: CGSize(width: 360, height: 340))
        exit(0)
    }
}
