import SwiftUI
import QuibbleCore
import QuibbleInference

/// A resumable setup workspace. Downloads belong to ModelLibrary, never this sheet.
@MainActor
struct QuickTourView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var library: ModelLibrary
    @ObservedObject private var vocabulary: VocabularyStore
    let finish: (Bool, QuibblePage?) -> Void
    @AppStorage("onboarding.step.v1") private var savedPage = 0
    @State private var practicing = false
    @State private var practiceText: String?
    @State private var lastCompletedPracticeText: String?
    @State private var practiceStatus: String?
    @State private var shortcutFailure: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(controller: DictationController, finish: @escaping (Bool, QuibblePage?) -> Void) {
        self.controller = controller
        library = controller.modelLibrary
        vocabulary = controller.vocabulary
        self.finish = finish
    }

    private let pages = ["Welcome", "Choose a model", "Try your voice", "Make it yours"]
    private let symbols = ["hand.wave", "waveform", "mic", "slider.horizontal.3"]
    private var page: Int { min(3, max(0, savedPage)) }
    private var busy: Bool { controller.recording || controller.processing || controller.inserting }
    private var editingModels: Bool { !busy && library.downloading == nil }
    private var requiredIDs: [String] {
        SetupRequirements.modelIDs(for: controller.workflow,
            hasVocabulary: vocabulary.enabled && vocabulary.entries.contains(where: \.enabled))
    }
    private var missingIDs: [String] { requiredIDs.filter { !library.installed.contains($0) } }
    private var missingModels: [LocalModelSpec] { missingIDs.compactMap { id in library.models.first { $0.name == id } } }
    private var modelsReady: Bool { missingIDs.isEmpty && (!controller.engine.isOnline || controller.cloudSpeech.hasKey) }
    private var permissionsReady: Bool { controller.microphoneAllowed && controller.accessibilityAllowed && controller.shortcutEnabled }
    private var shortcutsReady: Bool { controller.accessibilityAllowed && controller.shortcutEnabled }
    private var ready: Bool { modelsReady && permissionsReady }
    private var canPractice: Bool { modelsReady && controller.microphoneAllowed && library.downloading == nil }
    private var downloadSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(missingModels.reduce(0) { $0 + $1.gigabytes } * 1e9), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                navigation
                Divider()
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            pageHeader
                            Group {
                                switch page {
                                case 0: welcome
                                case 1: models
                                case 2: practice
                                default: personalize
                                }
                            }
                        }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    }.id(page).transition(.opacity)
                    Divider()
                    HStack(spacing: 12) {
                        Button("Back") { savedPage = max(0, page - 1) }.disabled(page == 0 || practicing)
                        Spacer()
                        if page == 3 && !ready {
                            Button("Review setup") { savedPage = permissionsReady ? 1 : 0 }
                        }
                        Button(page == 3 ? (ready ? "Start dictating" : "Finish later") : "Continue") {
                            if page == 3 { finish(ready, nil) } else { savedPage = page + 1 }
                        }.buttonStyle(.borderedProminent).controlSize(.large)
                            .keyboardShortcut(.defaultAction).disabled(practicing)
                    }.padding(.horizontal, 26).padding(.vertical, 16)
                }.frame(maxWidth: .infinity)
            }
            downloadShelf
        }
        .frame(width: 800, height: 590)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(AppPalette.speech)
        .interactiveDismissDisabled(practicing)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: page)
        .onAppear {
            library.refresh(root: controller.modelRoot); controller.refreshPermissions()
            controller.refreshShortcutConflicts()
            updatePracticeRouting()
        }
        .onDisappear { controller.setSetupPracticeEnabled(false) }
        .onChange(of: savedPage) { _, _ in updatePracticeRouting() }
        .onChange(of: canPractice) { _, _ in updatePracticeRouting() }
        .onChange(of: controller.setupPracticeRecording) { _, recording in
            if recording { practiceText = nil; practiceStatus = nil; practicing = true }
        }
        .onChange(of: controller.modelRoot) { _, root in library.refresh(root: root) }
        .onChange(of: controller.processing) { _, processing in
            guard practicing, !processing, !controller.recording else { return }
            practiceText = controller.lastResult?.text
            if let practiceText, !practiceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastCompletedPracticeText = practiceText
            }
            practiceStatus = controller.status
            practicing = false
        }
        .onChange(of: controller.recording) { _, recording in
            // Escape can cancel capture without ever entering processing.
            if practicing && !recording && !controller.processing {
                Task { @MainActor in
                    await Task.yield()
                    if practicing && !controller.recording && !controller.processing {
                        practiceStatus = controller.status; practicing = false
                    }
                }
            }
        }
    }

    private var navigation: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(spacing: 10) {
                Image("QuibbleMark").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 34, height: 34).frame(width: 24, height: 24)
                    .foregroundStyle(AppPalette.speech).accessibilityHidden(true)
                Text("Quibble").font(.title2.weight(.semibold))
            }.padding(.top, 6)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Button { savedPage = index } label: {
                        HStack(spacing: 10) {
                            Image(systemName: symbols[index]).font(.system(size: 13, weight: .medium))
                                .frame(width: 24, height: 24).foregroundStyle(page == index ? AppPalette.speech : .secondary)
                            Text(pages[index]).font(.system(size: 12, weight: page == index ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }.padding(9).background(page == index ? AppPalette.speech.opacity(0.12) : .clear,
                            in: RoundedRectangle(cornerRadius: 11)).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(practicing)
                        .accessibilityAddTraits(page == index ? [.isSelected] : [])
                }
            }
            Spacer(minLength: 10)
            VStack(alignment: .leading, spacing: 10) {
                readiness("Microphone", ready: controller.microphoneAllowed)
                readiness("Global shortcuts", ready: controller.accessibilityAllowed && controller.shortcutEnabled)
                readiness("Your models", ready: modelsReady)
            }.font(.caption)
            Button("Finish later") { finish(false, nil) }.buttonStyle(.plain)
                .font(.callout).foregroundStyle(.secondary).disabled(practicing)
                .keyboardShortcut(.cancelAction)
                .help("Resume from Setup guide. Downloads keep running while Quibble is open.")
        }.padding(18).frame(width: 195)
            .background(AppPalette.speech.opacity(0.035))
    }

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SETUP · \(page + 1) OF 4").font(.system(size: 10, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
            Text(["A little setup. A lot less typing.", "One voice. Your choice of model.", "Say something. See it written.", "A good start. Room to make it yours."][page])
                .font(.system(size: 26, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            Text(["Give Quibble access to hear you and put words at your cursor.",
                  "Start with one speech model. Add writing tools only if you want them.",
                  shortcutsReady ? "Hold your shortcut and speak. Your words will appear below." : "Try a recording here. Enable shortcuts to dictate in other apps.",
                  "Keep the essentials close. Explore the rest when you need it."][page])
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            HStack(spacing: 0) {
                concept("mic", title: "Speak", color: AppPalette.speech)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                concept("waveform", title: "Transcribe", color: AppPalette.speech)
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                concept("text.cursor", title: "At your cursor", color: AppPalette.speech)
            }.padding(.vertical, 10)
            VStack(spacing: 0) {
                permission("Microphone", symbol: "mic", detail: "Record only when you start dictation.", allowed: controller.microphoneAllowed,
                    action: controller.requestMicrophone)
                Divider().padding(.leading, 52)
                permission("Accessibility", symbol: "keyboard", detail: "Global shortcuts and inserting text.", allowed: controller.accessibilityAllowed,
                    action: controller.requestAccessibility)
                if controller.accessibilityAllowed && !controller.shortcutEnabled {
                    Divider().padding(.leading, 52)
                    HStack {
                        Label("Enable your shortcuts", systemImage: "command").font(.callout)
                        Spacer()
                        Button("Enable") {
                            controller.toggleShortcut()
                            shortcutFailure = controller.shortcutEnabled ? nil : controller.status
                        }.disabled(busy)
                    }.padding(16)
                    if let shortcutFailure {
                        Text(shortcutFailure).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 12)
                    }
                }
            }.background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "lock.shield").foregroundStyle(AppPalette.vocabulary)
                Text("Local models keep speech on your Mac. Online transcription is optional and sends audio to your chosen provider.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if !permissionsReady {
                Button("Check permissions again") { controller.refreshPermissions() }.buttonStyle(.link).font(.caption)
            }
            shortcutNotices
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 8) {
                ForEach(modelChoices) { spec in modelChoice(spec) }
            }
            if controller.engine.isOnline {
                HStack(spacing: 12) {
                    ModelIcon(modelID: controller.workflow.speechModel, size: 32)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(controller.engine.displayName).font(.callout.weight(.semibold))
                        Text(controller.cloudSpeech.hasKey ? "API key saved · Audio sent to OpenAI" : "API key needed · Separate provider billing")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage") { finish(false, .models) }
                }.padding(12).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            }
            Toggle(isOn: Binding(get: { controller.workflow.enabledSteps.contains { $0.kind == .cleanup } }, set: { setCleanup($0) })) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Polish punctuation and grammar").font(.callout.weight(.medium))
                    Text("Optional · S1-mini · 1.51 GB · Runs on your Mac").font(.caption).foregroundStyle(.secondary)
                }
            }.toggleStyle(.switch).disabled(!editingModels)
                .padding(14).background(AppPalette.instructions.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            if !missingIDs.isEmpty {
                SetupDownloadPrompt(modeName: controller.workflow.name, size: downloadSize,
                    modelNames: missingModels.map(\.title), downloading: library.downloading != nil,
                    canDownload: editingModels && missingModels.count == missingIDs.count,
                    missingCatalogEntry: missingModels.count != missingIDs.count) {
                        library.downloadSetup(missingModels, root: controller.modelRoot)
                    }
            } else if modelsReady {
                Label("Your mode’s models are downloaded", systemImage: "checkmark.circle.fill")
                    .font(.callout).foregroundStyle(AppPalette.vocabulary)
            }
            if let error = controller.workflows.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("All models & online options") { finish(false, .models) }.buttonStyle(.link)
                Spacer()
                Button("Storage folder…") { controller.chooseModels() }.buttonStyle(.link).disabled(!editingModels)
            }.font(.caption)
            Text("Downloads come from Hugging Face. Models load when needed and unload after two idle minutes. You can keep exploring this guide while they download.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var modelChoices: [LocalModelSpec] {
        let groups = ModelVariantGroup.make(from: library.models.filter { $0.role == "Speech" })
        var families = ["cohere", "qwen3-asr-17b", "whisper-turbo"]
        if let current = groups.first(where: { $0.variants.contains { $0.name == controller.workflow.speechModel } }),
           !families.contains(current.id) { families.insert(current.id, at: 0) }
        let writingReserve = ModelVariantGroup.additionalModelBytes(for: controller.workflow,
            hasVocabulary: vocabulary.enabled && vocabulary.entries.contains(where: \.enabled), models: library.models)
        return families.compactMap { family in
            groups.first { $0.id == family }?.recommendedVariant(
                physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                selectedID: controller.workflow.speechModel, installed: library.installed,
                additionalModelBytes: writingReserve)
        }
    }

    private func modelChoice(_ spec: LocalModelSpec) -> some View {
        let selected = controller.workflow.speechModel == spec.name
        return Button {
            if let engine = SpeechEngine(rawValue: spec.name) { _ = controller.selectSpeechEngine(engine) }
        } label: {
            HStack(spacing: 12) {
                ModelIcon(modelID: spec.name, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(spec.title).font(.callout.weight(.semibold))
                        if spec.logicalModelID == "cohere" { Text("Recommended").font(.system(size: 9, weight: .medium)).foregroundStyle(AppPalette.speech) }
                        if spec.isExperimental { Text("Experimental").font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary) }
                    }
                    Text(modelSummary(spec))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(spec.sizeLabel).font(.caption.monospacedDigit())
                    if library.installed.contains(spec.name) { Text("Downloaded").font(.system(size: 9)).foregroundStyle(.secondary) }
                }
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? AppPalette.speech : Color.secondary.opacity(0.35))
            }.padding(12).background(selected ? AppPalette.speech.opacity(0.085) : Color.primary.opacity(0.025),
                in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!editingModels)
            .accessibilityLabel("\(spec.title), \(spec.precisionLabel), \(spec.sizeLabel)" + (selected ? ", selected" : ""))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func modelSummary(_ spec: LocalModelSpec) -> String {
        let purpose: String
        switch spec.logicalModelID {
        case "cohere": purpose = "Everyday dictation"
        case "qwen3-asr-17b": purpose = "Alternative speech model"
        case "whisper-turbo": purpose = "Smaller download"
        default: purpose = "Your current model"
        }
        return purpose + " · " + spec.precisionLabel
    }

    private func setCleanup(_ enabled: Bool) {
        guard editingModels else { return }
        var workflow = controller.workflow
        let indices = workflow.steps.indices.filter { workflow.steps[$0].kind == .cleanup }
        if indices.isEmpty && enabled { workflow.steps.append(.init(kind: .cleanup)) }
        else { for index in indices { workflow.steps[index].enabled = enabled } }
        _ = controller.workflows.save(workflow)
    }

    private var practice: some View {
        VStack(alignment: .leading, spacing: 18) {
            SetupShortcutDemo(keys: controller.dictationShortcut.keys,
                recording: controller.recording && (practicing || controller.setupPracticeRecording),
                processing: controller.processing && (practicing || controller.setupPracticeRecording), processingStage: controller.status,
                paused: busy, transcript: practiceText)
            if let lastCompletedPracticeText, lastCompletedPracticeText.count > 160, !practicing {
                DisclosureGroup("Full test transcript") {
                    Text(lastCompletedPracticeText).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }.font(.caption).foregroundStyle(.secondary)
            }
            VStack(spacing: 12) {
                if practicing && controller.recording {
                    HStack(spacing: 12) {
                        Button("Cancel test") { controller.cancel() }.keyboardShortcut(.cancelAction)
                        Button("Finish test") { controller.stopRecording() }.buttonStyle(.borderedProminent)
                    }
                } else if practicing {
                    Button("Cancel test") { controller.cancel() }.keyboardShortcut(.cancelAction)
                } else {
                    Button(practiceText == nil ? (shortcutsReady ? "Or click to record" : "Record") : "Record again") {
                        practiceText = nil; practiceStatus = nil
                        controller.startSetupPractice()
                        practicing = controller.recording
                        if !practicing { practiceStatus = controller.status }
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(busy || !canPractice)
                }
                if let practiceStatus {
                    Text(practiceStatus).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Text(controller.engine.isOnline ? "Test audio is sent to OpenAI. Text is kept here for review." : "This test runs on your Mac. Text is kept here for review.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }.frame(maxWidth: .infinity)
            if !canPractice {
                HStack {
                    Label(!controller.microphoneAllowed ? "Microphone access needed" : library.downloading != nil ? "Your models are downloading" : "Set up your models first", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Go to setup") { savedPage = controller.microphoneAllowed ? 1 : 0 }.buttonStyle(.link).font(.caption).disabled(practicing)
                }
            }
            if shortcutsReady { HStack {
                Text("Prefer hands-free?").font(.caption).foregroundStyle(.secondary)
                ShortcutKeys(keys: controller.toggleDictationShortcut.keys)
                Text("Press to start. Press again to finish.").font(.caption).foregroundStyle(.secondary)
            } } else {
                HStack {
                    Label("Global shortcuts need setup", systemImage: "keyboard").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Set up shortcuts") { savedPage = 0 }.buttonStyle(.link).font(.caption).disabled(practicing)
                }
            }
            shortcutNotices
        }
    }

    @ViewBuilder private var shortcutNotices: some View {
        if !controller.shortcutConflictWarnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Shortcut conflict", systemImage: "exclamationmark.triangle")
                        .font(.caption.weight(.medium)).foregroundStyle(.orange)
                    Spacer()
                    Button("Change shortcuts") { finish(false, .general) }.buttonStyle(.link).font(.caption).disabled(practicing)
                }
                ForEach(controller.shortcutConflictWarnings, id: \.self) { warning in
                    Text(warning).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(12).background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var personalize: some View {
        VStack(alignment: .leading, spacing: 14) {
            lesson("Your names, spelled your way", detail: "Add names and technical terms in Vocabulary. Quibble checks saved spellings against your speech.", symbol: "character.book.closed", color: AppPalette.vocabulary, target: .vocabulary)
            lesson("A mode for each kind of writing", detail: "Keep the transcript, clean it up, or add your own instructions. Steps run in the order you choose.", symbol: "point.3.connected.trianglepath.dotted", color: AppPalette.instructions, target: .modes)
            lesson("Your shortcuts. Your HUD.", detail: "Change both shortcuts, choose a HUD layout and material, and find the sound that feels right.", symbol: "slider.horizontal.3", color: AppPalette.speech, target: .general)
            lesson("Your words, easy to find", detail: "History keeps text for this session by default. Optional local history lasts seven days; audio is not kept.", symbol: "clock.arrow.circlepath", color: .secondary, target: .history)
            HStack(spacing: 10) {
                Image(systemName: ready ? "checkmark.circle.fill" : "circle.dashed").foregroundStyle(ready ? AppPalette.vocabulary : .secondary)
                Text(ready ? "You’re set up. Try your shortcut in any text field." : "You can explore now and finish setup later.").font(.callout)
            }.padding(.top, 4)
        }
    }

    @ViewBuilder private var downloadShelf: some View {
        if let id = library.downloading {
            Divider()
            SetupDownloadShelf(state: .init(modelName: library.models.first { $0.name == id }?.title ?? id,
                phase: library.downloadPhase == .checking ? .checking : library.downloadPhase == .downloading ? .downloading : .preparing,
                progress: library.progress, bytesReceived: library.bytesReceived, expectedBytes: library.expectedBytes,
                bytesPerSecond: library.bytesPerSecond, lastProgressAt: library.lastProgressAt,
                queuedCount: library.queuedDownloads.count)) { library.cancelDownload() }
        } else if !library.message.isEmpty {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: library.downloadOutcome == .completed ? "checkmark.circle" : "info.circle").foregroundStyle(.secondary)
                Text(library.message).font(.caption).textSelection(.enabled).lineLimit(3)
                Spacer(minLength: 0)
                if !modelsReady { Button("Review") { savedPage = 1 }.font(.caption).disabled(practicing) }
            }.padding(.horizontal, 22).padding(.vertical, 12)
        }
    }

    private func readiness(_ title: String, ready: Bool) -> some View {
        Label(title, systemImage: ready ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(ready ? AppPalette.vocabulary : .secondary)
            .accessibilityLabel(title + (ready ? ", ready" : ", needs setup"))
    }

    private func permission(_ title: String, symbol: String, detail: String, allowed: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(AppPalette.speech).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if allowed { Image(systemName: "checkmark.circle.fill").foregroundStyle(AppPalette.vocabulary).accessibilityLabel(title + " allowed") }
            else { Button("Allow", action: action).disabled(busy).accessibilityLabel("Allow " + title) }
        }.padding(16)
    }

    private func concept(_ symbol: String, title: String, color: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 25, weight: .regular)).foregroundStyle(color)
                .frame(width: 56, height: 56).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 16))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }

    private func updatePracticeRouting() {
        controller.setSetupPracticeEnabled(page == 2 && canPractice)
    }

    private func lesson(_ title: String, detail: String, symbol: String, color: Color, target: QuibblePage) -> some View {
        Button { finish(false, target) } label: {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(color)
                    .frame(width: 38, height: 38).background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.callout.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.tertiary).padding(.top, 5)
            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// The idle illustration yields to the recorder's real state. No synthetic
/// audio metering is used; the only live result is the completed transcript.
private struct SetupShortcutDemo: View {
    let keys: [String]
    let recording: Bool
    let processing: Bool
    let processingStage: String
    let paused: Bool
    let transcript: String?
    @State private var started = Date()
    @State private var rewardStrength = 0.0
    @State private var replayText: String?
    @State private var replayReady = false
    @AppStorage("onboarding.firstPracticeSuccess.v1") private var hasPracticedSuccessfully = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let labels = ["Hold", "Speak", "Release", "Written"]
    private var phrase: String {
        guard let replayText else { return "Let’s take a walk after lunch." }
        // Keep the looping lesson compact; the success view shows the full result.
        return String(replayText.prefix(160)) + (replayText.count > 160 ? "…" : "")
    }
    private var typingDuration: Double { max(1.6, Double(phrase.count) / 28) }
    private enum Phase { case illustration, listening, processing, written }
    private var phase: Phase {
        if recording { return .listening }
        if processing { return .processing }
        return transcript != nil && !replayReady ? .written : .illustration
    }
    private var title: String {
        switch phase {
        case .illustration: replayText == nil ? "Shortcut demo" : "Shortcut replay"
        case .listening: "Listening"
        case .processing: "Processing"
        case .written: "Your dictation"
        }
    }
    private var symbol: String {
        switch phase {
        case .illustration: "play.rectangle"
        case .listening: "mic.fill"
        case .processing: "text.bubble"
        case .written: "checkmark.circle.fill"
        }
    }
    private var note: String {
        switch phase {
        case .illustration: paused ? "Demo paused" : replayText == nil ? "Illustration only" : "Your last test · No recording"
        case .listening: "Microphone on"
        case .processing: "You can stop speaking"
        case .written: "That’s your voice, written."
        }
    }
    private var accessibilitySummary: String {
        switch phase {
        case .listening: return "Listening. Microphone on."
        case .processing: return "Processing your speech."
        case .written: return "Your test dictation: " + (transcript ?? "")
        case .illustration:
            let instruction = "Shortcut demonstration: hold \(keys.joined(separator: " ")), speak, then release to transcribe. No recording."
            guard let replayText else { return instruction }
            return instruction + " Replaying your last test: " + replayText
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || paused || phase != .illustration)) { context in
            let time = reduceMotion ? 4.3 + typingDuration : max(0, context.date.timeIntervalSince(started)).truncatingRemainder(dividingBy: 6.8 + typingDuration)
            let demoStep = time < 1.3 ? 0 : time < 3.3 ? 1 : time < 4.3 ? 2 : 3
            let step = phase == .illustration ? demoStep : phase == .listening ? 1 : phase == .processing ? 2 : 3
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(phase == .illustration ? Color.primary : AppPalette.speech)
                        .contentTransition(.opacity)
                    Spacer()
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: note)
                }
                if phase == .written, let transcript {
                    Text(transcript).font(.body).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 18) {
                        SetupDemoKeycaps(keys: keys, pressed: recording || (phase == .illustration && time >= 0.55 && step < 2))
                        Group {
                            if processing && !reduceMotion { ProgressView().controlSize(.small) }
                            else { Image(systemName: recording ? "mic" : processing ? "ellipsis" : "arrow.right").foregroundStyle(AppPalette.speech) }
                        }.frame(width: 18)
                        Text(displayText(time: time, step: step))
                            .font(.callout).foregroundStyle(phase != .illustration || step == 3 ? .primary : .secondary)
                            .lineLimit(3).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .contentTransition(phase == .illustration && step == 3 ? .identity : .opacity)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: processingStage)
                    }
                }
                HStack(spacing: 7) {
                    ForEach(0..<4, id: \.self) { index in
                        HStack(spacing: 5) {
                            Circle().fill(index <= step ? AppPalette.speech : Color.secondary.opacity(0.25)).frame(width: 5, height: 5)
                            Text(labels[index]).font(.caption2).foregroundStyle(index == step ? .primary : .secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }.padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(phase == .illustration ? Color.primary.opacity(0.035) : AppPalette.speech.opacity(0.09 + rewardStrength * 0.055))
                }
                .shadow(color: AppPalette.speech.opacity(rewardStrength * 0.22), radius: 18)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: step)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.26), value: phase)
        }
        .onChange(of: phase) { _, phase in if phase == .illustration { started = Date() } }
        .task(id: transcript) {
            rewardStrength = 0; replayReady = false
            guard let transcript, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            replayText = transcript
            let firstSuccess = !hasPracticedSuccessfully
            hasPracticedSuccessfully = true
            if !reduceMotion { withAnimation(.easeOut(duration: 0.3)) { rewardStrength = firstSuccess ? 1 : 0.5 } }
            do { try await Task.sleep(for: .seconds(firstSuccess ? 1.0 : 0.6)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 1.4)) { rewardStrength = 0 }
            // First show the actual completed result. The following typing is a
            // clearly labelled replay, never a claim of streaming recognition.
            let readingTime = min(7, max(3.2, Double(transcript.split(whereSeparator: \.isWhitespace).count) * 0.22))
            do { try await Task.sleep(for: .seconds(readingTime)) } catch { return }
            guard !Task.isCancelled else { return }
            started = Date()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.26)) { replayReady = true }
        }
        .onChange(of: reduceMotion) { _, enabled in if enabled { rewardStrength = 0 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private func displayText(time: Double, step: Int) -> String {
        if recording { return "Speak naturally." }
        if processing { return processingStage }
        if step == 3 {
            return String(phrase.prefix(reduceMotion ? phrase.count : Int(min(1, max(0, time - 4.3) / typingDuration) * Double(phrase.count))))
        }
        return step == 1 ? "Say a short sentence…" : step == 2 ? "Release to transcribe…" : "Hold your shortcut…"
    }
}

private struct SetupDemoKeycaps: View {
    let keys: [String]
    let pressed: Bool
    @State private var depressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(key).font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.horizontal, 10).frame(height: 29)
                    .background {
                        RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor))
                            .overlay(RoundedRectangle(cornerRadius: 7).fill(AppPalette.speech.opacity(depressed ? 0.17 : 0.035)))
                    }
                    .shadow(color: .black.opacity(depressed ? 0.035 : 0.12), radius: depressed ? 0.5 : 2, y: depressed ? 0 : 3)
                    .offset(y: reduceMotion ? 0 : depressed ? 3 : 0)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.14)).offset(y: 4))
            }
        }.padding(.vertical, 6)
            .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.64), value: depressed)
            .onAppear { depressed = pressed }
            .onChange(of: pressed) { _, pressed in depressed = pressed }
            .accessibilityElement(children: .ignore).accessibilityLabel(keys.joined(separator: " "))
            .accessibilityValue(pressed ? "Pressed" : "Released")
    }
}

