import XCTest
@testable import LauncherCore

final class ApplicationScannerTests: TemporaryDirectoryTestCase {
    /// Creates a minimal .app bundle with an Info.plist and optional localized InfoPlist.strings.
    @discardableResult
    private func makeApp(
        _ parts: [String],
        executable: String? = nil,
        bundleName: String? = nil,
        displayName: String? = nil,
        packageType: String? = "APPL",
        localized: [String: [String: String]] = [:]
    ) -> String {
        let bundle = makeDir(parts.joined(separator: "/"))
        makeDir(parts.joined(separator: "/"), "Contents", "MacOS")

        var info: [String: Any] = [:]
        if let executable { info["CFBundleExecutable"] = executable }
        if let bundleName { info["CFBundleName"] = bundleName }
        if let displayName { info["CFBundleDisplayName"] = displayName }
        if let packageType { info["CFBundlePackageType"] = packageType }
        writePlist(info, to: bundle + "/Contents/Info.plist")

        for (localization, strings) in localized {
            makeDir(parts.joined(separator: "/"), "Contents", "Resources", localization + ".lproj")
            writePlist(strings, to: bundle + "/Contents/Resources/\(localization).lproj/InfoPlist.strings")
        }

        return bundle
    }

    private func writePlist(_ object: Any, to path: String) {
        let data = try! PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        try! data.write(to: URL(fileURLWithPath: path))
    }

    func testScan_FindsAppsInRootAndSubfolders_ButNotInsideBundles() throws {
        let root = makeDir("Applications")
        makeApp(["Applications", "Safari.app"], executable: "Safari")
        makeApp(["Applications", "Utilities", "Terminal.app"], executable: "Terminal")
        makeApp(["Applications", "Safari.app", "Contents", "Helpers", "Helper.app"], executable: "Helper")

        let entries = try ApplicationScanner(roots: [root]).scan()

        XCTAssertEqual(entries.map(\.name).sorted(), ["Safari", "Terminal"])
    }

    func testScan_ProducesLaunchableEntries() throws {
        let root = makeDir("Applications")
        let bundle = makeApp(["Applications", "Safari.app"], executable: "Safari")

        let entries = try ApplicationScanner(roots: [root]).scan()

        let expectedPath = AppPaths.normalizePath(bundle)!
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].source, .application)
        XCTAssertEqual(entries[0].launchPath, expectedPath)
        XCTAssertEqual(entries[0].targetPath, expectedPath + "/Contents/MacOS/Safari")
        XCTAssertEqual(entries[0].id, "app:" + expectedPath.lowercased())
    }

    func testScan_AddsBundleAndLocalizedNamesAsKeywords() throws {
        let root = makeDir("Applications")
        makeApp(
            ["Applications", "KakaoTalk.app"],
            executable: "KakaoTalk",
            bundleName: "KakaoTalk",
            localized: ["ko": ["CFBundleDisplayName": "카카오톡"], "en": ["CFBundleDisplayName": "KakaoTalk"]]
        )

        let entries = try ApplicationScanner(roots: [root]).scan()

        XCTAssertEqual(entries.count, 1)
        let searchable = [entries[0].name] + entries[0].keywords
        XCTAssertTrue(searchable.contains("카카오톡"), "\(searchable)")
        XCTAssertTrue(searchable.contains("KakaoTalk"), "\(searchable)")
        XCTAssertFalse(entries[0].keywords.contains(entries[0].name), "the display name is not repeated as a keyword")
    }

    func testScan_AddsSubfolderNameAsKeyword() throws {
        let root = makeDir("Applications")
        makeApp(["Applications", "Utilities", "Terminal.app"], executable: "Terminal")

        let entries = try ApplicationScanner(roots: [root]).scan()

        XCTAssertTrue(entries[0].keywords.contains("Utilities"))
    }

    func testScan_SkipsUninstallersAndNonApplicationBundles() throws {
        let root = makeDir("Applications")
        makeApp(["Applications", "Uninstall Foo.app"], executable: "Uninstall")
        makeApp(["Applications", "Foo 제거.app"], executable: "Remove")
        makeApp(["Applications", "Plugin.app"], executable: "Plugin", packageType: "BNDL")
        makeApp(["Applications", "Keep.app"], executable: "Keep")

        let entries = try ApplicationScanner(roots: [root]).scan()

        XCTAssertEqual(entries.map(\.name), ["Keep"])
    }

    func testScan_DeduplicatesSymlinkedBundles() throws {
        let root = makeDir("Applications")
        let real = makeApp(["Applications", "Real.app"], executable: "Real")
        try FileManager.default.createSymbolicLink(atPath: root + "/Alias.app", withDestinationPath: real)

        let entries = try ApplicationScanner(roots: [root]).scan()

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(
            URL(fileURLWithPath: entries[0].launchPath).resolvingSymlinksInPath().path,
            URL(fileURLWithPath: real).resolvingSymlinksInPath().path
        )
    }

    func testScan_ToleratesBundlesWithoutInfoPlist() throws {
        let root = makeDir("Applications")
        makeDir("Applications", "Bare.app")

        let entries = try ApplicationScanner(roots: [root]).scan()

        XCTAssertEqual(entries.map(\.name), ["Bare"])
        XCTAssertNil(entries[0].targetPath)
    }

    func testScan_IgnoresMissingRoots() throws {
        let entries = try ApplicationScanner(roots: [baseDir + "/missing", ""]).scan()

        XCTAssertTrue(entries.isEmpty)
    }

    func testDefaultRoots_CoverUserSystemAndCoreServicesApplications() {
        let roots = ApplicationScanner.defaultRoots(home: "/Users/me")

        XCTAssertEqual(roots, [
            "/Users/me/Applications",
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
        ])
    }
}
