import Foundation
import CryptoKit
import os

/// 界面语言。简体为原文，繁体（台湾用语）、其余语言见 Translations.swift。
public enum AppLang: String, CaseIterable, Codable, Sendable {
    case zhHans = "zh-Hans", zhHant = "zh-Hant", en, de, fr, es, it, ru, ja
    public var nativeName: String {
        switch self {
        case .zhHans: return "简体中文"; case .zhHant: return "繁體中文"; case .en: return "English"
        case .de: return "Deutsch"; case .fr: return "Français"; case .es: return "Español"
        case .it: return "Italiano"; case .ru: return "Русский"; case .ja: return "日本語"
        }
    }
    /// 是否有完整翻译（否则回退英文）
    public var isComplete: Bool { true }
    /// 各小米服务器地区建议的语言，第一个为默认
    public static func suggested(forRegion r: String) -> [AppLang] {
        switch r {
        case "cn": return [.zhHans, .zhHant, .en]
        case "sg": return [.en, .zhHant, .zhHans]
        case "de": return [.en, .de, .fr, .es, .it]
        case "ru": return [.ru, .en]
        default: return [.en, .zhHans, .zhHant]   // us, i2
        }
    }
    static func system() -> AppLang {
        let p = Locale.preferredLanguages.first ?? "en"
        if p.hasPrefix("zh") { return (p.contains("Hant") || p.contains("TW") || p.contains("HK") || p.contains("MO")) ? .zhHant : .zhHans }
        return AppLang(rawValue: String(p.prefix(2))) ?? .en
    }
}

/// 当前语言：用户在设置中选择的 > 系统语言（CLI 与 App 共用 UserDefaults 键 MijiaBarLang）
public var currentLang: AppLang {
    get { langState.withLock { $0.lang } }
    set { langState.withLock { $0.lang = newValue } }
}
public var isChinese: Bool { currentLang == .zhHans || currentLang == .zhHant }
/// 语言和繁体转换缓存可能在任意线程读写，用锁保护
private let langState = OSAllocatedUnfairLock(initialState: (
    lang: ProcessInfo.processInfo.environment["MIJIABAR_LANG"].flatMap(AppLang.init(rawValue:)) ?? UserDefaults.standard.string(forKey: "MijiaBarLang").flatMap(AppLang.init(rawValue:)) ?? AppLang.system(),
    hant: [String: String]()))
/// 简易本地化：中文系统显示中文，其它语言回退英文
public func L(_ zh: String, _ en: String) -> String {
    let (lang, cached) = langState.withLock { ($0.lang, $0.hant[zh]) }
    switch lang {
    case .zhHans: return zh
    case .zhHant:
        // 台湾用语：优先人工校对过的 i18n/zh-Hant.tsv，缺失时才自动转换
        if let t = hantTable[zh] { return t }
        if let cached { return cached }
        let t = zh.applyingTransform(StringTransform("Hans-Hant"), reverse: false) ?? zh
        langState.withLock { $0.hant[zh] = t }; return t
    default: return tr(en, lang) ?? en
    }
}

/// 带参数的本地化：模板中的 %@ 依次替换为参数
public func LF(_ zh: String, _ en: String, _ args: String...) -> String {
    var s = L(zh, en)
    for a in args { if let r = s.range(of: "%@") { s.replaceSubrange(r, with: a) } }
    return s
}

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
