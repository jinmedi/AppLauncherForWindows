import Foundation
import XCTest

/// A throw-away directory per test, removed on tearDown.
class TemporaryDirectoryTestCase: XCTestCase {
    private(set) var baseDir = ""

    override func setUpWithError() throws {
        try super.setUpWithError()
        baseDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppLauncherTests")
            .appendingPathComponent(UUID().uuidString)
            .path
        try FileManager.default.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: baseDir)
        try super.tearDownWithError()
    }

    @discardableResult
    func makeDir(_ parts: String...) -> String {
        let path = ([baseDir] + parts).joined(separator: "/")
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    func writeFile(_ path: String, _ text: String) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: URL(fileURLWithPath: path))
    }

    /// Marks a folder hidden the Finder way (UF_HIDDEN); returns false where the platform cannot.
    func setHidden(_ path: String) -> Bool {
        #if os(macOS)
        var url = URL(fileURLWithPath: path)
        var values = URLResourceValues()
        values.isHidden = true
        do {
            try url.setResourceValues(values)
            return true
        } catch {
            return false
        }
        #else
        return false
        #endif
    }
}
