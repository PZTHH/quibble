import Foundation
import Combine

public enum WorkflowStepKind: String, Codable, CaseIterable, Sendable {
    case vocabulary, cleanup, prompt
    public var title: String { switch self { case .vocabulary: "Saved spellings"; case .cleanup: "Basic cleanup"; case .prompt: "Custom prompt" } }
}
public struct WorkflowStep: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var kind: WorkflowStepKind
    public var enabled: Bool
    public var model: String
    public var prompt: String
    public init(kind: WorkflowStepKind, enabled: Bool = true, model: String = "qwen3-4b-instruct-4bit", prompt: String = "") {
        id = UUID(); self.kind = kind; self.enabled = enabled; self.model = model; self.prompt = prompt
    }
    public var modelID: String { switch kind { case .vocabulary: "whisper-turbo-vocabulary-4bit"; case .cleanup: "s1-mini"; case .prompt: model } }
    public func modelID(speechModel: String) -> String {
        kind == .vocabulary && ["openai-transcribe", "openai-diarize"].contains(speechModel) ? speechModel : modelID
    }
}
public enum WorkflowDestination: String, Codable, CaseIterable, Sendable {
    case insert, review
    public var title: String { self == .insert ? "Insert at cursor" : "Review in Quibble" }
}
public struct ASROptions: Codable, Equatable, Sendable {
    public var maxTokens = 512
    public var temperature: Float = 0
    public var language = "en"
    public var chunkSeconds: Float = 60
    public init() {}
    public var isValid: Bool {
        (64...2048).contains(maxTokens) && temperature.isFinite && (0...1).contains(temperature)
        && chunkSeconds.isFinite && (5...60).contains(chunkSeconds)
        && ["en", "de", "fr", "es", "it", "pt", "ja", "zh", "ko"].contains(language)
    }
}
public struct DictationWorkflow: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var speechModel: String
    public var steps: [WorkflowStep]
    public var destination: WorkflowDestination
    public var asr: ASROptions
    public init(id: String = UUID().uuidString, name: String, speechModel: String = "cohere-4bit", steps: [WorkflowStep] = [], destination: WorkflowDestination = .insert, asr: ASROptions = .init()) {
        self.id = id; self.name = name; self.speechModel = speechModel; self.steps = steps; self.destination = destination; self.asr = asr
    }
    public static func isUsableOutput(_ text: String) -> Bool { text.contains { !$0.isWhitespace && !$0.isPunctuation } }
    public var enabledSteps: [WorkflowStep] { steps.filter(\.enabled) }
    public var validationError: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 60 { return "Give this mode a name of 1–60 characters." }
        let speechIDs = ["cohere-4bit", "cohere", "parakeet", "parakeet-8bit", "qwen3-asr-4bit", "qwen3-asr-06b-4bit", "whisper-turbo-vocabulary-4bit", "whisper-large-vocabulary-4bit", "whisper-small-4bit", "whisper-base-4bit", "openai-transcribe", "openai-diarize", "cohere-8bit", "qwen3-asr-8bit", "qwen3-asr-06b-8bit", "whisper-turbo-vocabulary-8bit", "whisper-large-vocabulary-8bit", "whisper-small-8bit", "whisper-base-8bit", "canary-v2-8bit", "nemotron-35-8bit", "moonshine-tiny", "moonshine-base", "granite-4-speech-4bit", "granite-4-speech-5bit", "granite-4-speech-8bit"]
        if !speechIDs.contains(speechModel) { return "Choose a supported speech model." }
        if steps.contains(where: { $0.kind == .prompt && !["qwen3-4b-instruct-4bit", "qwen3-0.6b-4bit", "qwen3-1.7b-4bit"].contains($0.model) }) { return "Choose a supported instruction model." }
        if !asr.isValid { return "Speech settings are outside the supported ranges." }
        if steps.count > 6 { return "A mode can have up to six processing steps." }
        if Set(steps.map(\.id)).count != steps.count { return "Step identifiers must be unique." }
        if steps.contains(where: { $0.prompt.count > 2_000 }) { return "Custom prompts can have up to 2,000 characters." }
        if steps.contains(where: { $0.enabled && $0.kind == .prompt && $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { return "Write instructions for each enabled custom-prompt step." }
        return nil
    }
    public static func presets(speechModel: String) -> [DictationWorkflow] {
        [.init(id: "minimal", name: "Minimal dictation", speechModel: speechModel, steps: [.init(kind: .vocabulary)]),
         .init(id: "basic", name: "Basic cleanup", speechModel: speechModel, steps: [.init(kind: .vocabulary), .init(kind: .cleanup)])]
    }
}