/// Value-only presentation, also used by isolated visual fixtures. It never
/// instantiates a controller, changes preferences, or starts a download itself.
struct SetupDownloadPrompt: View {
    let modeName: String
    let size: String
    let modelNames: [String]
    let downloading: Bool
    let canDownload: Bool
    let missingCatalogEntry: Bool
    let download: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle").font(.title2).foregroundStyle(AppPalette.speech)
                VStack(alignment: .leading, spacing: 4) {
                    Text("For " + modeName).font(.caption.weight(.semibold))
                    Text(modelNames.joined(separator: " + ")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("≈ " + size).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Button(downloading ? "Download in progress" : "Download \(modelNames.count == 1 ? "model" : "models")", action: download)
                .buttonStyle(.borderedProminent).controlSize(.large).disabled(!canDownload)
            if missingCatalogEntry {
                Text("A model is missing from the catalog. Choose another in Models library.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(14).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct SetupDownloadShelf: View {
    struct State {
        enum Phase { case preparing, downloading, checking }
        let modelName: String
        let phase: Phase
        var progress = 0.0
        var bytesReceived: Int64 = 0
        var expectedBytes: Int64?
        var bytesPerSecond: Double?
        var lastProgressAt: Date?
        var queuedCount = 0
    }
    let state: State
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(state.lastProgressAt ?? context.date))
            let waiting = state.phase != .checking && elapsed >= 8
            HStack(spacing: 14) {
                Image(systemName: waiting ? "network" : state.phase == .checking ? "checkmark.shield" : "arrow.down.circle")
                    .font(.title2).foregroundStyle(AppPalette.speech).frame(width: 28)
                    .contentTransition(.opacity)
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(state.modelName).font(.caption.weight(.semibold)).lineLimit(1)
                        Spacer(minLength: 8)
                        if state.phase == .preparing || state.phase == .checking {
                            if reduceMotion {
                                Image(systemName: "ellipsis").font(.caption2).frame(width: 12).accessibilityHidden(true)
                            } else {
                                ProgressView().controlSize(.mini).frame(width: 12, height: 12).accessibilityHidden(true)
                            }
                        }
                        Text(waiting ? "Waiting for data" : state.phase == .checking ? "Checking files" : state.phase == .preparing ? "Connecting" : "Downloading")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    progressIndicator
                    HStack(spacing: 8) {
                        Text(byteStatus).font(.caption.monospacedDigit())
                        Spacer(minLength: 8)
                        if waiting {
                            Text("No new data for \(Int(elapsed))s").font(.caption.monospacedDigit())
                        } else if state.phase == .downloading, let speed = state.bytesPerSecond, speed.isFinite, speed > 0, speed < Double(Int64.max) {
                            Text(Self.bytes(Int64(speed)) + "/s").font(.caption.monospacedDigit())
                        } else {
                            Text(state.phase == .checking ? "Finishing this model…" : "Hugging Face").font(.caption)
                        }
                    }.foregroundStyle(.secondary)
                    Text(state.queuedCount > 0 ? "\(state.queuedCount) more \(state.queuedCount == 1 ? "model" : "models") queued · Keep exploring" : "Keep exploring. Downloads continue while Quibble is open.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button("Cancel", action: cancel).font(.caption)
            }.padding(.horizontal, 22).padding(.vertical, 13)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: waiting)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: state.phase)
        }
    }

