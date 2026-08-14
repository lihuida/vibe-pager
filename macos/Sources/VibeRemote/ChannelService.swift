import CryptoKit
import Foundation

enum ChannelService {
    static func dispatchAll(config: LaneConfig, event: OutboundEvent) async -> [SendOutcome] {
        switch config.activeChannel {
        case "telegram":
            guard config.telegram.isReady else { return [] }
            return [await sendTelegram(token: config.telegram.botToken, chatId: config.telegram.chatId, event: event)]
        case "feishu":
            guard config.feishu.isReady else { return [] }
            return [await sendFeishu(config.feishu, event: event)]
        case "dingtalk":
            guard config.dingtalk.isReady else { return [] }
            return [await sendDingTalk(config.dingtalk, event: event)]
        case "wechat":
            guard config.wechat.isReady else { return [] }
            return [await sendWeChat(config.wechat, event: event)]
        default:
            return []
        }
    }

    static func sendTest(config: LaneConfig, channel: String) async throws -> SendOutcome {
        let event = OutboundEvent(source: "Vibe Pager", summary: "这是一条测试消息。远程通讯已就绪。")
        switch channel {
        case "telegram":
            guard config.telegram.isReady else { throw ChannelError.message("请先完成 Telegram 绑定") }
            return await sendTelegram(token: config.telegram.botToken, chatId: config.telegram.chatId, event: event)
        case "feishu":
            guard config.feishu.isReady else { throw ChannelError.message("请先完成飞书单聊绑定") }
            return await sendFeishu(config.feishu, event: event)
        case "dingtalk":
            guard config.dingtalk.isReady else { throw ChannelError.message("请先完成钉钉单聊绑定") }
            return await sendDingTalk(config.dingtalk, event: event)
        case "wechat":
            guard config.wechat.isReady else { throw ChannelError.message("请先完成微信通道配置") }
            return await sendWeChat(config.wechat, event: event)
        default:
            throw ChannelError.message("未知通道")
        }
    }

    static func telegramGetMe(token: String) async throws -> String {
        let url = URL(string: "https://api.telegram.org/bot\(token)/getMe")!
        let json = try await getJSON(url)
        guard (json["ok"] as? Bool) == true else {
            throw ChannelError.message((json["description"] as? String) ?? "Token 无效")
        }
        let result = json["result"] as? [String: Any]
        return (result?["username"] as? String) ?? ""
    }

