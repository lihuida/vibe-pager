import Foundation

struct LaneConfig: Codable, Equatable {
    var enabled: Bool = false
    var remoteEnabled: Bool = false
    var sendScreenshots: Bool = true
    var telegramOffset: Int64 = 0
    var activeChannel: String = "telegram"
    var telegram: TelegramConfig = TelegramConfig()
    var feishu: WebhookConfig = WebhookConfig()
    var dingtalk: WebhookConfig = WebhookConfig()
    var wechat: WechatConfig = WechatConfig()
    var lastDelivery: LastDelivery?
    var taskSeq: Int = 0
    var tasks: [RemoteTask] = []
    var pendingTaskId: String = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, remoteEnabled, sendScreenshots, telegramOffset, activeChannel
        case telegram, feishu, dingtalk, wechat, lastDelivery, taskSeq, tasks, pendingTaskId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        remoteEnabled = try c.decodeIfPresent(Bool.self, forKey: .remoteEnabled) ?? false
        sendScreenshots = try c.decodeIfPresent(Bool.self, forKey: .sendScreenshots) ?? true
        telegramOffset = try c.decodeIfPresent(Int64.self, forKey: .telegramOffset) ?? 0
        activeChannel = try c.decodeIfPresent(String.self, forKey: .activeChannel) ?? "telegram"
        telegram = try c.decodeIfPresent(TelegramConfig.self, forKey: .telegram) ?? TelegramConfig()
        feishu = try c.decodeIfPresent(WebhookConfig.self, forKey: .feishu) ?? WebhookConfig()
        dingtalk = try c.decodeIfPresent(WebhookConfig.self, forKey: .dingtalk) ?? WebhookConfig()
        wechat = try c.decodeIfPresent(WechatConfig.self, forKey: .wechat) ?? WechatConfig()
        lastDelivery = try c.decodeIfPresent(LastDelivery.self, forKey: .lastDelivery)
        taskSeq = try c.decodeIfPresent(Int.self, forKey: .taskSeq) ?? 0
        tasks = try c.decodeIfPresent([RemoteTask].self, forKey: .tasks) ?? []
        pendingTaskId = try c.decodeIfPresent(String.self, forKey: .pendingTaskId) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
        try c.encode(remoteEnabled, forKey: .remoteEnabled)
        try c.encode(sendScreenshots, forKey: .sendScreenshots)
        try c.encode(telegramOffset, forKey: .telegramOffset)
        try c.encode(activeChannel, forKey: .activeChannel)
        try c.encode(telegram, forKey: .telegram)
        try c.encode(feishu, forKey: .feishu)
        try c.encode(dingtalk, forKey: .dingtalk)
        try c.encode(wechat, forKey: .wechat)
        try c.encodeIfPresent(lastDelivery, forKey: .lastDelivery)
        try c.encode(taskSeq, forKey: .taskSeq)
        try c.encode(tasks, forKey: .tasks)
        try c.encode(pendingTaskId, forKey: .pendingTaskId)
    }

    var anyChannelReady: Bool { activeReady }

    var activeReady: Bool {
        switch activeChannel {
        case "telegram": return telegram.isReady
        case "feishu": return feishu.isReady
        case "dingtalk": return dingtalk.isReady
        case "wechat": return wechat.isReady
        default: return false
        }
    }

    mutating func registerTask(source: String, cwd: String, summary: String, conversationId: String, name: String = "") -> RemoteTask {
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        let clipped = summary.count > 80 ? String(summary.prefix(80)) + "…" : summary
        if !conversationId.isEmpty, let index = tasks.lastIndex(where: { $0.conversationId == conversationId }) {
            tasks[index].summary = clipped
            if !cwd.isEmpty { tasks[index].cwd = cwd }
            if !folder.isEmpty { tasks[index].folder = folder }
            tasks[index].source = source
            if !name.isEmpty { tasks[index].name = name }
            return tasks[index]
        }
        if !pendingTaskId.isEmpty, let index = tasks.lastIndex(where: { $0.id == pendingTaskId }) {
            pendingTaskId = ""
            tasks[index].summary = clipped
            if !cwd.isEmpty { tasks[index].cwd = cwd }
            if !folder.isEmpty { tasks[index].folder = folder }
            tasks[index].source = source
            if tasks[index].conversationId.isEmpty {
                tasks[index].conversationId = conversationId
            }
            if !name.isEmpty { tasks[index].name = name }
            return tasks[index]
        }
        taskSeq += 1
        let task = RemoteTask(
            id: String(taskSeq),
            source: source,
            folder: folder,
            cwd: cwd,
            summary: clipped,
            conversationId: conversationId,
            name: name
        )
        tasks.append(task)
        if tasks.count > 12 {
            tasks.removeFirst(tasks.count - 12)
        }
        return task
    }

    mutating func attachThread(taskId: String, messageId: String) {
        guard !messageId.isEmpty, let index = tasks.lastIndex(where: { $0.id == taskId }) else { return }
        if tasks[index].threadId.isEmpty {
            tasks[index].threadId = messageId
        }
        if !tasks[index].replyIds.contains(messageId) {
            tasks[index].replyIds.append(messageId)
            if tasks[index].replyIds.count > 24 {
                tasks[index].replyIds.removeFirst(tasks[index].replyIds.count - 24)
            }
        }
    }

    func task(id: String) -> RemoteTask? {
        tasks.last(where: { $0.id == id })
    }

    func task(threadId: String) -> RemoteTask? {
        guard !threadId.isEmpty else { return nil }
        return tasks.last(where: { $0.threadId == threadId || $0.replyIds.contains(threadId) })
    }

    func taskListText() -> String {
        guard !tasks.isEmpty else {
            return "还没有任务。等完工后会出现编号。"
        }
        var lines = ["当前任务："]
        for task in tasks.reversed() {
            var row = "#\(task.id)"
            if !task.folder.isEmpty, !task.name.isEmpty {
                row += " \(task.folder)-\(task.name)"
            } else if !task.name.isEmpty {
                row += " \(task.name)"
            } else if !task.folder.isEmpty {
                row += " \(task.folder)"
            } else {
                row += " \(task.source)"
            }
            lines.append(row)
        }
        lines.append("")
        lines.append("回复时带 #编号，或直接回复那条消息。")
        return lines.joined(separator: "\n")
    }
}

