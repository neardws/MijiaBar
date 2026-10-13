import Foundation

public enum CloudError: LocalizedError {
    case notLoggedIn, authExpired, http(Int), api(String), badResponse, loginTimeout, noServiceToken
    public var errorDescription: String? {
        switch self {
        case .notLoggedIn: return L("未登录小米账号", "Not logged in")
        case .authExpired: return L("登录已过期，请重新扫码", "Session expired, please scan again")
        case .http(let c): return "HTTP \(c)"
        case .api(let m): return L("小米云返回错误：", "Xiaomi cloud error: ") + m
        case .badResponse: return L("小米云响应解析失败", "Bad cloud response")
        case .loginTimeout: return L("二维码已过期，请刷新", "QR code expired")
        case .noServiceToken: return L("没有拿到 serviceToken", "No serviceToken")
        }
    }
}

public var xiaomiRegions: [(id: String, name: String)] { [
    ("cn", L("中国大陆", "Mainland China")), ("de", L("欧洲", "Europe")), ("us", L("美国", "United States")),
    ("ru", L("俄罗斯", "Russia")), ("sg", L("新加坡", "Singapore")), ("i2", L("印度", "India")),
] }

/// 小米云 API（与米家 App 相同的 RC4 加密签名接口）
public final class XiaomiCloud: Sendable {
    public let session: Session
    private let agent: String
    private let http: URLSession

    public init(session: Session) {
        self.session = session
        let r1 = String((0..<18).map { _ in Character(UnicodeScalar(UInt8.random(in: 97...122))) })
        let r2 = String((0..<13).map { _ in Character(UnicodeScalar(UInt8.random(in: 65...69))) })
        agent = "\(r1)-\(r2) APP/com.xiaomi.mihome APPV/10.5.201"
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false; c.httpCookieAcceptPolicy = .never; c.timeoutIntervalForRequest = 15
        http = URLSession(configuration: c)
    }

    static func base(_ region: String) -> String { "https://" + (region == "cn" ? "" : region + ".") + "api.io.mi.com/app" }

