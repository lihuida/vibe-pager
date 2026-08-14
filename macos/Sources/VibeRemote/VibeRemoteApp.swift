import AppKit
import SwiftUI

@main
enum VibePagerMain {
    static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var store: AppStore?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("menu bar extra")
        ProcessInfo.processInfo.disableSuddenTermination()
        ProcessInfo.processInfo.processName = "Vibe Pager"
        NSApp.setActivationPolicy(.accessory)
        NSApp.appearance = NSAppearance(named: .aqua)

        let store = AppStore()
        self.store = store

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true
        if let button = item.button {
            let image = Self.statusItemImage()
            button.image = image
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "Vibe Pager"
            if image.size.width < 8 {
                button.title = "Vibe"
                button.imagePosition = .noImage
            } else {
                button.title = ""
                button.imagePosition = .imageOnly
            }
            button.target = self
            button.action = #selector(togglePanel)
        }
        statusItem = item

        let hosting = NSHostingView(rootView: RootView().environmentObject(store))
        hosting.frame = NSRect(x: 0, y: 0, width: 392, height: 640)

        let panel = NSPanel(
            contentRect: hosting.frame,
            styleMask: [.nonactivatingPanel, .titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.title = "Vibe Pager"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = NSColor(red: 246 / 255, green: 247 / 255, blue: 252 / 255, alpha: 1)
        panel.contentView = hosting
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.panel = panel

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let panel = self?.panel, panel.isVisible else { return }
            panel.orderOut(nil)
        }

        if shouldRevealOnLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showPanel()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    private var shouldRevealOnLaunch: Bool {
        if CommandLine.arguments.contains("--reveal") {
            return true
        }
        let key = "didRevealPanelOnce"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
            return true
        }
        return false
    }

    private static func statusItemImage() -> NSImage {
        if let named = NSImage(named: "StatusItem") {
            return configuredStatusImage(named)
        }
        for name in ["StatusItem", "StatusItem@2x"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                return configuredStatusImage(image)
            }
        }
        if let symbol = NSImage(systemSymbolName: "hare.fill", accessibilityDescription: "Vibe Pager") {
            let configured = symbol.withSymbolConfiguration(.init(pointSize: 14, weight: .medium)) ?? symbol
            configured.isTemplate = true
            return configured
        }
        return NSImage(size: NSSize(width: 18, height: 18))
    }

    private static func configuredStatusImage(_ image: NSImage) -> NSImage {
        image.isTemplate = true
        let pixels = image.representations.first as? NSBitmapImageRep
        let aspect = pixels.map { CGFloat($0.pixelsWide) / CGFloat(max($0.pixelsHigh, 1)) } ?? 1
        let height: CGFloat = 18
        let width = max(18, (height * aspect).rounded(.toNearestOrAwayFromZero))
        image.size = NSSize(width: width, height: height)
        return image
    }

    @objc private func togglePanel() {
        if panel?.isVisible == true {
            panel?.orderOut(nil)
            return
        }
        showPanel()
    }

    private func showPanel() {
        guard let panel else { return }
        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            var origin = NSPoint(
                x: screenRect.midX - panel.frame.width / 2,
                y: screenRect.minY - panel.frame.height - 6
            )
            if let screen = buttonWindow.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
                if origin.y < visible.minY {
                    origin.y = screenRect.maxY + 6
                }
            }
            panel.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 12,
                y: visible.maxY - panel.frame.height - 8
            ))
        }
        Task { @MainActor in
            store?.refreshPermissions()
            store?.refreshInstalled()
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
