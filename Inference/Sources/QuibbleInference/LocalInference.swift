import Foundation
import AVFoundation
import MLX
import MLXAudioCore
import MLXAudioSTT
import MLXLLM
import MLXLMCommon
import Tokenizers
import QuibbleCore
import QuibbleWhisper

// Local stages and the explicitly selected online speech adapter share one delivery pipeline.
public enum InferenceError: LocalizedError {
    case missingModel(String)
    case inputTooLong
    case emptyAudio
    case invalidRefinement
    public var errorDescription: String? {
        switch self {
        case .missingModel(let name): return "Download \(name) in the Models library."
        case .inputTooLong: return "This writing step exceeds the selected model's context. Its input was retained."
        case .invalidRefinement: return "The refinement was incomplete. Original transcription retained."
        case .emptyAudio: return "The audio file is empty or has an unsupported duration."
        }
    }
}

public struct InferenceResult: Codable, Sendable {
    public let engine: String
    public let raw: String
    public let text: String
    public let audioSeconds: Double
    public let loadSeconds: Double
    public let transcriptionSeconds: Double
    public let refinementSeconds: Double
    public let processingSeconds: Double
    public let peakMemoryBytes: Int
    public let mode: String
    public let warning: String?
    public var vocabularyText: String? = nil
    public var vocabularyChanges: [VocabularyChange]? = nil
    public var vocabularySeconds: Double? = nil
    public var activeMemoryBytes: Int? = nil
    public var workflow: DictationWorkflow? = nil
    public var stages: [WorkflowStageTrace]? = nil
    public var asrDetails: ASRDetails? = nil
    public var segments: [TranscriptSegment]? = nil
}

