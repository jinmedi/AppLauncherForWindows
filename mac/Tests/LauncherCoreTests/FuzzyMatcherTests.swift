import XCTest
@testable import LauncherCore

final class FuzzyMatcherTests: XCTestCase {
    func testTiersAreOrdered_ExactBeatsPrefixBeatsWordStartBeatsSubstringBeatsSubsequence() {
        let exact = FuzzyMatcher.score("code", "code")
        let prefix = FuzzyMatcher.score("code", "Code Editor")
        let wordStart = FuzzyMatcher.score("code", "Visual Studio Code")
        let substring = FuzzyMatcher.score("code", "xcodex")
        let subsequence = FuzzyMatcher.score("code", "cxoxdxe") // no separators, so no acronym tier

        XCTAssertGreaterThan(exact, prefix)
        XCTAssertGreaterThan(prefix, wordStart)
        XCTAssertGreaterThan(wordStart, substring)
        XCTAssertGreaterThan(substring, subsequence)
        XCTAssertGreaterThan(subsequence, 0)
    }

    func testScore_MatchesCaseInsensitivelyAndAcrossScripts() {
        let cases: [(String, String)] = [
            ("카카", "카카오톡"),
            ("카오", "카카오톡"),
            ("KAKAO", "KakaoTalk"),
            ("vsc", "Visual Studio Code"),
            ("kt", "KakaoTalk"),
        ]
        for (query, candidate) in cases {
            XCTAssertNotEqual(FuzzyMatcher.score(query, candidate), FuzzyMatcher.noMatch, "\(query) in \(candidate)")
        }
    }

    func testScore_MatchesDecomposedHangulFromTheFileSystem() {
        // HFS+ stores Hangul decomposed (NFD); the keyboard produces composed (NFC) syllables.
        let decomposed = "카카오톡".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(decomposed.utf8.count, "카카오톡".utf8.count)

        XCTAssertEqual(FuzzyMatcher.score("카카오톡", decomposed), 1000)
        XCTAssertNotEqual(FuzzyMatcher.score("카카", decomposed), FuzzyMatcher.noMatch)
    }

    func testScore_ReturnsNoMatch_WhenQueryCannotBeFound() {
        let cases: [(String, String)] = [
            ("zzz", "KakaoTalk"),
            ("talkkakao", "KakaoTalk"), // right letters, wrong order
            ("", "KakaoTalk"),
            ("   ", "KakaoTalk"),
            ("a", ""),
        ]
        for (query, candidate) in cases {
            XCTAssertEqual(FuzzyMatcher.score(query, candidate), FuzzyMatcher.noMatch, "\(query) in \(candidate)")
        }
    }

    func testAcronym_MatchesFirstLettersOfWords() {
        let acronym = FuzzyMatcher.score("vsc", "Visual Studio Code")
        let scattered = FuzzyMatcher.score("vsc", "Advanced Scanner")

        XCTAssertGreaterThan(acronym, scattered)
    }

    func testShorterCandidate_WinsOnEqualPrefix() {
        let shorter = FuzzyMatcher.score("note", "Notes")
        let longer = FuzzyMatcher.score("note", "Notes Exporter Portable Edition")

        XCTAssertGreaterThan(shorter, longer)
    }
}
