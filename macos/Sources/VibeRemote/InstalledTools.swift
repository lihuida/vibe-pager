import AppKit
import Foundation

enum InstalledTools {
    static func hasCursor() -> Bool {
        if appExists(named: "Cursor.app") { return true }
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") != nil {
            return true
        }
        return false
    }

    static func hasCodex() -> Bool {
        if appExists(named: "Codex.app") { return true }
        return executableExists("codex")
    }

    static func visibleLanes() -> [String] {
        var lanes: [String] = []
        if hasCursor() { lanes.append("cursor") }
        if hasCodex() { lanes.append("codex") }
        return lanes
    }

    private static func appExists(named fileName: String) -> Bool {
        let fm = FileManager.default
        let roots = [
            "/Applications",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
            "/System/Applications",
        ]
        return roots.contains { fm.fileExists(atPath: ($0 as NSString).appendingPathComponent(fileName)) }
    }

    private static func executableExists(_ name: String) -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.cargo/bin",
            "/opt/homebrew/opt/codex/bin",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs.append(contentsOf: path.split(separator: ":").map(String.init))
        }
        if let nvm = try? fm.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            dirs.append(contentsOf: nvm.map { "\(home)/.nvm/versions/node/\($0)/bin" })
        }
        if dirs.contains(where: { fm.isExecutableFile(atPath: ($0 as NSString).appendingPathComponent(name)) }) {
            return true
        }
        return which(name)
    }

    private static func which(_ name: String) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "command -v \(name)"]
        task.environment = [
            "HOME": NSHomeDirectory(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:/usr/bin:/bin",
        ]
        task.standardOutput = Pipe()
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
