import XCTest
@testable import LauncherCore

final class AppIndexTests: XCTestCase {
    private struct FixedSource: AppSource {
        let name: String
        let entries: [AppEntry]
        func scan() throws -> [AppEntry] { entries }
    }

    private struct FailingSource: AppSource {
        struct Boom: Error {}
        var name: String { "Broken" }
        func scan() throws -> [AppEntry] { throw Boom() }
    }

    private static func entry(_ id: String, _ name: String) -> AppEntry {
        AppEntry(id: id, name: name, launchPath: "/Applications/\(name).app")
    }

    func testRefresh_MergesSourcesAndDropsDuplicateIdsCaseInsensitively() async {
        let index = AppIndex(sources: [
            FixedSource(name: "A", entries: [Self.entry("app:/x", "X"), Self.entry("app:/y", "Y")]),
            FixedSource(name: "B", entries: [Self.entry("APP:/X", "X again"), Self.entry("app:/z", "Z")]),
        ])

        await index.refresh()

        XCTAssertEqual(index.entries.map(\.name), ["X", "Y", "Z"])
        XCTAssertFalse(index.isRefreshing)
        XCTAssertFalse(index.hasErrors)
        XCTAssertEqual(index.lastReport.map(\.count), [2, 2])
    }

    func testRefresh_ReportsAFailingSourceAndKeepsTheOthers() async {
        let index = AppIndex(sources: [FailingSource(), FixedSource(name: "Good", entries: [Self.entry("app:/x", "X")])])

        await index.refresh()

        XCTAssertEqual(index.count, 1)
        XCTAssertTrue(index.hasErrors)
        XCTAssertEqual(index.lastReport[0].source, "Broken")
        XCTAssertNotNil(index.lastReport[0].error)
        XCTAssertNil(index.lastReport[1].error)
    }

    func testSearch_AppliesUsageHistoryBoost() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AppLauncherTests/\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let history = UsageHistory(filePath: directory + "/history.json")
        let frequent = Self.entry("app:/paint", "Paint Visual Tool")
        let better = Self.entry("app:/code", "Visual Studio Code")
        let index = AppIndex(sources: [FixedSource(name: "A", entries: [better, frequent])], history: history)
        await index.refresh()

        XCTAssertEqual(index.search("visual")[0].entry, better)

        for _ in 0..<5 {
            history.record(frequent.id, query: "visual")
        }

        XCTAssertEqual(index.search("visual")[0].entry, frequent)
        XCTAssertGreaterThan(index.search("visual")[0].boost, 0)
    }

    func testRefresh_InvokesCallbackOnMainQueue() async {
        let index = AppIndex(sources: [FixedSource(name: "A", entries: [])])
        let refreshed = expectation(description: "refreshed")
        index.onRefreshed = {
            XCTAssertTrue(Thread.isMainThread)
            refreshed.fulfill()
        }

        await index.refresh()

        await fulfillment(of: [refreshed], timeout: 5)
    }
}
