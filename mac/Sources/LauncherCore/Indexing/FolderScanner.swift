import Foundation

/// Indexes a set of root folders and their subfolders down to a fixed depth so they can be
/// opened in Finder from the launcher. Hidden folders, dot-folders, symbolic links and packages
/// (.app bundles, photo libraries) are skipped.
public struct FolderScanner: AppSource {
    public static let defaultMaxDepth = 2
    public static let defaultMaxEntries = 10_000

    /// Alternative names people type for well-known roots, keyed by the folder's on-disk name.
    static let rootKeywordsByName: [String: [String]] = [
        "desktop": ["바탕 화면", "데스크탑"],
        "바탕 화면": ["Desktop"],
        "documents": ["문서"],
        "문서": ["Documents"],
        "downloads": ["다운로드"],
        "다운로드": ["Downloads"],
        "pictures": ["사진", "그림"],
        "사진": ["Pictures"],
        "movies": ["동영상", "영화", "Videos"],
        "videos": ["동영상", "Movies"],
        "동영상": ["Movies", "Videos"],
        "music": ["음악"],
        "음악": ["Music"],
        "public": ["공용"],
        "내 드라이브": ["My Drive", "Google Drive", "구글 드라이브"],
        "my drive": ["내 드라이브", "Google Drive", "구글 드라이브"],
        "공유 드라이브": ["Shared drives", "Google Drive", "구글 드라이브"],
        "shared drives": ["공유 드라이브", "Google Drive", "구글 드라이브"],
        "다른 컴퓨터": ["Computers", "Other computers", "Google Drive", "구글 드라이브"],
        "other computers": ["다른 컴퓨터", "Google Drive", "구글 드라이브"],
        "google drive": ["구글 드라이브"],
        "dropbox": ["드롭박스"],
        "com~apple~clouddocs": ["iCloud Drive", "iCloud", "아이클라우드"],
        "icloud drive": ["iCloud", "아이클라우드"],
        "icloud drive (archive)": ["iCloud", "아이클라우드"],
    ]

    /// Never descended into. ~/Library is skipped by the hidden flag; add it as a root if you want it indexed.
    static let skippedFolderNames: Set<String> = [
        "node_modules", "bin", "obj", "__pycache__", ".git", "$recycle.bin", "system volume information",
    ]

    public let roots: [String]
    private let maxDepth: Int
    private let maxEntries: Int

    public init(roots: [String], maxDepth: Int = FolderScanner.defaultMaxDepth, maxEntries: Int = FolderScanner.defaultMaxEntries) {
        precondition(maxDepth >= 0, "maxDepth must not be negative")
        precondition(maxEntries > 0, "maxEntries must be positive")
        self.roots = roots.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        self.maxDepth = maxDepth
        self.maxEntries = maxEntries
    }

    public var name: String { "Folders" }

    public func scan() throws -> [AppEntry] {
        var entries: [AppEntry] = []
        var seen: [String: Int] = [:]

        for configuredRoot in roots {
            guard let root = AppPaths.normalizePath(configuredRoot), FileSystemInfo.isDirectory(root) else {
                continue
            }

            let rawName = (root as NSString).lastPathComponent.isEmpty ? root : (root as NSString).lastPathComponent
            let displayName = FileSystemInfo.displayName(root)

            var keywords = Self.knownKeywords(rawName) ?? Self.knownKeywords(displayName) ?? []
            if rawName.lowercased().hasPrefix("onedrive") {
                keywords.append("원드라이브")
                keywords.append("OneDrive")
            }
            if rawName.lowercased().hasPrefix("googledrive") {
                keywords.append("Google Drive")
                keywords.append("구글 드라이브")
            }
            if rawName.caseInsensitiveCompare(displayName) != .orderedSame {
                keywords.append(rawName)
            }

            Self.add(&entries, &seen, path: root, name: displayName, keywords: keywords)

            if maxDepth > 0 {
                walk(&entries, &seen, directory: root, parentName: displayName, depth: 1)
            }

            if entries.count >= maxEntries {
                break
            }
        }

        return entries
    }

    private func walk(_ entries: inout [AppEntry], _ seen: inout [String: Int], directory: String, parentName: String, depth: Int) {
        for childName in FileSystemInfo.childNames(of: directory) {
            if entries.count >= maxEntries {
                return
            }

            let childPath = directory + "/" + childName
            if Self.skippedFolderNames.contains(childName.lowercased())
                || FileSystemInfo.isHidden(childPath, name: childName)
                || FileSystemInfo.isSymbolicLink(childPath)
                || !FileSystemInfo.isDirectory(childPath)
                || FileSystemInfo.isPackage(childPath, name: childName) {
                continue
            }

            let displayName = FileSystemInfo.displayName(childPath)
            var keywords = [parentName]
            if childName.caseInsensitiveCompare(displayName) != .orderedSame {
                keywords.append(childName)
            }
            if let known = Self.knownKeywords(childName) {
                keywords.append(contentsOf: known)
            }

            Self.add(&entries, &seen, path: childPath, name: displayName, keywords: keywords)

            if depth < maxDepth {
                walk(&entries, &seen, directory: childPath, parentName: displayName, depth: depth + 1)
            }
        }
    }

    /// Adds a folder once. When a root was already picked up as a child of an earlier root (the home
    /// folder contains "OneDrive", for example) the root's keywords are merged into the existing
    /// entry so "원드라이브" still finds it.
    private static func add(_ entries: inout [AppEntry], _ seen: inout [String: Int], path: String, name: String, keywords: [String]) {
        let key = path.lowercased()
        let distinct = distinctKeywords(keywords, excluding: name)

        if let existingIndex = seen[key] {
            let existing = entries[existingIndex]
            let missing = distinct.filter { candidate in
                !existing.keywords.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            }
            if !missing.isEmpty {
                entries[existingIndex] = existing.addingKeywords(missing)
            }
            return
        }

        seen[key] = entries.count
        entries.append(AppEntry(
            id: "folder:" + key,
            name: name,
            launchPath: path,
            source: .folder,
            keywords: distinct
        ))
    }

    /// Composed (NFC) and lower-cased lookup, so a decomposed Hangul name from an HFS+ volume still matches.
    private static func knownKeywords(_ name: String) -> [String]? {
        rootKeywordsByName[name.precomposedStringWithCanonicalMapping.lowercased()]
    }

    static func distinctKeywords(_ keywords: [String], excluding name: String) -> [String] {
        var result: [String] = []
        for keyword in keywords {
            let trimmed = keyword.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.caseInsensitiveCompare(name) == .orderedSame {
                continue
            }
            if result.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                continue
            }
            result.append(trimmed)
        }
        return result
    }
}
