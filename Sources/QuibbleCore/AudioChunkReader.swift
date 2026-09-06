import AVFoundation
import Foundation

/// Sequential decoding keeps memory independent of the recording's total length.
/// Windows cover every sample once; a quiet boundary is preferred near each window's end.
public final class AudioChunkReader {
    public struct Chunk: Sendable {
        public let start: Double
        public let samples: [Float]
        public var duration: Double { Double(samples.count) / 16_000 }
    }
    public enum ReadError: LocalizedError {
        case unsupportedAudio, conversionFailed
        public var errorDescription: String? {
            switch self {
            case .unsupportedAudio: "This audio file could not be decoded."
            case .conversionFailed: "The audio could not be converted for transcription."
            }
        }
    }
    public let duration: Double
    private let source: InputSource
    private let converter: AVAudioConverter
    private let output: AVAudioPCMBuffer
    private let maximumSamples: Int
    private var pending: [Float] = []
    private var ended = false
    private var emittedSamples = 0

    public init(file: URL, maximumSeconds: Double = 60) throws {
        guard maximumSeconds.isFinite, (1...60).contains(maximumSeconds) else { throw ReadError.unsupportedAudio }
        let input = try AVAudioFile(forReading: file, commonFormat: .pcmFormatFloat32, interleaved: false)
        let rate = input.processingFormat.sampleRate
        guard rate.isFinite, rate > 0, input.length > 0,
              input.processingFormat.channelCount > 0, input.processingFormat.channelCount <= 64,
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input.processingFormat, to: format),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000) else { throw ReadError.unsupportedAudio }
        duration = Double(input.length) / rate
        guard duration.isFinite, duration > 0 else { throw ReadError.unsupportedAudio }
        source = try InputSource(file: input)
        // A mono transcription stream must include speakers on every input channel.
        converter.downmix = true
        self.converter = converter
        self.output = output
        maximumSamples = Int(maximumSeconds * 16_000)
        pending.reserveCapacity(maximumSamples + 16_000)
    }

    public func next() throws -> Chunk? {
        try Task.checkCancellation()
        var emptyReads = 0
        while pending.count < maximumSamples && !ended {
            try Task.checkCancellation()
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { [source] packets, state in
                source.read(packets: packets, state: state)
            }
            if let error = source.error ?? error { throw error }
            if status == .error { throw ReadError.conversionFailed }
            if status == .endOfStream { ended = true }
            let count = Int(output.frameLength)
            if count > 0, let samples = output.floatChannelData?[0] {
                let values = UnsafeBufferPointer(start: samples, count: count)
                guard values.allSatisfy(\.isFinite) else { throw ReadError.conversionFailed }
                pending.append(contentsOf: values)
                emptyReads = 0
            } else {
                emptyReads += 1
                guard ended || emptyReads < 8 else { throw ReadError.conversionFailed }
            }
        }
        guard !pending.isEmpty else { return nil }
        let available = min(pending.count, maximumSamples)
        let remainingSeconds = duration - Double(emittedSamples) / 16_000
        let isFinalWindow = remainingSeconds <= Double(maximumSamples) / 16_000 + 1.0 / 16_000
        let count = (ended && pending.count <= maximumSamples) || isFinalWindow ? available : quietBoundary(through: available)
        let chunk = Chunk(start: Double(emittedSamples) / 16_000, samples: Array(pending.prefix(count)))
        pending.removeFirst(count)
        emittedSamples += count
        return chunk
    }

    private func quietBoundary(through end: Int) -> Int {
        // A minimum 160ms pause avoids treating the gaps inside a syllable as boundaries.
        let frame = 320, quietFrames = 8
        let start = max(frame, end - min(12 * 16_000, end / 4))
        var run = 0, best: Int?
        for offset in stride(from: start, through: end - frame, by: frame) {
            var energy: Float = 0
            for sample in pending[offset..<(offset + frame)] { energy += sample * sample }
            if energy / Float(frame) < 0.000_063 {
                run += 1
                if run >= quietFrames { best = offset + frame - quietFrames * frame / 2 }
            } else { run = 0 }
        }
        return best ?? end
    }

    // AVAudioConverter invokes this source synchronously for one reader; it never escapes.
    private final class InputSource: @unchecked Sendable {
        let file: AVAudioFile
        let buffer: AVAudioPCMBuffer
        var error: Error?
        init(file: AVAudioFile) throws {
            self.file = file
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { throw ReadError.unsupportedAudio }
            self.buffer = buffer
        }
        func read(packets: AVAudioPacketCount, state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            guard error == nil, file.framePosition < file.length else { state.pointee = .endOfStream; return nil }
            do {
                try Task.checkCancellation()
                try file.read(into: buffer, frameCount: min(4096, max(1, packets)))
                guard buffer.frameLength > 0 else { state.pointee = .endOfStream; return nil }
                state.pointee = .haveData
                return buffer
            } catch {
                self.error = error
                state.pointee = .endOfStream
                return nil
            }
        }
    }
}
