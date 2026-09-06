import XCTest
@testable import QuibbleCore

final class DictationPaceTests: XCTestCase {
    func testLongDictationsContributeTheirMeasuredDuration() {
        let pace = DictationPace(records: [record("One two three four five six", seconds: 120)])
        XCTAssertEqual(pace.seconds, 120)
        XCTAssertEqual(pace.wordsPerMinute, 3)
    }
    private func record(_ raw: String, seconds: Double?) -> TranscriptRecord {
        TranscriptRecord(original: raw, text: "Cleanup can add many words that were never spoken aloud.", application: "Notes",
            mode: "basic", engine: "test", delivery: "Inserted", audioSeconds: seconds)
    }

    func testSpeakingPaceWeightsDurationAndIgnoresCleanupAndUnmeasuredAudio() {
        let pace = DictationPace(records: [
            record("One, two three four five six seven eight nine ten.", seconds: 5),
            record("Eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen twenty.", seconds: 15),
            record("Imported audio and older records must not increase measured words.", seconds: nil)
        ])
        XCTAssertEqual(pace.words, 20)
        XCTAssertEqual(pace.seconds, 20)
        XCTAssertEqual(pace.wordsPerMinute, 60)
    }

    func testSpeakingPaceWaitsForEnoughAudioAndIgnoresInvalidOrEmptySamples() {
        XCTAssertNil(DictationPace(records: [record("One two three", seconds: 9)]).wordsPerMinute)
        let pace = DictationPace(records: [record("One two three", seconds: 10),
            record("!!!", seconds: 30), record("Invalid", seconds: .infinity),
            record("Invalid", seconds: -10), record("Invalid", seconds: .nan)])
        XCTAssertEqual(pace.wordsPerMinute, 18)
        XCTAssertEqual(pace.seconds, 10)
    }

    @MainActor func testMeasuredPaceRestoresAndClearsWithItsHistory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let history = TranscriptHistory(directory: directory, defaults: defaults)
        let sample = record("One two three", seconds: 10)
        history.append(sample)
        history.setPersistent(true)
        let restored = TranscriptHistory(directory: directory, defaults: defaults)
        XCTAssertEqual(restored.pace.wordsPerMinute, 18)
        restored.update(id: sample.id, text: "A much longer manually edited draft must not change speaking pace.")
        XCTAssertEqual(restored.pace.wordsPerMinute, 18)
        restored.remove(id: sample.id)
        XCTAssertNil(restored.pace.wordsPerMinute)
        restored.undoRemoval()
        XCTAssertEqual(restored.pace.wordsPerMinute, 18)
    }
}
