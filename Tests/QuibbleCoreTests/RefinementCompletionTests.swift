import XCTest
@testable import QuibbleCore

final class RefinementCompletionTests: XCTestCase {
    func testPartialTextCannotReplaceInputWithoutNormalCompletion() {
        XCTAssertNil(RefinementCompletion.text("Please meet", stoppedNormally: false), "A token limit or cancelled generation must not replace the transcript")
        XCTAssertNil(RefinementCompletion.text("Please meet", stoppedNormally: nil), "A stream without completion metadata must not replace the transcript")
    }

    func testNormalCompletionPreservesTheCompleteText() {
        XCTAssertEqual(RefinementCompletion.text("\n Please meet Aisling on Friday. \n", stoppedNormally: true), "Please meet Aisling on Friday.")
    }

    func testEmptyOrModelControlOutputCannotReplaceInputEvenAfterNormalCompletion() {
        XCTAssertNil(RefinementCompletion.text(" \n ", stoppedNormally: true))
        XCTAssertNil(RefinementCompletion.text("-", stoppedNormally: true))
        XCTAssertNil(RefinementCompletion.text("<think>I should rewrite this.</think>", stoppedNormally: true))
        XCTAssertNil(RefinementCompletion.text("<|im_start|>assistant", stoppedNormally: true))
    }
}
