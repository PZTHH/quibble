import XCTest
@testable import QuibbleCore

final class HUDSpectrumAnalyzerTests: XCTestCase {
    private let sampleRate = 48_000.0

    private func tone(_ frequency: Double, amplitude: Double = 0.1, rate: Double = 48_000) -> [Float] {
        (0..<HUDSpectrumAnalyzer.frameCount).map {
            Float(amplitude * sin(2 * .pi * frequency * Double($0) / rate))
        }
    }

    private func peakIndex(_ values: [Double]) -> Int {
        values.indices.max { values[$0] < values[$1] }!
    }

    func testSilenceAndIncompleteFramesRemainExactlyIdle() throws {
        var analyzer = try XCTUnwrap(HUDSpectrumAnalyzer(sampleRate: sampleRate))
        XCTAssertEqual(analyzer.analyze(samples: []), Array(repeating: 0, count: 64))
        XCTAssertTrue(analyzer.analyze(samples: Array(repeating: 0, count: 4096)).allSatisfy { $0 == 0 })
        XCTAssertTrue(analyzer.analyze(samples: Array(repeating: 0.1, count: 2048)).allSatisfy { $0 == 0 })
    }

    func testDifferentCurrentFrequenciesMoveEnergyToTheirActualColumns() throws {
        var analyzer = try XCTUnwrap(HUDSpectrumAnalyzer(sampleRate: sampleRate))
        let low = analyzer.analyze(samples: tone(440))
        let high = analyzer.analyze(samples: tone(2_400))
        let lowExpected = try XCTUnwrap(analyzer.frequencyRanges.firstIndex { $0.contains(440) })
        let highExpected = try XCTUnwrap(analyzer.frequencyRanges.firstIndex { $0.contains(2_400) })
        XCTAssertLessThanOrEqual(abs(peakIndex(low) - lowExpected), 1)
        XCTAssertLessThanOrEqual(abs(peakIndex(high) - highExpected), 1)
        XCTAssertGreaterThan(highExpected - lowExpected, 15)
        XCTAssertGreaterThan(low[lowExpected], 0.5)
        XCTAssertLessThan(low[highExpected], 0.01)
        XCTAssertLessThan(high[lowExpected], 0.01)
    }

    func testLowFrequencyRangesAreDistinctAndAtLeastOneFFTBinWide() throws {
        let analyzer = try XCTUnwrap(HUDSpectrumAnalyzer(sampleRate: sampleRate))
        let binWidth = sampleRate / Double(HUDSpectrumAnalyzer.frameCount)
        XCTAssertEqual(analyzer.frequencyRanges.count, 64)
        for range in analyzer.frequencyRanges {
            XCTAssertGreaterThanOrEqual(range.upperBound - range.lowerBound, binWidth)
        }
        for pair in zip(analyzer.frequencyRanges, analyzer.frequencyRanges.dropFirst()) {
            XCTAssertEqual(pair.0.upperBound, pair.1.lowerBound)
        }
    }

    func testFrequencyMappingSupportsDifferentMicrophoneSampleRates() throws {
        for rate in [8_000.0, 16_000, 44_100, 96_000, 192_000] {
            var analyzer = try XCTUnwrap(HUDSpectrumAnalyzer(sampleRate: rate))
            let output = analyzer.analyze(samples: tone(1_000, rate: rate))
            let expected = try XCTUnwrap(analyzer.frequencyRanges.firstIndex { $0.contains(1_000) })
            XCTAssertLessThanOrEqual(abs(peakIndex(output) - expected), 1)
            XCTAssertGreaterThan(output.max() ?? 0, 0.5)
        }
    }

    func testAmplitudeChangesBandEnergyAndPreviousAudioDoesNotPersist() throws {
        var analyzer = try XCTUnwrap(HUDSpectrumAnalyzer(sampleRate: sampleRate))
        let quiet = analyzer.analyze(samples: tone(1_000, amplitude: 0.01))
        let loud = analyzer.analyze(samples: tone(1_000, amplitude: 0.1))
        XCTAssertGreaterThan((loud.max() ?? 0) - (quiet.max() ?? 0), 0.3)
        let latest = tone(2_400)
        let latestOnly = analyzer.analyze(samples: latest)
        XCTAssertEqual(analyzer.analyze(samples: tone(440) + latest), latestOnly)
        XCTAssertTrue(analyzer.analyze(samples: Array(repeating: 0, count: 4096)).allSatisfy { $0 == 0 })
    }

    func testInvalidInputsRemainBoundedAndConfigurationIsValidated() throws {
        XCTAssertNil(HUDSpectrumAnalyzer(sampleRate: .nan))
        XCTAssertNil(HUDSpectrumAnalyzer(sampleRate: 0))
        XCTAssertNil(HUDSpectrumAnalyzer(sampleRate: sampleRate, columnCount: 0))
        var analyzer = try XCTUnwrap(HUDSpectrumAnalyzer(sampleRate: sampleRate))
        for sample in [Float.nan, .infinity, -.infinity, 1_000] {
            let output = analyzer.analyze(samples: Array(repeating: sample, count: 4096))
            XCTAssertEqual(output.count, 64)
            XCTAssertTrue(output.allSatisfy { $0.isFinite && (0...1).contains($0) })
        }
    }
}
