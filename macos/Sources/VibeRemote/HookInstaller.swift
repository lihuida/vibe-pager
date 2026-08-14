import Foundation

enum HookInstaller {
    private static let markerBegin = "# vibe-remote-begin"
    private static let markerEnd = "# vibe-remote-end"

    static func sync(_ config: AppConfig) -> [String] {
        syncAgentSkills(config)
        var notes = [syncSendScript(config)]
        if InstalledTools.hasCursor() { notes.append(syncCursor(config)) }
        if InstalledTools.hasCodex() { notes.append(syncCodex(config)) }
        return notes.compactMap { $0 }
    }

    private static func home() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    private static func writeExec(_ url: URL, _ contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func cursorScript(port: UInt16) -> String {
        """
        #!/bin/bash
        export VIBE_PORT="\(port)"
        export VIBE_CWD="$PWD"
        ruby -e '
        require "json"
        require "net/http"
        require "uri"
        require "shellwords"

        def pick_text(obj)
          return "" unless obj.is_a?(Hash)
          %w[last_assistant_message text].each do |k|
            v = obj[k]
            return v.strip if v.is_a?(String) && !v.strip.empty?
          end
          ""
        end

        def text_from(o, roles)
          return "" unless o.is_a?(Hash)
          typ = o["type"].to_s
          role = o["role"].to_s
          return "" unless roles.include?(typ) || roles.include?(role)
          msg = o["message"].is_a?(Hash) ? o["message"] : o
          c = msg["content"]
          return c.strip if c.is_a?(String) && !c.strip.empty?
          if c.is_a?(Array)
            parts = c.map { |p|
              next p.strip if p.is_a?(String)
              next "" unless p.is_a?(Hash)
              next "" if %w[tool_use tool_result thinking thought].include?(p["type"].to_s)
              (p["text"] || p["content"]).to_s
            }.map(&:strip).reject(&:empty?)
            return parts.join("\\n")
          end
          o["text"].to_s.strip
        end

        def last_role(path, roles)
          return "" if path.to_s.empty? || !File.file?(path)
          last = ""
          File.foreach(path) do |line|
            begin
              o = JSON.parse(line)
            rescue
              next
            end
            t = text_from(o, roles)
            last = t unless t.empty?
          end
          last
        end

        def conversation_id(body)
          %w[conversation_id conversationId composer_id composerId].each do |k|
            v = body[k].to_s.strip
            return v unless v.empty?
          end
          ""
        end

        def conversation_title(id)
          return "" if id.empty?
          db = File.expand_path("~/Library/Application Support/Cursor/User/globalStorage/state.vscdb")
          return "" unless File.file?(db)
          esc = id.gsub("'", "''")
          q1 = "SELECT json_extract(value,'$.name') FROM composerHeaders WHERE composerId='#{esc}' LIMIT 1;"
          name = `sqlite3 -readonly #{db.shellescape} "#{q1}" 2>/dev/null`.to_s.strip
          return name unless name.empty? || name == "null"
          q2 = "SELECT json_extract(value,'$.name') FROM cursorDiskKV WHERE key='composerData:#{esc}' LIMIT 1;"
          name = `sqlite3 -readonly #{db.shellescape} "#{q2}" 2>/dev/null`.to_s.strip
          name == "null" ? "" : name
        end

        raw = STDIN.read.to_s
        body = (JSON.parse(raw) rescue nil)
        body = {} unless body.is_a?(Hash)
        roots = body["workspace_roots"]
        if roots.is_a?(Array) && !roots.first.to_s.empty?
          body["cwd"] = roots.first
        else
          body["cwd"] ||= ENV["VIBE_CWD"].to_s
        end
        cid = conversation_id(body)
        body["conversation_id"] = cid unless cid.empty?
        title = body["conversation_title"].to_s.strip
        title = conversation_title(cid) if title.empty?
        body["conversation_title"] = title unless title.empty?
        path = body["transcript_path"]
        if pick_text(body).empty?
          t = last_role(path, %w[assistant])
          body["text"] = t unless t.empty?
        end
        event = body["hook_event_name"].to_s
        if event == "stop" && pick_text(body).empty?
          puts "{}"
          exit 0
        end
        uri = URI("http://127.0.0.1:#{ENV["VIBE_PORT"]}/hook")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["X-Vibe-Source"] = "cursor"
        req.body = JSON.generate(body)
        Net::HTTP.start(uri.hostname, uri.port, open_timeout: 2, read_timeout: 3) { |http| http.request(req) }
        ' >/dev/null 2>&1 || true
        echo '{}'
        """
    }

    private static func codexScript(port: UInt16) -> String {
        """
        #!/bin/bash
        payload="$1"
        if [ -z "$payload" ]; then
          payload="$(cat)"
        fi
        export VIBE_PORT="\(port)"
        export VIBE_CWD="$PWD"
        export VIBE_BODY="$payload"
        ruby -e '
        require "json"
        require "net/http"
        require "uri"
        raw = ENV["VIBE_BODY"].to_s
        body = (JSON.parse(raw) rescue {"summary" => raw})
        body = {} unless body.is_a?(Hash)
        body["cwd"] ||= ENV["VIBE_CWD"].to_s
        uri = URI("http://127.0.0.1:#{ENV["VIBE_PORT"]}/hook")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["X-Vibe-Source"] = "codex"
        req.body = JSON.generate(body)
        Net::HTTP.start(uri.hostname, uri.port, open_timeout: 2, read_timeout: 3) { |http| http.request(req) }
        ' >/dev/null 2>&1 || true
        echo '{}'
        """
    }

    private static func syncCursor(_ config: AppConfig) -> String? {
        let hooksDir = home().appendingPathComponent(".cursor/hooks")
        let script = hooksDir.appendingPathComponent("vibe-remote.sh")
        do {
            try writeExec(script, cursorScript(port: config.listenPort))
            let jsonURL = home().appendingPathComponent(".cursor/hooks.json")
            var root: [String: Any] = ["version": 1, "hooks": [String: Any]()]
            if let data = try? Data(contentsOf: jsonURL),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                root = parsed
            }
            root["version"] = root["version"] ?? 1
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            upsertCursorHook(&hooks, key: "stop", enabled: config.cursorEnabled)
            upsertCursorHook(&hooks, key: "afterAgentResponse", enabled: config.cursorEnabled)
            root["hooks"] = hooks
            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: jsonURL, options: .atomic)
            return config.cursorEnabled ? "已接入 Cursor，完工回复会推到手机" : "已关闭 Cursor 接入"
        } catch {
            return "Cursor 接入失败：\(error.localizedDescription)"
        }
    }

    private static func upsertCursorHook(_ hooks: inout [String: Any], key: String, enabled: Bool) {
        var list = hooks[key] as? [[String: Any]] ?? []
        list.removeAll { (($0["command"] as? String) ?? "").contains("vibe-remote") }
        if enabled {
            list.append(["command": "./hooks/vibe-remote.sh"])
        }
        if list.isEmpty {
            hooks.removeValue(forKey: key)
        } else {
            hooks[key] = list
        }
    }

    private static func syncCodex(_ config: AppConfig) -> String? {
        let vibeDir = home().appendingPathComponent(".vibe-remote")
        let script = vibeDir.appendingPathComponent("codex-notify.sh")
        do {
            try writeExec(script, codexScript(port: config.listenPort))
            try syncCodexNotify(enabled: config.codexEnabled, scriptPath: script.path)
            try syncCodexHooksJSON(enabled: config.codexEnabled, scriptPath: script.path)
            return config.codexEnabled ? "已接入 Codex notify 与 Stop hook" : "已关闭 Codex 接入"
        } catch {
            return "Codex 接入失败：\(error.localizedDescription)"
        }
    }

    private static func syncCodexNotify(enabled: Bool, scriptPath: String) throws {
        let tomlURL = home().appendingPathComponent(".codex/config.toml")
        try FileManager.default.createDirectory(at: tomlURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var text = (try? String(contentsOf: tomlURL, encoding: .utf8)) ?? ""
        text = stripMarkedBlock(text)
        if enabled {
            let block = """

            \(markerBegin)
            notify = ["\(scriptPath)"]
            \(markerEnd)
            """
            if !text.hasSuffix("\n") { text += "\n" }
            text += block
        }
        try text.write(to: tomlURL, atomically: true, encoding: .utf8)
    }

    private static func syncCodexHooksJSON(enabled: Bool, scriptPath: String) throws {
        let jsonURL = home().appendingPathComponent(".codex/hooks.json")
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: jsonURL),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = parsed
        }
        var stop = root["Stop"] as? [[String: Any]] ?? []
        stop = stop.compactMap { group in
            var copy = group
            var hooks = copy["hooks"] as? [[String: Any]] ?? []
            hooks.removeAll { commandLooksOurs($0["command"] as? String) }
            if hooks.isEmpty, group["hooks"] != nil {
                return nil
            }
            copy["hooks"] = hooks
            return copy
        }
        if enabled {
            let hook: [String: Any] = [
                "type": "command",
                "command": scriptPath,
                "timeout": 5,
            ]
            stop.append(["hooks": [hook]])
        }
        if stop.isEmpty {
            root.removeValue(forKey: "Stop")
        } else {
            root["Stop"] = stop
        }
        if root.isEmpty {
            if FileManager.default.fileExists(atPath: jsonURL.path) {
                try FileManager.default.removeItem(at: jsonURL)
            }
            return
        }
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: jsonURL, options: .atomic)
    }

    private static func commandLooksOurs(_ command: String?) -> Bool {
        guard let command else { return false }
        return command.contains("codex-notify.sh") || command.contains("vibe-remote")
    }

    private static func stripMarkedBlock(_ text: String) -> String {
        var result = text
        while let start = result.range(of: markerBegin),
              let endSearch = result.range(of: markerEnd, range: start.lowerBound..<result.endIndex) {
            let after = endSearch.upperBound
            var removalEnd = after
            if after < result.endIndex, result[after] == "\n" {
                removalEnd = result.index(after: after)
            }
            var removalStart = start.lowerBound
            if removalStart > result.startIndex {
                let prev = result.index(before: removalStart)
                if result[prev] == "\n" { removalStart = prev }
            }
            result.removeSubrange(removalStart..<removalEnd)
        }
        // Also drop a leftover notify line we may have written before markers existed.
        let lines = result.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        result = lines.filter { !$0.contains("codex-notify.sh") }.joined(separator: "\n")
        return result
    }

    private static func syncSendScript(_ config: AppConfig) -> String? {
        let script = home().appendingPathComponent(".vibe-remote/send.sh")
        do {
            try writeExec(script, sendScript(port: config.listenPort))
            return nil
        } catch {
            return "发图脚本写入失败：\(error.localizedDescription)"
        }
    }

    private static func sendScript(port: UInt16) -> String {
        """
        #!/bin/bash
        PORT="\(port)"
        SOURCE="agent"
        IMAGE=""
        SHOT=0
        TEXT=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --shot) SHOT=1; shift ;;
            --image) IMAGE="${2:-}"; shift 2 ;;
            --source) SOURCE="${2:-agent}"; shift 2 ;;
            --port) PORT="${2:-17800}"; shift 2 ;;
            *) TEXT="${TEXT:+$TEXT }$1"; shift ;;
          esac
        done
        DIR="$HOME/.vibe-remote"
        mkdir -p "$DIR"
        if [ "$SHOT" = "1" ]; then
          IMAGE="$DIR/agent-shot.png"
          /usr/sbin/screencapture -x -t png "$IMAGE" || true
        fi
        export VIBE_TEXT="$TEXT"
        export VIBE_IMAGE="$IMAGE"
        export VIBE_SOURCE="$SOURCE"
        export VIBE_PORT="$PORT"
        ruby -e '
        require "json"
        require "net/http"
        require "uri"
        image = ENV["VIBE_IMAGE"].to_s
        body = {
          "summary" => ENV["VIBE_TEXT"].to_s.empty? ? "发来一张截图" : ENV["VIBE_TEXT"],
          "skip_capture" => true
        }
        body["image_path"] = image unless image.empty?
        uri = URI("http://127.0.0.1:#{ENV["VIBE_PORT"]}/hook")
        req = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        req["X-Vibe-Source"] = ENV["VIBE_SOURCE"]
        req.body = JSON.generate(body)
        Net::HTTP.start(uri.hostname, uri.port, open_timeout: 2, read_timeout: 6) { |http| http.request(req) }
        ' >/dev/null 2>&1 || true
        echo '{}'
        """
    }

    private static func syncAgentSkills(_ config: AppConfig) {
        let enabled = config.cursorEnabled || config.codexEnabled
        let skill = skillMarkdown()
        writeSkill(home().appendingPathComponent(".cursor/skills/vibe-remote/SKILL.md"), contents: enabled && config.cursorEnabled ? skill : nil)
        writeSkill(home().appendingPathComponent(".codex/skills/vibe-remote/SKILL.md"), contents: enabled && config.codexEnabled ? skill : nil)
    }

    private static func writeSkill(_ url: URL, contents: String?) {
        do {
            if let contents {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try contents.write(to: url, atomically: true, encoding: .utf8)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            return
        }
    }

    private static func skillMarkdown() -> String {
        """
        ---
        name: vibe-remote
        description: Send a screenshot or progress note to the user's phone via Feishu / DingTalk / WeChat / Telegram. Use when the user is remote, asks to share a screenshot, or after finishing a visual change.
        ---

        用户通过 Vibe Pager 在手机上收完工消息。需要让对方看见界面时，在本机执行：

        ```bash
        ~/.vibe-remote/send.sh --shot --source cursor "改了什么，一句话即可"
        ```

        Codex 把 `--source` 换成 `codex`。已有图片文件时用 `--image /path/to.png`，不要 `--shot`。

        远程通讯关闭或 Vibe Pager 未运行时，这条命令会静默失败，不要重试很久。
        """
    }
}
