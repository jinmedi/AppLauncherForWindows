#if canImport(AppKit)
import AppKit
import LauncherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Posted by a second copy of the app so the running one shows its window instead.
    static let showNotification = Notification.Name("com.jinmedi.AppLauncher.show")

    /// Either a Carbon `GlobalHotkey` or an `EventTapHotkey`, depending on the chord.
    private var hotkey: AnyObject?
    private var statusBar: StatusBarController?
    private var windowController: LauncherWindowController?
    private var index: AppIndex?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if Self.forwardToRunningInstance() {
            NSApp.terminate(nil)
            return
        }

        let store = SettingsStore(filePath: SettingsStore.defaultPath)
        let settings = store.load()
        Self.writeDefaultSettingsIfMissing(store, settings)

        let history = UsageHistory(filePath: UsageHistory.defaultPath)
        history.load()

        let folderScanner = FolderScanner(roots: FolderRootResolver.resolve(settings), maxDepth: settings.folderScanDepth)
        let index = AppIndex(sources: [ApplicationScanner(), folderScanner], history: history)
        self.index = index

        let viewModel = MainViewModel(settings: settings, index: index, launcher: WorkspaceLauncher(), history: history)
        let windowController = LauncherWindowController(viewModel: viewModel, forceEnglishInput: settings.forceEnglishInput)
        self.windowController = windowController

        registerHotkey(settings.hotkeyOrDefault)

        statusBar = StatusBarController(
            onToggle: { [weak windowController] in windowController?.toggle() },
            onOpen: { [weak windowController] in windowController?.show() },
            onQuit: { NSApp.terminate(nil) }
        )

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(showRequested),
            name: Self.showNotification,
            object: nil
        )

        LoginItem.apply(startAtLogin: settings.startAtLogin)

        // Index in the background; the window shows "reading apps..." until it finishes.
        Task {
            await index.refresh()
            IndexLogWriter.write(index: index, folderRoots: folderScanner.roots)
        }

        // Show once on first launch so the user sees something happened.
        windowController.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey = nil
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func showRequested() {
        windowController?.show()
    }

    /// True when another copy is already running; that copy is asked to show itself.
    private static func forwardToRunningInstance() -> Bool {
        guard let bundleId = Bundle.main.bundleIdentifier else {
            return false // `swift run` has no bundle; nothing to coordinate with.
        }

        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        guard !others.isEmpty else {
            return false
        }

        DistributedNotificationCenter.default().postNotificationName(showNotification, object: nil, userInfo: nil, deliverImmediately: true)
        return true
    }

    /// Writes the defaults on first run so the user has a file to edit (hotkey, folder roots).
    private static func writeDefaultSettingsIfMissing(_ store: SettingsStore, _ settings: LauncherSettings) {
        if FileManager.default.fileExists(atPath: store.filePath) {
            return
        }
        do {
            try store.save(settings)
        } catch {
            NSLog("[AppLauncher] could not write default settings: %@", String(describing: error))
        }
    }

    /// Side-specific chords (right Option + Return) go through an event tap, which needs the Accessibility
    /// permission. Without it the chord falls back to its generic form (either Option key) via Carbon.
    private func registerHotkey(_ spec: HotkeySpec) {
        let toggle: () -> Void = { [weak self] in self?.windowController?.toggle() }

        if spec.requiresEventTap {
            if EventTapHotkey.isAccessibilityTrusted(prompt: true), let tap = try? EventTapHotkey(spec: spec) {
                tap.onPressed = toggle
                hotkey = tap
                return
            }

            let fallback = spec.genericEquivalent
            showWarning(
                "단축키 \(spec.symbolicDescription)처럼 왼쪽/오른쪽을 구분하는 조합은 손쉬운 사용 권한이 필요합니다.\n\n"
                + "시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 App Launcher를 켠 뒤 다시 실행하세요. "
                + "그동안은 양쪽 \(fallback.symbolicDescription)로 동작합니다."
            )
            registerCarbonHotkey(fallback, onPressed: toggle)
            return
        }

        registerCarbonHotkey(spec, onPressed: toggle)
    }

    private func registerCarbonHotkey(_ spec: HotkeySpec, onPressed: @escaping () -> Void) {
        do {
            let hotkey = try GlobalHotkey(spec: spec)
            hotkey.onPressed = onPressed
            self.hotkey = hotkey
        } catch {
            showWarning("전역 단축키 \(spec)을(를) 등록하지 못했습니다. 다른 프로그램이 같은 단축키를 사용 중일 수 있습니다.\n\n\(error)")
        }
    }

    private func showWarning(_ text: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "App Launcher"
        alert.informativeText = text
        alert.runModal()
    }
}
#endif
