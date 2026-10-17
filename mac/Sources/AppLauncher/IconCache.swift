#if canImport(AppKit)
import AppKit

/// Finder icons by path. NSWorkspace already caches internally, but keeping our own map avoids
/// re-resolving the same eight rows on every keystroke.
final class IconCache {
    private var icons: [String: NSImage] = [:]

    func icon(forPath path: String) -> NSImage {
        if let cached = icons[path] {
            return cached
        }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 28, height: 28)
        icons[path] = icon
        return icon
    }
}
#endif
