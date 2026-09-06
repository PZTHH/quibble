import Foundation
import Combine
import QuibbleCore

@MainActor
final class VocabularyStore: ObservableObject {
    @Published private(set) var entries: [VocabularyEntry] = []
    @Published private(set) var suggestions: [VocabularyCorrection] = []
    @Published private(set) var error: String?
    @Published private(set) var canUndo = false
    @Published var enabled = UserDefaults.standard.object(forKey: "vocabularyEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "vocabularyEnabled") }
    }
    @Published var learningEnabled = UserDefaults.standard.object(forKey: "learningEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(learningEnabled, forKey: "learningEnabled") }
    }
    private struct Storage: Codable {
        var version: Int? = 1
        var entries: [VocabularyEntry]
        var learning: CorrectionLearning
    }
    private var learning = CorrectionLearning()
    private var previous: Storage?
    private(set) var processor = VocabularyProcessor(entries: [])
    private let file: URL
    private var readable = true
    init(file: URL? = nil) {
        self.file = file ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Quibble/vocabulary.json")
        if FileManager.default.fileExists(atPath: self.file.path) {
            do {
                let storage = try JSONDecoder().decode(Storage.self, from: Data(contentsOf: self.file))
                guard (storage.version ?? 1) == 1 else { throw VocabularyArchive.ValidationError("This vocabulary uses a newer file format.") }
                entries = storage.entries; learning = storage.learning; refresh()
            } catch { self.error = "Your vocabulary could not be opened. The original file has been preserved. \(error.localizedDescription)"; readable = false }
        }
    }
    @discardableResult func save(_ entry: VocabularyEntry) -> Bool {
        var clean = entry
        clean.preferred = clean.preferred.trimmingCharacters(in: .whitespacesAndNewlines)
        clean.aliases = Array(Set(clean.aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
        var updated = entries
        if let index = updated.firstIndex(where: { $0.id == clean.id }) { updated[index] = clean }
        else { updated.append(clean) }
        return commit(updated, learning: learning)
    }
    func setEnabled(_ entry: VocabularyEntry, _ enabled: Bool) {
        var updated = entry; updated.enabled = enabled; save(updated)
    }
    func remove(_ id: UUID) { commit(entries.filter { $0.id != id }, learning: learning) }
    func observe(id: UUID, original: String, edited: String) {
        guard readable, learningEnabled else { return }
        var updated = learning
        updated.observe(session: id, original: original, edited: edited)
        // Do not turn machine changes into examples; callers supply user-edited final text.
        commit(entries, learning: updated, manual: false)
    }
    func accept(_ correction: VocabularyCorrection, asRule: Bool = false) {
        var updated = entries
        if let index = updated.firstIndex(where: { $0.preferred.caseInsensitiveCompare(correction.preferred) == .orderedSame }) {
            if asRule {
                updated[index].aliases = Array(Set(updated[index].aliases + [correction.heard])).sorted()
                updated[index].correctionsEnabled = true
            }
        } else {
            updated.append(VocabularyEntry(preferred: correction.preferred, aliases: asRule ? [correction.heard] : [], correctionsEnabled: asRule))
        }
        var learned = learning; learned.dismiss(correction)
        commit(updated, learning: learned)
    }
    func dismiss(_ correction: VocabularyCorrection) {
        var updated = learning; updated.dismiss(correction); commit(entries, learning: updated)
    }
    func undo() {
        guard let previous else { return }
        var restored = learning
        restored.restoreDismissals(from: previous.learning)
        if commit(previous.entries, learning: restored, manual: false) { self.previous = nil; canUndo = false }
    }
    func clearError() { error = nil }
    func report(_ error: Error) { self.error = error.localizedDescription }
    func exportData() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(VocabularyArchive(entries: entries))
    }
    func previewImport(_ data: Data) throws -> [VocabularyEntry] {
        guard data.count <= 2_000_000 else { throw VocabularyArchive.ValidationError("Choose a vocabulary file smaller than 2 MB.") }
        let archive = try JSONDecoder().decode(VocabularyArchive.self, from: data)
        let imported = try archive.validated()
        let additions = imported.filter { incoming in !entries.contains { $0.preferred.caseInsensitiveCompare(incoming.preferred) == .orderedSame } }
            .map { incoming in var entry = incoming; entry.id = UUID(); return entry }
        _ = try VocabularyArchive(entries: entries + additions).validated()
        return additions
    }
    @discardableResult func importEntries(_ additions: [VocabularyEntry]) -> Bool { commit(entries + additions, learning: learning) }
    @discardableResult private func commit(_ updated: [VocabularyEntry], learning: CorrectionLearning, manual: Bool = true) -> Bool {
        guard readable else { return false }
        do {
            _ = try VocabularyArchive(entries: updated).validated()
            let sorted = updated.sorted { $0.preferred.localizedCaseInsensitiveCompare($1.preferred) == .orderedAscending }
            let data = try JSONEncoder().encode(Storage(entries: sorted, learning: learning))
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            if manual { previous = Storage(entries: entries, learning: self.learning); canUndo = true }
            // Publish only after the durable write succeeds.
            let changed = entries != sorted
            entries = sorted; self.learning = learning; refresh(rebuildProcessor: changed); error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    private func refresh(rebuildProcessor: Bool = true) {
        if rebuildProcessor { processor = VocabularyProcessor(entries: entries) }
        suggestions = learning.suggestions.filter { correction in
            !entries.contains { $0.preferred == correction.preferred && $0.correctionsEnabled && $0.aliases.contains(correction.heard) }
        }
    }
}
