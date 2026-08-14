import AppKit
import CoreGraphics
import Foundation

enum ScreenShot {
    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestPermissionIfNeeded() {
        guard !CGPreflightScreenCaptureAccess() else { return }
        _ = CGRequestScreenCaptureAccess()
    }

    static func capture(appHint: String) -> Data? {
        guard hasPermission() else { return nil }
        let hints = windowHints(for: appHint)
        if let windowID = findWindowID(hints: hints) {
            if let data = captureWindow(windowID) { return ImagePrep.jpeg(data) }
        }
        if let data = captureDisplay() { return ImagePrep.jpeg(data) }
        return nil
    }

    static func loadFile(_ path: String) -> Data? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return ImagePrep.jpeg(data)
    }

    private static func windowHints(for source: String) -> [String] {
        switch source.lowercased() {
        case "cursor":
            return ["Cursor"]
        case "codex":
            return ["Codex", "iTerm2", "iTerm", "Warp", "Ghostty", "Terminal", "Alacritty", "Kitty"]
        default:
            return ["Cursor", "Codex"]
        }
    }

    private static func findWindowID(hints: [String]) -> CGWindowID? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        for hint in hints {
            for window in info {
                let layer = window[kCGWindowLayer as String] as? Int ?? 0
                guard layer == 0 else { continue }
                let owner = (window[kCGWindowOwnerName as String] as? String) ?? ""
                let title = (window[kCGWindowName as String] as? String) ?? ""
                let blob = owner + " " + title
                if blob.localizedCaseInsensitiveContains(hint) {
                    if let number = window[kCGWindowNumber as String] as? Int {
                        return CGWindowID(number)
                    }
                }
            }
        }
        return nil
    }

    private static func captureWindow(_ windowID: CGWindowID) -> Data? {
        let image = CGWindowListCreateImage(
            .null,
            [.optionIncludingWindow, .optionOnScreenBelowWindow],
            windowID,
            [.bestResolution, .boundsIgnoreFraming]
        )
        return pngData(image)
    }

    private static func captureDisplay() -> Data? {
        let image = CGWindowListCreateImage(
            .infinite,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution]
        )
        return pngData(image)
    }

    private static func pngData(_ image: CGImage?) -> Data? {
        guard let image else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        return rep.representation(using: .png, properties: [:])
    }
}

enum ImagePrep {
    static func jpeg(_ data: Data, maxBytes: Int = 1_400_000) -> Data {
        guard let image = NSImage(data: data) else { return data }
        var quality: CGFloat = 0.82
        var current = encode(image, quality: quality) ?? data
        while current.count > maxBytes, quality > 0.35 {
            quality -= 0.12
            if let next = encode(image, quality: quality) {
                current = next
            } else {
                break
            }
        }
        return current
    }

    private static func encode(_ image: NSImage, quality: CGFloat) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
