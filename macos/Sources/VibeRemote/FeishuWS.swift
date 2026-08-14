import Foundation

struct ChatInbound {
    var chatId: String
    var userId: String
    var text: String
    var isP2P: Bool
    var refId: String = ""
}

enum FeishuWS {
    static func run(appId: String, appSecret: String, onEvent: @escaping (ChatInbound) -> Void) async {
        while !Task.isCancelled {
            do {
                try await session(appId: appId, appSecret: appSecret, onEvent: onEvent)
            } catch {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
            }
        }
    }

    private static func session(appId: String, appSecret: String, onEvent: @escaping (ChatInbound) -> Void) async throws {
        let opened = try await post(
            URL(string: "https://open.feishu.cn/callback/ws/endpoint")!,
            body: ["AppID": appId, "AppSecret": appSecret],
            headers: ["locale": "zh"]
        )
        let code = (opened["code"] as? Int) ?? -1
        guard code == 0 else {
            throw ChannelError.message((opened["msg"] as? String) ?? "飞书长连接握手失败")
        }
        let data = opened["data"] as? [String: Any] ?? [:]
        guard let urlString = data["URL"] as? String, let url = URL(string: urlString) else {
            throw ChannelError.message("飞书长连接地址无效")
        }
        let serviceId = serviceId(from: urlString)
        let pingSecs = max(((data["ClientConfig"] as? [String: Any])?["PingInterval"] as? Int) ?? 120, 10)

        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        defer { task.cancel(with: .goingAway, reason: nil) }

        let socket = SocketBox(task: task)
        let seq = SeqBox()
        try await socket.send(PBFrame(seqId: seq.next(), logId: 0, service: serviceId, method: 0, headers: [("type", "ping")]).encode())

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                while !Task.isCancelled {
                    try await Task.sleep(nanoseconds: UInt64(pingSecs) * 1_000_000_000)
                    try await socket.send(PBFrame(seqId: seq.next(), logId: 0, service: serviceId, method: 0, headers: [("type", "ping")]).encode())
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    let raw = try await socket.receive()
                    guard let frame = PBFrame.decode(raw) else { continue }
                    if frame.method == 0 { continue }
                    var ack = frame
                    ack.payload = Data(#"{"code":200,"headers":{},"data":[]}"#.utf8)
                    ack.headers.append(("biz_rt", "0"))
                    try? await socket.send(ack.encode())
                    if frame.header("type") != "event" { continue }
                    if let inbound = parseEvent(frame.payload), inbound.isP2P, !inbound.text.isEmpty {
                        onEvent(inbound)
                    }
                }
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    private static func parseEvent(_ payload: Data?) -> ChatInbound? {
        guard let payload,
              let json = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        let header = json["header"] as? [String: Any] ?? [:]
        let eventType = (header["event_type"] as? String) ?? ""
        guard eventType == "im.message.receive_v1" else { return nil }
        let event = json["event"] as? [String: Any] ?? [:]
        let sender = event["sender"] as? [String: Any] ?? [:]
        let senderType = (sender["sender_type"] as? String) ?? ""
        if senderType == "app" || senderType == "bot" { return nil }
        let message = event["message"] as? [String: Any] ?? [:]
        let chatType = (message["chat_type"] as? String) ?? ""
        let chatId = (message["chat_id"] as? String) ?? ""
        let msgType = (message["message_type"] as? String) ?? (message["msg_type"] as? String) ?? ""
        let content = (message["content"] as? String) ?? ""
        let text = extractText(content, type: msgType)
        let senderId = ((sender["sender_id"] as? [String: Any])?["open_id"] as? String) ?? ""
        let rootId = (message["root_id"] as? String) ?? ""
        let parentId = (message["parent_id"] as? String) ?? ""
        let threadId = (message["thread_id"] as? String) ?? ""
        let messageId = (message["message_id"] as? String) ?? ""
        let refId = [rootId, parentId, threadId, messageId].first(where: { !$0.isEmpty }) ?? ""
        return ChatInbound(
            chatId: chatId,
            userId: senderId,
            text: text,
            isP2P: chatType == "p2p",
            refId: refId
        )
    }

    private static func extractText(_ content: String, type: String) -> String {
        guard let parsed = try? JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any] else {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let text = parsed["text"] as? String {
            let plain = stripAtTags(text)
            if !plain.isEmpty { return plain }
        }
        if type == "post" || parsed["content"] is [Any] {
            return flattenPost(parsed)
        }
        return ""
    }

    private static func stripAtTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"<at [^>]*>[\s\S]*?</at>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"@_user_\d+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flattenPost(_ parsed: [String: Any]) -> String {
        var parts: [String] = []
        if let title = parsed["title"] as? String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { parts.append(trimmed) }
        }
        let rows = parsed["content"] as? [Any] ?? []
        for row in rows {
            guard let items = row as? [Any] else { continue }
            var line: [String] = []
            for item in items {
                guard let dict = item as? [String: Any] else { continue }
                let tag = (dict["tag"] as? String) ?? ""
                if tag == "at" { continue }
                if let text = dict["text"] as? String, !text.isEmpty {
                    line.append(text)
                }
            }
            let joined = line.joined().trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { parts.append(joined) }
        }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func serviceId(from url: String) -> Int32 {
        guard let qs = URLComponents(string: url)?.queryItems else { return 0 }
        if let value = qs.first(where: { $0.name == "service_id" })?.value, let n = Int32(value) {
            return n
        }
        return 0
    }

    private static func post(_ url: URL, body: [String: Any], headers: [String: String] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if status >= 400 {
            throw ChannelError.message((json["msg"] as? String) ?? "HTTP \(status)")
        }
        return json
    }
}

private final class SeqBox: @unchecked Sendable {
    private var value: UInt64 = 0
    private let lock = NSLock()

    func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

private final class SocketBox: @unchecked Sendable {
    private let task: URLSessionWebSocketTask
    private let queue = DispatchQueue(label: "vibe.feishu.ws")

    init(task: URLSessionWebSocketTask) {
        self.task = task
    }

    func send(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                self.task.send(.data(data)) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
    }

    func receive() async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            task.receive { result in
                switch result {
                case let .success(.data(data)):
                    cont.resume(returning: data)
                case let .success(.string(text)):
                    cont.resume(returning: Data(text.utf8))
                case let .failure(error):
                    cont.resume(throwing: error)
                @unknown default:
                    cont.resume(returning: Data())
                }
            }
        }
    }
}

struct PBFrame {
    var seqId: UInt64 = 0
    var logId: UInt64 = 0
    var service: Int32 = 0
    var method: Int32 = 0
    var headers: [(String, String)] = []
    var payload: Data?

