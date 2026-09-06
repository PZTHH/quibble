import SwiftUI
import QuibbleCore

struct HistoryView: View {
    @ObservedObject var history: TranscriptHistory
    @State private var query = ""
    @State private var selected: TranscriptRecord?
    @State private var copiedID: UUID?
    @FocusState private var searchFocused: Bool
    private var filtered: [TranscriptRecord] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return history.records.filter { term.isEmpty || $0.text.localizedStandardContains(term) || $0.original.localizedStandardContains(term) || $0.application.localizedStandardContains(term) }
    }
    private var days: [Date] { Set(filtered.map { Calendar.current.startOfDay(for: $0.date) }).sorted(by: >) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("History").font(.largeTitle.bold())
                Spacer()
                Text(history.records.count == 1 ? "1 dictation" : "\(history.records.count) dictations").font(.callout).foregroundStyle(.secondary)
            }
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Keep text history on this Mac", isOn: Binding(get: { history.isPersistent }, set: { history.setPersistent($0) }))
                    Text("Keeps up to 100 dictations for 7 days, including original and final text. No audio is saved. Turning this off removes the saved copy; this session remains available until you quit.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 12)
            } label: {
                HStack {
                    Label("History storage", systemImage: "internaldrive.fill").foregroundStyle(.secondary)
                    Spacer()
                    Text(history.isPersistent ? "On this Mac · 7 days" : "Session only").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(16).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
            if let error = history.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary) }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transcripts or apps", text: $query).textFieldStyle(.plain).focused($searchFocused)
                if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear history search") }
                ShortcutKeys(keys: ["⌘", "F"]).scaleEffect(0.8, anchor: .trailing).accessibilityHidden(true)
            }.padding(12).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            if history.canUndoRemoval {
                HStack { Text("Dictation removed.").font(.callout).foregroundStyle(.secondary); Spacer(); Button("Undo") { history.undoRemoval() } }
            }
            if filtered.isEmpty {
                ContentUnavailableView(query.isEmpty ? "A place for your words" : "No matching dictations", systemImage: query.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass",
                    description: Text(query.isEmpty ? "Your next dictation will appear here." : "Try another word or app."))
            } else {
                ForEach(days, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(dayLabel(day)).font(.callout.weight(.semibold)).foregroundStyle(.secondary)
                        ForEach(filtered.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { record in
                            HStack(alignment: .top, spacing: 12) {
                                ApplicationIcon(name: record.application, bundleID: record.applicationBundleID, size: 38)
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 8) {
                                        Text(record.application.isEmpty ? "Quibble" : record.application)
                                            .font(.callout.weight(.medium)).lineLimit(1)
                                        Text(record.date, style: .time).font(.caption).foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                        DeliveryBadge(delivery: record.delivery)
                                    }
                                    Button { selected = record } label: {
                                        Text(record.text).font(.system(size: 14)).lineSpacing(3).lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityLabel("Review dictation: " + String(record.text.prefix(100)))
                                    HStack(spacing: 12) {
                                        Label(record.mode, systemImage: "slider.horizontal.3")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        if record.warning != nil {
                                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                                                .help("Open this dictation to see its processing warning")
                                                .accessibilityLabel("Processing warning")
                                        }
                                        if let segments = record.segments, !segments.isEmpty {
                                            Label("\(segments.count)", systemImage: segments.contains { $0.speaker != nil } ? "person.2" : "text.alignleft")
                                                .font(.caption).foregroundStyle(.secondary).help("Review timestamped segments")
                                        }
                                        Spacer(minLength: 0)
                                        Button { selected = record } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Review dictation")
                                            .accessibilityLabel("Review dictation from " + record.date.formatted())
                                        Button { copy(record) } label: { Image(systemName: copiedID == record.id ? "checkmark" : "doc.on.doc") }
                                            .buttonStyle(.borderless).foregroundStyle(copiedID == record.id ? .green : .secondary)
                                            .help(copiedID == record.id ? "Copied" : "Copy text")
                                            .accessibilityLabel(copiedID == record.id ? "Copied dictation" : "Copy dictation from " + record.date.formatted())
                                        Button { history.remove(id: record.id) } label: { Image(systemName: "trash") }
                                            .buttonStyle(.borderless).foregroundStyle(.secondary).help("Remove dictation")
                                            .accessibilityLabel("Remove dictation from " + record.date.formatted())
                                    }
                                }
                            }.padding(16).background(.background.opacity(0.45), in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
                        }
                    }
                }
            }
        }.onAppear { history.prune() }
            .background(Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).hidden())
            .sheet(item: $selected) { record in
                TranscriptReview(record: record) { copy(record) }
            }
    }
    private func copy(_ record: TranscriptRecord) {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(record.text, forType: .string)
        copiedID = record.id
    }
    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct TranscriptReview: View {
    let record: TranscriptRecord
    let copy: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var presentation = "Text"
    private var segments: [TranscriptSegment] { record.segments ?? [] }
    private var speakerCount: Int { Set(segments.compactMap(\.speaker)).count }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                ApplicationIcon(name: record.application, bundleID: record.applicationBundleID, size: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your dictation").font(.title2.bold())
                    Text(record.application + " · " + record.date.formatted(date: .abbreviated, time: .shortened)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            if !segments.isEmpty {
                HStack(spacing: 12) {
                    Picker("Transcript view", selection: $presentation) {
                        Text("Text").tag("Text")
                        Text("Timeline").tag("Timeline")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                    Spacer()
                    if speakerCount > 0 { Label("\(speakerCount) speaker labels", systemImage: "person.2").font(.caption).foregroundStyle(.secondary) }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if presentation == "Timeline" {
                        segmentTimeline
                    } else {
                    Text(record.text).font(.system(size: 16)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    Divider()
                    DisclosureGroup("Original transcription") {
                        Text(record.original).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                    }.font(.callout).foregroundStyle(.secondary)
                    }
                    if let warning = record.warning { Label(warning, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.secondary) }
                }.padding(4)
            }.frame(minHeight: 180, maxHeight: 400)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.mode).font(.callout)
                    Text(record.engine).font(.caption).foregroundStyle(.secondary)
                    DeliveryBadge(delivery: record.delivery)
                }
                Spacer()
                Button(copied ? "Copied" : presentation == "Timeline" ? "Copy timeline" : "Copy text", systemImage: copied ? "checkmark" : "doc.on.doc") {
                    if presentation == "Timeline" {
                        let text = segments.map { segment in
                            "[" + timestamp(segment.start) + "] " + (segment.speaker.map { $0 + ": " } ?? "") + segment.text
                        }.joined(separator: "\n\n")
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
                    } else { copy() }
                    copied = true
                }
                    .buttonStyle(.borderedProminent).tint(AppPalette.speech)
            }
        }.padding(28).frame(width: 620)
            .onChange(of: presentation) { _, _ in copied = false }
    }

    private var segmentTimeline: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(segments.contains { $0.source == .audioChunk } ? "Section times · original speech" : "Model timestamps · original speech")
            }.font(.caption).foregroundStyle(.secondary)
                .help("Times refer to the original audio. Writing steps and manual edits may change the final text. Section times mark processing boundaries rather than individual words.")
            ForEach(segments) { segment in
                HStack(alignment: .top, spacing: 14) {
                    Text(timestamp(segment.start)).font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary).frame(width: segment.start >= 3600 ? 58 : 45, alignment: .leading).padding(.top, 2)
                        .help(timestamp(segment.start) + "–" + timestamp(segment.end))
                    VStack(alignment: .leading, spacing: 7) {
                        if let speaker = segment.speaker {
                            Label(speaker, systemImage: "person.fill").font(.caption.weight(.medium))
                                .foregroundStyle(AppPalette.speech).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(AppPalette.speech.opacity(0.09), in: Capsule())
                        }
                        Text(segment.text).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let value = seconds.isFinite ? Int(min(86_400_000, max(0, seconds))) : 0
        return value >= 3600 ? String(format: "%d:%02d:%02d", value / 3600, value / 60 % 60, value % 60)
            : String(format: "%d:%02d", value / 60, value % 60)
    }
}
