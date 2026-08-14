import Foundation

enum ChannelKind: String {
    case telegram, feishu, dingtalk, wechat
}

enum PasteGuess {
    case telegram(token: String)
    case feishuApp(id: String)
    case wechat(provider: String, token: String)
    case unknown
}

enum ChannelPaste {
    static func guess(_ raw: String) -> PasteGuess {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .unknown }

        if text.hasPrefix("cli_") {
            return .feishuApp(id: firstToken(in: text))
        }
        if text.contains("qyapi.weixin.qq.com") {
            return .wechat(provider: "wecom", token: firstURL(in: text) ?? text)
        }
        if text.hasPrefix("AT_") {
            return .wechat(provider: "wxpusher", token: firstToken(in: text))
        }
        if isTelegramToken(text) {
            return .telegram(token: firstTelegramToken(in: text) ?? text)
        }
        if text.count >= 16, text.rangeOfCharacter(from: .letters) != nil, !text.contains("://") {
            return .wechat(provider: "pushplus", token: firstToken(in: text))
        }
        return .unknown
    }

    static func guideURL(for kind: ChannelKind) -> URL {
        switch kind {
        case .telegram:
            return URL(string: "https://t.me/BotFather")!
        case .feishu:
            return URL(string: "https://open.feishu.cn/app")!
        case .dingtalk:
            return URL(string: "https://open-dev.dingtalk.com/fe/app")!
        case .wechat:
            return URL(string: "https://wxpusher.zjiecode.com/")!
        }
    }

    private static func isTelegramToken(_ text: String) -> Bool {
        firstTelegramToken(in: text) != nil
    }

    private static func firstTelegramToken(in text: String) -> String? {
        let pattern = #"\d{6,}:[A-Za-z0-9_-]{20,}"#
        return firstMatch(pattern, in: text)
    }

    private static func firstURL(in text: String) -> String? {
        firstMatch(#"https?://[^\s]+"#, in: text)
    }

    private static func firstToken(in text: String) -> String {
        text.split { $0.isWhitespace || $0.isNewline }.map(String.init).first ?? text
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return String(text[swiftRange])
    }
}
