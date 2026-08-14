import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(Palette.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showSettings {
                        settingsPage
                    } else {
                        homePage
                    }
                }
                .padding(16)
            }
            Divider().overlay(Palette.line)
            footer
        }
        .frame(width: 392, height: 640)
        .background(Palette.canvas)
        .preferredColorScheme(.light)
        .tint(Palette.accent)
        .onAppear {
            store.refreshPermissions()
            store.refreshInstalled()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.refreshPermissions()
            store.refreshInstalled()
        }
        .overlay(alignment: .bottom) {
            if !store.toast.isEmpty {
                Text(store.toast)
                    .font(.callout)
                    .foregroundColor(Palette.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
                    .padding(.bottom, 52)
                    .padding(.horizontal, 16)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            if showSettings {
                Button {
                    showSettings = false
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Palette.ink)
                        .frame(width: 28, height: 28)
                        .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("设置")
                        .font(.headline)
                        .foregroundColor(Palette.ink)
                    Text("系统权限")
                        .font(.caption)
                        .foregroundColor(Palette.muted)
                }
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vibe Pager")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(Palette.ink)
                    Text("远程收消息，也能发指令")
                        .font(.caption)
                        .foregroundColor(Palette.muted)
                }
                Spacer()
                Button {
                    showSettings = true
                    store.refreshPermissions()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Palette.ink)
                            .frame(width: 28, height: 28)
                            .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Palette.line, lineWidth: 1))
                        if !store.accessibilityOn || !store.screenCaptureOn {
                            Circle()
                                .fill(Color(red: 0.86, green: 0.52, blue: 0.16))
                                .frame(width: 7, height: 7)
                                .offset(x: 1, y: -1)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("设置")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var homePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.visibleLanes.isEmpty {
                banner("没有检测到 Cursor 或 Codex。装好后重新打开面板即可。")
            } else {
                if store.visibleLanes.count > 1 {
                    laneTabs
                }
                remoteCard
                if store.remoteEnabled && !store.current.activeReady {
                    banner("远程已开。在这个页签里选一个通道，按步骤完成配置。")
                }
                if !store.serverOk {
                    banner(store.serverError.isEmpty ? "本机接收服务尚未就绪，请保持应用运行。" : store.serverError)
                }
                sectionTitle(
                    "通道",
                    trailing: store.current.activeReady ? "已连接" : "未连接",
                    trailingColor: store.current.activeReady ? Palette.ok : Palette.muted
                )
                channelPicker
                channelSetup
            }
        }
    }

    private var installedNames: [String] {
        store.visibleLanes.map { $0 == "codex" ? "Codex" : "Cursor" }
    }

    private var permissionHint: String {
        switch installedNames.count {
        case 0:
            return "回消息需要辅助功能；主动发截图时需要屏幕录制。"
        case 1:
            return "回消息需要辅助功能；主动发截图时需要屏幕录制。"
        default:
            return "Cursor 和 Codex 共用。回消息需要辅助功能；主动发截图时需要屏幕录制。"
        }
    }

    private var pasteHint: String {
        switch installedNames.count {
        case 1:
            return "把手机消息粘贴进 \(installedNames[0])"
        default:
            return "把手机消息粘贴进 Cursor / Codex"
        }
    }

    private var settingsPage: some View {
        permissionCard
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("系统权限")
                    .font(.headline)
                    .foregroundColor(Palette.ink)
                Text(permissionHint)
                    .font(.caption)
                    .foregroundColor(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            permissionRow(
                title: "辅助功能",
                detail: pasteHint,
                on: store.accessibilityOn,
                action: { store.openAccessibilitySettings() }
            )
            permissionRow(
                title: "屏幕录制",
                detail: "主动发截图时截取窗口画面",
                on: store.screenCaptureOn,
                action: { store.openScreenCaptureSettings() }
            )
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private func permissionRow(title: String, detail: String, on: Bool, action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(on ? Palette.accent : Color(red: 0.86, green: 0.52, blue: 0.16))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Palette.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(Palette.muted)
            }
            Spacer(minLength: 8)
            if on {
                Text("已开启")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Palette.accent)
            } else {
                Button("去打开", action: action)
                    .buttonStyle(AccentButtonStyle())
            }
        }
    }

    private var laneTabs: some View {
        HStack(spacing: 8) {
            ForEach(store.visibleLanes, id: \.self) { id in
                laneTab(
                    id: id,
                    title: id == "codex" ? "Codex" : "Cursor",
                    ready: id == "codex" ? store.config.codex.activeReady : store.config.cursor.activeReady
                )
            }
        }
    }

    private func laneTab(id: String, title: String, ready: Bool) -> some View {
        let selected = store.selectedLane == id
        return Button {
            store.selectLane(id)
        } label: {
            HStack(spacing: 8) {
                BrandMark(id: id, onAccent: selected, size: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(selected ? .white : Palette.ink)
                    Text(ready ? "已连接" : "未连接")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(ready ? (selected ? Color.white : Palette.ok) : (selected ? Color.white.opacity(0.78) : Palette.muted))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.accent : Palette.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selected ? Palette.accent : Palette.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var remoteCard: some View {
        let name = store.selectedLane == "codex" ? "Codex" : "Cursor"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        BrandMark(id: store.selectedLane, onAccent: false, size: 14)
                        Text("\(name) 远程通讯")
                            .font(.caption)
                            .foregroundColor(Palette.muted)
                    }
                    Text(store.remoteEnabled ? "已开启" : "已关闭")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(Palette.ink)
                    Text("开启后，可在通道里收\(name)的任务消息，也能把指令发回去")
                        .font(.caption)
                        .foregroundColor(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { store.remoteEnabled },
                    set: { store.remoteEnabled = $0 }
                ))
                .toggleStyle(.switch)
                .tint(Palette.accent)
                .labelsHidden()
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private var channelPicker: some View {
        let items: [(String, String)] = [
            ("feishu", "飞书"),
            ("dingtalk", "钉钉"),
            ("wechat", "微信"),
            ("telegram", "Telegram"),
        ]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(items, id: \.0) { id, title in
                Button {
                    store.activeChannel = id
                } label: {
                    HStack(spacing: 6) {
                        BrandMark(id: id, onAccent: store.activeChannel == id, size: 16)
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(store.activeChannel == id ? .white : Palette.ink)
                    .background(
                        store.activeChannel == id ? Palette.accent : Palette.card,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(store.activeChannel == id ? Palette.accent : Palette.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var channelSetup: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch store.activeChannel {
            case "feishu":
                botSetup(
                    title: "飞书",
                    kind: .feishu,
                    appPlaceholder: "App ID cli_…",
                    steps: [
                        "点下面打开飞书开发者后台",
                        "创建企业自建应用，开通机器人能力并发布",
                        "复制 App ID、App Secret，点连接",
                        "事件订阅选「使用长连接接收事件」，并订阅「接收消息」",
                        "在飞书搜索这个机器人，打开单聊发一句「你好」",
                    ]
                )
            case "dingtalk":
                botSetup(
                    title: "钉钉",
                    kind: .dingtalk,
                    appPlaceholder: "Client ID",
                    steps: [
                        "点下面打开钉钉开发者后台",
                        "创建企业内部应用，添加机器人，消息接收选 Stream",
                        "复制 Client ID、Client Secret，点连接",
                        "在钉钉搜索这个机器人，打开单聊发一句「你好」",
                    ]
                )
            case "wechat":
                wechatSetup
            default:
                telegramSetup
            }
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.line, lineWidth: 1))
    }

    private var telegramSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                BrandMark(id: "telegram", size: 16)
                Text("怎么配置 Telegram")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Palette.ink)
            }
            steps([
                "点下面按钮打开 BotFather",
                "发送 /newbot，按提示创建机器人",
                "复制 Token（形如 123456:AA…）粘贴，点连接",
                "给机器人发一句 /start",
            ])
            if store.current.telegram.isReady {
                Text("已连接 @\(store.current.telegram.botUsername.isEmpty ? "bot" : store.current.telegram.botUsername)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Palette.ok)
                connectedActions("telegram")
            } else {
                TextField("123456:AA…", text: store.binding(\.telegram.botToken))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(store.telegramBinding ? "等待 /start…" : "连接") {
                        store.connectTelegram()
                    }
                    .buttonStyle(AccentButtonStyle(disabled: store.telegramBinding || store.current.telegram.botToken.isEmpty))
                    .disabled(store.telegramBinding || store.current.telegram.botToken.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("打开 BotFather") { store.openGuide(for: .telegram) }
                        .buttonStyle(QuietButtonStyle())
                    if store.telegramBinding {
                        Button("停止") { store.cancelTelegramBind() }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }
    }

    private func botSetup(title: String, kind: ChannelKind, appPlaceholder: String, steps: [String]) -> some View {
        let ready = kind == .feishu ? store.current.feishu.isReady : store.current.dingtalk.isReady
        let waiting = kind == .feishu
            ? (store.current.feishu.canReceive && !store.current.feishu.isReady)
            : (store.current.dingtalk.canReceive && !store.current.dingtalk.isReady)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                BrandMark(id: kind.rawValue, size: 16)
                Text("怎么配置\(title)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Palette.ink)
            }
            self.steps(steps, firstLink: "打开开发者后台") {
                store.openGuide(for: kind)
            }
            if ready {
                Text("已绑定单聊")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Palette.ok)
                connectedActions(kind.rawValue)
            } else {
                TextField(appPlaceholder, text: webhookAppId(kind.rawValue))
                    .textFieldStyle(.roundedBorder)
                SecureField("Secret", text: webhookAppSecret(kind.rawValue))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(waiting ? "等待单聊…" : "连接") { store.connectBot(kind.rawValue) }
                        .buttonStyle(AccentButtonStyle(disabled: store.busy))
                        .disabled(store.busy)
                }
                if waiting {
                    Text("请打开机器人单聊发一句「你好」")
                        .font(.caption)
                        .foregroundColor(Palette.accent)
                }
            }
        }
    }

    private var wechatSetup: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                BrandMark(id: "wechat", size: 16)
                Text("扫码绑定微信")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Palette.ink)
            }
            Text("打开就能扫。用微信扫一扫；如果手机弹出数字，填到下面。连上后再在对话里发一句「你好」。")
                .font(.caption)
                .foregroundColor(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            if store.current.wechat.isReady {
                Text("已绑定微信")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Palette.ok)
                connectedActions("wechat")
            } else if store.current.wechat.isLoggedIn {
                Text(store.wechatHint.isEmpty ? "已登录。请在微信里发一句「你好」" : store.wechatHint)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                Button("重新扫码") {
                    store.disconnect("wechat")
                    store.startWeChatQR()
                }
                .buttonStyle(QuietButtonStyle())
            } else {
                wechatQRPanel
                if store.wechatNeedsVerify {
                    TextField("手机上显示的数字", text: $store.wechatVerifyCode)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { store.submitWeChatVerify() }
                    Text("扫码后微信会显示一组数字，填上再点提交。")
                        .font(.caption)
                        .foregroundColor(Palette.muted)
                    Button("提交数字") { store.submitWeChatVerify() }
                        .buttonStyle(AccentButtonStyle(disabled: store.wechatVerifyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
                        .disabled(store.wechatVerifyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Button(store.wechatQRWaiting ? "等待扫码…" : "重新生成二维码") {
                        store.startWeChatQR()
                    }
                    .buttonStyle(AccentButtonStyle(disabled: store.wechatQRWaiting))
                    .disabled(store.wechatQRWaiting)
                    if store.wechatQRWaiting {
                        Button("停止") { store.cancelWeChatQR() }
                            .buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }
        .onAppear { store.ensureWeChatLogin() }
    }

    private var wechatQRPanel: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Palette.line, lineWidth: 1)
                if let qr = store.wechatQR {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 168, height: 168)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 36, weight: .medium))
                            .foregroundColor(Palette.muted)
                        Text("正在生成二维码…")
                            .font(.caption)
                            .foregroundColor(Palette.muted)
                    }
                }
            }
            .frame(width: 196, height: 196)
            .frame(maxWidth: .infinity)
            Text(store.wechatHint.isEmpty ? "请用微信扫一扫" : store.wechatHint)
                .font(.caption.weight(.semibold))
                .foregroundColor(Palette.accent)
                .frame(maxWidth: .infinity)
        }
    }

    private func steps(_ items: [String], firstLink: String? = nil, firstAction: (() -> Void)? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 18, height: 18)
                        .background(Palette.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(text)
                            .font(.caption)
                            .foregroundColor(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if index == 0, let firstLink, let firstAction {
                            Button(firstLink, action: firstAction)
                                .buttonStyle(.plain)
                                .font(.caption.weight(.medium))
                                .foregroundColor(Palette.accent)
                        }
                    }
                }
            }
        }
    }

    private func connectedActions(_ id: String) -> some View {
        HStack {
            Button("发送测试") { store.test(id) }
                .buttonStyle(AccentButtonStyle(disabled: store.busy))
                .disabled(store.busy)
            Button("断开") { store.disconnect(id) }
                .buttonStyle(QuietButtonStyle())
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if let last = store.current.lastDelivery {
                Text("\(last.ok ? "上次推送成功" : "上次推送失败") · \(channelName(last.channel))")
                    .font(.caption)
                    .foregroundColor(Palette.muted)
                    .lineLimit(1)
            } else {
                Text(store.visibleLanes.isEmpty
                     ? "还没有推送记录"
                     : (store.selectedLane == "codex" ? "Codex 还没有推送记录" : "Cursor 还没有推送记录"))
                    .font(.caption)
                    .foregroundColor(Palette.muted)
            }
            Spacer()
            Button("退出") { store.quit() }
                .buttonStyle(.plain)
                .foregroundColor(Palette.muted)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Palette.card)
    }

    private func sectionTitle(_ title: String, trailing: String?, trailingColor: Color = Palette.muted) -> some View {
        HStack {
            Text(title).font(.headline).foregroundColor(Palette.ink)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption.weight(trailingColor == Palette.ok ? .semibold : .regular))
                    .foregroundColor(trailingColor)
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundColor(Palette.ink)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.banner, in: RoundedRectangle(cornerRadius: 8))
    }

    private func channelName(_ id: String) -> String {
        switch id {
        case "telegram": return "Telegram"
        case "feishu": return "飞书"
        case "dingtalk": return "钉钉"
        case "wechat": return "微信"
        default: return id
        }
    }

    private func webhookAppId(_ kind: String) -> Binding<String> {
        kind == "feishu" ? store.binding(\.feishu.appId) : store.binding(\.dingtalk.appId)
    }

    private func webhookAppSecret(_ kind: String) -> Binding<String> {
        kind == "feishu" ? store.binding(\.feishu.appSecret) : store.binding(\.dingtalk.appSecret)
    }
}
