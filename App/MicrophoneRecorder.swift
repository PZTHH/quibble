import AudioToolbox
import Foundation

/// One per-app input client supplies the WAV, loudness meters, and optional HUD spectrum.
@MainActor
final class MicrophoneRecorder {
    enum RecordingError: LocalizedError, Sendable {
        case queue(String, OSStatus), file(OSStatus), interrupted, alreadyStopped
        var errorDescription: String? {
            switch self {
            case .queue(let action, _): "Could not \(action) the selected microphone. Try another input."
            case .file: "The microphone recording could not be written or finalized."
            case .interrupted: "The microphone stopped unexpectedly. Reconnect it or choose another input."
            case .alreadyStopped: "This recording has already stopped. Start a new recording."
            }
        }
    }
    let device: AudioInputDevices.Device
    let url: URL
    private let capture: QueueMicrophoneCapture
    var spectrumEnabled = true { didSet { capture.state.spectrum?.setEnabled(spectrumEnabled) } }
    var isRecording: Bool { capture.state.snapshot().recording }
    var currentTime: TimeInterval { Double(capture.state.snapshot().frames) / 16_000 }
    var averagePower: Float { capture.state.snapshot().average }
    var peakPower: Float { capture.state.snapshot().peak }
    var latestAmplitudes: [Double]? { capture.state.spectrum?.latestAmplitudes }
    var error: RecordingError? { capture.state.snapshot().error }
    init(url: URL, device: AudioInputDevices.Device) throws {
        self.url = url; self.device = device
        capture = try QueueMicrophoneCapture(url: url, device: device)
    }
    func record() throws { try capture.start() }
    /// Returns after pending input is drained, the queue is disposed, and the WAV is closed.
    func stop() { capture.stop() }
}

/// Non-actor owner: synchronous disposal also runs safely during wrapper deinitialization.
private final class QueueMicrophoneCapture {
    let state: MicrophonePCMState
    private var queue: AudioQueueRef?
    private var callbackContext: UnsafeMutableRawPointer?
    private var started = false
    init(url: URL, device: AudioInputDevices.Device) throws {
        state = try MicrophonePCMState(url: url)
        var format = Self.format
        var created: AudioQueueRef?
        let context = Unmanaged.passRetained(state).toOpaque()
        callbackContext = context
        let status = AudioQueueNewInput(&format, Self.inputCallback, context, nil, nil, 0, &created)
        guard status == noErr, let created else {
            Unmanaged<MicrophonePCMState>.fromOpaque(context).release()
            callbackContext = nil
            state.finish()
            throw MicrophoneRecorder.RecordingError.queue("open", status)
        }
        queue = created
        do {
            try AudioInputDevices.configure(queue: created, for: device)
            let observing = AudioQueueAddPropertyListener(created, kAudioQueueProperty_IsRunning, Self.runningCallback, context)
            guard observing == noErr else { throw MicrophoneRecorder.RecordingError.queue("monitor", observing) }
            // Three 50 ms buffers keep conversion/file I/O bounded without a second capture engine.
            for _ in 0..<3 {
                var buffer: AudioQueueBufferRef?
                let allocated = AudioQueueAllocateBuffer(created, 1_600, &buffer)
                guard allocated == noErr, let buffer else { throw MicrophoneRecorder.RecordingError.queue("prepare", allocated) }
                let enqueued = AudioQueueEnqueueBuffer(created, buffer, 0, nil)
                guard enqueued == noErr else { throw MicrophoneRecorder.RecordingError.queue("prepare", enqueued) }
            }
        } catch { stop(); throw error }
    }
    static var format: AudioStreamBasicDescription {
        AudioStreamBasicDescription(mSampleRate: 16_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
            mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    }
    func start() throws {
        guard let queue else { throw MicrophoneRecorder.RecordingError.alreadyStopped }
        guard !started else { return }
        state.beginRecording()
        let status = AudioQueueStart(queue, nil)
        guard status == noErr else {
            state.fail(.queue("start", status)); stop()
            throw MicrophoneRecorder.RecordingError.queue("start", status)
        }
        started = true
    }
    func stop() {
        guard let queue else { state.finish(); return }
        // Stop recycling but write any final partial input flushed by Stop/Dispose.
        state.beginStopping()
        let stopped = AudioQueueStop(queue, true)
        if stopped != noErr { state.fail(.queue("stop", stopped)) }
        let disposed = AudioQueueDispose(queue, true)
        if disposed != noErr { state.fail(.queue("close", disposed)) }
        if disposed == noErr {
            self.queue = nil
            if let callbackContext { Unmanaged<MicrophonePCMState>.fromOpaque(callbackContext).release() }
            callbackContext = nil
        }
        // If native disposal fails, keep the callback context alive; a late callback must never
        // access released Swift memory. The failed state accepts no further data or recycling.
        state.finish()
    }
    // C callbacks are declared outside MainActor. They touch only locked PCM state.
    private static let inputCallback: AudioQueueInputCallback = { context, queue, buffer, _, _, _ in
        guard let context else { return }
        Unmanaged<MicrophonePCMState>.fromOpaque(context).takeUnretainedValue().consume(buffer, queue: queue)
    }
    private static let runningCallback: AudioQueuePropertyListenerProc = { context, queue, _ in
        guard let context else { return }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size) == noErr else { return }
        Unmanaged<MicrophonePCMState>.fromOpaque(context).takeUnretainedValue().runningChanged(running != 0)
    }
    deinit { stop() }
}

