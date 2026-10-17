import XCTest
@testable import LauncherCore

final class AppSearcherTests: XCTestCase {
    private static let kakaoTalk = make("카카오톡", "KakaoTalk")
    private static let notes = make("메모", "Notes")
    private static let vsCode = make("Visual Studio Code", "Electron")
    private static let visualizer = make("Visual Studio Viewer", "viewer")
    private static let calculator = make("계산기", "Calculator")

    private static let all = [notes, vsCode, visualizer, kakaoTalk, calculator]

    func testSearch_FindsKoreanNameByKoreanPrefix() {
        let results = AppSearcher.search("카카", in: Self.all)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry, Self.kakaoTalk)
    }

    func testSearch_FindsKoreanNameByEnglishExecutableKeyword() {
        let results = AppSearcher.search("kakao", in: Self.all)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry, Self.kakaoTalk)
    }

    func testSearch_NameMatchOutranksKeywordMatch() {
        let byName = Self.make("Code Writer", "writer")
        let byKeyword = Self.make("Editor", "code")

        let results = AppSearcher.search("code", in: [byKeyword, byName])

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].entry, byName)
    }

    func testSearch_MultiWordQuery_RequiresEveryWord() {
        let results = AppSearcher.search("visual code", in: Self.all)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry, Self.vsCode)
    }

    func testSearch_RespectsMaxResults() {
        XCTAssertEqual(AppSearcher.search("visual", in: Self.all, maxResults: 1).count, 1)
    }

    func testSearch_EmptyQuery_ReturnsNothing() {
        XCTAssertTrue(AppSearcher.search(nil, in: Self.all).isEmpty)
        XCTAssertTrue(AppSearcher.search("", in: Self.all).isEmpty)
        XCTAssertTrue(AppSearcher.search("   ", in: Self.all).isEmpty)
    }

    func testSearch_NoMatch_ReturnsNothing() {
        XCTAssertTrue(AppSearcher.search("qqqq", in: Self.all).isEmpty)
    }

    func testSearch_OnEqualScore_AppOutranksFolder() {
        let folder = AppEntry(id: "folder:x", name: "Slack", launchPath: "/Users/me/Slack", source: .folder)
        let app = AppEntry(id: "app:x", name: "Slack", launchPath: "/Applications/Slack.app", source: .application)

        let results = AppSearcher.search("slack", in: [folder, app])

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].score, results[1].score)
        XCTAssertEqual(results[0].entry, app)
    }

    func testSearch_SameNamedFolders_ShallowerPathFirst() {
        let deep = AppEntry(id: "folder:deep", name: "Downloads", launchPath: "/Users/me/OneDrive/Backup/Downloads", source: .folder)
        let root = AppEntry(id: "folder:root", name: "Downloads", launchPath: "/Users/me/Downloads", source: .folder)

        let results = AppSearcher.search("downloads", in: [deep, root])

        XCTAssertEqual(results[0].entry, root)
        XCTAssertEqual(results[1].entry, deep)
    }

    func testSearch_UsageBoost_LiftsFrequentlyUsedEntryAboveBetterTextMatch() {
        let betterMatch = Self.make("Visual Studio Code", "Electron") // "visual": prefix match
        let frequent = Self.make("Paint Visual Tool", "paint")        // "visual": word-start match, weaker

        let plain = AppSearcher.search("visual", in: [frequent, betterMatch])
        let boosted = AppSearcher.search("visual", in: [frequent, betterMatch], boost: { $0 == frequent ? 300 : 0 })

        XCTAssertEqual(plain[0].entry, betterMatch)
        XCTAssertEqual(boosted[0].entry, frequent)
        XCTAssertEqual(boosted[0].boost, 300)
        XCTAssertEqual(boosted[0].matchScore, boosted[0].score - 300)
    }

    func testSearch_UsageBoost_DoesNotResurrectNonMatches() {
        let results = AppSearcher.search("kakao", in: Self.all, boost: { _ in 1000 })

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].entry, Self.kakaoTalk)
    }

    func testSearch_NegativeBoost_IsIgnored() {
        let results = AppSearcher.search("kakao", in: Self.all, boost: { _ in -500 })

        XCTAssertEqual(results[0].boost, 0)
        XCTAssertEqual(results[0].matchScore, results[0].score)
    }

    func testSearch_FolderWithBetterScore_StillWins() {
        let folder = AppEntry(id: "folder:x", name: "Invoices", launchPath: "/Users/me/Invoices", source: .folder)
        let app = AppEntry(id: "app:x", name: "Invoice Tool Deluxe", launchPath: "/Applications/Tool.app", source: .application)

        let results = AppSearcher.search("invoices", in: [app, folder])

        XCTAssertEqual(results[0].entry, folder)
    }

    private static func make(_ name: String, _ executable: String) -> AppEntry {
        AppEntry(
            id: "test:" + name,
            name: name,
            launchPath: "/Applications/\(name).app",
            targetPath: "/Applications/\(name).app/Contents/MacOS/\(executable)",
            keywords: [executable]
        )
    }
}
