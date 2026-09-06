import SwiftUI
import QuibbleCore

struct SettingsView: View {
    @ObservedObject var controller: DictationController
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var section = "Feedback"
    @State private var editing: ShortcutAction?
    @AppStorage(FeedbackSoundStyle.preferenceKey) private var soundStyle = FeedbackSoundStyle.soft.rawValue
    private var busy: Bool { controller.recording || controller.processing }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Settings").font(.largeTitle.bold())
            Picker("Settings section", selection: $section) {
                ForEach(["Feedback", "Shortcuts", "Device"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            switch section {
            case "Feedback": feedback
            case "Shortcuts": shortcuts
            default:
                VStack(alignment: .leading, spacing: 16) {
                    Label("Resource use", systemImage: "leaf").font(.headline)
                    Label("Unload after 2 idle minutes", systemImage: "leaf.fill").foregroundStyle(AppPalette.vocabulary)
                    Text("Models load when needed. Recorded audio is deleted after processing.").font(.callout).foregroundStyle(.secondary)
                    Button("Unload models now") { controller.unloadModels() }.disabled(busy)
                }.settingsCard()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: section)
        .sheet(item: $editing) { action in ShortcutEditor(controller: controller, action: action) }
        .onAppear { controller.refreshShortcutConflicts() }
    }
    private var feedback: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Toggle("Floating indicator", isOn: $controller.hudEnabled).font(.headline).disabled(busy)
                    Spacer()
                    Button("Preview", systemImage: "play.fill") { controller.previewFeedback() }
                        .disabled(busy || !controller.hudEnabled)
                        .help("Preview the indicator and sounds without recording")
                }
                Text("Layout").font(.callout.weight(.medium))
                HStack(spacing: 10) {
                    ForEach(HUDStyle.allCases) { style in
                        styleChoice(style)
                    }
                }.disabled(busy || !controller.hudEnabled)
                HStack {
                    Text("Material").font(.callout.weight(.medium))
                    Spacer()
                    Picker("HUD material", selection: $controller.hudMaterial) {
                        ForEach(HUDMaterial.allCases) { material in Text(material.rawValue).tag(material) }
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                        .disabled(busy || !controller.hudEnabled)
                        .accessibilityLabel("HUD material, applies to every layout")
                }
                if reduceTransparency && controller.hudMaterial == .frosted {
                    Text("Reduce Transparency is on, so Frosted uses a solid background.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                FeedbackPreview(feedback: controller.feedback)
            }.settingsCard()
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Sound cues", isOn: $controller.soundEnabled).font(.headline)
                    Text(FeedbackSoundStyle(rawValue: soundStyle)?.subtitle ?? FeedbackSoundStyle.soft.subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Sound style", selection: $soundStyle) {
                    ForEach(FeedbackSoundStyle.allCases) { sound in Text(sound.rawValue).tag(sound.rawValue) }
                }.labelsHidden().frame(width: 130).disabled(!controller.soundEnabled)
                Button { controller.feedback.previewSound() } label: {
                    Image(systemName: "speaker.wave.2").frame(width: 20, height: 20)
                }.accessibilityLabel("Preview sound cues").help("Preview sound cues")
                    .disabled(busy || !controller.soundEnabled)
            }.settingsCard()
        }
    }
    private func styleChoice(_ style: HUDStyle) -> some View {
        let selected = controller.hudStyle == style
        return Button {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.18)) { controller.hudStyle = style }
        } label: {
            VStack(spacing: 12) {
                HUDStyleThumbnail(style: style, material: controller.hudMaterial).frame(height: 78)
                HStack(spacing: 5) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? AppPalette.speech : .secondary)
                    Text(style.name).font(.callout.weight(.medium))
                }
                Text(style.subtitle).font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity).padding(.vertical, 17)
                .background(selected ? AppPalette.speech.opacity(0.10) : Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? AppPalette.speech.opacity(0.5) : Color.primary.opacity(0.06), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).accessibilityLabel(style.name + ", " + style.detail)
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Global shortcuts", systemImage: "keyboard").font(.headline)
                Spacer()
                Toggle("Enabled", isOn: Binding(get: { controller.shortcutEnabled }, set: { _ in controller.toggleShortcut() }))
                    .labelsHidden().toggleStyle(.switch).accessibilityLabel("Enable global shortcuts")
            }
            shortcutRow(ShortcutAction.hold.title, binding: controller.dictationShortcut, action: .hold)
            Divider()
            shortcutRow(ShortcutAction.toggle.title, binding: controller.toggleDictationShortcut, action: .toggle)
            Divider()
            shortcutRow(ShortcutAction.pasteLast.title, binding: controller.pasteShortcut, action: .pasteLast)
            Divider()
            HStack { Text("Cancel shortcut recording"); Spacer(); ShortcutKeys(keys: ["Esc"]) }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(controller.shortcutConflictWarnings.isEmpty
                          ? (controller.shortcutConflictSnapshot.systemCheckAvailable ? "No known conflicts" : "Check unavailable")
                          : "Shortcut conflict",
                          systemImage: controller.shortcutConflictWarnings.isEmpty
                          ? (controller.shortcutConflictSnapshot.systemCheckAvailable ? "checkmark.shield" : "info.circle")
                          : "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(controller.shortcutConflictWarnings.isEmpty
                            ? (controller.shortcutConflictSnapshot.systemCheckAvailable ? AppPalette.vocabulary : Color.secondary)
                            : AppPalette.speed)
                        .help("Some app shortcuts can’t be checked.")
                    Spacer()
                    Button("Check again") { controller.refreshShortcutConflicts() }.font(.caption)
                }
                ForEach(controller.shortcutConflictWarnings, id: \.self) { warning in
                    Text(warning).font(.caption).foregroundStyle(.secondary)
                }
            }
        }.settingsCard().disabled(busy)
    }
    private func shortcutRow(_ title: String, binding: ShortcutBinding, action: ShortcutAction) -> some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            ShortcutKeys(keys: binding.keys)
            Button("Change…") { editing = action }.accessibilityLabel("Change " + title + " shortcut")
        }
    }
}
private extension View {
    func settingsCard() -> some View {
        quibbleCard()
    }
}

