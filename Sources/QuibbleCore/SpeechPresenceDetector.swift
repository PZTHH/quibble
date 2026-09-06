import Foundation
import SoundAnalysis
import CoreMedia
import AVFoundation

public enum SpeechPresence: Sendable, Equatable { case speech, noSpeech, uncertain }

/// Local preflight, shared by every ASR model. An uncertain result always keeps the audio.
public actor SpeechPresenceDetector {
    public static let shared = SpeechPresenceDetector()
    private let temporaryDirectory: URL
    public init() { temporaryDirectory = FileManager.default.temporaryDirectory }
    init(temporaryDirectory: URL) { self.temporaryDirectory = temporaryDirectory }

    public func detect(in file: URL) async throws -> SpeechPresence {
        try Task.checkCancellation()
        var analysisCopy: URL?
        defer { if let analysisCopy { try? FileManager.default.removeItem(at: analysisCopy) } }
        let request: SNClassifySoundRequest
        let analyzer: SNAudioFileAnalyzer
        do {
            let audio = try AVAudioFile(forReading: file, commonFormat: .pcmFormatFloat32, interleaved: false)
            let rate = audio.processingFormat.sampleRate
            // SoundAnalysis classifies channel zero. A quiet left channel cannot
            // establish absence of speech elsewhere; the ASR reader downmixes all channels.
            guard audio.processingFormat.channelCount == 1, rate.isFinite,
                  (8_000...192_000).contains(rate), audio.length >= 0 else { return .uncertain }
            if audio.length == 0 { return .noSpeech }
            if Double(audio.length) / rate < 0.5 {
                // A quick release may contain only the start cue. SoundAnalysis
                // needs a complete window; pad its private copy, never the ASR input.
                let copy = temporaryDirectory.appendingPathComponent("quibble-speech-analysis-\(UUID()).caf")
                analysisCopy = copy
                try writePaddedCopy(audio, to: copy)
            }
            try Task.checkCancellation()
            request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: 0.5, preferredTimescale: 16_000)
            request.overlapFactor = 0.5
            analyzer = try SNAudioFileAnalyzer(url: analysisCopy ?? file)
        } catch {
            try Task.checkCancellation()
            return .uncertain
        }
        let session = PresenceAnalysis(analyzer: analyzer)
        let observer = PresenceObserver { session.cancel() }
        do { try analyzer.add(request, withObserver: observer) }
        catch { return .uncertain }
        return try await withTaskCancellationHandler {
            analyzer.analyze()
            try Task.checkCancellation()
            return observer.result
        } onCancel: {
            session.cancel()
        }
    }

    private func writePaddedCopy(_ audio: AVAudioFile, to destination: URL) throws {
        let count = AVAudioFrameCount(audio.processingFormat.sampleRate.rounded(.up))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: count) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try Task.checkCancellation()
        try audio.read(into: buffer, frameCount: AVAudioFrameCount(audio.length))
        guard buffer.frameLength == audio.length, let samples = buffer.floatChannelData?[0],
              UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)).allSatisfy(\.isFinite) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        samples.advanced(by: Int(buffer.frameLength)).initialize(repeating: 0, count: Int(count - buffer.frameLength))
        buffer.frameLength = count
        try Task.checkCancellation()
        let output = try AVAudioFile(forWriting: destination, settings: buffer.format.settings)
        try output.write(from: buffer)
    }
}

/// SoundAnalysis supports cancelling its synchronous file analysis from another thread.
private final class PresenceAnalysis: @unchecked Sendable {
    let analyzer: SNAudioFileAnalyzer
    init(analyzer: SNAudioFileAnalyzer) { self.analyzer = analyzer }
    func cancel() { analyzer.cancelAnalysis() }
}

private final class PresenceObserver: NSObject, SNResultsObserving, @unchecked Sendable {
    private let lock = NSLock()
    private var maximumSpeech = 0.0
    private var reports = 0
    private var completed = false
    private var failed = false
    private let onSpeech: @Sendable () -> Void
    init(onSpeech: @escaping @Sendable () -> Void) { self.onSpeech = onSpeech }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        // Whispered dictation may score under the classifier's separate voice label.
        let confidence = ["speech", "whispering"].compactMap {
            classification.classification(forIdentifier: $0)?.confidence
        }.filter(\.isFinite).max()
        guard let confidence else { return }
        lock.lock()
        maximumSpeech = max(maximumSpeech, confidence)
        reports += 1
        let found = maximumSpeech >= 0.5
        lock.unlock()
        // Stop at the first plausible speech window. Long spoken dictations cost no extra analysis.
        if found { onSpeech() }
    }
    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock(); failed = true; lock.unlock()
    }
    func requestDidComplete(_ request: SNRequest) {
        lock.lock(); completed = true; lock.unlock()
    }
    var result: SpeechPresence {
        lock.lock(); defer { lock.unlock() }
        if maximumSpeech >= 0.5 { return .speech }
        // Short files, errors, and borderline scores must not discard a quiet or unusual voice.
        if completed && !failed && reports > 0 && maximumSpeech < 0.3 { return .noSpeech }
        return .uncertain
    }
}
