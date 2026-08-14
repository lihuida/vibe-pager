import AppKit
import SwiftUI

@main
struct VibeRemoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var store: AppStore?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.processName = "Vibe Pager"
        NSApp.appearance = NSAppearance(named: .aqua)

        let store = AppStore()
        self.store = store

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.statusItemImage()
            button.title = ""
            button.toolTip = "Vibe Pager"
            button.imagePosition = .imageOnly
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
    }

    private static func statusItemImage() -> NSImage {
        let names = ["StatusItem@2x", "StatusItem"]
        for name in names {
            if let url = Bundle.main.url(forResource: name, withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                let pixels = (image.representations.first as? NSBitmapImageRep)
                let aspect = pixels.map { CGFloat($0.pixelsWide) / CGFloat(max($0.pixelsHigh, 1)) } ?? 1
                let height: CGFloat = 18
                image.size = NSSize(width: (height * aspect).rounded(.toNearestOrAwayFromZero), height: height)
                image.isTemplate = true
                return image
            }
        }
        let fallback = NSImage(systemSymbolName: "hare", accessibilityDescription: "Vibe Pager")
        fallback?.isTemplate = true
        return fallback ?? NSImage()
    }

    @objc private func togglePanel() {
        guard let panel, let button = statusItem?.button, let buttonWindow = button.window else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            return
        }
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
        Task { @MainActor in
            store?.refreshPermissions()
            store?.refreshInstalled()
        }
        panel.setFrameOrigin(origin)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
