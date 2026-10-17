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
        #expect(!HouseModule.kitchen.hasArt && HouseModule.living.hasArt)
    }

    @Test func placesDemoHome() {
        let h = resolve(demo)
        #expect(h.rooms.map(\.module) == [.living, .bedroom, .study, .generic])
        let living = h.rooms[0]
        #expect(living.device(at: .fixture("floor_lamp"))?.did == "d3")
        #expect(living.device(at: .fixture("tv"))?.did == "d14")
        // 客厅画里没有空调：空调进徽章，不会占一个看不见的位置
        #expect(living.devices.first { $0.did == "d1" }?.spot == .badge("b1"))
        let bed = h.rooms[1]
        #expect(bed.device(at: .fixture("ac"))?.did == "d2")
        #expect(bed.devices.first { $0.did == "d4" }?.spot == .badge("b1"))
        #expect(h.rooms[2].placed.count == 2)   // 插座、温湿度计都是徽章
        #expect(h.rooms[3].devices.first?.spot == .badge("b1"))
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
        #expect(h.excluded.contains { $0.key == "r9" && $0.reason == .spotTaken })
        #expect(h.excluded.contains { $0.key == "rk" && $0.reason == .noArt })

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

    @Test func catalogMatchesCutawayJSON() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MijiaBarApp/Resources/House/house-cutaway.json")
        let o = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let modules = o["modules"] as! [String: [String: Any]]
        for m in HouseCatalog.artModules {
            let lights = (modules[m.rawValue]?["lights"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
            #expect(Set(lights) == Set(HouseCatalog.fixtures(m).map(\.id)), "\(m)")
            #expect((modules[m.rawValue]?["badges"] as? [[Double]])?.count == HouseCatalog.badgeCount(m), "\(m) badges")
        }
    }
}
