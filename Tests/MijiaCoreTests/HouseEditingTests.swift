import Foundation
import Testing
@testable import MijiaCore

private func dev(_ did: String, _ name: String, _ model: String, room: String, roomId: String) -> Device {
    Device(did: did, name: name, model: model, isOnline: true, homeId: "h", homeName: "", roomName: room, roomId: roomId)
}

@Suite struct HouseDropTests {
    let demo = [
        dev("d1", "客厅空调", "lumi.acpartner.mcn02", room: "客厅", roomId: "r1"),
        dev("d3", "落地灯", "yeelink.light.mbulb3", room: "客厅", roomId: "r1"),
        dev("d15", "壁灯", "yeelink.light.mbulb3", room: "客厅", roomId: "r1"),
        dev("d14", "客厅电视", "xiaomi.tv.demo", room: "客厅", roomId: "r1"),
        dev("d2", "卧室空调", "lumi.acpartner.mcn02", room: "主卧", roomId: "r2"),
        dev("d4", "循环扇", "xiaomi.fan.p51", room: "主卧", roomId: "r2"),
    ]
    func house(_ cfg: HomeHouse? = nil) -> ResolvedHouse {
        HouseResolver.resolve(devices: demo, config: cfg, isHidden: { _ in false }, name: { $0.name })
    }
    func src(_ did: String, hidden: Bool = false) -> HouseDragSource {
        let d = demo.first { $0.did == did }!
        return HouseDragSource(did: did, category: d.category, roomKey: HouseResolver.roomKey(d), hiddenInHouse: hidden)
    }
    func applied(_ v: HouseDropVerdict) -> ResolvedHouse {
        var f = HouseFile(); HouseEditing.apply(v.changes, to: &f, home: "h")
        return house(f.homes["h"])
    }

    @Test func rejectsOtherRoom() {
        #expect(HouseEditing.planDrop(src("d4"), roomKey: "r1", spot: .badge("b1"), house: house()) == .reject(.otherRoom))
    }

    @Test func rejectsIncompatibleFixture() {
        // 客厅空调不能放到落地灯位
        #expect(HouseEditing.planDrop(src("d1"), roomKey: "r1", spot: .fixture("floor_lamp"), house: house()) == .reject(.incompatible))
        // 卧室没有电视位
        #expect(HouseEditing.planDrop(src("d2"), roomKey: "r2", spot: .fixture("tv"), house: house()) == .reject(.incompatible))
        #expect(HouseEditing.planDrop(src("d2"), roomKey: "r2", spot: .badge("b9"), house: house()) == .reject(.incompatible))
        #expect(HouseEditing.planDrop(src("d1"), roomKey: "nope", spot: .badge("b1"), house: house()) == .reject(.roomNotInHouse))
    }

    @Test func swapsTwoLamps() {
        let h = house()
        #expect(h.rooms[0].device(at: .fixture("floor_lamp"))?.did == "d3")
        #expect(h.rooms[0].device(at: .fixture("sconce"))?.did == "d15")
        let v = HouseEditing.planDrop(src("d15"), roomKey: "r1", spot: .fixture("floor_lamp"), house: h)
        #expect(v == .accept([HouseDropChange(did: "d15", place: "fixture:floor_lamp"), HouseDropChange(did: "d3", place: "fixture:sconce")]))
        let r = applied(v).rooms[0]
        #expect(r.device(at: .fixture("floor_lamp"))?.did == "d15")
        #expect(r.device(at: .fixture("sconce"))?.did == "d3")
    }

