import XCTest
@testable import LauncherCore

final class HotkeySpecTests: XCTestCase {
    func testTryParse_AcceptsValidCombinations() {
        let cases: [(String, HotkeyModifiers, String)] = [
            ("Option+Space", .option, "Space"),
            ("Alt+Space", .option, "Space"),
            ("ctrl + shift + k", [.control, .shift], "K"),
            ("Cmd+1", .command, "1"),
            ("Win+D1", .command, "1"),
            ("Control+Alt+F12", [.control, .option], "F12"),
            ("⌘+⇧+Space", [.command, .shift], "Space"),
            ("RightOption+Return", .rightOption, "Return"),
            ("right option + enter", .rightOption, "Return"),
            ("RAlt+Enter", .rightOption, "Return"),
            ("오른쪽⌥+Return", .rightOption, "Return"),
            ("LeftCmd+Shift+Space", [.leftCommand, .shift], "Space"),
        ]
        for (text, modifiers, key) in cases {
            let spec = HotkeySpec.tryParse(text)
            XCTAssertNotNil(spec, text)
            XCTAssertEqual(spec?.modifiers, modifiers, text)
            XCTAssertEqual(spec?.key, key, text)
        }
    }

    func testTryParse_RejectsInvalidInput() {
        let cases: [String?] = [nil, "", "Space", "Alt+", "Foo+Space", "Alt+Ctrl"]
        for text in cases {
            XCTAssertNil(HotkeySpec.tryParse(text), text ?? "nil")
        }
    }

    func testIsSameChord_IgnoresKeyNameCase_ButNotModifiers() {
        let spec = HotkeySpec(modifiers: .control, key: "Space")

        XCTAssertTrue(spec.isSameChord(as: HotkeySpec(modifiers: .control, key: "space")))
        XCTAssertTrue(spec.isSameChord(as: try! HotkeySpec.parse("ctrl + SPACE")))
        XCTAssertFalse(spec.isSameChord(as: HotkeySpec(modifiers: .control, key: "Return")))
        XCTAssertFalse(spec.isSameChord(as: HotkeySpec(modifiers: [.control, .shift], key: "Space")))
    }

    func testDescription_RoundTripsThroughParse() throws {
        let original = HotkeySpec(modifiers: [.control, .command], key: "Space")
        let text = original.description

        XCTAssertEqual(text, "Ctrl+Cmd+Space")
        XCTAssertEqual(try HotkeySpec.parse(text), original)
    }

    func testDefault_IsRightOptionReturn() {
        XCTAssertEqual(HotkeySpec.default, HotkeySpec(modifiers: .rightOption, key: "Return"))
        XCTAssertEqual(HotkeySpec.default.description, "RightOption+Return")
        XCTAssertTrue(HotkeySpec.default.requiresEventTap)
        XCTAssertEqual(try HotkeySpec.parse(HotkeySpec.default.description), HotkeySpec.default)
    }

    func testSymbolicDescription_UsesMacGlyphs() {
        XCTAssertEqual(HotkeySpec.default.symbolicDescription, "오른쪽⌥Return")
        XCTAssertEqual(HotkeySpec(modifiers: .option, key: "Space").symbolicDescription, "⌥Space")
        XCTAssertEqual(HotkeySpec(modifiers: [.control, .shift], key: "K").symbolicDescription, "⌃⇧K")
    }

    func testGenericEquivalent_CollapsesSidesForCarbon() {
        let generic = HotkeySpec.default.genericEquivalent

        XCTAssertEqual(generic, HotkeySpec(modifiers: .option, key: "Return"))
        XCTAssertFalse(generic.requiresEventTap)
        XCTAssertEqual(HotkeySpec.default.modifiers.carbonModifiers, 0x0800)
        XCTAssertEqual(HotkeySpec(modifiers: [.rightCommand, .shift], key: "K").modifiers.carbonModifiers, 0x0300)
        XCTAssertFalse(HotkeySpec(modifiers: [.command, .shift], key: "K").requiresEventTap)
    }

    func testMatchesEventFlags_RequiresTheRightOptionKey() {
        let spec = HotkeySpec.default
        let option: UInt64 = 0x0008_0000
        let leftOption: UInt64 = option | 0x20
        let rightOption: UInt64 = option | 0x40
        let command: UInt64 = 0x0010_0000

        XCTAssertTrue(spec.matches(eventFlags: rightOption))
        XCTAssertTrue(spec.matches(eventFlags: rightOption | 0x0001_0000), "caps lock is ignored")
        XCTAssertFalse(spec.matches(eventFlags: leftOption))
        XCTAssertFalse(spec.matches(eventFlags: rightOption | command), "extra modifiers do not match")
        XCTAssertFalse(spec.matches(eventFlags: 0))

        let generic = HotkeySpec(modifiers: .option, key: "Return")
        XCTAssertTrue(generic.matches(eventFlags: leftOption))
        XCTAssertTrue(generic.matches(eventFlags: rightOption))

        let cmdShift = HotkeySpec(modifiers: [.command, .shift], key: "K")
        XCTAssertTrue(cmdShift.matches(eventFlags: command | 0x0002_0000))
        XCTAssertFalse(cmdShift.matches(eventFlags: command))
    }

    func testEventKeyCodes_ReturnAlsoAcceptsKeypadEnter() {
        XCTAssertEqual(HotkeySpec.default.eventKeyCodes, [0x24, 0x4C])
        XCTAssertEqual(HotkeySpec(modifiers: .option, key: "Space").eventKeyCodes, [0x31])
        XCTAssertTrue(HotkeySpec(modifiers: .option, key: "Hyper").eventKeyCodes.isEmpty)
    }

    func testCarbonKeyCode_KnowsLettersDigitsAndNamedKeys() {
        XCTAssertEqual(HotkeySpec.default.carbonKeyCode, 0x24)
        XCTAssertEqual(HotkeySpec(modifiers: .option, key: "Space").carbonKeyCode, 0x31)
        XCTAssertEqual(HotkeySpec(modifiers: .command, key: "K").carbonKeyCode, 0x28)
        XCTAssertEqual(HotkeySpec(modifiers: .command, key: "1").carbonKeyCode, 0x12)
        XCTAssertEqual(HotkeySpec(modifiers: .command, key: "F12").carbonKeyCode, 0x6F)
        XCTAssertNil(HotkeySpec(modifiers: .command, key: "Hyper").carbonKeyCode)
    }

    func testModifiers_MatchCarbonConstants() {
        XCTAssertEqual(HotkeyModifiers.command.rawValue, 0x0100) // cmdKey
        XCTAssertEqual(HotkeyModifiers.shift.rawValue, 0x0200)   // shiftKey
        XCTAssertEqual(HotkeyModifiers.option.rawValue, 0x0800)  // optionKey
        XCTAssertEqual(HotkeyModifiers.control.rawValue, 0x1000) // controlKey
    }

    func testParse_ThrowsOnInvalidText() {
        XCTAssertThrowsError(try HotkeySpec.parse("nonsense"))
    }
}
