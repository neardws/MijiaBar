import Foundation
import Network
import CommonCrypto
import CryptoKit
import os

public enum MiIOError: LocalizedError {
    case timeout, badResponse, deviceError(String), invalidToken, noLAN
    public var errorDescription: String? {
        switch self {
        case .timeout: return L("局域网请求超时", "LAN request timed out")
        case .badResponse: return L("设备响应无效", "Bad device response")
        case .deviceError(let e): return L("设备返回错误：", "Device error: ") + e
        case .invalidToken: return L("token 无效", "Invalid token")
        case .noLAN: return L("没有局域网地址或 token，且未登录小米云", "No LAN info and not logged in")
        }
    }
}

/// miIO 局域网协议（UDP 54321，AES-128-CBC，key=MD5(token)，iv=MD5(key+token)）
/// 同一台设备复用一个实例：握手（hello）结果会缓存，不必每次请求都多等一个往返。
/// 用 actor 保证同一设备的握手状态和消息 id 不会被并发请求打乱。
public actor MiIODevice {
    public nonisolated let ip: String
    public let timeout: TimeInterval
    let codec: MiIOCodec
    private var deviceID: UInt32 = 0
    private var stampOffset: Int = 0
    private var msgID = Int.random(in: 1...9000)
    /// 发一个包、收一个包；默认走 UDP，测试时可以换成假设备
    private let transport: @Sendable (Data, TimeInterval) async throws -> Data

    public init(ip: String, tokenHex: String, timeout: TimeInterval = 5) throws {
        try self.init(ip: ip, tokenHex: tokenHex, timeout: timeout, transport: nil)
    }

    init(ip: String, tokenHex: String, timeout: TimeInterval, transport: (@Sendable (Data, TimeInterval) async throws -> Data)?) throws {
        guard let t = Data(hex: tokenHex), t.count == 16 else { throw MiIOError.invalidToken }
        self.ip = ip; self.timeout = timeout; codec = MiIOCodec(token: t)
        self.transport = transport ?? { p, timeout in try await MiIODevice.udp(ip: ip, p, timeout: timeout) }
    }

    /// 超时或网络不通：说明当前不在设备所在的局域网（设备返回的业务错误不算）
    public nonisolated static func isUnreachable(_ e: Error) -> Bool {
        if case MiIOError.timeout = e { return true }
        return e is NWError
    }

    static func udp(ip: String, _ payload: Data, timeout: TimeInterval) async throws -> Data {
        let queue = DispatchQueue(label: "miio")
        return try await withCheckedThrowingContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(ip), port: 54321, using: .udp)
            // 失败、收到回包、超时可能先后触发，只取第一个
            let done = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (Result<Data, Error>) -> Void = { r in
                guard !done.withLock({ d in defer { d = true }; return d }) else { return }
                conn.cancel(); cont.resume(with: r)
            }
            conn.stateUpdateHandler = { st in if case .failed(let e) = st { finish(.failure(e)) } }
            conn.start(queue: queue)
            conn.send(content: payload, completion: .contentProcessed { e in if let e { finish(.failure(e)) } })
            conn.receiveMessage { data, _, _, err in
                if let err { finish(.failure(err)) } else if let data { finish(.success(data)) }
                else { finish(.failure(MiIOError.badResponse)) }
            }
            queue.asyncAfter(deadline: .now() + timeout) { finish(.failure(MiIOError.timeout)) }
        }
    }

    public func hello() async throws {
        let r = try await transport(MiIOCodec.helloPacket, timeout)
        guard r.count >= 32 else { throw MiIOError.badResponse }
        deviceID = r.be32(8)
        stampOffset = Int(r.be32(12)) - Int(Date().timeIntervalSince1970)
    }

    /// 旧版 miIO 命令（例如空调伴侣的 get_prop / set_power），结果统一成数组
    public func send(method: String, params: [PropValue]) async throws -> [PropValue] {
        let r = try await call(method: method, params: params.map(\.any))
        return (r as? [Any])?.map { PropValue($0) } ?? [PropValue(r)]
    }

    func call(method: String, params: Any) async throws -> Any {
        let cached = deviceID != 0
        if !cached { try await hello() }
        do { return try await request(method: method, params: params) }
        catch where cached && Self.isUnreachable(error) {
            // 缓存的握手可能已失效（例如设备重启后时间戳变了）：重新握手再试一次
            deviceID = 0
            try await hello()
            return try await request(method: method, params: params)
        }
    }

    private func request(method: String, params: Any) async throws -> Any {
        msgID += 1
        let json = try JSONSerialization.data(withJSONObject: ["id": msgID, "method": method, "params": params] as [String: Any])
        let packet = try codec.encode(json, deviceID: deviceID, stamp: UInt32(Int(Date().timeIntervalSince1970) + stampOffset))
        let resp = try codec.decode(try await transport(packet, timeout))
        guard let obj = try JSONSerialization.jsonObject(with: resp) as? [String: Any] else { throw MiIOError.badResponse }
        if let e = obj["error"] { throw MiIOError.deviceError("\(e)") }
        return obj["result"] ?? NSNull()
    }

    /// MIoT get_properties，返回键为 "siid.piid"
    public func getProperties(_ ps: [(Int, Int)]) async throws -> [String: PropValue] {
        let params = ps.map { ["did": "\($0.0).\($0.1)", "siid": $0.0, "piid": $0.1] as [String: Any] }
        let res = try await call(method: "get_properties", params: params) as? [[String: Any]] ?? []
        var out: [String: PropValue] = [:]
        for r in res where (r["code"] as? Int ?? -1) == 0 { if let d = r["did"] as? String { out[d] = PropValue(r["value"]) } }
        return out
    }

    public func setProperty(siid: Int, piid: Int, value: PropValue) async throws {
        _ = try await call(method: "set_properties", params: [["did": "set", "siid": siid, "piid": piid, "value": value.any]])
    }

    public func action(siid: Int, aiid: Int, inputs: [PropValue]) async throws -> PropValue {
        PropValue(try await call(method: "action", params: ["did": "call-\(siid)-\(aiid)", "siid": siid, "aiid": aiid, "in": inputs.map(\.any)]))
    }
}