struct AppConfig: Codable, Equatable {
    var listenPort: UInt16 = 17800
    var selectedLane: String = "cursor"
    var cursor: LaneConfig = LaneConfig()
    var codex: LaneConfig = LaneConfig()

    var cursorEnabled: Bool { cursor.enabled }
    var codexEnabled: Bool { codex.enabled }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        listenPort = try c.decodeIfPresent(UInt16.self, forKey: .listenPort) ?? 17800
        if c.contains(.cursor) || c.contains(.codex) {
            selectedLane = try c.decodeIfPresent(String.self, forKey: .selectedLane) ?? "cursor"
            cursor = try c.decodeIfPresent(LaneConfig.self, forKey: .cursor) ?? LaneConfig()
            codex = try c.decodeIfPresent(LaneConfig.self, forKey: .codex) ?? LaneConfig()
            return
        }
        selectedLane = "cursor"
        cursor = LaneConfig()
        cursor.enabled = try c.decodeIfPresent(Bool.self, forKey: .cursorEnabled) ?? false
        cursor.remoteEnabled = try c.decodeIfPresent(Bool.self, forKey: .remoteEnabled) ?? false
        cursor.sendScreenshots = try c.decodeIfPresent(Bool.self, forKey: .sendScreenshots) ?? true
        cursor.telegramOffset = try c.decodeIfPresent(Int64.self, forKey: .telegramOffset) ?? 0
        cursor.activeChannel = try c.decodeIfPresent(String.self, forKey: .activeChannel) ?? "telegram"
        cursor.telegram = try c.decodeIfPresent(TelegramConfig.self, forKey: .telegram) ?? TelegramConfig()
        cursor.feishu = try c.decodeIfPresent(WebhookConfig.self, forKey: .feishu) ?? WebhookConfig()
        cursor.dingtalk = try c.decodeIfPresent(WebhookConfig.self, forKey: .dingtalk) ?? WebhookConfig()
        cursor.wechat = try c.decodeIfPresent(WechatConfig.self, forKey: .wechat) ?? WechatConfig()
        cursor.lastDelivery = try c.decodeIfPresent(LastDelivery.self, forKey: .lastDelivery)
        cursor.taskSeq = try c.decodeIfPresent(Int.self, forKey: .taskSeq) ?? 0
        cursor.tasks = try c.decodeIfPresent([RemoteTask].self, forKey: .tasks) ?? []
        cursor.pendingTaskId = try c.decodeIfPresent(String.self, forKey: .pendingTaskId) ?? ""
        codex = LaneConfig()
        codex.enabled = try c.decodeIfPresent(Bool.self, forKey: .codexEnabled) ?? false
        codex.remoteEnabled = codex.enabled && cursor.remoteEnabled
        codex.sendScreenshots = cursor.sendScreenshots
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(listenPort, forKey: .listenPort)
        try c.encode(selectedLane, forKey: .selectedLane)
        try c.encode(cursor, forKey: .cursor)
        try c.encode(codex, forKey: .codex)
    }

    func lane(for source: String) -> LaneConfig {
        source == "codex" ? codex : cursor
    }

    mutating func updateLane(_ source: String, _ body: (inout LaneConfig) -> Void) {
        if source == "codex" {
            body(&codex)
        } else {
            body(&cursor)
        }
    }

    static var supportDir: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/VibeRemote")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var configURL: URL {
        supportDir.appendingPathComponent("config.json")
    }

    static var inboxDir: URL {
        let dir = supportDir.appendingPathComponent("inbox")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: configURL) else { return AppConfig() }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: AppConfig.configURL, options: .atomic)
    }

    private enum CodingKeys: String, CodingKey {
        case listenPort, selectedLane, cursor, codex
        case remoteEnabled, cursorEnabled, codexEnabled, sendScreenshots, replyTarget
        case telegramOffset, activeChannel, telegram, feishu, dingtalk, wechat
        case lastDelivery, taskSeq, tasks, pendingTaskId
    }
}

