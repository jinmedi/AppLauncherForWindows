import Foundation

/// Modifier flags for a global hotkey. Raw values match the Carbon `cmdKey`/`shiftKey`/`optionKey`/`controlKey`
/// constants so they can be passed straight to `RegisterEventHotKey`.
public struct HotkeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotkeyModifiers(rawValue: 0x0100)
    public static let shift = HotkeyModifiers(rawValue: 0x0200)
    public static let option = HotkeyModifiers(rawValue: 0x0800)
    public static let control = HotkeyModifiers(rawValue: 0x1000)
}

/// A parsed hotkey such as "Option+Space" or "Cmd+Shift+K".
/// The key is kept as a name so Core stays UI-agnostic; `carbonKeyCode` maps it for registration.
public struct HotkeySpec: Hashable, Sendable, CustomStringConvertible {
    public let modifiers: HotkeyModifiers
    public let key: String

    public init(modifiers: HotkeyModifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Option+Space: Spotlight owns Cmd+Space, and Option+Space is what Alt+Space becomes on a Mac keyboard.
    public static let `default` = HotkeySpec(modifiers: .option, key: "Space")

    public struct ParseError: Error, CustomStringConvertible {
        public let text: String
        public var description: String { "'\(text)' is not a valid hotkey. Expected e.g. \"Option+Space\"." }
    }

    public static func parse(_ text: String) throws -> HotkeySpec {
        guard let spec = tryParse(text) else {
            throw ParseError(text: text)
        }
        return spec
    }

    /// Returns nil for blank text, a key without modifiers, an unknown modifier, or a modifier used as the key.
    public static func tryParse(_ text: String?) -> HotkeySpec? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        let parts = text.split(separator: "+", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else {
            return nil
        }

        var modifiers: HotkeyModifiers = []
        for part in parts.dropLast() {
            guard let modifier = parseModifier(part) else {
                return nil
            }
            modifiers.formUnion(modifier)
        }

        let key = parts[parts.count - 1]
        if key.isEmpty || parseModifier(key) != nil {
            return nil
        }

        return HotkeySpec(modifiers: modifiers, key: normalizeKey(key))
    }

    /// Settings-file form: "Ctrl+Option+Shift+Cmd+Key".
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// On-screen form with Mac symbols: "⌥Space", "⌃⇧K".
    public var symbolicDescription: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + key
    }

    /// Virtual key code for `RegisterEventHotKey`; nil when the key name is not one we know.
    public var carbonKeyCode: UInt32? {
        HotkeySpec.keyCodes[key.lowercased()]
    }

    private static func parseModifier(_ token: String) -> HotkeyModifiers? {
        switch token.lowercased() {
        case "ctrl", "control", "⌃": return .control
        case "alt", "option", "opt", "⌥": return .option
        case "shift", "⇧": return .shift
        // "Win" is accepted so a settings file copied from the Windows launcher still parses.
        case "cmd", "command", "⌘", "win", "windows", "super": return .command
        default: return nil
        }
    }

    /// Single letters are upper-cased so "k" and "K" are the same key; WPF digit names ("D1") become "1".
    private static func normalizeKey(_ key: String) -> String {
        if key.count == 1, let scalar = key.unicodeScalars.first, scalar.isASCII, CharacterSet.letters.contains(scalar) {
            return key.uppercased()
        }
        if key.count == 2, key.hasPrefix("D"), let last = key.last, last.isNumber {
            return String(last)
        }
        return key
    }

    /// Carbon virtual key codes (Events.h) keyed by lower-cased key name.
    private static let keyCodes: [String: UInt32] = {
        var map: [String: UInt32] = [
            "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
            "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
            "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "=": 0x18,
            "9": 0x19, "7": 0x1A, "-": 0x1B, "8": 0x1C, "0": 0x1D, "]": 0x1E, "o": 0x1F, "u": 0x20,
            "[": 0x21, "i": 0x22, "p": 0x23, "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
            "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E, ".": 0x2F, "`": 0x32,
            "space": 0x31, "return": 0x24, "enter": 0x24, "tab": 0x30, "delete": 0x33, "backspace": 0x33,
            "escape": 0x35, "esc": 0x35, "forwarddelete": 0x75,
            "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
            "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
            "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76, "f5": 0x60, "f6": 0x61, "f7": 0x62,
            "f8": 0x64, "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F, "f13": 0x69, "f14": 0x6B,
            "f15": 0x71, "f16": 0x6A, "f17": 0x40, "f18": 0x4F, "f19": 0x50, "f20": 0x5A,
        ]
        map["equal"] = map["="]
        map["minus"] = map["-"]
        map["comma"] = map[","]
        map["period"] = map["."]
        map["slash"] = map["/"]
        map["backslash"] = map["\\"]
        map["semicolon"] = map[";"]
        map["quote"] = map["'"]
        map["grave"] = map["`"]
        map["leftbracket"] = map["["]
        map["rightbracket"] = map["]"]
        return map
    }()
}
