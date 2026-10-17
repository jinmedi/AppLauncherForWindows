import XCTest
@testable import LauncherCore

final class FolderScannerTests: TemporaryDirectoryTestCase {
    private func names(_ entries: [AppEntry]) -> [String] {
        entries.map(\.name)
    }

    func testScan_IncludesRootAndSubfoldersDownToMaxDepth() throws {
        let root = makeDir("Projects")
        makeDir("Projects", "Alpha")
        makeDir("Projects", "Alpha", "src")
        makeDir("Projects", "Alpha", "src", "deep") // depth 3: beyond the limit

        let entries = try FolderScanner(roots: [root], maxDepth: 2).scan()

        XCTAssertEqual(names(entries), ["Projects", "Alpha", "src"])
    }

    func testScan_DepthZero_IndexesOnlyRoots() throws {
        let root = makeDir("Only")
        makeDir("Only", "Child")

        let entries = try FolderScanner(roots: [root], maxDepth: 0).scan()

        XCTAssertEqual(names(entries), ["Only"])
    }

    func testScan_SkipsDotAndNoiseFolders() throws {
        let root = makeDir("Repo")
        makeDir("Repo", "src")
        makeDir("Repo", ".git")
        makeDir("Repo", "node_modules")
        makeDir("Repo", "obj")

        let entries = try FolderScanner(roots: [root]).scan()

        XCTAssertEqual(names(entries), ["Repo", "src"])
    }

    func testScan_SkipsFinderHiddenFolders() throws {
        let root = makeDir("Home")
        makeDir("Home", "Visible")
        let hidden = makeDir("Home", "Library")
        try XCTSkipUnless(setHidden(hidden), "This platform has no Finder hidden flag")

        let entries = try FolderScanner(roots: [root]).scan()

        XCTAssertEqual(names(entries), ["Home", "Visible"])
    }

    func testScan_SkipsSymbolicLinksAndAppBundles() throws {
        let root = makeDir("Links")
        let target = makeDir("Elsewhere")
        makeDir("Links", "Real")
        makeDir("Links", "Tool.app")
        try FileManager.default.createSymbolicLink(atPath: root + "/Linked", withDestinationPath: target)

        let entries = try FolderScanner(roots: [root]).scan()

        XCTAssertEqual(names(entries), ["Links", "Real"])
    }

    func testScan_AddsBothLanguagesAsKeywordsForCloudAndKnownRoots() throws {
        let myDrive = makeDir("내 드라이브")
        let desktopKo = makeDir("바탕 화면")

        let entries = try FolderScanner(roots: [myDrive, desktopKo], maxDepth: 0).scan()

        XCTAssertTrue(entries[0].keywords.contains("My Drive"))
        XCTAssertTrue(entries[0].keywords.contains("구글 드라이브"))
        XCTAssertTrue(entries[1].keywords.contains("Desktop"))
    }

    func testScan_ProducesFolderEntriesThatOpenThePathItself() throws {
        let root = makeDir("Docs")

        let entries = try FolderScanner(roots: [root], maxDepth: 0).scan()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].source, .folder)
        XCTAssertEqual(entries[0].launchPath, AppPaths.normalizePath(root))
        XCTAssertNil(entries[0].targetPath)
        XCTAssertTrue(entries[0].id.hasPrefix("folder:"))
    }

    func testScan_AddsKoreanKeywordForWellKnownRootNames() throws {
        let root = makeDir("Downloads")

        let entries = try FolderScanner(roots: [root], maxDepth: 0).scan()

        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].keywords.contains("다운로드"))
    }

    func testScan_NamesICloudDriveByItsFinderName() throws {
        let root = makeDir("Mobile Documents", "com~apple~CloudDocs")

        let entries = try FolderScanner(roots: [root], maxDepth: 0).scan()

        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].keywords.contains("iCloud Drive") || entries[0].name == "iCloud Drive")
        XCTAssertTrue(entries[0].keywords.contains("아이클라우드"))
    }

    func testScan_AddsParentNameAsKeywordForSubfolders() throws {
        let root = makeDir("Work")
        makeDir("Work", "Invoices")

        let entries = try FolderScanner(roots: [root]).scan()
        let child = entries.first { $0.name == "Invoices" }

        XCTAssertNotNil(child)
        XCTAssertTrue(child?.keywords.contains("Work") ?? false)
    }

    func testScan_IgnoresMissingAndBlankRoots() throws {
        let root = makeDir("Real")

        let entries = try FolderScanner(roots: [baseDir + "/missing", "", "   ", root], maxDepth: 0).scan()

        XCTAssertEqual(entries.count, 1)
    }

    func testScan_ExpandsTildeAndEnvironmentVariablesInRoots() throws {
        let root = makeDir("FromEnv")
        setenv("APPLAUNCHER_TEST_ROOT", baseDir, 1)
        defer { unsetenv("APPLAUNCHER_TEST_ROOT") }

        let entries = try FolderScanner(roots: ["$APPLAUNCHER_TEST_ROOT/FromEnv"], maxDepth: 0).scan()

        XCTAssertEqual(entries.map(\.launchPath), [AppPaths.normalizePath(root)!])
    }

    func testScan_DeduplicatesOverlappingRoots() throws {
        let root = makeDir("Home")
        let child = makeDir("Home", "Docs")

        let entries = try FolderScanner(roots: [root, child]).scan()

        XCTAssertEqual(entries.count, 2)
    }

    func testScan_MergesRootKeywords_WhenRootWasAlreadySeenAsChild() throws {
        let home = makeDir("home")
        let oneDrive = makeDir("home", "OneDrive - Work")

        // Home first, so OneDrive is first met as a child (keyword "home"), then again as a root.
        let entries = try FolderScanner(roots: [home, oneDrive]).scan()
        let entry = entries.first { $0.name == "OneDrive - Work" }

        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entry?.keywords.contains("home") ?? false)
        XCTAssertTrue(entry?.keywords.contains("원드라이브") ?? false)
    }

    func testScan_StopsAtMaxEntries() throws {
        let root = makeDir("Many")
        for i in 0..<10 {
            makeDir("Many", "f\(i)")
        }

        let entries = try FolderScanner(roots: [root], maxDepth: 1, maxEntries: 4).scan()

        XCTAssertEqual(entries.count, 4)
    }
}
