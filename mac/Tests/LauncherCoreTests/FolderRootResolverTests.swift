import XCTest
@testable import LauncherCore

final class FolderRootResolverTests: TemporaryDirectoryTestCase {
    func testResolve_CombinesKnownCloudAndUserRoots_InThatOrder() {
        let settings = LauncherSettings(folderRoots: ["/Volumes/Work"])

        let roots = FolderRootResolver.resolve(settings, knownFolders: ["/Users/me/Desktop"], cloudRoots: ["/Users/me/Library/CloudStorage/GoogleDrive-me/내 드라이브"])

        XCTAssertEqual(roots, ["/Users/me/Desktop", "/Users/me/Library/CloudStorage/GoogleDrive-me/내 드라이브", "/Volumes/Work"])
    }

    func testResolve_HonoursIncludeFlags() {
        let settings = LauncherSettings(includeKnownFolders: false, includeCloudDrives: false, folderRoots: ["/Volumes/Work"])

        let roots = FolderRootResolver.resolve(settings, knownFolders: ["/Users/me/Desktop"], cloudRoots: ["/Users/me/Dropbox"])

        XCTAssertEqual(roots, ["/Volumes/Work"])
    }

    func testResolve_DeduplicatesCaseInsensitivelyAndIgnoresTrailingSeparators() {
        let settings = LauncherSettings(folderRoots: ["/users/ME/desktop/", "", "  "])

        let roots = FolderRootResolver.resolve(settings, knownFolders: ["/Users/me/Desktop"], cloudRoots: [])

        XCTAssertEqual(roots.count, 1)
    }

    func testResolve_ExpandsTildeAndEnvironmentVariables() {
        setenv("APPLAUNCHER_TEST_ROOT", "/Volumes/FromEnv", 1)
        defer { unsetenv("APPLAUNCHER_TEST_ROOT") }

        let roots = FolderRootResolver.resolve(
            LauncherSettings(folderRoots: ["$APPLAUNCHER_TEST_ROOT/Sub", "${APPLAUNCHER_TEST_ROOT}/Other", "~/Desktop"]),
            knownFolders: [],
            cloudRoots: []
        )

        XCTAssertEqual(roots, ["/Volumes/FromEnv/Sub", "/Volumes/FromEnv/Other", NSHomeDirectory() + "/Desktop"])
    }

    func testCloudRoots_FindsICloudAndCloudStorageProviders() {
        let home = makeDir("home")
        let icloud = makeDir("home", "Library", "Mobile Documents", "com~apple~CloudDocs")
        let oneDrive = makeDir("home", "Library", "CloudStorage", "OneDrive-Personal")
        let dropbox = makeDir("home", "Library", "CloudStorage", "Dropbox")
        makeDir("home", "Library", "CloudStorage", ".hidden")

        let roots = FolderRootResolver.cloudRoots(home: home, dropboxInfoPath: nil, volumesDirectory: baseDir + "/no-volumes")

        XCTAssertEqual(roots, [icloud, dropbox, oneDrive])
    }

    func testCloudRoots_UsesGoogleDriveTopLevelFolders_SkippingDotFolders() {
        let home = makeDir("home")
        let drive = makeDir("home", "Library", "CloudStorage", "GoogleDrive-me@gmail.com")
        let myDrive = makeDir("home", "Library", "CloudStorage", "GoogleDrive-me@gmail.com", "내 드라이브")
        let computers = makeDir("home", "Library", "CloudStorage", "GoogleDrive-me@gmail.com", "다른 컴퓨터")
        makeDir("home", "Library", "CloudStorage", "GoogleDrive-me@gmail.com", ".shortcut-targets-by-id")

        let roots = FolderRootResolver.cloudRoots(home: home, dropboxInfoPath: nil, volumesDirectory: baseDir + "/no-volumes")

        XCTAssertEqual(Set(roots), Set([myDrive, computers]))
        XCTAssertFalse(roots.contains(drive))
    }

    func testCloudRoots_FindsLegacyVolumeAndHomeFolderClients() {
        let home = makeDir("home")
        let volumes = makeDir("Volumes")
        let legacyMyDrive = makeDir("Volumes", "GoogleDrive", "My Drive")
        let mirror = makeDir("home", "Google Drive")
        let dropbox = makeDir("home", "Dropbox")
        let oneDriveWork = makeDir("home", "OneDrive - Company")
        makeDir("home", "Documents")

        let roots = FolderRootResolver.cloudRoots(home: home, dropboxInfoPath: nil, volumesDirectory: volumes)

        XCTAssertEqual(Set(roots), Set([legacyMyDrive, mirror, dropbox, oneDriveWork]))
    }

    func testCloudRoots_ReadsDropboxInfoJson() {
        let personal = makeDir("Dropbox")
        let business = makeDir("Dropbox (Work)")
        let info = baseDir + "/info.json"
        writeFile(info, """
        { "business": { "path": "\(business)" },
          "personal": { "path": "\(personal)", "host": 1 },
          "broken": { "path": "/does/not/exist" } }
        """)

        let roots = FolderRootResolver.cloudRoots(home: makeDir("home"), dropboxInfoPath: info, volumesDirectory: baseDir + "/no-volumes")

        XCTAssertEqual(roots, [personal, business])
    }

    func testCloudRoots_ToleratesCorruptDropboxInfo() {
        let info = baseDir + "/info.json"
        writeFile(info, "{ not json")

        let roots = FolderRootResolver.cloudRoots(home: makeDir("home"), dropboxInfoPath: info, volumesDirectory: baseDir + "/no-volumes")

        XCTAssertTrue(roots.isEmpty)
    }

    func testKnownFolders_ContainsSevenHomeRelativePaths() {
        let known = FolderRootResolver.knownFolders(home: "/Users/me")

        XCTAssertEqual(known.count, 7)
        XCTAssertTrue(known.allSatisfy { $0.hasPrefix("/Users/me") })
        XCTAssertTrue(known.contains("/Users/me/Downloads"))
        XCTAssertTrue(known.contains("/Users/me/Movies"))
        XCTAssertEqual(known.last, "/Users/me")
    }
}
