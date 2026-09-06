import AppKit
import AVFoundation
import Combine
import QuibbleCore
import QuibbleInference
import UniformTypeIdentifiers

@MainActor
final class DictationController: ObservableObject {
    @Published var status = "Choose a mode, then record or import an audio file."
    @Published var transcript = "" {
        didSet { scheduleTranscriptObservation() }
    }
    @Published var rawTranscript = ""
    let audioInputs = AudioInputDevices()
    let workflows = WorkflowLibrary()
    let cloudSpeech = CloudSpeechConnection()
    private var workflowObservation: AnyCancellable?
    private var cloudObservation: AnyCancellable?
    var workflow: DictationWorkflow { workflows.selected }
    var mode: RefinementMode {
        get { workflow.enabledSteps.contains { $0.kind == .prompt } ? .custom : workflow.enabledSteps.contains { $0.kind == .cleanup } ? .basic : .exact }
        set { workflows.select(newValue == .exact ? "minimal" : "basic") }
    }
    @Published var customInstructions = UserDefaults.standard.string(forKey: "customInstructions") ?? "" {
        didSet { UserDefaults.standard.set(customInstructions, forKey: "customInstructions") }
    }
    @Published var contextEnabled = UserDefaults.standard.object(forKey: "contextEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(contextEnabled, forKey: "contextEnabled") }
    }
    @Published var contextApplication = "No application captured yet"
    @Published var contextPreview = ""
    @Published var contextStatus = "Application context is paused."
    var engine: SpeechEngine {
        get { SpeechEngine(rawValue: workflow.speechModel) ?? .cohere4bit }
        set {
            _ = selectSpeechEngine(newValue)
        }
    }
    @discardableResult func selectSpeechEngine(_ engine: SpeechEngine) -> Bool {
        guard !recording && !processing else { return false }
        var updated = workflow; updated.speechModel = engine.rawValue
        if !engine.languageCodes.contains(updated.asr.language) { updated.asr.language = "en" }
        guard workflows.save(updated) else { return false }
        UserDefaults.standard.set(engine.rawValue, forKey: "speechEngine")
        return true
    }
    @Published private(set) var memorySnapshot: [String: Int] = [:]
    @Published private(set) var memoryUpdatedAt: Date?
    func refreshMemory() {
        Task { memorySnapshot = await inference.memoryUsage(); memoryUpdatedAt = Date() }
    }
    func unloadModels() {
        guard !recording && !processing else { return }
        Task { await inference.unload(); refreshMemory(); status = "Models unloaded. They will load when needed." }
    }
    func removeModel(_ spec: LocalModelSpec) {
        guard !recording && !processing && modelLibrary.downloading == nil else { return }
        processing = true; status = "Removing \(spec.title)…"
        let root = modelRoot
        task = Task {
            defer { processing = false }
            await inference.unload()
            guard !Task.isCancelled else { return }
            _ = modelLibrary.trash(spec, root: root)
            status = modelLibrary.message
            refreshMemory()
        }
    }
    let history = TranscriptHistory(directory: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Quibble/History"))
    let vocabulary = VocabularyStore()
    let modelLibrary = ModelLibrary()
    private var transcriptBaseline: (id: UUID, text: String)?
    private var transcriptWasEdited = false
    private var editTask: Task<Void, Never>?
    private var externalEditTask: Task<Void, Never>?
    @Published private(set) var inserting = false
    private var recordingApplication = ""
    private var recordingContext = ""
    private var recordingWorkflow: DictationWorkflow?

    @Published var recording = false { didSet { if recording { idleUnloadTask?.cancel() } else { scheduleIdleUnload() } } }
    @Published var processing = false { didSet { if processing { idleUnloadTask?.cancel() } else { scheduleIdleUnload() } } }
    @Published var shortcutEnabled = false
    @Published var microphoneAllowed = false
    @Published var accessibilityAllowed = false
    @Published private(set) var setupPracticeRecording = false
    private var setupPracticeEnabled = false
    func setSetupPracticeEnabled(_ enabled: Bool) { setupPracticeEnabled = enabled }
    func startSetupPractice() {
        guard !recording && !processing && !inserting else { return }
        startRecording(global: false)
        setupPracticeRecording = recording
    }
    @Published var lastResult: InferenceResult?
    struct SpeechMeasurement {
        let audioSeconds: Double
        let transcriptionSeconds: Double
        var realTimeMultiple: Double { audioSeconds / transcriptionSeconds }
    }
    // Session-only scalar samples; no transcripts, prompts, audio, or disk writes.
    @Published private(set) var speechMeasurements: [String: SpeechMeasurement] = [:]
    @Published private(set) var stepMeasurements: [String: Double] = [:]
    @Published var releaseToResult: Double?
    @Published var insertionSeconds: Double?
    @Published var modelRoot: URL

    @Published var hudEnabled = UserDefaults.standard.object(forKey: "hudEnabled") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(hudEnabled, forKey: "hudEnabled"); feedback.hudEnabled = hudEnabled
            recorder?.spectrumEnabled = hudEnabled
        }
    }
    @Published var soundEnabled = UserDefaults.standard.object(forKey: "soundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(soundEnabled, forKey: "soundEnabled"); feedback.soundEnabled = soundEnabled }
    }
    @Published var hudStyle = HUDStyle(rawValue: UserDefaults.standard.string(forKey: "hudStyle") ?? "") ?? .solid {
        didSet { UserDefaults.standard.set(hudStyle.rawValue, forKey: "hudStyle"); feedback.style = hudStyle }
    }
    @Published var hudMaterial = HUDMaterial.restored() {
        didSet { UserDefaults.standard.set(hudMaterial.rawValue, forKey: HUDMaterial.preferenceKey); feedback.material = hudMaterial }
    }
    @Published private(set) var dictationShortcut = DictationController.readShortcut("dictationShortcut.v1", fallback: .dictation)
    @Published private(set) var toggleDictationShortcut = DictationController.readShortcut("toggleShortcut.v1", fallback: .toggleDictation)
    @Published private(set) var pasteShortcut = DictationController.readShortcut("pasteShortcut.v1", fallback: .pasteLast)
    private let shortcutConflictMonitor = ShortcutConflictMonitor()
    @Published private(set) var shortcutConflictSnapshot = ShortcutConflictMonitor.Snapshot()
    func refreshShortcutConflicts() { shortcutConflictSnapshot = shortcutConflictMonitor.refresh() }
    var shortcutConflictWarnings: [String] {
        ShortcutAction.allCases.flatMap { action in
            let binding = shortcutBinding(for: action)
            return shortcutConflictSnapshot.conflicts(with: binding).map { action.title + ": " + $0.message(for: binding) }
        }
    }
    private static func readShortcut(_ key: String, fallback: ShortcutBinding) -> ShortcutBinding {
        guard let data = UserDefaults.standard.data(forKey: key), data.count < 4096,
              let value = try? JSONDecoder().decode(ShortcutBinding.self, from: data), value.validationError == nil else { return fallback }
        return value
    }
    func shortcutBinding(for action: ShortcutAction) -> ShortcutBinding {
        switch action { case .hold: dictationShortcut; case .toggle: toggleDictationShortcut; case .pasteLast: pasteShortcut }
    }
    func shortcutValidation(_ value: ShortcutBinding, for action: ShortcutAction) -> String? {
        if let error = value.validationError { return error }
        if let conflict = ShortcutAction.allCases.first(where: { $0 != action && value.conflicts(with: shortcutBinding(for: $0)) }) {
            return "\(conflict.title) already uses this combination."
        }
        return shortcutConflictSnapshot.conflicts(with: value).first.map { $0.message(for: value) + " Choose another combination or change it there first." }
    }
    @discardableResult func saveShortcut(_ value: ShortcutBinding, for action: ShortcutAction) -> Bool {
        refreshShortcutConflicts()
        guard !recording && !processing && !inserting, shortcutValidation(value, for: action) == nil,
              let data = try? JSONEncoder().encode(value) else { return false }
        switch action { case .hold: dictationShortcut = value; case .toggle: toggleDictationShortcut = value; case .pasteLast: pasteShortcut = value }
        UserDefaults.standard.set(data, forKey: action.preferenceKey)
        shortcut.state = ShortcutState(dictation: dictationShortcut, toggleDictation: toggleDictationShortcut, pasteLast: pasteShortcut)
        return true
    }
    func suspendShortcuts(_ value: Bool) { shortcut.suspended = value }
    let feedback = DictationFeedback()
    private var meterTask: Task<Void, Never>?
    private let inference = LocalInference()
    private let shortcut = GlobalShortcut()
    private var session = DictationSession()
    private var recorder: MicrophoneRecorder?
    private var recordingURL: URL?
    private var temporaryAudio: Set<URL> = []
    private var target: TargetApplication?
    private var requestedInsertion = false
    private var recordingShortcut: ShortcutAction?
    private var task: Task<Void, Never>?
    private var idleUnloadTask: Task<Void, Never>?
    private var presentingPanel = false
    private var observers: [NSObjectProtocol] = []

    init() {
        let defaultPath = Bundle.main.object(forInfoDictionaryKey: "QuibblePrototypeModelsPath") as? String
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Quibble/Models").path
        modelRoot = URL(fileURLWithPath: UserDefaults.standard.string(forKey: "modelRoot") ?? defaultPath)
        // Choose formats only for a new installation. Existing modes and manual
        // precision choices remain authoritative, including original weights.
        let defaults = UserDefaults.standard
        let hasPreviousSetup = ["workflows.v1", "speechEngine", "didFinishQuickTour.v1",
            "onboarding.completed.v1", "onboarding.deferred.v1", "modelRoot"]
            .contains { defaults.object(forKey: $0) != nil }
        if !hasPreviousSetup {
            modelLibrary.refresh(root: modelRoot)
            let groups = ModelVariantGroup.make(from: modelLibrary.models)
            let hasVocabulary = vocabulary.enabled && vocabulary.entries.contains(where: \.enabled)
            for var preset in workflows.workflows {
                guard let group = groups.first(where: { $0.variants.contains { $0.name == preset.speechModel } }),
                    let recommended = group.recommendedVariant(
                        physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
                        installed: modelLibrary.installed,
                        additionalModelBytes: ModelVariantGroup.additionalModelBytes(
                            for: preset, hasVocabulary: hasVocabulary, models: modelLibrary.models)) else { continue }
                preset.speechModel = recommended.name
                _ = workflows.save(preset)
            }
        }
        workflowObservation = workflows.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        cloudObservation = cloudSpeech.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }
        contextEnabled = false
        feedback.hudEnabled = hudEnabled; feedback.soundEnabled = soundEnabled; feedback.style = hudStyle; feedback.material = hudMaterial
        if dictationShortcut.conflicts(with: pasteShortcut) { dictationShortcut = .dictation; pasteShortcut = .pasteLast }
        if toggleDictationShortcut.conflicts(with: dictationShortcut) || toggleDictationShortcut.conflicts(with: pasteShortcut) {
            // Preserve existing custom shortcuts when adding the new action.
            let alternatives: [ShortcutBinding] = [.toggleDictation,
                .init(keyCode: 49, modifiers: ShortcutBinding.control | ShortcutBinding.option | ShortcutBinding.shift, keyName: "Space"),
                .init(keyCode: 2, modifiers: ShortcutBinding.control | ShortcutBinding.option, keyName: "D")]
            toggleDictationShortcut = alternatives.first { !$0.conflicts(with: dictationShortcut) && !$0.conflicts(with: pasteShortcut) } ?? .toggleDictation
            if let data = try? JSONEncoder().encode(toggleDictationShortcut) { UserDefaults.standard.set(data, forKey: ShortcutAction.toggle.preferenceKey) }
        }
        shortcut.state = ShortcutState(dictation: dictationShortcut, toggleDictation: toggleDictationShortcut, pasteLast: pasteShortcut)
        feedback.onCancel = { [weak self] in self?.cancel() }
        feedback.onFinish = { [weak self] in self?.stopRecording() }
        refreshPermissions()
        refreshShortcutConflicts()
        shortcut.onPress = { [weak self] in self?.startShortcutRecording(.hold) }
        shortcut.onRelease = { [weak self] in
            guard let self, recordingShortcut == .hold else { return }
            stopRecording()
        }
        shortcut.onToggle = { [weak self] in
            guard let self else { return }
            if recording { stopRecording() } else { startShortcutRecording(.toggle) }
        }
        shortcut.onCancel = { [weak self] in self?.cancel() }
        shortcut.onPasteLast = { [weak self] in self?.pasteLastTranscript() }
        if accessibilityAllowed && (UserDefaults.standard.object(forKey: "shortcutEnabled") as? Bool ?? true) {
            shortcutEnabled = shortcut.start()
        }
        audioInputs.onDevicesChanged = { [weak self] in
            guard let self, recording, let recorder,
                  !audioInputs.devices.contains(where: { $0.uid == recorder.device.uid && $0.deviceID == recorder.device.deviceID }) else { return }
            interruptRecording("The recording microphone was disconnected.")
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                self?.refreshPermissions(); self?.refreshShortcutConflicts()
            } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.cancel() } })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated {
                guard let self else { return }
                self.cancel()
                for file in self.temporaryAudio { try? FileManager.default.removeItem(at: file) }
            } })
    }

    private func recordModelMeasurements(_ result: InferenceResult) {
        let speechModels = Set(modelLibrary.models.filter { $0.role == "Speech" }.map(\.name))
        let textModels = Set(modelLibrary.models.filter { $0.role != "Speech" }.map(\.name))
        if speechModels.contains(result.engine), result.audioSeconds.isFinite, result.audioSeconds > 0,
           result.transcriptionSeconds.isFinite, result.transcriptionSeconds > 0,
           (result.audioSeconds / result.transcriptionSeconds).isFinite {
            speechMeasurements[result.engine] = SpeechMeasurement(audioSeconds: result.audioSeconds,
                transcriptionSeconds: result.transcriptionSeconds)
        }
        for stage in result.stages ?? [] where textModels.contains(stage.model)
            && stage.status == "Completed" && stage.seconds.isFinite && stage.seconds >= 0 {
            stepMeasurements[stage.model] = stage.seconds
        }
    }

    func refreshPermissions() {
        history.prune()
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAllowed = AXIsProcessTrusted()
        if !accessibilityAllowed && shortcutEnabled { shortcut.stop(); shortcutEnabled = false }
    }

    private func scheduleIdleUnload() {
        idleUnloadTask?.cancel()
        guard !recording && !processing else { return }
        idleUnloadTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            guard let self, !self.recording, !self.processing, !Task.isCancelled else { return }
            await self.inference.unload()
        }
    }

    func requestMicrophone() {
        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else if !microphoneAllowed {
                openPrivacy("Privacy_Microphone")
            }
            refreshPermissions()
        }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
        refreshPermissions()
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    func toggleShortcut() {
        refreshPermissions()
        if shortcutEnabled { shortcut.stop(); shortcutEnabled = false; UserDefaults.standard.set(false, forKey: "shortcutEnabled"); return }
        guard accessibilityAllowed else { status = "Allow Accessibility, then enable the shortcut."; requestAccessibility(); return }
        shortcutEnabled = shortcut.start()
        UserDefaults.standard.set(shortcutEnabled, forKey: "shortcutEnabled")
        status = shortcutEnabled ? "Hold \(dictationShortcut.display) in a text field to dictate. Escape cancels while holding."
            : "The shortcut could not start. Check Accessibility and Input Monitoring in System Settings."
    }

    func chooseModels() {
        guard !recording && !processing && !presentingPanel && modelLibrary.downloading == nil else { return }
        presentingPanel = true
        Task {
            defer { presentingPanel = false }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.message = "Choose where Quibble stores its local models."
            panel.directoryURL = modelRoot
            guard await panel.present() == .OK, let url = panel.url, !recording && !processing && modelLibrary.downloading == nil else { return }
            modelRoot = url
            UserDefaults.standard.set(url.path, forKey: "modelRoot")
        }
    }

    func preload() {
        guard !recording && !processing else { return }
        if engine.isOnline { status = "Online speech needs no local model to preload."; return }
        processing = true; status = "Loading local models…"
        let root = modelRoot, selectedEngine = engine
        task = Task {
            do {
                let start = ProcessInfo.processInfo.systemUptime
                _ = try await inference.load(root: root, withCleanup: false, engine: selectedEngine)
                try Task.checkCancellation()
                status = String(format: "Speech model ready in %.2f seconds. Workflow steps load on demand.", ProcessInfo.processInfo.systemUptime - start)
            } catch { status = Task.isCancelled ? "Cancelled." : error.localizedDescription }
            processing = false
        }
    }

    private func startShortcutRecording(_ action: ShortcutAction) {
        guard !recording && !processing && !inserting else { return }
        recordingShortcut = action
        feedback.heldShortcut = action == .hold ? dictationShortcut.display : nil
        feedback.toggleShortcut = action == .toggle ? toggleDictationShortcut.display : nil
        // A shortcut demonstrated inside setup uses the real recorder and key
        // lifecycle, but keeps its result in the guide. Other apps retain normal
        // insertion even when the guide remains open in the background.
        let practicing = setupPracticeEnabled
            && NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier
        startRecording(global: !practicing)
        setupPracticeRecording = practicing && recording
        if recording { shortcut.state.toggleRecording = action == .toggle }
        else { clearRecordingShortcut() }
    }

    private func clearRecordingShortcut() {
        recordingShortcut = nil
        feedback.heldShortcut = nil
        feedback.toggleShortcut = nil
        shortcut.state.toggleRecording = false
    }

    func startRecording(global: Bool = false) {
        guard !recording && !processing else { return }
        if engine.isOnline && !cloudSpeech.hasKey {
            status = "Add an OpenAI API key in Models → Online transcription."
            feedback.show(.warning, title: "Set up OpenAI", detail: "Open Models in Quibble", cue: "error", dismissAfter: 3)
            return
        }
        feedback.meter(power: -60, seconds: 0)
        feedback.show(.starting, title: "Starting microphone", detail: "Getting ready")
        refreshPermissions()
        guard microphoneAllowed else { status = "Allow microphone access before recording."; feedback.show(.warning, title: "Microphone access needed", detail: "Open Quibble settings", cue: "error", dismissAfter: 3); return }
        guard session.start() != nil else { return }
        observeTranscriptEdits()
        externalEditTask?.cancel()
        target = global ? TargetApplication.capture() : nil
        requestedInsertion = global
        recordingWorkflow = workflow
        recordingApplication = ""; recordingContext = ""; contextPreview = ""
        contextApplication = "Application context is paused"
        contextStatus = "Nearby text is not sent to any model."
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("quibble-\(UUID().uuidString).wav")
        do {
            let device = try audioInputs.resolveForRecording()
            let capture = try MicrophoneRecorder(url: file, device: device)
            capture.spectrumEnabled = hudEnabled
            try capture.record()
            recorder = capture
            recordingURL = file; recording = true
            temporaryAudio.insert(file)
            feedback.meter(power: -60, seconds: 0)
            feedback.show(.listening, title: "Listening", cue: "start")
            meterTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self, let recorder = self.recorder else { return }
                    if let error = recorder.error {
                        self.interruptRecording(error.localizedDescription)
                        return
                    }
                    if !recorder.isRecording {
                        self.interruptRecording("The microphone stopped recording unexpectedly.")
                        return
                    }
                    self.feedback.meter(power: recorder.averagePower,
                        peak: recorder.peakPower, spectrum: recorder.latestAmplitudes, seconds: recorder.currentTime)
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            let finishInstruction = recordingShortcut == .toggle ? "Press \(toggleDictationShortcut.display) again to finish."
                : recordingShortcut == .hold ? "Release \(dictationShortcut.display) to finish." : "Use Finish to insert."
            status = target.map { "Listening for \($0.name)… " + finishInstruction }
                ?? "Listening… The result will appear here."
        } catch { session.cancel(); recorder?.stop(); recorder = nil; try? FileManager.default.removeItem(at: file); status = error.localizedDescription; feedback.show(.warning, title: "Recording failed", detail: "See Quibble for details", cue: "error", dismissAfter: 3) }
    }

    func stopRecording() {
        clearRecordingShortcut()
        guard recording, let file = recordingURL else { return }
        let released = ProcessInfo.processInfo.systemUptime
        meterTask?.cancel(); meterTask = nil
        recorder?.stop()
        if let error = recorder?.error {
            interruptRecording(error.localizedDescription)
            return
        }
        recorder = nil; recording = false; recordingURL = nil
        session.stop()
        feedback.show(.processing, title: "Transcribing", detail: "On your Mac", cue: "stop")
        process(file: file, deleteAfter: true, target: target, startedAt: released, requestedInsertion: requestedInsertion)
        target = nil
    }

    private func interruptRecording(_ reason: String) {
        guard recording else { return }
        clearRecordingShortcut()
        meterTask?.cancel(); meterTask = nil
        recorder?.stop(); recorder = nil
        recording = false; setupPracticeRecording = false
        session.cancel(); target = nil; recordingWorkflow = nil
        // Keep a partial recording available for manual import until orderly exit.
        // Never insert a truncated utterance as if the user had finished speaking.
        let recovery = recordingURL.map { " Partial audio may be recoverable before Quibble quits at: " + $0.path } ?? ""
        recordingURL = nil
        status = reason + recovery
        feedback.show(.warning, title: "Recording interrupted", detail: "See Quibble for details", cue: "error", dismissAfter: 3)
    }

    func importAudio() {
        guard !recording && !processing && !inserting && !presentingPanel else { return }
        presentingPanel = true
        Task {
            defer { presentingPanel = false }
            let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
            panel.message = engine.isOnline ? "Choose audio to send to OpenAI for transcription. Long files are processed in sections." : "Choose an audio file. Long files are processed in sections on your Mac."
            guard await panel.present() == .OK, let file = panel.url, session.start() != nil else { return }
            observeTranscriptEdits()
            externalEditTask?.cancel()
            recordingApplication = ""; recordingContext = ""; contextPreview = ""
            contextApplication = "Imported audio"; contextStatus = "No application context for imported audio."
            session.stop(); process(file: file, deleteAfter: false, target: nil)
        }
    }

    private func process(file: URL, deleteAfter: Bool, target: TargetApplication?, startedAt: Double? = nil, requestedInsertion: Bool = false) {
        guard case .processing(let id) = session.state else { return }
        if !deleteAfter { feedback.meter(power: -60, seconds: 0) }
        processing = true
        lastResult = nil; releaseToResult = nil; insertionSeconds = nil
        let started = startedAt ?? ProcessInfo.processInfo.systemUptime, root = modelRoot
        let selectedWorkflow = deleteAfter ? recordingWorkflow ?? workflow : workflow
        recordingWorkflow = nil
        let selectedEngine = SpeechEngine(rawValue: selectedWorkflow.speechModel) ?? .cohere4bit
        status = selectedEngine.isOnline ? "Transcribing with OpenAI…" : "Transcribing locally…"
        feedback.show(.processing, title: "Transcribing", detail: selectedEngine.isOnline ? "OpenAI · Online" : "On your Mac", cue: nil)
        let selectedMode: RefinementMode = selectedWorkflow.enabledSteps.contains { $0.kind == .prompt } ? .custom : selectedWorkflow.enabledSteps.contains { $0.kind == .cleanup } ? .basic : .exact
        let shouldInsert = requestedInsertion && selectedWorkflow.destination == .insert
        let entries = vocabulary.enabled ? vocabulary.entries.filter(\.enabled) : []
        let request = RefinementRequest(mode: selectedMode, application: recordingApplication,
            context: recordingContext, instructions: customInstructions, vocabulary: entries.map(\.preferred))
        task = Task {
            defer {
                if deleteAfter { try? FileManager.default.removeItem(at: file); temporaryAudio.remove(file) }
                processing = false
                setupPracticeRecording = false
            }
            do {
                status = "Checking for speech…"
                feedback.show(.processing, title: "Checking speech", detail: "On your Mac")
                let presence = try await SpeechPresenceDetector.shared.detect(in: file)
                try Task.checkCancellation()
                guard case .processing(let activeID) = session.state, activeID == id else { return }
                if presence == .noSpeech {
                    _ = session.complete(id, text: "")
                    releaseToResult = ProcessInfo.processInfo.systemUptime - started
                    status = "No speech detected. Nothing was inserted."
                    feedback.show(.noSpeech, title: "No speech detected", detail: "Nothing to insert", cue: "cancel", dismissAfter: 2.5)
                    return
                }
                let onlineKey = selectedEngine.isOnline ? try cloudSpeech.apiKey() : nil
                let result = try await inference.transcribe(file: file, root: root, refine: selectedMode != .exact, engine: selectedEngine,
                    request: request, onlineAPIKey: onlineKey, vocabulary: entries.map(\.preferred),
                    vocabularyEntries: entries, workflow: selectedWorkflow,
                    progress: { [weak self] stage in
                        Task { @MainActor in
                            guard let self, case .processing(let active) = self.session.state, active == id else { return }
                            self.status = stage + "…"
                            self.feedback.show(.processing, title: stage.hasPrefix("Loading") ? "Loading model" : stage,
                                detail: selectedEngine.isOnline && (stage.contains("OpenAI") || stage.contains("online")) ? "OpenAI · Online" : "On your Mac")
                        }
                    })
                try Task.checkCancellation()
                guard session.complete(id, text: result.text) else { return }
                recordModelMeasurements(result)
                releaseToResult = ProcessInfo.processInfo.systemUptime - started
                if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    status = "No speech detected. Nothing was inserted."
                    feedback.show(.noSpeech, title: "No speech detected", detail: "Nothing to insert", cue: "cancel", dismissAfter: 2.5)
                    return
                }
                lastResult = result; rawTranscript = result.raw
                transcriptBaseline = nil; transcript = result.text; transcriptBaseline = (id, result.text); transcriptWasEdited = false
                var insertion: InsertionResult?
                if shouldInsert, let target {
                    let insertionStart = ProcessInfo.processInfo.systemUptime
                    inserting = true
                    feedback.show(.inserting, title: "Inserting", detail: target.name,
                        destination: .init(name: target.name, bundleID: target.bundleID, confirmed: false))
                    let outcome = await target.insert(result.text, onPasteSent: { [weak self] in
                        guard result.warning == nil else { return }
                        self?.feedback.pasteSent(to: .init(name: target.name, bundleID: target.bundleID, confirmed: false))
                    })
                    insertion = outcome
                    status = outcome.message(in: target.name, pasteShortcut: pasteShortcut.display)
                    inserting = false
                    insertionSeconds = ProcessInfo.processInfo.systemUptime - insertionStart
                    if outcome.isConfirmed { watchCorrections(target: target, text: result.text, id: id) }
                } else {
                    status = shouldInsert ? "No input destination was available. Click a field and press \(pasteShortcut.display) to paste your transcript." : "Ready. Review or copy your transcript."
                }
                history.append(TranscriptRecord(id: id, original: result.raw, text: result.text,
                    application: target?.name ?? (deleteAfter ? "Quibble" : "Imported audio"),
                    applicationBundleID: target?.bundleID ?? (deleteAfter ? Bundle.main.bundleIdentifier : nil),
                    mode: selectedWorkflow.name, engine: selectedEngine.displayName,
                    delivery: insertion?.isConfirmed == true ? "Inserted" : insertion?.wasSent == true ? "Paste sent" : shouldInsert ? "Ready to paste" : "Ready",
                    warning: result.warning, audioSeconds: deleteAfter ? result.audioSeconds : nil, segments: result.segments))
                if let warning = result.warning { status += " " + warning }
                let inserted = insertion?.isConfirmed == true
                let sent = insertion?.wasSent == true
                let needsReview = result.warning != nil || (shouldInsert && !sent)
                if sent && !needsReview {
                    if inserted, let target {
                        feedback.confirmPaste(to: .init(name: target.name, bundleID: target.bundleID, confirmed: true))
                    }
                } else { feedback.show(needsReview ? .warning : .success,
                    title: inserted ? "Inserted" : sent ? "Paste sent" : "Transcript ready",
                    detail: sent ? target!.name : shouldInsert ? "Click a field · \(pasteShortcut.display)" : "Review in Quibble",
                    destination: sent && !needsReview ? target.map { .init(name: $0.name, bundleID: $0.bundleID, confirmed: inserted) } : nil,
                    cue: needsReview ? "error" : "complete", dismissAfter: needsReview ? 3 : 0.6) }
            } catch {
                session.cancel()
                status = Task.isCancelled ? "Cancelled." : error.localizedDescription
                feedback.show(Task.isCancelled ? .cancelled : .warning,
                    title: Task.isCancelled ? "Cancelled" : "Transcription failed", detail: Task.isCancelled ? "" : "See Quibble for details",
                    cue: Task.isCancelled ? nil : "error", dismissAfter: 3)
            }
        }
    }

    func cancel() {
        clearRecordingShortcut()
        guard !inserting else { return }
        let wasActive = recording || processing
        meterTask?.cancel(); meterTask = nil
        recorder?.stop(); recorder = nil; recording = false
        setupPracticeRecording = false
        if let file = recordingURL { try? FileManager.default.removeItem(at: file); temporaryAudio.remove(file) }
        recordingURL = nil; recordingWorkflow = nil; target = nil; session.cancel(); task?.cancel()
        // Keep processing true until the inference task unwinds; overlapping GPU work is disallowed.
        status = processing ? "Cancelling…" : "Cancelled."
        if wasActive { feedback.show(.cancelled, title: "Cancelled", cue: "cancel", dismissAfter: 1) }
    }

    private func scheduleTranscriptObservation() {
        editTask?.cancel()
        guard transcriptBaseline != nil else { return }
        editTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.observeTranscriptEdits()
        }
    }
    private func observeTranscriptEdits() {
        guard let baseline = transcriptBaseline else { return }
        history.update(id: baseline.id, text: transcript)
        if transcript != baseline.text { transcriptWasEdited = true }
        guard transcriptWasEdited else { return }
        vocabulary.observe(id: baseline.id, original: baseline.text, edited: transcript)
    }
    private func watchCorrections(target: TargetApplication, text: String, id: UUID) {
        externalEditTask?.cancel()
        externalEditTask = Task { [weak self] in
            var previous = text
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.vocabulary.learningEnabled else { return }
                if let edited = target.editedInsertion(text), edited != previous {
                    self.vocabulary.observe(id: id, original: text, edited: edited)
                    previous = edited
                }
            }
        }
    }

    func pasteLastTranscript() {
        guard !recording && !processing && !inserting && !transcript.isEmpty else { return }
        feedback.meter(power: -60, seconds: 0)
        guard let destination = TargetApplication.capture() else {
            status = "Click a field in another app, then press \(pasteShortcut.display)."
            feedback.show(.warning, title: "Choose an input field", detail: "Then press \(pasteShortcut.display)", dismissAfter: 3)
            return
        }
        let text = transcript
        processing = true; inserting = true
        externalEditTask?.cancel()
        task = Task {
            defer { processing = false; inserting = false }
            feedback.show(.inserting, title: "Pasting transcript", detail: destination.name,
                destination: .init(name: destination.name, bundleID: destination.bundleID, confirmed: false))
            let result = await destination.insert(text, onPasteSent: { [weak self] in
                self?.feedback.pasteSent(to: .init(name: destination.name, bundleID: destination.bundleID, confirmed: false))
            })
            status = result.message(in: destination.name, pasteShortcut: pasteShortcut.display)
            if result.wasSent {
                if result.isConfirmed { feedback.confirmPaste(to: .init(name: destination.name, bundleID: destination.bundleID, confirmed: true)) }
            } else { feedback.show(.warning,
                title: result.isConfirmed ? "Inserted" : result.wasSent ? "Paste sent" : "Transcript ready",
                detail: result.wasSent ? destination.name : "See Quibble",
                destination: result.wasSent ? .init(name: destination.name, bundleID: destination.bundleID, confirmed: result.isConfirmed) : nil,
                cue: "error", dismissAfter: 3) }
        }
    }

    func testInsertion() {
        guard !recording && !processing else { return }
        feedback.meter(power: -60, seconds: 0)
        processing = true
        task = Task {
            defer { processing = false }
            status = "Switch to an empty test field within five seconds…"
            for remaining in (1...5).reversed() {
                feedback.show(.processing, title: "Insertion test", detail: "Choose a field · \(remaining)s")
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
            }
            let diagnostic = TargetApplication.captureDiagnostic()
            guard let destination = TargetApplication.capture() else {
                status = "No insertion target. " + diagnostic
                feedback.show(.warning, title: "No input field", detail: "See Diagnostics", dismissAfter: 3)
                return
            }
            inserting = true
            feedback.show(.inserting, title: "Inserting test", detail: destination.name,
                destination: .init(name: destination.name, bundleID: destination.bundleID, confirmed: false))
            let result = await destination.insert("Quibble insertion test.", onPasteSent: { [weak self] in
                self?.feedback.pasteSent(to: .init(name: destination.name, bundleID: destination.bundleID, confirmed: false))
            })
            inserting = false
            status = result.message(in: destination.name, pasteShortcut: pasteShortcut.display) + " " + diagnostic
            if result.wasSent {
                if result.isConfirmed { feedback.confirmPaste(to: .init(name: destination.name, bundleID: destination.bundleID, confirmed: true)) }
            } else { feedback.show(.warning,
                title: result.isConfirmed ? "Inserted" : result.wasSent ? "Paste sent" : "Test finished",
                detail: "Check the field and Diagnostics",
                destination: result.wasSent ? .init(name: destination.name, bundleID: destination.bundleID, confirmed: result.isConfirmed) : nil,
                dismissAfter: 3) }
        }
    }

    func previewFeedback() {
        guard !recording && !processing else { return }
        feedback.preview(shortcut: dictationShortcut.display)
    }

    func copy() {
        observeTranscriptEdits()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
        status = "Copied."
    }

    func exportMetrics() {
        guard let result = lastResult, !presentingPanel else { return }
        presentingPanel = true
        Task {
            defer { presentingPanel = false }
            let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "quibble-result.json"
            guard await panel.present() == .OK, let url = panel.url else { return }
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(result).write(to: url)
            } catch { status = error.localizedDescription }
        }
    }
}