/// File access, frame count, and meters share one lock; optional visualization may skip a frame.
private final class MicrophonePCMState: @unchecked Sendable {
    struct Snapshot {
        let recording: Bool
        let frames: Int64
        let average: Float
        let peak: Float
        let error: MicrophoneRecorder.RecordingError?
    }
    let spectrum = HUDSpectrumMonitor(sampleRate: 16_000)
    private let lock = NSLock()
    private var file: AudioFileID?
    private var accepting = false
    private var recycling = false
    private var stopping = false
    private var hasRun = false
    private var recording = false
    private var frames: Int64 = 0
    private var average: Float = -160
    private var peak: Float = -160
    private var failure: MicrophoneRecorder.RecordingError?
    init(url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
        var format = QueueMicrophoneCapture.format
        let status = AudioFileCreateWithURL(url as CFURL, kAudioFileWAVEType, &format, [], &file)
        guard status == noErr, file != nil else { throw MicrophoneRecorder.RecordingError.file(status) }
    }
    func beginRecording() {
        lock.lock(); defer { lock.unlock() }
        accepting = true; recycling = true; recording = true
    }
    func beginStopping() {
        lock.lock(); defer { lock.unlock() }
        recycling = false; stopping = true; recording = false
    }
    func runningChanged(_ running: Bool) {
        lock.lock(); defer { lock.unlock() }
        if running { hasRun = true }
        else if hasRun && !stopping {
            failure = failure ?? .interrupted
            recording = false; recycling = false
        }
    }
    func consume(_ buffer: AudioQueueBufferRef, queue: AudioQueueRef) {
        lock.lock(); defer { lock.unlock() }
        guard accepting, failure == nil, let file else { return }
        let bytes = min(buffer.pointee.mAudioDataByteSize, buffer.pointee.mAudioDataBytesCapacity)
        let count = bytes / 2
        if count > 0 {
            let samples = UnsafeBufferPointer(start: buffer.pointee.mAudioData.assumingMemoryBound(to: Int16.self), count: Int(count))
            var written = count
            let result = AudioFileWritePackets(file, false, count * 2, nil, frames, &written, buffer.pointee.mAudioData)
            guard result == noErr, written == count else {
                failure = .file(result == noErr ? kAudioFileUnspecifiedError : result)
                recycling = false; recording = false
                return
            }
            frames += Int64(written)
            var sum = 0.0, maximum = 0.0
            for sample in samples {
                let value = Double(sample) / 32_768
                sum += value * value
                maximum = max(maximum, abs(value))
            }
            average = Float(max(-160, 10 * log10(max(1e-16, sum / Double(count)))))
            peak = Float(max(-160, 20 * log10(max(1e-8, maximum))))
            spectrum?.consume(samples)
        }
        if recycling {
            let result = AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            if result != noErr {
                failure = .queue("continue recording from", result)
                recycling = false; recording = false
            }
        }
    }
    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(recording: recording, frames: frames, average: average, peak: peak, error: failure)
    }
    func fail(_ error: MicrophoneRecorder.RecordingError) {
        lock.lock(); defer { lock.unlock() }
        failure = failure ?? error
        recycling = false; recording = false
    }
    /// Called after synchronous queue disposal: no callback can access a closed file.
    func finish() {
        lock.lock(); defer { lock.unlock() }
        accepting = false; recycling = false; recording = false
        if let file {
            let result = AudioFileClose(file)
            if result != noErr { failure = failure ?? .file(result) }
            self.file = nil
        }
        spectrum?.setEnabled(false)
    }
    deinit { finish() }
}
