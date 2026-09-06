import XCTest
@testable import QuibbleCore

final class ShortcutTests: XCTestCase {
    func testTapTimeoutKeepsTheHoldAliveUntilTheRealKeyRelease() {
        var state = ShortcutState()
        _ = state.handle(.down, key: 49, modifiers: ShortcutBinding.option)
        XCTAssertEqual(state.recoverAfterTimeout(pressedKeys: [49], modifiers: ShortcutBinding.option), .init())
        XCTAssertEqual(state.handle(.up, key: 49), .init(consume: true, action: .release))
    }
    func testTapTimeoutReleasesAKeyThatWasReleasedDuringTheGap() {
        var state = ShortcutState()
        _ = state.handle(.down, key: 49, modifiers: ShortcutBinding.option)
        XCTAssertEqual(state.recoverAfterTimeout(pressedKeys: [], modifiers: 0), .init(action: .release))
        XCTAssertEqual(state.handle(.up, key: 49), .init())
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: ShortcutBinding.option), .init(consume: true, action: .press))
    }
    func testTapTimeoutRetainsToggleRecordingAndRecoversAMissedToggleKeyUp() {
        var state = ShortcutState()
        _ = state.handle(.down, key: 49, modifiers: ShortcutBinding.toggleDictation.modifiers)
        state.toggleRecording = true
        XCTAssertEqual(state.recoverAfterTimeout(pressedKeys: [], modifiers: 0), .init())
        XCTAssertTrue(state.toggleRecording)
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: ShortcutBinding.toggleDictation.modifiers), .init(consume: true, action: .toggle))
    }
    func testToggleChordStartsAnActionWithoutHolding() {
        var state = ShortcutState()
        let result = state.handle(.down, key: 49, modifiers: ShortcutBinding.control | ShortcutBinding.option)
        XCTAssertEqual(result, .init(consume: true, action: .toggle))
        XCTAssertEqual(state.handle(.up, key: 49), .init(consume: true))
    }

    func testEscapeCancelsToggleRecordingAfterTheShortcutIsReleased() {
        var state = ShortcutState()
        _ = state.handle(.down, key: 49, modifiers: ShortcutBinding.control | ShortcutBinding.option)
        _ = state.handle(.up, key: 49)
        state.toggleRecording = true
        XCTAssertEqual(state.handle(.down, key: 53), .init(consume: true, action: .cancel))
        XCTAssertEqual(state.handle(.up, key: 53), .init(consume: true))
        XCTAssertFalse(state.toggleRecording)
        XCTAssertEqual(state.handle(.down, key: 53), .init())
    }

    func testToggleFiresOncePerPressAndNeverFinishesOnRelease() {
        var state = ShortcutState()
        let modifiers = ShortcutBinding.control | ShortcutBinding.option
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: modifiers), .init(consume: true, action: .toggle))
        state.toggleRecording = true
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: modifiers, repeated: true), .init(consume: true))
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: modifiers), .init(consume: true))
        XCTAssertEqual(state.handle(.modifiersChanged, modifiers: 0), .init())
        XCTAssertEqual(state.handle(.up, key: 49), .init(consume: true))
        XCTAssertTrue(state.toggleRecording)
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: modifiers), .init(consume: true, action: .toggle))
    }

    func testCustomToggleWorksWhileHoldIsPressedAndKeepsReleaseSeparate() {
        let toggle = ShortcutBinding(keyCode: 17, modifiers: ShortcutBinding.control | ShortcutBinding.option, keyName: "T")
        var state = ShortcutState(toggleDictation: toggle)
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: ShortcutBinding.option), .init(consume: true, action: .press))
        XCTAssertEqual(state.handle(.down, key: 17, modifiers: toggle.modifiers), .init(consume: true, action: .toggle))
        XCTAssertEqual(state.handle(.up, key: 17), .init(consume: true))
        XCTAssertEqual(state.handle(.up, key: 49), .init(consume: true, action: .release))
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: ShortcutBinding.toggleDictation.modifiers), .init())
        XCTAssertEqual(state.handle(.down, key: 9, modifiers: ShortcutBinding.pasteLast.modifiers), .init(consume: true, action: .pasteLast))
    }

    func testHoldReleaseDoesNotDisarmAnActiveToggleAndResetDoes() {
        var state = ShortcutState()
        state.toggleRecording = true
        _ = state.handle(.down, key: 49, modifiers: ShortcutBinding.option)
        XCTAssertEqual(state.handle(.up, key: 49), .init(consume: true, action: .release))
        XCTAssertTrue(state.toggleRecording)
        state.reset()
        XCTAssertFalse(state.toggleRecording)
        XCTAssertEqual(state.handle(.down, key: 53), .init())
    }

    func testCustomChordStartsAndReleasesOnce() {
        var state = ShortcutState(dictation: .init(keyCode: 2, modifiers: ShortcutBinding.control | ShortcutBinding.option, keyName: "D"))
        XCTAssertEqual(state.handle(.down, key: 2, modifiers: ShortcutBinding.control | ShortcutBinding.option), .init(consume: true, action: .press))
        XCTAssertEqual(state.handle(.down, key: 2, modifiers: ShortcutBinding.control | ShortcutBinding.option, repeated: true), .init(consume: true))
        XCTAssertEqual(state.handle(.up, key: 2), .init(consume: true, action: .release))
        XCTAssertEqual(state.handle(.up, key: 2), .init())
    }
    func testModifierFirstReleaseConsumesTheRemainingKeyWithoutRestarting() {
        var state = ShortcutState()
        _ = state.handle(.down, key: 49, modifiers: ShortcutBinding.option)
        XCTAssertEqual(state.handle(.modifiersChanged, modifiers: 0), .init(action: .release))
        XCTAssertEqual(state.handle(.down, key: 49, repeated: true), .init(consume: true))
        XCTAssertEqual(state.handle(.up, key: 49), .init(consume: true))
        XCTAssertEqual(state.handle(.down, key: 49, modifiers: ShortcutBinding.option), .init(consume: true, action: .press))
    }
    func testEscapeCancelsAndPasteLastDoesNotRepeat() {
        var state = ShortcutState()
        _ = state.handle(.down, key: 49, modifiers: ShortcutBinding.option)
        XCTAssertEqual(state.handle(.down, key: 53), .init(consume: true, action: .cancel))
        XCTAssertEqual(state.handle(.up, key: 53), .init(consume: true))
        XCTAssertEqual(state.handle(.up, key: 49), .init(consume: true))
        XCTAssertEqual(state.handle(.down, key: 9, modifiers: ShortcutBinding.control | ShortcutBinding.command), .init(consume: true, action: .pasteLast))
        XCTAssertEqual(state.handle(.down, key: 9, modifiers: ShortcutBinding.control | ShortcutBinding.command, repeated: true), .init(consume: true))
        XCTAssertEqual(state.handle(.up, key: 9), .init(consume: true))
        state.reset()
        XCTAssertEqual(state.handle(.down, key: 0), .init())
    }
    func testUnsafeBindingsAreRejectedAndDisplayNameDoesNotAffectCollision() throws {
        XCTAssertNotNil(ShortcutBinding(keyCode: 0, modifiers: 0, keyName: "A").validationError)
        XCTAssertNotNil(ShortcutBinding(keyCode: 0, modifiers: ShortcutBinding.shift, keyName: "A").validationError)
        XCTAssertNotNil(ShortcutBinding(keyCode: 53, modifiers: ShortcutBinding.option, keyName: "Esc").validationError)
        XCTAssertNotNil(ShortcutBinding(keyCode: 12, modifiers: ShortcutBinding.command, keyName: "Q").validationError)
        XCTAssertNil(ShortcutBinding.dictation.validationError)
        XCTAssertNil(ShortcutBinding.toggleDictation.validationError)
        XCTAssertNil(ShortcutBinding.pasteLast.validationError)
        XCTAssertFalse(ShortcutBinding.toggleDictation.conflicts(with: .dictation))
        XCTAssertFalse(ShortcutBinding.toggleDictation.conflicts(with: .pasteLast))
        XCTAssertTrue(ShortcutBinding.dictation.conflicts(with: .init(keyCode: 49, modifiers: ShortcutBinding.option, keyName: "Spacebar")))
        let encoded = try JSONEncoder().encode(ShortcutBinding.pasteLast)
        XCTAssertEqual(try JSONDecoder().decode(ShortcutBinding.self, from: encoded), .pasteLast)
    }
}
