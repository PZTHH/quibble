import AppKit
import XCTest
@testable import QuibbleInsertion

final class TargetApplicationTests: XCTestCase {
    @MainActor func testEditorWithoutReadableValueStillAcceptsPaste() {
        let element = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        var range = CFRange(location: 0, length: 0)
        let selectedRange = AXValueCreate(.cfRange, &range)!
        let target = TargetApplication.capture(pid: 42, name: "Editor", bundleID: "test.editor", field: element) { _, key in
            switch key {
            case kAXRoleAttribute: return kAXTextAreaRole as CFString
            case kAXSelectedTextRangeAttribute: return selectedRange
            default: return nil
            }
        }
        XCTAssertNotNil(target, "An editable field with missing AXValue must reach the paste path.")
    }
}

@MainActor
private func editor(value: String? = "", range: CFRange? = CFRange(location: 0, length: 0),
                    role: String = kAXTextAreaRole, subrole: String? = nil,
                    pid: pid_t = 42, enabled: Bool = true) -> TargetApplication? {
    let field = AXUIElementCreateApplication(pid)
    return TargetApplication.capture(pid: pid, name: "Editor", bundleID: "test.editor", field: field) { _, key in
        switch key {
        case kAXRoleAttribute: return role as CFString
        case kAXSubroleAttribute: return subrole as CFString?
        case kAXValueAttribute: return value as CFString?
        case kAXEnabledAttribute: return enabled ? kCFBooleanTrue : kCFBooleanFalse
        case kAXSelectedTextRangeAttribute:
            guard var range else { return nil }
            return AXValueCreate(.cfRange, &range)
        default: return nil
        }
    }
}

@MainActor
private final class FakeInsertionIO: InsertionIO {
    var target: TargetApplication?
    var modifiersReleased = true
    var clipboardChangeCount = 10
    var clipboard = "previous clipboard"
    var value: String?
    var elapsed = 0
    var dispatchCount = 0
    var restoreCount = 0
    var staged: String?
    var eventAvailable = true
    var stageAvailable = true
    var onWait: ((FakeInsertionIO) -> Void)?
    var onStage: ((FakeInsertionIO) -> Void)?
    var onSnapshot: ((FakeInsertionIO) -> Void)?
    init(_ target: TargetApplication?) { self.target = target; value = target?.original }
    func currentTarget() -> TargetApplication? { target }
    func snapshotClipboard() -> InsertionClipboard {
        let item = NSPasteboardItem(); item.setString(clipboard, forType: .string)
        let snapshot = InsertionClipboard(changeCount: clipboardChangeCount, items: [item])
        onSnapshot?(self)
        return snapshot
    }
    func stage(_ text: String) -> Bool {
        clipboard = text; staged = text; clipboardChangeCount += 1
        onStage?(self)
        return stageAvailable
    }
    func restore(_ snapshot: InsertionClipboard, ifOwned changeCount: Int) {
        guard clipboardChangeCount == changeCount else { return }
        clipboard = snapshot.items.first?.string(forType: .string) ?? ""
        clipboardChangeCount += 1; restoreCount += 1
    }
    func postPaste() -> Bool {
        guard eventAvailable else { return false }
        dispatchCount += 1; return true
    }
    func readValue(_ element: AXUIElement) -> String? { value }
    func wait(milliseconds: Int) async { elapsed += milliseconds; onWait?(self) }
}