    @ViewBuilder private var progressIndicator: some View {
        if state.bytesReceived > 0 {
            ProgressView(value: fraction).progressViewStyle(.linear)
                .animation(reduceMotion ? nil : .linear(duration: 0.2), value: fraction)
                .accessibilityLabel("Model download progress")
                .accessibilityValue(byteStatus)
        } else if reduceMotion {
            Capsule().fill(.primary.opacity(0.08)).frame(height: 4).accessibilityHidden(true)
        } else {
            ProgressView().progressViewStyle(.linear).accessibilityLabel("Preparing download")
        }
    }
    private var fraction: Double {
        let raw = state.expectedBytes.flatMap { $0 > 0 ? Double(state.bytesReceived) / Double($0) : nil } ?? state.progress
        return raw.isFinite ? min(1, max(0, raw)) : 0
    }
    private var byteStatus: String {
        guard state.bytesReceived > 0 else { return state.phase == .checking ? "Checking the download…" : "Preparing the download…" }
        if let expected = state.expectedBytes, expected > 0 {
            return Self.bytes(state.bytesReceived) + " of " + Self.bytes(expected)
        }
        return Self.bytes(state.bytesReceived) + " received · ≈ \(Int(fraction * 100))%"
    }
    private static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, count), countStyle: .file)
    }
}

