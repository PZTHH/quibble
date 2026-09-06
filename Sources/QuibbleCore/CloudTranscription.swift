import Foundation

public enum CloudTranscriptionError: LocalizedError, Equatable {
    case missingKey, invalidAudio, tooLarge, unauthorized, rateLimited, rejected(Int), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .missingKey: "Add your OpenAI API key in Models → Online transcription."
        case .invalidAudio: "The recording could not be prepared for online transcription."
        case .tooLarge: "The recording is too large for online transcription."
        case .unauthorized: "OpenAI rejected the API key. Update it in Models → Online transcription."
        case .rateLimited: "OpenAI's usage or rate limit was reached. Check your API billing and try again later."
        case .rejected(let status): "OpenAI could not transcribe this recording (HTTP \(status)). No fallback was sent."
        case .invalidResponse: "OpenAI returned an unreadable transcription. No text was inserted."
        }
    }
}

public struct CloudTranscript: Sendable, Equatable {
    public let text: String
    public let languages: [String]
    public let hintCount: Int
    public let omittedHintCount: Int
    public let segments: [TranscriptSegment]?
}

private final class RejectCloudRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Fixed provider endpoint, in-memory uploads, and no retries or implicit cloud fallback.
public struct OpenAITranscriptionClient: Sendable {
    public static let modelID = "openai-transcribe"
    public static let diarizationModelID = "openai-diarize"
    public static let apiModel = "gpt-transcribe"
    public static let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    public enum Model: String, Sendable {
        case transcription = "gpt-transcribe"
        case diarization = "gpt-4o-transcribe-diarize"
        public var supportsVocabularyHints: Bool { self == .transcription }
    }
    public let model: Model
    public init(model: Model = .transcription) { self.model = model }

    public struct Request: Sendable {
        public let urlRequest: URLRequest
        public let hintCount: Int
        public let omittedHintCount: Int
    }

