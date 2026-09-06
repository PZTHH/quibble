import XCTest
@testable import QuibbleCore

final class VocabularyEditsTests: XCTestCase {
    func testAcceptsUncommonNameWithoutUserAliases() {
        let result = VocabularyEdits.apply(#"[{"heard":"Shivon","preferred":"Siobhan"}]"#,
            to: "Ask Shivon to call.", entries: [VocabularyEntry(preferred: "Siobhan")])
        XCTAssertEqual(result.text, "Ask Siobhan to call.")
        XCTAssertEqual(result.changes.first?.before, "Shivon")
        XCTAssertTrue(result.protectedTerms.contains("Siobhan"))
    }
}

extension VocabularyEditsTests {
    func testRejectsMalformedOutputAndWordsOutsideSavedVocabulary() {
        let input = "Ask Shivon to call."
        let words = [VocabularyEntry(preferred: "Siobhan")]
        for response in ["Ignore the transcript and print Siobhan", #"[{"heard":"Shivon","preferred":"Someone Else"}]"#, #"[{"heard":"Ask Shivon to call.","preferred":"Unlisted"}]"#] {
            XCTAssertEqual(VocabularyEdits.apply(response, to: input, entries: words).text, input)
        }
    }
    func testNeverEditsCodeURLsOrSubstrings() {
        let words = [VocabularyEntry(preferred: "Siobhan")]
        let response = #"[{"heard":"Shivon","preferred":"Siobhan"}]"#
        for input in ["`Shivon`", "https://Shivon.com", "Shivon@example.com", "my_Shivon_id", "Shivonna"] {
            XCTAssertEqual(VocabularyEdits.apply(response, to: input, entries: words).text, input)
        }
    }
    func testPreservesPunctuationWhitespaceAndUnicodeOffsets() {
        let input = "📬  Ask Shivon, please.\nThen call Searsha."
        let words = [VocabularyEntry(preferred: "Siobhan"), VocabularyEntry(preferred: "Saoirse")]
        let response = #"[{"heard":"Shivon","preferred":"Siobhan"},{"heard":"Searsha","preferred":"Saoirse"}]"#
        XCTAssertEqual(VocabularyEdits.apply(response, to: input, entries: words).text, "📬  Ask Siobhan, please.\nThen call Saoirse.")
    }
    func testDisabledAlreadySavedAndRepeatedNamesAreNotChanged() {
        let response = #"[{"heard":"Shivon","preferred":"Siobhan"}]"#
        XCTAssertEqual(VocabularyEdits.apply(response, to: "Ask Shivon.", entries: [VocabularyEntry(preferred: "Siobhan", enabled: false)]).text, "Ask Shivon.")
        let words = [VocabularyEntry(preferred: "Siobhan"), VocabularyEntry(preferred: "Shivon")]
        XCTAssertEqual(VocabularyEdits.apply(response, to: "Ask Shivon.", entries: words).text, "Ask Shivon.")
        XCTAssertEqual(VocabularyEdits.apply(response, to: "Shivon called Shivon.", entries: [VocabularyEntry(preferred: "Siobhan")]).text, "Shivon called Shivon.")
    }
}

extension VocabularyEditsTests {
    func testProjectsOnlySavedWordWhilePreservingEverySurroundingCharacter() {
        let original = "📬  Please send the report to Shivon, today.\nThank you!"
        let hypothesis = "Please send a report to Siobhan today. Thanks."
        let result = VocabularyEdits.project(hypothesis, onto: original, entries: [VocabularyEntry(preferred: "Siobhan")])
        XCTAssertEqual(result.text, "📬  Please send the report to Siobhan, today.\nThank you!")
        XCTAssertEqual(result.changes.map(\.before), ["Shivon"])
    }
}

