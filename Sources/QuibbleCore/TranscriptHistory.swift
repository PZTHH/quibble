import Foundation
import Combine

public struct TranscriptRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let original: String
    public var text: String
    public let application: String
    public let applicationBundleID: String?
    public let mode: String
    public let engine: String
    public let delivery: String
    public let warning: String?
    /// Nil for imported audio and history created before duration was recorded.
    public let audioSeconds: Double?
    /// Original ASR sections. Nil in older history and when timing was unavailable.
    public let segments: [TranscriptSegment]?
    public init(id: UUID = UUID(), date: Date = Date(), original: String, text: String,
                application: String, applicationBundleID: String? = nil, mode: String, engine: String, delivery: String, warning: String? = nil,
                audioSeconds: Double? = nil, segments: [TranscriptSegment]? = nil) {
        self.id = id; self.date = date; self.original = original; self.text = text
        self.application = application; self.mode = mode; self.engine = engine
        self.applicationBundleID = applicationBundleID
        self.delivery = delivery; self.warning = warning
        self.audioSeconds = audioSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.segments = segments
    }
}

@MainActor
public final class TranscriptHistory: ObservableObject {
    public static let maximumTextUnits = 250_000
    @Published public private(set) var records: [TranscriptRecord] = []
    @Published public private(set) var pace = DictationPace(records: [])
    @Published public private(set) var isPersistent = false
    @Published public private(set) var error: String?
    private let directory: URL
    private let defaults: UserDefaults
    private var storageReadable = true
    private var file: URL { directory.appendingPathComponent("history.json") }
    private struct Archive: Codable { let version: Int; let records: [TranscriptRecord] }
    public init(directory: URL, defaults: UserDefaults = .standard) {
        self.directory = directory; self.defaults = defaults
        isPersistent = defaults.bool(forKey: "keepTranscriptHistory")
        if isPersistent, FileManager.default.fileExists(atPath: file.path) {
            do {
                guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 8_000_000 else { throw CocoaError(.fileReadCorruptFile) }
                let data = try Data(contentsOf: file)
                let archive = try JSONDecoder().decode(Archive.self, from: data)
                guard archive.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                records = archive.records
            } catch { storageReadable = false; self.error = "Saved history could not be read. It has been left untouched. New dictations are available for this session." }
        }
        prune()
    }
    public func append(_ record: TranscriptRecord, now: Date = Date()) {
        guard !record.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard record.text.utf16.count <= Self.maximumTextUnits, record.original.utf16.count <= Self.maximumTextUnits,
              Self.storageUnits(record) <= 1_000_000 else {
            error = "This transcript exceeds history’s storage capacity. The current result is still available to copy."
            return
        }
        records.removeAll { $0.id == record.id }
        records.insert(record, at: 0)
        trim(now: now)
        save()
    }
    public func prune(now: Date = Date()) {
        let before = records
        trim(now: now)
        if before != records { save() }
    }
    private func trim(now: Date) {
        var seen = Set<UUID>()
        // JSON can escape each UTF-16 code unit to six bytes. Bound all stored
        // strings so even heavily escaped text stays below the 8 MB read limit.
        var remainingUnits = 1_000_000
        records = Array(records.filter { record in
            record.date > now.addingTimeInterval(-7 * 86400) && record.date <= now.addingTimeInterval(60)
                && !record.text.isEmpty && record.text.utf16.count <= Self.maximumTextUnits && record.original.utf16.count <= Self.maximumTextUnits
                && seen.insert(record.id).inserted
        }.sorted { $0.date > $1.date }.prefix(100).prefix { record in
            let units = Self.storageUnits(record)
            guard units <= remainingUnits else { return false }
            remainingUnits -= units
            return true
        })
        // Compute on history changes, never on the HUD's audio-meter refresh.
        pace = DictationPace(records: records)
    }

    private static func storageUnits(_ record: TranscriptRecord) -> Int {
        let text = [record.original, record.text, record.application, record.applicationBundleID ?? "", record.mode,
                    record.engine, record.delivery, record.warning ?? ""].reduce(0) { $0 + $1.utf16.count }
        // Include raw segment text and conservative overhead for IDs, keys, and timestamps.
        return text + (record.segments ?? []).reduce(0) { $0 + $1.text.utf16.count + $1.id.utf16.count + ($1.speaker?.utf16.count ?? 0) + 128 }
    }

    @Published private var removed: TranscriptRecord?
    public var canUndoRemoval: Bool { removed != nil }
    public func remove(id: UUID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        removed = records.remove(at: index)
        pace = DictationPace(records: records)
        save()
    }
    public func undoRemoval() {
        guard let removed else { return }
        append(removed)
        self.removed = nil
    }

    public func update(id: UUID, text: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        guard records[index].text != text else { return }
        guard text.utf16.count <= Self.maximumTextUnits,
              Self.storageUnits(records[index]) - records[index].text.utf16.count + text.utf16.count <= 1_000_000 else {
            error = "This edit exceeds history’s storage capacity. The saved transcript was retained."
            return
        }
        records[index].text = text
        trim(now: Date())
        save()
    }

    public func setPersistent(_ value: Bool) {
        if value {
            guard storageReadable else { return }
            isPersistent = true
            save()

        } else {
            do {
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                isPersistent = false; storageReadable = true; error = nil
            } catch { self.error = "Could not remove saved history. Local storage remains enabled."; return }
        }
        defaults.set(isPersistent, forKey: "keepTranscriptHistory")
    }
    private func save() {
        guard isPersistent, storageReadable else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(Archive(version: 1, records: records)).write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            error = nil
        } catch { self.error = "History could not be saved. Your text is still available for this session." }
    }
}