#if DEBUG
#Preview("Setup · Download states") {
    ScrollView {
        VStack(spacing: 20) {
            SetupDownloadPrompt(modeName: "Basic cleanup", size: "3.7 GB", modelNames: ["Cohere Transcribe", "S1-mini"],
                downloading: false, canDownload: true, missingCatalogEntry: false) {}
                .padding(.horizontal, 22)
            SetupDownloadShelf(state: .init(modelName: "Cohere Transcribe", phase: .preparing,
                lastProgressAt: .now, queuedCount: 1)) {}
            SetupDownloadShelf(state: .init(modelName: "Cohere Transcribe", phase: .downloading, progress: 0.36,
                bytesReceived: 810_000_000, expectedBytes: 2_250_000_000, bytesPerSecond: 24_000_000,
                lastProgressAt: .now, queuedCount: 1)) {}
            SetupDownloadShelf(state: .init(modelName: "Cohere Transcribe", phase: .downloading, progress: 0.36,
                bytesReceived: 810_000_000, expectedBytes: 2_250_000_000, bytesPerSecond: 24_000_000,
                lastProgressAt: Date().addingTimeInterval(-14))) {}
            SetupDownloadShelf(state: .init(modelName: "Cohere Transcribe", phase: .checking, progress: 1,
                bytesReceived: 2_250_000_000, expectedBytes: 2_250_000_000)) {}
        }.padding(.vertical, 22)
    }.frame(width: 740, height: 590).background(Color(nsColor: .windowBackgroundColor)).tint(AppPalette.speech)
}
#endif
