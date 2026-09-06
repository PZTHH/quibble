import SwiftUI
import QuibbleInference

@MainActor
struct DiagnosticsView: View {
    @ObservedObject var controller: DictationController

    private var busy: Bool { controller.recording || controller.processing || controller.inserting }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Diagnostics").font(.largeTitle.bold())
                    Label("Measured on this Mac", systemImage: "desktopcomputer").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if controller.lastResult != nil {
                    Button { controller.exportMetrics() } label: {
                        Label("Export run…", systemImage: "square.and.arrow.up")
                    }
                }
            }

            activity
            if let result = controller.lastResult {
                measurements(result)
            } else {
                emptyState
            }

            insertionCheck
            if !controller.speechMeasurements.isEmpty { measuredModelSpeeds }
        }
    }

    private func measurements(_ result: InferenceResult) -> some View {
        let chartParts = parts(result).filter { $0.seconds > 0 }
        let chartTotal = max(result.processingSeconds, chartParts.reduce(0) { $0 + $1.seconds })
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                ModelIcon(modelID: result.engine, size: 24).accessibilityHidden(true)
                Text(SpeechEngine(rawValue: result.engine)?.displayName ?? result.engine)
                Text("·").foregroundStyle(.tertiary)
                Text(result.workflow?.name ?? result.mode).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if busy { Text("Previous run").font(.caption).foregroundStyle(.secondary) }
            }.font(.callout).lineLimit(1)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                metricCard("Processing", value: duration(result.processingSeconds),
                    detail: "Including model loading", symbol: "bolt.fill")
                metricCard("Audio", value: duration(result.audioSeconds),
                    detail: "Recording duration", symbol: "waveform")
                metricCard("Ready in", value: controller.releaseToResult.map(duration) ?? "—",
                    detail: "From release or import", symbol: "stopwatch")
                metricCard("MLX active", value: result.activeMemoryBytes.map(memory) ?? "—",
                    detail: "After this inference", symbol: "memorychip")
            }

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("Processing breakdown", systemImage: "chart.bar.xaxis").font(.headline)
                    Spacer()
                    Text(duration(result.processingSeconds)).font(.headline.monospacedDigit())
                }
                VStack(spacing: 12) {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(chartParts) { part in
                                RoundedRectangle(cornerRadius: 4).fill(part.color)
                                    .padding(.trailing, 2)
                                    .frame(width: geometry.size.width * (chartTotal > 0 ? part.seconds / chartTotal : 0))
                            }
                        }
                    }.frame(height: 12).accessibilityHidden(true)
                    ForEach(parts(result)) { part in
                        timingRow(part, total: result.processingSeconds)
                    }
                }
            }.diagnosticCard()

            if let warning = result.warning {
                Label {
                    Text(warning).font(.callout).textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            DisclosureGroup("Measurement details") {
                VStack(alignment: .leading, spacing: 14) {
                    detailRow("Model loading", duration(result.loadSeconds))
                    detailRow("Release / import to result", controller.releaseToResult.map(duration) ?? "Unavailable")
                    detailRow("Insertion attempt", controller.insertionSeconds.map(duration) ?? "Not measured")
                    Divider()
                    detailRow("MLX active after inference", result.activeMemoryBytes.map(memory) ?? "Unavailable")
                    detailRow("MLX process peak", memory(result.peakMemoryBytes))
                    Text("MLX allocations exclude other app memory. Active is a snapshot after inference; peak is the highest allocation recorded during this app process, across runs.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Processing includes loading, transcription, vocabulary, refinement and overhead. Workflow stage times below include their own loading and are not added to this total. Ready-in time ends before insertion; imported audio is not a microphone-to-insertion measurement.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Exports include transcript text, prompts, model settings and inference timings. Release / import and insertion measurements are shown here only.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 14)
            }.diagnosticCard()

            if let stages = result.stages, !stages.isEmpty {
                DisclosureGroup("Workflow stages · \(stages.count)") {
                    VStack(spacing: 14) {
                        ForEach(stages) { stage in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: stage.status == "Completed" ? "checkmark.circle.fill" : "circle.dotted")
                                    .foregroundStyle(stage.status == "Completed" ? AppPalette.vocabulary : Color.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stage.name).font(.callout.weight(.medium))
                                    Text(stage.status).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(duration(stage.seconds)).font(.callout.monospacedDigit())
                            }
                        }
                        Text("Stage times include loading. Full inputs and outputs are available in Developer.")
                            .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.top, 14)
                }.diagnosticCard()
            }
        }
    }

    private var measuredModelSpeeds: some View {
        DisclosureGroup("Local model speeds · This session") {
            VStack(spacing: 14) {
                ForEach(controller.speechMeasurements.keys.sorted(), id: \.self) { id in
                    if let measurement = controller.speechMeasurements[id] {
                        HStack(spacing: 10) {
                            ModelIcon(modelID: id, size: 26)
                            Text(SpeechEngine(rawValue: id)?.displayName ?? id).font(.callout)
                            Spacer()
                            Text(String(format: "%.1f×", measurement.realTimeMultiple))
                                .font(.callout.monospacedDigit().weight(.semibold)).foregroundStyle(AppPalette.speed)
                        }
                    }
                }
                Text("Latest audio duration ÷ transcription time on this Mac. Excludes loading and writing. Different recordings are not a controlled comparison.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 14)
        }.diagnosticCard()
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: controller.recording ? "mic.fill" : controller.processing ? "waveform.path" : "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                .frame(width: 74, height: 74).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
                .accessibilityHidden(true)
            VStack(spacing: 7) {
                Text(controller.recording ? "Recording this run" : controller.processing ? "Measuring this run…" : "Your next run, measured")
                    .font(.title3.weight(.semibold))
                Text(busy ? "Timing and memory appear after processing." : "Record or import audio to see timing and memory.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button {
                    if controller.recording { controller.stopRecording() }
                    else { controller.startRecording() }
                } label: {
                    Label(controller.recording ? "Finish recording" : "Record audio",
                        systemImage: controller.recording ? "stop.fill" : "mic.fill")
                }.buttonStyle(.borderedProminent).tint(AppPalette.speech)
                    .disabled(controller.processing || controller.inserting || !controller.microphoneAllowed)
                Button { controller.importAudio() } label: {
                    Label("Import audio…", systemImage: "square.and.arrow.down")
                }.disabled(busy)
            }
            if !controller.microphoneAllowed {
                Label("Microphone access is off", systemImage: "mic.slash").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 28).diagnosticCard()
    }

    private var activity: some View {
        HStack(alignment: .top, spacing: 12) {
            if busy { ProgressView().controlSize(.small).padding(.top, 2) }
            else {
                Image(systemName: "info.circle").foregroundStyle(.secondary).padding(.top, 2)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(busy ? "Current activity" : "Last activity").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Text(controller.status).font(.callout).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if busy { Button("Cancel") { controller.cancel() }.disabled(controller.inserting) }
        }.quibbleCard(padding: 16)
    }

    private var insertionCheck: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Test insertion", systemImage: "cursorarrow.click").font(.headline)
            Text("Start the test, then switch to an empty field within five seconds. Quibble inserts “Quibble insertion test.”")
                .font(.callout).foregroundStyle(.secondary)
            Button { controller.testInsertion() } label: {
                Label("Start 5-second test", systemImage: "timer")
            }.disabled(busy)
        }.diagnosticCard()
    }

    private func metricCard(_ title: String, value: String, detail: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.75)
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.quibbleCard(padding: 18)
    }

    private func timingRow(_ part: TimingPart, total: Double) -> some View {
        HStack(spacing: 9) {
            RoundedRectangle(cornerRadius: 3).fill(part.color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(part.name).font(.callout)
            Spacer()
            Text(duration(part.seconds)).font(.callout.monospacedDigit())
            Text(total > 0 ? String(format: "%.0f%%", min(1, max(0, part.seconds / total)) * 100) : "—")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 35, alignment: .trailing)
        }.accessibilityElement(children: .combine)
    }

    private func detailRow(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }.font(.callout)
    }

    private func parts(_ result: InferenceResult) -> [TimingPart] {
        // Aggregate inference times exclude loading; stage traces include it.
        // Use only the aggregates here so loading is represented exactly once.
        var values = [
            TimingPart(name: "Model loading", seconds: max(0, result.loadSeconds)),
            TimingPart(name: "Transcription", seconds: max(0, result.transcriptionSeconds)),
            TimingPart(name: "Vocabulary", seconds: max(0, result.vocabularySeconds ?? 0)),
            TimingPart(name: "Refinement", seconds: max(0, result.refinementSeconds))
        ]
        let accounted = values.reduce(0) { $0 + $1.seconds }
        values.append(TimingPart(name: "Other processing", seconds: max(0, result.processingSeconds - accounted)))
        return values
    }

    private func duration(_ seconds: Double) -> String { String(format: "%.3f s", seconds) }
    private func memory(_ bytes: Int) -> String { String(format: "%.2f GB", Double(bytes) / 1e9) }

    private struct TimingPart: Identifiable {
        let name: String
        let seconds: Double
        var id: String { name }
        var color: Color {
            switch name {
            case "Transcription": AppPalette.speech
            case "Vocabulary": AppPalette.vocabulary
            case "Refinement": AppPalette.instructions
            case "Model loading": AppPalette.speed
            default: Color.secondary.opacity(0.55)
            }
        }
    }
}

private extension View {
    func diagnosticCard() -> some View {
        quibbleCard()
    }
}
