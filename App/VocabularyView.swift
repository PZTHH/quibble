import SwiftUI
import UniformTypeIdentifiers
import QuibbleCore

struct VocabularyView: View {
    @ObservedObject var controller: DictationController
    @ObservedObject private var store: VocabularyStore
    init(controller: DictationController) { self.controller = controller; store = controller.vocabulary }
    private enum Tab: String, CaseIterable { case words = "Words", corrections = "Corrections", suggestions = "Suggestions" }
    @State private var tab: Tab = .words
    @State private var query = ""
    @State private var newWord = ""
    @State private var editing: VocabularyEntry?
    @State private var preferred = ""
    @State private var aliases = ""
    @State private var correctionsEnabled = false
    @State private var showingEditor = false
    @State private var sample = "Open Superwhisker for the meeting."
    @State private var preview: VocabularyResult?
    @State private var previewSeconds = 0.0
    @State private var testingAudio = false
    @State private var audioBefore = ""
    @State private var audioAfter = ""
    @State private var audioModel = ""
    @State private var audioChanges: [VocabularyChange] = []
    @State private var audioWarning: String?
    @State private var importing = false
    @State private var confirmingImport = false
    @State private var additions: [VocabularyEntry] = []
    @State private var exporting = false
    @State private var exportDocument = VocabularyDocument(data: Data())

