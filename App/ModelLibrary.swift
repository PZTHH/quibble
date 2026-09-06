import Foundation
import Combine
import QuibbleCore
import os

private final class ModelDownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    let update: @Sendable (Int64, Int64) -> Void
    private let lastUpdate = OSAllocatedUnfairLock(initialState: 0.0)
    init(update: @escaping @Sendable (Int64, Int64) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let now = ProcessInfo.processInfo.systemUptime
        let emit = lastUpdate.withLock { last in
            guard now - last >= 0.1 || (totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite) else { return false }
            last = now; return true
        }
        if emit { update(totalBytesWritten, totalBytesExpectedToWrite) }
    }
}

enum ModelDownloadPhase: Equatable { case idle, preparing, downloading, checking }
enum ModelDownloadOutcome: Equatable {
    case idle, inProgress, completed, cancelled
    case failed(String)
}

@MainActor
final class ModelLibrary: ObservableObject {
    let models: [LocalModelSpec]
    let benchmarks: ASRBenchmarkCatalog?
    @Published private(set) var downloading: String?
    /// Remaining model IDs after the active download. Closing setup does not cancel them.
    @Published private(set) var queuedDownloads: [String] = []
    @Published private(set) var downloadOutcome: ModelDownloadOutcome = .idle
    @Published private(set) var progress = 0.0
    @Published private(set) var downloadPhase: ModelDownloadPhase = .idle
    @Published private(set) var bytesReceived: Int64 = 0
    @Published private(set) var expectedBytes: Int64?
    @Published private(set) var bytesPerSecond: Double?
    @Published private(set) var lastProgressAt: Date?
    @Published private(set) var message = ""
    @Published private(set) var diskBytes: [String: Int64] = [:]
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var stored: Set<String> = []
    private var task: Task<Void, Never>?
    private var activeID: UUID?
    private var activeFileID: UUID?
    private var transferSampleTime = 0.0
    private var transferSampleBytes: Int64 = 0
    init(catalogURL: URL? = Bundle.main.url(forResource: "ModelCatalog", withExtension: "json")) {
        benchmarks = Bundle.main.url(forResource: "ASRBenchmarks", withExtension: "json").flatMap {
            try? JSONDecoder().decode(ASRBenchmarkCatalog.self, from: Data(contentsOf: $0))
        }
        struct Catalog: Decodable { let models: [LocalModelSpec] }
        do {
            guard let url = catalogURL else { throw CocoaError(.fileNoSuchFile) }
            models = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url)).models
        } catch { models = []; message = "The model catalog could not be loaded: \(error.localizedDescription)" }
    }
    func refresh(root: URL) {
        stored = Set(models.filter {
            FileManager.default.fileExists(atPath: root.appendingPathComponent($0.name).path)
        }.map(\.name))
        diskBytes = Dictionary(uniqueKeysWithValues: models.map { spec in
            (spec.name, spec.files.reduce(Int64(0)) { total, file in
                total + Int64((try? root.appendingPathComponent(spec.name).appendingPathComponent(file).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            })
        })
        installed = Set(models.filter { spec in
            spec.files.allSatisfy { file in
                let url = root.appendingPathComponent(spec.name).appendingPathComponent(file)
                return ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
            }
        }.map(\.name))
    }
    func download(_ spec: LocalModelSpec, root: URL) {
        guard task == nil, downloading == nil, !installed.contains(spec.name) else { return }
        downloadSetup([spec], root: root)
    }

    /// Uses the same pinned, checked downloader as the library. Resolve all IDs
    /// against the catalog before starting; caller-supplied URLs are never used.
    func downloadSetup(_ specs: [LocalModelSpec], root: URL) {
        guard task == nil, downloading == nil else { return }
        refresh(root: root)
        let plan = SetupDownloadPlan(requested: specs.map(\.name), installed: installed,
                                     available: Set(models.map(\.name)))
        guard plan.unknownIDs.isEmpty else {
            failDownload("These models are unavailable in the catalog: \(plan.unknownIDs.joined(separator: ", ")). Choose another model in Modes.")
            return
        }
        let lookup = Dictionary(uniqueKeysWithValues: models.map { ($0.name, $0) })
        let pending = plan.missingIDs.compactMap { lookup[$0] }
        guard let first = pending.first else {
            progress = 1; message = "Your models are ready."; downloadOutcome = .completed
            return
        }
        if let conflict = pending.first(where: { FileManager.default.fileExists(atPath: root.appendingPathComponent($0.name).path) }) {
            failDownload(Self.folderConflict(conflict))
            return
        }
        // Capture the root and queue once. A different folder or another model
        // cannot redirect an in-flight setup download between files.
        downloading = first.name; queuedDownloads = Array(pending.dropFirst().map(\.name))
        progress = 0; downloadOutcome = .inProgress; message = "Downloading \(first.title)…"
        task = Task {
            defer {
                queuedDownloads = []; downloading = nil; activeID = nil; activeFileID = nil; task = nil
                downloadPhase = .idle; bytesPerSecond = nil
                refresh(root: root)
            }
            do {
                for (index, spec) in pending.enumerated() {
                    try Task.checkCancellation()
                    downloading = spec.name; queuedDownloads = Array(pending.dropFirst(index + 1).map(\.name))
                    progress = 0; message = "Downloading \(spec.title)…"
                    try await downloadModel(spec, root: root)
                }
                try Task.checkCancellation()
                progress = 1; downloadOutcome = .completed
                message = pending.count == 1 ? "\(first.title) is ready." : "Your models are ready."
            } catch {
                if Task.isCancelled {
                    message = "Download cancelled. Completed models are kept."; downloadOutcome = .cancelled
                } else {
                    failDownload("Download failed. \(error.localizedDescription)")
                }
            }
        }
    }

    private func downloadModel(_ spec: LocalModelSpec, root: URL) async throws {
        let id = UUID(); activeID = id
        bytesReceived = 0; bytesPerSecond = nil; lastProgressAt = Date(); downloadPhase = .preparing
        let knownSizes = spec.files.compactMap { spec.fileBytes?[$0] }
        expectedBytes = knownSizes.count == spec.files.count && knownSizes.allSatisfy { $0 > 0 }
            ? knownSizes.reduce(Int64(0)) { total, size in total.addingReportingOverflow(size).overflow ? Int64.max : total + size } : nil
        let fm = FileManager.default
        let staging = root.appendingPathComponent(".download-\(spec.name)-\(id.uuidString)")
        let session = URLSession(configuration: .ephemeral)
        defer {
            session.invalidateAndCancel()
            try? fm.removeItem(at: staging)
            if activeID == id { activeID = nil }
            refresh(root: root)
        }
        guard !fm.fileExists(atPath: root.appendingPathComponent(spec.name).path) else {
            throw NSError(domain: "Quibble", code: 2, userInfo: [NSLocalizedDescriptionKey: Self.folderConflict(spec)])
        }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var completedBytes: Int64 = 0
        for file in spec.files {
            try Task.checkCancellation()
            let completed = completedBytes
            let fileID = UUID(); activeFileID = fileID
            transferSampleTime = ProcessInfo.processInfo.systemUptime
            transferSampleBytes = completed
            downloadPhase = .preparing; lastProgressAt = Date(); bytesPerSecond = nil
            let delegate = ModelDownloadProgress { [weak self] written, _ in
                Task { @MainActor in
                    guard let self, self.activeID == id, self.activeFileID == fileID else { return }
                    let total = completed + max(0, written)
                    guard total > self.bytesReceived else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    let elapsed = now - self.transferSampleTime
                    if elapsed >= 0.25 {
                        let rate = Double(total - self.transferSampleBytes) / elapsed
                        self.bytesPerSecond = self.bytesPerSecond.map { $0 * 0.65 + rate * 0.35 } ?? rate
                        self.transferSampleTime = now; self.transferSampleBytes = total
                    }
                    self.bytesReceived = total; self.lastProgressAt = Date(); self.downloadPhase = .downloading
                    self.progress = min(0.99, Double(completed + written) / max(1, spec.gigabytes * 1e9))
                }
            }
            let source = spec.fileSources?[file]
            guard let url = URL(string: "https://huggingface.co/\(source?.repository ?? spec.repository)/resolve/\(source?.revision ?? spec.revision)/\(file)") else {
                throw NSError(domain: "Quibble", code: 4, userInfo: [NSLocalizedDescriptionKey: "The catalog URL for \(spec.title) is invalid."])
            }
            let (temporary, response) = try await session.download(from: url, delegate: delegate)
            activeFileID = nil; downloadPhase = .checking; bytesPerSecond = nil
            defer { try? fm.removeItem(at: temporary) }
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let size = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0,
                  response.expectedContentLength <= 0 || Int64(size) == response.expectedContentLength else {
                throw NSError(domain: "Quibble", code: 1, userInfo: [NSLocalizedDescriptionKey: "The download of \(file) was incomplete."])
            }
            if let expected = spec.fileBytes?[file], Int64(size) != expected {
                throw NSError(domain: "Quibble", code: 3, userInfo: [NSLocalizedDescriptionKey: "The size of \(file) does not match the pinned catalog."])
            }
            try Task.checkCancellation()
            try fm.moveItem(at: temporary, to: staging.appendingPathComponent(file))
            completedBytes += Int64(size)
            bytesReceived = completedBytes; lastProgressAt = Date()
        }
        try Task.checkCancellation()
        let destination = root.appendingPathComponent(spec.name)
        // Never overwrite an existing directory that might contain a user's model files.
        guard !fm.fileExists(atPath: destination.path) else {
            throw NSError(domain: "Quibble", code: 2, userInfo: [NSLocalizedDescriptionKey: Self.folderConflict(spec)])
        }
        try JSONEncoder().encode(spec).write(to: staging.appendingPathComponent("catalog-receipt.json"), options: .atomic)
        try fm.moveItem(at: staging, to: destination)
        progress = 1
    }

    private static func folderConflict(_ spec: LocalModelSpec) -> String {
        "An incomplete \(spec.name) folder already exists. Choose another model folder or move that folder before downloading."
    }

    private func failDownload(_ reason: String) {
        message = reason; downloadOutcome = .failed(reason)
    }

    func cancelDownload() { queuedDownloads = []; task?.cancel() }

    /// Called after the controller has stopped inference and reserved its processing state.
    /// Trash keeps this action recoverable and never falls back to permanent deletion.
    @discardableResult func trash(_ spec: LocalModelSpec, root: URL) -> Bool {
        guard downloading == nil, models.contains(where: { $0.name == spec.name }),
              spec.name != ".", spec.name != "..", !spec.name.contains("/") else { return false }
        let directory = root.appendingPathComponent(spec.name, isDirectory: true)
        do {
            guard FileManager.default.fileExists(atPath: directory.path) else {
                refresh(root: root); message = "\(spec.title) is already removed."; return true
            }
            // A linked custom model folder is managed by its owner, outside this library.
            guard try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                message = "This model folder is a symbolic link. Manage it in Finder."; return false
            }
            try FileManager.default.trashItem(at: directory, resultingItemURL: nil)
            refresh(root: root)
            message = "\(spec.title) was moved to Trash. You can download it again or restore it in Finder."
            return true
        } catch {
            refresh(root: root)
            message = "Could not move \(spec.title) to Trash. \(error.localizedDescription)"
            return false
        }
    }
}
