import XCTest
@testable import LauncherCore

final class SettingsStoreTests: TemporaryDirectoryTestCase {
    private var settingsPath: String { baseDir + "/settings.json" }

    func testLoad_ReturnsDefaults_WhenFileIsMissing() {
        let settings = SettingsStore(filePath: settingsPath).load()

        XCTAssertEqual(settings.hotkey, "Option+Space")
        XCTAssertFalse(settings.startAtLogin)
        XCTAssertTrue(settings.includeKnownFolders)
        XCTAssertTrue(settings.includeCloudDrives)
        XCTAssertTrue(settings.folderRoots.isEmpty)
        XCTAssertEqual(settings.folderScanDepth, 2)
    }

    func testSave_ThenLoad_RoundTripsFolderSettings() throws {
        let store = SettingsStore(filePath: settingsPath)
        try store.save(LauncherSettings(folderRoots: ["/Volumes/Work", "~/Desktop"], folderScanDepth: 1))

        let loaded = store.load()

        XCTAssertEqual(loaded.folderRoots, ["/Volumes/Work", "~/Desktop"])
        XCTAssertEqual(loaded.folderScanDepth, 1)
    }

    func testSave_WritesKoreanAndPlusSignsUnescaped() throws {
        let store = SettingsStore(filePath: settingsPath)
        try store.save(LauncherSettings(hotkey: "Ctrl+Space", folderRoots: ["/Users/me/바탕 화면"]))

        let json = try String(contentsOfFile: settingsPath, encoding: .utf8)

        XCTAssertTrue(json.contains("Ctrl+Space"))
        XCTAssertTrue(json.contains("바탕 화면"))
        XCTAssertFalse(json.contains("\\u"))
        XCTAssertFalse(json.contains("\\/"))
        XCTAssertTrue(json.contains("\"Hotkey\""), "keys are PascalCase like the Windows file")
    }

    func testLoad_UsesDefaults_WhenOlderFileOmitsKeys() {
        writeFile(settingsPath, #"{ "Hotkey": "Cmd+Space" }"#)

        let settings = SettingsStore(filePath: settingsPath).load()

        XCTAssertEqual(settings.hotkey, "Cmd+Space")
        XCTAssertTrue(settings.includeKnownFolders)
        XCTAssertTrue(settings.includeCloudDrives)
        XCTAssertTrue(settings.folderRoots.isEmpty)
        XCTAssertEqual(settings.folderScanDepth, 2)
    }

    func testLoad_ReadsAWindowsSettingsFile() {
        writeFile(settingsPath, #"{ "Hotkey": "Alt+Space", "StartWithWindows": true, "FolderRoots": ["%USERPROFILE%\\Work"], "FolderScanDepth": 3 }"#)

        let settings = SettingsStore(filePath: settingsPath).load()

        XCTAssertEqual(settings.hotkeyOrDefault, HotkeySpec(modifiers: .option, key: "Space"))
        XCTAssertTrue(settings.startAtLogin, "StartWithWindows is read as StartAtLogin")
        XCTAssertEqual(settings.folderScanDepth, 3)
    }

    func testSave_ThenLoad_RoundTrips() throws {
        let store = SettingsStore(filePath: settingsPath)
        try store.save(LauncherSettings(hotkey: "Ctrl+Shift+Space", startAtLogin: true))

        let loaded = store.load()

        XCTAssertEqual(loaded.hotkey, "Ctrl+Shift+Space")
        XCTAssertTrue(loaded.startAtLogin)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsPath + ".tmp"))
    }

    func testLoad_ReturnsDefaults_WhenFileIsCorrupt() {
        writeFile(settingsPath, "{ not json")

        XCTAssertEqual(SettingsStore(filePath: settingsPath).load().hotkey, "Option+Space")
    }

    func testHotkeyOrDefault_FallsBackWhenTextIsInvalid() {
        XCTAssertEqual(LauncherSettings(hotkey: "nonsense").hotkeyOrDefault, HotkeySpec.default)
    }
}
