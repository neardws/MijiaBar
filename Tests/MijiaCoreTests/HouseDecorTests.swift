import Foundation
import CoreGraphics
import Testing
@testable import MijiaCore

@Suite struct HouseDecorTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let decorDir = root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/decor")
    static var shanghai: Calendar { var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return calendar }
    static func date(_ value: String) -> Date {
        let formatter = DateFormatter(); formatter.calendar = shanghai; formatter.timeZone = shanghai.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter.date(from: value)!
    }
    static func catalog() throws -> HouseDecorCatalog { try .load(from: decorDir.appendingPathComponent("decor-catalog.json")) }
    static func modules(_ style: String = "cozy-wood") throws -> HouseModuleCatalog {
        let path = style == "cozy-wood" ? "assets/house/modules/catalog.json" : "assets/house/styles/\(style)/modules/catalog.json"
        return try HouseComposer.loadCatalog(from: root.appendingPathComponent(path))
    }
    static func fixture() throws -> (HouseModuleCatalog, HouseDecorCatalog, [HouseLayoutCell]) {
        let modules = try JSONDecoder().decode(HouseModuleCatalog.self, from: Data(#"{"schema":3,"modules":{"test":{"footprint":[1,1],"size":[512,400],"tip":[186,124],"region":[],"label":[200,200],"badges":[],"lights":[],"decor":[{"id":"floor","surface":"floor","sizes":["S"],"at":[300,200],"default":"plant","holiday":true},{"id":"wall","surface":"wall","sizes":["S"],"at":[120,80],"wall":"nw","default":"art","holiday":true}]}}}"#.utf8))
        let items = try JSONDecoder().decode(HouseDecorCatalog.self, from: Data(#"{"schema":1,"seasons":{"christmas":{"calendar":"gregorian","month":12,"day":25,"window":7}},"items":[{"id":"plant","name":{"zh":"植物","en":"Plant"},"category":"plant","surface":"floor","size":"S","sprites":{"day":"plant.png","night":"plant.png"},"anchor":[0,0]},{"id":"art","name":{"zh":"挂画","en":"Art"},"category":"wall","surface":"wall","size":"S","sprites":{"day":{"nw":"nw.png","ne":"ne.png"},"night":{"nw":"nw.png","ne":"ne.png"}},"anchor":[0,0]},{"id":"holiday","name":{"zh":"节日","en":"Holiday"},"category":"holiday","surface":"floor","size":"S","sprites":{"day":"holiday.png","night":"holiday.png"},"anchor":[0,0],"season":"christmas"}]}"#.utf8))
        return (modules, items, [.init(room: "room", module: "test", col: 0, row: 0, level: 0)])
    }

    @Test func catalogAndSpriteIntegrity() throws {
        let catalog = try Self.catalog()
        #expect(catalog.schema == 1)
        #expect(!catalog.items.isEmpty)
        #expect(Set(catalog.items.map(\.id)).count == catalog.items.count)
        var missing: [String] = []
        for item in catalog.items {
            #expect(item.anchor.count == 2)
            #expect(["plant", "rug", "wall", "book", "pet", "holiday"].contains(item.category))
            #expect(["floor", "rug", "wall", "table"].contains(item.surface))
            #expect(["S", "M", "L"].contains(item.size))
            if item.category == "holiday" { #expect(item.season.flatMap { catalog.seasons[$0] } != nil) }
            if item.text == true { #expect(item.surface == "wall") }
            for phase in ["day", "night"] {
                let sprite = try #require(item.sprites[phase])
                if item.surface == "wall" {
                    #expect(sprite.file(wall: "nw") != nil); #expect(sprite.file(wall: "ne") != nil)
                } else { #expect(sprite.file() != nil) }
                for file in sprite.files where !FileManager.default.fileExists(atPath: Self.decorDir.appendingPathComponent(file).path) { missing.append(file) }
            }
        }
        #expect(missing.isEmpty, "Missing required decor PNGs: \(missing.joined(separator: ", "))")
    }

    @Test func slotSetParity() throws {
        let items = try Self.catalog(), reference = try Self.modules()
        let bundled = try HouseComposer.loadCatalog(from: Self.root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/modules/catalog.json"))
        for (module, art) in reference.modules { #expect(bundled.modules[module]?.decor == art.decor, "Bundled slots out of sync: \(module)") }
        for style in ["cozy-wood", "japanese", "modern"] {
            let catalog = try Self.modules(style)
            #expect(Set(catalog.modules.keys) == Set(reference.modules.keys))
            for (module, art) in catalog.modules {
                let slots = art.decor ?? [], expected = reference.modules[module]?.decor ?? []
                #expect((4...6).contains(slots.count), "\(style)/\(module) needs 4...6 decor slots")
                #expect(Set(slots.map(\.id)).count == slots.count)
                #expect(Set(slots.map(\.id)) == Set(expected.map(\.id)))
                for slot in slots {
                    #expect(slot.at.count == 2)
                    #expect(["floor", "rug", "wall", "table"].contains(slot.surface))
                    #expect(!slot.sizes.isEmpty && slot.sizes.allSatisfy { ["S", "M", "L"].contains($0) })
                    if slot.surface == "wall" { #expect(["nw", "ne"].contains(slot.wall ?? "")) }
                    let other = try #require(expected.first { $0.id == slot.id })
                    #expect(slot.surface == other.surface && slot.wall == other.wall && Set(slot.sizes) == Set(other.sizes))
                    if let id = slot.default { let item = try #require(items.items.first { $0.id == id }); #expect(item.fits(slot)) }
                }
            }
        }
    }

    @Test func overrideAndAutoResolution() throws {
        let (modules, items, layout) = try Self.fixture()
        func resolve(_ override: String?, enabled: Bool = true) -> [HouseDecorPlacement] {
            HouseDecor.resolve(layout: layout, catalog: modules, overrides: ["room/floor": .init(item: override)],
                               prefs: .init(enabled: enabled, seasonal: false), date: Self.date("2026-07-01"), items: items)
        }
        #expect(resolve(nil, enabled: false).isEmpty)
        #expect(resolve(nil).first { $0.slot == "floor" }?.source == .default)
        #expect(resolve("plant").first { $0.slot == "floor" }?.source == .user)
        #expect(resolve("none").allSatisfy { $0.slot != "floor" })
        #expect(resolve("missing").first { $0.slot == "floor" }?.item == "plant")
        #expect(resolve("art").first { $0.slot == "floor" }?.source == .default)
        let old = try JSONDecoder().decode(HouseModuleCatalog.self, from: Data(#"{"schema":3,"modules":{}}"#.utf8))
        #expect(HouseDecor.resolve(layout: layout, catalog: old, items: items).isEmpty)
        var withoutSlots = modules; withoutSlots.modules["test"]?.decor = nil
        let decoded = try JSONDecoder().decode(HouseModuleCatalog.self, from: JSONEncoder().encode(withoutSlots))
        #expect(decoded.modules["test"]?.decor == nil)
        #expect(HouseDecor.resolve(layout: layout, catalog: decoded, items: items).isEmpty)
    }

    @Test func holidaysOnlyUseAutoSlots() throws {
        let (modules, items, layout) = try Self.fixture()
        func resolve(_ override: String?, seasonal: Bool = true) -> [HouseDecorPlacement] {
            HouseDecor.resolve(layout: layout, catalog: modules, overrides: ["room/floor": .init(item: override)],
                               prefs: .init(seasonal: seasonal), date: Self.date("2026-12-25"), items: items, calendar: Self.shanghai)
        }
        #expect(resolve(nil).first { $0.slot == "floor" }?.source == .holiday)
        #expect(resolve("plant").first { $0.slot == "floor" }?.source == .user)
        #expect(resolve("none").allSatisfy { $0.slot != "floor" })
        #expect(resolve("missing").first { $0.slot == "floor" }?.source == .default)
        #expect(resolve(nil, seasonal: false).first { $0.slot == "floor" }?.source == .default)
        #expect(resolve("holiday", seasonal: false).first { $0.slot == "floor" }?.source == .user)
        var noHoliday = modules; noHoliday.modules["test"]?.decor?[0].holiday = false
        #expect(!HouseDecor.resolve(layout: layout, catalog: noHoliday, date: Self.date("2026-12-25"), items: items, calendar: Self.shanghai).contains { $0.source == .holiday })
    }

    @Test func holidaysAssignEachItemOnceInEachRoom() throws {
        var (modules, items, layout) = try Self.fixture()
        var slot = try #require(modules.modules["test"]?.decor?.first)
        slot.id = "second"; modules.modules["test"]?.decor?.append(slot)
        var item = try #require(items.items.last); item.id = "second-holiday"; items.items.append(item)
        layout.append(.init(room: "another", module: "test", col: 1, row: 0, level: 0))
        let resolved = HouseDecor.resolve(layout: layout, catalog: modules, date: Self.date("2026-12-25"), items: items, calendar: Self.shanghai)
        for room in ["room", "another"] {
            let holidays = resolved.filter { $0.room == room && $0.source == .holiday }
            #expect(holidays.map(\.slot) == ["floor", "second"])
            #expect(holidays.map(\.item) == ["holiday", "second-holiday"])
        }
    }

    @Test func cutWallsShareLightRule() throws {
        let (modules, items, _) = try Self.fixture()
        let layout = [HouseLayoutCell(room: "back", module: "test", col: 0, row: 0), .init(room: "room", module: "test", col: 1, row: 0)]
        #expect(HouseDecor.hiddenSlots(layout: layout, catalog: modules) == ["room/wall"])
        #expect(HouseDecor.resolve(layout: layout, catalog: modules, items: items).allSatisfy { !($0.room == "room" && $0.slot == "wall") })
        let segments = [HouseWallSegment(side: .ne, a: (0, 0), b: (160, 66), height: HouseGrid.cutH),
                        HouseWallSegment(side: .ne, a: (160, 66), b: (320, 132), height: HouseGrid.wallH)]
        #expect(HouseComposer.wallIsHidden(wall: "ne", anchor: [100, 0], segments: segments))
        #expect(!HouseComposer.wallIsHidden(wall: "ne", anchor: [200, 0], segments: segments))
    }

    @Test func holidayDatesAndBoundaries() throws {
        let seasons = try Self.catalog().seasons
        let cases: [(String, String, Bool)] = [("springFestival", "2027-01-31", true), ("springFestival", "2027-02-06", true),
            ("springFestival", "2027-02-13", true), ("springFestival", "2027-02-14", false), ("midAutumn", "2026-09-25", true),
            ("halloween", "2026-10-24", true), ("halloween", "2026-10-23", false), ("christmas", "2026-12-18", true),
            ("christmas", "2026-12-17", false), ("christmas", "2027-01-01", true), ("christmas", "2027-01-02", false)]
        for (season, day, expected) in cases {
            #expect(HouseSeasons.activeSeasons(on: Self.date(day), calendar: Self.shanghai, seasons: seasons).contains(season) == expected, "\(season) \(day)")
        }
        let zone = TimeZone(identifier: "Asia/Shanghai")!
        #expect(HouseSeasons.activeSeasons(on: Self.date("2026-10-24"), timeZone: zone, seasons: seasons).contains("halloween"))
    }

    @Test func storeMergeTombstonesAndOldFiles() throws {
        var older = HouseFile(), newer = HouseFile()
        let before = Date(timeIntervalSince1970: 10), after = Date(timeIntervalSince1970: 20)
        older.setDecor(home: "h", key: "room/floor", item: "plant", now: before)
        older.setDecorPrefs(home: "h", enabled: false, seasonal: false, now: before)
        newer.setDecor(home: "h", key: "room/floor", item: "auto", now: after)
        newer.setDecorPrefs(home: "h", enabled: true, now: after)
        for file in [HouseFile.merge(older, newer), HouseFile.merge(newer, older)] {
            let home = try #require(file.homes["h"])
            #expect(home.decor?["room/floor"]?.item == nil && home.decor?["room/floor"]?.updatedAt == after)
            #expect(home.decorPrefs?.enabled == true && home.decorPrefs?.seasonal == true)
            #expect(try HouseFile.decode(file.encoded()) == file)
        }
        newer.setDecor(home: "h", key: "room/wall", item: "none", now: before)
        newer.resetDecor(home: "h", now: after)
        #expect(newer.homes["h"]?.decor?.values.allSatisfy { $0.item == nil && $0.updatedAt == after } == true)
        older.reset(home: "h", now: after)
        #expect(older.homes["h"]?.decorPrefs == HouseDecorPrefs(updatedAt: after))
        #expect(older.homes["h"]?.decor?["room/floor"]?.item == nil)
        let old = try HouseFile.decode(Data(#"{"schema":1,"homes":{"h":{"rooms":{},"devices":{}}}}"#.utf8))
        #expect(old.homes["h"]?.decor == nil && old.homes["h"]?.decorPrefs == nil)
        #expect(try JSONDecoder().decode(HouseDecorPrefs.self, from: Data("{}".utf8)).enabled)
    }

    static func image(width: Int, height: Int, rgba: [UInt8]) -> CGImage {
        let bytes = Array(repeating: rgba, count: width * height).flatMap { $0 }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    static func pixels(_ image: CGImage) -> [UInt8] { HouseDecorPixels.cache.buffer(image)!.bytes }

    @Test func composeChangesOnlySpriteRectangle() throws {
        let (catalog, items, layout) = try Self.fixture()
        let base = Self.image(width: 512, height: 400, rgba: [50, 50, 50, 255]), sprite = Self.image(width: 8, height: 6, rgba: [160, 20, 0, 255])
        let placement = try #require(HouseDecor.resolve(layout: layout, catalog: catalog, prefs: .init(seasonal: false), items: items).first { $0.slot == "floor" })
        let decor = HouseDecorImage(placement: placement, image: sprite, anchor: [4, 6])
        let images = ["test": HouseModuleImages(unlit: base, lit: base)]
        let before = HouseComposer.compose(.init(layout: layout, catalog: catalog, images: images))
        let after = HouseComposer.compose(.init(layout: layout, catalog: catalog, images: images, decor: [decor]))
        let original = Self.pixels(try #require(before.unlit)), changed = Self.pixels(try #require(after.unlit))
        #expect(original != changed)
        let scene = try #require(try JSONSerialization.jsonObject(with: after.sceneJSON) as? [String: Any])
        let slots = try #require(scene["decorSlots"] as? [[String: Any]])
        let slot = try #require(slots.first { $0["slot"] as? String == "floor" })
        let rect = try #require(slot["rect"] as? [Double])
        var outside = 0
        for row in 0..<after.height {
            for column in 0..<after.width where Double(column) < rect[0] || Double(column) >= rect[0] + rect[2] || Double(row) < rect[1] || Double(row) >= rect[1] + rect[3] {
                let index = (row * after.width + column) * 4
                if original[index..<(index + 4)] != changed[index..<(index + 4)] { outside += 1 }
            }
        }
        #expect(outside == 0)
    }

    @Test func lightingClampAndShadowAlpha() throws {
        let (catalog, items, layout) = try Self.fixture()
        let placement = try #require(HouseDecor.resolve(layout: layout, catalog: catalog, items: items).first { $0.slot == "floor" })
        let unlit = Self.image(width: 512, height: 400, rgba: [30, 30, 30, 255]), lit = Self.image(width: 512, height: 400, rgba: [255, 255, 255, 255])
        let sprite = Self.image(width: 2, height: 2, rgba: [40, 20, 0, 128])
        let decor = HouseDecorImage(placement: placement, image: sprite, anchor: [0, 0])
        let brightened = Self.pixels(HouseDecorPixels.brightened(decor, module: .init(unlit: unlit, lit: lit)))
        #expect(Array(brightened.prefix(4)) == [100, 50, 0, 128])
        let shadow = HouseDecorImage(placement: placement, image: Self.image(width: 1, height: 1, rgba: [0, 0, 0, 80]), anchor: [0, 0])
        #expect(Self.pixels(HouseDecorPixels.brightened(shadow, module: .init(unlit: unlit, lit: lit))) == [0, 0, 0, 80])
        #expect(Self.pixels(HouseDecorPixels.brightened(decor, module: .init(unlit: lit, lit: unlit))) == Self.pixels(sprite))
        let faint = HouseDecorImage(placement: placement, image: Self.image(width: 1, height: 1, rgba: [1, 1, 1, 255]), anchor: [0, 0])
        #expect(Self.pixels(HouseDecorPixels.brightened(faint, module: .init(unlit: unlit, lit: lit)))[0] <= 2)
        let black = Self.image(width: 512, height: 400, rgba: [0, 0, 0, 255])
        #expect(Self.pixels(HouseDecorPixels.brightened(decor, module: .init(unlit: black, lit: lit)))[0] == 100)
    }

    @Test func lightingSamplesModulePixelsWithoutFlippingSprite() throws {
        let (catalog, items, layout) = try Self.fixture()
        var placement = try #require(HouseDecor.resolve(layout: layout, catalog: catalog, items: items).first { $0.slot == "floor" })
        placement.at = [4, 4]
        let bytes = (0..<32).flatMap { row in Array(repeating: [UInt8(row < 16 ? 200 : 40), UInt8(40), UInt8(40), UInt8(255)], count: 32).flatMap { $0 } }
        let light = CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 128,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let unlit = Self.image(width: 32, height: 32, rgba: [40, 40, 40, 255])
        let source: [UInt8] = [40, 0, 0, 255, 0, 40, 0, 255]
        let sprite = CGImage(width: 1, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4,
                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                             provider: CGDataProvider(data: Data(source) as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let upper = HouseDecorImage(placement: placement, image: sprite, anchor: [0, 0])
        let result = Self.pixels(HouseDecorPixels.brightened(upper, module: .init(unlit: unlit, lit: light)))
        #expect(result[0] > 40 && result[1] == 0)
        #expect(result[4] == 0 && result[5] > 40)
        placement.at = [4, 24]
        let lower = HouseDecorImage(placement: placement, image: sprite, anchor: [0, 0])
        #expect(Self.pixels(HouseDecorPixels.brightened(lower, module: .init(unlit: unlit, lit: light))) == source)
    }

    @Test func cachedCompositionOverhead() throws {
        var (catalog, items, layout) = try Self.fixture()
        let base = Self.image(width: 512, height: 400, rgba: [50, 50, 50, 255])
        let light = Self.image(width: 512, height: 400, rgba: [100, 100, 100, 255])
        let sprite = Self.image(width: 48, height: 48, rgba: [40, 20, 0, 128])
        var art = try #require(catalog.modules["test"])
        let floor = try #require(art.decor?.first { $0.id == "floor" })
        art.decor = (0..<5).map { index in var slot = floor; slot.id = "floor-\(index)"; slot.at = [220 + Double(index) * 32, 200]; return slot }
        catalog.modules["test"] = art
        layout = (0..<6).map { .init(room: "room-\($0)", module: "test", col: $0 % 3, row: $0 / 3, level: 0) }
        let placements = HouseDecor.resolve(layout: layout, catalog: catalog, items: items)
        #expect(placements.count == 30)
        let decor = placements.map { HouseDecorImage(placement: $0, image: sprite, anchor: [24, 48]) }
        let plain = HouseComposer.Input(layout: layout, catalog: catalog, images: ["test": .init(unlit: base, lit: light)])
        var decorated = plain; decorated.decor = decor
        _ = HouseComposer.compose(decorated)
        var overhead: [Double] = []
        for _ in 0..<7 {
            let baseline = HouseComposer.compose(plain).milliseconds
            overhead.append(HouseComposer.compose(decorated).milliseconds - baseline)
        }
        print("HouseDecor cached 30×48px sprite overhead ms: \(overhead.sorted()[overhead.count / 2])")
    }

    @Test func frontRoomOccludesBackDecor() throws {
        var (catalog, items, layout) = try Self.fixture()
        catalog.modules["front"] = catalog.modules["test"]
        layout += [.init(room: "front", module: "front", col: 1, row: 0, level: 0)]
        let image = Self.image(width: 512, height: 400, rgba: [70, 70, 70, 255])
        let images = ["test": HouseModuleImages(unlit: image, lit: image), "front": .init(unlit: image, lit: image)]
        let placement = try #require(HouseDecor.resolve(layout: layout, catalog: catalog, items: items).first { $0.room == "room" && $0.slot == "floor" })
        let sprite = Self.image(width: 8, height: 8, rgba: [200, 0, 0, 255])
        let without = HouseComposer.compose(.init(layout: layout, catalog: catalog, images: images))
        let with = HouseComposer.compose(.init(layout: layout, catalog: catalog, images: images, decor: [.init(placement: placement, image: sprite, anchor: [0, 0])]))
        #expect(Self.pixels(try #require(without.unlit)) == Self.pixels(try #require(with.unlit)))
        #expect(Self.pixels(try #require(without.lit)) == Self.pixels(try #require(with.lit)))
    }

    @Test func composeHidesCutWallButKeepsEditorMetadata() throws {
        let (catalog, items, _) = try Self.fixture()
        let layout = [HouseLayoutCell(room: "back", module: "test", col: 0, row: 0, level: 0),
                      .init(room: "room", module: "test", col: 1, row: 0, level: 1)]
        let placement = try #require(HouseDecor.resolve(layout: layout, catalog: catalog, items: items, includeHidden: true).first { $0.room == "room" && $0.slot == "wall" })
        let base = Self.image(width: 512, height: 400, rgba: [70, 70, 70, 255])
        let sprite = Self.image(width: 8, height: 8, rgba: [200, 0, 0, 255])
        let plain = HouseComposer.Input(layout: layout, catalog: catalog, images: ["test": .init(unlit: base, lit: base)])
        var decorated = plain; decorated.decor = [.init(placement: placement, image: sprite, anchor: [4, 4])]
        let before = HouseComposer.compose(plain), after = HouseComposer.compose(decorated)
        #expect(Self.pixels(try #require(before.unlit)) == Self.pixels(try #require(after.unlit)))
        let scene = try #require(try JSONSerialization.jsonObject(with: after.sceneJSON) as? [String: Any])
        let slots = try #require(scene["decorSlots"] as? [[String: Any]])
        let slot = try #require(slots.first { $0["room"] as? String == "room" && $0["slot"] as? String == "wall" })
        #expect(slot["hidden"] as? String == "wall cut")
        #expect(slot["item"] as? String == "art")
        let tip = HouseGrid.tip(col: 1, row: 0)
        #expect(slot["x"] as? Double == 120 + Double(tip.x - 186 - after.originX))
        #expect(slot["y"] as? Double == 80 + Double(tip.y - 124 - HouseGrid.levelStep - after.originY))
    }
}
