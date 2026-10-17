import Foundation

/// Scores how well a query matches a candidate string. Higher is better; `noMatch` means no match.
/// Tiers, best first: exact, prefix, word-start prefix, acronym, substring, in-order subsequence.
/// Works on characters (grapheme clusters), so Korean syllables match the same way as Latin letters
/// whether the file system handed us composed or decomposed Hangul.
public enum FuzzyMatcher {
    public static let noMatch = -1

    private static let wordSeparators: Set<Character> = [" ", "-", "_", ".", "(", ")", "[", "]", "/", "\\", ","]

    public static func score(_ query: String, _ candidate: String) -> Int {
        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        if trimmedQuery.isEmpty || candidate.isEmpty {
            return noMatch
        }

        let q = Array(normalize(trimmedQuery))
        let c = Array(normalize(candidate))

        if c == q {
            return 1000
        }

        if c.starts(with: q) {
            return 900 - min(c.count - q.count, 50)
        }

        let words = c.split(whereSeparator: { wordSeparators.contains($0) })
        for (i, word) in words.enumerated() where word.starts(with: q) {
            return 800 - min(i * 10, 50)
        }

        if words.count > 1 && q.count >= 2 {
            let acronym = words.map { $0.first! }
            if acronym.starts(with: q) {
                return 750
            }
        }

        if let index = indexOf(q, in: c) {
            return 600 - min(index * 5, 150)
        }

        return subsequenceScore(q, c)
    }

    /// Lower-cases and composes (NFC) so "한" typed on the keyboard equals "한" stored decomposed on disk.
    private static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func indexOf(_ needle: [Character], in haystack: [Character]) -> Int? {
        guard !needle.isEmpty, needle.count <= haystack.count else {
            return nil
        }
        for start in 0...(haystack.count - needle.count) {
            var matched = true
            for offset in 0..<needle.count where haystack[start + offset] != needle[offset] {
                matched = false
                break
            }
            if matched {
                return start
            }
        }
        return nil
    }

    /// All query characters must appear in order. Rewards runs of consecutive matches and matches
    /// at word starts; penalises gaps so "kt" prefers "KakaoTalk" over "k....t" spread far apart.
    private static func subsequenceScore(_ q: [Character], _ c: [Character]) -> Int {
        var score = 300
        var ci = 0
        var previousMatch = -2

        for ch in q {
            guard let found = c[ci...].firstIndex(of: ch) else {
                return noMatch
            }

            if found == previousMatch + 1 {
                score += 12
            } else {
                let gap = found - max(previousMatch + 1, 0)
                score -= min(gap * 2, 40)
            }

            if found == 0 || wordSeparators.contains(c[found - 1]) {
                score += 15
            }

            previousMatch = found
            ci = found + 1
        }

        return max(score, 1)
    }
}