@MainActor public final class WorkflowLibrary: ObservableObject {
    @Published public private(set) var workflows: [DictationWorkflow]
    @Published public private(set) var selectedID: String
    @Published public private(set) var error: String?
    @Published private var removed: DictationWorkflow?
    private let defaults: UserDefaults
    private var canWrite = true
    private struct Archive: Codable { let version: Int; let workflows: [DictationWorkflow]; let selectedID: String }
    public var selected: DictationWorkflow { workflows.first { $0.id == selectedID } ?? workflows[0] }
    public var canUndoRemoval: Bool { removed != nil }
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        workflows = DictationWorkflow.presets(speechModel: defaults.string(forKey: "speechEngine") ?? "cohere-4bit")
        selectedID = defaults.string(forKey: "mode") == "exact" ? "minimal" : "basic"
        if defaults.object(forKey: "workflows.v1") != nil {
            if let data = defaults.data(forKey: "workflows.v1"), data.count <= 256_000,
               let archive = try? JSONDecoder().decode(Archive.self, from: data), archive.version == 1,
               !archive.workflows.isEmpty, archive.workflows.count <= 24,
               Set(archive.workflows.map(\.id)).count == archive.workflows.count,
               archive.workflows.allSatisfy({ $0.validationError == nil }), archive.workflows.contains(where: { $0.id == archive.selectedID }) {
                workflows = archive.workflows; selectedID = archive.selectedID
            } else { canWrite = false; error = "Saved modes could not be read and were left untouched. Changes cannot be saved." }
        }
    }
    @discardableResult public func select(_ id: String) -> Bool {
        guard workflows.contains(where: { $0.id == id }) else { error = "This mode is no longer available."; return false }
        return persist(workflows, selectedID: id)
    }
    @discardableResult public func save(_ workflow: DictationWorkflow) -> Bool {
        guard workflow.validationError == nil else { error = workflow.validationError; return false }
        var candidate = workflows
        if let index = candidate.firstIndex(where: { $0.id == workflow.id }) { candidate[index] = workflow }
        else { guard candidate.count < 24 else { error = "Keep up to 24 modes."; return false }; candidate.append(workflow) }
        return persist(candidate, selectedID: selectedID)
    }
    @discardableResult public func remove(_ id: String) -> Bool {
        guard workflows.count > 1 else { error = "Keep at least one mode."; return false }
        guard let index = workflows.firstIndex(where: { $0.id == id }) else { error = "This mode is no longer available."; return false }
        var candidate = workflows
        let removing = candidate.remove(at: index)
        guard persist(candidate, selectedID: selectedID == id ? candidate[0].id : selectedID) else { return false }
        removed = removing
        return true
    }
    @discardableResult public func undoRemoval() -> Bool {
        guard let removed, save(removed) else { return false }
        self.removed = nil
        return true
    }
    private func persist(_ candidate: [DictationWorkflow], selectedID candidateID: String) -> Bool {
        guard canWrite else {
            error = "Saved modes could not be read and were left untouched. Changes cannot be saved."
            return false
        }
        do {
            let data = try JSONEncoder().encode(Archive(version: 1, workflows: candidate, selectedID: candidateID))
            guard data.count <= 256_000 else { error = "Modes are too large to save. Shorten custom prompts."; return false }
            defaults.set(data, forKey: "workflows.v1")
            // Readback establishes acceptance by UserDefaults, not an fsync guarantee.
            guard defaults.data(forKey: "workflows.v1") == data else {
                error = "Modes could not be saved. Your changes have not been applied."
                return false
            }
            workflows = candidate; selectedID = candidateID; error = nil
            return true
        } catch { self.error = "Modes could not be saved. Your changes have not been applied."; return false }
    }
}
