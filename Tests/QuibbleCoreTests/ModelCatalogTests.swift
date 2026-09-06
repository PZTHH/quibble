import XCTest
@testable import QuibbleCore

final class ModelCatalogTests: XCTestCase {
    func testShippedCatalogDecodesAndEveryModelCanBeUsedInAWorkflow() throws {
        struct Catalog: Decodable { let models: [LocalModelSpec] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let models = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/ModelCatalog.json"))).models
        let requiredSpeechModels: Set<String> = ["cohere-4bit", "cohere-8bit", "cohere", "parakeet", "parakeet-8bit",
            "qwen3-asr-4bit", "qwen3-asr-8bit", "qwen3-asr-06b-4bit", "qwen3-asr-06b-8bit",
            "whisper-turbo-vocabulary-4bit", "whisper-turbo-vocabulary-8bit",
            "whisper-large-vocabulary-4bit", "whisper-large-vocabulary-8bit",
            "whisper-small-4bit", "whisper-small-8bit", "whisper-base-4bit", "whisper-base-8bit",
            "canary-v2-8bit", "nemotron-35-8bit", "moonshine-tiny", "moonshine-base",
            "granite-4-speech-4bit", "granite-4-speech-5bit", "granite-4-speech-8bit"]
        XCTAssertEqual(Set(models.filter { $0.role == "Speech" }.map(\.name)), requiredSpeechModels)
        XCTAssertEqual(Set(models.map(\.name)).count, models.count)
        for model in models {
            XCTAssertTrue(model.gigabytes.isFinite && model.gigabytes > 0)
            XCTAssertEqual(model.revision.count, 40)
            let workflow = model.role == "Speech" ? DictationWorkflow(name: "Test", speechModel: model.name) : DictationWorkflow(name: "Test", steps: [model.name == "s1-mini" ? .init(kind: .cleanup) : .init(kind: .prompt, model: model.name, prompt: "Use bullets")])
            XCTAssertNil(workflow.validationError, model.name)
        }
    }
}

extension ModelCatalogTests {
    func testEverySpeechFamilyHasMeasuredResultsOrAnExplicitMissingDataReason() throws {
        struct Catalog: Decodable { let models: [LocalModelSpec] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let models = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/ModelCatalog.json"))).models
        let benchmarks = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/ASRBenchmarks.json")))
        let missingIDs: Set<String> = ["whisper-base-4bit", "whisper-small-4bit", "moonshine-base"]
        XCTAssertEqual(Set(benchmarks.unavailable?.map(\.modelID) ?? []), missingIDs)
        for model in models where model.role == "Speech" {
            if let missing = benchmarks.unavailableResult(for: model.benchmarkID) {
                XCTAssertNil(benchmarks.accuracyStanding(for: model.benchmarkID), model.name)
                XCTAssertNil(benchmarks.speedStanding(for: model.benchmarkID), model.name)
                XCTAssertFalse(missing.evaluatedModel.isEmpty, model.name)
                XCTAssertFalse(missing.reason.isEmpty, model.name)
            } else {
                XCTAssertNotNil(benchmarks.accuracyStanding(for: model.benchmarkID), model.name)
                XCTAssertNotNil(benchmarks.speedStanding(for: model.benchmarkID), model.name)
            }
        }
        XCTAssertNil(benchmarks.unavailableResult(for: "unknown-checkpoint"))
    }

    func testMissingDataMetadataIsOptionalAndNeverOverridesPublishedMeasurements() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/ASRBenchmarks.json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "unavailable")
        let legacy = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.unavailableResult(for: "moonshine-base"))
        XCTAssertNil(legacy.accuracyStanding(for: "moonshine-base"))
        json["unavailable"] = [["modelID": "cohere", "evaluatedModel": "CohereLabs/cohere-transcribe-03-2026", "reason": "Stale missing-data note"]]
        let measured = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(measured.unavailableResult(for: "cohere"))
        XCTAssertNotNil(measured.accuracyStanding(for: "cohere"))
        XCTAssertNotNil(measured.speedStanding(for: "cohere"))
    }

    func testPublishedSpeedUsesHFCohortAndRewardsHigherThroughput() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/ASRBenchmarks.json"))
        let catalog = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: data)
        XCTAssertEqual(catalog.speedBenchmark?.hardware, "NVIDIA H200")
        XCTAssertEqual(catalog.speedBenchmark?.scope, catalog.task)
        XCTAssertEqual(catalog.speedRTFx(for: "parakeet"), 6076.07)
        XCTAssertEqual(catalog.speedRTFx(for: "cohere-4bit"), 906.56)
        XCTAssertEqual(catalog.speedStanding(for: "parakeet")?.position, 1)
        XCTAssertEqual(catalog.speedStanding(for: "cohere"), catalog.speedStanding(for: "cohere-4bit"))
        XCTAssertLessThan(try XCTUnwrap(catalog.speedStanding(for: "cohere")?.position), try XCTUnwrap(catalog.speedStanding(for: "whisper-turbo-vocabulary-4bit")?.position))
        XCTAssertLessThan(try XCTUnwrap(catalog.speedRTFx(for: "whisper-large-vocabulary-4bit")), try XCTUnwrap(catalog.speedRTFx(for: "whisper-turbo-vocabulary-4bit")))
        XCTAssertNil(catalog.speedRTFx(for: "whisper-base-4bit"))
        XCTAssertNil(catalog.speedStanding(for: "whisper-small-4bit"))
        XCTAssertNil(catalog.speedStanding(for: "s1-mini"))
    }

    func testSpeedRequiresPositiveMeasurementsAndAnExplicitBenchmarkScope() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/ASRBenchmarks.json"))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var rows = try XCTUnwrap(json["results"] as? [[String: Any]])
        for index in rows.indices { rows[index]["rtfx"] = rows[index]["modelID"] as? String == "parakeet" ? 0 : -1 }
        json["results"] = rows
        let unavailable = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(unavailable.speedRTFx(for: "parakeet"))
        XCTAssertNil(unavailable.speedStanding(for: "cohere"))
        json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "speedBenchmark")
        let unscoped = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(unscoped.speedRTFx(for: "parakeet"))
        XCTAssertNil(unscoped.speedStanding(for: "parakeet"))
    }

    func testAccuracyStandingRewardsLowerErrorAndKeepsSharedScoresEqual() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/ASRBenchmarks.json"))
        let catalog = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: data)
        XCTAssertEqual(catalog.accuracyStanding(for: "qwen3-asr-4bit")?.position, 1)
        XCTAssertEqual(catalog.accuracyStanding(for: "cohere")?.position, 2)
        XCTAssertEqual(catalog.accuracyStanding(for: "cohere"), catalog.accuracyStanding(for: "cohere-4bit"))
        XCTAssertLessThan(try XCTUnwrap(catalog.accuracyStanding(for: "parakeet")?.position), try XCTUnwrap(catalog.accuracyStanding(for: "whisper-turbo-vocabulary-4bit")?.position))
        XCTAssertNil(catalog.accuracyStanding(for: "whisper-base-4bit"))
    }

    func testPublishedASRResultsKeepTheirScopeAndMissingModels() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/ASRBenchmarks.json"))
        let benchmarks = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: data)
        XCTAssertEqual(benchmarks.sourceRevision, "eec9efdf93683faf1dfb36c7d77b3c12d746215e")
        XCTAssertEqual(benchmarks.task, "English short-form · 8 public datasets")
        XCTAssertEqual(benchmarks.results.count, 11)
        XCTAssertEqual(Set(benchmarks.results.map(\.modelID)).count, benchmarks.results.count)
        XCTAssertEqual(benchmarks.result(for: "cohere-4bit")?.werPercent, 4.67)
        XCTAssertEqual(benchmarks.result(for: "qwen3-asr-4bit")?.evaluatedModel, "Qwen/Qwen3-ASR-1.7B-hf")
        XCTAssertNil(benchmarks.result(for: "whisper-base-4bit"))
        XCTAssertNil(benchmarks.result(for: "whisper-small-4bit"))
        XCTAssertNil(benchmarks.result(for: "s1-mini"))
        for result in benchmarks.results {
            XCTAssertTrue(result.werPercent.isFinite && result.werPercent >= 0)
            XCTAssertTrue(result.sourceURL.contains(benchmarks.sourceRevision))
            XCTAssertTrue(result.note.contains("Upstream"))
        }
    }
}