    func header(_ key: String) -> String {
        headers.first(where: { $0.0 == key })?.1 ?? ""
    }

    func encode() -> Data {
        var out = Data()
        out.append(PB.encodeVarintField(1, seqId))
        out.append(PB.encodeVarintField(2, logId))
        out.append(PB.encodeVarintField(3, UInt64(bitPattern: Int64(service))))
        out.append(PB.encodeVarintField(4, UInt64(bitPattern: Int64(method))))
        for (key, value) in headers {
            var nested = Data()
            nested.append(PB.encodeString(1, key))
            nested.append(PB.encodeString(2, value))
            out.append(PB.encodeBytes(5, nested))
        }
        if let payload {
            out.append(PB.encodeBytes(8, payload))
        }
        return out
    }

    static func decode(_ data: Data) -> PBFrame? {
        var frame = PBFrame()
        var i = 0
        while i < data.count {
            guard let key = PB.readVarint(data, &i) else { return nil }
            let field = Int(key >> 3)
            let wire = Int(key & 7)
            switch wire {
            case 0:
                guard let value = PB.readVarint(data, &i) else { return nil }
                switch field {
                case 1: frame.seqId = value
                case 2: frame.logId = value
                case 3: frame.service = Int32(truncatingIfNeeded: value)
                case 4: frame.method = Int32(truncatingIfNeeded: value)
                default: break
                }
            case 1:
                i += 8
                if i > data.count { return nil }
            case 2:
                guard let len64 = PB.readVarint(data, &i) else { return nil }
                let len = Int(len64)
                guard i + len <= data.count else { return nil }
                let slice = data.subdata(in: i..<(i + len))
                i += len
                switch field {
                case 5:
                    if let header = decodeHeader(slice) {
                        frame.headers.append(header)
                    }
                case 8:
                    frame.payload = slice
                default:
                    break
                }
            case 5:
                i += 4
                if i > data.count { return nil }
            default:
                return nil
            }
        }
        return frame
    }

    private static func decodeHeader(_ data: Data) -> (String, String)? {
        var key = ""
        var value = ""
        var i = 0
        while i < data.count {
            guard let tag = PB.readVarint(data, &i) else { return nil }
            let field = Int(tag >> 3)
            let wire = Int(tag & 7)
            guard wire == 2, let len64 = PB.readVarint(data, &i) else { return nil }
            let len = Int(len64)
            guard i + len <= data.count else { return nil }
            let text = String(data: data.subdata(in: i..<(i + len)), encoding: .utf8) ?? ""
            i += len
            if field == 1 { key = text }
            if field == 2 { value = text }
        }
        return (key, value)
    }
}

enum PB {
    static func encodeVarintField(_ field: Int, _ value: UInt64) -> Data {
        var out = encodeVarint(UInt64(field << 3))
        out.append(encodeVarint(value))
        return out
    }

    static func encodeString(_ field: Int, _ value: String) -> Data {
        encodeBytes(field, Data(value.utf8))
    }

    static func encodeBytes(_ field: Int, _ value: Data) -> Data {
        var out = encodeVarint(UInt64((field << 3) | 2))
        out.append(encodeVarint(UInt64(value.count)))
        out.append(value)
        return out
    }

    static func encodeVarint(_ value: UInt64) -> Data {
        var v = value
        var out = Data()
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    static func readVarint(_ data: Data, _ i: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift = 0
        while i < data.count {
            let byte = data[i]
            i += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }
}
