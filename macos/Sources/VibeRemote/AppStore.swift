import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    @Published var config: AppConfig
    @Published var selectedLane: String
    @Published var serverOk = false
    @Published var serverError = ""
    @Published var toast = ""
    @Published var busy = false
    @Published var telegramBinding = false
    @Published var wechatQR: NSImage?
    @Published var wechatQRWaiting = false
    @Published var wechatHint = ""
    @Published var wechatVerifyCode = ""
    @Published var wechatNeedsVerify = false
    @Published var accessibilityOn = false
    @Published var screenCaptureOn = false
    @Published var cursorInstalled = false
    @Published var codexInstalled = false

    private var server: HookServer?
    private var toastTask: Task<Void, Never>?
    private var bindTask: Task<Void, Never>?
    private var inboxTasks: [String: Task<Void, Never>] = [:]
    private var wechatQRTask: Task<Void, Never>?
    private var lastPushedGeneration: [String: String] = [:]
    private var lastPushedText: [String: String] = [:]

    init() {
        let loaded = AppConfig.load()
        config = loaded
        selectedLane = loaded.selectedLane == "codex" ? "codex" : "cursor"
        let server = HookServer(store: self)
        self.server = server
        server.start(port: config.listenPort)
        _ = HookInstaller.sync(config)
        refreshPermissions()
        refreshInstalled()
        startInboxes()
    }

    var visibleLanes: [String] {
        var lanes: [String] = []
        if cursorInstalled { lanes.append("cursor") }
        if codexInstalled { lanes.append("codex") }
        return lanes
    }

    func refreshInstalled() {
        cursorInstalled = InstalledTools.hasCursor()
        codexInstalled = InstalledTools.hasCodex()
        if !visibleLanes.contains(selectedLane), let first = visibleLanes.first {
            selectedLane = first
            config.selectedLane = first
            persist()
        }
    }

    var current: LaneConfig {
        config.lane(for: selectedLane)
    }

    var remoteEnabled: Bool {
        get { current.enabled && current.remoteEnabled }
        set {
            updateLane(selectedLane) {
                $0.enabled = newValue
                $0.remoteEnabled = newValue
            }
            persist()
            if let note = HookInstaller.sync(config).last(where: { !$0.isEmpty }) {
                flash(note)
            }
            startInboxes()
            if newValue {
                promptAccessibilityIfNeeded()
            }
        }
    }

    var activeChannel: String {
        get { current.activeChannel }
        set {
            updateLane(selectedLane) { $0.activeChannel = newValue }
            persist()
            startInboxes()
            if newValue == "wechat" {
                ensureWeChatLogin()
            }
        }
    }

    func selectLane(_ id: String) {
        let lane = id == "codex" ? "codex" : "cursor"
        guard lane != selectedLane else { return }
        cancelTelegramBind()
        cancelWeChatQR()
        wechatQR = nil
        selectedLane = lane
        config.selectedLane = lane
        persist()
    }

    func persist() {
        config.save()
    }

    func refreshPermissions() {
        accessibilityOn = AgentBridge.isTrusted()
        screenCaptureOn = ScreenShot.hasPermission()
    }

    func openAccessibilitySettings() {
        _ = AgentBridge.promptTrust()
        openPrivacy("Privacy_Accessibility")
        refreshPermissions()
    }

    func promptAccessibilityIfNeeded() {
        refreshPermissions()
        guard !accessibilityOn else { return }
        let name = selectedLane == "codex" ? "Codex" : "Cursor"
        let alert = NSAlert()
        alert.messageText = "需要打开辅助功能"
        alert.informativeText = "开启后才能把通道里的回复粘贴进 \(name)。请在「系统设置 → 隐私与安全 → 辅助功能」里允许 Vibe Pager。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "去打开")
        alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        let result = alert.runModal()
        if result == .alertFirstButtonReturn {
            openAccessibilitySettings()
        }
    }

    func openScreenCaptureSettings() {
        ScreenShot.requestPermissionIfNeeded()
        openPrivacy("Privacy_ScreenCapture")
        refreshPermissions()
    }

    func binding<T>(_ keyPath: WritableKeyPath<LaneConfig, T>) -> Binding<T> {
        Binding(
            get: { self.current[keyPath: keyPath] },
            set: { value in
                self.objectWillChange.send()
                self.config.updateLane(self.selectedLane) { $0[keyPath: keyPath] = value }
            }
        )
    }

    func flash(_ message: String) {
        toast = message
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_200_000_000)
            if !Task.isCancelled {
                self?.toast = ""
            }
        }
    }

    func handleIncoming(source: String, body: [String: Any]) async {
        let laneId = Self.resolveLane(source)
        var lane = config.lane(for: laneId)
        guard lane.enabled, lane.remoteEnabled else { return }
        guard lane.anyChannelReady else { return }
        let skipCapture = (body["skip_capture"] as? Bool) ?? false
        var image: Data?
        if let path = body["image_path"] as? String {
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                image = ScreenShot.loadFile(trimmed)
            }
        }
        let generation = (body["generation_id"] as? String) ?? ""
        let summary = ChannelService.summarize(source: source, body: body)
        if summary.isEmpty, !skipCapture {
            return
        }
        let alreadySent = !generation.isEmpty && generation == lastPushedGeneration[laneId]
        if alreadySent, !skipCapture {
            let prev = lastPushedText[laneId] ?? ""
            if summary.count <= prev.count + 24 {
                return
            }
        }
        let cwd = ChannelService.extractCwd(body)
        let project = ChannelService.projectName(body)
        let topic = ChannelService.topicName(body)
        var taskId = ""
        if !skipCapture {
            let task = lane.registerTask(
                source: source,
                cwd: cwd,
                summary: summary,
                conversationId: ChannelService.extractConversation(body),
                name: topic
            )
            taskId = task.id
            updateLane(laneId) { $0 = lane }
            persist()
        }
        // 每条完工都当新消息发，不要回贴到旧消息上。飞书对「回复」经常不推送，看起来像没收到。
        let event = OutboundEvent(
            source: source,
            summary: summary,
            image: image,
            title: topic,
            taskId: taskId,
            folder: project.isEmpty ? URL(fileURLWithPath: cwd).lastPathComponent : project
        )
        let results = await ChannelService.dispatchAll(config: lane, event: event)
        if let last = results.last, last.ok {
            if !generation.isEmpty {
                lastPushedGeneration[laneId] = generation
            }
            lastPushedText[laneId] = summary
        }
        if !taskId.isEmpty, let messageId = results.last?.messageId {
            updateLane(laneId) { $0.attachThread(taskId: taskId, messageId: messageId) }
        }
        if let last = results.last {
            applyDelivery(last, laneId: laneId)
        }
    }

    func test(_ channel: String) {
        let laneId = selectedLane
        let lane = current
        Task {
            busy = true
            defer { busy = false }
            do {
                let outcome = try await ChannelService.sendTest(config: lane, channel: channel)
                applyDelivery(outcome, laneId: laneId)
                flash(outcome.ok ? outcome.message : outcome.message)
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    func disconnect(_ channel: String) {
        updateLane(selectedLane) { lane in
            switch channel {
            case "telegram":
                lane.telegram = TelegramConfig()
            case "feishu":
                lane.feishu = WebhookConfig()
            case "dingtalk":
                lane.dingtalk = WebhookConfig()
            case "wechat":
                lane.wechat = WechatConfig()
            default:
                break
            }
        }
        if channel == "wechat" {
            cancelWeChatQR()
            wechatQR = nil
            wechatHint = ""
        }
        persist()
        startInboxes()
        flash("已解除绑定")
    }

    func saveWebhook() {
        persist()
        flash("已保存")
    }

    func connectTelegram() {
        updateLane(selectedLane) { $0.activeChannel = "telegram" }
        persist()
        startTelegramBind()
    }

    func connectBot(_ kind: String) {
        updateLane(selectedLane) { $0.activeChannel = kind }
        persist()
        let lane = current
        let ready = kind == "feishu" ? lane.feishu.canReceive : lane.dingtalk.canReceive
        guard ready else {
            flash(kind == "feishu" ? "请填写 App ID 和 Secret" : "请填写 Client ID 和 Secret")
            return
        }
        startInboxes()
        flash(kind == "feishu"
              ? "请在飞书搜索机器人，打开单聊发一句「你好」"
              : "请在钉钉搜索机器人，打开单聊发一句「你好」")
    }

    func connectWechat() {
        updateLane(selectedLane) { lane in
            let token = lane.wechat.token.trimmingCharacters(in: .whitespacesAndNewlines)
            if token.contains("qyapi.weixin.qq.com") {
                lane.wechat.provider = "wecom"
            } else if token.hasPrefix("AT_") {
                lane.wechat.provider = "wxpusher"
            } else {
                lane.wechat.provider = "pushplus"
            }
            lane.activeChannel = "wechat"
        }
        persist()
        startInboxes()
        if current.wechat.isILink || current.wechat.provider == "wxpusher" {
            ensureWeChatLogin()
        } else {
            testAfterConnect("wechat", success: "微信通道已连接，测试消息已发出")
        }
    }

    func connectPasted(_ raw: String) {
        switch ChannelPaste.guess(raw) {
        case let .telegram(token):
            updateLane(selectedLane) {
                $0.activeChannel = "telegram"
                $0.telegram.botToken = token
            }
            persist()
            startTelegramBind()
        case let .feishuApp(id):
            updateLane(selectedLane) {
                $0.activeChannel = "feishu"
                $0.feishu.appId = id
            }
            persist()
            flash("已填入 App ID，请再填 Secret 后点连接")
        case let .wechat(provider, token):
            updateLane(selectedLane) {
                $0.activeChannel = "wechat"
                $0.wechat.provider = provider
                $0.wechat.token = token
            }
            persist()
            if provider == "wxpusher" || provider == "ilink" {
                ensureWeChatLogin()
            } else {
                testAfterConnect("wechat", success: "微信通道已连接，测试消息已发出")
            }
        case .unknown:
            flash("识别不了这段内容。请按当前通道的说明来配置。")
        }
    }

    func connectFromPasteboard() {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            flash("剪贴板是空的")
            return
        }
        connectPasted(text)
    }

    func openGuide(for kind: ChannelKind) {
        NSWorkspace.shared.open(ChannelPaste.guideURL(for: kind))
    }

    func startTelegramBind() {
        let laneId = selectedLane
        let token = current.telegram.botToken.trimmingCharacters(in: .whitespaces)
        guard !token.isEmpty else {
            flash("请填写 Bot Token")
            return
        }
        bindTask?.cancel()
        telegramBinding = true
        startInboxes()
        bindTask = Task {
            do {
                let username = try await ChannelService.telegramGetMe(token: token)
                updateLane(laneId) { $0.telegram.botUsername = username }
                persist()
                if !username.isEmpty, let url = URL(string: "https://t.me/\(username)") {
                    NSWorkspace.shared.open(url)
                }
                flash(username.isEmpty ? "请向机器人发送 /start" : "请向 @\(username) 发送 /start")
                var offset: Int64 = config.lane(for: laneId).telegramOffset
                let deadline = Date().addingTimeInterval(90)
                while Date() < deadline, telegramBinding, !Task.isCancelled {
                    let (next, chatId) = try await ChannelService.telegramPollChatId(token: token, offset: offset)
                    offset = next
                    updateLane(laneId) { $0.telegramOffset = next }
                    if let chatId {
                        updateLane(laneId) { $0.telegram.chatId = chatId }
                        persist()
                        telegramBinding = false
                        flash("Telegram 已绑定，之后可直接在那边发消息")
                        startInboxes()
                        return
                    }
                }
                persist()
                telegramBinding = false
                if !Task.isCancelled {
                    flash("等待超时，请向机器人发送任意消息后重试")
                }
            } catch {
                telegramBinding = false
                flash(error.localizedDescription)
            }
        }
    }

    func cancelTelegramBind() {
        guard telegramBinding else { return }
        telegramBinding = false
        bindTask?.cancel()
        startInboxes()
    }

    func ensureWeChatLogin() {
        let wechat = current.wechat
        if wechat.isReady {
            wechatQRWaiting = false
            wechatHint = ""
            startInboxes()
            return
        }
        if wechat.isLoggedIn {
            wechatQRWaiting = false
            wechatHint = "已登录。请在微信里给这个对话发一句「你好」"
            startInboxes()
            return
        }
        if wechatQRWaiting { return }
        startWeChatQR()
    }

    func startWeChatQR() {
        wechatQRTask?.cancel()
        let laneId = selectedLane
        updateLane(laneId) {
            $0.activeChannel = "wechat"
            $0.wechat.provider = "ilink"
        }
        persist()
        wechatQRWaiting = true
        wechatQR = nil
        wechatNeedsVerify = false
        wechatVerifyCode = ""
        wechatHint = "正在生成二维码…"
        wechatQRTask = Task {
            do {
                var refreshes = 0
                while wechatQRWaiting, !Task.isCancelled, refreshes < 4 {
                    let session = try await WeixinILink.createQR()
                    wechatQR = QRCode.image(from: session.imageURL)
                    wechatHint = "请用微信扫一扫"
                    flash("请用微信扫一扫")
                    let deadline = Date().addingTimeInterval(8 * 60)
                    var expired = false
                    var baseUrl = WeixinILink.defaultBase
                    while Date() < deadline, wechatQRWaiting, !Task.isCancelled {
                        let pending = wechatVerifyCode.trimmingCharacters(in: .whitespacesAndNewlines)
                        if wechatNeedsVerify, pending.isEmpty {
                            try await Task.sleep(nanoseconds: 400_000_000)
                            continue
                        }
                        let status = try await WeixinILink.pollQR(
                            session.code,
                            baseUrl: baseUrl,
                            verifyCode: pending
                        )
                        switch status {
                        case .wait:
                            if !wechatNeedsVerify {
                                wechatHint = "请用微信扫一扫"
                            }
                        case .scanned:
                            if !pending.isEmpty {
                                wechatVerifyCode = ""
                                wechatNeedsVerify = false
                            }
                            wechatHint = "已扫码，请在手机上确认"
                        case .needVerify:
                            wechatNeedsVerify = true
                            if pending.isEmpty {
                                wechatHint = "请输入手机微信上显示的数字"
                            } else {
                                wechatVerifyCode = ""
                                wechatHint = "数字不匹配，请重新输入"
                            }
                        case let .redirect(host):
                            let trimmed = host.replacingOccurrences(of: "https://", with: "")
                            baseUrl = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
                            wechatHint = "已扫码，正在确认…"
                        case let .confirmed(creds):
                            applyWeChatLogin(laneId, creds)
                            return
                        case .alreadyBound:
                            wechatQRWaiting = false
                            wechatNeedsVerify = false
                            wechatHint = "这个微信已经绑定过，请重新生成二维码再试"
                            flash("这个微信已经绑定过，请重新扫码")
                            return
                        case .blocked:
                            wechatNeedsVerify = false
                            wechatVerifyCode = ""
                            expired = true
                            wechatHint = "配对码输错太多次，正在刷新二维码"
                        case .expired:
                            expired = true
                            wechatHint = "二维码已过期，正在刷新"
                        case let .unknown(raw):
                            wechatHint = raw.isEmpty ? "正在等待微信确认…" : "微信状态：\(raw)"
                        }
                        if expired { break }
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                    refreshes += 1
                    wechatNeedsVerify = false
                    wechatVerifyCode = ""
                }
                wechatQRWaiting = false
                if !Task.isCancelled {
                    wechatHint = "二维码已过期，点下面重新生成"
                    flash("二维码已过期，请重新生成")
                }
            } catch is CancellationError {
                wechatQRWaiting = false
            } catch {
                wechatQRWaiting = false
                wechatHint = error.localizedDescription
                flash(error.localizedDescription)
            }
        }
    }

    private func applyWeChatLogin(_ laneId: String, _ creds: WeixinILink.Credentials) {
        updateLane(laneId) { lane in
            lane.wechat.provider = "ilink"
            lane.wechat.token = creds.token
            lane.wechat.botId = creds.botId
            lane.wechat.uid = creds.userId
            lane.wechat.baseUrl = creds.baseUrl
            lane.wechat.contextToken = ""
            lane.wechat.peerUserId = ""
            lane.wechat.updatesBuf = ""
        }
        persist()
        wechatQRWaiting = false
        wechatNeedsVerify = false
        wechatHint = "已登录。请在微信里给这个对话发一句「你好」"
        flash("微信已登录，请再发一句「你好」完成绑定")
        startInboxes()
    }

    func submitWeChatVerify() {
        wechatVerifyCode = wechatVerifyCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wechatNeedsVerify, !wechatVerifyCode.isEmpty else { return }
        wechatHint = "正在验证数字…"
    }

    func cancelWeChatQR() {
        wechatQRWaiting = false
        wechatNeedsVerify = false
        wechatVerifyCode = ""
        wechatQRTask?.cancel()
    }

    func startInboxes() {
        stopInboxes()
        startLaneInboxes("cursor")
        startLaneInboxes("codex")
    }

    func stopInboxes() {
        for (_, task) in inboxTasks {
            task.cancel()
        }
        inboxTasks.removeAll()
    }

    func quit() {
        NSApp.terminate(nil)
    }

    private func startLaneInboxes(_ source: String) {
        let lane = config.lane(for: source)
        if lane.activeChannel == "wechat", lane.wechat.isILink, lane.wechat.canReceive {
            startWeChatILinkInbox(source)
        }
        guard lane.enabled, lane.remoteEnabled else { return }
        switch lane.activeChannel {
        case "telegram": startTelegramInbox(source)
        case "feishu": startFeishuInbox(source)
        case "dingtalk": startDingTalkInbox(source)
        case "wechat":
            if !lane.wechat.isILink {
                startWeComInbox(source)
            }
        default: break
        }
    }

    private func startTelegramInbox(_ source: String) {
        let key = "\(source)-telegram"
        inboxTasks[key]?.cancel()
        let bindingThisLane = telegramBinding && selectedLane == source
        let lane = config.lane(for: source)
        guard lane.telegram.isReady, !bindingThisLane else { return }
        inboxTasks[key] = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snap = await MainActor.run {
                    let lane = self.config.lane(for: source)
                    let binding = self.telegramBinding && self.selectedLane == source
                    return (
                        token: lane.telegram.botToken,
                        chatId: lane.telegram.chatId,
                        offset: lane.telegramOffset,
                        live: lane.enabled && lane.remoteEnabled && lane.telegram.isReady && !binding
                    )
                }
                guard snap.live else { return }
                do {
                    let (next, messages) = try await ChannelService.telegramPollInbox(token: snap.token, offset: snap.offset)
                    if next != snap.offset {
                        await MainActor.run {
                            self.updateLane(source) { $0.telegramOffset = next }
                            self.persist()
                        }
                    }
                    for message in messages where message.chatId == snap.chatId {
                        await self.handleTelegramInbound(source, message)
                    }
                } catch {
                    try? await Task.sleep(nanoseconds: 4_000_000_000)
                }
            }
        }
    }

    private func startFeishuInbox(_ source: String) {
        let key = "\(source)-feishu"
        inboxTasks[key]?.cancel()
        let lane = config.lane(for: source)
        guard lane.feishu.canReceive else { return }
        let appId = lane.feishu.appId
        let appSecret = lane.feishu.appSecret
        inboxTasks[key] = Task.detached { [weak self] in
            let store = self
            await ChannelInbox.runFeishu(appId: appId, appSecret: appSecret) { inbound in
                Task { @MainActor in
                    store?.handleChatInbound(source, "feishu", inbound)
                }
            }
        }
    }

    private func startDingTalkInbox(_ source: String) {
        let key = "\(source)-dingtalk"
        inboxTasks[key]?.cancel()
        let lane = config.lane(for: source)
        guard lane.dingtalk.canReceive else { return }
        let clientId = lane.dingtalk.appId
        let clientSecret = lane.dingtalk.appSecret
        inboxTasks[key] = Task.detached { [weak self] in
            let store = self
            await ChannelInbox.runDingTalk(clientId: clientId, clientSecret: clientSecret) { inbound in
                Task { @MainActor in
                    store?.handleChatInbound(source, "dingtalk", inbound)
                }
            }
        }
    }

    private func startWeChatILinkInbox(_ source: String) {
        let key = "\(source)-wechat"
        inboxTasks[key]?.cancel()
        let lane = config.lane(for: source)
        guard lane.wechat.isILink, lane.wechat.canReceive else { return }
        inboxTasks[key] = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let snap = await MainActor.run { () -> (WechatConfig, Bool, Bool)? in
                    let lane = self.config.lane(for: source)
                    guard lane.wechat.isILink, lane.wechat.canReceive else { return nil }
                    let live = !lane.wechat.isReady || (lane.enabled && lane.remoteEnabled)
                    return (lane.wechat, live, lane.wechat.isReady)
                }
                guard let snap, snap.1 else { return }
                do {
                    let result = try await WeixinILink.getUpdates(cfg: snap.0)
                    await MainActor.run {
                        if result.expired {
                            self.expireWeChatLogin(source)
                            return
                        }
                        if result.buf != snap.0.updatesBuf {
                            self.updateLane(source) { $0.wechat.updatesBuf = result.buf }
                            self.persist()
                        }
                    }
                    if result.expired { return }
                    for message in result.messages {
                        await self.handleWeChatILinkInbound(source, message)
                    }
                } catch {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
            }
        }
    }

    private func handleWeChatILinkInbound(_ source: String, _ message: WeixinILink.Inbound) async {
        let bound = await MainActor.run { () -> Bool in
            let ready = self.config.lane(for: source).wechat.isReady
            self.updateLane(source) { lane in
                if !message.contextToken.isEmpty {
                    lane.wechat.contextToken = message.contextToken
                }
                if lane.wechat.peerUserId.isEmpty {
                    lane.wechat.peerUserId = message.userId
                }
            }
            self.persist()
            if !ready {
                self.wechatHint = ""
                self.flash("微信已绑定")
                self.test("wechat")
                return false
            }
            return true
        }
        guard bound, !message.text.isEmpty else { return }
        let remoteOn = await MainActor.run {
            let lane = self.config.lane(for: source)
            return lane.enabled && lane.remoteEnabled
        }
        guard remoteOn else { return }
        await handleInbound(laneId: source, channel: "微信", text: message.text, threadId: message.messageId)
    }

    private func expireWeChatLogin(_ source: String) {
        updateLane(source) { $0.wechat = WechatConfig() }
        persist()
        wechatQR = nil
        wechatHint = "登录已过期，请重新扫码"
        flash("微信登录已过期，请重新扫码")
        if selectedLane == source, current.activeChannel == "wechat" {
            startWeChatQR()
        }
    }

    private func startWeComInbox(_ source: String) {
        let key = "\(source)-wechat"
        inboxTasks[key]?.cancel()
        let lane = config.lane(for: source)
        guard lane.wechat.canReceive else { return }
        let botId = lane.wechat.botId
        let secret = lane.wechat.botSecret
        inboxTasks[key] = Task.detached { [weak self] in
            let store = self
            await ChannelInbox.runWeCom(botId: botId, secret: secret) { text in
                Task { @MainActor in
                    store?.deliverFromChannel(source, "微信", text: text)
                }
            }
        }
    }

    private func handleChatInbound(_ laneId: String, _ kind: String, _ inbound: ChatInbound) {
        guard inbound.isP2P else { return }
        let lane = config.lane(for: laneId)
        if kind == "feishu" {
            if lane.feishu.chatId.isEmpty {
                guard !inbound.chatId.isEmpty else { return }
                updateLane(laneId) { $0.feishu.chatId = inbound.chatId }
                persist()
                flash("飞书单聊已绑定")
                test("feishu")
                return
            }
            guard inbound.chatId == lane.feishu.chatId else { return }
            Task { await handleInbound(laneId: laneId, channel: "飞书", text: inbound.text, threadId: inbound.refId) }
            return
        }
        if kind == "dingtalk" {
            if lane.dingtalk.userId.isEmpty {
                guard !inbound.userId.isEmpty else { return }
                updateLane(laneId) {
                    $0.dingtalk.userId = inbound.userId
                    $0.dingtalk.chatId = inbound.chatId
                }
                persist()
                flash("钉钉单聊已绑定")
                test("dingtalk")
                return
            }
            guard inbound.userId == lane.dingtalk.userId else { return }
            Task { await handleInbound(laneId: laneId, channel: "钉钉", text: inbound.text) }
        }
    }

    func deliverFromChannel(_ laneId: String, _ channel: String, text: String) {
        Task { await handleInbound(laneId: laneId, channel: channel, text: text) }
    }

    private func handleInbound(laneId: String, channel: String, text: String, image: Data? = nil, threadId: String = "") async {
        var lane = config.lane(for: laneId)
        let cmd = TaskRouter.parse(text, fallback: laneId)
        if cmd.listTasks {
            await ChannelService.replyOnActive(config: lane, text: lane.taskListText())
            return
        }
        if let taskId = cmd.taskId, lane.task(id: taskId) == nil {
            await ChannelService.replyOnActive(config: lane, text: "没有任务 #\(taskId)。发 /tasks 查看。")
            return
        }
        guard !cmd.prompt.isEmpty || image != nil else { return }
        let task = cmd.taskId.flatMap { lane.task(id: $0) }
            ?? lane.task(threadId: threadId)
            ?? lane.tasks.last
        if let task {
            updateLane(laneId) { $0.pendingTaskId = task.id }
            persist()
            lane = config.lane(for: laneId)
        }
        let prompt = TaskRouter.followupPrompt(task: task, prompt: cmd.prompt)
        let note = AgentBridge.deliver(to: cmd.target, text: prompt, image: image)
        flash("已从\(channel)交给 \(cmd.target == "codex" ? "Codex" : "Cursor")")
        if note.contains("请在") {
            flash(note)
        }
        await ChannelService.replyOnActive(config: lane, text: note, replyTo: task?.threadId ?? threadId)
    }

    private func handleTelegramInbound(_ laneId: String, _ message: InboundMessage) async {
        let lane = config.lane(for: laneId)
        var text = message.text
        if text == "/start" || text == "/help" {
            await ChannelService.telegramAck(
                token: lane.telegram.botToken,
                chatId: message.chatId,
                text: "直接发文字会交给 \(laneId == "codex" ? "Codex" : "Cursor")。开头加 /cursor 或 /codex 可指定。回复某条任务消息即可继续该任务，也可发 #编号。发 /tasks 查看全部。"
            )
            return
        }
        var image: Data?
        if let fileId = message.photoFileId {
            image = await ChannelService.telegramDownloadFile(token: lane.telegram.botToken, fileId: fileId)
            if let image {
                let url = AppConfig.inboxDir.appendingPathComponent("telegram-\(laneId).jpg")
                try? image.write(to: url)
                if text.isEmpty {
                    text = "用户发来一张图片，路径：\(url.path)"
                } else {
                    text += "\n\n附件图片：\(url.path)"
                }
            }
        }
        await handleInbound(laneId: laneId, channel: "Telegram", text: text, image: image, threadId: message.replyToId)
    }

    private func testAfterConnect(_ channel: String, success: String) {
        let laneId = selectedLane
        let lane = current
        Task {
            busy = true
            defer { busy = false }
            do {
                let outcome = try await ChannelService.sendTest(config: lane, channel: channel)
                applyDelivery(outcome, laneId: laneId)
                flash(outcome.ok ? success : outcome.message)
            } catch {
                flash("已保存，但测试失败：\(error.localizedDescription)")
            }
        }
    }

    private func applyDelivery(_ outcome: SendOutcome, laneId: String) {
        let formatter = ISO8601DateFormatter()
        updateLane(laneId) { lane in
            lane.lastDelivery = LastDelivery(
                at: formatter.string(from: Date()),
                channel: outcome.channel,
                ok: outcome.ok,
                message: outcome.message
            )
        }
        persist()
    }

    private func updateLane(_ source: String, _ body: (inout LaneConfig) -> Void) {
        objectWillChange.send()
        config.updateLane(source, body)
    }

    private func openPrivacy(_ anchor: String) {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?\(anchor)",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private static func resolveLane(_ source: String) -> String {
        let s = source.lowercased()
        if s.contains("codex") { return "codex" }
        if s.contains("cursor") { return "cursor" }
        return "cursor"
    }
}