    static func encSig(_ path: String, _ params: [(String, String)], _ signedNonce: String) -> String {
        let s = (["POST", path] + params.map { "\($0.0)=\($0.1)" } + [signedNonce]).joined(separator: "&")
        return MiCrypto.sha1(Data(s.utf8)).base64EncodedString()
    }
    static func pct(_ s: String) -> String {
        var cs = CharacterSet.alphanumerics; cs.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: cs) ?? s
    }

    /// path 形如 "/v2/homeroom/gethome"
    public func call(_ path: String, _ data: Any) async throws -> Any {
        let dataStr = String(data: try JSONSerialization.data(withJSONObject: data), encoding: .utf8) ?? "{}"
        let nonce = MiCrypto.nonce()
        let sn = MiCrypto.signedNonce(ssecurity: session.ssecurity, nonce: nonce)
        guard let snKey = Data(base64Encoded: sn) else { throw CloudError.badResponse }
        var params: [(String, String)] = [("data", dataStr)]
        params.append(("rc4_hash__", Self.encSig(path, params, sn)))
        params = params.map { ($0.0, MiCrypto.rc4(key: snKey, Data($0.1.utf8)).base64EncodedString()) }
        params.append(("signature", Self.encSig(path, params, sn)))
        params.append(("ssecurity", session.ssecurity))
        params.append(("_nonce", nonce))
        let q = params.map { "\($0.0)=\(Self.pct($0.1))" }.joined(separator: "&")
        guard let url = URL(string: Self.base(session.region) + path + "?" + q) else { throw CloudError.badResponse }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        req.setValue(agent, forHTTPHeaderField: "User-Agent")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("PROTOCAL-HTTP2", forHTTPHeaderField: "x-xiaomi-protocal-flag-cli")
        req.setValue("ENCRYPT-RC4", forHTTPHeaderField: "MIOT-ENCRYPT-ALGORITHM")
        req.setValue("userId=\(session.userId); yetAnotherServiceToken=\(session.serviceToken); serviceToken=\(session.serviceToken); locale=zh_CN; timezone=GMT+08:00; is_daylight=0; dst_offset=0; channel=MI_APP_STORE", forHTTPHeaderField: "Cookie")
        let (body, resp) = try await http.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw CloudError.authExpired }
        guard code == 200 else { throw CloudError.http(code) }
        var obj: [String: Any]?
        let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let raw = Data(base64Encoded: text) {
            obj = try? JSONSerialization.jsonObject(with: MiCrypto.rc4(key: snKey, raw)) as? [String: Any]
        }
        if obj == nil { obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] }
        guard let obj else { throw CloudError.badResponse }
        let c = (obj["code"] as? Int) ?? 0
        if c != 0 {
            if c == 2 || c == 3 { throw CloudError.authExpired }
            throw CloudError.api("\(c) \(obj["message"] ?? "")")
        }
        return obj["result"] ?? NSNull()
    }

    public func homes() async throws -> [Home] {
        let r = try await call("/v2/homeroom/gethome", ["fg": true, "fetch_share": true, "fetch_share_dev": true, "limit": 300, "app_ver": 7]) as? [String: Any] ?? [:]
        let list = (r["homelist"] as? [[String: Any]] ?? []) + (r["share_home_list"] as? [[String: Any]] ?? [])
        return list.map { h in
            Home(id: anyString(h["id"]), name: h["name"] as? String ?? L("我的家", "Home"), ownerId: anyString(h["uid"]),
                 rooms: (h["roomlist"] as? [[String: Any]] ?? []).map {
                    Room(id: anyString($0["id"]), name: $0["name"] as? String ?? "", dids: ($0["dids"] as? [Any] ?? []).map { anyString($0) })
                 })
        }
    }

    public func devices(in home: Home) async throws -> [Device] {
        let r = try await call("/v2/home/home_device_list", [
            "home_owner": Int64(home.ownerId) ?? Int64(0), "home_id": Int64(home.id) ?? Int64(0),
            "limit": 200, "get_split_device": true, "support_smart_home": true,
        ]) as? [String: Any] ?? [:]
        let infos = r["device_info"] as? [[String: Any]] ?? []
        return infos.map { d in
            let did = anyString(d["did"])
            func nz(_ s: Any?) -> String? { let v = anyString(s); return v.isEmpty ? nil : v }
            var last: Date?
            for k in ["last_online", "lastOnline", "last_online_time"] {
                if let n = d[k] as? NSNumber, n.doubleValue > 0 {
                    let v = n.doubleValue; last = Date(timeIntervalSince1970: v > 1e11 ? v / 1000 : v); break
                }
            }
            return Device(did: did, name: d["name"] as? String ?? did, model: d["model"] as? String ?? "",
                          ip: nz(d["localip"]), token: nz(d["token"]), isOnline: d["isOnline"] as? Bool ?? true,
                          homeId: home.id, homeName: home.name,
                          roomName: home.rooms.first { $0.dids.contains(did) }?.name, lastOnline: last)
        }
    }

    public func getProps(did: String, _ ps: [(Int, Int)]) async throws -> [String: Any] {
        let r = try await call("/miotspec/prop/get", ["params": ps.map { ["did": did, "siid": $0.0, "piid": $0.1] }]) as? [[String: Any]] ?? []
        var out: [String: Any] = [:]
        for x in r where (x["code"] as? Int ?? -1) == 0 {
            out["\(anyString(x["siid"])).\(anyString(x["piid"]))"] = x["value"]
        }
        return out
    }

    public func setProp(did: String, siid: Int, piid: Int, value: Any) async throws {
        let r = try await call("/miotspec/prop/set", ["params": [["did": did, "siid": siid, "piid": piid, "value": value]]]) as? [[String: Any]] ?? []
        if let c = r.first?["code"] as? Int, c != 0 { throw CloudError.api("set code \(c)") }
    }

    public func action(did: String, siid: Int, aiid: Int, inputs: [Any]) async throws -> Any {
        try await call("/miotspec/action", ["params": ["did": did, "siid": siid, "aiid": aiid, "in": inputs]])
    }

    /// 旧版 miIO 命令透传（例如空调伴侣的 get_prop / set_power）
    public func rpc(did: String, method: String, params: Any) async throws -> Any {
        try await call("/home/rpc/\(did)", ["method": method, "params": params])
    }
}

