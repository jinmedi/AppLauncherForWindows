import Foundation

/// One ranked hit. `score` is what results are ordered by: match score plus the usage `boost`.
public struct SearchResult: Equatable, Sendable {
    public let entry: AppEntry
    public let score: Int
    /// Usage-history bonus (0 when there is no history).
    public let boost: Int

    public init(entry: AppEntry, score: Int, boost: Int = 0) {
        self.entry = entry
        self.score = score
        self.boost = boost
    }

    public var matchScore: Int { score - boost }
}

/// Ranks index entries against a query. Multi-word queries require every word to match.
public enum AppSearcher {
    /// Keyword hits (executable name, folder, description) count a little less than name hits.
    private static let keywordWeight = 0.85

    /// - Parameter boost: Optional usage bonus per matched entry, added on top of the match score.
    public static func search(
        _ query: String?,
        in entries: [AppEntry],
        maxResults: Int = 8,
        boost: ((AppEntry) -> Int)? = nil
    ) -> [SearchResult] {
        guard let query, maxResults > 0 else {
            return []
        }

        let terms = query.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if terms.isEmpty {
            return []
        }

        var results: [SearchResult] = []
        results.reserveCapacity(entries.count / 8)

        for entry in entries {
            var total = 0
            var matchedAll = true

            for term in terms {
                let best = scoreEntry(term, entry)
                if best == FuzzyMatcher.noMatch {
                    matchedAll = false
                    break
                }
                total += best
            }

            if matchedAll {
                let matchScore = total / terms.count
                let bonus = max(0, boost?(entry) ?? 0)
                results.append(SearchResult(entry: entry, score: matchScore + bonus, boost: bonus))
            }
        }

        results.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let lhsRank = sourceRank(lhs.entry.source), rhsRank = sourceRank(rhs.entry.source)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            let lhsDepth = pathDepth(lhs.entry.launchPath), rhsDepth = pathDepth(rhs.entry.launchPath)
            if lhsDepth != rhsDepth { return lhsDepth < rhsDepth }
            if lhs.entry.name.count != rhs.entry.name.count { return lhs.entry.name.count < rhs.entry.name.count }
            return lhs.entry.name.localizedCaseInsensitiveCompare(rhs.entry.name) == .orderedAscending
        }

        return Array(results.prefix(maxResults))
    }

    /// On equal scores apps come before folders; there are far more folders and they are rarely the intent.
    private static func sourceRank(_ source: AppSourceKind) -> Int {
        source == .folder ? 1 : 0
    }

    /// Among same-named folders the shallower one (e.g. the Downloads root) is listed first.
    private static func pathDepth(_ path: String) -> Int {
        path.reduce(0) { $0 + ($1 == "/" || $1 == "\\" ? 1 : 0) }
    }

    private static func scoreEntry(_ term: String, _ entry: AppEntry) -> Int {
        var best = FuzzyMatcher.score(term, entry.name)

        for keyword in entry.keywords {
            let keywordScore = FuzzyMatcher.score(term, keyword)
            if keywordScore != FuzzyMatcher.noMatch {
                best = max(best, Int(Double(keywordScore) * keywordWeight))
            }
        }

        return best
    }
}
