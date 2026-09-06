import Foundation

public struct VocabularyChange: Codable, Equatable, Sendable, Identifiable {
    public var id: Int { location }
    public let location: Int
    public let length: Int
    public let before: String
    public let after: String
    public let explicit: Bool
    public init(location: Int, length: Int, before: String, after: String, explicit: Bool) {
        self.location = location; self.length = length; self.before = before; self.after = after; self.explicit = explicit
    }
}

public struct VocabularyResult: Sendable {
    public let original: String
    public let text: String
    public let changes: [VocabularyChange]
    public let protectedTerms: [String]
}

/// Compiled once per vocabulary revision. No network or model inference.
public struct VocabularyProcessor: Sendable {
    public let entries: [VocabularyEntry]
    private struct Term: Sendable { let key: String; let preferred: String }
    private let terms: [String: [Term]]
    private let rules: [String: String]
    private let ruleRegex: NSRegularExpression?
    private let preferredRegex: NSRegularExpression?
    private static let words = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}]+"#)
    static let protected = try! NSRegularExpression(pattern:
        #"`[^`]*`|(?:https?://|www\.)[^\s]+|[\p{L}\p{N}._%+-]+@[\p{L}\p{N}.-]+\.[\p{L}]{2,}|[\p{L}\p{N}]+_[\p{L}\p{N}_]+|(?:~?/)[^\s]+|[\p{L}\p{N}-]+\.(?:com|org|net|io|dev)\b"#,
        options: [.caseInsensitive])

    public init(entries: [VocabularyEntry]) {
        self.entries = entries.filter { $0.enabled && !$0.preferred.isEmpty }
        var terms: [String: [Term]] = [:]
        var choices: [String: Set<String>] = [:]
        for entry in self.entries {
            let key = Self.key(entry.preferred)
            if key.count >= 6 {
                terms[String(key.prefix(3)), default: []].append(Term(key: key, preferred: entry.preferred))
            }
            if entry.correctionsEnabled {
                for alias in entry.aliases where !alias.isEmpty {
                    choices[alias.lowercased(), default: []].insert(entry.preferred)
                }
            }
        }
        self.terms = terms
        // Conflicting imported/legacy rules are inert until the user resolves them.
        self.rules = choices.filter { $0.value.count == 1 }.mapValues { $0.first! }
        let patterns = rules.keys.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        self.ruleRegex = patterns.isEmpty ? nil : try? NSRegularExpression(pattern:
            #"(?<![\p{L}\p{N}_])(?:"# + patterns.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")(?![\p{L}\p{N}_])"#, options: [.caseInsensitive])
        let preferred = Array(Set(self.entries.map(\.preferred))).sorted { $0.count > $1.count }
        self.preferredRegex = preferred.isEmpty ? nil : try? NSRegularExpression(pattern:
            #"(?<![\p{L}\p{N}_])(?:"# + preferred.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + #")(?![\p{L}\p{N}_])"#)
    }

    public func process(_ text: String, isKnownWord: (String) -> Bool) -> VocabularyResult {
        guard !entries.isEmpty, text.utf16.count <= 16_000 else {
            return VocabularyResult(original: text, text: text, changes: [], protectedTerms: [])
        }
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        let protected = Self.protected.matches(in: text, range: range).map(\.range)
        var changes: [VocabularyChange] = []
        func overlaps(_ range: NSRange) -> Bool {
            protected.contains { NSIntersectionRange($0, range).length > 0 }
                || changes.contains { NSIntersectionRange(NSRange(location: $0.location, length: $0.length), range).length > 0 }
        }
        for match in ruleRegex?.matches(in: text, range: range) ?? [] where !overlaps(match.range) {
            let heard = source.substring(with: match.range)
            if let preferred = rules[heard.lowercased()], preferred != heard {
                changes.append(VocabularyChange(location: match.range.location, length: match.range.length,
                    before: heard, after: preferred, explicit: true))
            }
        }
        for word in Self.words.matches(in: text, range: range) where !overlaps(word.range) {
            let heard = source.substring(with: word.range), key = Self.key(heard)
            guard key.count >= 6, let bucket = terms[String(key.prefix(3))] else { continue }
            let candidates = bucket.filter { abs($0.key.count - key.count) <= 1 && Self.distance(key, $0.key) <= 1 }
            let preferred = Set(candidates.map(\.preferred))
            guard preferred.count == 1, let term = preferred.first, term != heard,
                  !isKnownWord(heard.lowercased()) else { continue }
            changes.append(VocabularyChange(location: word.range.location, length: word.range.length,
                before: heard, after: term, explicit: false))
        }
        return result(for: text, changes: changes)
    }

    func result(for text: String, changes: [VocabularyChange]) -> VocabularyResult {
        let changes = changes.sorted { $0.location < $1.location }
        let result = NSMutableString(string: text)
        for change in changes.reversed() { result.replaceCharacters(in: NSRange(location: change.location, length: change.length), with: change.after) }
        let final = result as String
        let finalSource = final as NSString
        let matchedTerms = preferredRegex?.matches(in: final, range: NSRange(location: 0, length: finalSource.length))
            .map { finalSource.substring(with: $0.range) } ?? []
        return VocabularyResult(original: text, text: final, changes: changes, protectedTerms: Array(Set(matchedTerms)))
    }

    public static func preservesTerms(in cleaned: String, from result: VocabularyResult) -> Bool {
        result.protectedTerms.allSatisfy { count($0, in: cleaned) == count($0, in: result.text) }
    }
    private static func count(_ term: String, in text: String) -> Int {
        let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: term) + #"(?![\p{L}\p{N}_])"#
        return (try? NSRegularExpression(pattern: pattern))?.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) ?? 0
    }
    private static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }
    private static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        guard abs(a.count - b.count) <= 1 else { return 2 }
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var row = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, y) in b.enumerated() { row[j + 1] = min(row[j] + 1, previous[j + 1] + 1, previous[j] + (x == y ? 0 : 1)) }
            if row.min()! > 1 { return 2 }
            previous = row
        }
        return previous[b.count]
    }
}
