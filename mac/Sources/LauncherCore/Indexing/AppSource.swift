import Foundation

/// Something that can enumerate launchable items (application folders, user folders, ...).
/// `scan` runs on a background task, so implementations must be self-contained values.
public protocol AppSource: Sendable {
    var name: String { get }

    func scan() throws -> [AppEntry]
}
