import Foundation

/// Where the launcher keeps its files: ~/Library/Application Support/AppLauncherForMac/.
public enum AppPaths {
    public static let folderName = "AppLauncherForMac"

    public static var supportDirectory: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent(folderName).path
    }

    public static var settingsFile: String { supportDirectory + "/settings.json" }
    public static var historyFile: String { supportDirectory + "/history.json" }
    public static var indexLogFile: String { supportDirectory + "/index.log" }

    /// Expands "~", "$VAR" and "${VAR}" and resolves ".." so the same folder is never indexed twice.
    /// Returns nil for blank input.
    public static func normalizePath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }

        let expanded = expandEnvironment((trimmed as NSString).expandingTildeInPath)
        var standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        while standardized.count > 1 && standardized.hasSuffix("/") {
            standardized.removeLast()
        }
        return standardized
    }

    static func expandEnvironment(_ text: String) -> String {
        guard text.contains("$") else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            guard ch == "$" else {
                result.append(ch)
                index = text.index(after: index)
                continue
            }

            var nameStart = text.index(after: index)
            var braced = false
            if nameStart < text.endIndex, text[nameStart] == "{" {
                braced = true
                nameStart = text.index(after: nameStart)
            }

            var nameEnd = nameStart
            while nameEnd < text.endIndex, text[nameEnd].isLetter || text[nameEnd].isNumber || text[nameEnd] == "_" {
                nameEnd = text.index(after: nameEnd)
            }

            let name = String(text[nameStart..<nameEnd])
            if name.isEmpty || (braced && (nameEnd >= text.endIndex || text[nameEnd] != "}")) {
                result.append(ch)
                index = text.index(after: index)
                continue
            }

            if let value = getenv(name) {
                result.append(String(cString: value))
            }
            index = braced ? text.index(after: nameEnd) : nameEnd
        }
        return result
    }

    /// Writes to a temp file first so a crash mid-write never leaves a truncated file.
    public static func writeAtomically(_ data: Data, to path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        if !directory.isEmpty {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        let tempPath = path + ".tmp"
        try data.write(to: URL(fileURLWithPath: tempPath))
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
        try FileManager.default.moveItem(atPath: tempPath, toPath: path)
    }

    /// Builds a JSONDecoder that tolerates comments and trailing commas where the platform supports it.
    public static func lenientJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        #if os(macOS)
        decoder.allowsJSON5 = true
        #endif
        return decoder
    }
}
