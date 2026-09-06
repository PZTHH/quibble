import Foundation

/// A gated current sound display. A live spectrum supplies its shape when available;
/// otherwise every column reports the same loudness, without invented detail.
/// Only its short attack/release envelope carries between microphone samples.
public struct HUDSignalMeter: Sendable {
    public static let columnCount = 64
    public private(set) var amplitudes = Array(repeating: 0.0, count: columnCount)
    public private(set) var isActive = false

    private var quietDuration = 0.0

    public init() {}

    public mutating func reset() {
        amplitudes = Array(repeating: 0, count: Self.columnCount)
        isActive = false
        quietDuration = 0
    }

    @discardableResult
    public mutating func update(averagePower: Double, peakPower: Double, deltaTime: Double, spectrum: [Double]? = nil) -> [Double] {
        let average = Self.validPower(averagePower)
        let peak = max(average, Self.validPower(peakPower))
        let interval = deltaTime.isFinite && deltaTime > 0 ? min(deltaTime, 0.25) : 0.05

        // Hysteresis keeps syllable tails open without letting ambient noise start motion.
        if isActive {
            isActive = average > -45 || peak > -36
        } else {
            isActive = average >= -42 || peak >= -30
        }
        quietDuration = isActive ? 0 : quietDuration + interval

        // A finite settling time prevents imperceptible values from scheduling idle UI work.
        if quietDuration >= 0.35 {
            if amplitudes.contains(where: { $0 != 0 }) {
                amplitudes = Array(repeating: 0, count: Self.columnCount)
            }
            return amplitudes
        }

        let gain = max(Self.unit((average + 46) / 34), 0.35 * Self.unit((peak + 36) / 30))
        let attackFraction = 1 - exp(-interval / 0.035)
        let releaseFraction = 1 - exp(-interval / 0.10)
        let liveSpectrum = spectrum?.count == Self.columnCount ? spectrum : nil
        let quietGain = Self.unit((average + 46) / 12)
        for index in amplitudes.indices {
            let band = liveSpectrum.map { $0[index].isFinite ? Self.unit($0[index]) : 0 }
            let current = band.map { $0 * quietGain } ?? (gain * quietGain)
            let target = isActive ? current : 0
            let fraction = target > amplitudes[index] ? attackFraction : releaseFraction
            let next = amplitudes[index] + fraction * (target - amplitudes[index])
            amplitudes[index] = next < 0.001 ? 0 : Self.unit(next)
        }
        return amplitudes
    }

    private static func validPower(_ value: Double) -> Double {
        value.isFinite ? min(0, max(-160, value)) : -160
    }

    private static func unit(_ value: Double) -> Double { min(1, max(0, value)) }
}