extension ModelCatalogTests {
    func testQuantizedVariantsKeepCheckpointIdentityAndMissingScoresHonest() throws {
        struct Catalog: Decodable { let models: [LocalModelSpec] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let models = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/ModelCatalog.json"))).models
        let benchmarks = try JSONDecoder().decode(ASRBenchmarkCatalog.self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/ASRBenchmarks.json")))
        let q4 = try XCTUnwrap(models.first { $0.name == "qwen3-asr-4bit" })
        let q8 = try XCTUnwrap(models.first { $0.name == "qwen3-asr-8bit" })
        let small = try XCTUnwrap(models.first { $0.name == "qwen3-asr-06b-8bit" })
        XCTAssertEqual(q4.logicalModelID, q8.logicalModelID)
        XCTAssertNotEqual(q8.logicalModelID, small.logicalModelID)
        XCTAssertEqual(q4.benchmarkID, q8.benchmarkID)
        XCTAssertEqual(q8.weightBits, 8)
        XCTAssertGreaterThan(q8.gigabytes, q4.gigabytes)
        let moonshine = try XCTUnwrap(models.first { $0.name == "moonshine-base" })
        XCTAssertNil(moonshine.weightBits)
        XCTAssertNil(benchmarks.result(for: moonshine.benchmarkID))
        let canary = try XCTUnwrap(benchmarks.result(for: "canary-v2-8bit"))
        XCTAssertEqual(canary.evaluatedModel, "nvidia/canary-1b-v2")
        XCTAssertEqual(canary.werPercent, 5.70625)
        XCTAssertEqual(benchmarks.result(for: "nemotron-35-8bit")?.werPercent, 7.87625)
    }

    func testLockedDownloadsMatchCatalogAndUseFlatLocalFiles() throws {
        struct Entry: Decodable { let name: String; let repository: String; let revision: String; let files: [String] }
        struct Catalog: Decodable { let models: [Entry] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("App/Resources/ModelCatalog.json")))
        let lock = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: root.appendingPathComponent("Models.lock.json")))
        for model in catalog.models {
            let pinned = try XCTUnwrap(lock.models.first { $0.name == model.name })
            XCTAssertEqual(pinned.repository, model.repository, model.name)
            XCTAssertEqual(pinned.revision, model.revision, model.name)
            XCTAssertEqual(Set(pinned.files), Set(model.files), model.name)
            XCTAssertTrue(model.files.contains("model.safetensors"), model.name)
            XCTAssertTrue(model.files.allSatisfy { !$0.contains("/") && !$0.hasPrefix(".") }, model.name)
        }
    }
}
