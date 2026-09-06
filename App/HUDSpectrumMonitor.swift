import Foundation
import QuibbleCore

/// Optional spectrum analysis of the same PCM written to the transcription WAV.
/// Owns no microphone client. Every mutable field is protected by the lock.
final class HUDSpectrumMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    private var analyzer: HUDSpectrumAnalyzer
    private var ring = Array(repeating: Float.zero, count: HUDSpectrumAnalyzer.frameCount)
    private var frame = Array(repeating: Float.zero, count: HUDSpectrumAnalyzer.frameCount)
    private var writeIndex = 0
    private var filled = 0
    private var nextAnalysisAt = 0.0
    private var updatedAt = 0.0
    private var amplitudes: [Double]?

    init?(sampleRate: Double) {
        guard let analyzer = HUDSpectrumAnalyzer(sampleRate: sampleRate, columnCount: 64) else { return nil }
        self.analyzer = analyzer
    }
    func setEnabled(_ value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard enabled != value else { return }
        enabled = value
        filled = 0; writeIndex = 0; updatedAt = 0; nextAnalysisAt = 0; amplitudes = nil
    }
    /// The audio callback never waits for visualization and never queues a PCM copy.
    func consume(_ samples: UnsafeBufferPointer<Int16>) {
        guard lock.try() else { return }
        defer { lock.unlock() }
        guard enabled, !samples.isEmpty else { return }
        let capacity = ring.count
        for index in max(0, samples.count - capacity)..<samples.count {
            ring[writeIndex] = Float(samples[index]) / 32_768
            writeIndex = (writeIndex + 1) % capacity
        }
        filled = min(capacity, filled + samples.count)
        let now = ProcessInfo.processInfo.systemUptime
        guard filled == capacity, now >= nextAnalysisAt else { return }
        nextAnalysisAt = now + 0.05
        for index in frame.indices { frame[index] = ring[(writeIndex + index) % capacity] }
        amplitudes = analyzer.analyze(samples: frame)
        updatedAt = now
    }
    /// Missing or stale data uses the HUD's existing loudness fallback.
    var latestAmplitudes: [Double]? {
        lock.lock()
        defer { lock.unlock() }
        guard enabled, ProcessInfo.processInfo.systemUptime - updatedAt <= 0.2 else { return nil }
        return amplitudes
    }
}
