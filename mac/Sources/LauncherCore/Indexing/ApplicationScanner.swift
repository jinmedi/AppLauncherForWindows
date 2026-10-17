import Foundation

/// Enumerates .app bundles under the application folders (/Applications, ~/Applications,
/// /System/Applications and the CoreServices applications), reads their Info.plist and
/// filters out uninstallers and duplicates. Mirrors the Windows Start Menu scanner.
public struct ApplicationScanner: AppSource {
    public static let defaultMaxDepth = 3

    private static let excludedNameFragments = [
        "uninstall", "제거", "삭제",
    ]

    /// Localizations whose InfoPlist.strings are read so both the Korean and the English name are searchable
    /// no matter which language the Mac runs in.
    private static let localizationsToRead = ["ko", "en", "Base", "English", "Korean"]

    public let roots: [String]
    private let maxDepth: Int

    public init(roots: [String]? = nil, maxDepth: Int = ApplicationScanner.defaultMaxDepth) {
        precondition(maxDepth >= 0, "maxDepth must not be negative")
        self.roots = roots ?? ApplicationScanner.defaultRoots()
        self.maxDepth = maxDepth
    }

    public var name: String { "Applications" }

    /// User folder first so a per-user copy wins over the system-wide one with the same path tail.
    public static func defaultRoots(home: String = NSHomeDirectory()) -> [String] {
        [
            home + "/Applications",
            "/Applications",
            "/System/Applications",
            "/System/Library/CoreServices/Applications",
        ]
    }

    public func scan() throws -> [AppEntry] {
        var entries: [AppEntry] = []
        var seenPaths = Set<String>()

        for configuredRoot in roots {
            guard let root = AppPaths.normalizePath(configuredRoot), FileSystemInfo.isDirectory(root) else {
                continue
            }
            walk(&entries, &seenPaths, directory: root, root: root, depth: 1)
        }

        return entries
    }

    private func walk(_ entries: inout [AppEntry], _ seen: inout Set<String>, directory: String, root: String, depth: Int) {
        for childName in FileSystemInfo.childNames(of: directory) where !childName.hasPrefix(".") {
            let childPath = directory + "/" + childName

            if childName.lowercased().hasSuffix(".app") {
                // A symlinked bundle (older Homebrew casks) is indexed once, under its real path.
                let isLink = FileSystemInfo.isSymbolicLink(childPath)
                let bundlePath = isLink ? FileSystemInfo.resolveSymlinks(childPath) : childPath
                let identity = FileSystemInfo.resolveSymlinks(childPath).lowercased()
                guard FileSystemInfo.isDirectory(bundlePath), seen.insert(identity).inserted else {
                    continue
                }
                if let entry = Self.makeEntry(bundlePath: bundlePath, bundleName: childName, root: root, parentDirectory: directory) {
                    entries.append(entry)
                }
                continue
            }

            if depth < maxDepth
                && FileSystemInfo.isDirectory(childPath)
                && !FileSystemInfo.isSymbolicLink(childPath)
                && !FileSystemInfo.isHidden(childPath, name: childName)
                && !FileSystemInfo.isPackage(childPath, name: childName) {
                walk(&entries, &seen, directory: childPath, root: root, depth: depth + 1)
            }
        }
    }

    /// Visible for tests: builds the entry for one bundle, or nil when it is excluded.
    static func makeEntry(bundlePath: String, bundleName: String, root: String, parentDirectory: String) -> AppEntry? {
        let fileName = String(bundleName.dropLast(4))
        if fileName.isEmpty || isExcludedName(fileName) {
            return nil
        }

        let info = readPlist(bundlePath + "/Contents/Info.plist")
        if let packageType = info["CFBundlePackageType"] as? String, packageType != "APPL" {
            return nil
        }

        let displayName = FileSystemInfo.displayName(bundlePath)
        let name = displayName.isEmpty ? fileName : displayName
        if isExcludedName(name) {
            return nil
        }

        var candidates: [String] = [fileName]
        for key in ["CFBundleDisplayName", "CFBundleName", "CFBundleExecutable"] {
            if let value = info[key] as? String {
                candidates.append(value)
            }
        }
        candidates.append(contentsOf: localizedNames(bundlePath: bundlePath))
        if parentDirectory.caseInsensitiveCompare(root) != .orderedSame {
            candidates.append((parentDirectory as NSString).lastPathComponent)
        }

        let keywords = FolderScanner.distinctKeywords(candidates, excluding: name)

        var targetPath: String?
        if let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty {
            targetPath = bundlePath + "/Contents/MacOS/" + executable
        }

        return AppEntry(
            id: "app:" + bundlePath.lowercased(),
            name: name,
            launchPath: bundlePath,
            targetPath: targetPath,
            description: info["CFBundleGetInfoString"] as? String,
            source: .application,
            keywords: keywords
        )
    }

    private static func isExcludedName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return excludedNameFragments.contains { lower.contains($0) }
    }

    /// CFBundleDisplayName / CFBundleName from the Korean and English InfoPlist.strings (or the compiled
    /// InfoPlist.loctable), so "카카오톡" and "KakaoTalk" both match regardless of the system language.
    private static func localizedNames(bundlePath: String) -> [String] {
        var names: [String] = []
        let resources = bundlePath + "/Contents/Resources"

        for localization in localizationsToRead {
            let strings = readPlist(resources + "/" + localization + ".lproj/InfoPlist.strings")
            if let display = strings["CFBundleDisplayName"] as? String { names.append(display) }
            if let bundle = strings["CFBundleName"] as? String { names.append(bundle) }
        }

        let loctable = readPlist(resources + "/InfoPlist.loctable")
        for localization in localizationsToRead {
            if let table = loctable[localization] as? [String: Any] {
                if let display = table["CFBundleDisplayName"] as? String { names.append(display) }
                if let bundle = table["CFBundleName"] as? String { names.append(bundle) }
            }
        }

        return names
    }

    private static func readPlist(_ path: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path) else {
            return [:]
        }
        var format = PropertyListSerialization.PropertyListFormat.xml
        let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        return object as? [String: Any] ?? [:]
    }
}
