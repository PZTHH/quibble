import XCTest
@testable import QuibbleCore

final class HUDSignalMeterTests: XCTestCase {
    func testQuietAmbientNoiseStaysExactlyIdle() {
        var meter = HUDSignalMeter()
        for index in 0..<240 {
            let average = [-55.0, -51, -46, -50, -48, -54][index % 6]
            let output = meter.update(averagePower: average, peakPower: average + 4, deltaTime: 0.05)
            XCTAssertTrue(output.allSatisfy { $0 == 0 })
            XCTAssertFalse(meter.isActive)
        }
    }

    func testSpeechAttacksPromptlyAndSettlesWithoutIdleChatter() {
        var meter = HUDSignalMeter()
        let attack = meter.update(averagePower: -22, peakPower: -12, deltaTime: 0.05)
        XCTAssertGreaterThan(attack.max() ?? 0, 0.5)
        XCTAssertTrue(meter.isActive)
        let firstRelease = meter.update(averagePower: -55, peakPower: -48, deltaTime: 0.05)
        XCTAssertGreaterThan(firstRelease.max() ?? 0, 0)
        XCTAssertLessThan(firstRelease.max() ?? 0, attack.max() ?? 0)
        var previous = firstRelease
        for _ in 0..<6 {
            let output = meter.update(averagePower: -49, peakPower: -43, deltaTime: 0.05)
            XCTAssertTrue(zip(output, previous).allSatisfy { $0 <= $1 })
            previous = output
        }
        XCTAssertTrue(previous.allSatisfy { $0 == 0 })
        XCTAssertFalse(meter.isActive)
    }

    func testHysteresisKeepsQuietSyllableTailsOpenButDoesNotStartFromNoise() {
        var meter = HUDSignalMeter()
        meter.update(averagePower: -44, peakPower: -39, deltaTime: 0.05)
        XCTAssertFalse(meter.isActive)
        meter.update(averagePower: -36, peakPower: -32, deltaTime: 0.05)
        XCTAssertTrue(meter.isActive)
        meter.update(averagePower: -44, peakPower: -39, deltaTime: 0.05)
        XCTAssertTrue(meter.isActive)
        meter.update(averagePower: -46, peakPower: -40, deltaTime: 0.05)
        XCTAssertFalse(meter.isActive)
    }

    func testMissingSpectrumUsesUniformLoudnessInsteadOfInventedDetail() {
        var meter = HUDSignalMeter()
        let output = meter.update(averagePower: -25, peakPower: -20, deltaTime: 0.05)
        XCTAssertEqual(output.count, 64)
        XCTAssertGreaterThan(output[0], 0)
        XCTAssertTrue(output.allSatisfy { $0 == output[0] })
    }

    func testCurrentSpectrumControlsShapeAndNoiseGateStillControlsSilence() {
        var low = HUDSignalMeter()
        var high = HUDSignalMeter()
        var lowSpectrum = Array(repeating: 0.0, count: 64)
        var highSpectrum = lowSpectrum
        lowSpectrum[3] = 0.8
        highSpectrum[53] = 0.8
        let lowOutput = low.update(averagePower: -22, peakPower: -18, deltaTime: 0.05, spectrum: lowSpectrum)
        let highOutput = high.update(averagePower: -22, peakPower: -18, deltaTime: 0.05, spectrum: highSpectrum)
        XCTAssertGreaterThan(lowOutput[3], 0.5)
        XCTAssertEqual(lowOutput[53], 0)
        XCTAssertEqual(highOutput[3], 0)
        XCTAssertGreaterThan(highOutput[53], 0.5)
        low.reset()
        XCTAssertTrue(low.update(averagePower: -50, peakPower: -44, deltaTime: 0.05, spectrum: lowSpectrum).allSatisfy { $0 == 0 })
    }

    func testQuietSpeechDoesNotMakeSensitiveColumnsJumpToFullHeight() {
        var meter = HUDSignalMeter()
        for _ in 0..<20 {
            meter.update(averagePower: -41, peakPower: -36, deltaTime: 0.05)
        }
        XCTAssertTrue(meter.isActive)
        XCTAssertGreaterThan(meter.amplitudes.max() ?? 0, 0)
        XCTAssertLessThan(meter.amplitudes.max() ?? 0, 0.1)
    }

    func testInvalidPowerAndTimeRemainFiniteAndBounded() {
        var meter = HUDSignalMeter()
        for value in [Double.nan, .infinity, -.infinity, -1000, 1000, -20] {
            for interval in [Double.nan, .infinity, -1, 0, 0.05, 1000] {
                let output = meter.update(averagePower: value, peakPower: value, deltaTime: interval)
                XCTAssertEqual(output.count, 64)
                XCTAssertTrue(output.allSatisfy { $0.isFinite && (0...1).contains($0) })
            }
        }
    }

    func testResetStartsTheNextRecordingAtSilence() {
        var meter = HUDSignalMeter()
        meter.update(averagePower: -6, peakPower: -1, deltaTime: 0.05)
        XCTAssertTrue(meter.amplitudes.contains { $0 > 0 })
        meter.reset()
        XCTAssertFalse(meter.isActive)
        XCTAssertTrue(meter.amplitudes.allSatisfy { $0 == 0 })
        XCTAssertTrue(meter.update(averagePower: -47, peakPower: -40, deltaTime: 0.05).allSatisfy { $0 == 0 })
    }
}
