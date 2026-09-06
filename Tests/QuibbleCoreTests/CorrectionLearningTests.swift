import XCTest
@testable import QuibbleCore

final class CorrectionLearningTests: XCTestCase {
    func testSuggestsRepeatedCorrectionAcrossDistinctDictationsOnly() throws {
        var learning = CorrectionLearning()
        let first = UUID()
        for _ in 0..<3 { learning.observe(session: first, original: "Try super whisper today.", edited: "Try Superwhisper today.") }
        XCTAssertTrue(learning.suggestions.isEmpty, "Editing one dictation repeatedly is one observation")
        learning.observe(session: UUID(), original: "Use super whisper today.", edited: "Use Superwhisper today.")
        XCTAssertEqual(learning.suggestions.count, 1)
        XCTAssertEqual(learning.suggestions.first?.heard, "super whisper")
        XCTAssertEqual(learning.suggestions.first?.preferred, "Superwhisper")
    }
    func testUndoRetractsObservationAndDismissalSurvivesStorage() throws {
        var learning = CorrectionLearning()
        let first = UUID(), second = UUID()
        learning.observe(session: first, original: "super whisper", edited: "Superwhisper")
        learning.observe(session: second, original: "super whisper", edited: "Superwhisper")
        XCTAssertEqual(learning.suggestions.count, 1)
        learning.observe(session: second, original: "super whisper", edited: "super whisper")
        XCTAssertTrue(learning.suggestions.isEmpty)
        learning.observe(session: second, original: "super whisper", edited: "Superwhisper")
        learning.dismiss(try XCTUnwrap(learning.suggestions.first))
        let restored = try JSONDecoder().decode(CorrectionLearning.self, from: JSONEncoder().encode(learning))
        XCTAssertTrue(restored.suggestions.isEmpty)
    }

    func testDoesNotLearnAddedSentencesDeletedWordsNumbersOrLargeRewrites() {
        for (original, edited) in [("Hello there", "Hello there. Another sentence."),
            ("Hello there", "Hello"), ("Send 17 invoices", "Send 70 invoices"),
            ("one two three four five", "six seven eight nine ten")] {
            XCTAssertNil(VocabularyCorrection.detect(original: original, edited: edited), original)
        }
    }
}