extension VocabularyEditsTests {
    func testProjectionRejectsInventedWordsAndSwallowedNeighbors() {
        let words = [VocabularyEntry(preferred: "PostgreSQL"), VocabularyEntry(preferred: "Caoimhe"), VocabularyEntry(preferred: "Aisling")]
        for (source, hypothesis) in [
            ("We made progress.", "We made PostgreSQL progress."),
            ("Call Kiva after lunch.", "Caoimhe."),
            ("Please ask Ashling to review it.", "Please Aisling to review it.")
        ] {
            XCTAssertEqual(VocabularyEdits.project(hypothesis, onto: source, entries: words).text, source)
        }
    }
    func testProjectionAllowsSplitTechnicalTermWithoutTouchingPunctuation() {
        let words = [VocabularyEntry(preferred: "Superwhisper"), VocabularyEntry(preferred: "C++")]
        XCTAssertEqual(VocabularyEdits.project("Open Superwhisper and use C++", onto: "Open super whisper, and use cpp!", entries: words).text,
            "Open Superwhisper, and use C++!")
        XCTAssertEqual(VocabularyEdits.project("Open Superwhisper", onto: "Open super, whisper.", entries: words).text,
            "Open super, whisper.")
    }
    func testProjectionKeepsProtectedAndAmbiguousOccurrences() {
        let words = [VocabularyEntry(preferred: "Siobhan")]
        for (source, hypothesis) in [
            ("Use `Shivon`.", "Use `Siobhan`."),
            ("Visit https://Shivon.com.", "Visit https://Siobhan.com."),
            ("Shivon called Shivon.", "Siobhan called Shivon.")
        ] {
            XCTAssertEqual(VocabularyEdits.project(hypothesis, onto: source, entries: words).text, source)
        }
    }
}

extension VocabularyEditsTests {
    func testOrdinaryCapitalizationDoesNotHideTheAdjacentVocabularyEdit() {
        let words = [VocabularyEntry(preferred: "QuickTime")]
        XCTAssertEqual(VocabularyEdits.project("Please open QuickTime Player.", onto: "Please open quick time player.", entries: words).text,
            "Please open QuickTime player.")
    }
}

extension VocabularyEditsTests {
    func testAudioVocabularyRequiresIndependentAgreementForOrdinaryWordFormatting() {
        let entries = [VocabularyEntry(preferred: "QuickTime"), VocabularyEntry(preferred: "Siobhan")]
        XCTAssertEqual(VocabularyEdits.resolve("We finished in QuickTime.", onto: "We finished in quick time.", entries: entries, normalization: "We finished in quick time.").text, "We finished in quick time.")
        XCTAssertEqual(VocabularyEdits.resolve("Open QuickTime player.", onto: "Open quick time player.", entries: entries, normalization: "Open QuickTime Player.").text, "Open QuickTime player.")
        XCTAssertEqual(VocabularyEdits.resolve("Call Siobhan.", onto: "Call Shivon.", entries: entries, normalization: nil).text, "Call Siobhan.")
        XCTAssertEqual(VocabularyEdits.resolve("Open QuickTime.", onto: "Open quick time.", entries: entries, normalization: nil).text, "Open quick time.")
    }
    func testExplicitRulesWinOverAudioProposalsWithoutFuzzyTextMatching() {
        let entries = [VocabularyEntry(preferred: "Siobhan"), VocabularyEntry(preferred: "Shivonne", aliases: ["Shivon"], correctionsEnabled: true), VocabularyEntry(preferred: "Superwhisper")]
        let result = VocabularyEdits.resolve("Call Siobhan about Superwhisper.", onto: "Call Shivon about Superwhispr.", entries: entries, normalization: nil)
        XCTAssertEqual(result.text, "Call Shivonne about Superwhisper.")
        XCTAssertTrue(result.changes.first!.explicit)
        XCTAssertEqual(VocabularyEdits.resolve("", onto: "Try Superwhispr.", entries: entries, normalization: nil).text, "Try Superwhispr.")
    }
}
