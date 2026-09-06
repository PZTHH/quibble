import SwiftUI
import QuibbleCore
import QuibbleInference

private struct CloudModelSelection: Identifiable {
    let engine: SpeechEngine
    var id: String { engine.rawValue }
}

struct ModelLibraryView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var library: ModelLibrary
    @State private var query = ""
    @State private var section: LibrarySection = .speech
    @State private var sort: ModelSort = .catalog
    @State private var detail: LocalModelSpec?
    @State private var removing: LocalModelSpec?
    @State private var showAdvancedWriting = false
    @State private var showingComparisonHelp = false
    @State private var showingOnline = false
    @State private var cloudSelection: CloudModelSelection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(controller: DictationController) { self.controller = controller; library = controller.modelLibrary }
    private var busy: Bool { controller.recording || controller.processing }
    private var onlineModels: [SpeechEngine] {
        SpeechEngine.allCases.filter { engine in
            engine.isOnline && (query.isEmpty || engine.displayName.localizedStandardContains(query)
                || engine.rawValue.localizedStandardContains(query)
                || (engine == .openAIDiarize && "speaker labels timestamps diarization".localizedStandardContains(query)))
        }
    }
    private var canManage: Bool { !busy && library.downloading == nil }
    private var filtered: [LocalModelSpec] {
        let candidates = library.models.filter { model in
            section == .speech ? model.role == "Speech" : section == .writing ? model.role != "Speech" : library.stored.contains(model.name)
        }
        let matches = ModelVariantGroup.make(from: candidates).filter { group in
            query.isEmpty || group.variants.contains { model in
                [model.title, model.variant, model.detail, model.repository].joined(separator: " ").localizedStandardContains(query)
            }
        }.compactMap { group in
            group.recommendedVariant(physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                selectedID: controller.workflow.speechModel, installed: library.installed,
                additionalModelBytes: writingMemoryEstimate)
        }
        // Sorting is stable for equal values; unknown accuracy follows rated models.
        return matches.enumerated().sorted { left, right in
            switch sort {
            case .catalog: return left.offset < right.offset
            case .accuracy:
                let lhs = library.benchmarks?.result(for: left.element.benchmarkID)?.werPercent ?? .infinity
                let rhs = library.benchmarks?.result(for: right.element.benchmarkID)?.werPercent ?? .infinity
                return lhs == rhs ? left.offset < right.offset : lhs < rhs
            case .speed:
                let lhs = library.benchmarks?.speedRTFx(for: left.element.benchmarkID) ?? 0
                let rhs = library.benchmarks?.speedRTFx(for: right.element.benchmarkID) ?? 0
                return lhs == rhs ? left.offset < right.offset : lhs > rhs
            case .size:
                return left.element.gigabytes == right.element.gigabytes ? left.offset < right.offset : left.element.gigabytes < right.element.gigabytes
            case .name:
                let order = left.element.title.localizedStandardCompare(right.element.title)
                return order == .orderedSame ? left.offset < right.offset : order == .orderedAscending
            }
        }.map(\.element)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Models").font(.largeTitle.bold())
                Spacer()
                Label("For " + controller.workflow.name, systemImage: "slider.horizontal.3")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help("Use a model to change the selected mode.")
            }
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search models", text: $query).textFieldStyle(.plain)
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear model search")
                    }
                }.padding(10).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                Menu {
                    Picker("Sort models", selection: $sort) {
                        ForEach(ModelSort.allCases) { order in Text(order.rawValue).tag(order) }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .menuStyle(.borderlessButton).frame(width: 26)
                    .accessibilityLabel("Sort models: " + sort.rawValue).help(sort.rawValue)
            }
            Picker("Model library", selection: $section) {
                ForEach(LibrarySection.allCases) { item in Text(item.rawValue).tag(item) }
            }.pickerStyle(.segmented).labelsHidden()
            if section == .speech && !onlineModels.isEmpty {
                DisclosureGroup(isExpanded: $showingOnline) {
                    VStack(spacing: 15) {
                        ForEach(onlineModels, id: \.rawValue) { engine in
                            HStack(spacing: 12) {
                                ModelIcon(modelID: engine.rawValue, size: 30)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(engine == .openAIDiarize ? "OpenAI · Speakers" : "OpenAI Transcribe").font(.callout.weight(.medium))
                                    Label(engine == .openAIDiarize ? "Speaker labels & timestamps" : "Personal vocabulary hints",
                                          systemImage: engine == .openAIDiarize ? "person.2" : "character.book.closed")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if controller.engine == engine {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(AppPalette.speech).accessibilityLabel("Selected")
                                } else if controller.cloudSpeech.hasKey {
                                    Button("Use") { _ = controller.selectSpeechEngine(engine) }.disabled(busy)
                                }
                                Button(controller.cloudSpeech.hasKey ? "Details…" : "Set up…") {
                                    cloudSelection = .init(engine: engine)
                                }.disabled(busy)
                            }
                        }
                        Text("Audio is sent to OpenAI only when an online model is selected.").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.top, 14)
                } label: {
                    HStack {
                        Label("Online transcription", systemImage: "cloud")
                        Spacer()
                        if controller.engine.isOnline { Text("In use").font(.caption).foregroundStyle(.secondary) }
                    }
                }.font(.callout).padding(15)
                    .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 20))
                    .background(controller.engine.isOnline ? AppPalette.speech.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(controller.engine.isOnline ? AppPalette.speech.opacity(0.5) : Color.primary.opacity(0.06)))
            }

            if filtered.isEmpty && (section != .speech || onlineModels.isEmpty) {
                ContentUnavailableView {
                    Label(query.isEmpty && section == .downloaded ? "No local downloads" : "No matching models", systemImage: query.isEmpty && section == .downloaded ? "internaldrive" : "magnifyingglass")
                } actions: {
                    Button(query.isEmpty ? "Browse speech models" : "Clear search") {
                        if query.isEmpty { section = .speech } else { query = "" }
                    }
                }
            } else if section == .writing {
                let standard = filtered.filter { $0.role == "Cleanup" }
                let advanced = filtered.filter { $0.role == "Instructions" }
                if !standard.isEmpty { modelTable(standard, speech: false) }
                if !advanced.isEmpty {
                    DisclosureGroup(isExpanded: $showAdvancedWriting) {
                        modelTable(advanced, speech: false).padding(.top, 12)
                    } label: {
                        HStack(spacing: 8) {
                            Text("More local writing models").font(.callout.weight(.medium))
                            Text("\(advanced.count)").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("Custom prompts").font(.caption).foregroundStyle(.secondary)
                        }
                    }.tint(AppPalette.instructions)
                }
            } else {
                let speech = filtered.filter { $0.role == "Speech" }
                let writing = filtered.filter { $0.role != "Speech" }
                if !speech.isEmpty { modelTable(speech, speech: true) }
                if !writing.isEmpty { modelTable(writing, speech: false) }
            }

            HStack(spacing: 8) {
                Label("\(ModelVariantGroup.make(from: library.models.filter { library.installed.contains($0.name) }).count) models downloaded", systemImage: "internaldrive")
                Text("·")
                Text(ByteCountFormatter.string(fromByteCount: library.diskBytes.values.reduce(0, +), countStyle: .file))
                Spacer()
                if section != .writing {
                    Button { showingComparisonHelp = true } label: { Label("About ratings", systemImage: "info.circle") }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showingComparisonHelp) { comparisonHelp }
                }
            }.font(.caption).foregroundStyle(.secondary)
            if !library.message.isEmpty && library.downloading == nil {
                Label(library.message, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let error = controller.workflows.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange)
            }
            DisclosureGroup("Storage & loading") {
                VStack(alignment: .leading, spacing: 12) {
                    Text(controller.modelRoot.path).font(.caption).textSelection(.enabled)
                    HStack {
                        Button("Choose folder…") { controller.chooseModels() }.disabled(!canManage)
                        Button("Show in Finder") { NSWorkspace.shared.open(controller.modelRoot) }
                        Spacer()
                        Button("Unload models") { controller.unloadModels() }.disabled(busy)
                    }
                    Text(controller.status).font(.caption).foregroundStyle(.secondary)
                    Text("Models load only when needed and unload after two idle minutes. Remove a download from its ••• menu; it goes to Trash.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 12)
            }.font(.callout)
        }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: section)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: sort)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: controller.workflow.speechModel)
            .onAppear { library.refresh(root: controller.modelRoot); showingOnline = controller.engine.isOnline }
            .onChange(of: controller.engine) { _, engine in if engine.isOnline { showingOnline = true } }
            .sheet(item: $cloudSelection) { selection in CloudSpeechView(controller: controller, preferredModel: selection.engine) }
            .onChange(of: controller.modelRoot) { _, root in library.refresh(root: root) }
            .onChange(of: query) { _, value in if !value.isEmpty { showAdvancedWriting = true; showingOnline = !onlineModels.isEmpty } }
            .sheet(item: $detail) { spec in
                ModelDetails(controller: controller, initial: spec)
            }
            .alert("Move \(removing?.title ?? "model") to Trash?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { spec in
                Button("Cancel", role: .cancel) { removing = nil }
                Button("Move to Trash", role: .destructive) {
                    guard canManage else { return }
                    controller.removeModel(spec)
                    removing = nil
                }.disabled(!canManage)
            } message: { spec in Text(removalMessage(spec)) }
    }

    private var writingMemoryEstimate: UInt64 {
        estimatedWritingMemory(controller: controller, models: library.models)
    }

    private func modelTable(_ models: [LocalModelSpec], speech: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("Model", systemImage: speech ? "waveform" : "wand.and.stars")
                Spacer(minLength: 4)
                Text(speech ? "HF · H200" : "Purpose").frame(width: 120, alignment: .leading)
                    .help(speech ? "Static upstream benchmark reference. More segments means a better relative rank; these are not measurements on this Mac." : "What this writing model can do")
                Text("Local size").frame(width: 60, alignment: .trailing)
                Color.clear.frame(width: 98, height: 1)
            }.font(.caption.weight(.medium)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 12)
            Divider().opacity(0.45)
            ForEach(Array(models.enumerated()), id: \.element.id) { index, spec in
                modelRow(spec).padding(.horizontal, 6).padding(.vertical, 2)
                if index < models.count - 1 { Divider().opacity(0.22).padding(.leading, 60) }
            }
        }.padding(.bottom, 4)
            .background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
    private func modelRow(_ spec: LocalModelSpec) -> some View {
        let isSelected = selected(spec)
        let downloaded = library.installed.contains(spec.name)
        let variants = library.models.filter { $0.logicalModelID == spec.logicalModelID }
        let activeDownload = variants.first { library.downloading == $0.name }
        let color = spec.role == "Speech" ? AppPalette.speech : spec.role == "Cleanup" ? AppPalette.vocabulary : AppPalette.instructions
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Button { detail = spec } label: {
                    HStack(spacing: 10) {
                        ModelIcon(modelID: spec.name, size: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 5) {
                                Text(spec.title).font(.callout.weight(isSelected ? .semibold : .medium)).lineLimit(1)
                                if variants.contains(where: { $0.variant.localizedCaseInsensitiveContains("Recommended") }) {
                                    Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(AppPalette.vocabulary)
                                        .help("Recommended").accessibilityLabel("Recommended")
                                }
                            }
                            HStack(spacing: 4) {
                                Text(variantLabel(spec)).lineLimit(1)
                                if variants.count > 1 { Text("· \(variants.count) variants").lineLimit(1) }
                                if spec.isExperimental {
                                    Image(systemName: "flask").help("Experimental — see Details").accessibilityLabel("Experimental")
                                }
                            }.font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Details for \(spec.title), \(spec.variant)")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                Group {
                    if spec.role == "Speech" {
                        if library.benchmarks?.accuracyStanding(for: spec.benchmarkID) == nil,
                           library.benchmarks?.speedStanding(for: spec.benchmarkID) == nil {
                            UnrankedBenchmarkBadge(reason: library.benchmarks?.unavailableResult(for: spec.benchmarkID)?.reason)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                BenchmarkSegments(title: "Accuracy", standing: library.benchmarks?.accuracyStanding(for: spec.benchmarkID), color: AppPalette.speech)
                                BenchmarkSegments(title: "Speed", standing: library.benchmarks?.speedStanding(for: spec.benchmarkID), color: AppPalette.speed)
                            }
                        }
                    } else {
                        Label(spec.role == "Cleanup" ? "Polish" : "Format", systemImage: spec.role == "Cleanup" ? "wand.and.stars" : "text.alignleft")
                            .font(.caption.weight(.medium)).foregroundStyle(color)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(color.opacity(0.10), in: Capsule())
                    }
                }.frame(width: 120, alignment: .leading)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(downloaded ? ByteCountFormatter.string(fromByteCount: library.diskBytes[spec.name] ?? 0, countStyle: .file) : spec.sizeLabel)
                        .font(.caption.monospacedDigit()).lineLimit(1)
                    if library.stored.contains(spec.name) && !downloaded {
                        Image(systemName: "exclamationmark.circle").font(.caption2).foregroundStyle(.orange)
                            .accessibilityLabel("Incomplete download").help("Incomplete download")
                    } else {
                        Image(systemName: downloaded ? "internaldrive" : "arrow.down.to.line")
                            .font(.caption2).foregroundStyle(.secondary)
                            .accessibilityLabel(downloaded ? "Downloaded" : "Not downloaded")
                            .help(downloaded ? "Downloaded on this Mac" : "Not downloaded · estimated size")
                    }
                }.frame(width: 60, alignment: .trailing)
                HStack(spacing: 6) {
                    Group {
                        if let activeDownload {
                            Button { library.cancelDownload() } label: { Image(systemName: "xmark.circle") }
                                .help("Cancel download").accessibilityLabel("Cancel downloading " + activeDownload.title)
                        } else if downloaded && isSelected {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 17, weight: .medium)).foregroundStyle(color)
                                .accessibilityLabel("In use in " + controller.workflow.name).help("In use in " + controller.workflow.name)
                        } else if downloaded {
                            Button(spec.role == "Speech" ? "Use" : hasDisabledStep(spec) ? "Enable" : "Add step") { select(spec) }.buttonStyle(.bordered)
                                .disabled(busy || (spec.role != "Speech" && !hasDisabledStep(spec) && controller.workflow.steps.count >= 6))
                                .help(spec.role == "Speech" ? "Use in " + controller.workflow.name : hasDisabledStep(spec) ? "Enable the saved step in " + controller.workflow.name : "Add a writing step to " + controller.workflow.name)
                                .accessibilityLabel(spec.role == "Speech" ? "Use \(spec.title), \(spec.variant)" : "\(hasDisabledStep(spec) ? "Enable" : "Add") \(spec.title) writing step")
                        } else if library.stored.contains(spec.name) {
                            Button { removing = spec } label: { Image(systemName: "exclamationmark.arrow.circlepath") }
                                .disabled(!canManage).help("Remove incomplete download…")
                                .accessibilityLabel("Remove incomplete download of " + spec.title)
                        } else {
                            Button { library.download(spec, root: controller.modelRoot) } label: { Image(systemName: "arrow.down.circle") }
                                .disabled(!canManage).help("Download " + spec.title)
                                .accessibilityLabel("Download \(spec.title), \(spec.variant)")
                        }
                    }.frame(width: 64).controlSize(.small)
                    Menu {
                        Button("Details…") { detail = spec }
                        if library.stored.contains(spec.name) {
                            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([controller.modelRoot.appendingPathComponent(spec.name)]) }
                            Divider()
                            Button("Remove download…", role: .destructive) { removing = spec }.disabled(!canManage)
                        }
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                        .accessibilityLabel("Options for \(spec.title), \(spec.variant)")
                }.frame(width: 98)
            }
            if let activeDownload {
                HStack(spacing: 10) {
                    Text(activeDownload.precisionLabel).font(.caption2).foregroundStyle(.secondary)
                    ProgressView(value: library.progress).tint(color).accessibilityLabel("Downloading " + activeDownload.title)
                    Text(library.progress, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 9)
            .background(isSelected ? color.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

    }
    private func variantLabel(_ spec: LocalModelSpec) -> String {
        if spec.name == "s1-mini" { return "English · text cleanup" }
        let parameters = spec.parameters.map { $0 >= 1_000_000_000 ? String(format: "%.1fB", Double($0) / 1e9) : String(format: "%.0fM", Double($0) / 1e6) }
        return [parameters, spec.precisionLabel].compactMap { $0 }.joined(separator: " · ")
    }
    private func selected(_ spec: LocalModelSpec) -> Bool {
        spec.role == "Speech" ? controller.workflow.speechModel == spec.name : controller.workflow.enabledSteps.contains { $0.modelID == spec.name }
    }
    private func hasDisabledStep(_ spec: LocalModelSpec) -> Bool {
        controller.workflow.steps.contains { $0.modelID == spec.name && !$0.enabled }
    }
    private func select(_ spec: LocalModelSpec) {
        guard !busy else { return }
        if let engine = SpeechEngine(rawValue: spec.name) { _ = controller.selectSpeechEngine(engine) }
        else {
            var workflow = controller.workflow
            if let index = workflow.steps.firstIndex(where: { $0.modelID == spec.name }) {
                guard !workflow.steps[index].enabled else { return }
                workflow.steps[index].enabled = true
            } else {
                guard workflow.steps.count < 6 else { return }
                workflow.steps.append(spec.name == "s1-mini" ? .init(kind: .cleanup) : .init(kind: .prompt, model: spec.name, prompt: "Clean up the dictation while preserving its meaning and wording."))
            }
            _ = controller.workflows.save(workflow)
        }
    }
    private func references(to spec: LocalModelSpec) -> [String] {
        controller.workflows.workflows.filter { mode in
            mode.speechModel == spec.name || mode.steps.contains { $0.modelID(speechModel: mode.speechModel) == spec.name }
            || (spec.name == "s1-mini" && mode.speechModel != OpenAITranscriptionClient.modelID && mode.steps.contains { $0.kind == .vocabulary })
        }.map(\.name)
    }
    private func removalMessage(_ spec: LocalModelSpec) -> String {
        var lines = ["\(spec.variant) · \(ByteCountFormatter.string(fromByteCount: library.diskBytes[spec.name] ?? 0, countStyle: .file)). The model folder will move to Trash and can be restored in Finder."]
        let modes = references(to: spec)
        if !modes.isEmpty { lines.append("Used by modes: " + modes.joined(separator: ", ") + ". Their choices are kept; download this model again or choose a replacement before using those steps.") }
        if spec.name == "whisper-turbo-vocabulary-4bit" { lines.append("This download is also the shared helper for saved spellings.") }
        if spec.name == "s1-mini" { lines.append("S1-mini also checks ambiguous saved spellings. Those checks will be skipped while it is unavailable.") }
        return lines.joined(separator: "\n\n")
    }
    private var comparisonHelp: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Accuracy & speed", systemImage: "chart.bar.xaxis").font(.headline)
            Text("More filled Accuracy segments means a better relative rank in the Hugging Face benchmark. Equal source scores share a rank; search and filters keep the same scale.")
            Text("This is a rank, not percent correct. Small differences are spread for readability. Details has the exact word error rate across eight public English datasets and the source.")
            Text("These are upstream results, not measurements of Quibble’s conversions or vocabulary workflow. Models without comparable results are marked Not ranked.")
            Text("Speed uses static Hugging Face throughput results on NVIDIA H200 hardware. Its segments show relative benchmark rank, not a proportional speed difference or expected Mac latency. Equal upstream checkpoints share a reference.")
            Text("Exact RTFx, hardware and source are in Details. Measurements from your Mac remain in Diagnostics.").foregroundStyle(.secondary)
            if let benchmarks = library.benchmarks, let url = URL(string: benchmarks.sourceURL) {
                Link("Hugging Face source · " + benchmarks.retrievedAt, destination: url)
            }
        }.font(.callout).padding(24).frame(width: 330)
    }
}

