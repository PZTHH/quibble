import Foundation
import QuibbleInference

struct RefinementBenchmark {
    struct Fixture: Codable {
        var name: String
        var transcript: String
        var application: String
        var context: String
        var instructions: String
        var vocabulary: [String]
    }
    struct Result: Codable {
        var name: String
        var original: String
        var refined: String
        var seconds: Double
    }
    static func run(_ arguments: [String]) async throws {
        guard arguments.count == 4 else { throw CocoaError(.fileReadInvalidFileName) }
        let root = URL(fileURLWithPath: arguments[1])
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[2])))
        let inference = LocalInference()
        _ = try await inference.load(root: root, withCleanup: false, engine: .cohere4bit)
        try await inference.loadInstructionModel(root: root)
        var results: [Result] = []
        for fixture in fixtures {
            let start = ProcessInfo.processInfo.systemUptime
            let request = RefinementRequest(mode: fixture.instructions.isEmpty ? .context : .custom,
                application: fixture.application, context: fixture.context, instructions: fixture.instructions, vocabulary: fixture.vocabulary)
            let text = try await inference.refineContext(fixture.transcript, request: request)
            results.append(Result(name: fixture.name, original: fixture.transcript, refined: text,
                seconds: ProcessInfo.processInfo.systemUptime - start))
            print("\(fixture.name): \(text)")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(results).write(to: URL(fileURLWithPath: arguments[3]), options: .atomic)
    }
}
