#if canImport(AppKit)
import Foundation
import LauncherCore

/// Search, selection and launching for the launcher window. Main-thread only; the view observes the callbacks.
final class MainViewModel {
    static let maxResults = 8

    /// Highest digit that is meaningful: ⌘1 through ⌘(maxResults - 1).
    static var maxShortcutDigit: Int { maxResults - 1 }

    struct Row {
        let entry: AppEntry
        /// Key that launches this row: "Enter" for the first result, "⌘1" for the second, and so on.
        let shortcutHint: String

        var name: String { entry.name }
        var detail: String { entry.launchPath }
        var kind: String { entry.source == .folder ? "폴더" : "앱" }
    }

    private let index: AppIndex
    private let launcher: AppLaunching
    private let history: UsageHistory

    private(set) var results: [Row] = []
    private(set) var statusText = ""
    let hintText: String

    var query = "" {
        didSet {
            if query != oldValue {
                updateResults()
            }
        }
    }

    var selectedIndex: Int? {
        didSet {
            if selectedIndex != oldValue {
                onSelectionChanged?()
            }
        }
    }

    var onResultsChanged: (() -> Void)?
    var onSelectionChanged: (() -> Void)?
    var onStatusChanged: (() -> Void)?
    var onQueryReset: (() -> Void)?
    /// Raised after an item was started so the window can hide itself.
    var onLaunchSucceeded: (() -> Void)?

    init(settings: LauncherSettings, index: AppIndex, launcher: AppLaunching, history: UsageHistory) {
        self.index = index
        self.launcher = launcher
        self.history = history

        let hotkey = settings.hotkeyOrDefault.symbolicDescription
        hintText = "Enter 실행   ·   ⌘숫자 n+1번째 실행   ·   Esc 닫기   ·   \(hotkey) 열기/닫기"

        index.onRefreshed = { [weak self] in self?.indexRefreshed() }
        updateStatus()
    }

    var hasResults: Bool { !results.isEmpty }

    func moveSelection(_ delta: Int) {
        guard !results.isEmpty else {
            return
        }
        let current = selectedIndex ?? -1
        selectedIndex = current < 0 ? 0 : (current + delta + results.count) % results.count
    }

    @discardableResult
    func launchSelected() -> Bool {
        guard let selectedIndex, selectedIndex < results.count else {
            return false
        }
        return launch(results[selectedIndex])
    }

    /// Launches the result at `index` (0-based). Enter covers index 0, so ⌘1 maps to index 1, ⌘2 to index 2, ...
    @discardableResult
    func launchAt(_ index: Int) -> Bool {
        guard index >= 0, index < results.count else {
            return false
        }
        return launch(results[index])
    }

    @discardableResult
    func launch(_ row: Row) -> Bool {
        do {
            try launcher.launch(row.entry)
        } catch {
            statusText = "실행 실패: \(error)"
            onStatusChanged?()
            return false
        }

        // Remember the launch and the query that led to it; the file write happens off the main thread.
        let launchedId = row.entry.id
        let usedQuery = query
        let history = self.history
        DispatchQueue.global(qos: .utility).async {
            history.record(launchedId, query: usedQuery)
        }

        query = ""
        onQueryReset?()
        onLaunchSucceeded?()
        return true
    }

    private static func shortcutHint(for index: Int) -> String {
        index == 0 ? "Enter" : "⌘\(index)"
    }

    private func updateResults() {
        let matches = index.search(query, maxResults: Self.maxResults)
        results = matches.enumerated().map { offset, match in
            Row(entry: match.entry, shortcutHint: Self.shortcutHint(for: offset))
        }
        onResultsChanged?()
        selectedIndex = results.isEmpty ? nil : 0
        onSelectionChanged?()
    }

    private func indexRefreshed() {
        updateStatus()
        if !query.isEmpty {
            updateResults()
        }
    }

    private func updateStatus() {
        if index.isRefreshing || index.count == 0 {
            statusText = "앱 목록을 읽는 중..."
            onStatusChanged?()
            return
        }

        let entries = index.entries
        let folders = entries.filter { $0.source == .folder }.count
        let apps = entries.count - folders
        var status = folders > 0 ? "앱 \(apps)개   ·   폴더 \(folders)개" : "앱 \(apps)개"
        if index.hasErrors {
            status += "   ·   일부 읽기 실패 (index.log 확인)"
        }
        statusText = status
        onStatusChanged?()
    }
}
#endif
