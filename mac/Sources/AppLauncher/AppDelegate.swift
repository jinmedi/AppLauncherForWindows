#if canImport(AppKit)
import AppKit
import LauncherCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Posted by a second copy of the app so the running one shows its window instead.
    static let showNotification = Notification.Name("com.jinmedi.AppLauncher.show")

    /// One entry per registered hotkey (Carbon `GlobalHotkey` or `EventTapHotkey`).
    private var hotkeys: [AnyObject] = []
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

        registerHotkeys(settings)

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
        hotkeys.removeAll()
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

    /// Registers the primary hotkey from settings and, if different, also registers RightOption+Return
    /// as a secondary hotkey so the launcher is always reachable with that chord.
    private func registerHotkeys(_ settings: LauncherSettings) {
        hotkeys.removeAll()
        let toggle: () -> Void = { [weak self] in self?.windowController?.toggle() }

        let primarySpec = settings.hotkeyOrDefault
        registerSingleHotkey(primarySpec, onPressed: toggle, warnOnFailure: true)

        let secondarySpec = HotkeySpec.default
        if primarySpec != secondarySpec {
            registerSingleHotkey(secondarySpec, onPressed: toggle, warnOnFailure: false)
        }
    }

    /// Side-specific chords go through an event tap (Accessibility permission required).
    /// Without it the chord falls back to its generic form via Carbon.
    /// `warnOnFailure` controls whether the user sees an alert on fallback or silent failure.
    private func registerSingleHotkey(_ spec: HotkeySpec, onPressed toggle: @escaping () -> Void, warnOnFailure: Bool) {
        if spec.requiresEventTap {
            if EventTapHotkey.isAccessibilityTrusted(prompt: warnOnFailure),
               let tap = try? EventTapHotkey(spec: spec) {
                tap.onPressed = toggle
                hotkeys.append(tap)
                return
            }

            let fallback = spec.genericEquivalent
            if warnOnFailure {
                showWarning(
                    "단축키 \(spec.symbolicDescription)처럼 왼쪽/오른쪽을 구분하는 조합은 손쉬운 사용 권한이 필요합니다.\n\n"
                    + "시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용에서 App Launcher를 켠 뒤 다시 실행하세요. "
                    + "그동안은 양쪽 \(fallback.symbolicDescription)로 동작합니다."
                )
            }
            addCarbonHotkey(fallback, onPressed: toggle, warnOnFailure: warnOnFailure)
            return
        }

        addCarbonHotkey(spec, onPressed: toggle, warnOnFailure: warnOnFailure)
    }

    private func addCarbonHotkey(_ spec: HotkeySpec, onPressed: @escaping () -> Void, warnOnFailure: Bool) {
        do {
            let hotkey = try GlobalHotkey(spec: spec)
            hotkey.onPressed = onPressed
            hotkeys.append(hotkey)
        } catch {
            if warnOnFailure {
                showWarning("전역 단축키 \(spec)을(를) 등록하지 못했습니다. 다른 프로그램이 같은 단축키를 사용 중일 수 있습니다.\n\n\(error)")
            }
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