    @Test func dropsOnSpecificBadgeAndSwapsWithIncompatible() {
        // 客厅现在有空调位（默认空调进 ac 灯具位）；这里用户把空调指定成徽章
        var base = HouseFile(); base.setDevice(home: "h", did: "d1") { $0.place = "badge" }
        func ap(_ v: HouseDropVerdict) -> ResolvedHouse {
            var f = base; HouseEditing.apply(v.changes, to: &f, home: "h"); return house(f.homes["h"])
        }
        let h = house(base.homes["h"])
        let acSpot = h.rooms[0].devices.first { $0.did == "d1" }?.spot
        #expect(acSpot == .badge("b1"))
        // 落地灯拖到 b3：落地灯位空出来，空调还在 b1
        let r = ap(HouseEditing.planDrop(src("d3"), roomKey: "r1", spot: .badge("b3"), house: h)).rooms[0]
        #expect(r.devices.first { $0.did == "d3" }?.spot == .badge("b3"))
        #expect(r.devices.first { $0.did == "d1" }?.spot == .badge("b1"))
        // 落地灯拖到空调占着的 b1：空调不能进落地灯位，改用其他徽章位
        let v = HouseEditing.planDrop(src("d3"), roomKey: "r1", spot: .badge("b1"), house: h)
        #expect(v.changes.last == HouseDropChange(did: "d1", place: "badge"))
        let r2 = ap(v).rooms[0]
        #expect(r2.devices.first { $0.did == "d3" }?.spot == .badge("b1"))
        if case .badge? = r2.devices.first(where: { $0.did == "d1" })?.spot {} else { Issue.record("AC should keep a badge") }
        // 再把空调拖回客厅的空调位
        let back = HouseEditing.planDrop(src("d1"), roomKey: "r1", spot: .fixture("ac"), house: h)
        #expect(back == .accept([HouseDropChange(did: "d1", place: "fixture:ac")]))
        #expect(ap(back).rooms[0].device(at: .fixture("ac"))?.did == "d1")
    }

    @Test func dropHiddenDeviceShowsIt() {
        var f = HouseFile(); f.setDevice(home: "h", did: "d4") { $0.visible = false }
        let h = house(f.homes["h"])
        #expect(h.hidden.contains("d4"))
        let v = HouseEditing.planDrop(src("d4", hidden: true), roomKey: "r2", spot: .badge("b2"), house: h)
        #expect(v == .accept([HouseDropChange(did: "d4", place: "badge:b2", visible: true)]))
    }

    @Test func sameSpotIsNoop() {
        #expect(HouseEditing.planDrop(src("d3"), roomKey: "r1", spot: .fixture("floor_lamp"), house: house()) == .accept([]))
    }

    @Test func clearMovesFixtureToBadgeAndBadgeToChip() {
        let h = house()
        #expect(HouseEditing.planClear(did: "d3", house: h) == [HouseDropChange(did: "d3", place: "badge")])
        #expect(HouseEditing.planClear(did: "d1", house: h) == [HouseDropChange(did: "d1", place: "badge")])   // 客厅空调位 → 徽章
        #expect(HouseEditing.planClear(did: "d4", house: h) == [HouseDropChange(did: "d4", place: "none")])    // 风扇徽章 → 只在按钮行
    }
}

