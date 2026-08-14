import Foundation

enum WeixinILink {
    static let defaultBase = "https://ilinkai.weixin.qq.com"
    private static let version = "1.0.3"

    struct QRSession {
        var code: String
        var imageURL: String
    }

    struct Credentials {
        var token: String
        var botId: String
        var userId: String
        var baseUrl: String
    }

    struct Inbound {
        var userId: String
        var text: String
        var contextToken: String
        var messageId: String
    }

    enum QRStatus {
        case wait
        case scanned
        case needVerify
        case redirect(String)
        case confirmed(Credentials)
        case expired
        case blocked
        case alreadyBound
        case unknown(String)
    }

    static func createQR() async throws -> QRSession {
        let url = "\(defaultBase)/ilink/bot/get_bot_qrcode?bot_type=3"
        var json: [String: Any]
        do {
            json = try await postUnauthed(url, body: ["local_token_list": [String]()], timeout: 20)
        } catch {
            json = try await get(url, timeout: 20, headers: loginHeaders())
        }
        try throwIfFailed(json)
        let payload = unwrap(json)
        let code = string(payload["qrcode"])
        let imageURL = string(payload["qrcode_img_content"])
        guard !code.isEmpty, !imageURL.isEmpty else {
            throw ChannelError.message("微信二维码生成失败，请稍后重试")
        }
        return QRSession(code: code, imageURL: imageURL)
    }

