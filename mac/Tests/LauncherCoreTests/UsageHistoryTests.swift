import XCTest
@testable import LauncherCore

final class UsageHistoryTests: TemporaryDirectoryTestCase {
    private var now = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+09:00")!

    private var historyPath: String { baseDir + "/history.json" }

    private func newHistory() -> UsageHistory {
        UsageHistory(filePath: historyPath, clock: { [unowned self] in self.now })
    }

    private func advance(days: Double) {
        now = now.addingTimeInterval(days * 24 * 60 * 60)
    }

    func testBoost_IsZero_WithoutHistory() {
        XCTAssertEqual(newHistory().boost(for: "app:x", query: "x"), 0)
    }

    func testRecord_GrowsCountBoost_UntilCap() {
        let history = newHistory()

        history.record("app", query: nil)
        let afterOne = history.boost(for: "app", query: nil)

        for _ in 0..<50 {
            history.record("app", query: nil)
        }
        let afterMany = history.boost(for: "app", query: nil)

        XCTAssertEqual(afterOne, 15 + 60)                           // one launch, just now
        XCTAssertEqual(afterMany, UsageHistory.maxCountBoost + 60)  // capped count, just now
        XCTAssertEqual(history.launchCount("app"), 51)
    }

    func testBoost_DecaysWithAge() {
        let history = newHistory()
        history.record("app", query: nil)

        let fresh = history.boost(for: "app", query: nil)
        advance(days: 3)
        let thisWeek = history.boost(for: "app", query: nil)
        advance(days: 20)
        let thisMonth = history.boost(for: "app", query: nil)
        advance(days: 60)
        let old = history.boost(for: "app", query: nil)

        XCTAssertEqual(fresh, 75)
        XCTAssertEqual(thisWeek, 55)
        XCTAssertEqual(thisMonth, 35)
        XCTAssertEqual(old, 15)
    }

    func testBoost_RewardsTheQueryThatLaunchedItBefore() {
        let history = newHistory()
        history.record("kakao", query: "  KaKao ")

        XCTAssertEqual(history.boost(for: "kakao", query: "kakao"), 75 + UsageHistory.exactQueryBoost)
        XCTAssertEqual(history.boost(for: "kakao", query: "ka"), 75 + UsageHistory.partialQueryBoost)
        XCTAssertEqual(history.boost(for: "kakao", query: "kakaotalk"), 75 + UsageHistory.partialQueryBoost)
        XCTAssertEqual(history.boost(for: "kakao", query: "zoom"), 75)
    }

    func testRecord_PersistsAndLoadReadsItBack() {
        let history = newHistory()
        history.record("app", query: "ap")
        history.record("app", query: "ap")
        history.record("folder:/users/me/x", query: "x")

        let reloaded = newHistory()
        reloaded.load()

        XCTAssertEqual(reloaded.count, 2)
        XCTAssertEqual(reloaded.launchCount("app"), 2)
        XCTAssertEqual(reloaded.boost(for: "app", query: "ap"), 30 + 60 + UsageHistory.exactQueryBoost)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyPath + ".tmp"))
    }

    func testEntryIds_AreCaseInsensitive() {
        let history = newHistory()
        history.record("App:/Applications/Safari.app", query: nil)

        XCTAssertEqual(history.launchCount("app:/applications/safari.app"), 1)
    }

    func testLoad_ToleratesMissingAndCorruptFiles() {
        let missing = newHistory()
        missing.load()
        XCTAssertEqual(missing.count, 0)

        writeFile(historyPath, "{ nope")
        let corrupt = newHistory()
        corrupt.load()
        XCTAssertEqual(corrupt.count, 0)
    }

    func testLoad_ReadsTheWindowsLaunchersFile() {
        // .NET writes seven fractional digits and camelCase keys.
        writeFile(historyPath, """
        {
          "entries": {
            "startmenu:c:\\\\foo.lnk": {
              "count": 3,
              "lastLaunched": "2026-10-17T11:30:00.1234567+09:00",
              "queries": { "foo": 2 }
            }
          }
        }
        """)

        let history = newHistory()
        history.load()

        XCTAssertEqual(history.launchCount("startmenu:c:\\foo.lnk"), 3)
        XCTAssertEqual(history.boost(for: "startmenu:c:\\foo.lnk", query: "foo"), 45 + 60 + UsageHistory.exactQueryBoost)
    }

    func testParseDate_AcceptsAnyFractionLength() {
        XCTAssertNotNil(UsageHistory.parseDate("2026-10-17T12:00:00+09:00"))
        XCTAssertNotNil(UsageHistory.parseDate("2026-10-17T12:00:00.123+09:00"))
        XCTAssertNotNil(UsageHistory.parseDate("2026-10-17T12:00:00.1234567+09:00"))
        XCTAssertNotNil(UsageHistory.parseDate("2026-10-17T03:00:00.1Z"))
        XCTAssertNil(UsageHistory.parseDate("yesterday"))
    }

    func testSave_DropsEntriesNotLaunchedForSixMonths() {
        let history = newHistory()
        history.record("old", query: nil)
        advance(days: 200)
        history.record("new", query: nil) // saving now prunes "old"

        let reloaded = newHistory()
        reloaded.load()

        XCTAssertEqual(reloaded.launchCount("old"), 0)
        XCTAssertEqual(reloaded.launchCount("new"), 1)
    }

    func testRecord_KeepsAtMostTenQueriesPerEntry() {
        let history = newHistory()
        for i in 0..<12 {
            history.record("app", query: "q\(i)")
        }

        history.record("app", query: "q11") // strongest; must survive

        let thirteenLaunchesJustNow = 13 * 15 + 60
        XCTAssertEqual(history.boost(for: "app", query: "q11"), thirteenLaunchesJustNow + UsageHistory.exactQueryBoost)
        XCTAssertEqual(history.boost(for: "app", query: "zzz"), thirteenLaunchesJustNow)
    }
}
