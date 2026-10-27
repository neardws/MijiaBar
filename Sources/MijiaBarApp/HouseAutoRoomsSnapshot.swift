import AppKit
import SwiftUI
import MijiaCore

extension Snapshot {
    static func houseAutoRooms(dir: String) {
        NSApplication.shared.setActivationPolicy(.accessory)
        do { try writeHouseAutoRooms(dir: dir) }
        catch { fputs("house auto rooms snapshot: \(error)\n", stderr); exit(1) }
        exit(0)
    }

    private static func writeHouseAutoRooms(dir: String) throws {
        let out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let model = AppModel(mock: true)
        let home = model.houseHomeKey
        func device(_ id: String, _ name: String, _ product: String, _ module: HouseModule) -> Device {
            Device(did: id, name: name, model: product, isOnline: true, homeId: home, homeName: "Demo",
                   roomName: module.title, roomId: module.rawValue)
        }
        let classicDevices = [
            device("demo-living", L("落地灯", "Floor lamp"), "yeelink.light.demo", .living),
            device("demo-bedroom", L("床头灯", "Bedside lamp"), "yeelink.light.demo", .bedroom),
            device("demo-study", L("智能插座", "Smart plug"), "cuco.plug.demo", .study),
            device("demo-entry", L("智能门铃", "Doorbell"), "madv.cateye.demo", .generic),
        ]
        let extraDevices = [
            device("demo-fridge", L("冰箱", "Fridge"), "viomi.fridge.demo", .kitchen),
            device("demo-pendant", L("吊灯", "Pendant light"), "yeelink.light.demo", .kitchen),
            device("demo-heater", L("热水器", "Water heater"), "zimi.waterheater.demo", .bathroom),
            device("demo-ceiling", L("吸顶灯", "Ceiling light"), "yeelink.light.demo", .bathroom),
            device("demo-washer", L("洗衣机", "Washer"), "mijia.washer.demo", .balcony),
            device("demo-wall", L("壁灯", "Wall lamp"), "yeelink.light.demo", .balcony),
        ]
        var summaries: [String: Any] = [:]
        func summary(_ scenario: String) {
            let config = model.house.homes[home]
            let effective = model.houseEffectiveLayout
            let resolved = model.houseResolved
            summaries[scenario] = [
                "source": HouseAutoLayout.source(config: config, effective: effective),
                "classic": HouseLayoutSolver.isClassicGeometry(effective),
                "style": model.houseStyle,
                "cells": (effective ?? model.houseClassicLayout).map {
                    ["room": $0.room, "module": $0.module, "col": $0.col, "row": $0.row] as [String: Any]
                },
                "rooms": resolved.rooms.map { room in
                    ["key": room.key, "title": room.title, "module": room.module.rawValue,
                     "devices": room.devices.map(\.did)] as [String: Any]
                },
                "excluded": resolved.excluded.map {
                    ["key": $0.key, "module": $0.module.rawValue, "reason": $0.reason.rawValue, "count": $0.deviceCount] as [String: Any]
                },
            ]
        }
        func scene(_ scenario: String, phase: HousePhase) throws {
            appearance = NSAppearance(named: phase == .day ? .aqua : .darkAqua)
            let config = model.house.homes[home] ?? HomeHouse()
            let layout = model.houseLayoutCells
            guard let source = HouseSceneSource.make(layout: layout, phase: phase, style: model.houseStyle, config: config) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let width: CGFloat = 960
            let rooms = model.houseRooms.map { $0.lit(Set(HouseCatalog.fixtures($0.module).map(\.id)), badgesOn: true) }
            render(HouseCutawaySceneView(rooms: rooms, phase: phase, fitWidth: width, layout: layout,
                                        style: model.houseStyle, decorConfig: config).background(Theme.bg),
                   out.appendingPathComponent("\(scenario).png"),
                   size: CGSize(width: width, height: ceil(source.artSize.height * width / source.artSize.width)))
            summary(scenario)
        }
        model.devices = classicDevices
        try scene("auto-rooms-classic-day", phase: .day)
        model.devices += extraDevices
        let classic = model.houseClassicLayout
        model.house.setLayout(home: home, layout: classic)
        try scene("auto-rooms-before-day", phase: .day)
        model.house.setLayout(home: home, layout: nil)
        try scene("auto-rooms-after-day", phase: .day)
        try scene("auto-rooms-after-night", phase: .night)
        for style in ["japanese", "modern"] {
            model.house.setStyle(home: home, style: style)
            try scene("auto-rooms-after-\(style)-day", phase: .day)
        }
        model.house.setStyle(home: home, style: nil)
        appearance = NSAppearance(named: .aqua)
        render(HouseListEmbed(snapshotPhase: .day).padding(12).background(Theme.bg).environmentObject(model),
               out.appendingPathComponent("auto-rooms-menubar-day.png"), size: CGSize(width: 360, height: 390))
        summary("auto-rooms-menubar-day")
        render(HouseArrangeView().background(Theme.bg).environmentObject(model),
               out.appendingPathComponent("auto-rooms-arrange.png"), size: HouseWindow.editSize)
        summary("auto-rooms-arrange")
        try JSONSerialization.data(withJSONObject: summaries, options: [.prettyPrinted, .sortedKeys])
            .write(to: out.appendingPathComponent("auto-rooms.json"))
    }
}
