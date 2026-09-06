import SwiftUI
import QuibbleCore
import QuibbleInference

@MainActor
struct CloudSpeechView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var connection: CloudSpeechConnection
    @Environment(\.dismiss) private var dismiss
    @State private var keyInput = ""
    @State private var confirmingRemoval = false
    @State private var selectedModel: SpeechEngine

    init(controller: DictationController, preferredModel: SpeechEngine? = nil) {
        self.controller = controller
        connection = controller.cloudSpeech
        _selectedModel = State(initialValue: preferredModel ?? (controller.engine.isOnline ? controller.engine : .openAI))
    }

    private var busy: Bool { controller.recording || controller.processing }
    private var referencedModes: [String] {
        controller.workflows.workflows.filter { SpeechEngine(rawValue: $0.speechModel)?.isOnline == true }.map(\.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image("ModelBrand-openai").resizable().scaledToFit().frame(width: 36, height: 36)
                    .padding(10).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 17))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenAI speech").font(.title2.bold())
                    Text("Cloud transcription").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }

            Picker("Online speech model", selection: $selectedModel) {
                Text("Dictation").tag(SpeechEngine.openAI)
                Text("Speaker labels").tag(SpeechEngine.openAIDiarize)
            }.pickerStyle(.segmented).labelsHidden().disabled(busy)
            VStack(alignment: .leading, spacing: 13) {
                Label("Audio is sent to OpenAI", systemImage: "cloud")
                    .font(.callout.weight(.medium)).foregroundStyle(AppPalette.speech)
                Text(selectedModel == .openAIDiarize
                    ? "Separate speakers with timestamped turns in History. Labels distinguish voices; they do not identify people. This model does not accept vocabulary hints."
                    : "Recordings and enabled vocabulary terms are sent to OpenAI. Writing steps still run on your Mac.")
                    .font(.callout).foregroundStyle(.secondary)
                Divider()
                HStack(alignment: .firstTextBaseline) {
                    Text("API billing is separate from ChatGPT.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Link("Pricing", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!).font(.caption)
                }
            }.padding(18).background(AppPalette.speech.opacity(0.055), in: RoundedRectangle(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label(connection.hasKey ? "Key saved in Keychain" : "Add your API key", systemImage: "key")
                        .font(.headline)
                    Spacer()
                    Link("Get an API key", destination: URL(string: "https://platform.openai.com/api-keys")!).font(.caption)
                }
                if connection.hasKey {
                    Text("Saved in this Mac’s Keychain. Verified only when you transcribe.").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    SecureField(connection.hasKey ? "Replacement API key" : "API key", text: $keyInput)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel(connection.hasKey ? "Replacement OpenAI API key" : "OpenAI API key")
                        .disabled(busy)
                    Button("Save key") {
                        guard !busy else { return }
                        if connection.saveKey(keyInput) { keyInput = "" }
                    }.disabled(busy || keyInput.isEmpty)
                }
                Text("Saving a key does not send audio or change your mode.").font(.caption).foregroundStyle(.secondary)
                if let error = connection.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                }
                if let error = controller.workflows.error {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.secondary)
                }
            }

            Divider()
            HStack {
                if connection.hasKey {
                    Button("Remove key…", role: .destructive) { confirmingRemoval = true }
                        .disabled(busy)
                }
                Spacer()
                if controller.engine == selectedModel {
                    Label("Selected for " + controller.workflow.name, systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Button("Use for this mode") {
                        guard !busy && connection.hasKey else { return }
                        if controller.selectSpeechEngine(selectedModel) { dismiss() }
                    }.buttonStyle(.borderedProminent).tint(AppPalette.speech)
                        .disabled(busy || !connection.hasKey)
                }
            }
        }.padding(26).frame(width: 520)
            .presentationCornerRadius(26)
            .onAppear { connection.refreshKeyState() }
            .onDisappear { keyInput = "" }
            .alert("Remove the OpenAI API key?", isPresented: $confirmingRemoval) {
                Button("Cancel", role: .cancel) {}
                Button("Remove key", role: .destructive) {
                    guard !busy else { return }
                    if connection.removeKey() { keyInput = "" }
                }.disabled(busy)
            } message: {
                if referencedModes.isEmpty {
                    Text("The key will be removed from Quibble’s Keychain storage. You can add it again later.")
                } else {
                    Text("Used by: " + referencedModes.joined(separator: ", ") + ". These modes keep their choices and will need a new key or a local speech model before transcription.")
                }
            }
    }
}