extension TargetApplicationTests {
    @MainActor func testPasteDispatchFeedbackPrecedesSlowReadbackWithoutChangingVerification() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target)
        var notifications = 0
        io.onWait = { io in
            XCTAssertEqual(notifications, 1, "Visual completion must be notified before waiting for editor readback.")
            if io.elapsed == 700 { io.value = "dictation" }
        }
        let result = await target.insert("dictation", using: io, onPasteSent: {
            XCTAssertEqual(io.dispatchCount, 1)
            XCTAssertEqual(io.elapsed, 0)
            XCTAssertEqual(io.restoreCount, 0)
            notifications += 1
        })
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(io.elapsed, 700)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(io.restoreCount, 1)
    }

    @MainActor func testFailedDispatchDoesNotAnnounceVisualCompletion() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target); io.eventAvailable = false
        var notifications = 0
        let result = await target.insert("dictation", using: io, onPasteSent: { notifications += 1 })
        XCTAssertFalse(result.wasSent)
        XCTAssertEqual(notifications, 0)
        XCTAssertEqual(io.restoreCount, 1)
    }

    @MainActor func testOpaqueAndLargeEditorsAreNotExcluded() {
        XCTAssertNotNil(editor(value: nil, range: nil, role: "AXGroup"))
        XCTAssertNotNil(editor(value: String(repeating: "x", count: 40_000)))
        XCTAssertNotNil(editor(value: "text", range: nil))
        XCTAssertNotNil(editor(value: nil, range: nil, role: "AXWindow"))
    }

    @MainActor func testSecureDisabledAndKnownNonInputControlsAreExcluded() {
        XCTAssertNil(editor(subrole: kAXSecureTextFieldSubrole))
        XCTAssertNil(editor(enabled: false))
        XCTAssertNil(editor(role: kAXButtonRole))
    }

    @MainActor func testOpaqueEditorReceivesExactlyOnePasteAndRetainsTranscript() async throws {
        let target = try XCTUnwrap(editor(value: nil, range: nil, role: "AXGroup"))
        let io = FakeInsertionIO(target)
        let result = await target.insert("Hello 👋\nSecond paragraph", using: io)
        XCTAssertEqual(result, .unconfirmed)
        XCTAssertEqual(io.dispatchCount, 1)
        XCTAssertEqual(io.clipboard, "Hello 👋\nSecond paragraph")
        XCTAssertEqual(io.restoreCount, 0)
        XCTAssertEqual(io.elapsed, 0, "An opaque editor cannot acknowledge through AXValue; waiting only blocks the next dictation.")
    }

    @MainActor func testMissingSelectionReturnsPromptlyWithoutGuessingReadback() async throws {
        let target = try XCTUnwrap(editor(value: "draft", range: nil))
        let io = FakeInsertionIO(target)
        var notifications = 0
        let result = await target.insert("dictation", using: io, onPasteSent: { notifications += 1 })
        XCTAssertEqual(result, .unconfirmed)
        XCTAssertEqual(io.dispatchCount, 1)
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(io.clipboard, "dictation")
        XCTAssertEqual(io.restoreCount, 0)
        XCTAssertEqual(io.elapsed, 0, "Without a selection there is no exact expected value to verify.")
    }

    @MainActor func testDelayedReadbackRestoresClipboardOnlyAfterAcknowledgement() async throws {
        let target = try XCTUnwrap(editor(value: "A old Z", range: CFRange(location: 2, length: 3)))
        let io = FakeInsertionIO(target)
        io.onWait = { io in
            XCTAssertEqual(io.clipboard, "new 🌍\nline")
            if io.elapsed >= 700 { io.value = "A new 🌍\nline Z" }
        }
        let result = await target.insert("new 🌍\nline", using: io)
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(io.elapsed, 700)
        XCTAssertEqual(io.dispatchCount, 1)
        XCTAssertEqual(io.clipboard, "previous clipboard")
        XCTAssertEqual(io.restoreCount, 1)
    }

    @MainActor func testUserClipboardChangeDuringDeliveryIsPreserved() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target)
        io.onWait = { io in io.clipboard = "new user copy"; io.clipboardChangeCount += 1; io.value = "dictation" }
        let result = await target.insert("dictation", using: io)
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(io.clipboard, "new user copy")
        XCTAssertEqual(io.restoreCount, 0)
    }

    @MainActor func testFocusChangesBeforeDispatchDoNotInsert() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(editor(pid: 43))
        let result = await target.insert("dictation", using: io)
        XCTAssertFalse(result.wasSent)
        XCTAssertNil(io.staged)
        XCTAssertEqual(io.dispatchCount, 0)
    }

    @MainActor func testSelectionOrTextChangesDoNotOverwriteEdits() async throws {
        let target = try XCTUnwrap(editor(value: "draft"))
        for other in [editor(value: "draft", range: CFRange(location: 3, length: 0)), editor(value: "new draft")] {
            let io = FakeInsertionIO(other)
            let result = await target.insert("dictation", using: io)
            XCTAssertFalse(result.wasSent)
            XCTAssertEqual(io.dispatchCount, 0)
        }
    }

    @MainActor func testFocusChangesWhileStagingRestoreClipboardWithoutDispatch() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target)
        io.onStage = { $0.target = editor(pid: 43) }
        let result = await target.insert("dictation", using: io)
        XCTAssertFalse(result.wasSent)
        XCTAssertEqual(io.dispatchCount, 0)
        XCTAssertEqual(io.clipboard, "previous clipboard")
    }

    @MainActor func testClipboardChangesDuringSnapshotAreNotOverwritten() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target)
        io.onSnapshot = { $0.clipboardChangeCount += 1; $0.clipboard = "user copy" }
        let result = await target.insert("dictation", using: io)
        XCTAssertFalse(result.wasSent)
        XCTAssertNil(io.staged)
        XCTAssertEqual(io.clipboard, "user copy")
    }

    @MainActor func testFailedEventCreationRestoresClipboardAndDoesNotRetry() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target); io.eventAvailable = false
        let result = await target.insert("dictation", using: io)
        XCTAssertFalse(result.wasSent)
        XCTAssertEqual(io.dispatchCount, 0)
        XCTAssertEqual(io.clipboard, "previous clipboard")
    }

    @MainActor func testUnchangedReadbackDoesNotTriggerAnotherInsertion() async throws {
        let target = try XCTUnwrap(editor(value: "draft"))
        let io = FakeInsertionIO(target)
        let result = await target.insert("dictation", using: io)
        XCTAssertEqual(result, .unconfirmed)
        XCTAssertEqual(io.dispatchCount, 1)
        XCTAssertEqual(io.clipboard, "dictation")
    }

    @MainActor func testNoOpReplacementIsNotMistakenForAcknowledgement() async throws {
        let target = try XCTUnwrap(editor(value: "same", range: CFRange(location: 0, length: 4)))
        let io = FakeInsertionIO(target)
        let result = await target.insert("same", using: io)
        XCTAssertEqual(result, .unconfirmed)
        XCTAssertEqual(io.restoreCount, 0)
        XCTAssertEqual(io.dispatchCount, 1)
        XCTAssertEqual(io.clipboard, "same")
        XCTAssertEqual(io.elapsed, 0, "An unchanged value can never prove that paste was consumed.")
    }

    @MainActor func testWaitsForShortcutReleaseBeforePasting() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target); io.modifiersReleased = false
        io.onWait = { io in
            if io.elapsed <= 100 { XCTAssertEqual(io.dispatchCount, 0) }
            if io.elapsed == 100 { io.modifiersReleased = true }
            if io.dispatchCount > 0 { io.value = "dictation" }
        }
        let result = await target.insert("dictation", using: io)
        XCTAssertEqual(result, .confirmed)
        XCTAssertEqual(io.dispatchCount, 1)
    }

    @MainActor func testHeldModifiersTimeOutWithoutChangingClipboard() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target); io.modifiersReleased = false
        let result = await target.insert("dictation", using: io)
        XCTAssertFalse(result.wasSent)
        XCTAssertEqual(io.elapsed, 750)
        XCTAssertNil(io.staged)
    }
}

