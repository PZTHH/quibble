import XCTest
@testable import QuibbleCore

final class VocabularyProcessorTests: XCTestCase {
    func testUnusualMisspellingUsesPreferredWordWithoutAnAlias() {
        let engine = VocabularyProcessor(entries: [VocabularyEntry(preferred: "Superwhisper")])
        let result = engine.process("Open Superwhisker for the meeting.", isKnownWord: { _ in false })
        XCTAssertEqual(result.text, "Open Superwhisper for the meeting.")
    }
}

extension VocabularyProcessorTests {
    func testExplicitPhraseCorrectionAvoidsURLsAndCode() {
        let engine = VocabularyProcessor(entries: [VocabularyEntry(preferred: "Superwhisper", aliases: ["super whisper"])])
        let input = "Use super whisper. Keep https://superwhisker.com and `Superwhisker` and my_Superwhisker_id."
        XCTAssertEqual(engine.process(input, isKnownWord: { _ in false }).text,
            "Use Superwhisper. Keep https://superwhisker.com and `Superwhisker` and my_Superwhisker_id.")
    }
}

extension VocabularyProcessorTests {
    func testOrdinaryWordsAndAmbiguousCandidatesRemainUnchanged() {
        let engine = VocabularyProcessor(entries: [VocabularyEntry(preferred: "Obsidian"), VocabularyEntry(preferred: "QuickTime"),
            VocabularyEntry(preferred: "Superwhisper"), VocabularyEntry(preferred: "Superwhisker")])
        let text = "The obsidian rock. We finished in quick time. Open Superwhister."
        XCTAssertEqual(engine.process(text, isKnownWord: { ["obsidian", "quick", "time"].contains($0) }).text, text)
    }
    func testDisabledEntriesAndConflictingRulesDoNotApply() {
        let engine = VocabularyProcessor(entries: [VocabularyEntry(preferred: "Quibble", aliases: ["app"], enabled: false),
            VocabularyEntry(preferred: "One", aliases: ["tool"]), VocabularyEntry(preferred: "Two", aliases: ["tool"])])
        XCTAssertEqual(engine.process("app tool", isKnownWord: { _ in false }).text, "app tool")
    }
    func testCleanupCannotUndoApprovedSpellingOrDuplicateIt() {
        let engine = VocabularyProcessor(entries: [VocabularyEntry(preferred: "Superwhisper", aliases: ["super whisper"])])
        let result = engine.process("please open super whisper", isKnownWord: { _ in true })
        XCTAssertTrue(VocabularyProcessor.preservesTerms(in: "Please open Superwhisper.", from: result))
        XCTAssertFalse(VocabularyProcessor.preservesTerms(in: "Please open Super Whisper.", from: result))
        XCTAssertFalse(VocabularyProcessor.preservesTerms(in: "Superwhisper, Superwhisper.", from: result))
    }
    func testNoRelevantTermSkipsSpellingService() {
        let engine = VocabularyProcessor(entries: [VocabularyEntry(preferred: "Superwhisper")])
        var lookups = 0
        let text = "Please send the revised document to Maya before Thursday afternoon."
        XCTAssertEqual(engine.process(text, isKnownWord: { _ in lookups += 1; return true }).text, text)
        XCTAssertEqual(lookups, 0)
    }
}
