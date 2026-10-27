import Foundation
import Testing
@testable import MijiaCore

private func dev(_ did: String, _ name: String, _ model: String, room: String?, roomId: String? = nil, online: Bool = true) -> Device {
    Device(did: did, name: name, model: model, isOnline: online, homeId: "h", homeName: "", roomName: room, roomId: roomId)
}
private func resolve(_ ds: [Device], _ cfg: HomeHouse? = nil, hidden: Set<String> = []) -> ResolvedHouse {
    HouseResolver.resolve(devices: ds, config: cfg, isHidden: { hidden.contains($0.did) }, name: { $0.name })
}

@Suite struct HouseResolverTests {
    let demo = [
        dev("d1", "客厅空调", "lumi.acpartner.mcn02", room: "客厅", roomId: "r1"),
        dev("d3", "落地灯", "yeelink.light.mbulb3", room: "客厅", roomId: "r1"),
        dev("d14", "客厅电视", "xiaomi.tv.demo", room: "客厅", roomId: "r1"),
        dev("d2", "卧室空调", "lumi.acpartner.mcn02", room: "主卧", roomId: "r2"),
        dev("d4", "循环扇", "xiaomi.fan.p51", room: "主卧", roomId: "r2"),
        dev("d5", "智能插座", "cuco.plug.v3", room: "书房", roomId: "r3"),
        dev("d6", "温湿度计", "miaomiaoce.sensor_ht.t2", room: "书房", roomId: "r3"),
        dev("d11", "智能门铃", "madv.cateye.demo", room: "门口", roomId: "r4"),
    ]

    @Test func customLayoutResolvesOneRoomPerCell() {
        let layout: [HouseLayoutCell] = [
            .init(room: "r2", module: "bedroom", col: 0, row: 0),
            .init(room: "name:厨房", module: "kitchen", col: 1, row: 0),
            .init(room: "r1", module: "living", col: 0, row: 1),
        ]
        let h = HouseResolver.resolve(devices: demo, config: nil, isHidden: { _ in false }, name: { $0.name }, layout: layout)
        // 按 (row, col) 排：主卧、厨房（没有米家设备，标题取 name: 后缀）、客厅
        #expect(h.rooms.map(\.key) == ["r2", "name:厨房", "r1"])
        #expect(h.rooms.map(\.module) == [.bedroom, .kitchen, .living])
        #expect(h.rooms[1].title == "厨房")
        #expect(h.rooms[1].devices.isEmpty)
        // 客厅设备照旧落到灯具位上
        let living = h.rooms[2]
        #expect(living.devices.first { $0.did == "d3" }?.spot == .fixture("floor_lamp"))
        // 书房、门口不在布局里
        #expect(Set(h.excluded.filter { $0.reason == .notInLayout }.map(\.key)) == ["r3", "r4"])
    }

    @Test func classicGeometryLayoutUsesClassicResolver() {
        let classic = HouseLayoutSolver.classicFour
        let a = HouseResolver.resolve(devices: demo, config: nil, isHidden: { _ in false }, name: { $0.name }, layout: classic)
        let b = resolve(demo)
        #expect(a.rooms.map(\.key) == b.rooms.map(\.key))
    }

    @Test func matchesMoreRoomNames() {
        #expect(HouseModule.from(roomName: "儿童房") == .bedroom)
        #expect(HouseModule.from(roomName: "次臥") == .bedroom)
        #expect(HouseModule.from(roomName: "Kitchen") == .kitchen)
        #expect(HouseModule.from(roomName: "卫生间") == .bathroom)
        #expect(HouseModule.from(roomName: "阳台") == .balcony)
        #expect(HouseModule.from(roomName: "餐厅") == .generic)
        #expect(HouseModule.allCases.allSatisfy { $0.hasArt })
    }

