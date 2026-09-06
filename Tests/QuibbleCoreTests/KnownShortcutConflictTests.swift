import XCTest
@testable import QuibbleCore

final class KnownShortcutConflictTests: XCTestCase {
    func testRaycastCommandSpaceDoesNotConflictWithOptionSpace() throws {
        let configured = try XCTUnwrap(KnownShortcutConflict.raycastLegacyPreference("Command-49"))
        XCTAssertFalse(configured.matches(.dictation))
        XCTAssertTrue(configured.matches(.init(keyCode: 49, modifiers: ShortcutBinding.command, keyName: "Space")))
        XCTAssertEqual(configured.source, .raycast)
    }

    func testEnabledSystemHotkeyConvertsCarbonModifierBits() throws {
        // Carbon controlKey (4096) + optionKey (2048), physical Space (49).
        let configured = try XCTUnwrap(KnownShortcutConflict.macOSSymbolicHotKey(
            keyCode: 49, carbonModifiers: 6144, enabled: true
        ))
        XCTAssertEqual(configured.modifiers, 786432)
        XCTAssertTrue(configured.matches(.toggleDictation))
        XCTAssertFalse(configured.matches(.dictation))
        XCTAssertEqual(configured.source, .macOS)
    }

    func testOnlyEnabledAndFullySupportedSystemBindingsAreReported() {
        XCTAssertNil(KnownShortcutConflict.macOSSymbolicHotKey(keyCode: 49, carbonModifiers: 2048, enabled: false))
        XCTAssertNil(KnownShortcutConflict.macOSSymbolicHotKey(keyCode: -1, carbonModifiers: 2048, enabled: true))
        XCTAssertNil(KnownShortcutConflict.macOSSymbolicHotKey(keyCode: 65535, carbonModifiers: 2048, enabled: true))
        // Unknown flags must not be silently stripped into an Option–Space match.
        XCTAssertNil(KnownShortcutConflict.macOSSymbolicHotKey(keyCode: 49, carbonModifiers: 2048 | 8192, enabled: true))
    }

    func testRaycastOptionSpaceAndMultimodifierChordsMatchExactly() throws {
        let optionSpace = try XCTUnwrap(KnownShortcutConflict.raycastLegacyPreference("Option-49"))
        XCTAssertTrue(optionSpace.matches(.dictation))
        XCTAssertFalse(optionSpace.matches(.toggleDictation))
        let paste = try XCTUnwrap(KnownShortcutConflict.raycastLegacyPreference("Command-Control-9"))
        XCTAssertTrue(paste.matches(.pasteLast))
    }

    func testUnsupportedRaycastFormatsNeverCollapseIntoOrdinaryChords() {
        let unsupported = [
            "", "49", "Command", "Option-Option-49", "Command-55", "Fn-Option-49",
            "Alt-49", "Option-49x", "Option--49", "Option-999", "Option-٤٩", "option-49",
            "{\"kind\":{\"type\":\"SingleStep\"}}", "Command-Shift-",
        ]
        for value in unsupported {
            XCTAssertNil(KnownShortcutConflict.raycastLegacyPreference(value), value)
        }
    }
}