/// miIO 数据包的加解密与封包（与网络无关，便于测试）
struct MiIOCodec {
    let token: Data, key: Data, iv: Data
    init(token: Data) { self.token = token; key = md5(token); iv = md5(key + token) }

    static let helloPacket: Data = { var p = Data([0x21, 0x31, 0x00, 0x20]); p += Data(repeating: 0xFF, count: 28); return p }()

    /// 32 字节头（魔数、长度、0、设备 id、时间戳、MD5 校验）+ 加密后的 JSON
    func encode(_ json: Data, deviceID: UInt32, stamp: UInt32) throws -> Data {
        let enc = try aes(json, op: CCOperation(kCCEncrypt))
        var h = Data([0x21, 0x31]); h.appendBE16(UInt16(32 + enc.count))
        h.appendBE32(0); h.appendBE32(deviceID); h.appendBE32(stamp)
        return h + md5(h + token + enc) + enc
    }

    /// 取出包体并解密，去掉设备在 JSON 末尾补的 0
    func decode(_ packet: Data) throws -> Data {
        guard packet.count > 32 else { throw MiIOError.badResponse }
        return try aes(packet.subdata(in: packet.startIndex + 32..<packet.endIndex), op: CCOperation(kCCDecrypt)).filter { $0 != 0 }
    }

    func aes(_ input: Data, op: CCOperation) throws -> Data {
        var out = Data(count: input.count + kCCBlockSizeAES128); var moved = 0
        let outCap = out.count
        let st = out.withUnsafeMutableBytes { o in input.withUnsafeBytes { i in key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCrypt(op, CCAlgorithm(kCCAlgorithmAES128), CCOptions(kCCOptionPKCS7Padding),
                    k.baseAddress, kCCKeySizeAES128, v.baseAddress, i.baseAddress, input.count,
                    o.baseAddress, outCap, &moved) } } } }
        guard st == kCCSuccess else { throw MiIOError.badResponse }
        return out.prefix(moved)
    }
}

func md5(_ d: Data) -> Data { Data(Insecure.MD5.hash(data: d)) }

extension Data {
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: .whitespaces); guard s.count % 2 == 0 else { return nil }
        var d = Data(); var i = s.startIndex
        while i < s.endIndex { let j = s.index(i, offsetBy: 2); guard let b = UInt8(s[i..<j], radix: 16) else { return nil }; d.append(b); i = j }
        self = d
    }
    func be32(_ o: Int) -> UInt32 { self[startIndex+o..<startIndex+o+4].reduce(0) { $0 << 8 | UInt32($1) } }
    mutating func appendBE16(_ v: UInt16) { append(UInt8(v >> 8)); append(UInt8(v & 0xff)) }
    mutating func appendBE32(_ v: UInt32) { for s in [24, 16, 8, 0] { append(UInt8((v >> UInt32(s)) & 0xff)) } }
}
