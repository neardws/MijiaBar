import Foundation
import Testing
@testable import MijiaCore

private let token = "00112233445566778899aabbccddeeff"

/// 假的 miIO 设备：按真实协议解包请求、加密回复，可以模拟掉线、丢包和重启
final class FakeDevice: @unchecked Sendable {
    let codec = MiIOCodec(token: Data(hex: token)!)
    let deviceID: UInt32 = 0x0102_0304
    var stamp: UInt32 = 1_000_000
    var unreachable = false
    var hellos = 0, requests = 0
    var lastRequest: [String: Any]?
    var reply: ([String: Any]) -> [String: Any] = { ["id": $0["id"] ?? 0, "result": ["ok"]] }
    private let lock = NSLock()

    /// 设备重启：时钟归零，之前握手得到的时间戳全部作废
    func reboot() { lock.withLock { stamp = 5 } }

    func handle(_ p: Data, _ timeout: TimeInterval) throws -> Data {
        try lock.withLock {
            if unreachable { throw MiIOError.timeout }
            if p == MiIOCodec.helloPacket {
                hellos += 1
                var r = Data([0x21, 0x31, 0x00, 0x20]); r.appendBE32(0); r.appendBE32(deviceID); r.appendBE32(stamp)
                return r + Data(repeating: 0, count: 16)
            }
            requests += 1
            // 真实设备会忽略时间戳对不上的包，表现为超时
            guard p.be32(8) == deviceID, abs(Int(p.be32(12)) - Int(stamp)) < 60 else { throw MiIOError.timeout }
            let req = try JSONSerialization.jsonObject(with: codec.decode(p)) as! [String: Any]
            lastRequest = req
            return try codec.encode(JSONSerialization.data(withJSONObject: reply(req)), deviceID: deviceID, stamp: stamp)
        }
    }

    func makeDevice() throws -> MiIODevice {
        try MiIODevice(ip: "192.0.2.1", tokenHex: token, timeout: 0.1, transport: { p, t in try self.handle(p, t) })
    }
}

@Suite struct MiIOProtocolTests {
    @Test func codecRoundTrip() throws {
        let c = MiIOCodec(token: Data(hex: token)!)
        let json = Data(#"{"id":1,"method":"get_prop","params":["power"]}"#.utf8)
        let packet = try c.encode(json, deviceID: 42, stamp: 7)
        #expect(packet.prefix(2) == Data([0x21, 0x31]))
        #expect(Int(packet[2]) << 8 | Int(packet[3]) == packet.count)
        #expect(packet.be32(8) == 42 && packet.be32(12) == 7)
        #expect(try c.decode(packet) == json)
    }

    @Test func requestReachesDeviceAndReturnsResult() async throws {
        let fake = FakeDevice()
        fake.reply = { ["id": $0["id"]!, "result": ["on", "cool", 26]] }
        let r = try await fake.makeDevice().send(method: "get_prop", params: [.string("power"), .string("mode"), .string("tar_temp")])
        #expect(fake.lastRequest?["method"] as? String == "get_prop")
        #expect(fake.lastRequest?["params"] as? [String] == ["power", "mode", "tar_temp"])
        #expect(r == [.string("on"), .string("cool"), .int(26)])
    }

    @Test func handshakeIsReusedAcrossRequests() async throws {
        let fake = FakeDevice()
        let d = try fake.makeDevice()
        _ = try await d.send(method: "get_prop", params: [.string("power")])
        _ = try await d.send(method: "set_power", params: [.string("on")])
        _ = try await d.send(method: "get_prop", params: [.string("power")])
        #expect(fake.hellos == 1)
        #expect(fake.requests == 3)
    }

    @Test func staleHandshakeIsRefreshedOnce() async throws {
        let fake = FakeDevice()
        let d = try fake.makeDevice()
        _ = try await d.send(method: "get_prop", params: [.string("power")])
        fake.reboot()
        _ = try await d.send(method: "get_prop", params: [.string("power")])
        #expect(fake.hellos == 2)
    }

    @Test func unreachableDeviceFailsFastWithoutRetryLoop() async throws {
        let fake = FakeDevice(); fake.unreachable = true
        await #expect(throws: MiIOError.self) { try await fake.makeDevice().send(method: "get_prop", params: []) }
        #expect(MiIODevice.isUnreachable(MiIOError.timeout))
    }

    @Test func deviceErrorIsNotTreatedAsUnreachable() async throws {
        let fake = FakeDevice()
        fake.reply = { ["id": $0["id"]!, "error": ["code": -5001, "message": "invalid arg"]] }
        do {
            _ = try await fake.makeDevice().send(method: "set_mode", params: [.string("bogus")])
            Issue.record("expected a device error")
        } catch {
            #expect(!MiIODevice.isUnreachable(error))
            #expect(fake.hellos == 1)
        }
    }
}

@Suite struct LANHealthTests {
    @Test func backsOffAfterFailureThenRetries() {
        var h = LANHealth(backoff: 300)
        let t0 = Date()
        #expect(h.shouldTry("ac", now: t0))
        h.recordFailure("ac", now: t0)
        #expect(!h.shouldTry("ac", now: t0.addingTimeInterval(299)))
        #expect(h.shouldTry("ac", now: t0.addingTimeInterval(300)))
        #expect(h.shouldTry("lamp", now: t0))
    }

