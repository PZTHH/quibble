import Foundation

/// A duration-weighted estimate over measured dictations, including pauses.
public struct DictationPace: Equatable, Sendable {
    public let words: Int
    public let seconds: Double
    /// Very short samples make unstable estimates; wait for ten measured seconds.
    public var wordsPerMinute: Double? { seconds >= 10 && words > 0 ? Double(words) * 60 / seconds : nil }
    public init(records: [TranscriptRecord]) {
        var wordTotal = 0, duration = 0.0
        for record in records {
            guard let seconds = record.audioSeconds, seconds.isFinite, seconds > 0, (duration + seconds).isFinite else { continue }
            var count = 0
            record.original.enumerateSubstrings(in: record.original.startIndex..<record.original.endIndex,
                options: [.byWords, .substringNotRequired]) { _, _, _, _ in count += 1 }
            guard count > 0 else { continue }
            wordTotal += count; duration += seconds
        }
        words = wordTotal; seconds = duration
    }
}