extension TargetApplicationTests {
    @MainActor func testRealClipboardRestoresMultipleItemsAndRepresentations() {
        let board = NSPasteboard(name: .init("quibble-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let rich = NSPasteboardItem()
        rich.setString("previous text", forType: .string)
        let custom = NSPasteboard.PasteboardType("test.quibble.binary")
        let bytes = Data([0, 255, 2, 3])
        rich.setData(bytes, forType: custom)
        let second = NSPasteboardItem(); second.setString("second item", forType: .string)
        board.writeObjects([rich, second])
        let io = SystemInsertionIO(pasteboard: board)
        let saved = io.snapshotClipboard()
        XCTAssertTrue(io.stage("你好 👋\nsecond paragraph"))
        XCTAssertEqual(board.string(forType: .string), "你好 👋\nsecond paragraph")
        io.restore(saved, ifOwned: io.clipboardChangeCount)
        XCTAssertEqual(board.pasteboardItems?.count, 2)
        XCTAssertEqual(board.pasteboardItems?.first?.string(forType: .string), "previous text")
        XCTAssertEqual(board.pasteboardItems?.first?.data(forType: custom), bytes)
        XCTAssertEqual(board.pasteboardItems?.last?.string(forType: .string), "second item")
    }

    @MainActor func testRealClipboardDoesNotRestoreOverNewCopy() {
        let board = NSPasteboard(name: .init("quibble-tests-\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        board.setString("old clipboard", forType: .string)
        let io = SystemInsertionIO(pasteboard: board)
        let saved = io.snapshotClipboard()
        XCTAssertTrue(io.stage("dictation"))
        let ours = io.clipboardChangeCount
        board.clearContents(); board.setString("new user copy", forType: .string)
        io.restore(saved, ifOwned: ours)
        XCTAssertEqual(board.string(forType: .string), "new user copy")
    }

    @MainActor func testFailedStagingDoesNotSendKeys() async throws {
        let target = try XCTUnwrap(editor())
        let io = FakeInsertionIO(target); io.stageAvailable = false
        let result = await target.insert("dictation", using: io)
        XCTAssertFalse(result.wasSent)
        XCTAssertEqual(io.dispatchCount, 0)
        XCTAssertEqual(io.clipboard, "previous clipboard")
    }
}
