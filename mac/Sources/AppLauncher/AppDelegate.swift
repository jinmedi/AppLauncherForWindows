#if canImport(AppKit)
import AppKit
import LauncherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Posted by a second copy of the app so the running one shows its window instead.
    static let showNotification = Notification.Name("com.jinmedi.AppLauncher.show")

    private var hotkey: GlobalHotkey?
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
        let windowController = LauncherWindowController(viewModel: viewModel)
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

    private func registerHotkey(_ spec: HotkeySpec) {
        do {
            let hotkey = try GlobalHotkey(spec: spec)
            hotkey.onPressed = { [weak self] in self?.windowController?.toggle() }
            self.hotkey = hotkey
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "App Launcher"
            alert.informativeText = "전역 단축키 \(spec)을(를) 등록하지 못했습니다. 다른 프로그램이 같은 단축키를 사용 중일 수 있습니다.\n\n\(error)"
            alert.runModal()
        }
    }
}
#endif