@Suite struct HouseUndoTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func edit(_ f: inout HouseFile, _ stack: inout HouseUndoStack, at t: Date, _ body: (inout HouseFile) -> Void) {
        let before = f; body(&f)
        stack.record(HouseEdit.diff(label: "x", home: "h", before: before, after: f))
    }

    @Test func undoRedoAssignVisibilityRoomAndReset() {
        var f = HouseFile(), s = HouseUndoStack()
        edit(&f, &s, at: t0) { $0.setDevice(home: "h", did: "d3", now: self.t0) { $0.place = "fixture:sconce" } }
        edit(&f, &s, at: t0) { $0.setDevice(home: "h", did: "d4", now: self.t0) { $0.visible = false } }
        edit(&f, &s, at: t0) { $0.setRoom(home: "h", key: "r9", module: "study", now: self.t0) }
        edit(&f, &s, at: t0) { $0.reset(home: "h", now: self.t0) }
        #expect(s.undos.count == 4)
        let allAuto = f.homes["h"]!.devices.values.allSatisfy { $0.isEmpty }; #expect(allAuto)

        let t1 = t0.addingTimeInterval(10)
        let u1 = s.undo(&f, now: t1); #expect(u1 != .stale)   // 撤销「恢复自动」
        #expect(f.homes["h"]?.devices["d3"]?.place == "fixture:sconce")
        #expect(f.homes["h"]?.devices["d4"]?.visible == false)
        #expect(f.homes["h"]?.rooms["r9"]?.module == "study")
        #expect(f.homes["h"]?.devices["d3"]?.updatedAt == t1)   // 写回用新的时间，合并时赢

        _ = s.undo(&f, now: t1); _ = s.undo(&f, now: t1); _ = s.undo(&f, now: t1)
        #expect(f.homes["h"]?.devices["d3"]?.isEmpty == true)
        #expect(f.homes["h"]?.rooms["r9"]?.module == nil)
        #expect(!s.canUndo && s.redos.count == 4)
        let u2 = s.undo(&f, now: t1); #expect(u2 == .empty)

        _ = s.redo(&f, now: t1)
        #expect(f.homes["h"]?.devices["d3"]?.place == "fixture:sconce")
        // 新的编辑清掉重做
        edit(&f, &s, at: t1) { $0.setDevice(home: "h", did: "d1", now: t1) { $0.place = "badge" } }
        #expect(!s.canRedo)
    }

    @Test func noChangeIsNotRecorded() {
        var f = HouseFile(), s = HouseUndoStack()
        edit(&f, &s, at: t0) { $0.reset(home: "h", did: "d3", now: self.t0) }   // 本来就是自动
        #expect(!s.canUndo)
    }

    @Test func externalEditToOtherEntryKeepsStack() {
        var f = HouseFile(), s = HouseUndoStack()
        edit(&f, &s, at: t0) { $0.setDevice(home: "h", did: "d3", now: self.t0) { $0.place = "badge" } }
        f.setDevice(home: "h", did: "d9", now: t0) { $0.visible = false }   // 另一台 Mac 改了别的设备
        let dropped = s.rebase(on: f); #expect(!dropped)
        let u = s.undo(&f); #expect(u != .stale)
        #expect(f.homes["h"]?.devices["d3"]?.isEmpty == true)
        #expect(f.homes["h"]?.devices["d9"]?.visible == false)
    }

    @Test func externalEditToSameEntryClearsStack() {
        var f = HouseFile(), s = HouseUndoStack()
        edit(&f, &s, at: t0) { $0.setDevice(home: "h", did: "d3", now: self.t0) { $0.place = "badge" } }
        var g = f; g.setDevice(home: "h", did: "d3", now: t0.addingTimeInterval(5)) { $0.place = "none" }   // CLI 改了同一台
        var stale = s
        let u = stale.undo(&g); #expect(u == .stale)
        #expect(!stale.canUndo)
        #expect(g.homes["h"]?.devices["d3"]?.place == "none")   // 不会把外部改动撤掉
        let dropped = s.rebase(on: g); #expect(dropped && !s.canUndo)
    }

    @Test func undoSurvivesMergeWithOlderRemote() {
        var f = HouseFile(), s = HouseUndoStack()
        edit(&f, &s, at: t0) { $0.setDevice(home: "h", did: "d3", now: self.t0) { $0.place = "badge" } }
        let remoteBeforeUndo = f
        _ = s.undo(&f, now: t0.addingTimeInterval(1))
        // 另一台 Mac 还没同步到撤销，合并后撤销（更新的 updatedAt）仍然生效
        let m = HouseFile.merge(remoteBeforeUndo, f)
        #expect(m.homes["h"]?.devices["d3"]?.isEmpty == true)
    }

    @Test func limitDropsOldest() {
        var f = HouseFile(), s = HouseUndoStack(); s.limit = 3
        for i in 0..<5 { edit(&f, &s, at: t0) { $0.setDevice(home: "h", did: "d\(i)", now: self.t0) { $0.place = "none" } } }
        #expect(s.undos.count == 3)
        #expect(s.undos.first?.devices.keys.first == "d2")
    }

    @Test func decorUndoUsesFreshTombstonesAndPreservesOtherSlots() {
        var file = HouseFile(), stack = HouseUndoStack()
        edit(&file, &stack, at: t0) { $0.setDecor(home: "h", key: "r/corner", item: "monstera", now: self.t0) }
        let remote = file
        file.setDecor(home: "h", key: "r/desk", item: "books", now: t0)
        let unrelatedChangeDroppedUndo = stack.rebase(on: file)
        #expect(!unrelatedChangeDroppedUndo)
        _ = stack.undo(&file, now: t0.addingTimeInterval(1))
        #expect(file.homes["h"]?.decor?["r/corner"]?.item == nil)
        #expect(file.homes["h"]?.decor?["r/corner"]?.updatedAt == t0.addingTimeInterval(1))
        #expect(HouseFile.merge(remote, file).homes["h"]?.decor?["r/corner"]?.item == nil)
        #expect(file.homes["h"]?.decor?["r/desk"]?.item == "books")
        _ = stack.redo(&file, now: t0.addingTimeInterval(2))
        #expect(file.homes["h"]?.decor?["r/corner"]?.item == "monstera")
        file.setDecor(home: "h", key: "r/corner", item: "none", now: t0.addingTimeInterval(3))
        let sameSlotDroppedUndo = stack.rebase(on: file)
        #expect(sameSlotDroppedUndo)
        #expect(!stack.canUndo)
    }
}
