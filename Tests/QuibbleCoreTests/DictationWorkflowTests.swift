import XCTest
@testable import QuibbleCore

final class DictationWorkflowTests: XCTestCase {
    func testExecutionPlanPreservesOrderAndSkipsDisabledSteps() {
        let prompt = WorkflowStep(kind: .prompt, prompt: "Use bullet points.")
        let skipped = WorkflowStep(kind: .cleanup, enabled: false)
        let vocabulary = WorkflowStep(kind: .vocabulary)
        let workflow = DictationWorkflow(name: "Lists", steps: [prompt, skipped, vocabulary])
        XCTAssertEqual(workflow.enabledSteps, [prompt, vocabulary])
    }
}


extension DictationWorkflowTests {
    @MainActor func testMigrationRoundTripPreservesModelAndCustomWorkflow() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("cohere", forKey: "speechEngine")
        defaults.set("exact", forKey: "mode")
        let library = WorkflowLibrary(defaults: defaults)
        XCTAssertEqual(library.selected.name, "Minimal dictation")
        XCTAssertEqual(library.selected.speechModel, "cohere")
        let workflow = DictationWorkflow(name: "My bullets", speechModel: "parakeet", steps: [.init(kind: .prompt, prompt: "Use bullets")], destination: .review)
        XCTAssertTrue(library.save(workflow)); library.select(workflow.id)
        let restored = WorkflowLibrary(defaults: defaults)
        XCTAssertEqual(restored.selected, workflow)
        restored.remove(workflow.id); restored.undoRemoval()
        XCTAssertTrue(restored.workflows.contains(workflow))
    }
    func testInvalidSettingsAndEmptyPromptsAreRejectedBeforeInference() {
        var workflow = DictationWorkflow(name: "Test", steps: [.init(kind: .prompt)])
        XCTAssertNotNil(workflow.validationError)
        workflow.steps[0].enabled = false
        XCTAssertNil(workflow.validationError)
        workflow.asr.temperature = .nan
        XCTAssertNotNil(workflow.validationError)
        workflow.asr = .init(); workflow.speechModel = "../../unexpected"
        XCTAssertNotNil(workflow.validationError)
    }
    @MainActor func testCorruptModeArchiveIsNotOverwritten() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("corrupt".utf8); defaults.set(corrupt, forKey: "workflows.v1")
        let library = WorkflowLibrary(defaults: defaults)
        let original = library.workflows
        XCTAssertNotNil(library.error)
        XCTAssertFalse(library.save(DictationWorkflow(name: "Unsaved edit")))
        XCTAssertTrue(library.workflows == original, "Rejected changes must not alter the in-memory modes")
        XCTAssertEqual(defaults.data(forKey: "workflows.v1"), corrupt)
    }

    @MainActor func testOversizedArchiveDoesNotPublishUnsavedMode() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = WorkflowLibrary(defaults: defaults)
        for index in 0..<5 { XCTAssertTrue(library.save(largeWorkflow("Saved \(index)"))) }
        let original = library.workflows
        let stored = defaults.data(forKey: "workflows.v1")
        XCTAssertNotNil(stored)
        XCTAssertFalse(library.save(largeWorkflow("Too large")))
        XCTAssertTrue(library.workflows == original, "Rejected changes must not alter the in-memory modes")
        XCTAssertEqual(defaults.data(forKey: "workflows.v1"), stored)
        XCTAssertNotNil(library.error)
    }

    @MainActor func testNonDataArchiveIsPreservedAndBlocksEdits() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unreadable legacy value", forKey: "workflows.v1")
        let library = WorkflowLibrary(defaults: defaults)
        let original = library.workflows
        XCTAssertFalse(library.save(DictationWorkflow(name: "Do not apply")))
        XCTAssertTrue(library.workflows == original, "A malformed stored value must not enable session-only changes")
        XCTAssertEqual(defaults.string(forKey: "workflows.v1"), "unreadable legacy value")
        XCTAssertNotNil(library.error)
    }

    @MainActor func testOversizedEditedModeLeavesItsSavedVersionIntact() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = WorkflowLibrary(defaults: defaults)
        var edited = DictationWorkflow(name: "Existing mode")
        XCTAssertTrue(library.save(edited))
        for index in 0..<5 { XCTAssertTrue(library.save(largeWorkflow("Saved \(index)"))) }
        let original = library.workflows, stored = defaults.data(forKey: "workflows.v1")
        edited.steps = largeWorkflow("Large prompts").steps
        XCTAssertFalse(library.save(edited))
        XCTAssertTrue(library.workflows == original, "A failed edit must leave the saved version intact")
        XCTAssertEqual(defaults.data(forKey: "workflows.v1"), stored)
    }

    func testCloudVocabularyUsesTheSpeechProviderWithoutChangingLocalHelpers() {
        let vocabulary = WorkflowStep(kind: .vocabulary)
        XCTAssertEqual(vocabulary.modelID(speechModel: "openai-transcribe"), "openai-transcribe")
        XCTAssertEqual(vocabulary.modelID(speechModel: "cohere-4bit"), "whisper-turbo-vocabulary-4bit")
        XCTAssertEqual(WorkflowStep(kind: .cleanup).modelID(speechModel: "openai-transcribe"), "s1-mini")
        XCTAssertNil(DictationWorkflow(name: "Cloud dictation", speechModel: "openai-transcribe").validationError)
    }

    @MainActor func testCorruptArchiveBlocksSelectionAndRemovalWithoutChangingFallbackModes() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let corrupt = Data("corrupt".utf8); defaults.set(corrupt, forKey: "workflows.v1")
        let library = WorkflowLibrary(defaults: defaults)
        let original = library.workflows, selectedID = library.selectedID
        XCTAssertFalse(library.select(original.first { $0.id != selectedID }!.id))
        XCTAssertEqual(library.selectedID, selectedID)
        XCTAssertFalse(library.remove(selectedID))
        XCTAssertTrue(library.workflows == original, "Rejected changes must not alter the in-memory modes")
        XCTAssertEqual(library.selectedID, selectedID)
        XCTAssertFalse(library.canUndoRemoval)
        XCTAssertEqual(defaults.data(forKey: "workflows.v1"), corrupt)
    }

    @MainActor func testOversizedUndoKeepsRemovedModeAvailableForRetry() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = WorkflowLibrary(defaults: defaults)
        let removed = largeWorkflow("To restore")
        XCTAssertTrue(library.save(removed)); library.remove(removed.id)
        for index in 0..<5 { XCTAssertTrue(library.save(largeWorkflow("Saved \(index)"))) }
        let original = library.workflows, stored = defaults.data(forKey: "workflows.v1")
        XCTAssertFalse(library.undoRemoval())
        XCTAssertTrue(library.workflows == original, "Rejected changes must not alter the in-memory modes")
        XCTAssertEqual(defaults.data(forKey: "workflows.v1"), stored)
        XCTAssertTrue(library.canUndoRemoval)
        XCTAssertNotNil(library.error)
    }

    private func largeWorkflow(_ name: String) -> DictationWorkflow {
        // Each prompt is valid by character count, but UTF-8 archive size is bounded separately.
        DictationWorkflow(name: name, steps: (0..<6).map { _ in
            .init(kind: .prompt, prompt: String(repeating: "🙂", count: 2_000))
        })
    }
}


extension DictationWorkflowTests {
    func testPunctuationOnlyModelOutputCannotReplaceADictation() {
        XCTAssertFalse(DictationWorkflow.isUsableOutput("-"))
        XCTAssertFalse(DictationWorkflow.isUsableOutput(" \n... "))
        XCTAssertTrue(DictationWorkflow.isUsableOutput("- Please open Superwhisper."))
        XCTAssertTrue(DictationWorkflow.isUsableOutput("こんにちは。"))
    }
}
