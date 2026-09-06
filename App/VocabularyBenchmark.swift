import Foundation
import QuibbleInference

struct VocabularyBenchmark {
    struct Fixture: Codable {
        let text: String
        let candidates: String
        let expected: [Int]
    }
    struct Result: Codable {
        let text: String
        let response: String
        let expected: [Int]
        let seconds: Double
        let passed: Bool
    }
    static func run(_ args: [String]) async throws {
        guard args.count == 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let directory = URL(fileURLWithPath: args[1])
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let inference = LocalInference()
        var results: [Result] = []
        for fixture in fixtures {
            let start = ProcessInfo.processInfo.systemUptime
            let response = try await inference.selectVocabularyEdits(transcript: fixture.text, candidates: fixture.candidates, directory: directory)
            let selected = try? JSONDecoder().decode([Int].self, from: Data(response.utf8))
            let passed = selected.map { Set($0) == Set(fixture.expected) } ?? false
            results.append(Result(text: fixture.text, response: response, expected: fixture.expected,
                                  seconds: ProcessInfo.processInfo.systemUptime - start, passed: passed))
            print("\(passed ? "PASS" : "FAIL"): \(fixture.text) => \(response)")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    }
}

import QuibbleCore

extension VocabularyBenchmark {
    struct CPUFixture: Codable {
        let text: String
        let words: [String]
        let corrections: [String: String]
        let expected: String
    }
    @MainActor static func runCPU(_ args: [String]) throws {
        guard args.count == 3 else { throw CocoaError(.fileReadInvalidFileName) }
        let fixtures = try JSONDecoder().decode([CPUFixture].self, from: Data(contentsOf: URL(fileURLWithPath: args[1])))
        var output: [[String: Any]] = []
        for fixture in fixtures {
            let names = Set(fixture.words + Array(fixture.corrections.values))
            let entries = names.map { name in VocabularyEntry(preferred: name, aliases: fixture.corrections.filter { $0.value == name }.map(\.key)) }
            let processor = VocabularyProcessor(entries: entries)
            for index in 0..<3 {
                let start = ProcessInfo.processInfo.systemUptime
                let result = VocabularySpelling.process(fixture.text, with: processor)
                output.append(["input": fixture.text, "output": result.text, "expected": fixture.expected,
                    "run": index, "seconds": ProcessInfo.processInfo.systemUptime - start, "passed": result.text == fixture.expected])
            }
        }
        let large = VocabularyProcessor(entries: (0..<1_000).map { VocabularyEntry(preferred: "TermExample\($0)") })
        let start = ProcessInfo.processInfo.systemUptime
        for _ in 0..<100 { _ = VocabularySpelling.process("Please send the revised document to Maya before Thursday afternoon.", with: large) }
        let result: [String: Any] = ["cases": output, "thousandEntryUnrelatedSecondsPerRun": (ProcessInfo.processInfo.systemUptime - start) / 100]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
        print("CPU vocabulary: \(output.filter { $0["passed"] as? Bool == true }.count)/\(output.count) passed")
    }
}

extension VocabularyBenchmark {
    @MainActor static func runResolver(_ args: [String]) async throws {
        guard args.count == 4 || args.count == 5 else { throw CocoaError(.fileReadInvalidFileName) }
        let directory = URL(fileURLWithPath: args[1])
        let fixtures = try JSONDecoder().decode([CPUFixture].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let prompt = args.count == 5 ? try String(contentsOfFile: args[4], encoding: .utf8) : nil
        let inference = LocalInference()
        var results: [[String: Any]] = []
        for fixture in fixtures {
            let start = ProcessInfo.processInfo.systemUptime
            let rendered = prompt?.replacingOccurrences(of: "{{vocabulary}}", with: String(decoding: try JSONEncoder().encode(fixture.words), as: UTF8.self))
            let parts = rendered?.components(separatedBy: "\n---USER---\n")
            let system = parts?.first
            let payload = parts?.count == 2 ? parts![1].replacingOccurrences(of: "{{transcript}}", with: fixture.text) : nil
            let response = try await inference.proposeVocabularyEdits(transcript: fixture.text, words: fixture.words, directory: directory, prompt: system, payload: payload)
            results.append(["text": fixture.text, "response": response, "expected": fixture.expected,
                "seconds": ProcessInfo.processInfo.systemUptime - start])
            print("\(fixture.text) => \(response)")
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    }
}

extension VocabularyBenchmark {
    @MainActor static func runS1Prefixes(_ args: [String]) async throws {
        guard args.count == 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let directory = URL(fileURLWithPath: args[1])
        let fixtures = try JSONDecoder().decode([CPUFixture].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let inference = LocalInference()
        let system = "You are a text normalizer for speech-to-text transcripts. The input begins with a control line specifying the styling, structure, and context settings; clean the transcript to match those settings and output only the cleaned text."
        let control = "[Styling: semi-formal] [Structure: prose] [Context: general]\n"
        var results: [[String: Any]] = []
        for fixture in fixtures {
            let terms = fixture.words.joined(separator: ", ")
            let prefixes = ["baseline": "", "list": terms + ".\n\n",
                "reference": "Names and terms: " + terms + ".\n\n",
                "sentence": "The names and terms are " + terms + ". End of vocabulary reference.\n\n",
                "brackets": "[Vocabulary: " + terms + "]\n\n",
                "header": "Vocabulary: " + terms + ".\n\nTranscript:\n",
                "spellings": "Correct spellings: " + terms + ".\n\n",
                "repeat": Array(repeating: terms + ".", count: 3).joined(separator: " ") + "\n\n",
                "conversation": "I was talking about " + terms + ".\n\n"]
            for variant in ["brackets", "header", "spellings", "repeat", "conversation"] {
                let prefix = prefixes[variant]!
                let start = ProcessInfo.processInfo.systemUptime
                var response = "", failure = ""
                do {
                    response = try await inference.proposeVocabularyEdits(transcript: fixture.text, words: fixture.words,
                        directory: directory, prompt: system, payload: control + prefix + fixture.text)
                } catch { failure = error.localizedDescription }
                results.append(["text": fixture.text, "words": fixture.words, "variant": variant, "prefix": prefix,
                    "response": response, "error": failure, "expected": fixture.expected, "seconds": ProcessInfo.processInfo.systemUptime - start])
                try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
                print("\(variant): \(fixture.text) => \(failure.isEmpty ? response : failure)")
            }
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: args[3]), options: .atomic)
    }
}

// Uses the same entry point as live dictation, including the audio helper and ambiguity gate.
extension VocabularyBenchmark {
    private struct AudioFixture: Decodable {
        let name: String
        let audio: String
        let expected: String
    }
    private struct AudioFixtures: Decodable { let words: [String]; let cases: [AudioFixture] }
    @MainActor static func runAudio(_ args: [String]) async throws {
        guard args.count >= 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let fixtures = try JSONDecoder().decode(AudioFixtures.self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
        let root = URL(fileURLWithPath: args[1]), destination = URL(fileURLWithPath: args[3])
        let inference = LocalInference()
        let entries = fixtures.words.map { VocabularyEntry(preferred: $0) }
        let engines: [SpeechEngine] = args.contains("--all-models") ? SpeechEngine.allCases.filter { !$0.isOnline } : [.cohere4bit]
        var results: [[String: Any]] = []
        for engine in engines {
            await inference.unload()
            for fixture in fixtures.cases {
                let result = try await inference.transcribe(file: URL(fileURLWithPath: fixture.audio), root: root,
                    refine: args.contains("--cleanup"), engine: engine, vocabularyEntries: entries)
                let data = try JSONEncoder().encode(result)
                var row = try JSONSerialization.jsonObject(with: data) as! [String: Any]
                row["case"] = fixture.name; row["expected"] = fixture.expected
                row["passed"] = result.vocabularyText == fixture.expected
                results.append(row)
                try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: destination, options: .atomic)
                print("\(engine.rawValue) \(fixture.name): \(result.raw) => \(result.text)")
            }
        }
        let before = await inference.memoryUsage()
        await inference.unload()
        try JSONSerialization.data(withJSONObject: ["before": before, "after": await inference.memoryUsage()], options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.deletingPathExtension().appendingPathExtension("memory.json"), options: .atomic)
    }
}
