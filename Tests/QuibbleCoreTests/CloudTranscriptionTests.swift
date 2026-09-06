import XCTest
@testable import QuibbleCore

final class CloudTranscriptionTests: XCTestCase {
    let wav = try! OpenAITranscriptionClient.wav(samples: [0, 0.2, -0.2, 0])
    func testSpeakerRequestUsesDedicatedModelAndOmitsUnsupportedHints() throws {
        let prepared = try OpenAITranscriptionClient(model: .diarization).request(wav: wav, apiKey: "fixture-key", language: "en", vocabulary: ["Siobhan"])
        let body = String(decoding: prepared.urlRequest.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-4o-transcribe-diarize"))
        XCTAssertTrue(body.contains("name=\"response_format\"\r\n\r\ndiarized_json"))
        XCTAssertTrue(body.contains("name=\"chunking_strategy\"\r\n\r\nauto"))
        XCTAssertTrue(body.contains("name=\"language\"\r\n\r\nen"))
        for unsupported in ["keywords[]", "languages[]", "prompt", "timestamp_granularities[]", "include[]"] {
            XCTAssertFalse(body.contains("name=\"\(unsupported)\""))
        }
        XCTAssertFalse(body.contains("Siobhan"))
        XCTAssertEqual(prepared.hintCount, 0)
        XCTAssertEqual(prepared.omittedHintCount, 1)
    }

    func testSpeakerSegmentsPreserveActualTextTimingAndLabels() throws {
        let body = Data(#"{"text":"Hello there. Good morning.","duration":3.2,"segments":[{"id":"seg_1","start":0.2,"end":1.5,"text":"Hello there.","speaker":"A"},{"id":"seg_2","start":1.4,"end":3.2,"text":"Good morning.","speaker":"B"}]}"#.utf8)
        let result = try OpenAITranscriptionClient(model: .diarization).decode(body, status: 200, hintCount: 0, omittedHintCount: 0)
        let segments = try XCTUnwrap(result.segments)
        XCTAssertEqual(segments.map(\.speaker), ["A", "B"])
        XCTAssertEqual(segments.map(\.start), [0.2, 1.4], "Overlapping speakers are valid and must not be forced sequential")
        XCTAssertEqual(segments.map(\.end), [1.5, 3.2])
        XCTAssertEqual(segments.map(\.text), ["Hello there.", "Good morning."])
        XCTAssertTrue(segments.allSatisfy { $0.source == .model })
    }

    func testMalformedSpeakerMetadataRejectsEntireResponse() throws {
        let client = OpenAITranscriptionClient(model: .diarization)
        let valid: [String: Any] = ["id": "seg_1", "start": 0.2, "end": 1.5, "text": "Hello.", "speaker": "A"]
        var invalidSegments: [[String: Any]] = []
        for (key, value) in [("start", -1.0 as Any), ("end", 0.1 as Any), ("end", 90.0 as Any),
                             ("speaker", "" as Any), ("speaker", "A\nB" as Any), ("id", String(repeating: "x", count: 161) as Any)] {
            var segment = valid; segment[key] = value; invalidSegments.append(segment)
        }
        for segment in invalidSegments {
            let body = try JSONSerialization.data(withJSONObject: ["text": "Hello.", "duration": 2, "segments": [segment]])
            XCTAssertThrowsError(try client.decode(body, status: 200, hintCount: 0, omittedHintCount: 0)) {
                XCTAssertEqual($0 as? CloudTranscriptionError, .invalidResponse)
            }
        }
        for body in [Data(#"{"text":"Hello."}"#.utf8), Data(#"{"text":"Hello.","segments":[]}"#.utf8),
                     try JSONSerialization.data(withJSONObject: ["text": "Hello.", "segments": [valid, valid]])] {
            XCTAssertThrowsError(try client.decode(body, status: 200, hintCount: 0, omittedHintCount: 0))
        }
    }

    func testSpeakerTransportReturnsSegmentsWithoutExtraRequests() async throws {
        let body = Data(#"{"text":"Hello.","duration":2,"segments":[{"id":"seg_1","start":0.2,"end":1.5,"text":"Hello.","speaker":"A"}]}"#.utf8)
        let (session, fixture, key) = fixtureSession(status: 200, body: body)
        defer { session.invalidateAndCancel(); CloudFixtureRegistry.shared.remove(key: key) }
        let result = try await OpenAITranscriptionClient(model: .diarization).transcribe(wav: wav, apiKey: key, language: "en", vocabulary: [], session: session)
        XCTAssertEqual(result.segments?.first?.speaker, "A")
        XCTAssertEqual(fixture.requestCount, 1)
    }
    func testRequestSendsOnlyExplicitAudioLanguageAndLiteralVocabularyToFixedProvider() throws {
        let request = try OpenAITranscriptionClient().request(wav: wav, apiKey: "fixture-key", language: "en",
            vocabulary: ["Siobhan", "AC-42", "Siobhan", "bad\nterm", "<injection>"])
        XCTAssertEqual(request.urlRequest.httpMethod, "POST")
        XCTAssertEqual(request.urlRequest.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
        let body = String(decoding: request.urlRequest.httpBody ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-transcribe"))
        XCTAssertTrue(body.contains("name=\"keywords[]\"\r\n\r\nSiobhan"))
        XCTAssertTrue(body.contains("name=\"languages[]\"\r\n\r\nen"))
        XCTAssertTrue(body.contains("filename=\"dictation.wav\""))
        XCTAssertFalse(body.contains("bad\nterm"))
        XCTAssertFalse(body.contains("<injection>"))
        XCTAssertFalse(body.contains("name=\"prompt\""))
        XCTAssertFalse(body.contains("fixture-key"))
        XCTAssertEqual(request.hintCount, 2)
        XCTAssertEqual(request.omittedHintCount, 2)
    }

    func testDecodingPreservesTextLanguageAndHintAccountingAndRejectsInvalidResults() throws {
        let client = OpenAITranscriptionClient()
        let valid = Data(#"{"text":"  Meet Siobhan on Friday.\n","languages":[{"code":"en"},{"code":"de"}]}"#.utf8)
        let result = try client.decode(valid, status: 200, hintCount: 2, omittedHintCount: 3)
        XCTAssertEqual(result.text, "Meet Siobhan on Friday.")
        XCTAssertEqual(result.languages, ["en", "de"])
        XCTAssertEqual(result.hintCount, 2)
        XCTAssertEqual(result.omittedHintCount, 3)
        let noLanguage = try client.decode(Data(#"{"text":"Hello."}"#.utf8), status: 200, hintCount: 0, omittedHintCount: 0)
        XCTAssertEqual(noLanguage.languages, [])

        let overlongText = try JSONSerialization.data(withJSONObject: ["text": String(repeating: "🙂", count: 16_001)])
        for invalid in [Data("not JSON".utf8), Data(#"{"text":42}"#.utf8), Data(repeating: 0x20, count: 1_000_001), overlongText] {
            XCTAssertThrowsError(try client.decode(invalid, status: 200, hintCount: 0, omittedHintCount: 0)) {
                XCTAssertEqual($0 as? CloudTranscriptionError, .invalidResponse)
            }
        }
    }

    func testHTTPFailuresNeverReflectProviderBodyOrSecretsInStatusMessages() {
        let body = Data(#"{"error":{"message":"fixture-secret-token; private dictated text; unexpected provider diagnostic"}}"#.utf8)
        let cases: [(Int, CloudTranscriptionError)] = [(401, .unauthorized), (403, .unauthorized), (429, .rateLimited), (503, .rejected(503))]
        for (status, expected) in cases {
            XCTAssertThrowsError(try OpenAITranscriptionClient().decode(body, status: status, hintCount: 0, omittedHintCount: 0)) { error in
                XCTAssertEqual(error as? CloudTranscriptionError, expected)
                for privateText in ["fixture-secret-token", "private dictated text", "unexpected provider diagnostic"] {
                    XCTAssertFalse(error.localizedDescription.contains(privateText))
                }
            }
        }
    }

    func testCanonicalWAVEncodesMonoPCM16LittleEndianAndRejectsInvalidSamples() throws {
        let data = try OpenAITranscriptionClient.wav(samples: [-2, -1, -0.5, 0, 0.5, 1, 2])
        // RIFF size 50; 16kHz mono PCM16; seven samples occupy 14 bytes.
        let header: [UInt8] = [
            0x52, 0x49, 0x46, 0x46, 0x32, 0, 0, 0, 0x57, 0x41, 0x56, 0x45,
            0x66, 0x6d, 0x74, 0x20, 0x10, 0, 0, 0, 1, 0, 1, 0,
            0x80, 0x3e, 0, 0, 0, 0x7d, 0, 0, 2, 0, 0x10, 0,
            0x64, 0x61, 0x74, 0x61, 0x0e, 0, 0, 0
        ]
        XCTAssertEqual(Array(data.prefix(44)), header)
        XCTAssertEqual(Array(data.dropFirst(44)), [0x01, 0x80, 0x01, 0x80, 0, 0xc0, 0, 0, 0, 0x40, 0xff, 0x7f, 0xff, 0x7f])
        for invalid: [Float] in [[], [.nan], [.infinity], Array(repeating: 0, count: 968_001)] {
            XCTAssertThrowsError(try OpenAITranscriptionClient.wav(samples: invalid)) {
                XCTAssertEqual($0 as? CloudTranscriptionError, .invalidAudio)
            }
        }
    }

    func testLiteralVocabularyIsSanitizedAndBoundedBeforeUpload() throws {
        let client = OpenAITranscriptionClient()
        let sanitized = try client.request(wav: wav, apiKey: "fixture-key", language: "en\r\nInjected: yes",
            vocabulary: [" Siobhan ", "Siobhan", "", "bad\u{0000}term", "bad\r\nterm", "<tag>", String(repeating: "x", count: 101), "AC-42"])
        let body = String(decoding: sanitized.urlRequest.httpBody!, as: UTF8.self)
        XCTAssertEqual(sanitized.hintCount, 2)
        XCTAssertEqual(sanitized.omittedHintCount, 5)
        XCTAssertFalse(body.contains("Injected: yes"))
        XCTAssertFalse(body.contains("name=\"languages[]\""))
        XCTAssertFalse(body.contains("bad\u{0000}term"))
        XCTAssertTrue(body.contains("\r\n\r\nSiobhan\r\n"))

        let byteBound = try client.request(wav: wav, apiKey: "fixture-key", language: "en", vocabulary: (0..<25).map {
            String(format: "%02d", $0) + String(repeating: "é", count: 98)
        })
        XCTAssertEqual(byteBound.hintCount, 20, "The literal hint budget counts UTF-8 bytes, not just characters")
        XCTAssertEqual(byteBound.omittedHintCount, 5)
        let countBound = try client.request(wav: wav, apiKey: "fixture-key", language: "en", vocabulary: (0..<105).map { "Term\($0)" })
        XCTAssertEqual(countBound.hintCount, 100)
        XCTAssertEqual(countBound.omittedHintCount, 5)
    }

    func testCancellationBeforeTranscriptionDoesNotReachTransport() async {
        let (session, fixture, key) = fixtureSession(status: 200, body: Data(#"{"text":"Unexpected."}"#.utf8))
        defer { session.invalidateAndCancel(); CloudFixtureRegistry.shared.remove(key: key) }
        let audio = wav
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await OpenAITranscriptionClient().transcribe(wav: audio, apiKey: key, language: "en", vocabulary: [], session: session)
        }
        switch await task.result {
        case .success: XCTFail("A cancelled request must not return a transcript")
        case .failure(let error): XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(fixture.requestCount, 0)
    }

    func testTransportDecodesSuccessAndDoesNotRetryRateLimitedUploads() async throws {
        for status in [200, 429] {
            let body = Data(#"{"text":"  Please email Siobhan.  ","languages":[{"code":"en"}]}"#.utf8)
            let (session, fixture, key) = fixtureSession(status: status, body: body)
            defer { session.invalidateAndCancel(); CloudFixtureRegistry.shared.remove(key: key) }
            do {
                let result = try await OpenAITranscriptionClient().transcribe(wav: wav, apiKey: key, language: "en", vocabulary: ["Siobhan"], session: session)
                XCTAssertEqual(status, 200, "A rate-limited upload must fail instead of inserting a response")
                XCTAssertEqual(result.text, "Please email Siobhan.")
                XCTAssertEqual(result.languages, ["en"])
                XCTAssertEqual(result.hintCount, 1)
            } catch {
                if status == 429 { XCTAssertEqual(error as? CloudTranscriptionError, .rateLimited) }
                else { throw error }
            }
            XCTAssertEqual(fixture.requestCount, 1, "Each explicit dictation may upload only once")
        }
    }

    private func fixtureSession(status: Int, body: Data) -> (URLSession, CloudHTTPFixture, String) {
        let key = "fixture-" + UUID().uuidString
        let fixture = CloudHTTPFixture(status: status, body: body)
        CloudFixtureRegistry.shared.install(fixture, key: key)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudFixtureURLProtocol.self]
        configuration.urlCache = nil
        return (URLSession(configuration: configuration), fixture, key)
    }
}

private final class CloudHTTPFixture: @unchecked Sendable {
    let status: Int
    let body: Data
    private let lock = NSLock()
    private var count = 0
    init(status: Int, body: Data) { self.status = status; self.body = body }
    var requestCount: Int { lock.withLock { count } }
    func recordRequest() { lock.withLock { count += 1 } }
}

private final class CloudFixtureRegistry: @unchecked Sendable {
    static let shared = CloudFixtureRegistry()
    private let lock = NSLock()
    private var fixtures: [String: CloudHTTPFixture] = [:]
    func install(_ fixture: CloudHTTPFixture, key: String) { lock.withLock { fixtures[key] = fixture } }
    func remove(key: String) { lock.withLock { _ = fixtures.removeValue(forKey: key) } }
    func fixture(for request: URLRequest) -> CloudHTTPFixture? {
        guard let header = request.value(forHTTPHeaderField: "Authorization"), header.hasPrefix("Bearer ") else { return nil }
        return lock.withLock { fixtures[String(header.dropFirst(7))] }
    }
}

/// Intercepts every request in each fixture session, so a missing fixture cannot hit the network.
private final class CloudFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = CloudFixtureRegistry.shared.fixture(for: request), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        fixture.recordRequest()
        let response = HTTPURLResponse(url: url, statusCode: fixture.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