    @Test func successAndResetClearTheBackoff() {
        var h = LANHealth()
        h.recordFailure("ac"); h.recordSuccess("ac")
        #expect(h.shouldTry("ac"))
        h.recordFailure("ac"); h.reset()
        #expect(h.shouldTry("ac"))
    }
}

@Suite struct ControllerLANTests {
    let ac = Device(did: "ac1", name: "AC", model: "lumi.acpartner.mcn02", ip: "192.0.2.1", token: token)
    let cloud = XiaomiCloud(session: Session(userId: "test", ssecurity: "", serviceToken: "", region: "cn"))

    func controller(_ fake: FakeDevice, cloud: XiaomiCloud?) -> Controller {
        let c = Controller(cloud: cloud)
        c.makeLAN = { _, _ in try fake.makeDevice() }
        return c
    }

    @Test func reusesOneConnectionPerDevice() throws {
        let c = controller(FakeDevice(), cloud: cloud)
        let a = try #require(c.lan(ac)), b = try #require(c.lan(ac))
        #expect(a === b)
        var moved = ac; moved.ip = "192.0.2.9"
        let c2 = try #require(c.lan(moved))
        #expect(c2 !== a)
    }

    @Test func skipsLANAfterTimeoutWhenCloudIsAvailable() async throws {
        let fake = FakeDevice(); fake.unreachable = true
        let c = controller(fake, cloud: cloud)
        let m = try #require(c.lan(ac))
        _ = try? await c.viaLAN(ac, m) { (d: MiIODevice) -> [PropValue] in try await d.send(method: "get_prop", params: []) }
        #expect(c.lan(ac) == nil)
    }

    @Test func alwaysTriesLANWithoutCloud() async throws {
        let fake = FakeDevice(); fake.unreachable = true
        let c = controller(fake, cloud: nil)
        let m = try #require(c.lan(ac))
        _ = try? await c.viaLAN(ac, m) { (d: MiIODevice) -> [PropValue] in try await d.send(method: "get_prop", params: []) }
        #expect(c.lan(ac) != nil)
    }

    @Test func deviceErrorsDoNotTriggerBackoff() async throws {
        let fake = FakeDevice()
        fake.reply = { ["id": $0["id"]!, "error": "busy"] }
        let c = controller(fake, cloud: cloud)
        let m = try #require(c.lan(ac))
        _ = try? await c.viaLAN(ac, m) { (d: MiIODevice) -> [PropValue] in try await d.send(method: "set_power", params: [.string("on")]) }
        #expect(c.lan(ac) != nil)
    }
}
