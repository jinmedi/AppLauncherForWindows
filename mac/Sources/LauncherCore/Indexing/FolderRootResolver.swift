import Foundation

/// Builds the list of folders `FolderScanner` indexes: the well-known home folders, auto-detected
/// cloud-sync roots (iCloud Drive, Google Drive, Dropbox, OneDrive, anything else under
/// ~/Library/CloudStorage) and the user's own `LauncherSettings.folderRoots`. Detection runs at
/// startup, so a Mac with a different account picks up its own folders without editing settings.
public enum FolderRootResolver {
    public static func resolve(_ settings: LauncherSettings) -> [String] {
        resolve(settings, knownFolders: knownFolders(), cloudRoots: cloudRoots())
    }

    /// Composition only; the detectors are passed in so it can be unit-tested.
    public static func resolve(_ settings: LauncherSettings, knownFolders: [String], cloudRoots: [String]) -> [String] {
        var result: [String] = []
        var seen = Set<String>()

        func addAll(_ paths: [String]) {
            for path in paths {
                if let normalized = AppPaths.normalizePath(path), seen.insert(normalized.lowercased()).inserted {
                    result.append(normalized)
                }
            }
        }

        if settings.includeKnownFolders {
            addAll(knownFolders)
        }
        if settings.includeCloudDrives {
            addAll(cloudRoots)
        }
        addAll(settings.folderRoots)
        return result
    }

    /// Desktop, Documents, Downloads, Pictures, Movies, Music and the home folder itself.
    public static func knownFolders(home: String = NSHomeDirectory()) -> [String] {
        [
            home + "/Desktop",
            home + "/Documents",
            home + "/Downloads",
            home + "/Pictures",
            home + "/Movies",
            home + "/Music",
            home,
        ]
    }

    /// Detects cloud-sync roots on this machine.
    public static func cloudRoots() -> [String] {
        let home = NSHomeDirectory()
        return cloudRoots(home: home, dropboxInfoPath: home + "/.dropbox/info.json")
    }

    /// Detection logic with its inputs injected so it can be unit-tested.
    /// - Parameters:
    ///   - home: the user's home folder.
    ///   - dropboxInfoPath: Dropbox's `~/.dropbox/info.json`, or nil.
    ///   - volumesDirectory: where legacy Google Drive File Stream mounted its volume (/Volumes).
    public static func cloudRoots(home: String, dropboxInfoPath: String?, volumesDirectory: String = "/Volumes") -> [String] {
        var roots: [String] = []

        // iCloud Drive lives under an internal name; Finder shows it as "iCloud Drive".
        let icloud = home + "/Library/Mobile Documents/com~apple~CloudDocs"
        if FileSystemInfo.isDirectory(icloud) {
            roots.append(icloud)
        }

        // macOS 12+ File Provider roots: GoogleDrive-<account>, OneDrive-Personal, Dropbox, Box-Box, ...
        let cloudStorage = home + "/Library/CloudStorage"
        for provider in FileSystemInfo.childNames(of: cloudStorage) where !provider.hasPrefix(".") {
            let path = cloudStorage + "/" + provider
            guard FileSystemInfo.isDirectory(path) else { continue }
            if provider.lowercased().hasPrefix("googledrive") {
                // Its top level holds "내 드라이브"/"My Drive", "공유 드라이브"/"Shared drives", "다른 컴퓨터". Each becomes a root.
                roots.append(contentsOf: topLevelFolders(path))
            } else {
                roots.append(path)
            }
        }

        // Legacy streaming Google Drive mounted a volume per account.
        for volume in FileSystemInfo.childNames(of: volumesDirectory) where volume.lowercased().hasPrefix("googledrive") {
            roots.append(contentsOf: topLevelFolders(volumesDirectory + "/" + volume))
        }

        // Older clients (and mirror mode) sync straight into the home folder.
        for name in FileSystemInfo.childNames(of: home) {
            let lower = name.lowercased()
            let isCloudFolder = lower == "google drive" || lower == "my drive" || lower == "내 드라이브"
                || lower == "dropbox" || lower.hasPrefix("dropbox (") || lower.hasPrefix("onedrive")
                || lower == "box" || lower == "box sync" || lower == "icloud drive" || lower == "iclouddrive"
            if isCloudFolder {
                let path = home + "/" + name
                if FileSystemInfo.isDirectory(path) && !FileSystemInfo.isSymbolicLink(path) {
                    roots.append(path)
                }
            }
        }

        roots.append(contentsOf: dropboxFolders(dropboxInfoPath))
        return roots
    }

    private static func topLevelFolders(_ root: String) -> [String] {
        FileSystemInfo.childNames(of: root)
            .filter { !$0.hasPrefix(".") && !$0.hasPrefix("$") }
            .map { root + "/" + $0 }
            .filter { FileSystemInfo.isDirectory($0) && !FileSystemInfo.isHidden($0, name: ($0 as NSString).lastPathComponent) }
    }

    /// Dropbox writes ~/.dropbox/info.json: { "personal": { "path": "..." }, "business": { "path": "..." } }.
    private static func dropboxFolders(_ infoPath: String?) -> [String] {
        guard let infoPath, let data = FileManager.default.contents(atPath: infoPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        return json.keys.sorted { lhs, rhs in
            // "personal" first, then the rest alphabetically, mirroring how Dropbox lists accounts.
            if lhs == "personal" { return true }
            if rhs == "personal" { return false }
            return lhs < rhs
        }
        .compactMap { key -> String? in
            guard let account = json[key] as? [String: Any], let path = account["path"] as? String else {
                return nil
            }
            return FileSystemInfo.isDirectory(path) ? path : nil
        }
    }
}
