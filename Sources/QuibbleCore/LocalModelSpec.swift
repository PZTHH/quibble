import Foundation

public struct LocalModelSpec: Codable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let repository: String
    public let revision: String
    public let files: [String]
    public struct AssetSource: Codable, Sendable { public let repository: String; public let revision: String }
    public let fileSources: [String: AssetSource]?
    public let title: String
    public let category: String
    public let variant: String
    public let gigabytes: Double
    public let detail: String
    public let source: String?
    public let parameters: Int?
    public let languages: String?
    public let license: String?
    public let validation: String?
    public let fileBytes: [String: Int64]?
    /// Same checkpoint and parameter size; different weight formats share this ID.
    public let familyID: String?
    public let quantizationBits: Int?
    /// Upstream score reference, independent from this artifact's weight precision.
    public let benchmarkModelID: String?
    /// An explicitly documented per-model recommendation, not inferred from a title.
    public let preferredVariant: Bool?
    /// "publisher" or "conversion" when the artifact's publisher has been verified.
    public let artifactSource: String?
    /// Successful local inference checks of this exact artifact, distinct from
    /// upstream scores or an experimental label. Missing evidence is not a pass.
    public let smokeTested: Bool?
    public var logicalModelID: String {
        guard role == "Speech" else { return name }
        if let familyID, !familyID.isEmpty { return familyID }
        return ["cohere", "cohere-4bit", "cohere-8bit"].contains(name) ? "cohere" : name
    }
    public var weightBits: Int? {
        if let quantizationBits { return quantizationBits }
        if name.hasSuffix("-4bit") { return 4 }
        if name.hasSuffix("-8bit") { return 8 }
        return nil
    }
    public var benchmarkID: String { benchmarkModelID ?? name }
    public var precisionLabel: String {
        if let bits = weightBits { return "\(bits)-bit" }
        if variant.localizedCaseInsensitiveContains("FP32") { return "FP32" }
        if variant.localizedCaseInsensitiveContains("FP16") { return "FP16" }
        return "Original format"
    }
    public var isExperimental: Bool { validation?.localizedCaseInsensitiveContains("experimental") == true || validation?.localizedCaseInsensitiveContains("not yet") == true || validation?.localizedCaseInsensitiveContains("pending") == true }
    public var sizeLabel: String { gigabytes < 1 ? String(format: "%.0f MB", gigabytes * 1000) : String(format: "%.2f GB", gigabytes) }
    public var role: String { category == "Speech recognition" ? "Speech" : name == "s1-mini" ? "Cleanup" : "Instructions" }
}
