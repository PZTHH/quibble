import AVFoundation
import XCTest
@testable import QuibbleCore

@MainActor
final class SpeechPresenceTests: XCTestCase {
    func testShortStartCuesDoNotEnterASRWithoutTrailingSilence() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["soft-start", "start"] {
            let file = root.appendingPathComponent("App/Resources/\(name).wav")
            let original = try Data(contentsOf: file)
            let result = try await SpeechPresenceDetector().detect(in: file)
            XCTAssertEqual(result, .noSpeech, "A fast release after the \(name) cue must not reach ASR")
            XCTAssertEqual(try Data(contentsOf: file), original, "Preflight must leave the original ASR audio unchanged")
        }
    }

    func testShortWordsAndQuietShortWordsAreKept() async throws {
        for name in ["speech-short-yes", "speech-short-um"] {
            let fixture = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "wav"))
            let source = try AVAudioFile(forReading: fixture)
            XCTAssertLessThan(Double(source.length) / source.processingFormat.sampleRate, 0.5)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(source.length)))
            try source.read(into: buffer)
            let samples = try XCTUnwrap(buffer.floatChannelData?[0])
            for gain: Float in [1, 0.02] {
                let file = try write((0..<Int(buffer.frameLength)).map { samples[$0] * gain })
                defer { try? FileManager.default.removeItem(at: file) }
                let original = try Data(contentsOf: file)
                let result = try await SpeechPresenceDetector().detect(in: file)
                XCTAssertNotEqual(result, .noSpeech, "Short \(name), gain \(gain), must remain available to ASR")
                XCTAssertEqual(try Data(contentsOf: file), original)
            }
        }
    }

    func testEmptyButValidMonoRecordingHasNoSpeech() async throws {
        let file = try write([])
        defer { try? FileManager.default.removeItem(at: file) }
        let result = try await SpeechPresenceDetector().detect(in: file)
        XCTAssertEqual(result, .noSpeech)
    }

    func testTemporaryAnalysisCopiesAreRemovedAndFailuresKeepTheAudio() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quibble-analysis-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try write(Array(repeating: 0, count: 1_600))
        defer { try? FileManager.default.removeItem(at: original) }
        let originalBytes = try Data(contentsOf: original)
        let detector = SpeechPresenceDetector(temporaryDirectory: directory)
        let result = try await detector.detect(in: original)
        XCTAssertEqual(result, .noSpeech)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await detector.detect(in: original)
        }
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled analysis must throw")
        } catch is CancellationError {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)

        // If a private analysis copy cannot be created, preserve the input for ASR.
        let unavailableDirectory = directory.appendingPathComponent("missing")
        let failedResult = try await SpeechPresenceDetector(temporaryDirectory: unavailableDirectory).detect(in: original)
        XCTAssertEqual(failedResult, .uncertain)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    func testBundledStartCuesDoNotCountAsSpeech() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["soft-start", "start"] {
            let source = try AVAudioFile(forReading: root.appendingPathComponent("App/Resources/\(name).wav"))
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(source.length)))
            try source.read(into: buffer)
            let channel = try XCTUnwrap(buffer.floatChannelData?[0])
            var samples = Array(repeating: Float.zero, count: Int(source.processingFormat.sampleRate * 1.5))
            for index in 0..<Int(buffer.frameLength) { samples[index] = channel[index] * 0.4 }
            let file = try write(samples, rate: source.processingFormat.sampleRate)
            defer { try? FileManager.default.removeItem(at: file) }
            let result = try await SpeechPresenceDetector().detect(in: file)
            XCTAssertEqual(result, .noSpeech, "The shipped \(name) cue alone must not enter ASR")
        }
    }

    func testSilenceAndSteadyBackgroundNoiseDoNotEnterASR() async throws {
        let detector = SpeechPresenceDetector()
        let silence = try write(Array(repeating: 0, count: 32_000))
        defer { try? FileManager.default.removeItem(at: silence) }
        let silentResult = try await detector.detect(in: silence)
        XCTAssertEqual(silentResult, .noSpeech)

        var seed: UInt64 = 17
        let noise: [Float] = (0..<32_000).map { _ in
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return (Float(seed >> 40) / Float(1 << 24) - 0.5) * 0.012
        }
        let background = try write(noise)
        defer { try? FileManager.default.removeItem(at: background) }
        let noiseResult = try await detector.detect(in: background)
        XCTAssertEqual(noiseResult, .noSpeech)
    }

    func testSpeechAndQuietSpeechAreKept() async throws {
        // Fixture generated with macOS `say`: "Hello. This is a dictation check."
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "speech-presence", withExtension: "aiff"))
        let detector = SpeechPresenceDetector()
        let spoken = try await detector.detect(in: fixture)
        XCTAssertEqual(spoken, .speech)
        let file = try AVAudioFile(forReading: fixture)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let quiet = try write((0..<Int(buffer.frameLength)).map { channel[$0] * 0.02 }, rate: file.processingFormat.sampleRate)
        defer { try? FileManager.default.removeItem(at: quiet) }
        let quietResult = try await detector.detect(in: quiet)
        XCTAssertNotEqual(quietResult, .noSpeech, "A quiet voice must not be discarded by the preflight")
    }

    func testUnreadableAudioDefersToExistingErrorHandling() async throws {
        let result = try await SpeechPresenceDetector().detect(in: URL(fileURLWithPath: "/nonexistent/quibble-test.wav"))
        XCTAssertEqual(result, .uncertain)
    }

    func testSpeechOnlyOnSecondChannelIsNotDiscarded() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "speech-presence", withExtension: "aiff"))
        let source = try AVAudioFile(forReading: fixture)
        let mono = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: AVAudioFrameCount(source.length)))
        try source.read(into: mono)
        let speech = try XCTUnwrap(mono.floatChannelData?[0])
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: source.processingFormat.sampleRate, channels: 2))
        let stereo = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: mono.frameLength))
        stereo.frameLength = mono.frameLength
        for index in 0..<Int(mono.frameLength) {
            stereo.floatChannelData![0][index] = 0
            stereo.floatChannelData![1][index] = speech[index]
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quibble-stereo-presence-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            try file.write(from: stereo)
        }
        let result = try await SpeechPresenceDetector().detect(in: url)
        XCTAssertNotEqual(result, .noSpeech, "A silent first channel must not hide a speaker on another channel")
    }

    private func write(_ samples: [Float], rate: Double = 16_000) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quibble-presence-test-\(UUID()).wav")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, samples.count))))
        buffer.frameLength = AVAudioFrameCount(samples.count)
        if !samples.isEmpty {
            samples.withUnsafeBufferPointer { source in buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count) }
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }
}