private struct FeedbackPreview: View {
    @ObservedObject var feedback: DictationFeedback
    var body: some View {
        if feedback.isPreview {
            DictationHUD(feedback: feedback).allowsHitTesting(false)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 20))
                .accessibilityLabel("HUD preview: " + feedback.title)
        }
    }
}

private struct HUDStyleThumbnail: View {
    let style: HUDStyle
    let material: HUDMaterial
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var radius: CGFloat { style == .compact ? 15 : 18 }
    var body: some View {
        Group {
            if style == .solid {
                VStack(spacing: 5) {
                    HStack {
                        Text("Listening").font(.system(size: 9, weight: .medium))
                        Spacer(minLength: 2)
                        Text("0:08").font(.system(size: 8, design: .monospaced)).opacity(0.5)
                    }
                    waveform(bars: 32, height: 15)
                    HStack(spacing: 5) {
                        Text("Cancel").font(.system(size: 7)).opacity(0.65)
                        Spacer()
                        Text("Finish").font(.system(size: 7, weight: .medium)).foregroundStyle(.black.opacity(0.8))
                            .padding(.horizontal, 6).padding(.vertical, 4).background(.white.opacity(0.8), in: Capsule())
                    }
                }.padding(11).frame(width: 144, height: 70)
            } else if style == .glass {
                VStack(spacing: 4) {
                    HStack {
                        Text("Listening").font(.system(size: 8, weight: .medium))
                        Spacer()
                        Text("0:08").font(.system(size: 7, design: .monospaced)).opacity(0.5)
                    }
                    HStack(spacing: 7) {
                        waveform(bars: 16, height: 13)
                        Image(systemName: "checkmark").font(.system(size: 7))
                        Image(systemName: "xmark").font(.system(size: 6)).opacity(0.6)
                    }
                }.padding(.horizontal, 12).frame(width: 144, height: 43)
            } else {
                HStack(spacing: 7) {
                    waveform(bars: 12, height: 13)
                    Text("0:08").font(.system(size: 9, design: .monospaced)).opacity(0.6)
                }.padding(.horizontal, 12).frame(width: 124, height: 30)
            }
        }
        .background {
            if material == .frosted && !reduceTransparency {
                RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black.opacity(0.22)))
            } else { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(white: 0.1)) }
        }
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .foregroundStyle(.white).preferredColorScheme(.dark).accessibilityHidden(true)
    }
    private func waveform(bars: Int, height: CGFloat) -> some View {
        let levels: [CGFloat] = [0.2, 0.32, 0.54, 0.41, 0.28, 0.47, 0.74, 0.9,
            0.66, 0.42, 0.63, 0.82, 1, 0.73, 0.48, 0.34,
            0.51, 0.77, 0.93, 0.64, 0.4, 0.56, 0.79, 0.68,
            0.46, 0.33, 0.57, 0.72, 0.49, 0.29, 0.38, 0.22]
        return HStack(spacing: 1.5) {
            ForEach(0..<bars, id: \.self) { index in
                Capsule().fill(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(3, height * levels[index * (levels.count - 1) / (bars - 1)]))
            }
        }.frame(height: height)
    }
}
