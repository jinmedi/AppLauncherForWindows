import Foundation

/// Where an index entry came from. Mirrors the Windows `AppSource` enum.
public enum AppSourceKind: String, Codable, Sendable {
    case application
    case folder
    case custom
}

/// One launchable item in the index.
public struct AppEntry: Hashable, Sendable {
    /// Stable, case-insensitive key used for de-duplication and usage history.
    public let id: String

    /// Display name, e.g. "카카오톡". For apps this is the Finder (localized) name.
    public let name: String

    /// What gets handed to NSWorkspace to launch: the .app bundle or the folder itself.
    public let launchPath: String

    /// Resolved executable inside the bundle, when known. Used as a search keyword.
    public let targetPath: String?

    public let description: String?

    public let source: AppSourceKind

    /// Extra searchable terms (bundle name, executable name, parent folder, other-language name).
    public let keywords: [String]

    public init(
        id: String,
        name: String,
        launchPath: String,
        targetPath: String? = nil,
        description: String? = nil,
        source: AppSourceKind = .application,
        keywords: [String] = []
    ) {
        self.id = id
        self.name = name
        self.launchPath = launchPath
        self.targetPath = targetPath
        self.description = description
        self.source = source
        self.keywords = keywords
    }

    /// Copy with extra keywords appended (used when two sources describe the same path).
    public func addingKeywords(_ extra: [String]) -> AppEntry {
        AppEntry(
            id: id,
            name: name,
            launchPath: launchPath,
            targetPath: targetPath,
            description: description,
            source: source,
            keywords: keywords + extra
        )
    }
}
