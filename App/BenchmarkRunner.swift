import Foundation
import QuibbleInference
import QuibbleCore

enum BenchmarkRunner {
    struct Report: Codable {
        let recordedAt: Date
        let hardware: String
        let operatingSystem: String
        let sourceFile: String
        let note: String
        let runs: [InferenceResult]
    }
    static func run(arguments: [String]) async throws {
        guard arguments.count >= 4 else {
            throw NSError(domain: "Quibble", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Usage: Quibble --benchmark MODELS AUDIO OUTPUT.json [--engine MODEL_ID] [--cleanup] [--runs N]"])
        }
        let root = URL(fileURLWithPath: arguments[1]), audio = URL(fileURLWithPath: arguments[2])
        let output = URL(fileURLWithPath: arguments[3]), cleanup = arguments.contains("--cleanup")
        var count = 3
        if let index = arguments.firstIndex(of: "--runs"), arguments.indices.contains(index + 1) {
            count = Int(arguments[index + 1]) ?? 3
        }
        count = min(20, max(1, count))
        var vocabulary: [String] = []
        if let index = arguments.firstIndex(of: "--vocabulary"), arguments.indices.contains(index + 1) {
            vocabulary = arguments[index + 1].split(separator: ";").map(String.init)
        }
        var selectedEngine: SpeechEngine = arguments.contains("--qwen-asr") ? .qwenASR : arguments.contains("--parakeet") ? .parakeet : .cohere4bit
        if let index = arguments.firstIndex(of: "--engine"), arguments.indices.contains(index + 1) {
            guard let value = SpeechEngine(rawValue: arguments[index + 1]) else { throw InferenceError.missingModel(arguments[index + 1]) }
            selectedEngine = value
        }
        var workflow: DictationWorkflow?
        if let index = arguments.firstIndex(of: "--workflow-file"), arguments.indices.contains(index + 1) {
            let candidate = try JSONDecoder().decode(DictationWorkflow.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])))
            guard candidate.validationError == nil, let engine = SpeechEngine(rawValue: candidate.speechModel) else { throw InferenceError.invalidRefinement }
            workflow = candidate; selectedEngine = engine
        }
        let engine = LocalInference()
        var entries: [VocabularyEntry] = []
        if let index = arguments.firstIndex(of: "--vocabulary-file"), arguments.indices.contains(index + 1) {
            entries = try JSONDecoder().decode(VocabularyArchive.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[index + 1]))).validated()
            vocabulary = entries.filter(\.enabled).map(\.preferred)
        }
        if entries.isEmpty { entries = vocabulary.map { VocabularyEntry(preferred: $0) } }
        var runs: [InferenceResult] = []
        for index in 0..<count {
            let result = try await engine.transcribe(file: audio, root: root, refine: cleanup,
                engine: selectedEngine, vocabulary: vocabulary,
                vocabularyEntries: entries, workflow: workflow)
            runs.append(result)
            print(String(format: "Run %d: load %.3fs, ASR %.3fs, cleanup %.3fs", index + 1,
                result.loadSeconds, result.transcriptionSeconds, result.refinementSeconds))
            print(result.text)
        }
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("machdep.cpu.brand_string", &bytes, &size, nil, 0)
        let report = Report(recordedAt: Date(), hardware: String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            sourceFile: audio.lastPathComponent,
            note: "File processing only; first run includes cold model loading. No microphone, Accessibility, or insertion exercised. Peak MLX memory is process-wide, not total resident memory.", runs: runs)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(report).write(to: output, options: .atomic)
        print("Saved \(output.path)")
        if arguments.contains("--verify-unload") {
            let before = await engine.memoryUsage()
            await engine.unload()
            let after = await engine.memoryUsage()
            let data = try JSONSerialization.data(withJSONObject: ["before": before, "after": after], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: output.deletingPathExtension().appendingPathExtension("memory.json"))
        }
    }
}
