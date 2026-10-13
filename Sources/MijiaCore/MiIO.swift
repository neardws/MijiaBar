import Foundation
import Network
import CommonCrypto
import CryptoKit

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
public final class MiIODevice {
    public let ip: String
    public var timeout: TimeInterval
    private let token: Data
    private let key: Data
    private let iv: Data
    private var deviceID: UInt32 = 0
    private var stampOffset: Int = 0
    private var msgID = Int.random(in: 1...9000)
    private let queue = DispatchQueue(label: "miio")

    public init(ip: String, tokenHex: String, timeout: TimeInterval = 5) throws {
        guard let t = Data(hex: tokenHex), t.count == 16 else { throw MiIOError.invalidToken }
        self.ip = ip; self.timeout = timeout; token = t
        key = md5(t); iv = md5(key + t)
    }

    private func udp(_ payload: Data) async throws -> Data {
        let timeout = self.timeout
        return try await withCheckedThrowingContinuation { cont in
            let conn = NWConnection(host: NWEndpoint.Host(ip), port: 54321, using: .udp)
            var done = false
            let finish: (Result<Data, Error>) -> Void = { r in
                self.queue.async {
                    guard !done else { return }; done = true
                    conn.cancel(); cont.resume(with: r)
                }
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
        var p = Data([0x21, 0x31, 0x00, 0x20]); p += Data(repeating: 0xFF, count: 28)
        let r = try await udp(p)
        guard r.count >= 32 else { throw MiIOError.badResponse }
        deviceID = r.be32(8)
        stampOffset = Int(r.be32(12)) - Int(Date().timeIntervalSince1970)
    }

    public func send(method: String, params: Any) async throws -> Any {
        if deviceID == 0 { try await hello() }
        msgID += 1
        let obj: [String: Any] = ["id": msgID, "method": method, "params": params]
        let json = try JSONSerialization.data(withJSONObject: obj)
        let enc = try aes(json, op: CCOperation(kCCEncrypt))
        var h = Data([0x21, 0x31]); h.appendBE16(UInt16(32 + enc.count))
        h.appendBE32(0); h.appendBE32(deviceID)
        h.appendBE32(UInt32(Int(Date().timeIntervalSince1970) + stampOffset))
        let sum = md5(h + token + enc)
        let r = try await udp(h + sum + enc)
        guard r.count > 32 else { throw MiIOError.badResponse }
        let dec = try aes(r.subdata(in: 32..<r.count), op: CCOperation(kCCDecrypt))
        let clean = dec.filter { $0 != 0 }
        guard let resp = try JSONSerialization.jsonObject(with: clean) as? [String: Any] else { throw MiIOError.badResponse }
        if let e = resp["error"] { throw MiIOError.deviceError("\(e)") }
        return resp["result"] ?? NSNull()
    }

    /// MIoT get_properties，返回键为 "siid.piid"
    public func getProperties(_ ps: [(Int, Int)]) async throws -> [String: Any] {
        let params = ps.map { ["did": "\($0.0).\($0.1)", "siid": $0.0, "piid": $0.1] as [String: Any] }
        let res = try await send(method: "get_properties", params: params) as? [[String: Any]] ?? []
        var out: [String: Any] = [:]
        for r in res where (r["code"] as? Int ?? -1) == 0 { if let d = r["did"] as? String { out[d] = r["value"] } }
        return out
    }

    public func setProperty(siid: Int, piid: Int, value: Any) async throws {
        _ = try await send(method: "set_properties", params: [["did": "set", "siid": siid, "piid": piid, "value": value]])
    }

    public func action(siid: Int, aiid: Int, inputs: [Any]) async throws -> Any {
        try await send(method: "action", params: ["did": "call-\(siid)-\(aiid)", "siid": siid, "aiid": aiid, "in": inputs])
    }

    private func aes(_ input: Data, op: CCOperation) throws -> Data {
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