    private var visible: [VocabularyEntry] {
        store.entries.filter { (tab != .corrections || !$0.aliases.isEmpty) &&
            (query.isEmpty || ($0.preferred + " " + $0.aliases.joined(separator: " ")).localizedCaseInsensitiveContains(query)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your vocabulary").font(.largeTitle.bold())
                    Text("Names and spellings that follow you across models.").foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Import vocabulary…") { importing = true }
                    Button("Export vocabulary…") {
                        do { exportDocument = VocabularyDocument(data: try store.exportData()); exporting = true }
                        catch { store.report(error) }
                    }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }.menuStyle(.borderlessButton).fixedSize()
            }
            HStack(spacing: 14) {
                Image(systemName: "character.book.closed.fill").font(.title2).foregroundStyle(AppPalette.vocabulary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.enabled ? "Your personal vocabulary" : "Vocabulary is paused").font(.headline)
                    Text(store.enabled ? "Saved words and correction rules" : "Your entries are saved. Turn on to use them in dictation.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Use personal vocabulary", isOn: $store.enabled).labelsHidden().toggleStyle(.switch)
                    .help("Use personal vocabulary")
            }.padding(20).background(AppPalette.vocabulary.opacity(0.07), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
            HStack {
                Picker("Vocabulary section", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { item in
                        Text(item == .suggestions && !store.suggestions.isEmpty ? "Suggestions (\(store.suggestions.count))" : item.rawValue).tag(item)
                    }
                }.pickerStyle(.segmented).labelsHidden()
                if store.canUndo { Button("Undo") { store.undo() }.buttonStyle(.borderless) }
            }
            if let error = store.error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            if tab == .suggestions { suggestions }
            else {
                HStack(spacing: 10) {
                    Image(systemName: "plus.circle").foregroundStyle(.secondary)
                    TextField(tab == .words ? "Add a name or technical term" : "Preferred spelling", text: $newWord)
                        .textFieldStyle(.plain).onSubmit(add)
                    Button(tab == .words ? "Add word" : "Add correction", action: add)
                        .buttonStyle(.borderedProminent).tint(AppPalette.vocabulary).disabled(newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(14).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search words and corrections", text: $query).textFieldStyle(.plain)
                    Spacer()
                    Text("\(visible.count) \(visible.count == 1 ? "entry" : "entries")").font(.caption).foregroundStyle(.secondary)
                }
                if visible.isEmpty {
                    ContentUnavailableView(query.isEmpty ? (tab == .words ? "Make it sound like you" : "Fix a recurring misspelling") : "No matching entries",
                        systemImage: tab == .words ? "character.book.closed" : "arrow.right.arrow.left",
                        description: Text(tab == .words ? "Add names, companies, and technical terms above." : "Use a correction such as “super whisper → Superwhisper” for a mistake you want replaced consistently."))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(visible, id: \.id) { (entry: VocabularyEntry) in
                            HStack(spacing: 14) {
                                Toggle("Enable \(entry.preferred)", isOn: Binding(get: { entry.enabled }, set: { store.setEnabled(entry, $0) }))
                                    .labelsHidden().toggleStyle(.checkbox)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(entry.preferred).font(.headline).foregroundStyle(entry.enabled ? .primary : .secondary)
                                    if !entry.aliases.isEmpty && (entry.correctionsEnabled || tab == .corrections) {
                                        HStack(spacing: 6) {
                                            Text(entry.aliases.joined(separator: ", ")).lineLimit(2)
                                            Image(systemName: "arrow.right")
                                            Text(entry.correctionsEnabled ? "Exact rule" : "Rule paused")
                                        }.font(.caption).foregroundStyle(Color.secondary)
                                    } else { Text("Saved spelling").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Button("Edit") { edit(entry) }.buttonStyle(.borderless)
                                Button("Remove \(entry.preferred)", systemImage: "trash") { store.remove(entry.id) }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless).foregroundStyle(.secondary)
                            }.padding(17)
                            Divider().padding(.leading, 17)
                        }
                    }.background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
                }
                DisclosureGroup("How saved words work") {
                    Text("Quibble checks saved spellings against your audio with every speech model. Uncertain names may still be missed. The Vocabulary audio helper and S1-mini are managed in Models library.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }.font(.callout).foregroundStyle(.secondary)
            }
            tryIt
        }
        .sheet(isPresented: $showingEditor) { editor }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get(), access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 2_000_000 else { throw VocabularyArchive.ValidationError("Choose a vocabulary file smaller than 2 MB.") }
                additions = try store.previewImport(Data(contentsOf: url)); confirmingImport = true
            } catch { store.report(error) }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json, defaultFilename: "Quibble Vocabulary") { result in
            if case .failure(let error) = result { store.report(error) }
        }
        .sheet(isPresented: $confirmingImport) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Import \(additions.count) entries?").font(.title2.bold())
                Text("Existing names stay unchanged. Review any enabled correction rules before importing.").foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(additions) { entry in
                            Text(entry.preferred).bold()
                            if !entry.aliases.isEmpty { Text(entry.aliases.joined(separator: ", ") + (entry.correctionsEnabled ? " → correction enabled" : " → correction disabled")).font(.caption).foregroundStyle(.secondary) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 250)
                if let error = store.error { Text(error).foregroundStyle(.red) }
                HStack {
                    Button("Cancel") { confirmingImport = false }
                    Spacer()
                    Button("Import") { if store.importEntries(additions) { confirmingImport = false } }
                        .buttonStyle(.borderedProminent).disabled(additions.isEmpty)
                }
            }.padding(28).frame(width: 460)
        }
        .onReceive(controller.$lastResult) { result in
            guard testingAudio, let result else { return }
            audioBefore = result.raw; audioAfter = result.text; audioChanges = result.vocabularyChanges ?? []; audioWarning = result.warning; preview = nil; testingAudio = false
        }
        .onChange(of: store.entries) { _, _ in preview = nil }
        .onChange(of: store.enabled) { _, _ in preview = nil }
        .onChange(of: sample) { _, _ in preview = nil }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Suggest additions from my corrections", isOn: $store.learningEnabled)
            Text("Quibble looks for the same short correction in two separate dictations. It can observe edits here and in supported input fields for 30 seconds after insertion.")
                .font(.callout).foregroundStyle(.secondary)
            if store.suggestions.isEmpty {
                ContentUnavailableView("No suggestions yet", systemImage: "sparkles", description: Text("Keep dictating and correcting. Suggestions will appear here for you to review."))
            }
            ForEach(store.suggestions, id: \.self) { item in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(item.heard).foregroundStyle(.secondary)
                        Image(systemName: "arrow.right")
                        Text(item.preferred).bold()
                        Spacer()
                    }
                    Text("Corrected in at least two dictations").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Add word") { store.accept(item) }
                        Button("Always correct this phrase") { store.accept(item, asRule: true) }
                        Spacer()
                        Button("Dismiss") { store.dismiss(item) }.buttonStyle(.borderless)
                    }
                }.padding(18).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    private var tryIt: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Try your vocabulary", systemImage: "waveform.and.magnifyingglass").font(.headline)
                Spacer()
                Text("On your Mac").font(.caption).foregroundStyle(.secondary)
            }
            Text("Say a sentence with one of your saved words. See what Quibble heard and exactly what changed.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button(controller.recording && testingAudio ? "Finish test" : "Record test", systemImage: "mic") {
                    if controller.recording && testingAudio { controller.stopRecording() }
                    else { testingAudio = true; audioBefore = ""; audioAfter = ""; audioModel = controller.engine.displayName; controller.startRecording() }
                }.buttonStyle(.borderedProminent).tint(AppPalette.vocabulary)
                    .disabled(controller.processing || (controller.recording && !testingAudio))
                Spacer()
                if controller.processing && testingAudio { ProgressView().controlSize(.small) }
            }
            if !audioBefore.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("HEARD").font(.caption).foregroundStyle(.secondary)
                    Text(audioBefore).foregroundStyle(.secondary).textSelection(.enabled)
                    if !audioChanges.isEmpty {
                        ForEach(audioChanges) { change in
                            HStack(spacing: 8) {
                                Text(change.before).foregroundStyle(.secondary)
                                Image(systemName: "arrow.right").font(.caption)
                                Text(change.after).fontWeight(.semibold).foregroundStyle(AppPalette.vocabulary)
                                Spacer()
                                Text(change.explicit ? "Your rule" : "Saved spelling").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else { Text("No saved-word replacements.").font(.caption).foregroundStyle(.secondary) }
                    Text("FINAL · \(audioModel)").font(.caption).foregroundStyle(.secondary)
                    Text(audioAfter).textSelection(.enabled)
                    if let audioWarning { Label(audioWarning, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.secondary) }
                }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(AppPalette.vocabulary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            if testingAudio { Text(controller.status).font(.caption).foregroundStyle(.secondary) }
            DisclosureGroup("Test an exact correction rule") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Typed samples check only the explicit rules you enabled. Use Record test for speech recognition.").font(.caption).foregroundStyle(.secondary)
            TextField("Type a sample transcript", text: $sample, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                Button("Test exact rules") {
                    audioBefore = ""; audioAfter = ""
                    let start = ProcessInfo.processInfo.systemUptime
                    preview = (store.enabled ? store.processor : VocabularyProcessor(entries: [])).process(sample, isKnownWord: { _ in true })
                    previewSeconds = ProcessInfo.processInfo.systemUptime - start
                }.disabled(sample.isEmpty)
            if let preview {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) { Text("BEFORE").font(.caption).foregroundStyle(.secondary); Text(preview.original).textSelection(.enabled) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.right").foregroundStyle(.secondary).padding(.top, 22)
                    VStack(alignment: .leading, spacing: 8) { Text("AFTER").font(.caption).foregroundStyle(.secondary); highlighted(preview).textSelection(.enabled) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(16).background(AppPalette.vocabulary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                Text(preview.changes.isEmpty ? "No exact rule matched. Use Record test to test saved spellings against audio." : "\(preview.changes.count) correction\(preview.changes.count == 1 ? "" : "s") · \(String(format: "%.1f", previewSeconds * 1_000)) ms · No AI inference")
                    .font(.caption).foregroundStyle(.secondary)
            }
                }.padding(.top, 12)
            }.font(.callout)
        }.padding(20).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(editing == nil ? "Add a correction" : "Edit vocabulary").font(.title2.bold())
            TextField("Preferred spelling", text: $preferred).textFieldStyle(.roundedBorder)
            Toggle("Always correct these phrases", isOn: $correctionsEnabled)
            Text("Only enable this for misspellings you always want replaced. Put each phrase on its own line.").font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $aliases).font(.body).frame(height: 90).padding(8).border(.secondary.opacity(0.2))
            if let error = store.error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Button("Cancel") { showingEditor = false; store.clearError() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save") {
                    if store.save(VocabularyEntry(id: editing?.id ?? UUID(), preferred: preferred,
                        aliases: aliases.split(whereSeparator: \.isNewline).map(String.init), enabled: editing?.enabled ?? true,
                        correctionsEnabled: correctionsEnabled)) { showingEditor = false; newWord = "" }
                }.buttonStyle(.borderedProminent).disabled(preferred.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(28).frame(width: 460)
    }
    private func add() {
        guard !newWord.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.clearError()
        if tab == .words {
            if store.save(VocabularyEntry(preferred: newWord, correctionsEnabled: false)) { newWord = "" }
        } else { editing = nil; preferred = newWord; aliases = ""; correctionsEnabled = true; showingEditor = true }
    }
    private func edit(_ entry: VocabularyEntry) {
        store.clearError(); editing = entry; preferred = entry.preferred; aliases = entry.aliases.joined(separator: "\n")
        correctionsEnabled = entry.correctionsEnabled; showingEditor = true
    }
    private func highlighted(_ result: VocabularyResult) -> Text {
        let source = result.original as NSString
        var text = Text(""), cursor = 0
        for change in result.changes {
            text = text + Text(source.substring(with: NSRange(location: cursor, length: change.location - cursor)))
                + Text(change.after).bold().foregroundColor(AppPalette.vocabulary)
            cursor = change.location + change.length
        }
        return text + Text(source.substring(from: cursor))
    }
}

private struct VocabularyDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}