private enum LibrarySection: String, CaseIterable, Identifiable {
    case speech = "Speech", writing = "Writing", downloaded = "Downloaded"
    var id: String { rawValue }
}

private struct UnrankedBenchmarkBadge: View {
    let reason: String?
    var body: some View {
        Label("Not ranked", systemImage: "chart.bar.xaxis")
            .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Color.primary.opacity(0.05), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Accuracy and speed: not ranked in the current Hugging Face comparison")
            .help(reason ?? "No comparable Hugging Face benchmark result. See Details.")
    }
}

private struct BenchmarkSegments: View {
    let title: String
    let standing: ASRBenchmarkCatalog.AccuracyStanding?
    let color: Color
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(width: 46, alignment: .leading)
            if let standing {
                HStack(spacing: 3) {
                    ForEach(0..<standing.levels, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index < standing.filledSegments ? color.opacity(0.85) : Color.primary.opacity(0.08))
                    }
                }.frame(height: 6)
            } else {
                Text("Not ranked").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(title + ", relative HF benchmark")
            .accessibilityValue(standing.map { "Rank \($0.position) of \($0.levels), \($0.filledSegments) filled segments. More is better." } ?? "Not ranked")
            .help(standing.map { "\(title): \($0.filledSegments)/\($0.levels), relative HF benchmark. More is better. See Details for the published metric and H200 benchmark scope." } ?? "No comparable Hugging Face benchmark result.")
    }
}

