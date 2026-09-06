import AVFoundation
import XCTest
@testable import QuibbleCore

final class AudioChunkReaderTests: XCTestCase {
    private func audio(seconds: Double, rate: Double = 16_000, channels: AVAudioChannelCount = 1,
        channelValue: ((Int, Int) -> Float)? = nil,
        value: (Int) -> Float = { _ in 0.25 }) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("quibble-chunk-test-\(UUID()).wav")
        let format = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false))
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        let frames = Int(seconds * rate)
        for start in stride(from: 0, to: frames, by: 4096) {
            let count = min(4096, frames - start)
            buffer.frameLength = AVAudioFrameCount(count)
            for channel in 0..<Int(channels) {
                for index in 0..<count {
                    buffer.floatChannelData![channel][index] = channelValue?(start + index, channel) ?? value(start + index)
                }
            }
            try file.write(from: buffer)
        }
        return url
    }

    func testLongRecordingUsesBoundedWindowsAndPreservesEverySample() throws {
        let file = try audio(seconds: 125.25)
        defer { try? FileManager.default.removeItem(at: file) }
        let reader = try AudioChunkReader(file: file)
        var starts: [Double] = [], count = 0
        while let chunk = try reader.next() {
            starts.append(chunk.start)
            XCTAssertLessThanOrEqual(chunk.samples.count, 960_000)
            XCTAssertTrue(chunk.samples.allSatisfy { abs($0 - 0.25) < 0.0001 })
            count += chunk.samples.count
        }
        XCTAssertEqual(starts, [0, 60, 120])
        XCTAssertEqual(count, 2_004_000)
        XCTAssertEqual(reader.duration, 125.25)
    }

    func testAQuietOneMinuteFileRemainsOneSection() throws {
        let file = try audio(seconds: 60, value: { _ in 0 })
        defer { try? FileManager.default.removeItem(at: file) }
        let reader = try AudioChunkReader(file: file)
        XCTAssertEqual(try reader.next()?.samples.count, 960_000)
        XCTAssertNil(try reader.next())
    }

    func testQuietBoundaryMovesTheSplitWithoutDroppingOrRepeatingAudio() throws {
        let silence = (54 * 16_000)..<(55 * 16_000)
        let file = try audio(seconds: 62.5, value: { silence.contains($0) ? 0 : 0.25 })
        defer { try? FileManager.default.removeItem(at: file) }
        let reader = try AudioChunkReader(file: file)
        let first = try XCTUnwrap(reader.next())
        XCTAssertGreaterThan(first.duration, 54)
        XCTAssertLessThan(first.duration, 55)
        let second = try XCTUnwrap(reader.next())
        XCTAssertEqual(second.start, first.duration)
        let all = first.samples + second.samples
        XCTAssertEqual(all.count, 1_000_000)
        XCTAssertEqual(all.filter { $0 == 0 }.count, 16_000)
        XCTAssertNil(try reader.next())
    }

    func testStereoImportIsResampledToFiniteMonoWindows() throws {
        let file = try audio(seconds: 3.2, rate: 48_000, channels: 2)
        defer { try? FileManager.default.removeItem(at: file) }
        let reader = try AudioChunkReader(file: file, maximumSeconds: 2)
        var total = 0
        while let chunk = try reader.next() {
            XCTAssertLessThanOrEqual(chunk.samples.count, 32_000)
            XCTAssertTrue(chunk.samples.allSatisfy(\.isFinite))
            XCTAssertGreaterThan(chunk.samples.map(abs).max() ?? 0, 0.1)
            total += chunk.samples.count
        }
        XCTAssertEqual(total, 51_200, accuracy: 64)
    }

    func testSpeakerPresentOnlyInTheRightChannelIsNotDiscarded() throws {
        let file = try audio(seconds: 1, rate: 48_000, channels: 2, channelValue: { _, channel in channel == 1 ? 0.25 : 0 })
        defer { try? FileManager.default.removeItem(at: file) }
        let reader = try AudioChunkReader(file: file)
        let chunk = try XCTUnwrap(reader.next())
        let energy = chunk.samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(chunk.samples.count)
        XCTAssertGreaterThan(sqrt(energy), 0.05)
    }

    func testCancellationStopsReadingBeforeMoreAudioIsDecoded() async throws {
        let file = try audio(seconds: 61)
        defer { try? FileManager.default.removeItem(at: file) }
        let task = Task {
            let reader = try AudioChunkReader(file: file)
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try reader.next(); return false }
            catch is CancellationError { return true }
        }
        let cancelled = try await task.value
        XCTAssertTrue(cancelled)
    }
}
