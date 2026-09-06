import Foundation

/// Original ASR text and timing. Writing cleanup must not relabel these timestamps.
public struct TranscriptSegment: Codable, Equatable, Identifiable, Sendable {
    public enum Source: String, Codable, Sendable {
        /// Timing returned by an acoustic alignment or diarization model.
        case model
        /// Actual input audio-window bounds; not word or sentence alignment.
        case audioChunk
    }

    public let id: String
    public let start: Double
    public let end: Double
    public let text: String
    public let speaker: String?
    public let source: Source

    public init(id: String = UUID().uuidString, start: Double, end: Double, text: String,
                speaker: String? = nil, source: Source) {
        self.id = id; self.start = start; self.end = end; self.text = text
        self.speaker = speaker; self.source = source
    }

    public var isValid: Bool {
        start.isFinite && end.isFinite && start >= 0 && end > start
            && !id.isEmpty && id.utf16.count <= 160
            && !id.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
            && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.utf16.count <= 32_000
            && (speaker.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.utf16.count <= 128
                && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) } ?? true)
    }

    private enum CodingKeys: String, CodingKey { case id, start, end, text, speaker, source }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id), start: try values.decode(Double.self, forKey: .start),
            end: try values.decode(Double.self, forKey: .end), text: try values.decode(String.self, forKey: .text),
            speaker: try values.decodeIfPresent(String.self, forKey: .speaker), source: try values.decode(Source.self, forKey: .source))
        guard isValid else { throw DecodingError.dataCorruptedError(forKey: .start, in: values, debugDescription: "Invalid transcript segment metadata") }
    }

    /// Speaker labels from independent requests are scoped, never merged by matching A/B labels.
    public func offsetted(by seconds: Double, speakerScope: String? = nil) -> Self {
        let scopedSpeaker = speaker.map { label in speakerScope.map { "\($0) · \(label)" } ?? label }
        return Self(id: speakerScope.map { "\($0)-\(id)" } ?? id, start: start + seconds, end: end + seconds,
                    text: text, speaker: scopedSpeaker, source: source)
    }

    /// Converts the optional metadata returned by MLXAudioSTT without inventing timing or speakers.
    public static func fromModelSegments(_ values: [[String: Any]], source: Source, offset: Double = 0) -> [Self] {
        values.compactMap { value in
            guard let start = value["start"] as? Double, let end = value["end"] as? Double,
                  let text = value["text"] as? String else { return nil }
            let segment = Self(id: value["id"] as? String ?? UUID().uuidString,
                start: start + offset, end: end + offset, text: text,
                speaker: value["speaker"] as? String, source: source)
            return segment.isValid ? segment : nil
        }
    }
}
