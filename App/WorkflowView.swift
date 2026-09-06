import SwiftUI
import QuibbleCore
import QuibbleInference

struct WorkflowView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var library: WorkflowLibrary
    @State private var editing: DictationWorkflow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(controller: DictationController) { self.controller = controller; library = controller.workflows }
    private var busy: Bool { controller.recording || controller.processing }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Modes & workflows").font(.largeTitle.bold())
                }
                Spacer()
                Button("New mode", systemImage: "plus") {
                    editing = DictationWorkflow(name: "Untitled mode", speechModel: controller.engine.rawValue,
                        steps: [.init(kind: .vocabulary), .init(kind: .cleanup)])
                }.buttonStyle(.borderedProminent).tint(AppPalette.speech)
            }
            ForEach(library.workflows) { workflow in
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "point.3.connected.trianglepath.dotted").foregroundStyle(AppPalette.speech).font(.title2)
                        Text(workflow.name).font(.headline)
                        Spacer()
                        if workflow.id == library.selectedID { Label("Active", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(AppPalette.speech) }
                        else { Button("Use mode") { library.select(workflow.id) }.accessibilityLabel("Use " + workflow.name) }
                        Button("Edit") { editing = workflow }.accessibilityLabel("Edit " + workflow.name)
                        Menu {
                            Button("Duplicate") { var copy = workflow; copy.id = UUID().uuidString; copy.name = String((workflow.name + " copy").prefix(60)); editing = copy }
                            Button("Remove mode") { library.remove(workflow.id) }.disabled(library.workflows.count == 1)
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More actions for " + workflow.name)
                    }
                    HStack(spacing: 8) {
                        ModelIcon(modelID: workflow.speechModel, size: 24)
                        Text(SpeechEngine(rawValue: workflow.speechModel)?.displayName ?? workflow.speechModel)
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            pipelinePill("Speech", symbol: "waveform", color: AppPalette.speech)
                            ForEach(workflow.enabledSteps) { step in
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                                pipelinePill(step.kind.title, symbol: step.kind == .prompt ? "text.bubble" : step.kind == .cleanup ? "wand.and.stars" : "character.book.closed",
                                    color: step.kind == .vocabulary ? AppPalette.vocabulary : AppPalette.instructions)
                            }
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                            pipelinePill(workflow.destination.title, symbol: workflow.destination == .insert ? "cursorarrow" : "doc.text.magnifyingglass")
                        }
                    }.scrollIndicators(.hidden)
                    if workflow.steps.contains(where: { !$0.enabled }) {
                        let skipped = workflow.steps.filter { !$0.enabled }.count
                        Text("\(skipped) \(skipped == 1 ? "step" : "steps") skipped").font(.caption).foregroundStyle(.secondary)
                    }
                }.quibbleCard()
                    .overlay(RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous).strokeBorder(workflow.id == library.selectedID ? AppPalette.instructions.opacity(0.4) : .clear))
            }
            if library.canUndoRemoval { HStack { Text("Mode removed.").foregroundStyle(.secondary); Button("Undo") { library.undoRemoval() } } }
            if let error = library.error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange) }
            DisclosureGroup("About workflow steps") {
                Text("Steps run from left to right. Disabled steps use no model. Custom prompts run locally; each added pass can increase latency. Application context remains off.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.callout)
        }.disabled(busy)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: library.selectedID)
            .sheet(item: $editing) { workflow in
                WorkflowEditor(workflow: workflow, models: controller.modelLibrary.models, canUseOnline: controller.cloudSpeech.hasKey) { updated in library.save(updated) }.disabled(busy)
            }
    }
    private func pipelinePill(_ title: String, symbol: String, color: Color = .secondary) -> some View {
        return Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(color.opacity(0.10), in: Capsule())
    }
}

