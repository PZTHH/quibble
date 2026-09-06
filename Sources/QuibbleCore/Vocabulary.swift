import Foundation

public struct VocabularyEntry: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var preferred: String
    public var aliases: [String]
    public var enabled: Bool
    public var correctionsEnabled: Bool
    public init(id: UUID = UUID(), preferred: String, aliases: [String] = [], enabled: Bool = true, correctionsEnabled: Bool = true) {
        self.id = id; self.preferred = preferred; self.aliases = aliases
        self.enabled = enabled; self.correctionsEnabled = correctionsEnabled
    }
    private enum CodingKeys: String, CodingKey { case id, preferred, aliases, enabled, correctionsEnabled }
    public init(from decoder: Decoder) throws {
        let data = try decoder.container(keyedBy: CodingKeys.self)
        id = try data.decode(UUID.self, forKey: .id)
        preferred = try data.decode(String.self, forKey: .preferred)
        aliases = try data.decodeIfPresent([String].self, forKey: .aliases) ?? []
        enabled = try data.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        // Legacy aliases were hidden and inactive in build 6. Preserve that choice.
        correctionsEnabled = try data.decodeIfPresent(Bool.self, forKey: .correctionsEnabled) ?? false
    }
}

public enum Vocabulary {
    public static func apply(_ entries: [VocabularyEntry], to text: String) -> String {
        var replacements: [String: String] = [:]
        for entry in entries where entry.enabled && !entry.preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            for alias in (entry.correctionsEnabled ? entry.aliases : []) + [entry.preferred] where !alias.isEmpty {
                if replacements[alias.lowercased()] == nil { replacements[alias.lowercased()] = entry.preferred }
            }
        }
        let aliases = replacements.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        guard !aliases.isEmpty else { return text }
        let pattern = #"(?<![\p{L}\p{N}_])(?:"# + aliases.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")(?![\p{L}\p{N}_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let result = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            let alias = (text as NSString).substring(with: match.range).lowercased()
            if let preferred = replacements[alias] { result.replaceCharacters(in: match.range, with: preferred) }
        }
        return result as String
    }
}

public struct VocabularyCorrection: Codable, Hashable, Sendable {
    public var heard: String
    public var preferred: String
    public static func detect(original: String, edited: String) -> Self? {
        guard original != edited, original.count <= 8_000, edited.count <= 8_000 else { return nil }
        let before = original.split(whereSeparator: \.isWhitespace).map(String.init)
        let after = edited.split(whereSeparator: \.isWhitespace).map(String.init)
        let trim = CharacterSet(charactersIn: ".,!?;:\"“”()[]{}")
        func comparable(_ word: String) -> String { word.trimmingCharacters(in: trim) }
        var start = 0
        while start < min(before.count, after.count), comparable(before[start]) == comparable(after[start]) { start += 1 }
        var endBefore = before.count, endAfter = after.count
        while endBefore > start, endAfter > start, comparable(before[endBefore - 1]) == comparable(after[endAfter - 1]) {
            endBefore -= 1; endAfter -= 1
        }
        guard endBefore > start, endAfter > start, endBefore - start <= 4, endAfter - start <= 4 else { return nil }
        let heard = before[start..<endBefore].joined(separator: " ").trimmingCharacters(in: trim)
        let preferred = after[start..<endAfter].joined(separator: " ").trimmingCharacters(in: trim)
        guard heard != preferred, !heard.isEmpty, !preferred.isEmpty, heard.count <= 80, preferred.count <= 80,
              heard.rangeOfCharacter(from: .letters) != nil, preferred.rangeOfCharacter(from: .letters) != nil else { return nil }
        return Self(heard: heard.lowercased(), preferred: preferred)
    }
}

public struct CorrectionLearning: Codable, Sendable {
    private var votes: [String: VocabularyCorrection] = [:]
    private var dismissed: Set<VocabularyCorrection> = []
    public init() {}
    public mutating func observe(session: UUID, original: String, edited: String) {
        if let correction = VocabularyCorrection.detect(original: original, edited: edited) {
            votes[session.uuidString] = correction
        } else { votes.removeValue(forKey: session.uuidString) }
        // Retain only a bounded set of phrase pairs, never the full source text.
        if votes.count > 200 { votes.removeValue(forKey: votes.keys.sorted().first!) }
    }
    public var suggestions: [VocabularyCorrection] {
        Dictionary(grouping: votes.values, by: { $0 }).filter { $0.value.count >= 2 && !dismissed.contains($0.key) }
            .keys.sorted { $0.preferred < $1.preferred }
    }
    public mutating func dismiss(_ correction: VocabularyCorrection) { dismissed.insert(correction) }
    public mutating func restoreDismissals(from other: CorrectionLearning) { dismissed = other.dismissed }
}
