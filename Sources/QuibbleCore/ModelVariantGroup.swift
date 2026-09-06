import Foundation

/// One user-facing model with one or more downloadable representations.
public struct ModelVariantGroup: Identifiable, Sendable {
    public let id: String
    public let variants: [LocalModelSpec]

    /// Conservative reserve for optional local writing/vocabulary models. It stays
    /// independent of the current speech backend so a new local choice can reuse it.
    public static func additionalModelBytes(for workflow: DictationWorkflow, hasVocabulary: Bool,
                                            models: [LocalModelSpec]) -> UInt64 {
        var ids = Set(workflow.enabledSteps.filter { $0.kind != .vocabulary || hasVocabulary }.map(\.modelID))
        if hasVocabulary && workflow.enabledSteps.contains(where: { $0.kind == .vocabulary }) { ids.insert("s1-mini") }
        let bytes = models.filter { ids.contains($0.name) && $0.gigabytes.isFinite && $0.gigabytes > 0 }
            .reduce(0.0) { $0 + $1.gigabytes * 2_000_000_000 }
        return bytes.isFinite && bytes < Double(UInt64.max) ? UInt64(bytes) : UInt64.max
    }

    public static func make(from models: [LocalModelSpec]) -> [ModelVariantGroup] {
        var order: [String] = [], grouped: [String: [LocalModelSpec]] = [:]
        for model in models {
            let id = model.logicalModelID
            if grouped[id] == nil { order.append(id) }
            grouped[id, default: []].append(model)
        }
        return order.map { ModelVariantGroup(id: $0, variants: grouped[$0] ?? []) }
    }

    public func recommendedVariant(physicalMemoryBytes: UInt64, selectedID: String? = nil,
                                   installed: Set<String> = [], additionalModelBytes: UInt64 = 0) -> LocalModelSpec? {
        if let selectedID, let selected = variants.first(where: { $0.name == selectedID }) { return selected }
        let ordered = variants.enumerated().sorted {
            let left = $0.element.artifactSource == "publisher"
            let right = $1.element.artifactSource == "publisher"
            return left == right ? $0.offset < $1.offset : left
        }.map(\.element)
        let quantized = ordered.filter { model in model.weightBits.map { (1...8).contains($0) } ?? false }
        if let downloaded = quantized.first(where: { installed.contains($0.name) }) { return downloaded }
        let budget = Double(physicalMemoryBytes) * 0.4 - Double(additionalModelBytes)
        // This is a conservative download recommendation, not measured runtime RAM:
        // leave most memory to the OS/other apps and allow space beyond model weights.
        func fits(_ model: LocalModelSpec) -> Bool {
            model.gigabytes.isFinite && model.gigabytes > 0
                && model.gigabytes * 2_000_000_000 + 1_500_000_000 <= budget
        }
        let candidates = quantized.isEmpty ? ordered : quantized
        let tested = candidates.filter { $0.smokeTested == true }
        // Memory alone must not promote an untested conversion over one that has
        // actually run. Experimental labels and upstream scores are not evidence.
        let options = tested.isEmpty ? candidates : tested
        if let preferred = options.first(where: { $0.preferredVariant == true && fits($0) }) {
            return options.first { $0.weightBits == preferred.weightBits && fits($0) } ?? preferred
        }
        if let eight = options.first(where: { $0.weightBits == 8 && fits($0) }) { return eight }
        return options.first(where: { $0.weightBits == 4 }) ?? options.first
    }
}