private struct WorkflowEditor: View {
    @State var workflow: DictationWorkflow
    let models: [LocalModelSpec]
    let canUseOnline: Bool
    let save: (DictationWorkflow) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var saveFailed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Build your mode").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save mode") { if save(workflow) { dismiss() } else { saveFailed = true } }
                    .buttonStyle(.borderedProminent).tint(AppPalette.speech).keyboardShortcut(.defaultAction)
                    .disabled(workflow.validationError != nil)
            }
            TextField("Mode name", text: $workflow.name).textFieldStyle(.roundedBorder).font(.title3).accessibilityLabel("Mode name")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    stageHeading("1", "Speech recognition", "waveform")
                    Picker("Speech model", selection: $workflow.speechModel) {
                        ForEach(models.filter { $0.category == "Speech recognition" }) { model in Text(model.title + " · " + model.variant).tag(model.name) }
                        ForEach(SpeechEngine.allCases.filter(\.isOnline), id: \.rawValue) { engine in
                            Text(engine.displayName).tag(engine.rawValue).disabled(!canUseOnline)
                        }
                    }
                    if SpeechEngine(rawValue: workflow.speechModel)?.isOnline == true {
                        Text(workflow.speechModel == OpenAITranscriptionClient.diarizationModelID
                            ? "Audio is sent to OpenAI. Speaker labels and timestamps appear in History. Vocabulary prompts are unavailable."
                            : "Audio and enabled vocabulary hints are sent to OpenAI. Set up your API key in Models → Online transcription.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Language and decoding controls live in Developer for this mode.").font(.caption).foregroundStyle(.secondary)
                    ForEach($workflow.steps) { $step in
                        let index = workflow.steps.firstIndex { $0.id == step.id } ?? 0
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                stageHeading(String(index + 2), step.kind.title, step.kind == .prompt ? "text.bubble" : "slider.horizontal.3")
                                Spacer()
                                Toggle("Enabled", isOn: $step.enabled).toggleStyle(.switch).labelsHidden()
                                    .accessibilityLabel("Enable " + step.kind.title + " step " + String(index + 2))
                                Button { workflow.steps.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).accessibilityLabel("Move " + step.kind.title + " step " + String(index + 2) + " up")
                                Button { workflow.steps.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }.disabled(index == workflow.steps.count - 1).accessibilityLabel("Move " + step.kind.title + " step " + String(index + 2) + " down")
                                Button { workflow.steps.remove(at: index) } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Remove " + step.kind.title + " step " + String(index + 2))
                            }
                            if step.kind == .prompt {
                                Picker("Instruction model", selection: $step.model) {
                                    ForEach(models.filter { $0.category == "Text refinement" && $0.name != "s1-mini" }) { model in Text(model.title).tag(model.name) }
                                }
                                TextEditor(text: $step.prompt).font(.system(size: 13)).frame(height: 90)
                                    .padding(7).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                                    .accessibilityLabel("Custom instructions for step " + String(index + 2))
                                Text("For example: Turn the dictated items into a Markdown checklist. Preserve the wording.").font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(step.kind == .vocabulary ? (workflow.speechModel == OpenAITranscriptionClient.diarizationModelID ? "Apply enabled explicit spelling corrections locally. This speaker-label model does not accept saved-word prompts." : workflow.speechModel == OpenAITranscriptionClient.modelID ? "Send saved-word hints to OpenAI's recognizer and apply enabled explicit corrections. Hints are not guaranteed matches. No local vocabulary model is loaded." : "Check saved words against the audio. Only scoped spelling corrections are accepted. Uses your enabled Vocabulary entries.") : "Normalize spelling, punctuation, and prose with S1-mini by Superwhisper. This step has a fixed cleanup prompt.")
                                    .font(.callout).foregroundStyle(.secondary)
                            }
                            if !step.enabled { Text("Skipped · no model loading or processing").font(.caption).foregroundStyle(.secondary) }
                        }.padding(16).background(.background.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Menu("Add a step", systemImage: "plus.circle") {
                        ForEach(WorkflowStepKind.allCases, id: \.self) { kind in
                            Button(kind.title) { workflow.steps.append(.init(kind: kind, prompt: kind == .prompt ? "Format the dictation as concise bullet points. Preserve all facts." : "")) }
                        }
                    }.disabled(workflow.steps.count >= 6)
                    Divider().padding(.vertical, 6)
                    stageHeading(String(workflow.steps.count + 2), "Output", "arrow.up.doc")
                    Picker("Destination", selection: $workflow.destination) { ForEach(WorkflowDestination.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Text("Insertion applies to the global shortcut. Record here and imported audio always stay in Quibble. Review mode never pastes automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(2)
            }
            if let error = workflow.validationError { Text(error).font(.caption).foregroundStyle(.orange) }
            if saveFailed { Text("The mode could not be saved. Check the Modes page for details.").font(.caption).foregroundStyle(.orange) }
        }.padding(24).frame(width: 660, height: 600)
            .onChange(of: workflow.speechModel) { _, model in
                if let engine = SpeechEngine(rawValue: model), !engine.languageCodes.contains(workflow.asr.language) { workflow.asr.language = "en" }
            }
    }
    private func stageHeading(_ number: String, _ title: String, _ symbol: String) -> some View {
        HStack { Text(number).font(.caption.monospacedDigit()).foregroundStyle(AppPalette.speech).frame(width: 24, height: 24).background(AppPalette.speech.opacity(0.1), in: Circle()); Label(title, systemImage: symbol).font(.headline) }
    }
}
