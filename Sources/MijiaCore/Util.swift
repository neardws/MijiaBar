import Foundation
import CryptoKit

public let isChinese: Bool = (Locale.preferredLanguages.first ?? "en").hasPrefix("zh")
/// 简易本地化：中文系统显示中文，其它语言回退英文
public func L(_ zh: String, _ en: String) -> String { isChinese ? zh : en }

public func anyString(_ a: Any?) -> String {
    if let s = a as? String { return s }
    if let n = a as? NSNumber { return n.stringValue }
    return ""
}

public enum MijiaError: LocalizedError {
    case unknownProperty(String), deviceNotFound(String), noSpec(String), denied(String), notWritable(String)
    public var errorDescription: String? {
        switch self {
        case .unknownProperty(let p): return L("未知属性/动作：", "Unknown property/action: ") + p
        case .deviceNotFound(let d): return L("找不到设备：", "Device not found: ") + d
        case .noSpec(let m): return L("没有找到该型号的 MIoT 规格：", "No MIoT spec for model: ") + m
        case .denied(let r): return L("Agent 权限不允许：", "Denied by agent policy: ") + r
        case .notWritable(let p): return L("属性不可写：", "Property not writable: ") + p
        }
    }
}

enum MiCrypto {
    static func rc4(key: Data, _ input: Data) -> Data {
        var s = [UInt8](0...255); let k = [UInt8](key); var j = 0
        for i in 0..<256 { j = (j + Int(s[i]) + Int(k[i % k.count])) & 0xff; s.swapAt(i, j) }
        var i = 0; j = 0
        var out = [UInt8](); out.reserveCapacity(input.count)
        for n in 0..<(1024 + input.count) {
            i = (i + 1) & 0xff; j = (j + Int(s[i])) & 0xff; s.swapAt(i, j)
            let ks = s[(Int(s[i]) + Int(s[j])) & 0xff]
            if n >= 1024 { out.append(input[input.startIndex + n - 1024] ^ ks) }
        }
        return Data(out)
    }
    static func sha256(_ d: Data) -> Data { Data(SHA256.hash(data: d)) }
    static func sha1(_ d: Data) -> Data { Data(Insecure.SHA1.hash(data: d)) }
    static func nonce() -> String {
        var b = Data((0..<8).map { _ in UInt8.random(in: 0...255) })
        b.appendBE32(UInt32(Int(Date().timeIntervalSince1970 * 1000) / 60000))
        return b.base64EncodedString()
    }
    static func signedNonce(ssecurity: String, nonce: String) -> String {
        sha256((Data(base64Encoded: ssecurity) ?? Data()) + (Data(base64Encoded: nonce) ?? Data())).base64EncodedString()
    }
}