    @Test func placesDemoHome() {
        let h = resolve(demo)
        #expect(h.rooms.map(\.module) == [.living, .bedroom, .study, .generic])
        let living = h.rooms[0]
        #expect(living.device(at: .fixture("floor_lamp"))?.did == "d3")
        #expect(living.device(at: .fixture("tv"))?.did == "d14")
        // 客厅美术里画了壁挂空调（Phase 3a）：空调进 ac 灯具位，不再是茶几上的徽章
        #expect(living.device(at: .fixture("ac"))?.did == "d1")
        let bed = h.rooms[1]
        #expect(bed.device(at: .fixture("ac"))?.did == "d2")
        #expect(bed.devices.first { $0.did == "d4" }?.spot == .fixture("fan"))
        #expect(h.rooms[2].placed.count == 2)   // 插座、温湿度计都是徽章
        #expect(h.rooms[3].devices.first?.spot == .badge("b1"))
    }

    @Test func acLandsOnWallUnitInEveryRoomThatHasOne() {
        let ds = [dev("a1", "客厅空调", "xiaomi.aircondition.mt0", room: "客厅"), dev("a2", "卧室空调", "lumi.acpartner.mcn02", room: "主卧"),
                  dev("a3", "书房空调", "lumi.acpartner.v3", room: "书房"), dev("a4", "门口空调", "lumi.acpartner.v3", room: "门口")]
        let h = resolve(ds)
        for (i, m) in [HouseModule.living, .bedroom, .study].enumerated() {
            #expect(h.rooms.first { $0.module == m }?.device(at: .fixture("ac"))?.did == "a\(i + 1)", "\(m)")
        }
        // 玄关没有空调位：退回徽章
        #expect(h.rooms.first { $0.module == .generic }?.devices.first?.spot == .badge("b1"))
        // 第二台空调：灯具位已占，退回徽章
        let two = resolve([dev("x", "空调1", "lumi.acpartner.v3", room: "客厅"), dev("y", "空调2", "lumi.acpartner.v3", room: "客厅")])
        #expect(two.rooms[0].devices.map(\.spot) == [.fixture("ac"), .badge("b1")])
    }

