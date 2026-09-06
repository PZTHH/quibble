import Foundation

/// Local files needed to run the enabled parts of a mode. Unknown identifiers are
/// deliberately preserved so a missing catalog entry cannot look like a ready mode.
public enum SetupRequirements {
    public static func modelIDs(for workflow: DictationWorkflow, hasVocabulary: Bool) -> [String] {
        let online = ["openai-transcribe", "openai-diarize"].contains(workflow.speechModel)
        var identifiers = online ? [] : [workflow.speechModel]
        for step in workflow.enabledSteps {
            if step.kind == .vocabulary {
                if hasVocabulary && !online { identifiers.append(step.modelID) }
            } else {
                identifiers.append(step.modelID)
            }
        }
        return unique(identifiers)
    }

    public static func missingModelIDs(for workflow: DictationWorkflow, hasVocabulary: Bool,
                                      installed: Set<String>) -> [String] {
        modelIDs(for: workflow, hasVocabulary: hasVocabulary).filter { !installed.contains($0) }
    }

    fileprivate static func unique(_ identifiers: [String]) -> [String] {
        var seen: Set<String> = []
        return identifiers.filter { seen.insert($0).inserted }
    }
}

/// A deterministic setup queue. A request with an unknown ID must be resolved
/// before downloading, rather than silently dropping a requirement.
public struct SetupDownloadPlan: Equatable, Sendable {
    public let missingIDs: [String]
    public let unknownIDs: [String]
    public var canDownload: Bool { unknownIDs.isEmpty && !missingIDs.isEmpty }

    public init(requested: [String], installed: Set<String>, available: Set<String>) {
        let identifiers = SetupRequirements.unique(requested)
        unknownIDs = identifiers.filter { !available.contains($0) }
        missingIDs = identifiers.filter { !installed.contains($0) }
    }
}
