#if canImport(AppKit)
import AppKit
import LauncherCore

/// Launches through NSWorkspace: apps are opened (or activated when already running), folders open in Finder.
struct WorkspaceLauncher: AppLaunching {
    func launch(_ entry: AppEntry) throws {
        guard FileManager.default.fileExists(atPath: entry.launchPath) else {
            throw LaunchError(path: entry.launchPath, reason: "경로를 찾을 수 없습니다: \(entry.launchPath)")
        }

        let url = URL(fileURLWithPath: entry.launchPath)
        if entry.source == .folder {
            guard NSWorkspace.shared.open(url) else {
                throw LaunchError(path: entry.launchPath)
            }
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                NSLog("[AppLauncher] launch failed for %@: %@", entry.launchPath, error.localizedDescription)
            }
        }
    }
}
#endif
