import SwiftUI
import QuibbleCore
import QuibbleInference

struct DeveloperView: View {
    @ObservedObject var controller: DictationController
    @State private var options = ASROptions()
    @State private var saved = false
    @State private var configuration = ""
    private var engine: SpeechEngine { controller.engine }
    private var busy: Bool { controller.recording || controller.processing }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Developer").font(.largeTitle.bold())
            Text("Inspect the recognizer and every step after it.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 16) {
                HStack { Label("Decoding controls", systemImage: "slider.horizontal.3").font(.headline); Spacer(); Text(controller.workflow.name).font(.caption).foregroundStyle(.secondary) }
                Text(engine.displayName).font(.callout)
                if engine.supportsTokenLimit {
                    Stepper("Token limit: \(options.maxTokens)", value: $options.maxTokens, in: 64...2048, step: 64)
                    Text(engine.isWhisper ? "Per 30-second window; the model also caps tokens to its remaining context space." : "A small limit may truncate a valid dictation. This is a cap, not an accuracy target.").font(.caption).foregroundStyle(.secondary)
                }
                if engine.supportsTemperature {
                    HStack { Text("Temperature"); Slider(value: $options.temperature, in: 0...1, step: 0.05); Text(String(format: "%.2f", options.temperature)).monospacedDigit().frame(width: 42) }
                    Text("0 is greedy and repeatable. Higher values sample alternatives and can reduce reliability.").font(.caption).foregroundStyle(.secondary)
                }
                if engine.supportsLanguageSelection {
                    Picker(engine.isOnline ? "Language hint" : "Forced language", selection: $options.language) {
                        ForEach(engine.languageCodes, id: \.self) { Text(Locale(identifier: "en").localizedString(forLanguageCode: $0) ?? $0).tag($0) }
                    }
                }
                Text(engine.languageDescription).font(.caption).foregroundStyle(.secondary)
                if engine.supportsChunkLength { Stepper("Audio chunk: \(Int(options.chunkSeconds)) seconds", value: $options.chunkSeconds, in: 5...60, step: 5) }
                Text(engine.decoderNotes).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if !engine.isOnline { DisclosureGroup("Model configuration · read-only") {
                    if configuration.isEmpty { Button("Read local config") { readConfiguration() } }
                    else { code(configuration) }
                    Text("Architecture and quantization come from the downloaded model. Editing generation controls does not change its weights.").font(.caption).foregroundStyle(.secondary)
                } }
                HStack {
                    Button(saved ? "Saved" : "Apply to this mode") {
                        var workflow = controller.workflow; workflow.asr = options
                        saved = controller.workflows.save(workflow)
                    }.buttonStyle(.borderedProminent).tint(AppPalette.speech)
                    Button("Reset controls") { options = .init(); saved = false }
                }
            }.padding(22).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous)).disabled(busy)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Memory snapshot", systemImage: "memorychip").font(.headline); Spacer()
                    Button("Refresh") { controller.refreshMemory() }.disabled(busy)
                    Button("Unload models") { controller.unloadModels() }.disabled(busy)
                }
                if let date = controller.memoryUpdatedAt {
                    HStack(spacing: 24) {
                        memory("MLX active", "activeBytes"); memory("MLX cache", "cacheBytes"); memory("MLX peak", "peakBytes")
                    }
                    Text("Captured " + date.formatted(date: .omitted, time: .standard)).font(.caption).foregroundStyle(.secondary)
                }
                Text("MLX allocations cover model tensors and cache, not total app RAM. Peak is historical for this process. Refresh is manual; this screen does not poll.").font(.caption).foregroundStyle(.secondary)
            }.padding(22).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
            if let result = controller.lastResult {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("Last inference").font(.headline); Spacer(); Button("Export run…") { controller.exportMetrics() } }
                    Text((result.workflow?.name ?? result.mode) + " · " + result.engine).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        measure("Audio", String(format: "%.2f s", result.audioSeconds))
                        measure("ASR wall time", String(format: "%.3f s", result.transcriptionSeconds))
                        measure("ASR / audio", result.audioSeconds > 0 ? String(format: "%.3f×", result.transcriptionSeconds / result.audioSeconds) : "Unavailable")
                    }
                    if let detail = result.asrDetails {
                        HStack(spacing: 24) {
                            measure("Prompt tokens", detail.promptTokens.map(String.init) ?? "Unavailable")
                            measure("Generated tokens", detail.generatedTokens.map(String.init) ?? "Unavailable")
                            measure("Backend tokens/s", detail.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "Unavailable")
                        }
                        Text(String(format: "Audio level: %.1f dBFS RMS · 16 kHz mono input", detail.rmsDBFS)).font(.caption).foregroundStyle(.secondary)
                        Text("Requested language: \(detail.requested.language) · Backend label: \(detail.reportedLanguage ?? "Unavailable")" + (result.engine == OpenAITranscriptionClient.modelID ? "" : " · Token cap: \(detail.requested.maxTokens)")).font(.caption).foregroundStyle(.secondary)
                        Text(detail.notes).font(.caption).foregroundStyle(.secondary)
                        if let segments = detail.segmentsJSON {
                            DisclosureGroup("Backend segments / chunk ranges") { code(segments) }
                        }
                    }
                    DisclosureGroup("Raw ASR output") { code(result.raw) }
                    ForEach(result.stages ?? []) { stage in
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(stage.model).font(.caption).foregroundStyle(.secondary)
                                if let prompt = stage.prompt { Text("Instructions").font(.caption.bold()); code(prompt) }
                                Text("Input").font(.caption.bold()); code(stage.input)
                                if let candidate = stage.modelOutput, candidate != stage.output { Text("Model proposal · before guards").font(.caption.bold()); code(candidate) }
                                Text("Accepted output").font(.caption.bold()); code(stage.output)
                            }.padding(.top, 8)
                        } label: {
                            HStack { Text(stage.name); Spacer(); Text(stage.status).font(.caption).foregroundStyle(.secondary); Text(String(format: "%.3f s", stage.seconds)).font(.caption.monospacedDigit()) }
                        }
                    }
                    Text("Exports include transcript text, custom prompts, model IDs, settings, and timings. No audio or automatic telemetry. Token IDs, log-probabilities, and calibrated confidence are not exposed by these backends.").font(.caption).foregroundStyle(.secondary)
                }.padding(22).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
            } else { ContentUnavailableView("No run to inspect", systemImage: "waveform.path", description: Text("Record or import audio from Home. Its actual processing stages will appear here.")) }
        }.onAppear { options = controller.workflow.asr }
            .onChange(of: controller.workflow.id) { _, _ in options = controller.workflow.asr; saved = false; configuration = "" }
            .onChange(of: controller.engine) { _, _ in options = controller.workflow.asr; saved = false; configuration = "" }
            .onChange(of: options) { _, _ in saved = false }
    }
    private func readConfiguration() {
        let url = controller.modelRoot.appendingPathComponent(controller.engine.rawValue).appendingPathComponent("config.json")
        do {
            guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 128_000 else { configuration = "Config is too large to preview."; return }
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            configuration = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
        } catch { configuration = "Local configuration unavailable: " + error.localizedDescription }
    }
    private func memory(_ title: String, _ key: String) -> some View { measure(title, controller.memorySnapshot[key].map { String(format: "%.2f GB", Double($0) / 1e9) } ?? "Unavailable") }
    private func measure(_ title: String, _ value: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(value).font(.callout.monospacedDigit()) } }
    private func code(_ text: String) -> some View { Text(text.isEmpty ? "(empty)" : text).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8)) }
}
