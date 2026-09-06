import Foundation

public struct VocabularyArchive: Codable, Sendable {
    public var version: Int = 1
    public var entries: [VocabularyEntry]
    public init(entries: [VocabularyEntry]) { self.entries = entries }
    public func validated() throws -> [VocabularyEntry] {
        guard version == 1 else { throw ValidationError("This vocabulary file was made by a newer version of Quibble.") }
        guard entries.count <= 2_000 else { throw ValidationError("Import up to 2,000 entries at a time.") }
        var names = Set<String>(), ids = Set<UUID>(), aliases: [String: String] = [:]
        for entry in entries {
            let name = entry.preferred.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 80, entry.aliases.count <= 20,
                  entry.aliases.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 80 }),
                  !name.contains(where: \.isNewline), !entry.aliases.contains(where: { $0.contains(where: \.isNewline) }) else {
                throw ValidationError("Use a word or short phrase of up to 80 characters, with up to 20 corrections.")
            }
            guard names.insert(name.lowercased()).inserted, ids.insert(entry.id).inserted else {
                throw ValidationError("The vocabulary contains a duplicate entry for \(name).")
            }
            if entry.enabled && entry.correctionsEnabled {
                for alias in entry.aliases {
                    let key = alias.lowercased()
                    if let other = aliases[key], other != name { throw ValidationError("“\(alias)” already corrects to “\(other)”. Edit that rule first.") }
                    aliases[key] = name
                }
            }
        }
        return entries
    }
    public struct ValidationError: LocalizedError {
        let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }
}
