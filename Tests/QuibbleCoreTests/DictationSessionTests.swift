import XCTest
@testable import QuibbleCore

final class DictationSessionTests: XCTestCase {
    func testRepeatedShortcutPressDoesNotReplaceAnActiveRecording() throws {
        var session = DictationSession()
        let current = try XCTUnwrap(session.start())
        XCTAssertNil(session.start())
        XCTAssertEqual(session.state, .recording(current))
    }

    func testCancelledInferenceCannotInsertIntoANewerSession() throws {
        var session = DictationSession()
        let cancelled = try XCTUnwrap(session.start())
        session.stop()
        session.cancel()
        let current = try XCTUnwrap(session.start())
        XCTAssertFalse(session.complete(cancelled, text: "stale text"))
        XCTAssertEqual(session.state, .recording(current))
    }
}
