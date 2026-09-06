import SwiftUI
import QuibbleCore
import QuibbleInference

struct ModelCapabilities: View {
    let spec: LocalModelSpec
    var expanded = false
    private var engine: SpeechEngine? { SpeechEngine(rawValue: spec.name) }
    var body: some View {
        if expanded {
            VStack(alignment: .leading, spacing: 12) {
                Text("Capabilities in Quibble").font(.headline)
                if let engine {
                    row("Personal vocabulary", detail: "Shared audio helper in a Saved spellings step; optional S1-mini check for ambiguity.", supported: true, color: AppPalette.vocabulary)
                    row("Language controls", detail: engine.languageDescription, supported: engine.supportsLanguageSelection, color: AppPalette.speech)
                    row("Temperature", detail: engine.supportsTemperature ? "Adjustable in Developer; zero uses greedy decoding." : "Greedy decoding; temperature has no effect in this adapter.", supported: engine.supportsTemperature, color: AppPalette.instructions)
                    row("Primary ASR vocabulary hints", detail: "Primary recognition runs without hints. Saved words are checked in a separate, guarded audio pass.", supported: false, color: .secondary)
                    row("Transcript timing", detail: alignedTimes(engine) ? "Aligned sentence timestamps appear in History’s Timeline." : "Actual audio-section boundaries appear in History’s Timeline; these are not word alignments.", supported: true, color: AppPalette.speech)
                    row("Speaker labels", detail: "This recognizer does not separate voices. Choose OpenAI Speakers under Online transcription for speaker-labeled turns.", supported: false, color: .secondary)
                    row("Live partial transcripts", detail: "Recognition runs after you finish recording.", supported: false, color: .secondary)
                    row("Custom formatting", detail: "Add a separate instruction model to your workflow.", supported: false, color: .secondary)
                } else {
                    row("Text cleanup", detail: spec.name == "s1-mini" ? "Fixed normalization for spelling, punctuation and prose." : "Follow your workflow prompt to edit or format text.", supported: true, color: AppPalette.vocabulary)
                    row("Custom prompts", detail: spec.name == "s1-mini" ? "S1-mini uses its fixed cleanup prompt." : "Editable instructions in Modes; local generation with thinking disabled.", supported: spec.name != "s1-mini", color: AppPalette.instructions)
                    row("Audio transcription", detail: "Requires a speech model earlier in the workflow.", supported: false, color: .secondary)
                }
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { badges }
                VStack(alignment: .leading, spacing: 6) { badges }
            }
        }
    }
    @ViewBuilder private var badges: some View {
        if let engine {
            badge("Saved words", symbol: "character.book.closed", color: AppPalette.vocabulary, help: "Supported through Quibble’s shared audio helper when a Saved spellings step is enabled.")
            badge(engine.isMoonshine ? "English" : engine.supportsLanguageSelection ? "Language choice" : "Auto language", symbol: "globe", color: AppPalette.speech, help: engine.languageDescription)
            badge(alignedTimes(engine) ? "Aligned times" : "Section times", symbol: "clock", color: .secondary, help: alignedTimes(engine) ? "Sentence alignment from the acoustic model, shown in History." : "Actual recording section boundaries, not word timestamps. Shown in History.")
        } else {
            badge(spec.role == "Cleanup" ? "Cleanup" : "Formatting", symbol: "wand.and.stars", color: AppPalette.vocabulary, help: "Local text processing; requires a transcript.")
            badge(spec.role == "Cleanup" ? "No custom prompts" : "Custom prompts", symbol: spec.role == "Cleanup" ? "minus.circle" : "text.bubble", color: spec.role == "Cleanup" ? .secondary : AppPalette.instructions, help: spec.role == "Cleanup" ? "S1-mini follows a fixed cleanup prompt." : "Write instructions in a workflow step.")
            badge("Text only", symbol: "text.alignleft", color: .secondary, help: "This model does not transcribe audio.")
        }
    }
    private func alignedTimes(_ engine: SpeechEngine) -> Bool { engine.isParakeet || engine == .nemotron }
    private func badge(_ title: String, symbol: String, color: Color, help: String) -> some View {
        Label(title, systemImage: symbol).font(.caption2.weight(.medium)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .help(help)
    }
    private func row(_ title: String, detail: String, supported: Bool, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: supported ? "checkmark.circle.fill" : "minus.circle").foregroundStyle(supported ? color : .secondary)
                .accessibilityLabel(supported ? "Supported" : "Not available in this step")
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Informational color has a stable meaning across cards, sections and feedback.
/// Named light/dark variants keep small labels readable without fluorescent system hues.
enum AppPalette {
    static let speech = Color("CapabilitySpeech")
    static let vocabulary = Color("CapabilityVocabulary")
    static let instructions = Color("CapabilityInstructions")
    static let speed = Color("CapabilitySpeed")
}

enum AppSurface {
    static let cardRadius: CGFloat = 20
    static let rowRadius: CGFloat = 12
}

extension View {
    func quibbleCard(padding inset: CGFloat = 20) -> some View {
        padding(inset).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.75),
                in: RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AppSurface.cardRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.055), lineWidth: 0.5))
    }
}