    @Test func deviceClasses() {
        func k(_ model: String) -> HouseDeviceClass { HouseCatalog.deviceClass(category: DeviceCategory.guess(model), model: model) }
        #expect(k("lumi.acpartner.mcn02") == .fixture(.ac))
        #expect(k("yeelink.light.ceiling22") == .fixture(.light))
        #expect(k("xiaomi.tv.eanfv1") == .fixture(.screen))
        #expect(k("zhimi.fan.za5") == .fixture(.fan))
        #expect(k("zhimi.airpurifier.mb4") == .fixture(.airPurifier))
        #expect(k("nwt.derh.wdh318efw1") == .fixture(.dehumidifier))
        #expect(k("deerma.humidifier.jsq5") == .fixture(.humidifier))
        #expect(k("roborock.vacuum.a15") == .fixture(.vacuum))
        #expect(k("lumi.curtain.hagl05") == .fixture(.curtain))
        #expect(k("viomi.fridge.x3") == .fixture(.fridge))
        #expect(k("cuco.plug.v3") == .badge)
        #expect(k("miaomiaoce.sensor_ht.t2") == .badge)
        #expect(k("lumi.gateway.mgl03") == .badge)
        #expect(k("isa.camera.hlc7") == .badge)
        #expect(k("minij.washer.v5") == .fixture(.washer))
        #expect(k("zimi.waterheater.e1") == .fixture(.waterHeater))
        // 六种落地电器都有灯具位美术
        #expect(k("lumi.acpartner.mcn02").hasFixtureArt && k("zhimi.fan.za5").hasFixtureArt && !k("cuco.plug.v3").hasFixtureArt)
        for model in ["lumi.curtain.hagl05", "viomi.fridge.x3", "minij.washer.v5", "zimi.waterheater.e1"] { #expect(k(model).hasFixtureArt, "\(model)") }
        // 每个灯具位都有 kind，而且是已实现的
        for m in HouseModule.allCases { for f in HouseCatalog.fixtures(m) { #expect(HouseCatalog.fixtureKind(m, f.id)?.implemented == true) } }
        #expect(HouseCatalog.fixtureKind(.living, "ac") == .ac && HouseCatalog.fixtureKind(.study, "monitor") == .screen)
        #expect(HouseCatalog.fixtureKind(.bedroom, "curtain") == .curtain && HouseCatalog.fixtureKind(.kitchen, "fridge") == .fridge)
        #expect(HouseCatalog.fixtureKind(.bathroom, "water_heater") == .waterHeater && HouseCatalog.fixtureKind(.balcony, "washer") == .washer)
    }

    @Test func fixtureSetValidation() {
        let ids = ["ceiling", "monitor", "ac", "curtain", "fan", "heater"]
        #expect(HouseCatalog.fixtureSetProblems(.study, lightIds: ids).isEmpty)
        #expect(HouseCatalog.fixtureSetProblems(.study, lightIds: ids.filter { $0 != "ac" }) == ["study: missing fixture ac"])
        #expect(HouseCatalog.fixtureSetProblems(.study, lightIds: ids + ["humidifier"]) == ["study: unknown fixture humidifier"])
        #expect(HouseCatalog.fixtureSetProblems(.study, lightIds: ids + ["vacuum"]) == ["study: unknown fixture vacuum"])
        for module in [HouseModule.living, .bedroom] {
            let floorIds = HouseCatalog.fixtures(module).map(\.id)
            for id in ["humidifier", "vacuum"] {
                #expect(HouseCatalog.fixtureSetProblems(module, lightIds: floorIds.filter { $0 != id }) == ["\(module.rawValue): missing fixture \(id)"])
            }
        }
    }

    @Test func humidifierAndVacuumResolveToFixturesOrBadges() throws {
        for (id, model) in [("humidifier", "deerma.jsq.demo"), ("vacuum", "roborock.vacuum.demo")] {
            for roomName in ["客厅", "主卧"] {
                let house = resolve([dev("first", "First", model, room: roomName), dev("second", "Second", model, room: roomName)])
                let room = try #require(house.rooms.first)
                #expect(room.devices.count == 2)
                #expect(room.device(at: .fixture(id))?.did == "first")
                #expect(room.device(at: .badge("b1"))?.did == "second")
            }
            let study = resolve([dev("study", "Study appliance", model, room: "书房")])
            #expect(study.rooms.first?.device(at: .badge("b1"))?.did == "study")
        }
    }

    @Test func floorApplianceSlots() {
        let categories: [(String, DeviceCategory, HouseFixtureKind, Set<HouseModule>)] = [
            ("fan", .fan, .fan, [.living, .bedroom, .study]),
            ("air_purifier", .airPurifier, .airPurifier, [.living, .bedroom]),
            ("dehumidifier", .dehumidifier, .dehumidifier, [.living, .bedroom, .bathroom]),
            ("heater", .heater, .heater, [.living, .bedroom, .study]),
            ("humidifier", .humidifier, .humidifier, [.living, .bedroom]),
            ("vacuum", .vacuum, .vacuum, [.living, .bedroom]),
        ]
        for (id, category, kind, modules) in categories {
            #expect(kind.implemented)
            #expect(HouseCatalog.showable(category))
            #expect(HouseCatalog.deviceClass(category: category).hasFixtureArt)
            for module in HouseModule.allCases {
                let fixture = HouseCatalog.fixture(module, id)
                #expect((fixture != nil) == modules.contains(module))
                if let fixture {
                    #expect(fixture.accepts == [category])
                    #expect(HouseCatalog.fixtureKind(module, id) == kind)
                }
            }
        }
    }

    @Test func floorApplianceCatalogGeometry() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let base = try HouseComposer.loadCatalog(from: root.appendingPathComponent("assets/house/modules/catalog.json"))
        let directories = ["Sources/MijiaBarApp/Resources/House/modules", "assets/house/modules"]
            + ["light-wood", "walnut", "japanese", "modern"].map { "assets/house/styles/\($0)/modules" }
        for directory in directories {
            let catalog = try HouseComposer.loadCatalog(from: root.appendingPathComponent(directory + "/catalog.json"))
            for module in HouseModule.allCases {
                let lights = try #require(catalog.modules[module.rawValue]?.lights)
                #expect(HouseCatalog.fixtureSetProblems(module, lightIds: lights.map(\.id)).isEmpty)
                for light in lights where ["fan", "air-purifier", "dehumidifier", "heater", "humidifier", "vacuum"].contains(light.role) {
                    #expect(light.kind == HouseCatalog.fixtureKind(module, light.id)?.rawValue)
                    #expect(light.role == light.kind && light.slot == 0)
                    #expect(!light.bakesLight && light.wall == nil && light.alt == nil)
                    let anchor = try #require(light.anchor)
                    let body = try #require(light.body)
                    #expect(anchor.count == 2 && body.count == 4)
                    #expect(anchor == [(body[2][0] + body[3][0]) / 2, body[2][1]])
                    let expected = try #require(base.modules[module.rawValue]?.lights.first { $0.id == light.id })
                    #expect(light == expected)
                }
            }
        }
        let bundled = try Data(contentsOf: root.appendingPathComponent("Sources/MijiaBarApp/Resources/House/modules/catalog.json"))
        #expect(bundled == (try Data(contentsOf: root.appendingPathComponent("assets/house/modules/catalog.json"))))
    }

    @Test func tvNeverLandsOnStudyMonitor() {
        let h = resolve([dev("t", "书房电视", "xiaomi.tv.x", room: "书房"), dev("m", "显示器挂灯", "yeelink.light.lamp22", room: "书房")])
        let study = h.rooms[0]
        #expect(study.device(at: .fixture("monitor"))?.did == "m")
        #expect(study.devices.first { $0.did == "t" }?.spot == .badge("b1"))
    }

    @Test func bedroomTVGoesToBadge() {
        let h = resolve([dev("t", "卧室电视", "xiaomi.tv.x", room: "主卧")])
        #expect(h.rooms[0].devices[0].spot == .badge("b1"))
    }

    @Test func nameHintsBeatOrder() {
        let h = resolve([dev("a", "壁灯", "yeelink.light.a", room: "客厅"), dev("b", "落地灯", "yeelink.light.b", room: "客厅")])
        #expect(h.rooms[0].device(at: .fixture("sconce"))?.did == "a")
        #expect(h.rooms[0].device(at: .fixture("floor_lamp"))?.did == "b")
    }

    @Test func independentOfInputOrder() {
        let a = resolve(demo), b = resolve(demo.reversed()), c = resolve(demo.shuffled())
        #expect(a == b && b == c)
    }

    @Test func respectsHiddenAndVisibility() {
        var cfg = HomeHouse()
        cfg.devices["d14"] = HouseDeviceOverride(visible: false)
        cfg.devices["d6"] = HouseDeviceOverride(visible: true)      // 列表里隐藏，但小屋里要显示
        let h = resolve(demo, cfg, hidden: ["d3", "d6"])
        let living = h.rooms[0]
        #expect(living.devices.map(\.did).sorted() == ["d1"])
        #expect(h.hidden == ["d14", "d3"])
        #expect(h.rooms[2].devices.contains { $0.did == "d6" })
    }

    @Test func userPlacementWins() {
        var cfg = HomeHouse()
        cfg.devices["d3"] = HouseDeviceOverride(place: "fixture:sconce")
        cfg.devices["d14"] = HouseDeviceOverride(place: "none")
        cfg.devices["d5"] = HouseDeviceOverride(place: "fixture:tv")       // 插座放不进电视位：退回自动
        let h = resolve(demo, cfg)
        let living = h.rooms[0]
        #expect(living.device(at: .fixture("sconce"))?.did == "d3")
        #expect(living.device(at: .fixture("floor_lamp")) == nil)
        #expect(living.devices.first { $0.did == "d14" }?.spot == nil)
        #expect(living.devices.first { $0.did == "d14" }?.pinned == true)
        #expect(h.rooms[2].devices.first { $0.did == "d5" }?.spot != nil)
    }

    @Test func oneRoomPerModuleAndOverrides() {
        let ds = demo + [dev("x1", "次卧灯", "yeelink.light.x", room: "次卧", roomId: "r9"), dev("k", "电饭煲", "chunmi.cooker.x", room: "厨房", roomId: "rk")]
        let h = resolve(ds)
        #expect(h.rooms.first { $0.module == .bedroom }?.key == "r2")   // 主卧设备更多
        #expect(h.excluded.contains { $0.key == "r9" && $0.reason == .notInLayout })
        #expect(h.rooms.contains { $0.key == "rk" && $0.module == .kitchen })

        var cfg = HomeHouse()
        cfg.rooms["r9"] = HouseRoomOverride(module: "bedroom")
        cfg.rooms["r4"] = HouseRoomOverride(module: "none")
        let h2 = resolve(ds, cfg)
        #expect(h2.rooms.first { $0.module == .bedroom }?.key == "r9")
        #expect(h2.excluded.contains { $0.key == "r4" && $0.reason == .excluded })
        #expect(!h2.rooms.contains { $0.module == .generic })
    }

    @Test func unassignedAndNameKeys() {
        let h = resolve([dev("u", "灯", "yeelink.light.x", room: nil), dev("n", "灯", "yeelink.light.y", room: "客厅")])
        #expect(h.excluded.first?.reason == .unassigned)
        #expect(h.rooms.first?.key == "name:客厅")
    }
}

@Suite struct HouseFileTests {
    @Test func mergesPerEntryLastWriterWins() {
        let t0 = Date(timeIntervalSince1970: 1_000_000), t1 = t0.addingTimeInterval(10)
        var a = HouseFile(), b = HouseFile()
        a.setDevice(home: "h", did: "x", now: t0) { $0.visible = false }
        a.setDevice(home: "h", did: "y", now: t1) { $0.place = "badge" }
        b.setDevice(home: "h", did: "x", now: t1) { $0.visible = true }
        b.setDevice(home: "h", did: "y", now: t0) { $0.place = "none" }
        b.setRoom(home: "h", key: "r", module: "study", now: t0)
        let m = HouseFile.merge(a, b)
        #expect(m.homes["h"]?.devices["x"]?.visible == true)
        #expect(m.homes["h"]?.devices["y"]?.place == "badge")
        #expect(m.homes["h"]?.rooms["r"]?.module == "study")
        #expect(HouseFile.merge(b, a) == m)
    }

    @Test func resetWritesTombstonesThatSync() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var a = HouseFile(); a.setDevice(home: "h", did: "x", now: t0) { $0.visible = false }
        var b = a; b.reset(home: "h", now: t0.addingTimeInterval(5))
        #expect(HouseFile.merge(a, b).homes["h"]?.devices["x"]?.isEmpty == true)
        var p = b; p.prune(now: t0.addingTimeInterval(40 * 86400))
        #expect(p.homes["h"]?.devices.isEmpty == true)
    }

    @Test func roundTripsAndToleratesUnknownFields() throws {
        var f = HouseFile(); f.setRoom(home: "h", key: "r1", module: "living", now: Date(timeIntervalSince1970: 1_700_000_000.25))
        let back = try HouseFile.decode(f.encoded())
        #expect(back == f)
        let future = #"{"schema":2,"style":"cozy","homes":{"h":{"devices":{"d":{"visible":false,"updatedAt":"2026-10-17T12:00:00Z","x":1}},"layout":[]}}}"#
        let g = try HouseFile.decode(Data(future.utf8))
        #expect(g.schema == 2 && g.homes["h"]?.devices["d"]?.visible == false)
    }

    @Test func storeMergesConflictCopies() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("house-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("house.json")
        try HouseStore.update(at: url) { $0.setDevice(home: "h", did: "a", now: Date(timeIntervalSince1970: 100)) { $0.visible = false } }
        var other = HouseFile(); other.setDevice(home: "h", did: "b", now: Date(timeIntervalSince1970: 200)) { $0.place = "badge" }
        try other.encoded().write(to: dir.appendingPathComponent("house 2.json"))
        #expect(HouseStore.load(at: url).homes["h"]?.devices.count == 2)
        try HouseStore.update(at: url) { $0.setRoom(home: "h", key: "r", module: "none") }
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("house 2.json").path))
        #expect(HouseStore.load(at: url).homes["h"]?.devices.count == 2)
        try? FileManager.default.removeItem(at: dir)
    }

    /// 每套素材（模块 catalog.json；以后每个风格包）都必须提供同一套灯具位
    @Test func moduleCatalogDefinesEveryFixture() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for dir in ["assets/house/modules", "Sources/MijiaBarApp/Resources/House/modules"] {
            let o = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(dir + "/catalog.json"))) as! [String: Any]
            let modules = o["modules"] as! [String: [String: Any]]
            for m in HouseModule.allCases {
                let lights = try #require(modules[m.rawValue]?["lights"] as? [[String: Any]], "\(dir) \(m)")
                #expect(HouseCatalog.fixtureSetProblems(m, lightIds: lights.compactMap { $0["id"] as? String }).isEmpty, "\(dir) \(m)")
                for L in lights where (L["role"] as? String) == "ac" {
                    #expect(L["wall"] != nil && L["anchor"] != nil && L["alt"] != nil && L["vent"] != nil, "\(dir) \(m) ac")
                }
                for L in lights {
                    let role = L["role"] as? String ?? ""
                    if role == "curtain" {
                        // 窗帘贴片：四个状态的 PNG 都在，rect 偶数对齐（2px 像素格），mid 在窗内
                        let rect = try #require(L["rect"] as? [Double], "\(dir) \(m) curtain rect")
                        #expect(rect.count == 4 && rect.allSatisfy { $0.truncatingRemainder(dividingBy: 2) == 0 }, "\(dir) \(m) rect")
                        let mid = try #require(L["mid"] as? Double)
                        #expect(mid > rect[0] && mid < rect[0] + rect[2], "\(dir) \(m) mid")
                        #expect(L["wall"] != nil && L["anchor"] != nil && L["alt"] != nil && (L["quad"] as? [[Double]])?.count == 4, "\(dir) \(m) curtain")
                        let patch = try #require(L["patch"] as? String)
                        for v in ["day-unlit", "day-lit", "night-unlit", "night-lit"] {
                            #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(dir)/\(patch)-\(v).png").path), "\(dir) \(patch)-\(v)")
                        }
                    }
                    if ["fridge", "water-heater", "washer"].contains(role) {
                        #expect(((L["display"] as? [[Double]])?.count ?? 0) >= 3 && L["body"] != nil, "\(dir) \(m) \(role)")
                        #expect(L["pool"] == nil && L["reveal"] == nil, "\(dir) \(m) \(role) 不烘焙光")
                    }
                    if role == "washer" { #expect((L["door"] as? [String: Any])?["r"] != nil, "\(dir) washer door") }
                    if role == "water-heater" { #expect(L["wall"] != nil && L["alt"] != nil && L["led"] != nil, "\(dir) heater") }
                }
            }
        }
    }

    /// 墙挂灯具 / 家电被切掉时的徽章兜底位（alt）：素材里挑好的空地，离徽章位、彼此都留够一个徽章（36px）的距离
    @Test func moduleAltSpotsClearOfBadges() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MijiaBarApp/Resources/House/modules/catalog.json")
        let o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let dist = { (a: [Double], b: [Double]) in hypot(a[0] - b[0], a[1] - b[1]) }
        for (m, mod) in o["modules"] as! [String: [String: Any]] {
            let badges = mod["badges"] as? [[Double]] ?? []
            let alts = (mod["lights"] as? [[String: Any]] ?? []).filter { ($0["kind"] as? String) != "ceiling" }
                .flatMap { L -> [(String, [Double])] in ["alt", "alt2"].compactMap { k in (L[k] as? [Double]).map { ("\(L["id"] as? String ?? "?").\(k)", $0) } } }
            for (i, (id, a)) in alts.enumerated() {
                for b in badges { #expect(dist(a, b) >= 38, "\(m) \(id) alt \(a) vs badge \(b)") }
                // alt / alt2 是同一灯具的备选，不会同时画；只要求和其他灯具的位拉开
                let fixture = id.split(separator: ".").first.map(String.init) ?? id
                for (id2, a2) in alts[(i + 1)...] {
                    let fixture2 = id2.split(separator: ".").first.map(String.init) ?? id2
                    if fixture == fixture2 { continue }
                    #expect(dist(a, a2) >= 38, "\(m) \(id) vs \(id2)")
                }
            }
        }
    }

    @Test func catalogMatchesCutawayJSON() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MijiaBarApp/Resources/House/house-cutaway.json")
        let o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let modules = o["modules"] as! [String: [String: Any]]
        for m in HouseCatalog.classicModules {
            let lights = (modules[m.rawValue]?["lights"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            #expect(HouseCatalog.fixtureSetProblems(m, lightIds: lights).isEmpty, "\(m)")
            #expect((modules[m.rawValue]?["badges"] as? [[Double]])?.count == HouseCatalog.badgeCount(m), "\(m) badges")
            // 经典整图的窗帘贴片（四个状态）都在 Resources/House
            for L in modules[m.rawValue]?["lights"] as? [[String: Any]] ?? [] where (L["role"] as? String) == "curtain" {
                let patch = try #require(L["patch"] as? String)
                for v in ["day-unlit", "day-lit", "night-unlit", "night-lit"] {
                    #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("\(patch)-\(v).png").path), "\(patch)-\(v)")
                }
                #expect((L["rect"] as? [Double])?.count == 4 && L["mid"] != nil && (L["quad"] as? [[Double]])?.count == 4, "\(m)")
            }
        }
    }
}

