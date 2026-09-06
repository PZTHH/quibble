// Offline regression harness for the app-owned ModelLibrary; compile this file
// with App/ModelLibrary.swift and the built QuibbleCore module. It never starts a
// network request: queued requests are cancelled before the actor can run them.
import Foundation
import QuibbleCore

@main struct ModelLibrarySetupHarness {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Quibble-Setup-Test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let catalog = root.appendingPathComponent("catalog.json")
        let data = Data("""
        {"models":[
          {"name":"speech","title":"Speech","repository":"unused/offline","revision":"pinned","files":["model.bin"],"category":"Speech recognition","variant":"Test","gigabytes":0.1,"detail":"Offline test"},
          {"name":"helper","title":"Helper","repository":"unused/offline","revision":"pinned","files":["model.bin"],"category":"Speech recognition","variant":"Test","gigabytes":0.1,"detail":"Offline test"},
          {"name":"cleanup","title":"Cleanup","repository":"unused/offline","revision":"pinned","files":["model.bin"],"category":"Text","variant":"Test","gigabytes":0.1,"detail":"Offline test"}
        ]}
        """.utf8)
        try data.write(to: catalog)
        let library = ModelLibrary(catalogURL: catalog)
        precondition(library.models.count == 3)
        let speech = library.models[0], helper = library.models[1], cleanup = library.models[2]
        let modelsRoot = root.appendingPathComponent("models")
        let speechRoot = modelsRoot.appendingPathComponent(speech.name)
        try FileManager.default.createDirectory(at: speechRoot, withIntermediateDirectories: true)
        try Data([1]).write(to: speechRoot.appendingPathComponent("model.bin"))

        library.downloadSetup([speech, helper, cleanup, helper], root: modelsRoot)
        precondition(library.downloading == "helper", "Installed speech must be skipped")
        precondition(library.queuedDownloads == ["cleanup"], "Queue must be ordered and unique")
        precondition(library.downloadOutcome == .inProgress)
        library.downloadSetup([cleanup], root: root.appendingPathComponent("wrong-root"))
        library.download(cleanup, root: root.appendingPathComponent("wrong-root"))
        precondition(library.downloading == "helper" && library.queuedDownloads == ["cleanup"],
                     "A second action must not replace the active queue or its root")
        library.cancelDownload()
        precondition(library.queuedDownloads.isEmpty)
        await waitForCompletion(library)
        precondition(library.downloadOutcome == .cancelled)
        precondition(library.installed == ["speech"])
        precondition(!FileManager.default.fileExists(atPath: root.appendingPathComponent("wrong-root").path))
        precondition(!FileManager.default.fileExists(atPath: modelsRoot.appendingPathComponent("helper").path))

        // All required files already exist: no task is started and readiness is explicit.
        library.downloadSetup([speech, speech], root: modelsRoot)
        precondition(library.downloadOutcome == .completed && library.downloading == nil)

        // One incomplete directory blocks the whole setup before another download starts.
        let cleanupRoot = modelsRoot.appendingPathComponent("cleanup")
        try FileManager.default.createDirectory(at: cleanupRoot, withIntermediateDirectories: true)
        let ownerFile = cleanupRoot.appendingPathComponent("keep.txt")
        try Data("user file".utf8).write(to: ownerFile)
        library.downloadSetup([helper, cleanup], root: modelsRoot)
        guard case .failed(let failure) = library.downloadOutcome else { fatalError("Expected a folder conflict") }
        precondition(failure.contains("incomplete cleanup folder"))
        precondition(library.downloading == nil && library.queuedDownloads.isEmpty)
        let preserved = try String(contentsOf: ownerFile, encoding: .utf8)
        precondition(preserved == "user file", "An incomplete folder must never be replaced")

        // A spec from another catalog is not silently ignored or trusted as a URL source.
        let unknownData = try JSONEncoder().encode(helper)
        let unknownJSON = String(decoding: unknownData, as: UTF8.self).replacingOccurrences(of: "\"helper\"", with: "\"future-model\"")
        let unknown = try JSONDecoder().decode(LocalModelSpec.self, from: Data(unknownJSON.utf8))
        library.downloadSetup([unknown], root: modelsRoot)
        guard case .failed(let unavailable) = library.downloadOutcome else { fatalError("Expected unavailable model") }
        precondition(unavailable.contains("future-model") && library.downloading == nil)
        print("ModelLibrary setup: skip, ordering, concurrency, cancellation, readiness, conflicts, and unknown-model checks passed.")
    }

    @MainActor private static func waitForCompletion(_ library: ModelLibrary) async {
        for _ in 0..<100 where library.downloading != nil { await Task.yield() }
        precondition(library.downloading == nil, "Cancelled task did not settle")
    }
}
