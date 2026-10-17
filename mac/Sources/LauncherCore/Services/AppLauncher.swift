import Foundation

/// Starts an entry. Throws on failure so the caller can show a message.
public protocol AppLaunching {
    func launch(_ entry: AppEntry) throws
}

public struct LaunchError: Error, CustomStringConvertible {
    public let path: String
    public let reason: String?

    public init(path: String, reason: String? = nil) {
        self.path = path
        self.reason = reason
    }

    public var description: String {
        if let reason, !reason.isEmpty {
            return reason
        }
        return "열 수 없습니다: \(path)"
    }
}
