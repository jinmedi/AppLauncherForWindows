#if canImport(AppKit)
import AppKit

/// Owns the panel and the launcher view: shows it centred near the top of the screen under the mouse,
/// hides it on Esc, focus loss or a launch, and resizes it as results come and go.
final class LauncherWindowController: NSObject, NSWindowDelegate {
    static let panelWidth: CGFloat = 680

    private let panel: LauncherPanel
    private let launcherView: LauncherView
    private let viewModel: MainViewModel
    /// Set when `ForceEnglishInput` is on: English layout while shown, previous layout restored on hide.
    private let inputSwitcher: InputSourceSwitcher?
    /// Screen y of the panel's top edge while shown; the panel grows downward from here.
    private var anchorTop: CGFloat = 0

    init(viewModel: MainViewModel, forceEnglishInput: Bool) {
        self.viewModel = viewModel
        inputSwitcher = forceEnglishInput ? InputSourceSwitcher() : nil
        launcherView = LauncherView(viewModel: viewModel)
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: Self.panelWidth, height: 120))
        super.init()

        panel.contentView = launcherView
        panel.delegate = self
        panel.keyEventInterceptor = { [weak self] event in self?.interceptKey(event) ?? false }

        launcherView.onCancel = { [weak self] in self?.hide() }
        launcherView.onContentHeightChanged = { [weak self] in self?.relayout() }
        viewModel.onLaunchSucceeded = { [weak self] in self?.hide() }
    }

    func show() {
        let screen = Self.screenUnderMouse()
        let visible = screen.visibleFrame
        anchorTop = visible.maxY - visible.height * 0.18
        relayout()

        panel.makeKeyAndOrderFront(nil)
        launcherView.focusSearchField()
        inputSwitcher?.switchToEnglish()
    }

    func hide() {
        panel.orderOut(nil)
        inputSwitcher?.restore()
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide()
        } else {
            show()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    /// ⌘1 launches the second result, ⌘2 the third, ... (Enter already covers the first). Ctrl works too,
    /// for hands used to the Windows launcher. Esc hides even when the field editor did not see it.
    private func interceptKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])

        if flags == [.command] || flags == [.control],
           let characters = event.charactersIgnoringModifiers,
           characters.count == 1,
           let digit = Int(characters),
           digit >= 1, digit <= MainViewModel.maxShortcutDigit {
            viewModel.launchAt(digit)
            return true
        }

        if event.keyCode == 53, flags.isEmpty { // Escape
            hide()
            return true
        }

        return false
    }

    private func relayout() {
        let screen = Self.screenUnderMouse()
        let visible = screen.visibleFrame
        let height = launcherView.preferredHeight(forWidth: Self.panelWidth)
        let x = visible.midX - Self.panelWidth / 2
        let frame = NSRect(x: x, y: anchorTop - height, width: Self.panelWidth, height: height)
        panel.setFrame(frame, display: true)
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}
#endif
