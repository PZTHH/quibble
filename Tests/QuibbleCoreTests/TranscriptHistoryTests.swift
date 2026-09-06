import XCTest
@testable import QuibbleCore

@MainActor
final class TranscriptHistoryTests: XCTestCase {
    func testLongTranscriptAndOriginalTimedSegmentsSurvivePersistenceAndEditing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let history = TranscriptHistory(directory: directory, defaults: defaults)
        let text = String(repeating: "A spoken sentence. ", count: 3_000)
        let segments = [TranscriptSegment(start: 0, end: 1_800, text: "Original timed section.", source: .audioChunk)]
        let record = TranscriptRecord(original: text, text: text, application: "Notes", mode: "exact", engine: "test", delivery: "Ready", audioSeconds: 1_800, segments: segments)
        history.append(record)
        history.setPersistent(true)
        let restored = TranscriptHistory(directory: directory, defaults: defaults)
        XCTAssertNil(restored.error)
        XCTAssertEqual(restored.records.first?.audioSeconds, 1_800)
        XCTAssertEqual(restored.records.first?.text, text)
        restored.update(id: record.id, text: "Edited prose.")
        XCTAssertEqual(restored.records.first?.segments, segments, "Editing prose must not claim that new words inherit old acoustic timings")
    }

    func testOlderHistoryDoesNotRequireSegmentsAndOversizedHistoryReportsCapacity() throws {
        let old = Data(#"{"id":"00000000-0000-0000-0000-000000000001","date":0,"original":"Hello","text":"Hello","application":"Notes","mode":"exact","engine":"test","delivery":"Ready"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(TranscriptRecord.self, from: old).segments)
        let history = TranscriptHistory(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let text = String(repeating: "x", count: TranscriptHistory.maximumTextUnits + 1)
        history.append(TranscriptRecord(original: text, text: text, application: "", mode: "exact", engine: "test", delivery: "Ready"))
        XCTAssertNotNil(history.error)
    }

    func testSessionHistoryRetainsTextWithoutWritingItToDisk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let history = TranscriptHistory(directory: directory, defaults: defaults)
        history.append(TranscriptRecord(original: "Private draft", text: "Private draft.", application: "Notes", mode: "basic", engine: "test", delivery: "Ready"))
        XCTAssertEqual(history.records.first?.text, "Private draft.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertFalse(history.isPersistent)
    }
}

extension TranscriptHistoryTests {
    func testRecordedDurationSurvivesHistoryRoundTrip() throws {
        let legacy = TranscriptRecord(original: "One two three", text: "A much longer cleaned up result", application: "Notes", mode: "basic", engine: "test", delivery: "Inserted")
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any])
        object["audioSeconds"] = 12.0
        let restored = try decoder.decode(TranscriptRecord.self, from: JSONSerialization.data(withJSONObject: object))
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(restored)) as? [String: Any])
        XCTAssertEqual(encoded["audioSeconds"] as? Double, 12.0, "Measured recording duration must survive a restart")
    }

    func testOptInRestoresTextAndOptOutRemovesTheSavedCopy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let first = TranscriptHistory(directory: directory, defaults: defaults)
        first.append(TranscriptRecord(original: "Shivon called", text: "Siobhan called.", application: "Notes", mode: "basic", engine: "test", delivery: "Paste sent"))
        first.setPersistent(true)
        let restored = TranscriptHistory(directory: directory, defaults: defaults)
        XCTAssertTrue(restored.isPersistent)
        XCTAssertEqual(restored.records.first?.original, "Shivon called")
        XCTAssertEqual(restored.records.first?.text, "Siobhan called.")
        restored.setPersistent(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("history.json").path))
        XCTAssertEqual(restored.records.count, 1, "Opting out keeps this session available")
        XCTAssertTrue(TranscriptHistory(directory: directory, defaults: defaults).records.isEmpty)
    }
}

extension TranscriptHistoryTests {
    func testHistoryExpiresOldTextAndBoundsItsSize() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let history = TranscriptHistory(directory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let now = Date()
        history.append(TranscriptRecord(date: now.addingTimeInterval(-8 * 86400), original: "Expired", text: "Expired", application: "", mode: "exact", engine: "test", delivery: "Ready"), now: now)
        XCTAssertTrue(history.records.isEmpty)
        for index in 0..<105 {
            history.append(TranscriptRecord(date: now.addingTimeInterval(Double(-index)), original: "Text", text: "Item \(index)", application: "", mode: "exact", engine: "test", delivery: "Ready"), now: now)
        }
        XCTAssertEqual(history.records.count, 100)
        XCTAssertEqual(history.records.first?.text, "Item 0")
        XCTAssertEqual(history.records.last?.text, "Item 99")
    }
}

extension TranscriptHistoryTests {
    func testRemovingAndUndoingARecordPreservesOriginalAndCorrectedText() {
        let history = TranscriptHistory(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let record = TranscriptRecord(original: "Shivon", text: "Siobhan", application: "Notes", mode: "basic", engine: "test", delivery: "Ready")
        history.append(record)
        history.remove(id: record.id)
        XCTAssertTrue(history.records.isEmpty)
        XCTAssertTrue(history.canUndoRemoval)
        history.undoRemoval()
        XCTAssertEqual(history.records, [record])
        XCTAssertFalse(history.canUndoRemoval)
    }
}

extension TranscriptHistoryTests {
    func testUnreadableHistoryIsNotOverwrittenByANewDictation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("history.json"), bytes = Data("unreadable existing archive".utf8)
        try bytes.write(to: file)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(true, forKey: "keepTranscriptHistory")
        let history = TranscriptHistory(directory: directory, defaults: defaults)
        history.append(TranscriptRecord(original: "New", text: "New text", application: "", mode: "basic", engine: "test", delivery: "Ready"))
        XCTAssertNotNil(history.error)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(history.records.first?.text, "New text")
    }
}


extension TranscriptHistoryTests {
    func testLargeHistoryStaysReadableWithinTheStorageLimit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let history = TranscriptHistory(directory: directory, defaults: defaults)
        let largeText = String(repeating: "\u{0001}", count: 32_000)
        for index in 0..<24 {
            history.append(TranscriptRecord(original: largeText, text: largeText, application: "Item \(index)", mode: "basic", engine: "test", delivery: "Ready"))
        }
        history.setPersistent(true)
        let data = try Data(contentsOf: directory.appendingPathComponent("history.json"))
        XCTAssertLessThanOrEqual(data.count, 8_000_000)
        let restored = TranscriptHistory(directory: directory, defaults: defaults)
        XCTAssertNil(restored.error)
        XCTAssertFalse(restored.records.isEmpty)
        XCTAssertEqual(restored.records, history.records)
        XCTAssertEqual(restored.records.first?.application, "Item 23")
    }
}

extension TranscriptHistoryTests {
    func testApplicationIdentitySurvivesRoundTripWithoutRequiringItInOlderHistory() throws {
        let legacy = TranscriptRecord(original: "Hello", text: "Hello", application: "Notes", mode: "basic", engine: "test", delivery: "Inserted")
        let encoder = JSONEncoder(), decoder = JSONDecoder()
        let oldData = try encoder.encode(legacy)
        XCTAssertEqual(try decoder.decode(TranscriptRecord.self, from: oldData), legacy)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: oldData) as? [String: Any])
        object["applicationBundleID"] = "com.apple.Notes"
        let restored = try decoder.decode(TranscriptRecord.self, from: JSONSerialization.data(withJSONObject: object))
        let roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(restored)) as? [String: Any])
        XCTAssertEqual(roundTrip["applicationBundleID"] as? String, "com.apple.Notes")
    }
}
