#if canImport(AppKit)
import AppKit

/// Borderless floating panel that can take keyboard focus without activating the app, so the
/// previously active app keeps its place and gets focus back when the launcher hides.
final class LauncherPanel: NSPanel {
    /// Return true to swallow a key-down before it reaches the search field (⌘1..⌘7, Esc).
    var keyEventInterceptor: ((NSEvent) -> Bool)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .utilityWindow
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let keyEventInterceptor, keyEventInterceptor(event) {
            return
        }
        super.sendEvent(event)
    }
}
#endif