public struct WorkflowStageTrace: Codable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let model: String
    public let input: String
    public let output: String
    public let seconds: Double
    public let status: String
    public let prompt: String?
    public let modelOutput: String?
}
public struct ASRDetails: Codable, Sendable {
    public let requested: ASROptions
    public let promptTokens: Int?
    public let generatedTokens: Int?
    public let tokensPerSecond: Double?
    public let reportedLanguage: String?
    public let segmentsJSON: String?
    public let rmsDBFS: Double
    public let notes: String
}
public enum SpeechEngine: String, CaseIterable, Sendable {
    case cohere4bit = "cohere-4bit", cohere8bit = "cohere-8bit"
    case cohere, parakeet
    case parakeet8bit = "parakeet-8bit"
    case qwenASR = "qwen3-asr-4bit", qwenSmall = "qwen3-asr-06b-4bit"
    case qwen8bit = "qwen3-asr-8bit", qwenSmall8bit = "qwen3-asr-06b-8bit"
    case whisperTurbo = "whisper-turbo-vocabulary-4bit", whisperLarge = "whisper-large-vocabulary-4bit"
    case whisperSmall = "whisper-small-4bit", whisperBase = "whisper-base-4bit"
    case whisperTurbo8bit = "whisper-turbo-vocabulary-8bit", whisperLarge8bit = "whisper-large-vocabulary-8bit"
    case whisperSmall8bit = "whisper-small-8bit", whisperBase8bit = "whisper-base-8bit"
    case canary = "canary-v2-8bit", nemotron = "nemotron-35-8bit"
    case granite4bit = "granite-4-speech-4bit", granite5bit = "granite-4-speech-5bit", granite8bit = "granite-4-speech-8bit"
    case moonshineTiny = "moonshine-tiny", moonshineBase = "moonshine-base"
    case openAI = "openai-transcribe"
    case openAIDiarize = "openai-diarize"
    public var isOnline: Bool { self == .openAI || self == .openAIDiarize }
    public var supportsVocabularyHints: Bool { self == .openAI }
    public var isParakeet: Bool { self == .parakeet || self == .parakeet8bit }
    public var isWhisper: Bool { rawValue.hasPrefix("whisper-") }
    public var isQwen: Bool { rawValue.hasPrefix("qwen3-asr-") }
    public var isCohere: Bool { self == .cohere || self == .cohere4bit || self == .cohere8bit }
    public var isGranite: Bool { rawValue.hasPrefix("granite-4-speech-") }
    public var isMoonshine: Bool { self == .moonshineTiny || self == .moonshineBase }
    public var supportsTemperature: Bool { isCohere || isWhisper || isMoonshine || isGranite || self == .canary }
    public var supportsTokenLimit: Bool { !isParakeet && self != .nemotron && !isOnline }
    public var supportsChunkLength: Bool { !isWhisper && !isMoonshine && !isGranite && self != .canary && !isOnline }
    /// Bound full-context decoders; the sequential reader retains every audio sample.
    public var maximumAudioSectionSeconds: Double { isMoonshine ? 20 : self == .canary || isGranite ? 30 : 60 }
    public var languageCodes: [String] {
        if isParakeet || isMoonshine { return ["en"] }
        if self == .canary { return ["en", "de", "fr", "es", "it", "pt"] }
        if isGranite { return ["en", "de", "fr", "es", "pt", "ja"] }
        return ["en", "de", "fr", "es", "it", "pt", "ja", "zh", "ko"]
    }
    public var supportsLanguageSelection: Bool { !isParakeet && !isMoonshine && !isGranite }
    /// Resolve the persisted UI code to the exact decoder key; nil means no language control.
    public func decoderLanguage(for requested: String) -> String? {
        guard supportsLanguageSelection else { return nil }
        let supported = languageCodes.contains(requested) ? requested : "en"
        if self == .nemotron {
            // The pinned 3.5 prompt dictionary has no bare ja/zh aliases; those silently use auto.
            return ["ja": "ja-JP", "zh": "zh-CN"][supported] ?? supported
        }
        return supported
    }
    public var languageDescription: String {
        if isMoonshine { return "English only. This original Moonshine model has no language selector or detection." }
        if isGranite { return "Recognizes English, French, German, Spanish, Portuguese and Japanese from the audio. Language selection is unavailable in this ASR adapter; no translation prompt is sent." }
        if isParakeet { return "Automatic in the TDT adapter. The upstream v3 model is multilingual; English is the tested baseline." }
        if self == .nemotron { return "Nemotron 3.5 uses the chosen language for recognition. Chinese uses its Mainland Chinese locale; Japanese uses its Japanese locale. This is the multilingual model, not the older English-only checkpoint." }
        if self == .canary { return "Choose English, German, French, Spanish, Italian or Portuguese. The chosen language is used for both source and target, preserving transcription." }
        if isOnline { return "The chosen language is sent as a provider hint." }
        return "Choose from \(languageCodes.count) languages exposed by this adapter. English is the tested baseline."
    }
    public var decoderNotes: String {
        if self == .openAIDiarize { return "OpenAI speaker transcription provides model timestamps and request-scoped speaker labels. Vocabulary hints are unsupported; explicit spelling rules still apply. Long recordings use separate requests, so a speaker label is not an identity across sections." }
        if isOnline { return "OpenAI file transcription. Audio and enabled saved-word hints are sent on release. Language is a hint, not a forced decoder setting. Token limits, temperature, and chunks are managed by the provider. No local speech or vocabulary model is loaded; enabled writing steps remain local." }
        if isParakeet { return "Greedy TDT decoding. Token limit and temperature are not supported. Language is automatic; the backend language label is not detection evidence. Segment times are sentence alignments; token counts are unavailable." }
        if self == .nemotron { return "Greedy RNN-T decoding with language conditioning. Token limit and temperature are not supported. This app processes audio on release; model streaming capability does not imply live partial text. Segment times are backend sentence alignments, not confidence scores." }
        if isGranite { return "Granite 4.0 recognition in bounded 30-second sections. The audio determines its language; no translation prompt is sent. Token limit and temperature are adjustable. Section boundaries are not word timestamps. This is the autoregressive 4.0 model, not newer NAR or TurboCTC." }
        if self == .canary { return "Attention encoder-decoder transcription in the chosen supported language. Audio uses bounded 30-second sections with quiet boundaries where available; token limit is capped at 1,000 per section. Segment times are audio-section boundaries." }
        if isMoonshine { return "Original English-only Moonshine. Audio uses bounded 20-second sections with quiet boundaries where available. Decoder tokens are limited by audio duration and model context to reduce loops. No language detection or word timestamps; full-context decoding has no live partial text." }
        if isWhisper { return "Fixed 30-second windows. Token cap applies per window and is also bounded by the model context. Segment times are chunk boundaries, not word alignments. Explicit language selection; no automatic language detection in this adapter." }
        if isQwen { return "Greedy decoding. Temperature is ineffective in this runtime and remains zero. Segments are chunk boundaries, not word alignments. The primary ASR receives no vocabulary/context prompt." }
        return "Temperature zero uses greedy decoding. Token cap applies within the backend context budget. No calibrated word confidence or token IDs are exposed by this adapter." 
    }
    public var displayName: String {
        switch self {
        case .cohere4bit: "Cohere Transcribe · 4-bit"
        case .cohere8bit: "Cohere Transcribe · 8-bit"
        case .cohere: "Cohere Transcribe · FP16"
        case .parakeet: "Parakeet v3 · FP32"
        case .parakeet8bit: "Parakeet v3 · 8-bit"
        case .qwenASR: "Qwen3 ASR 1.7B · 4-bit"
        case .qwenSmall: "Qwen3 ASR 0.6B · 4-bit"
        case .qwen8bit: "Qwen3 ASR 1.7B · 8-bit"
        case .qwenSmall8bit: "Qwen3 ASR 0.6B · 8-bit"
        case .whisperTurbo: "Whisper Turbo · 4-bit"
        case .whisperLarge: "Whisper Large v3 · 4-bit"
        case .whisperSmall: "Whisper Small · 4-bit"
        case .whisperBase: "Whisper Base · 4-bit"
        case .whisperTurbo8bit: "Whisper Turbo · 8-bit"
        case .whisperLarge8bit: "Whisper Large v3 · 8-bit"
        case .whisperSmall8bit: "Whisper Small · 8-bit"
        case .whisperBase8bit: "Whisper Base · 8-bit"
        case .granite4bit: "Granite Speech 4.0 · 4-bit"
        case .granite5bit: "Granite Speech 4.0 · 5-bit"
        case .granite8bit: "Granite Speech 4.0 · 8-bit"
        case .canary: "Canary v2 · 8-bit"
        case .nemotron: "Nemotron 3.5 · 8-bit"
        case .moonshineTiny: "Moonshine Tiny"
        case .moonshineBase: "Moonshine Base"
        case .openAI: "OpenAI Transcribe · Online"
        case .openAIDiarize: "OpenAI Speakers · Online"
        }
    }
}