private struct AccuracyMeter: View {
    let standing: ASRBenchmarkCatalog.AccuracyStanding
    private var description: String {
        return "Relative rank \(standing.position) of \(standing.levels); more filled segments is better"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Accuracy").foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text("\(standing.filledSegments)/\(standing.levels)")
                    .fontWeight(.medium).monospacedDigit()
            }.font(.caption)
            HStack(spacing: 4) {
                ForEach(0..<standing.levels, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < standing.filledSegments ? AppPalette.speech.opacity(0.85) : Color.primary.opacity(0.07))
                        .frame(maxWidth: .infinity)
                }
            }.frame(height: 7)
        }.frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore).accessibilityLabel("Accuracy, relative HF benchmark")
            .accessibilityValue(description)
    }
}

private struct ModelDetails: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var library: ModelLibrary
    private let initial: LocalModelSpec
    @State private var variantID: String
    @State private var removing: LocalModelSpec?
    @Environment(\.dismiss) private var dismiss

    init(controller: DictationController, initial: LocalModelSpec) {
        self.controller = controller
        self.library = controller.modelLibrary
        self.initial = initial
        _variantID = State(initialValue: initial.name)
    }

    private var variants: [LocalModelSpec] { library.models.filter { $0.logicalModelID == initial.logicalModelID } }
    private var spec: LocalModelSpec { variants.first { $0.name == variantID } ?? initial }
    private var installed: Bool { library.installed.contains(spec.name) }
    private var diskBytes: Int64 { library.diskBytes[spec.name] ?? 0 }
    private var benchmarks: ASRBenchmarkCatalog? { library.benchmarks }
    private var busy: Bool { controller.recording || controller.processing }
    private var canManage: Bool { !busy && library.downloading == nil }
    private var selected: Bool {
        spec.role == "Speech" ? controller.workflow.speechModel == spec.name : controller.workflow.enabledSteps.contains { $0.modelID == spec.name }
    }
    private var hasDisabledStep: Bool { controller.workflow.steps.contains { $0.modelID == spec.name && !$0.enabled } }
    private var recommendation: LocalModelSpec? {
        ModelVariantGroup.make(from: variants).first?.recommendedVariant(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            additionalModelBytes: estimatedWritingMemory(controller: controller, models: library.models))
    }
    private var references: [String] {
        controller.workflows.workflows.filter { mode in
            mode.speechModel == spec.name || mode.steps.contains { $0.modelID(speechModel: mode.speechModel) == spec.name }
                || (spec.name == "s1-mini" && SpeechEngine(rawValue: mode.speechModel)?.isOnline != true && mode.steps.contains { $0.kind == .vocabulary })
        }.map(\.name)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ModelIcon(modelID: spec.name, size: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(spec.title).font(.title2.bold())
                    Text(spec.variant + " · " + spec.role).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    variantControls
                    Text(spec.detail)
                    LabeledContent("Download", value: spec.sizeLabel)
                    LabeledContent("Local files", value: installed ? ByteCountFormatter.string(fromByteCount: diskBytes, countStyle: .file) : "Not fully downloaded")
                    if !references.isEmpty {
                        LabeledContent("Referenced by", value: references.joined(separator: ", "))
                        Text("Includes saved, disabled, and shared vocabulary steps.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(spec.languages ?? "See the source model card for language support.").font(.callout)
                    Divider()
                    if spec.role == "Speech", let standing = benchmarks?.accuracyStanding(for: spec.benchmarkID) {
                        AccuracyMeter(standing: standing)
                        Text("Relative Hugging Face benchmark rank; more segments is better.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let benchmark = benchmarks?.result(for: spec.benchmarkID), let benchmarks {
                        LabeledContent("Published word error rate", value: String(format: "%.2f%% · lower is better", benchmark.werPercent))
                        Text(benchmarks.task).font(.callout)
                        Text(benchmark.note).font(.caption).foregroundStyle(.secondary)
                        Text("Evaluated: " + benchmark.evaluatedModel).font(.caption).textSelection(.enabled)
                        if let url = URL(string: benchmark.sourceURL) { Link("Hugging Face benchmark · " + benchmarks.retrievedAt, destination: url) }
                        DisclosureGroup("Benchmark methodology") {
                            Text(benchmarks.methodology).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        }
                        Divider()
                    }
                    if spec.role == "Speech", benchmarks?.accuracyStanding(for: spec.benchmarkID) == nil,
                       benchmarks?.speedStanding(for: spec.benchmarkID) == nil {
                        UnrankedBenchmarkBadge(reason: benchmarks?.unavailableResult(for: spec.benchmarkID)?.reason)
                        Text(benchmarks?.unavailableResult(for: spec.benchmarkID)?.reason ?? "No comparable accuracy or speed result is available in the bundled Hugging Face benchmark snapshot.")
                            .font(.callout).foregroundStyle(.secondary)
                        if let benchmarks, let url = URL(string: benchmarks.sourceURL) {
                            Link("Hugging Face comparison · " + benchmarks.retrievedAt, destination: url)
                        }
                        Divider()
                    }
                    if spec.role == "Speech", let rtfx = benchmarks?.speedRTFx(for: spec.benchmarkID), let speed = benchmarks?.speedBenchmark {
                        Text("Published speed").font(.headline)
                        LabeledContent("HF throughput", value: String(format: "%.2f× RTFx", rtfx))
                        LabeledContent("Hardware", value: speed.hardware)
                        Text(speed.note).font(.caption).foregroundStyle(.secondary)
                        if let url = URL(string: speed.sourceURL) { Link("Speed results · " + speed.retrievedAt, destination: url) }
                        if let url = URL(string: speed.hardwareSourceURL) { Link("HF evaluation setup", destination: url) }
                        DisclosureGroup("Speed methodology") {
                            Text(speed.methodology).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                        }
                        Divider()
                    }
                    ModelCapabilities(spec: spec, expanded: true)
                    Divider()
                    Text("Available controls").font(.headline)
                    if let engine = SpeechEngine(rawValue: spec.name) {
                        Text(engine.decoderNotes).font(.callout)
                        Text("Edit supported controls in Developer. The vocabulary helper is a separate guarded pass; primary recognition is kept available for comparison.").font(.caption).foregroundStyle(.secondary)
                    } else if spec.name == "s1-mini" { Text("Fixed normalization prompt, greedy decoding. Add or skip this step in Modes. It does not accept arbitrary custom prompts.").font(.callout) }
                    else { Text("User-defined prompt in a workflow step. Greedy text generation with thinking disabled, bounded output, and incomplete-output fallback. Larger models are not automatically better at your prompt.").font(.callout) }
                    Divider()
                    Text("Evidence & provenance").font(.headline)
                    if let artifactSource = spec.artifactSource {
                        LabeledContent("Weights", value: artifactSource == "publisher" ? "Original publisher" : "Runtime conversion")
                    }
                    Text(spec.validation ?? "Not yet evaluated in Quibble.").font(.callout).foregroundStyle(.secondary)
                    Text(spec.license ?? "See source license").font(.caption).foregroundStyle(.secondary)
                    Text(spec.repository).font(.caption.monospaced()).textSelection(.enabled)
                    Text("Pinned download revision: " + spec.revision).font(.caption.monospaced()).textSelection(.enabled)
                    if let url = URL(string: "https://huggingface.co/\(spec.repository)/tree/\(spec.revision)") { Link("Open pinned model files", destination: url) }
                    if let source = spec.source, let url = URL(string: source) { Link("Original model card", destination: url) }
                    Text("Community conversions are attributed separately from the original publisher. Existing folders are checked for required files, not rehashed against this revision. Published WER describes the upstream model; local quantization and decoding may change recognition quality.").font(.caption).foregroundStyle(.secondary)
                }.padding(2)
            }
        }.padding(24).frame(width: 620, height: 650)
            .presentationCornerRadius(20)
            .alert("Move download to Trash?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), presenting: removing) { model in
                Button("Cancel", role: .cancel) { removing = nil }
                Button("Move to Trash", role: .destructive) {
                    guard canManage else { return }
                    controller.removeModel(model)
                    removing = nil
                }.disabled(!canManage)
            } message: { model in
                Text("\(model.title) · \(model.precisionLabel) will move to Trash. Saved modes keep their selection. Download it again or choose another variant before using those modes. Shared saved-spelling steps may also need this download.")
            }
    }

    private var variantControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if variants.count > 1 {
                Picker("Weight variant", selection: $variantID) {
                    ForEach(variants) { variant in
                        Text(variant.precisionLabel + " · " + variant.sizeLabel).tag(variant.name)
                    }
                }.pickerStyle(.menu).disabled(busy)
                if let recommendation {
                    HStack(spacing: 6) {
                        Image(systemName: "memorychip")
                        Text("Suggested for this Mac: " + recommendation.precisionLabel)
                    }.font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("About this suggestion") {
                        Text("Estimated from this Mac’s memory and the mode’s writing steps. Existing choices and downloads are kept. This is not a measured memory peak or an accuracy guarantee; changing this picker only previews a variant.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    }.font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                if library.downloading == spec.name {
                    ProgressView(value: library.progress).tint(AppPalette.speech)
                        .accessibilityLabel("Downloading " + spec.title + " " + spec.precisionLabel)
                    Text(library.progress, format: .percent.precision(.fractionLength(0))).font(.caption.monospacedDigit())
                    Button("Cancel download") { library.cancelDownload() }.controlSize(.small)
                } else if installed {
                    Label("Downloaded", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(AppPalette.vocabulary)
                    Spacer()
                    if selected {
                        Label("In use", systemImage: "checkmark").font(.callout.weight(.medium)).foregroundStyle(AppPalette.speech)
                    } else {
                        Button(spec.role == "Speech" ? "Use this variant" : hasDisabledStep ? "Enable step" : "Add step") { useVariant() }
                            .buttonStyle(.borderedProminent).tint(AppPalette.speech)
                            .disabled(busy || (spec.role != "Speech" && !hasDisabledStep && controller.workflow.steps.count >= 6))
                    }
                    Menu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([controller.modelRoot.appendingPathComponent(spec.name)]) }
                        Button("Remove download…", role: .destructive) { removing = spec }.disabled(!canManage)
                    } label: { Image(systemName: "ellipsis") }
                        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 20)
                        .accessibilityLabel("Manage " + spec.precisionLabel + " download")
                } else if library.stored.contains(spec.name) {
                    Label("Incomplete download", systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove incomplete…") { removing = spec }.disabled(!canManage)
                } else {
                    Label("Not downloaded", systemImage: "arrow.down.to.line").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Download " + spec.sizeLabel) { library.download(spec, root: controller.modelRoot) }
                        .buttonStyle(.borderedProminent).tint(AppPalette.speech).disabled(!canManage)
                }
            }
            if !library.message.isEmpty && library.downloading == nil {
                Text(library.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let active = library.models.first(where: { $0.name == library.downloading && $0.name != spec.name }) {
                Label("Downloading " + active.title + " · " + active.precisionLabel, systemImage: "arrow.down.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = controller.workflows.error {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(15).background(.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 14))
    }

    private func useVariant() {
        guard !busy, installed else { return }
        if let engine = SpeechEngine(rawValue: spec.name) {
            _ = controller.selectSpeechEngine(engine)
        } else {
            var mode = controller.workflow
            if let index = mode.steps.firstIndex(where: { $0.modelID == spec.name }) {
                mode.steps[index].enabled = true
            } else {
                guard mode.steps.count < 6 else { return }
                mode.steps.append(spec.name == "s1-mini" ? .init(kind: .cleanup)
                    : .init(kind: .prompt, model: spec.name, prompt: "Clean up the dictation while preserving its meaning and wording."))
            }
            _ = controller.workflows.save(mode)
        }
    }
}

@MainActor
private func estimatedWritingMemory(controller: DictationController, models: [LocalModelSpec]) -> UInt64 {
    let hasVocabulary = controller.vocabulary.enabled && controller.vocabulary.entries.contains(where: \.enabled)
    return ModelVariantGroup.additionalModelBytes(for: controller.workflow, hasVocabulary: hasVocabulary, models: models)
}

private enum ModelSort: String, CaseIterable, Identifiable {
    case catalog = "Library order"
    case accuracy = "Accuracy: highest first"
    case speed = "HF speed: fastest first"
    case size = "Download size: smallest first"
    case name = "Name"
    var id: String { rawValue }
}
