// Opt-in integration coverage for the production downloader. Downloads only
// pinned public JSON metadata (under 10 KB total), never model weights. Run with
// --allow-public-downloads; all catalog and installation paths are temporary.
import Foundation
import Combine
import Darwin
import QuibbleCore

@main struct ModelLibraryDownloadHarness {
    @MainActor static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data("Download harness failed: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    @MainActor private static func run() async throws {
        guard CommandLine.arguments.contains("--allow-public-downloads") else {
            print("Skipped. Add --allow-public-downloads to fetch tiny pinned public JSON fixtures.")
            return
        }
        struct Catalog: Decodable { let models: [LocalModelSpec] }
        let catalogURL = URL(fileURLWithPath: "App/Resources/ModelCatalog.json")
        let shippingCatalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: catalogURL))
        let source = try require(shippingCatalog.models.first { $0.name == "whisper-base-4bit" }, "Missing fixture source")
        // Exact fixture sizes come from the same pinned catalog shipped by the app.
        let configBytes = try require(source.fileBytes?["config.json"], "Config size must be pinned")
        let specialBytes = try require(source.fileBytes?["special_tokens_map.json"], "Token metadata size must be pinned")
        try check(configBytes * 3 + specialBytes < 10_000, "Fixture byte budget exceeded")

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Quibble-Download-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }

        // Both successful models must be observed in order and installed with receipts.
        let successRoot = temporary.appendingPathComponent("success")
        let success = try makeLibrary(at: temporary.appendingPathComponent("success.json"), specs: [
            fixture("first", file: "config.json", bytes: configBytes, source: source),
            fixture("second", file: "special_tokens_map.json", bytes: specialBytes, source: source)
        ])
        var order: [String] = []
        var phases: [ModelDownloadPhase] = []
        let phaseObservation = success.$downloadPhase.sink { phases.append($0) }
        let observation = success.$downloading.sink { value in
            if let value, order.last != value { order.append(value) }
        }
        success.downloadSetup(success.models, root: successRoot)
        try await settle(success)
        try check(success.downloadOutcome == .completed, "Success queue failed: \(success.message)")
        try check(order == ["first", "second"], "Success queue ran out of order: \(order)")
        try check(success.installed == ["first", "second"], "Success queue did not install both models")
        try check(phases.contains(.preparing) && phases.contains(.checking), "Download preparation/checking phases were not exposed")
        try check(success.downloadPhase == .idle && success.bytesPerSecond == nil, "Completed download retained active transfer feedback")
        try check(success.bytesReceived == specialBytes && success.expectedBytes == specialBytes,
                  "Visible byte counts must describe the completed model, not a stale earlier file")
        for spec in success.models { try verifyReceipt(spec, root: successRoot) }
        try verifyNoStaging(successRoot)
        observation.cancel()
        phaseObservation.cancel()
        print("PASS: two real downloads installed in sequence, with receipts and staging cleanup.")

        // A real 404 on the second model must retain the completed first model and
        // never start the third. This intentionally tests the HTTP failure path.
        let failureRoot = temporary.appendingPathComponent("failure")
        let failure = try makeLibrary(at: temporary.appendingPathComponent("failure.json"), specs: [
            fixture("kept", file: "config.json", bytes: configBytes, source: source),
            fixture("broken", file: "quibble-fixture-deliberately-missing-20260906.json", bytes: nil, source: source),
            fixture("never-started", file: "special_tokens_map.json", bytes: specialBytes, source: source)
        ])
        var failureOrder: [String] = []
        let failureObservation = failure.$downloading.sink { value in
            if let value, failureOrder.last != value { failureOrder.append(value) }
        }
        failure.downloadSetup(failure.models, root: failureRoot)
        try await settle(failure)
        guard case .failed(let reason) = failure.downloadOutcome else { throw HarnessError("Expected HTTP failure") }
        try check(reason.contains("incomplete"), "HTTP failure was not actionable: \(reason)")
        try check(failureOrder == ["kept", "broken"], "Failure did not stop the queue: \(failureOrder)")
        try check(failure.installed == ["kept"] && failure.queuedDownloads.isEmpty, "Failure lost completed files or retained queued items")
        try verifyReceipt(failure.models[0], root: failureRoot)
        try check(!FileManager.default.fileExists(atPath: failureRoot.appendingPathComponent("broken").path), "Failed model was published")
        try check(!FileManager.default.fileExists(atPath: failureRoot.appendingPathComponent("never-started").path), "Third model started after failure")
        try verifyNoStaging(failureRoot)
        failureObservation.cancel()
        print("PASS: actual second-model HTTP failure stops the queue and preserves the first model.")

        // Cancel immediately after the first real transfer is committed. Unlike
        // the offline harness, this exercises completion and cancellation cleanup.
        let cancelRoot = temporary.appendingPathComponent("cancel")
        let cancel = try makeLibrary(at: temporary.appendingPathComponent("cancel.json"), specs: [
            fixture("completed", file: "config.json", bytes: configBytes, source: source),
            fixture("cancelled", file: "special_tokens_map.json", bytes: specialBytes, source: source)
        ])
        var didCancel = false
        let cancellation = cancel.$progress.sink { value in
            if value == 1 && !didCancel { didCancel = true; cancel.cancelDownload() }
        }
        cancel.downloadSetup(cancel.models, root: cancelRoot)
        try await settle(cancel)
        try check(didCancel && cancel.downloadOutcome == .cancelled, "Expected cancellation after a real completion")
        try check(cancel.installed == ["completed"] && cancel.queuedDownloads.isEmpty, "Cancellation did not preserve only the completed model")
        try verifyReceipt(cancel.models[0], root: cancelRoot)
        try check(!FileManager.default.fileExists(atPath: cancelRoot.appendingPathComponent("cancelled").path), "Queued download continued after cancellation")
        try verifyNoStaging(cancelRoot)
        cancellation.cancel()
        print("PASS: cancellation after an actual transfer keeps its receipt and prevents the next transfer.")
        print("Downloaded fixture bodies: \(configBytes * 3 + specialBytes) bytes, plus one small HTTP error body. Temporary files removed on exit.")
    }

    private static func fixture(_ name: String, file: String, bytes: Int64?, source: LocalModelSpec) -> [String: Any] {
        var result: [String: Any] = ["name": name, "title": name, "repository": source.repository, "revision": source.revision,
            "files": [file], "category": "Speech recognition", "variant": "Integration fixture", "gigabytes": 0.00001,
            "detail": "Temporary metadata fixture; not a usable model."]
        if let bytes { result["fileBytes"] = [file: bytes] }
        if let asset = source.fileSources?[file] {
            result["fileSources"] = [file: ["repository": asset.repository, "revision": asset.revision]]
        }
        return result
    }

    @MainActor private static func makeLibrary(at url: URL, specs: [[String: Any]]) throws -> ModelLibrary {
        try JSONSerialization.data(withJSONObject: ["models": specs]).write(to: url)
        let library = ModelLibrary(catalogURL: url)
        try check(library.models.count == specs.count, "Fixture catalog could not be read")
        return library
    }

    @MainActor private static func settle(_ library: ModelLibrary) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        while library.downloading != nil && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        if library.downloading != nil {
            library.cancelDownload()
            for _ in 0..<100 where library.downloading != nil { try await Task.sleep(for: .milliseconds(20)) }
            throw HarnessError("Timed out: \(library.message)")
        }
    }

    private static func verifyReceipt(_ spec: LocalModelSpec, root: URL) throws {
        let receiptURL = root.appendingPathComponent(spec.name).appendingPathComponent("catalog-receipt.json")
        let receipt = try JSONDecoder().decode(LocalModelSpec.self, from: Data(contentsOf: receiptURL))
        try check(receipt.name == spec.name && receipt.revision == spec.revision, "Missing or incorrect catalog receipt")
        for file in spec.files {
            let size = try root.appendingPathComponent(spec.name).appendingPathComponent(file).resourceValues(forKeys: [.fileSizeKey]).fileSize
            try check(Int64(size ?? 0) == spec.fileBytes?[file], "Installed fixture size changed")
        }
    }

    private static func verifyNoStaging(_ root: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(atPath: root.path)
        try check(!entries.contains { $0.hasPrefix(".download-") }, "Staging files were left behind")
    }

    private static func require<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw HarnessError(message) }; return value
    }
    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw HarnessError(message) }
    }
    private struct HarnessError: LocalizedError { let errorDescription: String?; init(_ message: String) { errorDescription = message } }
}
