import AppKit
import XCTest
import QuibbleCore
@testable import QuibbleVocabulary

final class VocabularyStoreTests: XCTestCase {
    @MainActor func testRoundTripUndoAndImportPreserveRules() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("vocabulary.json")
        let store = VocabularyStore(file: file)
        let entry = VocabularyEntry(preferred: "Superwhisper", aliases: ["super whisper"])
        XCTAssertTrue(store.save(entry))
        XCTAssertEqual(VocabularyStore(file: file).entries, [entry])
        let export = try store.exportData()
        store.remove(entry.id)
        XCTAssertTrue(store.entries.isEmpty)
        store.undo()
        XCTAssertEqual(store.entries, [entry])
        XCTAssertTrue(try store.previewImport(export).isEmpty)
        let other = VocabularyStore(file: folder.appendingPathComponent("other.json"))
        let additions = try other.previewImport(export)
        XCTAssertEqual(additions.first?.preferred, entry.preferred)
        XCTAssertEqual(additions.first?.correctionsEnabled, true)
        XCTAssertTrue(other.importEntries(additions))
        XCTAssertEqual(other.processor.process("super whisper", isKnownWord: { _ in true }).text, "Superwhisper")
    }

    @MainActor func testConflictingRulesDoNotChangeMemoryOrDisk() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("vocabulary.json")
        let store = VocabularyStore(file: file)
        let entry = VocabularyEntry(preferred: "Acme", aliases: ["company"])
        XCTAssertTrue(store.save(entry))
        let before = try Data(contentsOf: file)
        XCTAssertFalse(store.save(VocabularyEntry(preferred: "Other", aliases: ["company"])))
        XCTAssertEqual(store.entries, [entry])
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertNotNil(store.error)
    }

    @MainActor func testFailedWriteDoesNotPretendEntryWasSaved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let obstacle = folder.appendingPathComponent("file-not-directory")
        try Data([1]).write(to: obstacle)
        let store = VocabularyStore(file: obstacle.appendingPathComponent("vocabulary.json"))
        XCTAssertFalse(store.save(VocabularyEntry(preferred: "Quibble")))
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertNotNil(store.error)
    }

    @MainActor func testSystemSpellingProtectsOrdinaryWordsAndCorrectsUnusualOnes() {
        let processor = VocabularyProcessor(entries: [VocabularyEntry(preferred: "Superwhisper"), VocabularyEntry(preferred: "Obsidian")])
        XCTAssertEqual(VocabularySpelling.process("Open Superwhisker.", with: processor).text, "Open Superwhisper.")
        XCTAssertEqual(VocabularySpelling.process("The obsidian rock.", with: processor).text, "The obsidian rock.")
    }

    @MainActor func testExplicitRulesCanBeDisabledWithoutLosingTheirAliases() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = VocabularyStore(file: folder.appendingPathComponent("vocabulary.json"))
        var entry = VocabularyEntry(preferred: "Superwhisper", aliases: ["super whisper"])
        XCTAssertTrue(store.save(entry))
        entry.correctionsEnabled = false
        XCTAssertTrue(store.save(entry))
        XCTAssertEqual(store.entries.first?.aliases, ["super whisper"])
        XCTAssertEqual(store.processor.process("super whisper", isKnownWord: { _ in true }).text, "super whisper")
    }
}

extension VocabularyStoreTests {
    @MainActor func testUndoKeepsCorrectionsObservedAfterTheManualChange() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = VocabularyStore(file: folder.appendingPathComponent("vocabulary.json"))
        store.observe(id: UUID(), original: "super whisper", edited: "Superwhisper")
        store.observe(id: UUID(), original: "super whisper", edited: "Superwhisper")
        store.accept(try XCTUnwrap(store.suggestions.first), asRule: true)
        store.observe(id: UUID(), original: "postgress", edited: "PostgreSQL")
        store.observe(id: UUID(), original: "postgress", edited: "PostgreSQL")
        store.undo()
        XCTAssertEqual(Set(store.suggestions.map(\.preferred)), ["Superwhisper", "PostgreSQL"])
        XCTAssertTrue(store.entries.isEmpty)
    }
}