    static func pollQR(_ code: String, baseUrl: String = defaultBase, verifyCode: String = "") async throws -> QRStatus {
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        var path = "/ilink/bot/get_qrcode_status?qrcode=\(encoded)"
        let verify = verifyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !verify.isEmpty {
            let v = verify.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verify
            path += "&verify_code=\(v)"
        }
        let root = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = root.isEmpty ? defaultBase : root
        do {
            let json = try await get("\(host)\(path)", timeout: 35, headers: loginHeaders())
            let payload = unwrap(json)
            switch string(payload["status"]).lowercased() {
            case "", "wait", "waiting":
                return .wait
            case "scaned", "scanned":
                return .scanned
            case "need_verifycode", "need_verify_code":
                return .needVerify
            case "scaned_but_redirect", "scanned_but_redirect":
                let next = string(payload["redirect_host"])
                return next.isEmpty ? .scanned : .redirect(next)
            case "expired":
                return .expired
            case "verify_code_blocked":
                return .blocked
            case "binded_redirect", "already_bound":
                return .alreadyBound
            case "confirmed":
                if let creds = credentials(from: payload), !creds.botId.isEmpty {
                    return .confirmed(creds)
                }
                throw ChannelError.message("微信已确认，但没有返回登录凭证")
            default:
                return .unknown(string(payload["status"]))
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return .wait
        }
    }

    private static func credentials(from json: [String: Any]) -> Credentials? {
        let token = firstString(json, ["bot_token", "token", "ilink_bot_token"])
        let botId = firstString(json, ["ilink_bot_id", "bot_id", "account_id"])
        guard !token.isEmpty || !botId.isEmpty else { return nil }
        var base = firstString(json, ["baseurl", "base_url", "baseUrl"])
        if base.isEmpty { base = defaultBase }
        return Credentials(
            token: token,
            botId: botId,
            userId: firstString(json, ["ilink_user_id", "user_id", "userId"]),
            baseUrl: base
        )
    }

    private static func unwrap(_ json: [String: Any]) -> [String: Any] {
        (json["data"] as? [String: Any]) ?? json
    }

    private static func firstString(_ json: [String: Any], _ keys: [String]) -> String {
        for key in keys {
            let value = string(json[key])
            if !value.isEmpty { return value }
        }
        return ""
    }

    static func getUpdates(cfg: WechatConfig) async throws -> (buf: String, messages: [Inbound], expired: Bool) {
        let json: [String: Any]
        do {
            json = try await post(cfg, path: "/ilink/bot/getupdates", body: [
                "get_updates_buf": cfg.updatesBuf,
                "base_info": ["channel_version": version],
            ], timeout: 40)
        } catch is URLError {
            return (cfg.updatesBuf, [], false)
        }
        if isExpired(json) { return (cfg.updatesBuf, [], true) }
        try throwIfFailed(json)
        let buf = string(json["get_updates_buf"])
        var messages: [Inbound] = []
        for item in (json["msgs"] as? [[String: Any]]) ?? [] {
            if let inbound = parseInbound(item) {
                messages.append(inbound)
            }
        }
        return (buf.isEmpty ? cfg.updatesBuf : buf, messages, false)
    }

    static func sendText(cfg: WechatConfig, text: String) async throws {
        let token = cfg.contextToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = cfg.peerUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !to.isEmpty else {
            throw ChannelError.message("请先在微信里发一句「你好」完成绑定")
        }
        let json = try await post(cfg, path: "/ilink/bot/sendmessage", body: [
            "msg": [
                "from_user_id": "",
                "to_user_id": to,
                "client_id": "vibe-pager:\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(8))",
                "message_type": 2,
                "message_state": 2,
                "context_token": token,
                "item_list": [[
                    "type": 1,
                    "text_item": ["text": text],
                ]],
            ],
            "base_info": ["channel_version": version],
        ], timeout: 20)
        if isExpired(json) {
            throw ChannelError.message("微信登录已过期，请重新扫码")
        }
        try throwIfFailed(json)
    }

    private static func parseInbound(_ item: [String: Any]) -> Inbound? {
        if let type = item["message_type"] as? Int, type == 2 { return nil }
        if let type = item["message_type"] as? Int64, type == 2 { return nil }
        let userId = string(item["from_user_id"])
        let context = string(item["context_token"])
        guard !userId.isEmpty, userId.contains("@im.wechat") else { return nil }
        var texts: [String] = []
        for part in (item["item_list"] as? [[String: Any]]) ?? [] {
            if let text = (part["text_item"] as? [String: Any]).map({ string($0["text"]) }), !text.isEmpty {
                texts.append(text)
            } else if let voice = part["voice_item"] as? [String: Any] {
                let spoken = string(voice["text"])
                if !spoken.isEmpty { texts.append(spoken) }
            }
        }
        let text = texts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !context.isEmpty else { return nil }
        let mid = item["message_id"]
        let messageId = (mid as? String) ?? (mid as? NSNumber).map { $0.stringValue } ?? ""
        return Inbound(userId: userId, text: text, contextToken: context, messageId: messageId)
    }

    private static func loginHeaders() -> [String: String] {
        [
            "iLink-App-ClientVersion": "1",
            "SKRouteTag": "1001",
        ]
    }

    private static func authHeaders(_ token: String) -> [String: String] {
        [
            "Content-Type": "application/json",
            "AuthorizationType": "ilink_bot_token",
            "Authorization": "Bearer \(token)",
            "X-WECHAT-UIN": randomUIN(),
            "SKRouteTag": "1001",
        ]
    }

    private static func randomUIN() -> String {
        Data(String(UInt32.random(in: 0...UInt32.max)).utf8).base64EncodedString()
    }

    private static func post(_ cfg: WechatConfig, path: String, body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        let base = cfg.baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = base.isEmpty ? defaultBase : base
        guard let url = URL(string: root + path) else {
            throw ChannelError.message("微信接口地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        for (key, value) in authHeaders(cfg.token) {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await parse(request)
    }

    private static func postUnauthed(_ urlString: String, body: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw ChannelError.message("微信接口地址无效")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in loginHeaders() {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await parse(request)
    }

    private static func get(_ urlString: String, timeout: TimeInterval, headers: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else {
            throw ChannelError.message("微信接口地址无效")
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await parse(request)
    }

    private static func parse(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ChannelError.message("微信接口 HTTP \(status): \(text.prefix(160))")
        }
        if data.isEmpty { return [:] }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    private static func isExpired(_ json: [String: Any]) -> Bool {
        retValue(json["ret"]) == -14 || retValue(json["errcode"]) == -14
    }

    private static func throwIfFailed(_ json: [String: Any]) throws {
        let ret = retValue(json["ret"])
        let err = retValue(json["errcode"])
        if (ret == nil || ret == 0) && (err == nil || err == 0) { return }
        throw ChannelError.message(string(json["errmsg"]).isEmpty ? "微信接口失败" : string(json["errmsg"]))
    }

    private static func retValue(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Int64 { return Int(n) }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) }
        return nil
    }

    private static func string(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