    static func telegramPollInbox(token: String, offset: Int64) async throws -> (Int64, [InboundMessage]) {
        let url = URL(string: "https://api.telegram.org/bot\(token)/getUpdates?timeout=20&offset=\(offset)")!
        let json = try await getJSON(url, timeout: 28)
        guard (json["ok"] as? Bool) == true else {
            throw ChannelError.message((json["description"] as? String) ?? "getUpdates 失败")
        }
        var next = offset
        var messages: [InboundMessage] = []
        for update in (json["result"] as? [[String: Any]]) ?? [] {
            if let id = jsonInt(update["update_id"]) {
                next = max(next, id + 1)
            }
            guard let message = update["message"] as? [String: Any],
                  let chat = message["chat"] as? [String: Any],
                  let chatId = jsonInt(chat["id"]) else { continue }
            let text = ((message["text"] as? String) ?? (message["caption"] as? String) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var photoFileId: String?
            if let photos = message["photo"] as? [[String: Any]] {
                photoFileId = photos.last?["file_id"] as? String
            }
            if let doc = message["document"] as? [String: Any],
               ((doc["mime_type"] as? String) ?? "").hasPrefix("image/") {
                photoFileId = doc["file_id"] as? String
            }
            if !text.isEmpty || photoFileId != nil {
                var replyToId = ""
                if let reply = message["reply_to_message"] as? [String: Any], let id = jsonInt(reply["message_id"]) {
                    replyToId = String(id)
                }
                messages.append(InboundMessage(chatId: String(chatId), text: text, photoFileId: photoFileId, replyToId: replyToId))
            }
        }
        return (next, messages)
    }

    static func telegramDownloadFile(token: String, fileId: String) async -> Data? {
        do {
            let json = try await getJSON(URL(string: "https://api.telegram.org/bot\(token)/getFile?file_id=\(fileId)")!)
            guard let result = json["result"] as? [String: Any],
                  let path = result["file_path"] as? String,
                  let url = URL(string: "https://api.telegram.org/file/bot\(token)/\(path)") else { return nil }
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status < 400, !data.isEmpty else { return nil }
            return ImagePrep.jpeg(data)
        } catch {
            return nil
        }
    }

    static func telegramAck(token: String, chatId: String, text: String, replyTo: String = "") async {
        let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage")!
        var body: [String: Any] = ["chat_id": chatId, "text": text]
        if let id = Int64(replyTo), id > 0 {
            body["reply_to_message_id"] = id
        }
        _ = try? await postJSON(url, body: body)
    }

    static func replyOnActive(config: LaneConfig, text: String, replyTo: String = "") async {
        let event = OutboundEvent(source: "", summary: text, title: "", replyTo: replyTo)
        switch config.activeChannel {
        case "telegram":
            guard config.telegram.isReady else { return }
            await telegramAck(token: config.telegram.botToken, chatId: config.telegram.chatId, text: text, replyTo: replyTo)
        case "feishu":
            guard config.feishu.isReady else { return }
            _ = await sendFeishu(config.feishu, event: event)
        case "dingtalk":
            guard config.dingtalk.isReady else { return }
            _ = await sendDingTalk(config.dingtalk, event: event)
        case "wechat":
            guard config.wechat.isReady else { return }
            _ = await sendWeChat(config.wechat, event: event)
        default:
            break
        }
    }

    static func createWxPusherQR(token: String) async throws -> (code: String, imageURL: String) {
        let extra = "vibe-\(Int(Date().timeIntervalSince1970))"
        let json = try await postJSON(URL(string: "https://wxpusher.zjiecode.com/api/fun/create/qrcode")!, body: [
            "appToken": token,
            "extra": extra,
            "validTime": 1800,
        ])
        let data = json["data"] as? [String: Any] ?? [:]
        let code = (data["code"] as? String) ?? ""
        let imageURL = (data["url"] as? String) ?? (data["shortUrl"] as? String) ?? ""
        guard !code.isEmpty else { throw ChannelError.message("生成二维码失败，请检查 AT_ Token") }
        return (code, imageURL)
    }

    static func wxPusherScanUID(code: String) async -> String? {
        guard let url = URL(string: "https://wxpusher.zjiecode.com/api/fun/scan-qrcode-uid?code=\(code)") else { return nil }
        guard let json = try? await getJSON(url, timeout: 15) else { return nil }
        if let uid = json["data"] as? String, uid.hasPrefix("UID_") { return uid }
        if let data = json["data"] as? [String: Any], let uid = data["uid"] as? String, !uid.isEmpty {
            return uid
        }
        return nil
    }

    static func downloadImage(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        return try? await URLSession.shared.data(from: url).0
    }

    static func telegramPollChatId(token: String, offset: Int64) async throws -> (Int64, String?) {
        let (next, messages) = try await telegramPollInbox(token: token, offset: offset)
        return (next, messages.last?.chatId)
    }

    private static func sendTelegram(token: String, chatId: String, event: OutboundEvent) async -> SendOutcome {
        do {
            let json: [String: Any]
            if let image = event.image {
                let caption = truncate(event.composed, 1000)
                json = try await postTelegramPhoto(token: token, chatId: chatId, image: image, caption: caption, replyTo: event.replyTo)
            } else {
                let url = URL(string: "https://api.telegram.org/bot\(token)/sendMessage")!
                var body: [String: Any] = ["chat_id": chatId, "text": event.composed]
                if let id = Int64(event.replyTo), id > 0 {
                    body["reply_to_message_id"] = id
                }
                json = try await postJSON(url, body: body)
            }
            return SendOutcome(channel: "telegram", ok: true, message: "已发送到 Telegram", messageId: telegramMessageId(json))
        } catch {
            return SendOutcome(channel: "telegram", ok: false, message: error.localizedDescription)
        }
    }

    private static func sendFeishu(_ cfg: WebhookConfig, event: OutboundEvent) async -> SendOutcome {
        do {
            let token = try await feishuTenantToken(appId: cfg.appId, appSecret: cfg.appSecret)
            let content = jsonString(["text": event.composed])
            let headers = ["Authorization": "Bearer \(token)"]
            var json: [String: Any] = [:]
            var sent = false
            if !event.replyTo.isEmpty {
                let encoded = event.replyTo.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? event.replyTo
                if let url = URL(string: "https://open.feishu.cn/open-apis/im/v1/messages/\(encoded)/reply") {
                    do {
                        json = try await postJSON(url, body: [
                            "content": content,
                            "msg_type": "text",
                            "reply_in_thread": false,
                        ], headers: headers)
                        sent = true
                    } catch {
                        sent = false
                    }
                }
            }
            if !sent {
                var comps = URLComponents(string: "https://open.feishu.cn/open-apis/im/v1/messages")!
                comps.queryItems = [URLQueryItem(name: "receive_id_type", value: "chat_id")]
                guard let url = comps.url else { throw ChannelError.message("飞书发送地址无效") }
                json = try await postJSON(url, body: [
                    "receive_id": cfg.chatId,
                    "msg_type": "text",
                    "content": content,
                ], headers: headers)
            }
            return SendOutcome(channel: "feishu", ok: true, message: "已发送到飞书", messageId: feishuMessageId(json))
        } catch {
            return SendOutcome(channel: "feishu", ok: false, message: error.localizedDescription)
        }
    }

    private static func sendDingTalk(_ cfg: WebhookConfig, event: OutboundEvent) async -> SendOutcome {
        do {
            let token = try await dingTalkAccessToken(appKey: cfg.appId, appSecret: cfg.appSecret)
            let userId = cfg.userId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !userId.isEmpty else { throw ChannelError.message("还没有绑定钉钉单聊") }
            _ = try await postJSON(
                URL(string: "https://api.dingtalk.com/v1.0/robot/oToMessages/batchSend")!,
                body: [
                    "robotCode": cfg.appId.trimmingCharacters(in: .whitespacesAndNewlines),
                    "userIds": [userId],
                    "msgKey": "sampleText",
                    "msgParam": jsonString(["content": event.composed]),
                ],
                headers: ["x-acs-dingtalk-access-token": token]
            )
            return SendOutcome(channel: "dingtalk", ok: true, message: "已发送到钉钉")
        } catch {
            return SendOutcome(channel: "dingtalk", ok: false, message: error.localizedDescription)
        }
    }

    private static func feishuTenantToken(appId: String, appSecret: String) async throws -> String {
        let json = try await postJSON(
            URL(string: "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal")!,
            body: ["app_id": appId, "app_secret": appSecret]
        )
        if let token = json["tenant_access_token"] as? String, !token.isEmpty {
            return token
        }
        throw ChannelError.message((json["msg"] as? String) ?? "飞书 App ID / Secret 无效")
    }

    private static func dingTalkAccessToken(appKey: String, appSecret: String) async throws -> String {
        let json = try await postJSON(
            URL(string: "https://api.dingtalk.com/v1.0/oauth2/accessToken")!,
            body: ["appKey": appKey, "appSecret": appSecret]
        )
        if let token = json["accessToken"] as? String, !token.isEmpty {
            return token
        }
        throw ChannelError.message((json["message"] as? String) ?? "钉钉 Client ID / Secret 无效")
    }

    private static func sendWeChat(_ cfg: WechatConfig, event: OutboundEvent) async -> SendOutcome {
        do {
            switch cfg.provider {
            case "pushplus":
                var content = event.composed
                let template = "html"
                if let image = event.image {
                    content = "<p>\(htmlEscape(event.composed))</p><p><img src=\"data:image/jpeg;base64,\(image.base64EncodedString())\" /></p>"
                }
                _ = try await postJSON(URL(string: "https://www.pushplus.plus/send")!, body: [
                    "token": cfg.token.trimmingCharacters(in: .whitespaces),
                    "title": "Vibe Pager",
                    "template": template,
                    "content": content,
                ])
            case "wecom":
                _ = try await postJSON(URL(string: cfg.token.trimmingCharacters(in: .whitespaces))!, body: [
                    "msgtype": "text",
                    "text": ["content": event.composed],
                ])
                if let image = event.image {
                    let md5 = md5Hex(image)
                    _ = try await postJSON(URL(string: cfg.token.trimmingCharacters(in: .whitespaces))!, body: [
                        "msgtype": "image",
                        "image": [
                            "base64": image.base64EncodedString(),
                            "md5": md5,
                        ],
                    ])
                }
            case "ilink":
                try await WeixinILink.sendText(cfg: cfg, text: event.composed)
            default:
                if cfg.isILink {
                    try await WeixinILink.sendText(cfg: cfg, text: event.composed)
                } else {
                    var content = event.composed
                    var contentType = 1
                    if let image = event.image {
                        content = "<p>\(htmlEscape(event.composed))</p><p><img src=\"data:image/jpeg;base64,\(image.base64EncodedString())\" /></p>"
                        contentType = 2
                    }
                    var body: [String: Any] = [
                        "appToken": cfg.token.trimmingCharacters(in: .whitespaces),
                        "content": content,
                        "summary": "Vibe Pager",
                        "contentType": contentType,
                    ]
                    if !cfg.uid.trimmingCharacters(in: .whitespaces).isEmpty {
                        body["uids"] = [cfg.uid.trimmingCharacters(in: .whitespaces)]
                    }
                    _ = try await postJSON(URL(string: "https://wxpusher.zjiecode.com/api/send/message")!, body: body)
                }
            }
            return SendOutcome(channel: "wechat", ok: true, message: "已发送到微信通道")
        } catch {
            return SendOutcome(channel: "wechat", ok: false, message: error.localizedDescription)
        }
    }

    static func extractConversation(_ body: [String: Any]) -> String {
        for key in ["conversation_id", "conversationId", "composer_id", "composerId", "session_id", "thread_id"] {
            if let text = body[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    static func extractCwd(_ body: [String: Any]) -> String {
        if let roots = body["workspace_roots"] as? [String], let first = roots.first {
            let trimmed = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        for key in ["cwd", "workspace_path", "workspacePath", "rootPath", "project_path"] {
            if let text = body[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return ""
    }

    static func projectName(_ body: [String: Any]) -> String {
        let cwd = extractCwd(body)
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        if name.isEmpty || name == ".cursor" { return "" }
        return name
    }

    static func topicName(_ body: [String: Any]) -> String {
        if let text = body["conversation_title"] as? String {
            let clipped = clipTitle(text)
            if !clipped.isEmpty { return clipped }
        }
        let name = cursorConversationName(id: extractConversation(body))
        return clipTitle(name)
    }

    static func cursorConversationName(id: String) -> String {
        let composerId = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !composerId.isEmpty else { return "" }
        let db = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        guard FileManager.default.fileExists(atPath: db.path) else { return "" }
        let escaped = composerId.replacingOccurrences(of: "'", with: "''")
        let queries = [
            "SELECT json_extract(value,'$.name') FROM composerHeaders WHERE composerId='\(escaped)' LIMIT 1",
            "SELECT json_extract(value,'$.name') FROM cursorDiskKV WHERE key='composerData:\(escaped)' LIMIT 1",
        ]
        for sql in queries {
            if let name = sqliteText(db: db.path, sql: sql), !name.isEmpty, name != "null" {
                return name
            }
        }
        return ""
    }

    private static func jsonField(_ raw: String, _ key: String) -> String? {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = obj[key] as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func sqliteText(db: String, sql: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "file:\(db)?mode=ro", sql]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    static func cleanReply(_ text: String) -> String {
        var result = text
        let patterns = [
            #"<thinking>[\s\S]*?</thinking>"#,
            #"<think>[\s\S]*?</think>"#,
            #"<thought>[\s\S]*?</thought>"#,
            #"```thinking[\s\S]*?```"#,
            #"<tool_call>[\s\S]*?</tool_call>"#,
            #"<tool_use>[\s\S]*?</tool_use>"#,
            #"<tool_result>[\s\S]*?</tool_result>"#,
            #"<function_calls>[\s\S]*?</function_calls>"#,
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return result
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clipTitle(_ text: String) -> String {
        let first = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !first.isEmpty else { return "" }
        if first.count <= 48 { return first }
        return String(first.prefix(48)) + "…"
    }

    static func extractAssistantText(_ body: [String: Any]) -> String {
        for key in ["last_assistant_message", "text", "summary", "content", "output"] {
            if let text = body[key] as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        if let message = body["message"] as? String {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ""
    }

    static func summarize(source: String, body: [String: Any]) -> String {
        let text = cleanReply(extractAssistantText(body))
        if !text.isEmpty { return truncate(text, 8000) }
        return ""
    }

    private static func jsonString(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func feishuMessageId(_ json: [String: Any]) -> String {
        ((json["data"] as? [String: Any])?["message_id"] as? String) ?? ""
    }

    private static func telegramMessageId(_ json: [String: Any]) -> String {
        if let id = jsonInt((json["result"] as? [String: Any])?["message_id"]) {
            return String(id)
        }
        return ""
    }

    private static func postJSON(_ url: URL, body: [String: Any], headers: [String: String] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await parseResponse(request)
    }

    private static func getJSON(_ url: URL, timeout: TimeInterval = 25) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try await parseResponse(request)
    }

    private static func postTelegramPhoto(token: String, chatId: String, image: Data, caption: String, replyTo: String) async throws -> [String: Any] {
        let boundary = "VibeBoundary\(Int(Date().timeIntervalSince1970))"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }
        field("chat_id", chatId)
        field("caption", caption)
        if let id = Int64(replyTo), id > 0 {
            field("reply_to_message_id", String(id))
        }
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"shot.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(image)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "https://api.telegram.org/bot\(token)/sendPhoto")!)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30
        request.httpBody = body
        return try await parseResponse(request)
    }

    private static func htmlEscape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static func md5Hex(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func parseResponse(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw ChannelError.message("HTTP \(status): \(truncate(text, 180))")
        }
        if data.isEmpty { return ["ok": true] }
        let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? ["raw": String(data: data, encoding: .utf8) ?? ""]
        if (raw["ok"] as? Bool) == false {
            throw ChannelError.message((raw["description"] as? String) ?? (raw["msg"] as? String) ?? "发送失败")
        }
        if let code = jsonInt(raw["code"]), code != 0, code != 200, code != 1000 {
            throw ChannelError.message((raw["msg"] as? String) ?? (raw["errmsg"] as? String) ?? "发送失败")
        }
        if let code = jsonInt(raw["StatusCode"]), code != 0 {
            throw ChannelError.message((raw["StatusMessage"] as? String) ?? "发送失败")
        }
        return raw
    }

    private static func jsonInt(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        if let s = value as? String { return Int64(s) }
        return nil
    }

    private static func truncate(_ text: String, _ max: Int) -> String {
        if text.count <= max { return text }
        return String(text.prefix(max)) + "…"
    }
}

enum ChannelError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case let .message(text) = self { return text }
        return nil
    }
}
