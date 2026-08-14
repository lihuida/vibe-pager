import AppKit
import ApplicationServices
import Foundation

enum AgentKind: String {
    case cursor
    case codex

    var title: String {
        switch self {
        case .cursor: return "Cursor"
        case .codex: return "Codex"
        }
    }
}

enum TaskRouter {
    struct Command {
        var listTasks: Bool
        var taskId: String?
        var target: String
        var prompt: String
    }

    static func parse(_ text: String, fallback: String) -> Command {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "/tasks" || lower == "/task" || lower.hasPrefix("/tasks ") {
            return Command(listTasks: true, taskId: nil, target: fallback, prompt: "")
        }
        var rest = trimmed
        var taskId: String?
        if rest.hasPrefix("#") {
            let after = rest.dropFirst()
            let digits = after.prefix(while: \.isNumber)
            if !digits.isEmpty {
                taskId = String(digits)
                rest = String(after.dropFirst(digits.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let (target, prompt) = AgentBridge.parseTarget(from: rest, fallback: fallback)
        let finalPrompt = prompt.isEmpty && taskId != nil ? "请继续刚才的任务。" : prompt
        return Command(listTasks: false, taskId: taskId, target: target, prompt: finalPrompt)
    }

    static func followupPrompt(task: RemoteTask?, prompt: String) -> String {
        guard let task else { return prompt }
        var lines = ["【跟进任务 #\(task.id) · \(task.source)】"]
        if !task.cwd.isEmpty {
            lines.append("项目路径：\(task.cwd)")
        }
        lines.append(prompt)
        return lines.joined(separator: "\n")
    }
}

enum AgentBridge {
    static func deliver(to rawTarget: String, text: String, image: Data?) -> String {
        let kind = AgentKind(rawValue: rawTarget) ?? .cursor
        return deliver(to: kind, text: text, image: image)
    }

    static func deliver(to kind: AgentKind, text: String, image: Data?) -> String {
        guard ensureAccessibility() else {
            return "请在「系统设置 → 隐私与安全 → 辅助功能」里允许 Vibe Pager，才能把消息交给 \(kind.title)"
        }
        var prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.isEmpty {
            prompt = image == nil ? "" : "请查看用户发来的图片。"
        }
        guard !prompt.isEmpty || image != nil else {
            return "没有可发送的内容"
        }

        let board = NSPasteboard.general
        board.clearContents()
        var objects: [NSPasteboardWriting] = []
        if !prompt.isEmpty {
            objects.append(prompt as NSString)
        }
        if let image, let nsImage = NSImage(data: image) {
            objects.append(nsImage)
        }
        board.writeObjects(objects)

        switch kind {
        case .cursor:
            return pasteIntoApp(named: "Cursor", bundleHint: "Cursor") ? "已交给 Cursor" : "没找到 Cursor，请先打开它"
        case .codex:
            if pasteIntoCodex() {
                return "已交给 Codex"
            }
            return "没找到 Codex 窗口。请打开 Codex / 终端里的会话后再试"
        }
    }

    static func parseTarget(from text: String, fallback: String) -> (String, String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("/cursor") {
            return ("cursor", dropCommand(trimmed, "/cursor"))
        }
        if lower.hasPrefix("/codex") {
            return ("codex", dropCommand(trimmed, "/codex"))
        }
        if lower.hasPrefix("/c ") || lower == "/c" {
            return ("cursor", dropCommand(trimmed, "/c"))
        }
        if lower.hasPrefix("/x ") || lower == "/x" {
            return ("codex", dropCommand(trimmed, "/x"))
        }
        return (fallback, trimmed)
    }

    private static func dropCommand(_ text: String, _ command: String) -> String {
        let index = text.index(text.startIndex, offsetBy: min(command.count, text.count))
        return text[index...].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptTrust() -> Bool {
        ensureAccessibility()
    }

    private static func ensureAccessibility() -> Bool {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [prompt: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    private static func pasteIntoApp(named name: String, bundleHint: String) -> Bool {
        func find() -> NSRunningApplication? {
            let apps = NSWorkspace.shared.runningApplications
            return apps.first(where: { ($0.localizedName ?? "").localizedCaseInsensitiveContains(name) })
                ?? apps.first(where: { ($0.bundleIdentifier ?? "").localizedCaseInsensitiveContains(bundleHint) })
        }
        var app = find()
        if app == nil, name == "Cursor" {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Cursor.app"))
            Thread.sleep(forTimeInterval: 1.2)
            app = find()
        }
        guard let app else { return false }
        app.activate(options: [.activateIgnoringOtherApps])
        Thread.sleep(forTimeInterval: 0.45)
        return keystrokePasteEnter()
    }

    private static func pasteIntoCodex() -> Bool {
        let names = ["Codex", "iTerm2", "iTerm", "Warp", "Ghostty", "Alacritty", "kitty", "Terminal"]
        let apps = NSWorkspace.shared.runningApplications
        for name in names {
            if let app = apps.first(where: { ($0.localizedName ?? "").localizedCaseInsensitiveContains(name) }) {
                app.activate(options: [.activateIgnoringOtherApps])
                Thread.sleep(forTimeInterval: 0.45)
                return keystrokePasteEnter()
            }
        }
        return false
    }

    private static func keystrokePasteEnter() -> Bool {
        let source = """
        tell application "System Events"
          keystroke "v" using command down
          delay 0.12
          keystroke return
        end tell
        """
        var error: NSDictionary?
        if let script = NSAppleScript(source: source) {
            _ = script.executeAndReturnError(&error)
            return error == nil
        }
        return false
    }
}