    public func request(wav: Data, apiKey: String, language: String, vocabulary: [String]) throws -> Request {
        guard !apiKey.isEmpty, apiKey.count <= 2048, apiKey.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw CloudTranscriptionError.missingKey
        }
        guard wav.count >= 12, wav.prefix(4) == Data("RIFF".utf8), wav[8..<12] == Data("WAVE".utf8) else {
            throw CloudTranscriptionError.invalidAudio
        }
        guard wav.count <= 25_000_000 else { throw CloudTranscriptionError.tooLarge }
        let boundary = "Quibble-" + UUID().uuidString
        var body = Data(), hints: [String] = [], seen = Set<String>(), omitted = 0, budget = 4_000
        for word in vocabulary {
            let term = word.trimmingCharacters(in: .whitespacesAndNewlines)
            guard seen.insert(term).inserted else { continue }
            guard !term.isEmpty, term.count <= 100, !term.contains(where: { $0 == "<" || $0 == ">" || $0.isNewline }),
                  !term.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  hints.count < 100, term.utf8.count <= budget else { omitted += 1; continue }
            hints.append(term); budget -= term.utf8.count
        }
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", model.rawValue)
        // Restrict to controls Quibble actually exposes; never interpolate arbitrary form headers.
        if ["en", "de", "fr", "es", "it", "pt", "ja", "zh", "ko"].contains(language) {
            field(model == .diarization ? "language" : "languages[]", language)
        }
        if model == .diarization {
            field("response_format", "diarized_json")
            field("chunking_strategy", "auto")
            omitted += hints.count
            hints.removeAll()
        } else {
            for hint in hints { field("keywords[]", hint) }
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: Self.endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 60)
        request.httpMethod = "POST"; request.httpBody = body; request.httpShouldHandleCookies = false
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return Request(urlRequest: request, hintCount: hints.count, omittedHintCount: omitted)
    }

    public func decode(_ data: Data, status: Int, hintCount: Int, omittedHintCount: Int) throws -> CloudTranscript {
        if status == 401 || status == 403 { throw CloudTranscriptionError.unauthorized }
        if status == 429 { throw CloudTranscriptionError.rateLimited }
        guard status == 200 else { throw CloudTranscriptionError.rejected(status) }
        struct Response: Decodable {
            struct Language: Decodable { let code: String }
            struct Segment: Decodable {
                let id: String
                let start: Double
                let end: Double
                let text: String
                let speaker: String
            }
            let text: String
            let languages: [Language]?
            let segments: [Segment]?
            let duration: Double?
        }
        guard data.count <= 1_000_000, let value = try? JSONDecoder().decode(Response.self, from: data),
              value.text.utf16.count <= 32_000 else { throw CloudTranscriptionError.invalidResponse }
        var segments: [TranscriptSegment]?
        if model == .diarization {
            guard let reported = value.segments, reported.count <= 2_048 else { throw CloudTranscriptionError.invalidResponse }
            let converted = reported.map {
                TranscriptSegment(id: $0.id, start: $0.start, end: $0.end, text: $0.text, speaker: $0.speaker, source: .model)
            }
            var seen = Set<String>()
            guard converted.allSatisfy({ $0.isValid && seen.insert($0.id).inserted }),
                  converted.reduce(0, { $0 + $1.text.utf16.count }) <= 32_000 else { throw CloudTranscriptionError.invalidResponse }
            if let duration = value.duration {
                guard duration.isFinite && duration >= 0,
                      converted.allSatisfy({ $0.end <= duration + 0.05 }) else { throw CloudTranscriptionError.invalidResponse }
            }
            guard value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !converted.isEmpty else {
                throw CloudTranscriptionError.invalidResponse
            }
            segments = converted
        }
        return CloudTranscript(text: value.text.trimmingCharacters(in: .whitespacesAndNewlines),
            languages: (value.languages ?? []).map(\.code).filter { $0.count <= 12 },
            hintCount: hintCount, omittedHintCount: omittedHintCount, segments: segments)
    }

    public func transcribe(wav: Data, apiKey: String, language: String, vocabulary: [String],
        session testSession: URLSession? = nil) async throws -> CloudTranscript {
        try Task.checkCancellation()
        let prepared = try request(wav: wav, apiKey: apiKey, language: language, vocabulary: vocabulary)
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 90
        let session = testSession ?? URLSession(configuration: config, delegate: RejectCloudRedirects(), delegateQueue: nil)
        defer { if testSession == nil { session.invalidateAndCancel() } }
        let (bytes, response) = try await session.bytes(for: prepared.urlRequest)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CloudTranscriptionError.invalidResponse }
        guard response.statusCode == 200 else {
            return try decode(Data(), status: response.statusCode, hintCount: prepared.hintCount, omittedHintCount: prepared.omittedHintCount)
        }
        guard response.expectedContentLength <= 1_000_000 else { throw CloudTranscriptionError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            guard data.count < 1_000_000 else { throw CloudTranscriptionError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try decode(data, status: response.statusCode, hintCount: prepared.hintCount, omittedHintCount: prepared.omittedHintCount)
    }

    /// Canonical upload for recordings and imports alike; original filenames never leave the Mac.
    public static func wav(samples: [Float]) throws -> Data {
        guard !samples.isEmpty, samples.count <= 968_000, samples.allSatisfy(\.isFinite) else { throw CloudTranscriptionError.invalidAudio }
        let bytes = UInt32(samples.count * 2)
        var data = Data()
        func integer<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(Data("RIFF".utf8)); integer(bytes + 36); data.append(Data("WAVEfmt ".utf8))
        integer(UInt32(16)); integer(UInt16(1)); integer(UInt16(1)); integer(UInt32(16_000))
        integer(UInt32(32_000)); integer(UInt16(2)); integer(UInt16(16))
        data.append(Data("data".utf8)); integer(bytes)
        let pcm = samples.map { Int16((min(1, max(-1, $0)) * 32767).rounded()).littleEndian }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
