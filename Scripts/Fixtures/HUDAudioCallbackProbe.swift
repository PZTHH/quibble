// Appended to the current microphone/spectrum sources by check-hud-audio-callback.py.
// Crosses the actual AudioQueueInputCallback boundary on a background executor.
import AVFoundation

extension QueueMicrophoneCapture {
    fileprivate static func callbackForRegression() -> AudioQueueInputCallback { inputCallback }
}

@main
struct BackgroundAudioRegression {
    @MainActor
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("quibble-pcm-probe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("synthetic.wav")
        let state = try MicrophonePCMState(url: url)
        // Callback is obtained on MainActor and invoked off it. No audio queue or microphone is opened.
        let callback = QueueMicrophoneCapture.callbackForRegression()
        await Task.detached {
            dispatchPrecondition(condition: .notOnQueue(.main))
            state.beginRecording()
            // Exercise the final-buffer path, which writes PCM without recycling a native buffer.
            state.beginStopping()
            let count = HUDSpectrumAnalyzer.frameCount
            let samples = UnsafeMutablePointer<Int16>.allocate(capacity: count)
            defer { samples.deallocate() }
            for index in 0..<count {
                samples[index] = Int16((0.2 * sin(2 * Double.pi * 1_000 * Double(index) / 16_000) * 32_768).rounded())
            }
            var buffer = AudioQueueBuffer(mAudioDataBytesCapacity: UInt32(count * 2), mAudioData: samples,
                mAudioDataByteSize: UInt32(count * 2), mUserData: nil,
                mPacketDescriptionCapacity: 0, mPacketDescriptions: nil, mPacketDescriptionCount: 0)
            var timestamp = AudioTimeStamp()
            let context = Unmanaged.passUnretained(state).toOpaque()
            // The drain path never calls an AudioQueue function with this placeholder.
            let unusedQueue = OpaquePointer(bitPattern: 1)!
            callback(context, unusedQueue, &buffer, &timestamp, UInt32(count), nil)
            let reading = state.snapshot()
            precondition(reading.frames == count && reading.error == nil)
            precondition(abs(reading.average - (-16.99)) < 0.05 && abs(reading.peak - (-13.98)) < 0.05)
            guard let bands = state.spectrum?.latestAmplitudes, bands.count == 64,
                  bands.allSatisfy({ $0.isFinite && (0...1).contains($0) }),
                  bands.contains(where: { $0 > 0.1 }) else { fatalError("No valid spectrum from recorded PCM") }
            state.spectrum?.setEnabled(false)
            buffer.mAudioDataByteSize = 514
            callback(context, unusedQueue, &buffer, &timestamp, 257, nil)
            precondition(state.snapshot().frames == count + 257, "Final partial buffer was lost")
            precondition(state.spectrum?.latestAmplitudes == nil, "Hidden HUD should not analyze audio")
            state.finish()
            callback(context, unusedQueue, &buffer, &timestamp, 257, nil)
            precondition(state.snapshot().frames == count + 257, "Late callback wrote after finalization")
            precondition(state.snapshot().error == nil)
        }.value
        let audio = try AVAudioFile(forReading: url)
        precondition(audio.fileFormat.sampleRate == 16_000 && audio.fileFormat.channelCount == 1)
        precondition(audio.fileFormat.streamDescription.pointee.mBitsPerChannel == 16)
        precondition(audio.length == HUDSpectrumAnalyzer.frameCount + 257, "WAV header was not finalized")
        let interrupted = try MicrophonePCMState(url: directory.appendingPathComponent("interrupted.wav"))
        interrupted.beginRecording(); interrupted.runningChanged(true); interrupted.runningChanged(false)
        interrupted.finish()
        guard case .interrupted? = interrupted.snapshot().error else { fatalError("Interruption error was lost on stop") }
        print("Audio callback probe passed: background C callback, 64 shared-PCM bands, meters, partial-buffer drain, finalized 16 kHz mono WAV, late callback rejection, and retained interruption error.")
    }
}
