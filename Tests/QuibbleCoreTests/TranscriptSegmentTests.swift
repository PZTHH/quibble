import XCTest
@testable import QuibbleCore

final class TranscriptSegmentTests: XCTestCase {
    func testModelMetadataConversionPreservesTimingAndSkipsMissingOrInvalidTimes() {
        let values: [[String: Any]] = [
            ["start": 0.4, "end": 2.1, "text": "Hello.", "speaker": "A"],
            ["start": 1.0, "end": 0.0, "text": "Backwards."],
            ["text": "No timestamp."],
            ["start": Double.nan, "end": 3.0, "text": "Invalid."]
        ]
        let segments = TranscriptSegment.fromModelSegments(values, source: .model, offset: 60)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].start, 60.4)
        XCTAssertEqual(segments[0].end, 62.1)
        XCTAssertEqual(segments[0].speaker, "A")
        XCTAssertEqual(segments[0].source, .model)
    }

    func testIndependentSpeakerScopesNeverBecomeTheSamePersonByLabelAlone() {
        let segment = TranscriptSegment(id: "segment", start: 1, end: 2, text: "Original ASR.", speaker: "A", source: .model)
        let first = segment.offsetted(by: 0, speakerScope: "Part 1")
        let second = segment.offsetted(by: 60, speakerScope: "Part 2")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.speaker, second.speaker)
        XCTAssertEqual(second.start, 61)
        XCTAssertEqual(second.text, segment.text)
    }

    func testInvalidSavedMetadataCannotDecodeIntoTheTimeline() throws {
        let segment = TranscriptSegment(id: "segment", start: 1, end: 2, text: "Hello.", source: .audioChunk)
        let encoded = try JSONEncoder().encode(segment)
        XCTAssertEqual(try JSONDecoder().decode(TranscriptSegment.self, from: encoded), segment)
        var invalid = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        invalid["end"] = 0
        XCTAssertThrowsError(try JSONDecoder().decode(TranscriptSegment.self, from: JSONSerialization.data(withJSONObject: invalid)))
    }
}