@Suite struct HouseApplianceFixtureTests {
    @Test func categoriesForNewAppliances() {
        #expect(DeviceCategory.guess("lumi.curtain.hagl05") == .curtain)
        #expect(DeviceCategory.guess("viomi.fridge.x3") == .fridge)
        #expect(DeviceCategory.guess("minij.washer.v5") == .washer)
        #expect(DeviceCategory.guess("viomi.dishwasher.v01") == .kitchen)
        #expect(DeviceCategory.guess("dreame.hairdryer.v1") != .washer)
        #expect(DeviceCategory.guess("zimi.waterheater.e1") == .waterHeater)
        #expect(DeviceCategory.guess("zhimi.heater.za1") == .heater)
    }

    @Test func appliancesLandOnTheirSlots() {
        let ds = [dev("c1", "客厅窗帘", "lumi.curtain.hagl05", room: "客厅"), dev("c2", "卧室窗帘", "lumi.curtain.hagl05", room: "主卧"),
                  dev("c3", "书房窗帘", "lumi.curtain.hagl05", room: "书房"), dev("c4", "第二个窗帘", "lumi.curtain.hagl05", room: "客厅")]
        let h = resolve(ds)
        for m in [HouseModule.living, .bedroom, .study] { #expect(h.rooms.first { $0.module == m }?.device(at: .fixture("curtain")) != nil, "\(m)") }
        // 同一房间第二个窗帘：位置已占 → 徽章
        #expect(h.rooms.first { $0.module == .living }?.devices.first { $0.did == "c4" }?.spot == .badge("b1"))
        // 厨房 / 卫生间 / 阳台使用模块合成
        let layout: [HouseLayoutCell] = [.init(room: "name:厨房", module: "kitchen", col: 0, row: 0), .init(room: "name:卫生间", module: "bathroom", col: 1, row: 0),
                                         .init(room: "name:阳台", module: "balcony", col: 2, row: 0)]
        let ap = [dev("f", "冰箱", "viomi.fridge.x3", room: "厨房"), dev("k", "厨房窗帘", "lumi.curtain.hagl05", room: "厨房"),
                  dev("w", "热水器", "zimi.waterheater.e1", room: "卫生间"), dev("x", "洗衣机", "minij.washer.v5", room: "阳台")]
        let c = HouseResolver.resolve(devices: ap, config: nil, isHidden: { _ in false }, name: { $0.name }, layout: layout)
        #expect(c.rooms[0].device(at: .fixture("fridge"))?.did == "f")
        #expect(c.rooms[0].device(at: .fixture("curtain"))?.did == "k")
        #expect(c.rooms[1].device(at: .fixture("water_heater"))?.did == "w")
        #expect(c.rooms[2].device(at: .fixture("washer"))?.did == "x")
    }

    private func S(_ t: String, _ props: [SpecProperty]) -> DeviceSpec {
        DeviceSpec(type: "", description: "", services: [SpecService(iid: 2, type: "urn:miot-spec-v2:service:\(t):0", description: t, properties: props, actions: [])])
    }
    private func P(_ iid: Int, _ t: String, _ f: String, range: [Double]? = nil, opts: [ValueOption]? = nil) -> SpecProperty {
        SpecProperty(siid: 2, iid: iid, type: "urn:miot-spec-v2:property:\(t):0", description: t, format: f, access: ["read"], unit: nil, range: range, options: opts)
    }

    @Test func curtainPositionFromSpec() {
        let spec = S("curtain", [P(2, "current-position", "uint8", range: [0, 100, 1])])
        #expect(HouseDeviceState.curtainPosition(DeviceState(values: ["2.2": .int(50)], spec: spec, legacy: false, source: "t")) == 0.5)
        #expect(HouseDeviceState.curtainPosition(DeviceState(values: ["2.2": .int(130)], spec: spec, legacy: false, source: "t")) == 1)
        #expect(HouseDeviceState.curtainPosition(DeviceState(values: [:], spec: spec, legacy: false, source: "t")) == nil)
        #expect(HouseDeviceState.curtainPosition(nil) == nil)
        // 只有 target-position 时也认
        let t = S("curtain", [P(3, "target-position", "uint8", range: [0, 10, 1])])
        #expect(HouseDeviceState.curtainPosition(DeviceState(values: ["2.3": .int(2)], spec: t, legacy: false, source: "t")) == 0.2)
    }

    @Test func busyFromStatusOptions() {
        let spec = S("washer", [P(2, "status", "uint8", opts: [ValueOption(value: 1, description: "Idle"), ValueOption(value: 2, description: "Washing"),
                                                              ValueOption(value: 3, description: "Heating")])])
        func st(_ v: Int) -> DeviceState { DeviceState(values: ["2.2": .int(v)], spec: spec, legacy: false, source: "t") }
        #expect(!HouseDeviceState.busy(st(1), otherwise: true))
        #expect(HouseDeviceState.busy(st(2), otherwise: false))
        #expect(HouseDeviceState.busy(st(3), otherwise: false))
        #expect(HouseDeviceState.busy(st(9), otherwise: true))   // 未知选项 → otherwise
        #expect(HouseDeviceState.busy(nil, otherwise: true) && !HouseDeviceState.busy(nil, otherwise: false))
    }

    @Test func curtainRangesCloseFromBothSides() {
        #expect(HouseDeviceState.curtainVisibleRanges(x0: 100, x1: 200, mid: 150, closed: 0).isEmpty)
        #expect(HouseDeviceState.curtainVisibleRanges(x0: 100, x1: 200, mid: 150, closed: 1) == [100...200])
        let half = HouseDeviceState.curtainVisibleRanges(x0: 100, x1: 200, mid: 150, closed: 0.5)
        #expect(half == [100...126, 176...200])
        // 2px 对齐
        for r in HouseDeviceState.curtainVisibleRanges(x0: 100, x1: 200, mid: 151, closed: 0.33) {
            #expect(r.lowerBound.truncatingRemainder(dividingBy: 2) == 0 && r.upperBound.truncatingRemainder(dividingBy: 2) == 0)
        }
    }
}
