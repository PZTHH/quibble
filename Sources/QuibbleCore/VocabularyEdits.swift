import Foundation

/// An inference result is a proposal, never authority to rewrite the whole transcript.
public enum VocabularyEdits {
    /// Projects a model hypothesis onto saved-word edits; semantic validation is still required.
    public static func project(_ hypothesis: String, onto original: String, entries: [VocabularyEntry]) -> VocabularyResult {
        let unchanged = VocabularyProcessor(entries: entries).result(for: original, changes: [])
        guard original.utf16.count <= 16_000, hypothesis.utf16.count <= 16_000 else { return unchanged }
        let source = original as NSString, proposed = hypothesis as NSString
        let a = lexical.matches(in: original, range: NSRange(location: 0, length: source.length))
        let b = lexical.matches(in: hypothesis, range: NSRange(location: 0, length: proposed.length))
        guard a.count <= 512, b.count <= 512 else { return unchanged }
        let aw = a.map { source.substring(with: $0.range) }
        let bw = b.map { proposed.substring(with: $0.range) }
        let vocabularyTokens = Set(entries.filter(\.enabled).flatMap { entry in
            lexical.matches(in: entry.preferred, range: NSRange(location: 0, length: (entry.preferred as NSString).length))
                .map { (entry.preferred as NSString).substring(with: $0.range).lowercased() }
        })
        func anchor(_ word: String) -> String { vocabularyTokens.contains(word.lowercased()) ? word : word.lowercased() }
        let ax = aw.map(anchor), bx = bw.map(anchor)
        let width = b.count + 1
        var lcs = Array(repeating: 0, count: (a.count + 1) * width)
        for i in a.indices.reversed() {
            for j in b.indices.reversed() {
                lcs[i * width + j] = ax[i] == bx[j]
                    ? 1 + lcs[(i + 1) * width + j + 1]
                    : max(lcs[(i + 1) * width + j], lcs[i * width + j + 1])
            }
        }
        let allowed = Set(entries.filter(\.enabled).map(\.preferred))
        var proposals: [[String: String]] = []
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, ax[i] == bx[j] { i += 1; j += 1; continue }
            let from = i, to = j
            while i < a.count || j < b.count {
                if i < a.count, j < b.count, ax[i] == bx[j] { break }
                if j < b.count && (i == a.count || lcs[i * width + j + 1] > lcs[(i + 1) * width + j]) { j += 1 }
                else { i += 1 }
            }
            // A vocabulary correction replaces existing words; insertions and deletions are never applied.
            guard i > from, j > to, i - from <= 4 else { continue }
            let heardRange = NSRange(location: a[from].range.location,
                length: NSMaxRange(a[i - 1].range) - a[from].range.location)
            let targetRange = NSRange(location: b[to].range.location,
                length: NSMaxRange(b[j - 1].range) - b[to].range.location)
            let heard = source.substring(with: heardRange), target = proposed.substring(with: targetRange)
            guard allowed.contains(target) else { continue }
            // Do not swallow neighboring words when the model shortened a sentence around a name.
            // Joined/split technical terms may differ only slightly in spelling.
            if i - from > j - to {
                let x = aw[from..<i].joined().lowercased(), y = bw[to..<j].joined().lowercased()
                guard closeCompound(x, y) else { continue }
            }
            if i - from > 1 {
                let interior = source.substring(with: heardRange)
                let letters = aw[from..<i].joined()
                guard interior.filter({ !$0.isWhitespace }) == letters else { continue }
            }
            proposals.append(["heard": heard, "preferred": target])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: proposals) else { return unchanged }
        return apply(String(decoding: data, as: UTF8.self), to: original, entries: entries)
    }

    /// Case/spacing alone cannot establish whether an ordinary word names a saved product.
    public static func needsNormalization(_ change: VocabularyChange) -> Bool {
        func compact(_ value: String) -> String { value.lowercased().filter { !$0.isWhitespace } }
        return compact(change.before) == compact(change.after)
    }

    /// Audio proposes spellings; independent cleanup must agree on ambiguous capitalization/joins.
    /// Explicit user rules take precedence. Every change uses offsets in the original transcript.
    public static func resolve(_ hypothesis: String, onto original: String, entries: [VocabularyEntry], normalization: String?) -> VocabularyResult {
        let processor = VocabularyProcessor(entries: entries)
        let rules = processor.process(original, isKnownWord: { _ in true })
        let proposed = project(hypothesis, onto: original, entries: entries)
        let corroborated = normalization.map { project($0, onto: original, entries: entries).changes } ?? []
        let automatic = proposed.changes.filter { change in
            let overlap = rules.changes.contains { rule in
                NSIntersectionRange(NSRange(location: change.location, length: change.length), NSRange(location: rule.location, length: rule.length)).length > 0
            }
            return !overlap && (!needsNormalization(change) || corroborated.contains(change))
        }
        return processor.result(for: original, changes: rules.changes + automatic)
    }

    private static let lexical = try! NSRegularExpression(pattern: #"[\p{L}\p{M}\p{N}]+(?:[’'-][\p{L}\p{M}\p{N}]+)*[+#]*"#)
    private static func closeCompound(_ lhs: String, _ rhs: String) -> Bool {
        let x = Array(lhs), y = Array(rhs)
        guard abs(x.count - y.count) <= 2 else { return false }
        var row = Array(0...y.count)
        for (i, c) in x.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: y.count)
            for (j, d) in y.enumerated() { next[j + 1] = min(next[j] + 1, row[j + 1] + 1, row[j] + (c == d ? 0 : 1)) }
            row = next
        }
        return row[y.count] <= 2
    }

    private struct Proposal: Decodable { let heard: String; let preferred: String }

    public static func apply(_ response: String, to text: String, entries: [VocabularyEntry]) -> VocabularyResult {
        let processor = VocabularyProcessor(entries: entries)
        let unchanged = processor.result(for: text, changes: [])
        guard response.utf8.count <= 16_000, text.utf16.count <= 16_000,
              let proposals = try? JSONDecoder().decode([Proposal].self, from: Data(response.utf8)),
              proposals.count <= 24 else { return unchanged }
        let allowed = Set(entries.filter(\.enabled).map(\.preferred))
        let source = text as NSString
        let full = NSRange(location: 0, length: source.length)
        let protected = VocabularyProcessor.protected.matches(in: text, range: full).map(\.range)
        var changes: [VocabularyChange] = []
        for proposal in proposals {
            guard allowed.contains(proposal.preferred), !proposal.heard.isEmpty,
                  proposal.heard != proposal.preferred, proposal.heard.utf16.count <= 80,
                  proposal.heard.split(whereSeparator: \.isWhitespace).count <= 4,
                  !proposal.heard.contains(where: \.isNewline) else { continue }
            let pattern = #"(?<![\p{L}\p{N}_])"# + NSRegularExpression.escapedPattern(for: proposal.heard) + #"(?![\p{L}\p{N}_])"#
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: text, range: full)
            // A phrase-only proposal cannot identify which repeated occurrence was intended.
            guard matches.count == 1, let range = matches.first?.range,
                  !protected.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                  !changes.contains(where: { NSIntersectionRange(NSRange(location: $0.location, length: $0.length), range).length > 0 }),
                  !allowed.contains(proposal.heard) else { continue }
            changes.append(VocabularyChange(location: range.location, length: range.length,
                before: proposal.heard, after: proposal.preferred, explicit: false))
        }
        return processor.result(for: text, changes: changes)
    }
}
