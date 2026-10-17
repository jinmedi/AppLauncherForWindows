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

    func testDescription_RoundTripsThroughParse() throws {
        let original = HotkeySpec(modifiers: [.control, .command], key: "Space")
        let text = original.description

        XCTAssertEqual(text, "Ctrl+Cmd+Space")
        XCTAssertEqual(try HotkeySpec.parse(text), original)
    }

    func testSymbolicDescription_UsesMacGlyphs() {
        XCTAssertEqual(HotkeySpec.default.symbolicDescription, "⌥Space")
        XCTAssertEqual(HotkeySpec(modifiers: [.control, .shift], key: "K").symbolicDescription, "⌃⇧K")
    }

    func testCarbonKeyCode_KnowsLettersDigitsAndNamedKeys() {
        XCTAssertEqual(HotkeySpec.default.carbonKeyCode, 0x31)
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
