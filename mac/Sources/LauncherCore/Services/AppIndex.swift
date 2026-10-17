import Foundation

/// What one source contributed to the last refresh. `error` is set when it threw.
public struct SourceReport: Equatable, Sendable {
    public let source: String
    public let count: Int
    public let elapsed: TimeInterval
    public let error: String?

    public init(source: String, count: Int, elapsed: TimeInterval, error: String?) {
        self.source = source
        self.count = count
        self.elapsed = elapsed
        self.error = error
    }
}

/// In-memory list of launchable apps gathered from all registered sources.
public final class AppIndex: @unchecked Sendable {
    private let sources: [any AppSource]
    private let history: UsageHistory?
    private let lock = NSLock()
    private var storedEntries: [AppEntry] = []
    private var storedReport: [SourceReport] = []
    private var refreshing = false

    public init(sources: [any AppSource], history: UsageHistory? = nil) {
        self.sources = sources
        self.history = history
    }

    public var entries: [AppEntry] {
        lock.lock(); defer { lock.unlock() }
        return storedEntries
    }

    public var count: Int { entries.count }

    public var isRefreshing: Bool {
        lock.lock(); defer { lock.unlock() }
        return refreshing
    }

    public var lastReport: [SourceReport] {
        lock.lock(); defer { lock.unlock() }
        return storedReport
    }

    public var hasErrors: Bool { lastReport.contains { $0.error != nil } }

    /// Called on the main queue after every refresh.
    public var onRefreshed: (() -> Void)?

    /// Scans every source concurrently. A source that throws is reported in `lastReport` and skipped; the others still load.
    public func refresh() async {
        setRefreshing(true)

        let sources = self.sources
        let results = await withTaskGroup(of: (Int, [AppEntry], SourceReport).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask {
                    let (entries, report) = Self.scan(source)
                    return (index, entries, report)
                }
            }

            var collected: [(Int, [AppEntry], SourceReport)] = []
            for await result in group {
                collected.append(result)
            }
            return collected.sorted { $0.0 < $1.0 }
        }

        var merged: [AppEntry] = []
        var seen = Set<String>()
        for (_, entries, _) in results {
            for entry in entries where seen.insert(entry.id.lowercased()).inserted {
                merged.append(entry)
            }
        }

        store(entries: merged, report: results.map { $0.2 })

        if let onRefreshed {
            DispatchQueue.main.async { onRefreshed() }
        }
    }

    // NSLock must not be taken directly from an async context; these synchronous helpers scope it.
    private func setRefreshing(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        refreshing = value
    }

    private func store(entries: [AppEntry], report: [SourceReport]) {
        lock.lock(); defer { lock.unlock() }
        storedEntries = entries
        storedReport = report
        refreshing = false
    }

    /// Matches are boosted by usage history when one was supplied, so frequently launched items rank first.
    public func search(_ query: String?, maxResults: Int = 8) -> [SearchResult] {
        let history = self.history
        return AppSearcher.search(
            query,
            in: entries,
            maxResults: maxResults,
            boost: history.map { h in { entry in h.boost(for: entry.id, query: query) } }
        )
    }

    private static func scan(_ source: any AppSource) -> ([AppEntry], SourceReport) {
        let started = Date()
        do {
            let entries = try source.scan()
            return (entries, SourceReport(source: source.name, count: entries.count, elapsed: Date().timeIntervalSince(started), error: nil))
        } catch {
            return ([], SourceReport(source: source.name, count: 0, elapsed: Date().timeIntervalSince(started), error: String(describing: error)))
        }
    }
}
