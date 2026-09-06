import XCTest
@testable import QuibbleCore

final class SetupRequirementsTests: XCTestCase {
    func testEmptyVocabularyDoesNotRequireTheAudioHelperOrAnOptionalChecker() {
        let workflow = DictationWorkflow(name: "Minimal", speechModel: "qwen3-asr-4bit",
                                         steps: [.init(kind: .vocabulary)])
        XCTAssertEqual(SetupRequirements.modelIDs(for: workflow, hasVocabulary: false), ["qwen3-asr-4bit"])
        XCTAssertEqual(SetupRequirements.modelIDs(for: workflow, hasVocabulary: true),
                       ["qwen3-asr-4bit", "whisper-turbo-vocabulary-4bit"])
    }

    func testEnabledTextStepsAndVocabularyPreserveWorkflowOrderWithoutDuplicates() {
        let workflow = DictationWorkflow(name: "Writing", speechModel: "whisper-turbo-vocabulary-4bit", steps: [
            .init(kind: .prompt, model: "qwen3-1.7b-4bit", prompt: "Use paragraphs."),
            .init(kind: .vocabulary), .init(kind: .cleanup), .init(kind: .cleanup),
            .init(kind: .prompt, model: "qwen3-1.7b-4bit", prompt: "Keep it concise.")
        ])
        XCTAssertEqual(SetupRequirements.modelIDs(for: workflow, hasVocabulary: true),
                       ["whisper-turbo-vocabulary-4bit", "qwen3-1.7b-4bit", "s1-mini"])
    }

    func testDisabledStepsDoNotAddDownloads() {
        let workflow = DictationWorkflow(name: "Exact", speechModel: "parakeet", steps: [
            .init(kind: .vocabulary, enabled: false), .init(kind: .cleanup, enabled: false),
            .init(kind: .prompt, enabled: false)
        ])
        XCTAssertEqual(SetupRequirements.modelIDs(for: workflow, hasVocabulary: true), ["parakeet"])
    }

    func testBothOnlineSpeechModelsStillRequireEnabledLocalWritingModels() {
        for speech in ["openai-transcribe", "openai-diarize"] {
            let workflow = DictationWorkflow(name: "Online", speechModel: speech, steps: [
                .init(kind: .vocabulary), .init(kind: .cleanup),
                .init(kind: .prompt, model: "qwen3-0.6b-4bit", prompt: "Use bullets.")
            ])
            XCTAssertEqual(SetupRequirements.modelIDs(for: workflow, hasVocabulary: true),
                           ["s1-mini", "qwen3-0.6b-4bit"])
        }
    }

    func testMissingRequirementsOnlyExcludeInstalledFiles() {
        let workflow = DictationWorkflow(name: "Writing", steps: [.init(kind: .vocabulary), .init(kind: .cleanup)])
        XCTAssertEqual(SetupRequirements.missingModelIDs(for: workflow, hasVocabulary: true,
                                                        installed: ["cohere-4bit", "s1-mini"]),
                       ["whisper-turbo-vocabulary-4bit"])
    }

    func testDownloadPlanPreservesOrderAndSkipsOnlyInstalledDuplicates() {
        let plan = SetupDownloadPlan(requested: ["speech", "helper", "cleanup", "speech", "helper"],
                                     installed: ["speech"], available: ["speech", "helper", "cleanup"])
        XCTAssertEqual(plan.missingIDs, ["helper", "cleanup"])
        XCTAssertTrue(plan.unknownIDs.isEmpty)
        XCTAssertTrue(plan.canDownload)
    }

    func testUnknownRequirementsAreNotHiddenByTheCatalogOrInstalledSet() {
        let workflow = DictationWorkflow(name: "Unavailable", speechModel: "future-model")
        XCTAssertEqual(SetupRequirements.missingModelIDs(for: workflow, hasVocabulary: false, installed: []),
                       ["future-model"])
        let plan = SetupDownloadPlan(requested: ["known", "future-model"], installed: ["future-model"],
                                     available: ["known"])
        XCTAssertEqual(plan.unknownIDs, ["future-model"])
        XCTAssertFalse(plan.canDownload, "A stale installed set must not validate an unknown catalog ID")
    }

    func testAlreadyReadyPlanNeedsNoDownload() {
        let plan = SetupDownloadPlan(requested: ["speech", "speech"], installed: ["speech"], available: ["speech"])
        XCTAssertTrue(plan.missingIDs.isEmpty)
        XCTAssertTrue(plan.unknownIDs.isEmpty)
        XCTAssertFalse(plan.canDownload)
    }
}
