import Foundation

/// Small file-system helpers shared by the scanners. Everything here swallows errors:
/// a folder that refuses to answer is simply not indexed.
enum FileSystemInfo {
    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// True for symbolic links (lstat, so the link itself is examined, not its target).
    static func isSymbolicLink(_ path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let type = attributes[.type] as? FileAttributeType else {
            return false
        }
        return type == .typeSymbolicLink
    }

    /// Dot-folders everywhere; on macOS also folders carrying the Finder "hidden" flag (~/Library).
    static func isHidden(_ path: String, name: String) -> Bool {
        if name.hasPrefix(".") {
            return true
        }
        #if os(macOS)
        if let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isHiddenKey]), values.isHidden == true {
            return true
        }
        #endif
        return false
    }

    /// Bundles the Finder shows as a single item (.app, .photoslibrary, ...). Never descended into.
    static func isPackage(_ path: String, name: String) -> Bool {
        if name.lowercased().hasSuffix(".app") {
            return true
        }
        #if os(macOS)
        if let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey]), values.isPackage == true {
            return true
        }
        #endif
        return false
    }

    /// Children of `directory`, sorted by name so scans are deterministic. Empty when unreadable.
    static func childNames(of directory: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []).sorted {
            $0.lowercased() < $1.lowercased()
        }
    }

    /// Finder's name for the path: localized ("다운로드" for ~/Downloads on a Korean system) and without
    /// a hidden extension. On other platforms this is the last path component minus ".app".
    static func displayName(_ path: String) -> String {
        var name = FileManager.default.displayName(atPath: path)
        if name.isEmpty {
            name = (path as NSString).lastPathComponent
        }
        if name.lowercased().hasSuffix(".app") {
            name = String(name.dropLast(4))
        }
        return name
    }

    static func resolveSymlinks(_ path: String) -> String {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        return resolved.isEmpty ? path : resolved
    }
}
