import Foundation

/// Modifier flags for a global hotkey. The low 16 bits match the Carbon `cmdKey`/`shiftKey`/`optionKey`/
/// `controlKey` constants so they can be passed straight to `RegisterEventHotKey`. The side-specific flags
/// (right Option, left Command, ...) are our own: Carbon cannot tell the two Option keys apart, so a spec
/// that uses one of them is registered through a CGEvent tap instead (see `requiresEventTap`).
public struct HotkeyModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let command = HotkeyModifiers(rawValue: 0x0100)
    public static let shift = HotkeyModifiers(rawValue: 0x0200)
    public static let option = HotkeyModifiers(rawValue: 0x0800)
    public static let control = HotkeyModifiers(rawValue: 0x1000)

    public static let leftOption = HotkeyModifiers(rawValue: 0x1_0000)
    public static let rightOption = HotkeyModifiers(rawValue: 0x2_0000)
    public static let leftCommand = HotkeyModifiers(rawValue: 0x4_0000)
    public static let rightCommand = HotkeyModifiers(rawValue: 0x8_0000)

    static let sideSpecific: HotkeyModifiers = [.leftOption, .rightOption, .leftCommand, .rightCommand]

    /// Either Option key, or a specific one.
    public var wantsOption: Bool { !isDisjoint(with: [.option, .leftOption, .rightOption]) }

    /// Either Command key, or a specific one.
    public var wantsCommand: Bool { !isDisjoint(with: [.command, .leftCommand, .rightCommand]) }

    /// What `RegisterEventHotKey` understands: side-specific keys collapse to their generic modifier.
    public var carbonModifiers: UInt32 {
        var value = rawValue & 0xFF00
        if wantsOption { value |= HotkeyModifiers.option.rawValue }
        if wantsCommand { value |= HotkeyModifiers.command.rawValue }
        return value
    }
}

/// A parsed hotkey such as "RightOption+Return" or "Cmd+Shift+K".
/// The key is kept as a name so Core stays UI-agnostic; `carbonKeyCode` maps it for registration.
public struct HotkeySpec: Hashable, Sendable, CustomStringConvertible {
    public let modifiers: HotkeyModifiers
    public let key: String

    public init(modifiers: HotkeyModifiers, key: String) {
        self.modifiers = modifiers
        self.key = key
    }

    /// Right Option + Return: a two-key chord nothing else uses, reachable with the right hand alone.
    public static let `default` = HotkeySpec(modifiers: .rightOption, key: "Return")

    public struct ParseError: Error, CustomStringConvertible {
        public let text: String
        public var description: String { "'\(text)' is not a valid hotkey. Expected e.g. \"RightOption+Return\"." }
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

    /// True when a left/right-specific modifier is used; Carbon cannot register those, a CGEvent tap can.
    public var requiresEventTap: Bool {
        !modifiers.isDisjoint(with: HotkeyModifiers.sideSpecific)
    }

    /// The same chord with side-specific modifiers collapsed to generic ones (the Carbon fallback).
    public var genericEquivalent: HotkeySpec {
        HotkeySpec(modifiers: HotkeyModifiers(rawValue: modifiers.carbonModifiers), key: key)
    }

    /// Settings-file form: "Ctrl+RightOption+Shift+Cmd+Key".
    public var description: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("Ctrl") }
        if modifiers.contains(.option) { parts.append("Option") }
        if modifiers.contains(.leftOption) { parts.append("LeftOption") }
        if modifiers.contains(.rightOption) { parts.append("RightOption") }
        if modifiers.contains(.shift) { parts.append("Shift") }
        if modifiers.contains(.command) { parts.append("Cmd") }
        if modifiers.contains(.leftCommand) { parts.append("LeftCmd") }
        if modifiers.contains(.rightCommand) { parts.append("RightCmd") }
        parts.append(key)
        return parts.joined(separator: "+")
    }

    /// On-screen form with Mac symbols: "오른쪽⌥Return", "⌃⇧K".
    public var symbolicDescription: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.leftOption) { text += "왼쪽⌥" }
        if modifiers.contains(.rightOption) { text += "오른쪽⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        if modifiers.contains(.leftCommand) { text += "왼쪽⌘" }
        if modifiers.contains(.rightCommand) { text += "오른쪽⌘" }
        return text + key
    }

    /// Virtual key code for `RegisterEventHotKey` / `CGEvent`; nil when the key name is not one we know.
    public var carbonKeyCode: UInt32? {
        HotkeySpec.keyCodes[key.lowercased()]
    }

    /// Every key code that counts as this key in a CGEvent: Return also accepts the keypad Enter.
    public var eventKeyCodes: Set<UInt32> {
        guard let code = carbonKeyCode else { return [] }
        return code == 0x24 ? [0x24, 0x4C] : [code]
    }

    /// Whether a CGEvent's modifier flags (`CGEventFlags.rawValue`) satisfy this spec exactly:
    /// the generic modifiers must match one-for-one, and a side-specific modifier needs its device bit.
    public func matches(eventFlags flags: UInt64) -> Bool {
        let command = flags & 0x0010_0000 != 0   // kCGEventFlagMaskCommand
        let option = flags & 0x0008_0000 != 0    // kCGEventFlagMaskAlternate
        let control = flags & 0x0004_0000 != 0   // kCGEventFlagMaskControl
        let shift = flags & 0x0002_0000 != 0     // kCGEventFlagMaskShift

        guard command == modifiers.wantsCommand,
              option == modifiers.wantsOption,
              control == modifiers.contains(.control),
              shift == modifiers.contains(.shift) else {
            return false
        }

        // NX_DEVICE*KEYMASK bits tell the two keys of a pair apart.
        if modifiers.contains(.leftOption) && flags & 0x20 == 0 { return false }
        if modifiers.contains(.rightOption) && flags & 0x40 == 0 { return false }
        if modifiers.contains(.leftCommand) && flags & 0x08 == 0 { return false }
        if modifiers.contains(.rightCommand) && flags & 0x10 == 0 { return false }
        return true
    }

    private static func parseModifier(_ token: String) -> HotkeyModifiers? {
        // "Right Option", "right-option" and "RightOption" are the same token.
        let normalized = token.lowercased().filter { $0 != " " && $0 != "-" && $0 != "_" }
        switch normalized {
        case "ctrl", "control", "⌃": return .control
        case "alt", "option", "opt", "⌥": return .option
        case "leftoption", "loption", "lopt", "leftalt", "lalt", "왼쪽option", "왼쪽⌥": return .leftOption
        case "rightoption", "roption", "ropt", "rightalt", "ralt", "오른쪽option", "오른쪽⌥": return .rightOption
        case "shift", "⇧": return .shift
        // "Win" is accepted so a settings file copied from the Windows launcher still parses.
        case "cmd", "command", "⌘", "win", "windows", "super": return .command
        case "leftcmd", "leftcommand", "lcmd", "왼쪽⌘": return .leftCommand
        case "rightcmd", "rightcommand", "rcmd", "오른쪽⌘": return .rightCommand
        default: return nil
        }
    }

    /// Single letters are upper-cased so "k" and "K" are the same key; WPF digit names ("D1") become "1";
    /// "Enter" is the Return key.
    private static func normalizeKey(_ key: String) -> String {
        if key.count == 1, let scalar = key.unicodeScalars.first, scalar.isASCII, CharacterSet.letters.contains(scalar) {
            return key.uppercased()
        }
        if key.count == 2, key.hasPrefix("D"), let last = key.last, last.isNumber {
            return String(last)
        }
        if key.lowercased() == "enter" {
            return "Return"
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
