import XCTest
@testable import QuibbleCore

final class ModelVariantGroupTests: XCTestCase {
    private func model(_ name: String, family: String? = nil, bits: Int? = nil,
                       gigabytes: Double = 1.5, parameters: Int = 2_000_000_000,
                       preferred: Bool = false, source: String? = nil, smokeTested: Bool? = nil,
                       validation: String? = nil) throws -> LocalModelSpec {
        var json: [String: Any] = ["name": name, "repository": "publisher/model", "revision": String(repeating: "a", count: 40),
                                 "files": ["model.safetensors"], "title": name, "category": "Speech recognition",
                                 "variant": bits.map { "\($0)-bit" } ?? "FP16", "gigabytes": gigabytes,
                                 "detail": "Test model", "parameters": parameters]
        if let family { json["familyID"] = family }
        if let bits { json["quantizationBits"] = bits }
        if preferred { json["preferredVariant"] = true }
        if let source { json["artifactSource"] = source }
        if let smokeTested { json["smokeTested"] = smokeTested }
        if let validation { json["validation"] = validation }
        return try JSONDecoder().decode(LocalModelSpec.self, from: JSONSerialization.data(withJSONObject: json))
    }

    func testLegacyCohereVariantsShareOneRowWithoutCollapsingOtherModels() throws {
        let groups = ModelVariantGroup.make(from: try [model("cohere-4bit"), model("cohere"), model("parakeet")])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups.first?.variants.map(\.name), ["cohere-4bit", "cohere"])
    }

    func testRecommendationUsesEightBitOnlyWhenEstimatedWorkingSetFits() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("sample-4bit", family: "sample", bits: 4, gigabytes: 1.5),
            model("sample-8bit", family: "sample", bits: 8, gigabytes: 3.0),
            model("sample-fp16", family: "sample", gigabytes: 5.0)
        ]).first)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 48_000_000_000)?.name, "sample-8bit")
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 16_000_000_000)?.name, "sample-4bit")
    }

    func testRecommendationPreservesExplicitSelectionAndExistingQuantizedDownload() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("cohere-4bit", bits: 4), model("cohere-8bit", bits: 8, gigabytes: 3), model("cohere", gigabytes: 4.1)
        ]).first)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 48_000_000_000, selectedID: "cohere")?.name, "cohere")
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 48_000_000_000, installed: ["cohere-4bit"])?.name, "cohere-4bit")
    }

    func testDocumentedModelSpecificVariantWinsOverGenericEightBitRule() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("granite-4bit", family: "granite", bits: 4),
            model("granite-8bit", family: "granite", bits: 8),
            model("granite-5bit", family: "granite", bits: 5, preferred: true)
        ]).first)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 48_000_000_000)?.name, "granite-5bit")
    }

    func testEquivalentPublisherArtifactIsPreferredWithoutGuessingFromRepositoryName() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("converted-8bit", family: "sample", bits: 8, source: "conversion"),
            model("publisher-8bit", family: "sample", bits: 8, source: "publisher")
        ]).first)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 48_000_000_000)?.name, "publisher-8bit")
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 48_000_000_000, selectedID: "converted-8bit")?.name, "converted-8bit")
    }

    func testExplicitFamiliesKeepDifferentParameterSizesSeparate() throws {
        let groups = ModelVariantGroup.make(from: try [
            model("qwen-small-4bit", family: "qwen-small", bits: 4, parameters: 600_000_000),
            model("qwen-large-4bit", family: "qwen-large", bits: 4, parameters: 1_700_000_000),
            model("qwen-small-8bit", family: "qwen-small", bits: 8, parameters: 600_000_000),
            model("qwen-large-8bit", family: "qwen-large", bits: 8, parameters: 1_700_000_000)
        ])
        XCTAssertEqual(groups.map(\.id), ["qwen-small", "qwen-large"])
        XCTAssertEqual(groups.map { $0.variants.count }, [2, 2])
    }

    func testWritingReserveCanKeepFourBitOnAnOtherwiseLargeMemoryMac() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("sample-4bit", family: "sample", bits: 4),
            model("sample-8bit", family: "sample", bits: 8, gigabytes: 3)
        ]).first)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 48_000_000_000,
            additionalModelBytes: 15_000_000_000)?.name, "sample-4bit")
    }

    func testExtraMemoryDoesNotAutomaticallySelectFullPrecision() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [model("cohere", gigabytes: 4.1), model("cohere-4bit", bits: 4)]).first)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 128_000_000_000)?.name, "cohere-4bit")
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 128_000_000_000, installed: ["cohere"])?.name, "cohere-4bit")
    }

    func testOriginalFormatOnlyModelsRemainAvailableAndDownloadedFiveBitIsReused() throws {
        let native = try XCTUnwrap(ModelVariantGroup.make(from: [model("moonshine-tiny", gigabytes: 0.11)]).first)
        XCTAssertEqual(native.recommendedVariant(physicalMemoryBytes: 8_000_000_000)?.name, "moonshine-tiny")
        let quantized = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("sample-4bit", family: "sample", bits: 4), model("sample-5bit", family: "sample", bits: 5)
        ]).first)
        XCTAssertEqual(quantized.recommendedVariant(physicalMemoryBytes: 48_000_000_000, installed: ["sample-5bit"])?.name, "sample-5bit")
    }

    func testFullPrecisionMetadataIsNotTreatedAsAQuantizedRecommendation() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("sample-fp16", family: "sample", bits: 16, preferred: true),
            model("sample-4bit", family: "sample", bits: 4)
        ]).first)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 128_000_000_000,
            installed: ["sample-fp16"])?.name, "sample-4bit")
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 128_000_000_000,
            selectedID: "sample-fp16")?.name, "sample-fp16")
    }

    func testWritingReserveDeduplicatesModelsAndSkipsInactiveSteps() throws {
        let models = try [model("s1-mini", gigabytes: 0.8),
                          model("whisper-turbo-vocabulary-4bit", gigabytes: 0.9),
                          model("qwen3-4b-instruct-4bit", gigabytes: 2.3)]
        let workflow = DictationWorkflow(name: "Writing", steps: [
            .init(kind: .vocabulary), .init(kind: .cleanup), .init(kind: .cleanup),
            .init(kind: .prompt, enabled: false)
        ])
        XCTAssertEqual(ModelVariantGroup.additionalModelBytes(for: workflow,
            hasVocabulary: true, models: models), 3_400_000_000)
        XCTAssertEqual(ModelVariantGroup.additionalModelBytes(for: workflow,
            hasVocabulary: false, models: models), 1_600_000_000)
    }

    func testWritingReserveRemainsConservativeWhenChoosingLocalFromOnlineWorkflow() throws {
        let models = try [model("s1-mini", gigabytes: 0.8),
                          model("whisper-turbo-vocabulary-4bit", gigabytes: 0.9)]
        let workflow = DictationWorkflow(name: "Online", speechModel: "openai-transcribe",
                                         steps: [.init(kind: .vocabulary)])
        XCTAssertEqual(ModelVariantGroup.additionalModelBytes(for: workflow,
            hasVocabulary: true, models: models), 3_400_000_000)
        XCTAssertEqual(ModelVariantGroup.additionalModelBytes(for: workflow,
            hasVocabulary: false, models: models), 0)
    }

    func testSmokeTestedArtifactWinsOverUntestedHigherPrecisionWithoutOverridingUserChoices() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("sample-4bit", family: "sample", bits: 4, smokeTested: true,
                  validation: "Experimental. Local smoke tests passed; broader accuracy is unmeasured."),
            model("sample-8bit", family: "sample", bits: 8, preferred: true,
                  source: "publisher", smokeTested: false, validation: "Exact-artifact audio validation pending.")
        ]).first)
        XCTAssertTrue(try XCTUnwrap(group.variants.first).isExperimental)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 128_000_000_000)?.name, "sample-4bit")
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 128_000_000_000,
            selectedID: "sample-8bit")?.name, "sample-8bit")
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 128_000_000_000,
            installed: ["sample-8bit"])?.name, "sample-8bit")
    }

    func testPendingOnlyFamilyRemainsAvailableWithMemoryBasedRecommendation() throws {
        let group = try XCTUnwrap(ModelVariantGroup.make(from: [
            model("sample-4bit", family: "sample", bits: 4, smokeTested: false),
            model("sample-8bit", family: "sample", bits: 8, smokeTested: false)
        ]).first)
        XCTAssertEqual(group.recommendedVariant(physicalMemoryBytes: 48_000_000_000)?.name, "sample-8bit")
    }
}
