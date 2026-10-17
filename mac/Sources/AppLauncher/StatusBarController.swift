#if canImport(AppKit)
import AppKit

/// Menu-bar icon: left click toggles the launcher, right click shows "열기 / 종료".
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let onToggle: () -> Void
    private let onOpen: () -> Void
    private let onQuit: () -> Void

    init(onToggle: @escaping () -> Void, onOpen: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onOpen = onOpen
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "App Launcher")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "App Launcher"
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let openItem = NSMenuItem(title: "열기", action: #selector(openClicked), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "종료", action: #selector(quitClicked), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func buttonClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            // Attach the menu only while it is open so a plain left click keeps toggling the window.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onToggle()
        }
    }

    @objc private func openClicked() {
        onOpen()
    }

    @objc private func quitClicked() {
        onQuit()
    }
}
#endif
