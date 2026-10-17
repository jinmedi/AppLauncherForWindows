import Foundation

/// Remembers what was launched, how often, when, and with which query, and turns that into a
/// ranking boost so frequently used items float to the top of matching results.
/// Persisted as JSON next to settings.json, in the same shape the Windows launcher writes.
/// Safe to call from any thread.
public final class UsageHistory: @unchecked Sendable {
    public static let maxCountBoost = 300
    public static let exactQueryBoost = 400
    public static let partialQueryBoost = 200

    private static let pointsPerLaunch = 15
    private static let countCap = maxCountBoost / pointsPerLaunch
    private static let maxQueriesPerEntry = 10
    private static let maxEntries = 1000
    private static let retainFor: TimeInterval = 180 * 24 * 60 * 60

    private let lock = NSLock()
    private let clock: () -> Date
    private var records: [String: UsageRecord] = [:]

    public let filePath: String

    public init(filePath: String, clock: (() -> Date)? = nil) {
        precondition(!filePath.trimmingCharacters(in: .whitespaces).isEmpty, "filePath must not be blank")
        self.filePath = filePath
        self.clock = clock ?? { Date() }
    }

    /// ~/Library/Application Support/AppLauncherForMac/history.json
    public static var defaultPath: String { AppPaths.historyFile }

    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return records.count
    }

    /// Loads the file; a missing or corrupt file simply means no history.
    public func load() {
        var loaded: [String: UsageRecord] = [:]
        if let data = FileManager.default.contents(atPath: filePath),
           let file = try? Self.decoder.decode(HistoryFile.self, from: data) {
            for (id, record) in file.entries ?? [:] where !id.isEmpty {
                loaded[Self.key(id)] = record
            }
        }

        lock.lock()
        records = loaded
        lock.unlock()
    }

    /// Records one launch of `entryId` made from `query` and saves.
    public func record(_ entryId: String, query: String?) {
        precondition(!entryId.isEmpty, "entryId must not be blank")

        let now = clock()
        let normalizedQuery = Self.normalizeQuery(query)
        let key = Self.key(entryId)

        lock.lock(); defer { lock.unlock() }

        var record = records[key] ?? UsageRecord()
        record.count += 1
        record.lastLaunched = now

        if !normalizedQuery.isEmpty {
            record.queries[normalizedQuery, default: 0] += 1
            if record.queries.count > Self.maxQueriesPerEntry {
                // Never evict the query just recorded; drop the weakest of the others.
                if let weakest = record.queries
                    .filter({ $0.key != normalizedQuery })
                    .min(by: { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }) {
                    record.queries.removeValue(forKey: weakest.key)
                }
            }
        }

        records[key] = record
        saveLocked(now: now)
    }

    public func launchCount(_ entryId: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return records[Self.key(entryId)]?.count ?? 0
    }

    /// Ranking bonus for `entryId` when the user typed `query`:
    /// launches (15 each, capped at 300) + recency (60/40/20 within 1/7/30 days)
    /// + 400 if this exact query launched it before, or 200 if a remembered query shares a prefix with it.
    public func boost(for entryId: String, query: String?) -> Int {
        if entryId.isEmpty {
            return 0
        }

        lock.lock()
        let snapshot = records[Self.key(entryId)]
        lock.unlock()

        guard let record = snapshot else {
            return 0
        }

        var boost = min(record.count, Self.countCap) * Self.pointsPerLaunch

        let age = clock().timeIntervalSince(record.lastLaunched)
        let day: TimeInterval = 24 * 60 * 60
        if age < day {
            boost += 60
        } else if age < 7 * day {
            boost += 40
        } else if age < 30 * day {
            boost += 20
        }

        let q = Self.normalizeQuery(query)
        if !q.isEmpty {
            if record.queries[q] != nil {
                boost += Self.exactQueryBoost
            } else if record.queries.keys.contains(where: { $0.hasPrefix(q) || q.hasPrefix($0) }) {
                boost += Self.partialQueryBoost
            }
        }

        return boost
    }

    /// Entry ids are case-insensitive, like the Windows history.
    private static func key(_ entryId: String) -> String {
        entryId.lowercased()
    }

    private static func normalizeQuery(_ query: String?) -> String {
        (query ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Caller holds the lock. Drops stale entries, keeps the most-used, and writes atomically.
    private func saveLocked(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retainFor)
        for stale in records.filter({ $0.value.lastLaunched < cutoff }).map(\.key) {
            records.removeValue(forKey: stale)
        }

        if records.count > Self.maxEntries {
            let overflow = records
                .sorted { lhs, rhs in
                    if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
                    return lhs.value.lastLaunched < rhs.value.lastLaunched
                }
                .prefix(records.count - Self.maxEntries)
            for item in overflow {
                records.removeValue(forKey: item.key)
            }
        }

        do {
            let data = try Self.encoder.encode(HistoryFile(entries: records))
            try AppPaths.writeAtomically(data, to: filePath)
        } catch {
            // Losing one save is acceptable; the in-memory history still ranks this session.
        }
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(isoWithFraction.string(from: date))
        }
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = AppPaths.lenientJSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)"))
        }
        return decoder
    }()

    /// Accepts "2026-10-17T12:00:00+09:00" with 0, 3 or more fractional digits (.NET writes seven).
    static func parseDate(_ text: String) -> Date? {
        if let date = isoWithFraction.date(from: text) ?? isoPlain.date(from: text) {
            return date
        }

        // Trim the fraction to milliseconds, which every ISO8601DateFormatter build accepts.
        guard let dot = text.firstIndex(of: "."),
              let end = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) else {
            return nil
        }
        let fraction = String(text[text.index(after: dot)..<end].prefix(3))
        let trimmed = String(text[..<dot]) + "." + fraction.padding(toLength: 3, withPad: "0", startingAt: 0) + String(text[end...])
        return isoWithFraction.date(from: trimmed)
    }

    private static let isoWithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private struct HistoryFile: Codable {
        var entries: [String: UsageRecord]?
    }

    private struct UsageRecord: Codable {
        var count = 0
        var lastLaunched = Date(timeIntervalSince1970: 0)
        var queries: [String: Int] = [:]

        init() {}

        private enum CodingKeys: String, CodingKey {
            case count, lastLaunched, queries
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
            lastLaunched = try container.decodeIfPresent(Date.self, forKey: .lastLaunched) ?? Date(timeIntervalSince1970: 0)
            queries = try container.decodeIfPresent([String: Int].self, forKey: .queries) ?? [:]
        }
    }
}