struct TelegramConfig: Codable, Equatable {
    var botToken: String = ""
    var chatId: String = ""
    var botUsername: String = ""

    var isReady: Bool {
        !botToken.trimmingCharacters(in: .whitespaces).isEmpty
            && !chatId.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

struct WebhookConfig: Codable, Equatable {
    var webhookUrl: String = ""
    var secret: String = ""
    var keyword: String = ""
    var appId: String = ""
    var appSecret: String = ""
    var lastMessageId: String = ""

    var chatId: String = ""
    var userId: String = ""

    var isReady: Bool {
        canReceive && (!chatId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !userId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var canReceive: Bool {
        !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !appSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        webhookUrl = try c.decodeIfPresent(String.self, forKey: .webhookUrl) ?? ""
        secret = try c.decodeIfPresent(String.self, forKey: .secret) ?? ""
        keyword = try c.decodeIfPresent(String.self, forKey: .keyword) ?? ""
        appId = try c.decodeIfPresent(String.self, forKey: .appId) ?? ""
        appSecret = try c.decodeIfPresent(String.self, forKey: .appSecret) ?? ""
        lastMessageId = try c.decodeIfPresent(String.self, forKey: .lastMessageId) ?? ""
        chatId = try c.decodeIfPresent(String.self, forKey: .chatId) ?? ""
        userId = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
    }
}

struct WechatConfig: Codable, Equatable {
    var provider: String = "ilink"
    var token: String = ""
    var uid: String = ""
    var botId: String = ""
    var botSecret: String = ""
    var baseUrl: String = ""
    var contextToken: String = ""
    var peerUserId: String = ""
    var updatesBuf: String = ""

    var isILink: Bool {
        provider == "ilink" || token.hasPrefix("ilinkbot_")
    }

    var isLoggedIn: Bool {
        isILink && !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isReady: Bool {
        let token = token.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else { return false }
        switch provider {
        case "ilink":
            return !peerUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !contextToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case "wxpusher":
            return !uid.trimmingCharacters(in: .whitespaces).isEmpty
        case "pushplus", "wecom":
            return true
        default:
            return isILink && !peerUserId.isEmpty && !contextToken.isEmpty
        }
    }

    var canReceive: Bool {
        if isILink {
            return !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return !botId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !botSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        uid = try c.decodeIfPresent(String.self, forKey: .uid) ?? ""
        botId = try c.decodeIfPresent(String.self, forKey: .botId) ?? ""
        botSecret = try c.decodeIfPresent(String.self, forKey: .botSecret) ?? ""
        baseUrl = try c.decodeIfPresent(String.self, forKey: .baseUrl) ?? ""
        contextToken = try c.decodeIfPresent(String.self, forKey: .contextToken) ?? ""
        peerUserId = try c.decodeIfPresent(String.self, forKey: .peerUserId) ?? ""
        updatesBuf = try c.decodeIfPresent(String.self, forKey: .updatesBuf) ?? ""
        if let saved = try c.decodeIfPresent(String.self, forKey: .provider), !saved.isEmpty {
            provider = saved
        } else if token.hasPrefix("ilinkbot_") {
            provider = "ilink"
        } else if token.hasPrefix("AT_") {
            provider = "wxpusher"
        } else {
            provider = "ilink"
        }
    }
}

struct LastDelivery: Codable, Equatable {
    var at: String
    var channel: String
    var ok: Bool
    var message: String
}

struct RemoteTask: Codable, Equatable {
    var id: String
    var source: String
    var folder: String
    var cwd: String
    var summary: String
    var conversationId: String = ""
    var threadId: String = ""
    var replyIds: [String] = []
    var name: String = ""

    init(id: String, source: String, folder: String, cwd: String, summary: String, conversationId: String = "", threadId: String = "", name: String = "") {
        self.id = id
        self.source = source
        self.folder = folder
        self.cwd = cwd
        self.summary = summary
        self.conversationId = conversationId
        self.threadId = threadId
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        source = try c.decodeIfPresent(String.self, forKey: .source) ?? ""
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? ""
        cwd = try c.decodeIfPresent(String.self, forKey: .cwd) ?? ""
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        conversationId = try c.decodeIfPresent(String.self, forKey: .conversationId) ?? ""
        threadId = try c.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        replyIds = try c.decodeIfPresent([String].self, forKey: .replyIds) ?? []
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
    }
}

struct OutboundEvent {
    var source: String
    var summary: String
    var image: Data? = nil
    var title: String = "任务完成"
    var taskId: String = ""
    var folder: String = ""
    var replyTo: String = ""
    var replyHint: String = ""

    var composed: String {
        if source.isEmpty && title.isEmpty { return summary }
        let topic = (!title.isEmpty && title != "任务完成" && title != "回复" && title != "发来消息") ? title : ""
        let name: String = {
            if !folder.isEmpty, !topic.isEmpty { return "\(folder)-\(topic)" }
            if !topic.isEmpty { return topic }
            if !folder.isEmpty { return folder }
            if !source.isEmpty { return source }
            return "Vibe Pager"
        }()
        if !taskId.isEmpty {
            return "【#\(taskId) \(name)】\n\n\(summary)"
        }
        return "【\(name)】\n\n\(summary)"
    }
}

struct SendOutcome {
    var channel: String
    var ok: Bool
    var message: String
    var messageId: String = ""
}

struct InboundMessage {
    var chatId: String
    var text: String
    var photoFileId: String?
    var replyToId: String = ""
}
