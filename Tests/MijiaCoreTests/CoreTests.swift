import Foundation
import Testing
@testable import MijiaCore

@Suite struct PropValueTests {
    @Test func parsesCommandLineLiterals() {
        #expect(PropValue.parse("true") == .bool(true))
        #expect(PropValue.parse(" FALSE ") == .bool(false))
        #expect(PropValue.parse("26") == .int(26))
        #expect(PropValue.parse("26.5") == .double(26.5))
        #expect(PropValue.parse("\"26\"") == .string("26"))
        #expect(PropValue.parse("cool") == .string("cool"))
    }

    @Test func keepsJSONBooleansApartFromNumbers() throws {
        let o = try JSONSerialization.jsonObject(with: Data(#"[true, 1, 1.5, "on", null]"#.utf8)) as! [Any]
        #expect(o.map { PropValue($0) } == [.bool(true), .int(1), .double(1.5), .string("on"), .null])
        #expect(PropValue(nil) == .null)
    }

    @Test func coercesToMIoTFormats() {
        #expect(PropValue.string("on").coerced(to: "bool") == .bool(true))
        #expect(PropValue.int(0).coerced(to: "bool") == .bool(false))
        #expect(PropValue.double(25.6).coerced(to: "uint8") == .int(26))
        #expect(PropValue.int(26).coerced(to: "float") == .double(26))
        #expect(PropValue.double(3).coerced(to: "string") == .string("3"))
        #expect(PropValue.string("abc").coerced(to: "int32") == .string("abc"))
    }

    @Test func describesValuesForDisplay() {
        #expect(PropValue.double(26).description == "26")
        #expect(PropValue.double(26.25).description == "26.2")
        #expect(PropValue.bool(true).description == "true")
        #expect(PropValue.null.description == "-")
    }

    @Test func survivesTheDeviceCache() throws {
        let v: [String: PropValue] = ["a": .bool(true), "b": .int(3), "c": .double(2.5), "d": .string("x"), "e": .null]
        #expect(try JSONDecoder().decode([String: PropValue].self, from: JSONEncoder().encode(v)) == v)
    }
}

/// 精简过的空调规格，结构和 miot-spec.org 返回的一致
let acSpecJSON = #"""
{"type": "urn:miot-spec-v2:device:air-conditioner:0000A004:xiaomi-mt5:1", "description": "Air Conditioner",
 "services": [
  {"iid": 1, "type": "urn:miot-spec-v2:service:device-information:00007801:xiaomi-mt5:1", "description": "Device Information",
   "properties": [{"iid": 1, "type": "urn:miot-spec-v2:property:manufacturer:00000001:xiaomi-mt5:1", "description": "Manufacturer", "format": "string", "access": ["read"]}]},
  {"iid": 2, "type": "urn:miot-spec-v2:service:air-conditioner:00007832:xiaomi-mt5:1", "description": "Air Conditioner",
   "properties": [
    {"iid": 1, "type": "urn:miot-spec-v2:property:on:00000006:xiaomi-mt5:1", "description": "Switch Status", "format": "bool", "access": ["read", "write", "notify"]},
    {"iid": 2, "type": "urn:miot-spec-v2:property:mode:00000008:xiaomi-mt5:1", "description": "Mode", "format": "uint8", "access": ["read", "write", "notify"],
     "value-list": [{"value": 1, "description": "Cool"}, {"value": 2, "description": "Dry"}, {"value": 5, "description": "Heat"}]},
    {"iid": 4, "type": "urn:miot-spec-v2:property:target-temperature:00000021:xiaomi-mt5:1", "description": "Target Temperature", "format": "float",
     "access": ["read", "write", "notify"], "unit": "celsius", "value-range": [16, 31, 0.5]}],
   "actions": [{"iid": 1, "type": "urn:miot-spec-v2:action:toggle:00002811:xiaomi-mt5:1", "description": "Toggle", "in": []}]},
  {"iid": 3, "type": "urn:miot-spec-v2:service:fan-control:00007808:xiaomi-mt5:1", "description": "Fan Control",
   "properties": [
    {"iid": 2, "type": "urn:miot-spec-v2:property:fan-level:00000016:xiaomi-mt5:1", "description": "Fan Level", "format": "uint8", "access": ["read", "write"],
     "value-list": [{"value": 0, "description": "Auto"}, {"value": 1, "description": "Low"}, {"value": 3, "description": "High"}]},
    {"iid": 4, "type": "urn:miot-spec-v2:property:vertical-swing:00000018:xiaomi-mt5:1", "description": "Vertical Swing", "format": "bool", "access": ["read", "write"]}]},
  {"iid": 4, "type": "urn:miot-spec-v2:service:environment:0000780A:xiaomi-mt5:1", "description": "Environment",
   "properties": [{"iid": 7, "type": "urn:miot-spec-v2:property:temperature:00000020:xiaomi-mt5:1", "description": "Indoor Temperature", "format": "float", "access": ["read", "notify"]}]}
 ]}
"""#

func acSpec() throws -> DeviceSpec {
    DeviceSpec.parse(try JSONSerialization.jsonObject(with: Data(acSpecJSON.utf8)) as! [String: Any])
}

@Suite struct SpecTests {
    @Test func parsesServicesPropertiesAndActions() throws {
        let s = try acSpec()
        #expect(s.name == "air-conditioner")
        #expect(s.services.map(\.iid) == [1, 2, 3, 4])
        #expect(s.controlServices.map(\.iid) == [2, 3, 4])
        let t = try #require(s.prop(key: "2.4"))
        #expect(t.name == "target-temperature" && t.range == [16, 31, 0.5] && t.unit == "celsius")
        #expect(t.readable && t.writable && t.isNumber)
        #expect(s.prop(key: "2.2")?.options?.map(\.value) == [1, 2, 5])
        #expect(s.prop(key: "4.7")?.writable == false)
    }

    @Test func findsPropertiesAndActionsByName() throws {
        let s = try acSpec()
        #expect(s.prop(named: "fan-level")?.key == "3.2")
        #expect(s.prop(named: "manufacturer") == nil)   // 设备信息服务不算控制项
        #expect(s.mainOnProperty?.key == "2.1")
        #expect(s.action(named: "toggle")?.key == "2.1")
        #expect(s.action(key: "9.9") == nil)
    }

    @Test func survivesTheSpecCache() throws {
        let s = try acSpec()
        #expect(try JSONDecoder().decode(DeviceSpec.self, from: JSONEncoder().encode(s)) == s)
    }
}

/// 改动全局语言的测试放在一起串行执行，结束后恢复
@Suite(.serialized) struct LocalizedTests {
    func with(_ lang: AppLang, _ body: () throws -> Void) rethrows {
        let old = currentLang; currentLang = lang; defer { currentLang = old }
        try body()
    }

    @Test func picksTheLanguage() {
        with(.zhHans) { #expect(L("设备", "Device") == "设备") }
        with(.zhHant) {
            #expect(L("设备", "Device") == "裝置")                        // 人工校对的台湾用语优先
            #expect(L("温度单元测试", "x") == "溫度單元測試")              // 表里没有的自动转换
            #expect(L("温度单元测试", "x") == "溫度單元測試")              // 第二次走缓存
        }
        with(.en) { #expect(L("设备", "Device") == "Device") }
    }

    @Test func translatesCommonValues() {
        with(.zhHans) { #expect(trValue("Cool") == "制冷"); #expect(trValue("unknown-thing") == "unknown-thing") }
        with(.zhHant) { #expect(trValue("Dry") == "除濕"); #expect(trValue("Heat") == "暖氣") }
        with(.en) { #expect(trValue("Cool") == "Cool") }
    }

    @Test func readsMIoTAirConditioner() throws {
        let s = try acSpec()
        try with(.zhHans) {
            let st = DeviceState(values: ["2.1": .bool(true), "2.2": .int(5), "2.4": .double(26.5), "3.2": .int(3), "3.4": .bool(false), "4.7": .double(24.3)],
                                 spec: s, legacy: false, source: "cloud")
            let a = try #require(ACState.make(st))
            #expect(a.power && a.powerKey == "2.1" && a.onValue == .bool(true))
            #expect(a.modeLabel == "制热" && a.isHeating && !a.isCooling)
            #expect(a.target == 26.5 && a.tempIsFloat && a.minT == 16 && a.maxT == 31 && a.step == 0.5)
            #expect(a.tempValue(26) == .double(26))
            #expect(a.fanLabel == "高" && a.fanKey == "3.2")
            #expect(a.swing == false && a.swingKey == "3.4")
            #expect(a.roomTemp == 24.3)
        }
    }

    @Test func readsLegacyACPartner() {
        with(.en) {
            let st = DeviceState(values: ["power": .string("on"), "mode": .string("cool"), "tar_temp": .int(25), "fan_level": .string("small_fan"),
                                          "ver_swing": .string("off"), "load_power": .double(812.4)], spec: nil, legacy: true, source: "lan")
            let a = ACState.make(st)!
            #expect(a.power && a.isCooling && a.modeLabel == "Cool" && a.fanLabel == "Low")
            #expect(a.tempValue(24.6) == .int(25))
            #expect(a.swing == false && a.swingOn == .string("on"))
            #expect(a.loadPower == 812.4)
        }
    }

    @Test func notAnAirConditionerWithoutTheService() throws {
        let plug = DeviceSpec(type: "urn:miot-spec-v2:device:outlet:0000A002:cuco-v3:1", description: "", services: [])
        #expect(ACState.make(DeviceState(values: [:], spec: plug, legacy: false, source: "cloud")) == nil)
        #expect(ACState.make(DeviceState(values: [:], spec: nil, legacy: false, source: "none")) == nil)
    }
}

@Suite struct DeviceTests {
    @Test func guessesCategoryFromModel() {
        let cases: [(String, DeviceCategory)] = [
            ("lumi.acpartner.mcn02", .ac), ("xiaomi.aircondition.mt5", .ac), ("chuangmi.plug.m1", .plug), ("cuco.plug.v3", .plug),
            ("yeelink.light.ceiling22", .light), ("philips.light.bulb", .light), ("dmaker.fan.p5", .fan), ("zhimi.heater.za1", .heater),
            ("nwt.derh.wdh318efw1", .dehumidifier), ("lumi.sensor_magnet.v2", .sensor), ("xiaomi.tv.eanfv1", .tv), ("isa.camera.hlc7", .camera),
            ("xiaomi.wifispeaker.lx06", .speaker), ("chunmi.cooker.normal2", .kitchen), ("yunmi.waterpuri.lx5", .purifier), ("hp.printer.x1", .printer),
            ("zhimi.airpurifier.mb4", .airPurifier), ("xiaomi.airp.va2b", .airPurifier), ("zhimi.airfresh.va4", .airPurifier),
            ("roborock.vacuum.s5", .other),
        ]
        for (model, cat) in cases { #expect(DeviceCategory.guess(model) == cat, "\(model)") }
    }

    @Test func hidesOfflineAndStaleDevicesUnlessTheUserDecides() {
        let now = Date()
        let online = Device(did: "1", name: "Lamp", model: "m", lastOnline: now.addingTimeInterval(-86400))
        let offline = Device(did: "2", name: "Old", model: "m", isOnline: false)
        let stale = Device(did: "3", name: "Stale", model: "m", lastOnline: now.addingTimeInterval(-31 * 86400))
        var p = Prefs()
        #expect(!p.isHidden(online) && p.isHidden(offline) && p.isHidden(stale))
        p.devices["2"] = DevicePrefs(); p.devices["2"]?.hidden = false
        p.devices["1"] = DevicePrefs(); p.devices["1"]?.hidden = true; p.devices["1"]?.alias = "Desk lamp"
        #expect(!p.isHidden(offline) && p.isHidden(online))
        #expect(p.name(online) == "Desk lamp" && p.name(stale) == "Stale")
    }

    @Test func agentPolicyGatesWrites() {
        var p = AgentPolicy()
        #expect(p.canRead && !p.canWrite("ac"))   // 默认只读
        p.mode = .allowlist; p.allowlist = ["ac"]
        #expect(p.canWrite("ac") && !p.canWrite("lamp"))
        p.mode = .full
        #expect(p.canWrite("lamp"))
        p.mode = .disabled
        #expect(!p.canRead && !p.canWrite("ac"))
    }

    @Test func suggestsLanguagesForEachRegion() {
        #expect(AppLang.suggested(forRegion: "cn").first == .zhHans)
        #expect(AppLang.suggested(forRegion: "us").first == .en)
        #expect(AppLang.suggested(forRegion: "tw") == [.zhHant, .en, .zhHans])
        #expect(AppLang.suggested(forRegion: "hk").first == .zhHant)
        #expect(AppLang.suggested(forRegion: "ru") == [.en, .zhHans, .zhHant])
        #expect(AppLang.allCases == [.zhHans, .zhHant, .en])
    }

    @Test func migratesRemovedLanguages() {
        let d = UserDefaults(suiteName: "MijiaBarLangTest-\(UUID().uuidString)")!
        d.set("ja", forKey: "MijiaBarLang"); d.set(true, forKey: "MijiaBarLangManual")
        #expect(AppLang.saved(d) == nil)                       // 已移除的语言：回到系统 / 地区默认
        #expect(d.string(forKey: "MijiaBarLang") == nil && !d.bool(forKey: "MijiaBarLangManual"))
        d.set("zh-Hant", forKey: "MijiaBarLang")
        #expect(AppLang.saved(d) == .zhHant)
    }
}

/// 期望值由一份独立的 Python 实现算出，和 python-miio / token extractor 的算法一致
@Suite struct CloudSigningTests {
    @Test func rc4DropsTheFirst1024Bytes() {
        let key = Data("0123456789abcdef".utf8), plain = Data("hello mijia".utf8)
        let enc = MiCrypto.rc4(key: key, plain)
        #expect(enc.base64EncodedString() == "9iTS3HyRu54goHU=")
        #expect(MiCrypto.rc4(key: key, enc) == plain)
    }

    @Test func signsRequestsLikeTheMiHomeApp() {
        let sn = MiCrypto.signedNonce(ssecurity: "AAECAwQFBgcICQoLDA0ODw==", nonce: "EBESExQVFhcYGRob")
        #expect(sn == "3Cf46O4tCKK8y7Lb1sjgf/uhlBAfw0WMNN7VX3LAlxo=")
        #expect(XiaomiCloud.encSig("/v2/homeroom/gethome", [("data", #"{"fg":true}"#)], sn) == "5PM2LYJLalQOEKq/wNfDccEzmvc=")
    }

    @Test func nonceIsTwelveBytesWithAMinuteCounter() throws {
        let n = try #require(Data(base64Encoded: MiCrypto.nonce()))
        #expect(n.count == 12)
        #expect(abs(Int(n.be32(8)) - Int(Date().timeIntervalSince1970) / 60) <= 1)
    }

    @Test func regionPicksTheAPIHost() {
        #expect(XiaomiCloud.base("cn") == "https://api.io.mi.com/app")
        #expect(XiaomiCloud.base("de") == "https://de.api.io.mi.com/app")
    }
}

@Suite struct OrderingTests {
    func dev(_ id: String, _ room: String?, home: String = "h1", online: Bool = true) -> Device {
        Device(did: id, name: id, model: "x.plug.y", isOnline: online, homeId: home, homeName: "", roomName: room)
    }

    @Test func arrangeKeepsSavedOrderAppendsNewDropsRemoved() {
        #expect(Ordering.arrange(["a", "b", "c"], saved: nil) == ["a", "b", "c"])
        #expect(Ordering.arrange(["a", "b", "c", "d"], saved: ["c", "gone", "a", "c"]) == ["c", "a", "b", "d"])
    }

    @Test func movesUpDownTopAndDrops() {
        let l = ["a", "b", "c"]
        #expect(Ordering.moved(l, "b", .up) == ["b", "a", "c"])
        #expect(Ordering.moved(l, "b", .down) == ["a", "c", "b"])
        #expect(Ordering.moved(l, "c", .top) == ["c", "a", "b"])
        #expect(Ordering.moved(l, "a", .up) == l)
        #expect(Ordering.dropped(l, "a", onto: "c") == ["b", "c", "a"])
        #expect(Ordering.dropped(l, "c", onto: "a") == ["c", "a", "b"])
    }

    @Test func mergeVisibleLeavesHiddenInPlace() {
        // b 被隐藏：只在可见的 a、c、d 之间调整，b 留在原位
        #expect(Ordering.mergeVisible(full: ["a", "b", "c", "d"], visible: ["d", "a", "c"]) == ["d", "b", "a", "c"])
    }

    @Test func persistsPerHomeAndSurvivesCoding() throws {
        var p = Prefs()
        p.setOrder(home: "h1", key: nil, ["卧室", "办公室"])
        p.setOrder(home: "h1", key: "卧室", ["d2", "d1"])
        p.setOrder(home: "h2", key: nil, ["客厅"])
        let back = try JSONDecoder().decode(Prefs.self, from: JSONEncoder().encode(p))
        #expect(back == p)
        #expect(back.orderedRooms(home: "h1", ["办公室", "卧室", "厨房"]) == ["卧室", "办公室", "厨房"])
        #expect(back.orderedRooms(home: "h3", ["b", "a"]) == ["b", "a"])
        let ds = [dev("d1", "卧室"), dev("d2", "卧室"), dev("d3", "卧室")]
        #expect(back.orderedDevices(home: "h1", key: "卧室", ds).map(\.did) == ["d2", "d1", "d3"])
        // 旧版 prefs.json 没有 order 字段也能读
        let old = try JSONDecoder().decode(Prefs.self, from: Data(#"{"devices":{},"region":"cn"}"#.utf8))
        #expect(old.order == nil)
    }

    @Test func cliListFollowsRoomAndDeviceOrder() {
        var p = Prefs()
        p.setOrder(home: "h1", key: nil, ["卧室", "办公室"])
        p.setOrder(home: "h1", key: "办公室", ["o2", "o1"])
        let ds = [dev("o1", "办公室"), dev("b1", "卧室"), dev("x", nil), dev("o2", "办公室"), dev("z", "客厅", home: "h2")]
        #expect(p.sortedForList(ds) { $0.isEmpty ? "~" : $0 }.map(\.did) == ["b1", "o2", "o1", "x", "z"])
    }
}

@Suite struct HistoryTests {
    var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Shanghai")!; return c }
    func at(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

    @Test func integratesEnergyAndSkipsGaps() {
        var s = Series()
        // 100 W 持续 1 小时（每 10 分钟一个读数）= 100 Wh
        for i in 0...6 { History.record(&s, 100, at: at("2026-10-14T02:00:00Z").addingTimeInterval(Double(i) * 600), energy: true, cal: cal) }
        #expect(abs((s.daily["2026-10-14"]?.wh ?? 0) - 100) < 0.001)
        // 空档 2 小时：不积分
        History.record(&s, 100, at: at("2026-10-14T05:00:00Z"), energy: true, cal: cal)
        #expect(abs((s.daily["2026-10-14"]?.wh ?? 0) - 100) < 0.001)
        #expect(s.daily["2026-10-14"]?.n == 8 && s.daily["2026-10-14"]?.max == 100)
    }

    @Test func ignoresTooFrequentSamplesAndBucketsByLocalDay() {
        var s = Series()
        #expect(History.record(&s, 20, at: at("2026-10-14T15:59:00Z"), cal: cal))       // 上海 23:59
        #expect(!History.record(&s, 21, at: at("2026-10-14T16:00:30Z"), cal: cal))      // 不到 4 分钟，忽略
        #expect(History.record(&s, 22, at: at("2026-10-14T16:05:00Z"), cal: cal))       // 上海次日 00:05
        #expect(s.daily.keys.sorted() == ["2026-10-14", "2026-10-15"])
    }

    @Test func prunesOldData() {
        var s = Series()
        History.record(&s, 1, at: at("2025-01-01T00:00:00Z"), cal: cal)
        History.record(&s, 2, at: at("2026-10-14T00:00:00Z"), cal: cal)
        #expect(s.samples.count == 1 && s.daily.count == 1)
    }

    @Test func monthlyAndLastDays() {
        let d = ["2026-09-30": 1.0, "2026-10-01": 2.0, "2026-10-02": 3.0]
        #expect(History.monthly(d) == ["2026-09": 1, "2026-10": 5])
        let days = History.lastDays(d, days: 3, now: at("2026-10-02T04:00:00Z"), cal: cal)
        #expect(days.map(\.value) == [1, 2, 3])
    }

    @Test func parsesCloudSampleFormats() {
        let r: [[String: Any]] = [["time": 1760400000, "value": "[1.5]"], ["time": "1760313600", "value": 2], ["time": 1, "value": "bad"]]
        #expect(XiaomiCloud.parseSamples(r) == [Sample(t: 1760313600, v: 2), Sample(t: 1760400000, v: 1.5)])
        #expect(XiaomiCloud.parseSamples(["result": [["time": 5, "value": "true"]]]) == [Sample(t: 5, v: 1)])
    }
}
