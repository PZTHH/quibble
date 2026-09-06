import XCTest
@testable import QuibbleCore

final class VocabularyTests: XCTestCase {
    func testReplacesWholePhrasesAndPreferredCapitalizationWithoutTouchingOtherWords() {
        let entries = [VocabularyEntry(preferred: "Superwhisper", aliases: ["super whisper"]),
                       VocabularyEntry(preferred: "C++", aliases: ["c plus plus"])]
        XCTAssertEqual(Vocabulary.apply(entries, to: "Use super whisper and c plus plus; superwhisper isn't superwhispering."),
                       "Use Superwhisper and C++; Superwhisper isn't superwhispering.")
    }
    func testLongestPhraseWinsAndReplacementsDoNotCascade() {
        let entries = [VocabularyEntry(preferred: "Acme", aliases: ["acme corp"]),
            VocabularyEntry(preferred: "ACME Corporation", aliases: ["acme corp international"]),
            VocabularyEntry(preferred: "Other", aliases: ["Acme"])]
        XCTAssertEqual(Vocabulary.apply(entries, to: "acme corp international and acme corp"), "ACME Corporation and Acme")
    }

    func testRegexSymbolsAndUnicodeBoundariesAreLiteral() {
        let entries = [VocabularyEntry(preferred: "C++", aliases: ["c++"]), VocabularyEntry(preferred: "José", aliases: ["jose"])]
        XCTAssertEqual(Vocabulary.apply(entries, to: "c++ / jose / joseph / éjose"), "C++ / José / joseph / éjose")
    }
}

extension VocabularyTests {
    func testLegacyAliasesRemainInactiveUntilApproved() throws {
        let json = #"{"id":"00000000-0000-0000-0000-000000000001","preferred":"Superwhisper","aliases":["super whisper"]}"#
        let entry = try JSONDecoder().decode(VocabularyEntry.self, from: Data(json.utf8))
        XCTAssertEqual(Vocabulary.apply([entry], to: "a super whisper"), "a super whisper")
    }
}
