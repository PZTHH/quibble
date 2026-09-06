import Accelerate
import Foundation

/// A small, stateless audio spectrum for the HUD. Call on a serial analysis queue
/// at most 20 times per second, using the latest complete mono PCM frame.
public struct HUDSpectrumAnalyzer {
    public static let frameCount = 4096
    public let frequencyRanges: [Range<Double>]

    private final class Plan {
        let setup: FFTSetup
        init?() {
            guard let setup = vDSP_create_fftsetup(12, FFTRadix(kFFTRadix2)) else { return nil }
            self.setup = setup
        }
        deinit { vDSP_destroy_fftsetup(setup) }
    }

    private let plan: Plan
    private let window: [Float]
    private let powerScale: Double
    private let binWidth: Double
    private var real = Array(repeating: Float(0), count: frameCount)
    private var imaginary = Array(repeating: Float(0), count: frameCount)

    public init?(sampleRate: Double, columnCount: Int = 64) {
        guard sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
              (1...128).contains(columnCount), let plan = Plan() else { return nil }
        self.plan = plan
        binWidth = sampleRate / Double(Self.frameCount)
        window = (0..<Self.frameCount).map {
            Float(0.5 - 0.5 * cos(2 * .pi * Double($0) / Double(Self.frameCount)))
        }
        let windowEnergy = window.reduce(0.0) { $0 + Double($1 * $1) }
        powerScale = 2 / (Double(Self.frameCount) * windowEnergy)

        let lower = 100.0
        let upper = min(8_000, sampleRate * 0.48)
        // Each range is at least one FFT bin wide. Adding a logarithmic term
        // then gives speech's lower frequencies more detail without duplicating bins.
        let linearSpan = binWidth * Double(columnCount)
        let curvedSpan = upper - lower - linearSpan
        guard curvedSpan >= 0 else { return nil }
        let ratio = upper / lower
        let edges = (0...columnCount).map { index in
            let position = Double(index) / Double(columnCount)
            return lower + linearSpan * position + curvedSpan * (pow(ratio, position) - 1) / (ratio - 1)
        }
        frequencyRanges = (0..<columnCount).map { edges[$0]..<edges[$0 + 1] }
    }

    /// Returns dB-scaled band power in 0...1, with -64 dBFS at zero and -8 dBFS at one.
    /// Incomplete frames remain idle; oversized inputs use only their latest frame.
    public mutating func analyze(samples: [Float]) -> [Double] {
        guard samples.count >= Self.frameCount else { return Array(repeating: 0, count: frequencyRanges.count) }
        let start = samples.count - Self.frameCount
        for index in 0..<Self.frameCount {
            let sample = samples[start + index]
            real[index] = (sample.isFinite ? min(1, max(-1, sample)) : 0) * window[index]
            imaginary[index] = 0
        }
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                vDSP_fft_zip(plan.setup, &split, 1, 12, FFTDirection(FFT_FORWARD))
            }
        }

        return frequencyRanges.map { range in
            let lowerBin = max(1, Int(floor(range.lowerBound / binWidth - 0.5)))
            let upperBin = min(Self.frameCount / 2 - 1, Int(ceil(range.upperBound / binWidth + 0.5)))
            var power = 0.0
            for bin in lowerBin...upperBin {
                let binLower = (Double(bin) - 0.5) * binWidth
                let binUpper = binLower + binWidth
                let overlap = max(0, min(range.upperBound, binUpper) - max(range.lowerBound, binLower)) / binWidth
                power += (Double(real[bin]) * Double(real[bin]) + Double(imaginary[bin]) * Double(imaginary[bin])) * overlap
            }
            let normalizedPower = power * powerScale
            guard normalizedPower > 0, normalizedPower.isFinite else { return 0 }
            return min(1, max(0, (10 * log10(normalizedPower) + 64) / 56))
        }
    }
}