public actor LocalInference {
    private var primaryWhisper: QuibbleWhisper.WhisperModel?
    private var loadedInstructionID: String?
    private var vocabularyModel: QuibbleWhisper.WhisperModel?
    private var cohere: CohereTranscribeModel?
    private var parakeet: ParakeetModel?
    private var qwenASR: Qwen3ASRModel?
    private var canary: CanaryModel?
    private var nemotron: NemotronASRModel?
    private var moonshine: MoonshineModel?
    private var granite: GraniteSpeechModel?
    private var cleanup: ModelContainer?
    private var instructionModel: ModelContainer?
    private var loadedRoot: URL?
    private var loadedSpeechEngine: SpeechEngine?
    public init() { Memory.cacheLimit = 32 * 1_024 * 1_024 }

    public func unload() {
        guard !Task.isCancelled else { return }
        cohere = nil; parakeet = nil; qwenASR = nil; primaryWhisper = nil; canary = nil; nemotron = nil; moonshine = nil; granite = nil; cleanup = nil; instructionModel = nil; vocabularyModel = nil
        loadedRoot = nil; loadedSpeechEngine = nil
        Memory.clearCache()
    }
    public func memoryUsage() -> [String: Int] {
        ["activeBytes": Memory.activeMemory, "cacheBytes": Memory.cacheMemory, "peakBytes": Memory.peakMemory]
    }

    public func load(root: URL, withCleanup: Bool, engine: SpeechEngine = .cohere4bit) async throws -> Double {
        let start = ProcessInfo.processInfo.systemUptime
        if loadedRoot != root { cohere = nil; parakeet = nil; qwenASR = nil; primaryWhisper = nil; canary = nil; nemotron = nil; moonshine = nil; granite = nil; cleanup = nil; instructionModel = nil; vocabularyModel = nil; loadedRoot = root }
        if loadedSpeechEngine != engine {
            cohere = nil; parakeet = nil; qwenASR = nil; primaryWhisper = nil; canary = nil; nemotron = nil; moonshine = nil; granite = nil; loadedSpeechEngine = engine
        }
        let speechDirectory = root.appendingPathComponent(engine.rawValue)
        guard engine.isOnline || FileManager.default.fileExists(atPath: speechDirectory.appendingPathComponent("model.safetensors").path) else {
            throw InferenceError.missingModel(engine.displayName)
        }
        if engine.isCohere && cohere == nil { parakeet = nil; cohere = try CohereTranscribeModel.fromDirectory(speechDirectory) }
        if engine.isParakeet && parakeet == nil { cohere = nil; parakeet = try ParakeetModel.fromDirectory(speechDirectory) }
        if engine.isQwen && qwenASR == nil { qwenASR = try await Qwen3ASRModel.fromModelDirectory(speechDirectory) }
        if engine == .canary && canary == nil { canary = try await CanaryModel.fromModelDirectory(speechDirectory) }
        if engine == .nemotron && nemotron == nil { nemotron = try NemotronASRModel.fromDirectory(speechDirectory) }
        if engine.isMoonshine && moonshine == nil { moonshine = try await MoonshineModel.fromModelDirectory(speechDirectory) }
        if engine.isGranite && granite == nil { granite = try await GraniteSpeechModel.fromModelDirectory(speechDirectory) }
        if engine.isWhisper && primaryWhisper == nil {
            if engine == .whisperTurbo, let vocabularyModel { primaryWhisper = vocabularyModel }
            else { primaryWhisper = try await QuibbleWhisper.WhisperModel.fromDirectory(speechDirectory) }
        }
        if withCleanup { instructionModel = nil; loadedInstructionID = nil }
        if withCleanup && cleanup == nil {
            let directory = root.appendingPathComponent("s1-mini")
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.safetensors").path) else {
                throw InferenceError.missingModel("S1-mini")
            }
            cleanup = try await LLMModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
        }
        return ProcessInfo.processInfo.systemUptime - start
    }

    public func transcribe(file: URL, root: URL, refine: Bool, engine: SpeechEngine = .cohere4bit,
        request: RefinementRequest? = nil,
        onlineAPIKey: String? = nil,
        vocabulary: [String] = [],
        vocabularyEntries: [VocabularyEntry]? = nil,
        workflow: DictationWorkflow? = nil,
        progress: (@Sendable (String) -> Void)? = nil) async throws -> InferenceResult {
        let started = ProcessInfo.processInfo.systemUptime
        let reader = try AudioChunkReader(file: file, maximumSeconds: engine.maximumAudioSectionSeconds)
        let isLong = reader.duration > engine.maximumAudioSectionSeconds
        var parts: [InferenceResult] = [], segments: [TranscriptSegment] = []
        while let chunk = try reader.next() {
            try Task.checkCancellation()
            let number = parts.count + 1
            let partProgress: (@Sendable (String) -> Void)?
            if let progress { partProgress = { stage in progress(isLong ? "\(stage) · section \(number)" : stage) } }
            else { partProgress = nil }
            var part = try await transcribeChunk(samples: chunk.samples, root: root, refine: refine, engine: engine,
                request: request, onlineAPIKey: onlineAPIKey, vocabulary: vocabulary,
                vocabularyEntries: vocabularyEntries, workflow: workflow, progress: partProgress)
            let reported = part.segments ?? []
            let valid = reported.filter { $0.isValid && $0.start < chunk.duration && $0.end <= chunk.duration + 0.1 }
            if engine.isOnline && valid.count != reported.count { throw CloudTranscriptionError.invalidResponse }
            var localSegments = valid.map { TranscriptSegment(id: $0.id, start: $0.start,
                end: min($0.end, chunk.duration), text: $0.text, speaker: $0.speaker, source: $0.source) }
            if localSegments.isEmpty && !part.raw.isEmpty {
                localSegments = [TranscriptSegment(start: 0, end: chunk.duration, text: part.raw, source: .audioChunk)]
            }
            let shifted = localSegments.enumerated().map { index, segment in
                let value = segment.offsetted(by: chunk.start,
                    speakerScope: isLong && engine == .openAIDiarize ? "Part \(number)" : nil)
                return TranscriptSegment(id: "part-\(number)-\(index)-" + String(segment.id.prefix(96)),
                    start: value.start, end: value.end, text: value.text, speaker: value.speaker, source: value.source)
            }
            segments.append(contentsOf: shifted)
            part.segments = shifted
            parts.append(part)
            Memory.clearCache()
        }
        guard let first = parts.first else { throw InferenceError.emptyAudio }
        if parts.count == 1 { return first }
        try Task.checkCancellation()
        let raw = parts.map(\.raw).filter { !$0.isEmpty }.joined(separator: " ")
        let text = parts.map(\.text).filter { !$0.isEmpty }.joined(separator: " ")
        let executedWorkflow = parts.compactMap(\.workflow).first ?? workflow
        var warnings: [String] = []
        for warning in parts.compactMap(\.warning) where !warnings.contains(warning) { warnings.append(warning) }
        if engine == .openAIDiarize { warnings.append("Speaker labels are scoped to each audio section; labels in different sections may represent the same person.") }
        if executedWorkflow?.enabledSteps.contains(where: { $0.kind == .prompt }) == true {
            warnings.append("Custom instructions were applied separately to \(parts.count) audio sections.")
        }
        var combined = InferenceResult(engine: engine.rawValue, raw: raw, text: text,
            audioSeconds: reader.duration, loadSeconds: parts.reduce(0) { $0 + $1.loadSeconds },
            transcriptionSeconds: parts.reduce(0) { $0 + $1.transcriptionSeconds },
            refinementSeconds: parts.reduce(0) { $0 + $1.refinementSeconds },
            processingSeconds: ProcessInfo.processInfo.systemUptime - started,
            peakMemoryBytes: parts.map(\.peakMemoryBytes).max() ?? 0, mode: first.mode,
            warning: warnings.isEmpty ? nil : warnings.joined(separator: " "))
        combined.workflow = executedWorkflow
        combined.segments = segments
        combined.vocabularyText = parts.compactMap(\.vocabularyText).filter { !$0.isEmpty }.joined(separator: " ")
        combined.vocabularySeconds = parts.reduce(0) { $0 + ($1.vocabularySeconds ?? 0) }
        combined.activeMemoryBytes = Memory.activeMemory
        var rawOffset = 0, changes: [VocabularyChange] = []
        for part in parts where !part.raw.isEmpty {
            changes.append(contentsOf: (part.vocabularyChanges ?? []).map {
                VocabularyChange(location: rawOffset + $0.location, length: $0.length,
                    before: $0.before, after: $0.after, explicit: $0.explicit)
            })
            rawOffset += part.raw.utf16.count + 1
        }
        combined.vocabularyChanges = changes
        let template = parts.first { !($0.stages ?? []).isEmpty }?.stages ?? []
        combined.stages = template.enumerated().map { index, stage in
            let matching = parts.compactMap { part -> WorkflowStageTrace? in
                guard let stages = part.stages, stages.indices.contains(index) else { return nil }
                return stages[index]
            }
            return WorkflowStageTrace(id: stage.id, name: stage.name, model: stage.model,
                input: matching.map(\.input).filter { !$0.isEmpty }.joined(separator: " "),
                output: matching.map(\.output).filter { !$0.isEmpty }.joined(separator: " "),
                seconds: matching.reduce(0) { $0 + $1.seconds },
                status: "\(parts.count) sections · " + Array(Set(matching.map(\.status))).sorted().joined(separator: "; "),
                prompt: stage.prompt, modelOutput: matching.compactMap(\.modelOutput).joined(separator: " "))
        }
        if let details = parts.compactMap(\.asrDetails).first {
            let generated = parts.reduce(0) { $0 + ($1.asrDetails?.generatedTokens ?? 0) }
            let prompt = parts.reduce(0) { $0 + ($1.asrDetails?.promptTokens ?? 0) }
            let energy = parts.reduce(0.0) { $0 + pow(10, ($1.asrDetails?.rmsDBFS ?? -140) / 10) * $1.audioSeconds }
            let json = try JSONEncoder().encode(segments)
            combined.asrDetails = ASRDetails(requested: details.requested, promptTokens: prompt > 0 ? prompt : nil,
                generatedTokens: generated > 0 ? generated : nil,
                tokensPerSecond: generated > 0 && combined.transcriptionSeconds > 0 ? Double(generated) / combined.transcriptionSeconds : nil,
                reportedLanguage: Array(Set(parts.compactMap { $0.asrDetails?.reportedLanguage })).sorted().joined(separator: ", "),
                segmentsJSON: String(decoding: json, as: UTF8.self),
                rmsDBFS: 10 * log10(max(energy / reader.duration, 0.000_000_000_000_01)),
                notes: details.notes + " Processed sequentially in \(parts.count) bounded audio sections; quiet boundaries were preferred.")
        }
        return combined
    }

    private func transcribeChunk(samples: [Float], root: URL, refine: Bool, engine: SpeechEngine,
        request: RefinementRequest?, onlineAPIKey: String?, vocabulary: [String],
        vocabularyEntries: [VocabularyEntry]?, workflow: DictationWorkflow?,
        progress: (@Sendable (String) -> Void)?) async throws -> InferenceResult {
        let mode = request?.mode ?? (refine ? .basic : .exact)
        var plan = workflow ?? DictationWorkflow(name: mode.title, speechModel: engine.rawValue,
            steps: [.init(kind: .vocabulary)] + (mode == .exact ? [] : [mode.needsInstructionModel ? .init(kind: .prompt, prompt: request?.instructions.isEmpty == false ? request!.instructions : "Keep edits minimal.") : .init(kind: .cleanup)]))
        if workflow == nil { plan.asr.chunkSeconds = 60 }
        guard plan.validationError == nil, plan.speechModel == engine.rawValue else { throw InferenceError.invalidRefinement }
        let options = plan.asr
        let entries = (vocabularyEntries ?? vocabulary.map { VocabularyEntry(preferred: $0) }).filter(\.enabled)
        let wantsVocabulary = !entries.isEmpty && plan.enabledSteps.contains { $0.kind == .vocabulary }
        if !plan.enabledSteps.contains(where: { $0.kind == .prompt }) { instructionModel = nil; loadedInstructionID = nil }
        if !plan.enabledSteps.contains(where: { $0.kind == .cleanup }) && (!wantsVocabulary || engine.isOnline) { cleanup = nil }
        if !wantsVocabulary || engine.isOnline { vocabularyModel = nil; Memory.clearCache() }
        let processingStart = ProcessInfo.processInfo.systemUptime
        try Task.checkCancellation()
        guard !samples.isEmpty, samples.count <= 960_000 else { throw InferenceError.emptyAudio }
        let audio = MLXArray(samples)
        let seconds = Double(audio.size) / 16_000
        // Digital silence should never enter a generative recognizer. This is not a full VAD.
        let rms = sqrt(mean(audio * audio)).item(Float.self)
        if rms < 0.0001 {
            return InferenceResult(engine: engine.rawValue, raw: "", text: "", audioSeconds: seconds, loadSeconds: 0,
                transcriptionSeconds: 0, refinementSeconds: 0,
                processingSeconds: ProcessInfo.processInfo.systemUptime - processingStart, peakMemoryBytes: Memory.peakMemory,
                mode: mode.rawValue, warning: nil)
        }
        progress?(engine.isOnline ? "Preparing online transcription" : "Loading speech model")
        var loadTime = try await load(root: root, withCleanup: false, engine: engine)
        try Task.checkCancellation()
        progress?(engine.isOnline ? "Transcribing with OpenAI" : "Transcribing")
        let start = ProcessInfo.processInfo.systemUptime
        let output: STTOutput
        var onlineResult: CloudTranscript?
        // Moonshine's author recommends a duration-derived cap to reduce hallucination loops.
        let effectiveTokenLimit = engine.isMoonshine
            ? min(options.maxTokens, min(511, max(16, Int(ceil(seconds * 6.5)))))
            : engine == .canary ? min(options.maxTokens, 1_000) : options.maxTokens
        let parameters = STTGenerateParameters(maxTokens: effectiveTokenLimit,
            temperature: engine.supportsTemperature ? options.temperature : 0,
            language: engine.decoderLanguage(for: options.language), chunkDuration: options.chunkSeconds)
        if engine.isOnline {
            guard let onlineAPIKey else { throw CloudTranscriptionError.missingKey }
            let wav = try OpenAITranscriptionClient.wav(samples: audio.asArray(Float.self))
            let result = try await OpenAITranscriptionClient(model: engine == .openAIDiarize ? .diarization : .transcription)
                .transcribe(wav: wav, apiKey: onlineAPIKey, language: options.language,
                    vocabulary: wantsVocabulary && engine.supportsVocabularyHints ? entries.map(\.preferred) : [])
            onlineResult = result
            output = STTOutput(text: result.text, language: result.languages.isEmpty ? nil : result.languages.joined(separator: ", "))
        } else if engine.isWhisper {
            primaryWhisper!.setVocabularyHints([])
            output = primaryWhisper!.generate(audio: audio, generationParameters: parameters)
        } else if engine.isGranite {
            // In this upstream API, language means translate TO. Nil keeps native ASR.
            output = granite!.generate(audio: audio, maxTokens: options.maxTokens, temperature: options.temperature, language: nil)
        } else if engine.isQwen {
            let languages = ["en": "English", "de": "German", "fr": "French", "es": "Spanish", "it": "Italian", "pt": "Portuguese", "ja": "Japanese", "zh": "Chinese", "ko": "Korean"]
            output = qwenASR!.generate(audio: audio, maxTokens: options.maxTokens, temperature: 0,
                context: "", language: languages[options.language] ?? "English", chunkDuration: options.chunkSeconds)
        } else {
            let model: any STTGenerationModel
            if engine.isParakeet { model = parakeet! }
            else if engine == .canary { model = canary! }
            else if engine == .nemotron { model = nemotron! }
            else if engine.isMoonshine { model = moonshine! }
            else { model = cohere! }
            output = model.generate(audio: audio, generationParameters: parameters)
        }
        let asrTime = ProcessInfo.processInfo.systemUptime - start
        try Task.checkCancellation()
        let raw = output.text.trimmingCharacters(in: .whitespacesAndNewlines)
        var warnings: [String] = []
        if engine.supportsLanguageSelection && !engine.languageCodes.contains(options.language) {
            warnings.append("This speech model does not support the saved language setting; English was used.")
        }
        if (engine.isMoonshine || engine.isGranite || engine == .canary), output.generationTokens >= effectiveTokenLimit {
            warnings.append("The speech decoder reached its token limit; this audio section may be incomplete.")
        }
        if let onlineResult, onlineResult.omittedHintCount > 0 {
            warnings.append("\(onlineResult.omittedHintCount) saved words did not fit OpenAI's hint format or Quibble's request budget.")
        }
        var text = raw, vocabularyTime = 0.0, refinementTime = 0.0
        var vocabularyResult = VocabularyEdits.resolve("", onto: raw, entries: [], normalization: nil)
        var traces: [WorkflowStageTrace] = []
        let activeIDs = Set(plan.enabledSteps.map(\.id))
        for step in plan.steps {
            try Task.checkCancellation()
            let before = text, stageStart = ProcessInfo.processInfo.systemUptime, loadBeforeStage = loadTime
            let enabled = activeIDs.contains(step.id) && !raw.isEmpty && (step.kind != .vocabulary || !entries.isEmpty)
            var stageStatus = enabled ? "Completed" : "Skipped"
            var modelOutput: String?
            if enabled {
                do {
                    switch step.kind {
                    case .vocabulary:
                        if engine.isOnline {
                            vocabularyResult = VocabularyEdits.resolve("", onto: before, entries: entries, normalization: nil)
                            text = vocabularyResult.text
                            stageStatus = engine.supportsVocabularyHints ? "\(onlineResult?.hintCount ?? 0) ASR hints · explicit rules applied" : "Explicit rules applied · ASR hints unavailable"
                            break
                        }
                        progress?("Checking saved spellings")
                        let directory = root.appendingPathComponent("whisper-turbo-vocabulary-4bit")
                        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.safetensors").path) else { throw InferenceError.missingModel("Vocabulary audio helper") }
                        if vocabularyModel == nil {
                            let helperLoadStart = ProcessInfo.processInfo.systemUptime
                            if engine == .whisperTurbo { vocabularyModel = primaryWhisper }
                            else { vocabularyModel = try await QuibbleWhisper.WhisperModel.fromDirectory(directory) }
                            loadTime += ProcessInfo.processInfo.systemUptime - helperLoadStart
                        }
                        let included = vocabularyModel!.setVocabularyHints(entries.map(\.preferred))
                        let hypothesis = vocabularyModel!.generate(audio: audio,
                            generationParameters: STTGenerateParameters(maxTokens: 256, language: options.language)).text
                        modelOutput = hypothesis
                        try Task.checkCancellation()
                        let proposals = VocabularyEdits.project(hypothesis, onto: before, entries: entries)
                        var normalization: String?
                        if proposals.changes.contains(where: VocabularyEdits.needsNormalization) {
                            do {
                                loadTime += try await load(root: root, withCleanup: true, engine: engine)
                                normalization = try await normalize(before)
                            } catch is CancellationError { throw CancellationError() }
                            catch { warnings.append("Ambiguous spelling changes were skipped because S1-mini is unavailable.") }
                        }
                        vocabularyResult = VocabularyEdits.resolve(hypothesis, onto: before, entries: entries, normalization: normalization)
                        text = vocabularyResult.text
                        if included < entries.count { warnings.append("The vocabulary prompt fits \(included) of \(entries.count) words.") }
                    case .cleanup:
                        progress?("Loading cleanup model")
                        loadTime += try await load(root: root, withCleanup: true, engine: engine)
                        progress?("Cleaning up")
                        text = try await normalize(before)
                        modelOutput = text
                    case .prompt:
                        progress?("Loading instruction model")
                        let loadStart = ProcessInfo.processInfo.systemUptime
                        try await loadInstructionModel(root: root, modelID: step.model)
                        loadTime += ProcessInfo.processInfo.systemUptime - loadStart
                        progress?("Applying custom prompt")
                        let instruction = workflow == nil ? request ?? RefinementRequest(mode: .custom, instructions: step.prompt) : RefinementRequest(mode: .custom, instructions: step.prompt)
                        text = try await refineContext(before, request: instruction)
                        modelOutput = text
                    }
                    guard DictationWorkflow.isUsableOutput(text) else { throw InferenceError.invalidRefinement }
                    if step.kind != .vocabulary && !VocabularyProcessor.preservesTerms(in: text, from: vocabularyResult) {
                        text = before; stageStatus = "Kept input: saved spelling changed"
                        warnings.append("\(step.kind.title) changed a saved spelling; kept its input.")
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    text = before; stageStatus = "Failed: input retained"
                    if step.kind == .vocabulary {
                        vocabularyResult = VocabularyEdits.resolve("", onto: before, entries: entries, normalization: nil)
                        text = vocabularyResult.text
                        stageStatus = "Audio check unavailable: explicit rules applied"
                    }
                    warnings.append("\(step.kind.title): " + error.localizedDescription)
                }
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - stageStart
            let generationSeconds = max(0, elapsed - (loadTime - loadBeforeStage))
            if step.kind == .vocabulary { vocabularyTime += generationSeconds } else { refinementTime += generationSeconds }
            traces.append(WorkflowStageTrace(id: step.id, name: step.kind.title, model: step.modelID(speechModel: plan.speechModel),
                input: before, output: text, seconds: enabled ? elapsed : 0, status: stageStatus,
                prompt: step.kind == .prompt ? step.prompt : nil, modelOutput: modelOutput))
        }
        let warning = warnings.isEmpty ? nil : warnings.joined(separator: " ")
        let prepared = vocabularyResult.text
        try Task.checkCancellation()
        var result = InferenceResult(engine: engine.rawValue, raw: raw, text: text, audioSeconds: seconds, loadSeconds: loadTime,
            transcriptionSeconds: asrTime, refinementSeconds: refinementTime,
            processingSeconds: ProcessInfo.processInfo.systemUptime - processingStart,
            peakMemoryBytes: Memory.peakMemory, mode: warning == nil ? (workflow?.id ?? mode.rawValue) : "workflow-fallback", warning: warning)
        result.vocabularyText = prepared
        result.vocabularyChanges = vocabularyResult.changes
        result.vocabularySeconds = vocabularyTime
        result.activeMemoryBytes = Memory.activeMemory
        result.workflow = plan; result.stages = traces
        if let onlineSegments = onlineResult?.segments { result.segments = onlineSegments }
        else if let modelSegments = output.segments {
            let values = TranscriptSegment.fromModelSegments(modelSegments, source: engine.isParakeet || engine == .nemotron ? .model : .audioChunk)
            if !values.isEmpty { result.segments = values }
        }
        var segmentsJSON: String?
        if let segments = output.segments, JSONSerialization.isValidJSONObject(segments),
           let data = try? JSONSerialization.data(withJSONObject: segments, options: [.prettyPrinted, .sortedKeys]) {
            segmentsJSON = String(decoding: data, as: UTF8.self)
        }
        result.asrDetails = ASRDetails(requested: options,
            promptTokens: output.promptTokens > 0 ? output.promptTokens : nil,
            generatedTokens: output.generationTokens > 0 ? output.generationTokens : nil,
            tokensPerSecond: output.generationTps > 0 ? output.generationTps : nil,
            reportedLanguage: output.language, segmentsJSON: segmentsJSON,
            rmsDBFS: 20 * log10(Double(max(rms, 0.0000001))), notes: engine.decoderNotes)
        return result
    }

    public func loadInstructionModel(root: URL, modelID: String = "qwen3-4b-instruct-4bit") async throws {
        if loadedRoot != root { cohere = nil; parakeet = nil; qwenASR = nil; primaryWhisper = nil; canary = nil; nemotron = nil; moonshine = nil; granite = nil; cleanup = nil; instructionModel = nil; vocabularyModel = nil; loadedRoot = root }
        cleanup = nil
        guard ["qwen3-4b-instruct-4bit", "qwen3-0.6b-4bit", "qwen3-1.7b-4bit"].contains(modelID) else { throw InferenceError.missingModel(modelID) }
        if loadedInstructionID != modelID { instructionModel = nil; loadedInstructionID = modelID; Memory.clearCache() }
        guard instructionModel == nil else { return }
        let directory = root.appendingPathComponent(modelID)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.safetensors").path) else {
            throw InferenceError.missingModel(modelID)
        }
        instructionModel = try await LLMModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
    }

    public func refineContext(_ transcript: String, request: RefinementRequest) async throws -> String {
        guard let instructionModel else { throw InferenceError.missingModel("Qwen3 4B Instruct · 4-bit") }
        let tokens = await instructionModel.encode(transcript)
        guard tokens.count < 900 else { throw InferenceError.inputTooLong }
        let input = try await instructionModel.prepare(input: UserInput(chat: [
            .system(request.systemPrompt), .user(try request.userData(transcript: transcript))
        ], additionalContext: ["enable_thinking": false]))
        let stream = try await instructionModel.generate(input: input,
            parameters: GenerateParameters(maxTokens: max(96, tokens.count * 2 + 48), temperature: 0))
        var output = ""
        var finished: Bool?
        for await event in stream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text): output += text
            case .info(let info): finished = info.stopReason == .stop
            default: break
            }
        }
        guard let clean = RefinementCompletion.text(output, stoppedNormally: finished) else { throw InferenceError.invalidRefinement }
        return clean
    }

    /// An explicit diagnostic seam for forcing token exhaustion in the real cleanup path.
    /// It loads only the provided S1-mini folder; it does not alter a mode or the ASR model.
    public func benchmarkCleanup(_ transcript: String, directory: URL, maxTokens: Int) async throws -> String {
        guard (1...2048).contains(maxTokens) else { throw InferenceError.invalidRefinement }
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("model.safetensors").path) else {
            throw InferenceError.missingModel("S1-mini")
        }
        let model = try await LLMModelFactory.shared.loadContainer(from: directory, using: LocalTokenizerLoader())
        return try await normalize(transcript, model: model, maxTokens: maxTokens)
    }

    private func normalize(_ transcript: String, model: ModelContainer? = nil, maxTokens: Int? = nil) async throws -> String {
        guard let cleanup = model ?? cleanup else { throw InferenceError.missingModel("S1-mini") }
        let tokens = await cleanup.encode(transcript)
        guard tokens.count < 900 else { throw InferenceError.inputTooLong }
        let system = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."
        let input = try await cleanup.prepare(input: UserInput(chat: [
            .system(system),
            .user("[Styling: semi-formal] [Structure: prose] [Context: general]\n" + transcript)
        ], additionalContext: ["enable_thinking": false]))
        let stream = try await cleanup.generate(input: input,
            parameters: GenerateParameters(maxTokens: maxTokens ?? Int(Double(tokens.count) * 1.3) + 32, temperature: 0))
        var output = ""
        var finished: Bool?
        for await event in stream {
            try Task.checkCancellation()
            switch event {
            case .chunk(let text): output += text
            case .info(let info): finished = info.stopReason == .stop
            default: break
            }
        }
        guard let clean = RefinementCompletion.text(output, stoppedNormally: finished) else { throw InferenceError.invalidRefinement }
        return clean
    }
}
