import SwiftUI
import QuibbleCore
import QuibbleInference

struct ShortcutKeys: View {
    let keys: [String]
    var body: some View {
        HStack(spacing: 5) {
            ForEach(keys, id: \.self) { key in
                Text(key).font(.system(size: 13, weight: .medium, design: .rounded))
                    .padding(.horizontal, 9).frame(height: 28)
                    .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.08)))
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel(keys.joined(separator: " "))
    }
}

struct HomeView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var history: TranscriptHistory
    @ObservedObject private var library: ModelLibrary
    let navigate: (QuibblePage) -> Void
    @State private var copied = false
    init(controller: DictationController, navigate: @escaping (QuibblePage) -> Void) {
        self.controller = controller; history = controller.history; library = controller.modelLibrary; self.navigate = navigate
    }
    private var busy: Bool { controller.recording || controller.processing }
    private var speechReady: Bool { controller.engine.isOnline ? controller.cloudSpeech.hasKey : library.installed.contains(controller.engine.rawValue) }
    private var ready: Bool { controller.microphoneAllowed && speechReady }
    private var terminalFeedback: DictationFeedback.Phase? {
        guard !busy, !controller.feedback.isPreview else { return nil }
        switch controller.feedback.phase {
        case .noSpeech, .warning, .cancelled: return controller.feedback.phase
        default: return nil
        }
    }
    private var headlineSymbol: String {
        if controller.recording { return "mic.fill" }
        switch terminalFeedback {
        case .noSpeech: return "mic.slash"
        case .warning: return "exclamationmark.circle"
        case .cancelled: return "xmark"
        default: return "waveform"
        }
    }
    private var headline: String {
        if controller.recording { return "Listening to you" }
        if controller.processing { return "Putting your words together" }
        if terminalFeedback != nil { return controller.feedback.title }
        return ready ? "Ready when you are" : "Let’s get you ready"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Home").font(.largeTitle.bold())
                Spacer()
                Label(controller.engine.isOnline ? "OpenAI · Online" : "Local", systemImage: controller.engine.isOnline ? "cloud" : "lock.shield.fill").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: headlineSymbol)
                        .font(.system(size: 25, weight: .medium))
                        .foregroundStyle(controller.recording ? .red : terminalFeedback != nil ? .secondary : AppPalette.speech)
                        .frame(width: 52, height: 52).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(headline).font(.system(size: 23, weight: .semibold, design: .rounded))
                        if busy || terminalFeedback != nil {
                            Text(terminalFeedback == .noSpeech ? "Nothing was inserted." : controller.status)
                                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        } else {
                            Button { navigate(.models) } label: {
                                HStack(spacing: 7) {
                                    ModelIcon(modelID: controller.engine.rawValue, size: 20).accessibilityHidden(true)
                                    Text(controller.engine.displayName)
                                    Image(systemName: "chevron.right").font(.caption2)
                                }.font(.callout).foregroundStyle(.secondary)
                            }.buttonStyle(.plain).help("Change speech model")
                                .accessibilityLabel("Speech model: " + controller.engine.displayName + ". Open model library")
                        }
                    }
                    Spacer(minLength: 0)
                    if controller.processing { ProgressView().controlSize(.small) }
                }
                if ready {
                    shortcutSummary
                } else {
                    HStack {
                        Label(!controller.microphoneAllowed ? "Microphone access needed" : controller.engine.isOnline ? "Add your OpenAI API key to begin" : "Download a speech model to begin", systemImage: "exclamationmark.circle")
                            .font(.callout)
                        Spacer()
                        Button(!controller.microphoneAllowed ? "Set up permissions" : "Open models") { navigate(!controller.microphoneAllowed ? .permissions : .models) }
                    }
                }
                HStack(spacing: 12) {
                    Button {
                        if controller.recording { controller.stopRecording() } else { controller.startRecording() }
                    } label: { Label(controller.recording ? "Finish recording" : "Record here", systemImage: controller.recording ? "stop.fill" : "mic.fill") }
                        .buttonStyle(.borderedProminent).tint(controller.recording ? .red : AppPalette.speech).controlSize(.large)
                        .disabled(controller.processing || !ready)
                    Button("Import audio…", systemImage: "square.and.arrow.down") { controller.importAudio() }
                        .buttonStyle(.bordered).controlSize(.large).disabled(busy || !speechReady)
                    Spacer(minLength: 8)
                    if busy { Button("Cancel") { controller.cancel() }.disabled(controller.inserting) }
                    else {
                        Menu {
                            ForEach(controller.workflows.workflows) { workflow in
                                Button { controller.workflows.select(workflow.id) } label: {
                                    if controller.workflow.id == workflow.id { Label(workflow.name, systemImage: "checkmark") } else { Text(workflow.name) }
                                }
                            }
                            Divider()
                            Button("Edit workflows") { navigate(.modes) }
                        } label: { Label(controller.workflow.name, systemImage: controller.mode == .basic ? "wand.and.stars" : "text.quote") }
                            .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Writing mode: " + controller.workflow.name)
                    }
                }
            }.padding(22)
                .background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous).strokeBorder(.primary.opacity(0.06)))

            if !controller.transcript.isEmpty || (controller.lastResult != nil && terminalFeedback != .noSpeech) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(terminalFeedback == .noSpeech ? "Previous dictation" : "Latest dictation").font(.headline)
                        Spacer()
                        Button(copied ? "Copied" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            controller.copy(); copied = true
                        }.disabled(busy || controller.transcript.isEmpty)
                    }
                    TextEditor(text: $controller.transcript).font(.system(size: 15)).lineSpacing(5)
                        .scrollContentBackground(.hidden).frame(minHeight: 120, maxHeight: 190).disabled(busy)
                        .accessibilityLabel("Edit latest dictation")
                    HStack {
                        Label("Editable", systemImage: "pencil").font(.caption).foregroundStyle(.secondary).help("Corrections you make here can help Quibble suggest vocabulary updates.")
                        Spacer()
                        if !controller.rawTranscript.isEmpty && controller.rawTranscript != controller.transcript {
                            Button("View original") { navigate(.history) }.font(.caption).buttonStyle(.link)
                        }
                    }
                    if let warning = controller.lastResult?.warning {
                        Label(warning, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary)
                    }
                    if !busy && terminalFeedback == nil {
                        Text(controller.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }.padding(22).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
                    .onChange(of: controller.transcript) { _, _ in copied = false }
            }
            HStack(spacing: 20) {
                Image(systemName: "gauge.with.needle").font(.title2).foregroundStyle(AppPalette.speech)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Speaking pace").font(.callout.weight(.medium))
                    Text(history.isPersistent ? "Recent dictations" : "This session").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let pace = history.pace.wordsPerMinute {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(pace, format: .number.precision(.fractionLength(0))).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit()
                        Text("wpm").font(.callout).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .ignore).accessibilityLabel("\(Int(pace.rounded())) words per minute")
                } else {
                    Text("— wpm").font(.title3).foregroundStyle(.tertiary)
                        .accessibilityLabel("Speaking pace available after ten seconds of measured dictation")
                }
            }.padding(20)
                .background(AppPalette.speech.opacity(0.06), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
                .help("Estimated from original transcription words and recorded duration, including pauses. Appears after 10 seconds of dictation. Imported audio and older unmeasured history are excluded. Word counts vary by language.")
            HStack {
                Text("Recent dictations").font(.headline)
                Spacer()
                Button("View history", systemImage: "arrow.right") { navigate(.history) }.buttonStyle(.link)
            }
            if history.records.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "text.bubble").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text("Your words will appear here").font(.callout.weight(.medium))
                    
                }.frame(maxWidth: .infinity).padding(24)
                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(history.records.prefix(3))) { record in
                        Button { navigate(.history) } label: {
                            HStack(spacing: 14) {
                                ApplicationIcon(name: record.application, bundleID: record.applicationBundleID)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(record.text).lineLimit(2).foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        Text(record.application).font(.caption).foregroundStyle(.secondary)
                                        DeliveryBadge(delivery: record.delivery)
                                    }
                                }
                                Spacer()
                                Text(record.date, format: Calendar.current.isDateInToday(record.date)
                                     ? .dateTime.hour().minute() : .dateTime.month(.abbreviated).day())
                                    .font(.caption).foregroundStyle(.secondary)
                                    .help(record.date.formatted(date: .abbreviated, time: .shortened))
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(14).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if record.id != history.records.prefix(3).last?.id { Divider().padding(.leading, 64) }
                    }
                }.background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
            }
            Label(history.isPersistent ? "Local history · 7 days · No audio saved" : "Session history · No audio saved", systemImage: history.isPersistent ? "internaldrive" : "clock")
                .font(.caption).foregroundStyle(.secondary)
            if let error = history.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary) }
        }.onAppear { library.refresh(root: controller.modelRoot) }
    }

    private var shortcutSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    shortcutCard("Hold", keys: controller.dictationShortcut.keys, hint: "Release to finish")
                    shortcutCard("Toggle", keys: controller.toggleDictationShortcut.keys, hint: "Press again to finish")
                }
                VStack(spacing: 8) {
                    shortcutCard("Hold", keys: controller.dictationShortcut.keys, hint: "Release to finish")
                    shortcutCard("Toggle", keys: controller.toggleDictationShortcut.keys, hint: "Press again to finish")
                }
            }.opacity(controller.shortcutEnabled ? 1 : 0.55)
            if !controller.shortcutEnabled {
                HStack {
                    Label("Global shortcuts are off", systemImage: "keyboard").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Set up") { navigate(controller.accessibilityAllowed ? .general : .permissions) }.buttonStyle(.link)
                }
            } else if controller.workflow.destination != .insert {
                Label("This mode keeps text in Quibble", systemImage: "doc.text")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func shortcutCard(_ title: String, keys: [String], hint: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.callout.weight(.medium)).lineLimit(1)
            Spacer(minLength: 8)
            ShortcutKeys(keys: keys).fixedSize()
        }.padding(10).frame(maxWidth: .infinity)
            .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: AppSurface.rowRadius))
            .help(title + " to dictate. " + hint + ".")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title + " to dictate: " + keys.joined(separator: " ") + ". " + hint)
    }
}
