import Foundation

/// Loads and saves `LauncherSettings` as a JSON file.
public final class SettingsStore: @unchecked Sendable {
    public let filePath: String

    public init(filePath: String) {
        precondition(!filePath.trimmingCharacters(in: .whitespaces).isEmpty, "filePath must not be blank")
        self.filePath = filePath
    }

    /// ~/Library/Application Support/AppLauncherForMac/settings.json
    public static var defaultPath: String { AppPaths.settingsFile }

    /// Returns defaults when the file is missing or unreadable.
    public func load() -> LauncherSettings {
        guard let data = FileManager.default.contents(atPath: filePath) else {
            return LauncherSettings()
        }

        // Comments and trailing commas are tolerated so the hand-edited file is forgiving (JSON5 superset).
        let decoder = AppPaths.lenientJSONDecoder()
        return (try? decoder.decode(LauncherSettings.self, from: data)) ?? LauncherSettings()
    }

    public func save(_ settings: LauncherSettings) throws {
        let encoder = JSONEncoder()
        // Keep Korean folder names and "+" in hotkeys readable in the file the user edits by hand.
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(settings)
        try AppPaths.writeAtomically(data, to: filePath)
    }
}
