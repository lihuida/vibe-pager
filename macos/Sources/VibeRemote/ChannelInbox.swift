import Foundation

enum ChannelInbox {
    static func runFeishu(appId: String, appSecret: String, onEvent: @escaping (ChatInbound) -> Void) async {
        await FeishuWS.run(appId: appId, appSecret: appSecret, onEvent: onEvent)
    }

    static func runDingTalk(clientId: String, clientSecret: String, onEvent: @escaping (ChatInbound) -> Void) async {
        while !Task.isCancelled {
            do {
                try await dingTalkSession(clientId: clientId, clientSecret: clientSecret, onEvent: onEvent)
            } catch {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    static func runWeCom(botId: String, secret: String, onText: @escaping (String) -> Void) async {
        while !Task.isCancelled {
            do {
                try await weComSession(botId: botId, secret: secret, onText: onText)
            } catch {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    // MARK: - DingTalk Stream

    private static func dingTalkSession(clientId: String, clientSecret: String, onEvent: @escaping (ChatInbound) -> Void) async throws {
        let opened = try await post(
            URL(string: "https://api.dingtalk.com/v1.0/gateway/connections/open")!,
            body: [
                "clientId": clientId,
                "clientSecret": clientSecret,
                "subscriptions": [["type": "CALLBACK", "topic": "/v1.0/im/bot/messages/get"]],
                "ua": "vibe-remote/0.1",
                "localIp": "127.0.0.1",
            ]
        )
        guard let endpoint = opened["endpoint"] as? String,
              let ticket = opened["ticket"] as? String,
              var comps = URLComponents(string: endpoint) else {
            throw ChannelError.message("钉钉 Stream 连接失败")
        }
        comps.queryItems = [URLQueryItem(name: "ticket", value: ticket)]
        guard let url = comps.url else { throw ChannelError.message("钉钉 Stream 地址无效") }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }
        while !Task.isCancelled {
            let message = try await receive(task)
            guard let json = jsonObject(message) else { continue }
            let type = json["type"] as? String ?? ""
            let headers = json["headers"] as? [String: Any] ?? [:]
            if type == "CALLBACK" {
                if let inbound = dingTalkInbound(json["data"]), inbound.isP2P, !inbound.text.isEmpty {
                    onEvent(inbound)
                }
                try? await sendJSON(task, [
                    "code": 200,
                    "headers": [
                        "messageId": headers["messageId"] ?? "",
                        "contentType": "application/json",
                    ],
                    "message": "OK",
                    "data": "{}",
                ])
            }
        }
    }

    private static func dingTalkInbound(_ data: Any?) -> ChatInbound? {
        var dict: [String: Any]?
        if let parsed = data as? [String: Any] {
            dict = parsed
        } else if let raw = data as? String,
                  let parsed = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any] {
            dict = parsed
        }
        guard let dict else { return nil }
        var text = ""
        if let content = dict["text"] as? [String: Any] {
            text = (content["content"] as? String) ?? ""
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let type = stringValue(dict["conversationType"])
        let userId = (dict["senderStaffId"] as? String)
            ?? (dict["senderId"] as? String)
            ?? ""
        let chatId = (dict["conversationId"] as? String) ?? ""
        return ChatInbound(
            chatId: chatId,
            userId: userId,
            text: text,
            isP2P: type == "1" || type.lowercased() == "private"
        )
    }

    private static func stringValue(_ value: Any?) -> String {
        if let s = value as? String { return s }
        if let n = value as? Int { return String(n) }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    // MARK: - WeCom smart robot

    private static func weComSession(botId: String, secret: String, onText: @escaping (String) -> Void) async throws {
        guard let url = URL(string: "wss://openws.work.weixin.qq.com") else {
            throw ChannelError.message("企业微信地址无效")
        }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }
        let reqId = UUID().uuidString
        try await sendJSON(task, [
            "cmd": "aibot_subscribe",
            "headers": ["req_id": reqId],
            "body": ["bot_id": botId, "secret": secret],
        ])
        while !Task.isCancelled {
            let message = try await receive(task)
            guard let json = jsonObject(message) else { continue }
            let cmd = json["cmd"] as? String ?? ""
            if cmd == "aibot_msg_callback" {
                let headers = json["headers"] as? [String: Any] ?? [:]
                let body = json["body"] as? [String: Any] ?? [:]
                let callbackId = (headers["req_id"] as? String) ?? UUID().uuidString
                var text = ""
                if let t = body["text"] as? [String: Any] {
                    text = (t["content"] as? String) ?? ""
                }
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    onText(text)
                    try? await sendJSON(task, [
                        "cmd": "aibot_respond_msg",
                        "headers": ["req_id": callbackId],
                        "body": [
                            "msgtype": "stream",
                            "stream": [
                                "id": UUID().uuidString,
                                "finish": true,
                                "content": "已发给本机 Cursor / Codex",
                            ],
                        ],
                    ])
                }
            }
        }
    }

    private static func post(_ url: URL, body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status >= 400 {
            throw ChannelError.message((json["message"] as? String) ?? "HTTP \(status)")
        }
        return json
    }

    private static func receive(_ task: URLSessionWebSocketTask) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            task.receive { result in
                switch result {
                case let .success(.string(text)):
                    cont.resume(returning: text)
                case let .success(.data(data)):
                    cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
                case let .failure(error):
                    cont.resume(throwing: error)
                @unknown default:
                    cont.resume(returning: "")
                }
            }
        }
    }

    private static func sendJSON(_ task: URLSessionWebSocketTask, _ body: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: body)
        let text = String(data: data, encoding: .utf8) ?? "{}"
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.send(.string(text)) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    private static func jsonObject(_ text: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]
    }
}
