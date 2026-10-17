#if canImport(AppKit)
import Carbon.HIToolbox
import Foundation

/// Switches the keyboard to an English layout while the launcher is open, so app names can be typed
/// without first leaving the Korean input method, and switches back when the launcher hides.
final class InputSourceSwitcher {
    private static let preferredEnglishIds = ["com.apple.keylayout.ABC", "com.apple.keylayout.US", "com.apple.keylayout.USExtended"]

    private var previous: TISInputSource?

    /// Selects an enabled English keyboard layout, remembering the current source for `restore()`.
    /// Does nothing when the current source is already English or no English layout is enabled.
    func switchToEnglish() {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return
        }
        if Self.isEnglish(current) {
            previous = nil
            return
        }
        guard let english = Self.englishSource() else {
            return
        }
        previous = current
        TISSelectInputSource(english)
    }

    /// Returns to the source that was active before `switchToEnglish()`, if it changed anything.
    func restore() {
        guard let previous else {
            return
        }
        self.previous = nil
        TISSelectInputSource(previous)
    }

    private static func englishSource() -> TISInputSource? {
        let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource as String] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return nil
        }

        let candidates = list.filter { source in
            isEnglish(source) && boolProperty(source, kTISPropertyInputSourceIsSelectCapable) && boolProperty(source, kTISPropertyInputSourceIsEnabled)
        }

        for preferredId in preferredEnglishIds {
            if let match = candidates.first(where: { stringProperty($0, kTISPropertyInputSourceID) == preferredId }) {
                return match
            }
        }
        return candidates.first
    }

    private static func isEnglish(_ source: TISInputSource) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return false
        }
        let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String] ?? []
        return languages.first.map { $0 == "en" || $0.hasPrefix("en-") } ?? false
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return false
        }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue())
    }

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
#endif