/// 扫码登录：account.xiaomi.com/longPolling/loginUrl → 用米家 App 扫码 → 长轮询拿 ssecurity → 访问 location 拿 serviceToken
public final class QRLogin {
    public struct Ticket: Sendable { public let qrURL: URL; public let loginURL: String; public let lpURL: URL; public let timeout: TimeInterval }
    private let http: URLSession
    private let cookies: HTTPCookieStorage

    public init() {
        let c = URLSessionConfiguration.ephemeral
        cookies = c.httpCookieStorage ?? HTTPCookieStorage.shared
        c.timeoutIntervalForRequest = 30
        http = URLSession(configuration: c)
    }

    static func strip(_ d: Data) throws -> [String: Any] {
        let s = (String(data: d, encoding: .utf8) ?? "").replacingOccurrences(of: "&&&START&&&", with: "")
        guard let o = try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any] else { throw CloudError.badResponse }
        return o
    }

    public func start() async throws -> Ticket {
        let dc = Int(Date().timeIntervalSince1970 * 1000)
        let s = "https://account.xiaomi.com/longPolling/loginUrl?_qrsize=480&qs=%253Fsid%253Dxiaomiio%2526_json%253Dtrue&callback=https%3A%2F%2Fsts.api.io.mi.com%2Fsts&_hasLogo=false&sid=xiaomiio&serviceParam=&_locale=zh_CN&_dc=\(dc)"
        let (d, r) = try await http.data(from: URL(string: s)!)
        guard (r as? HTTPURLResponse)?.statusCode == 200 else { throw CloudError.http((r as? HTTPURLResponse)?.statusCode ?? 0) }
        let o = try Self.strip(d)
        guard let qr = (o["qr"] as? String).flatMap(URL.init(string:)), let lp = (o["lp"] as? String).flatMap(URL.init(string:)) else {
            throw CloudError.api(o["desc"] as? String ?? "no qr")
        }
        return Ticket(qrURL: qr, loginURL: o["loginUrl"] as? String ?? "", lpURL: lp, timeout: (o["timeout"] as? NSNumber)?.doubleValue ?? 300)
    }

    public func image(_ t: Ticket) async throws -> Data { try await http.data(from: t.qrURL).0 }

    /// 阻塞等待用户在手机上确认，返回会话
    public func wait(_ t: Ticket, region: String) async throws -> Session {
        let start = Date()
        while true {
            try Task.checkCancellation()
            if Date().timeIntervalSince(start) > t.timeout { throw CloudError.loginTimeout }
            var req = URLRequest(url: t.lpURL); req.timeoutInterval = 20
            let d: Data, r: URLResponse
            do { (d, r) = try await http.data(for: req) }
            catch let e as URLError where e.code == .timedOut { continue }
            guard (r as? HTTPURLResponse)?.statusCode == 200 else { try await Task.sleep(nanoseconds: 1_000_000_000); continue }
            let o = try Self.strip(d)
            guard let ssecurity = o["ssecurity"] as? String, let loc = (o["location"] as? String).flatMap(URL.init(string:)) else {
                try await Task.sleep(nanoseconds: 1_000_000_000); continue
            }
            let userId = anyString(o["userId"])
            _ = try await http.data(from: loc)
            guard let token = cookies.cookies?.first(where: { $0.name == "serviceToken" })?.value else { throw CloudError.noServiceToken }
            return Session(userId: userId, ssecurity: ssecurity, serviceToken: token, region: region, cUserId: o["cUserId"] as? String)
        }
    }
}
