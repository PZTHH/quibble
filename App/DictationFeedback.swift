import AppKit
import SwiftUI
import Combine
import QuibbleCore

enum HUDStyle: String, CaseIterable, Identifiable {
    // Persisted raw values stay stable for existing installations.
    case solid = "Solid", glass = "Glass", compact = "Compact"
    var id: String { rawValue }
    var name: String { switch self { case .solid: "Studio"; case .glass: "Strip"; case .compact: "Compact" } }
    var width: CGFloat { switch self { case .solid: 352; case .glass: 316; case .compact: 188 } }
    var height: CGFloat { switch self { case .solid: 134; case .glass: 62; case .compact: 40 } }
    var subtitle: String { switch self { case .solid: "Details & controls"; case .glass: "Lightweight controls"; case .compact: "Just the essentials" } }
    var detail: String {
        switch self {
        case .solid: "Time, processing details, and full recording controls."
        case .glass: "A slim strip with quick finish and cancel actions."
        case .compact: "A small, click-through indicator. Your shortcut handles recording."
        }
    }
}

enum HUDMaterial: String, CaseIterable, Identifiable {
    case solid = "Solid", frosted = "Frosted"
    static let preferenceKey = "hudMaterial"
    var id: String { rawValue }

    /// Persist migration immediately so future layout changes cannot change the material on restart.
    static func restored(from defaults: UserDefaults = .standard) -> Self {
        if let stored = defaults.string(forKey: preferenceKey), let material = Self(rawValue: stored) { return material }
        let material: Self = defaults.string(forKey: "hudStyle") == HUDStyle.glass.rawValue ? .frosted : .solid
        defaults.set(material.rawValue, forKey: preferenceKey)
        return material
    }
}

enum FeedbackSoundStyle: String, CaseIterable, Identifiable {
    case soft = "Soft", original = "Original"
    static let preferenceKey = "feedbackSoundStyle"
    var id: String { rawValue }
    static var selected: Self {
        Self(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .soft
    }
    var subtitle: String { self == .soft ? "Rounded, quiet tones" : "Crisp feedback" }
    func resource(for cue: String) -> String { self == .soft ? "soft-" + cue : cue }
}

private final class DictationPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DictationFeedback: ObservableObject {
    enum Phase: Equatable { case starting, listening, processing, inserting, success, noSpeech, warning, cancelled }
    struct Destination: Equatable {
        let name: String
        let bundleID: String?
        let confirmed: Bool
    }
    @Published private(set) var destination: Destination?
    @Published private(set) var processingStartedAt = Date()
    @Published private(set) var amplitudes = Array(repeating: 0.0, count: HUDSignalMeter.columnCount)
    private var signalMeter = HUDSignalMeter()
    private var previousMeterTime: Double?
    @Published private(set) var phase: Phase = .listening
    @Published private(set) var title = "Listening"
    @Published private(set) var detail = ""
    var level: Double { amplitudes.max() ?? 0 }
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var isVisible = false
    @Published var heldShortcut: String?
    @Published var toggleShortcut: String?
    @Published private(set) var previewShortcut: String?
    @Published var style: HUDStyle = .solid
    @Published var material: HUDMaterial = .solid
    @Published private(set) var isPreview = false
    private var previewTask: Task<Void, Never>?
    private var soundPreviewTask: Task<Void, Never>?
    var onCancel: (() -> Void)?
    var onFinish: (() -> Void)?
    var hudEnabled = true { didSet { if !hudEnabled { panel?.orderOut(nil); isVisible = false } } }
    var soundEnabled = true { didSet { if !soundEnabled { soundPreviewTask?.cancel(); sound?.stop() } } }
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var sound: NSSound?

    func pasteSent(to destination: Destination) {
        show(.success, title: "Paste sent", detail: destination.name, destination: destination,
            cue: "complete", dismissAfter: 0.2)
    }

    /// Update a still-visible receipt without reopening a HUD that has dismissed.
    func confirmPaste(to destination: Destination) {
        guard phase == .success, self.destination?.bundleID == destination.bundleID else { return }
        self.destination = destination
        title = "Inserted"
    }

    func show(_ phase: Phase, title: String, detail: String = "", destination: Destination? = nil, cue: String? = nil, dismissAfter: Double? = nil, preview: Bool = false) {
        // A previous completion/preview cue must end before a new microphone capture.
        if phase == .starting && !preview { sound?.stop() }
        if !preview {
            previewTask?.cancel(); previewTask = nil
            previewShortcut = nil
            soundPreviewTask?.cancel(); soundPreviewTask = nil
        }
        isPreview = preview
        hideTask?.cancel()
        // Repeated model-stage updates keep the waiting animation continuous.
        if (phase == .processing || phase == .inserting) && self.phase != .processing && self.phase != .inserting {
            processingStartedAt = Date()
        }
        self.destination = destination
        self.phase = phase; self.title = title; self.detail = detail
        if let cue { playCue(cue) }
        if hudEnabled {
            if panel == nil {
                let window = DictationPanel(contentRect: NSRect(x: 0, y: 0, width: style.width, height: style.height + 12),
                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                window.isFloatingPanel = true; window.hidesOnDeactivate = false
                window.level = .statusBar; window.isOpaque = false; window.backgroundColor = .clear
                window.hasShadow = true; window.isMovableByWindowBackground = false
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: DictationHUD(feedback: self))
                panel = window
            }
            // The passive style passes clicks through; controls in other styles never activate Quibble.
            let hasControls = phase == .starting || phase == .listening || phase == .processing
            panel?.ignoresMouseEvents = style == .compact || preview || !hasControls
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
               let panel {
                panel.setContentSize(NSSize(width: style.width, height: style.height + 12))
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - panel.frame.width / 2,
                    y: screen.visibleFrame.minY + 14))
                panel.orderFrontRegardless()
                isVisible = true
                panel.contentView?.layoutSubtreeIfNeeded()
                panel.displayIfNeeded()
            }
        }
        if let dismissAfter {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(dismissAfter))
                guard !Task.isCancelled else { return }
                self?.panel?.orderOut(nil)
                self?.isVisible = false
            }
        }
    }

    private func playCue(_ cue: String) {
        guard soundEnabled,
              let url = Bundle.main.url(forResource: FeedbackSoundStyle.selected.resource(for: cue), withExtension: "wav")
                ?? Bundle.main.url(forResource: cue, withExtension: "wav") else { return }
        sound?.stop(); sound = NSSound(contentsOf: url, byReference: true)
        sound?.volume = 0.4; sound?.play()
    }

    func previewSound() {
        guard soundEnabled else { return }
        soundPreviewTask?.cancel()
        soundPreviewTask = Task { [weak self] in
            self?.playCue("start")
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            self?.playCue("stop")
        }
    }

    func preview(shortcut: String) {
        guard hudEnabled else { return }
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            self.previewShortcut = shortcut
            self.meter(power: -60, seconds: 0)
            self.show(.starting, title: "Starting microphone", detail: "Preview", preview: true)
            do {
                try await Task.sleep(for: .milliseconds(350))
                self.show(.listening, title: "Preview", cue: "start", preview: true)
                // Preview covers quiet, speech, a pause, and processing through the real meter path.
                let demoPowers: [Float] = [-60, -55, -48, -51, -54, -50, -60, -58,
                    -39, -30, -21, -27, -35, -24, -18, -29, -38, -26, -22, -33,
                    -57, -50, -54, -60, -55, -48, -53, -58]
                var previewAnalyzer = HUDSpectrumAnalyzer(sampleRate: 48_000)
                for (index, power) in demoPowers.enumerated() {
                    let amplitude = pow(10, Double(power) / 20)
                    let fundamental = 130.0 + Double(index % 5) * 32
                    let formant = [650.0, 1100, 1850, 850][index % 4]
                    let samples = (0..<HUDSpectrumAnalyzer.frameCount).map { sample -> Float in
                        let time = Double(sample) / 48_000
                        return Float(amplitude * (sin(2 * .pi * fundamental * time)
                            + 0.65 * sin(2 * .pi * formant * time)
                            + 0.3 * sin(2 * .pi * (formant + 1600) * time)))
                    }
                    let spectrum = previewAnalyzer?.analyze(samples: samples)
                    let crest: Float = index.isMultiple(of: 3) ? 12 : 6
                    self.meter(power: power, peak: power + crest, spectrum: spectrum, seconds: Double(index + 1) * 0.1)
                    try await Task.sleep(for: .milliseconds(100))
                }
                self.show(.processing, title: "Transcribing", detail: "Turning speech into text", cue: "stop", preview: true)
                try await Task.sleep(for: .milliseconds(1800))
                self.show(.success, title: "Inserted", detail: "Quibble",
                    destination: .init(name: "Quibble", bundleID: Bundle.main.bundleIdentifier, confirmed: true),
                    cue: "complete", dismissAfter: 0.2, preview: true)
            } catch { return }
        }
    }

    func meter(power: Float, peak: Float? = nil, spectrum: [Double]? = nil, seconds: Double) {
        let time = seconds.isFinite ? max(0, seconds) : 0
        if time == 0 || previousMeterTime.map({ time < $0 }) == true {
            signalMeter.reset()
            amplitudes = signalMeter.amplitudes
            previousMeterTime = time
            elapsed = time
            return
        }
        let delta = previousMeterTime.map { time - $0 } ?? 0.05
        previousMeterTime = time
        let next = signalMeter.update(averagePower: Double(power), peakPower: Double(peak ?? power), deltaTime: delta, spectrum: spectrum)
        if amplitudes != next { amplitudes = next }
        // The duration label only changes once a second; quiet input should not redraw at 20 Hz.
        let displayedTime = min(86_400, time.rounded(.down))
        if elapsed != displayedTime { elapsed = displayedTime }
    }

}

struct DictationHUD: View {
    @ObservedObject var feedback: DictationFeedback
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var active: Bool { feedback.phase == .starting || feedback.phase == .listening || feedback.phase == .processing }
    private var showsBars: Bool { feedback.phase == .starting || feedback.phase == .listening || working }
    private var working: Bool { feedback.phase == .processing || feedback.phase == .inserting }
    private var destinationLabel: String? {
        guard let destination = feedback.destination else { return nil }
        if feedback.phase == .inserting { return "Inserting into " + destination.name }
        return (destination.confirmed ? "Inserted into " : "Paste sent to ") + destination.name
            + (destination.confirmed ? "" : ". Check the field; this app did not confirm insertion.")
    }
    private var statusLabel: String {
        (feedback.isPreview ? "Preview. " : "") + (destinationLabel ?? (feedback.title + (feedback.detail.isEmpty ? "" : ". " + feedback.detail)))
    }
    private var animate: Bool { !reduceMotion && feedback.isVisible }
    private var phaseAnimation: Animation? { animate ? .easeInOut(duration: 0.16) : nil }
    private var radius: CGFloat { feedback.style == .compact ? 20 : 26 }
    private var timer: String { String(format: "%d:%02d", Int(feedback.elapsed) / 60, Int(feedback.elapsed) % 60) }
    private var currentShortcut: String? { feedback.isPreview ? feedback.previewShortcut : feedback.heldShortcut }
    private var finishHint: String? {
        guard feedback.phase == .listening else { return nil }
        if !feedback.isPreview, let toggle = feedback.toggleShortcut { return "Press " + toggle }
        return currentShortcut.map { "Release " + $0 }
    }
    private var cancelHint: String? {
        (feedback.phase == .starting || feedback.phase == .listening) && (currentShortcut != nil || feedback.toggleShortcut != nil) ? "Esc" : nil
    }
    private var shortTitle: String {
        switch feedback.phase {
        case .starting: "Starting"
        case .listening: feedback.isPreview ? "Preview" : "Listening"
        case .processing: "Working"
        case .inserting: "Inserting"
        case .success: feedback.destination.map { $0.confirmed ? "Inserted" : "Paste sent" } ?? "Ready"
        case .noSpeech: "No speech"
        case .warning: "Check Quibble"
        case .cancelled: "Cancelled"
        }
    }
    var body: some View {
        Group {
            switch feedback.style {
            case .solid: studio
            case .glass: strip
            case .compact: compact
            }
        }
        .frame(width: feedback.style.width, height: feedback.style.height)
        .background {
            if feedback.material == .frosted && !reduceTransparency {
                HUDVisualEffect().overlay(Color.black.opacity(0.22))
            } else { Color(white: 0.09) }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
        .help(statusLabel).accessibilityElement(children: .contain)
        .accessibilityLabel(statusLabel)
        .preferredColorScheme(.dark).padding(.vertical, 6)
    }

    private var studio: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if !showsBars && feedback.destination == nil && feedback.phase != .noSpeech { phaseIndicator.frame(width: 18, height: 16) }
                Text(feedback.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).truncationMode(.tail).contentTransition(.opacity)
                Spacer(minLength: 2)
                if feedback.elapsed > 0 { elapsedTime }
            }.frame(height: 17)
            Group {
                if showsBars {
                    waveform(bars: 64, height: 42)
                } else if feedback.phase == .noSpeech {
                    HStack(spacing: 10) {
                        Image(systemName: "mic.slash").font(.system(size: 24, weight: .light))
                        Text("Nothing to insert").font(.system(size: 11))
                    }.foregroundStyle(.white.opacity(0.55)).frame(maxWidth: .infinity)
                } else if feedback.destination != nil {
                    destinationIcon(size: 40).frame(maxWidth: .infinity)
                } else if !feedback.detail.isEmpty {
                    Text(feedback.detail).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                } else { Color.clear }
            }.frame(height: 46)
            if active {
                HStack(spacing: 8) {
                    actionButton("Cancel", symbol: "xmark", hint: cancelHint, prominent: false) { feedback.onCancel?() }
                    Spacer(minLength: 0)
                    if feedback.phase == .listening {
                        actionButton("Finish", symbol: "checkmark", hint: finishHint, prominent: true) { feedback.onFinish?() }
                    } else if working {
                        Text(feedback.detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }.frame(height: 28).transition(.opacity)
            }
        }.padding(.horizontal, 20)
            .animation(phaseAnimation, value: feedback.phase)
    }

    private var strip: some View {
        Group {
            if showsBars {
                VStack(spacing: 4) {
                    HStack {
                        Text(feedback.title).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1).contentTransition(.opacity)
                        Spacer(minLength: 4)
                        if feedback.elapsed > 0 { elapsedTime }
                    }
                    HStack(spacing: 10) {
                        waveform(bars: 48, height: 24).frame(maxWidth: .infinity)
                        if feedback.phase == .listening {
                            iconButton("Finish recording", symbol: "checkmark", hint: finishHint, showsHint: false) { feedback.onFinish?() }
                        }
                        if active { iconButton("Cancel dictation", symbol: "xmark", hint: cancelHint, showsHint: false) { feedback.onCancel?() } }
                    }.frame(height: 28)
                }
            } else {
                HStack(spacing: 10) {
                    if feedback.destination != nil { destinationIcon(size: 30) }
                    else { phaseIndicator.frame(width: 24, height: 24) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feedback.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.white)
                        if feedback.destination == nil && !feedback.detail.isEmpty {
                            Text(feedback.detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        }
                    }.lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
            }
        }.padding(.horizontal, 15).animation(phaseAnimation, value: feedback.phase)
    }

    private var compact: some View {
        HStack(spacing: 10) {
            if showsBars {
                waveform(bars: 32, height: 23).frame(maxWidth: .infinity)
                if feedback.phase == .listening { elapsedTime }
            } else {
                if feedback.destination != nil { destinationIcon(size: 24) }
                else { phaseIndicator.frame(width: 20, height: 24) }
                Text(shortTitle).font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.9).contentTransition(.opacity)
                Spacer(minLength: 0)
            }
        }.padding(.horizontal, 14).animation(phaseAnimation, value: feedback.phase)
    }

    @ViewBuilder
    private func destinationIcon(size: CGFloat) -> some View {
        if let destination = feedback.destination {
            ApplicationIcon(name: destination.name, bundleID: destination.bundleID, size: size)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: destination.confirmed ? "checkmark.circle.fill" : "arrow.up.forward.circle.fill")
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .symbolRenderingMode(.palette).foregroundStyle(Color(white: 0.9), Color(white: 0.16))
                        .background(Color(white: 0.16), in: Circle()).offset(x: 3, y: 2)
                }
                .accessibilityHidden(true)
        }
    }

    private var elapsedTime: some View {
        Text(timer).font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.5))
            .accessibilityLabel("Recording duration " + timer)
    }

    private func waveform(bars: Int, height: CGFloat) -> some View {
        // Only waiting needs a clock. Live bars update from the recorder; silence schedules no animation.
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate || !working)) { timeline in
            let time = timeline.date.timeIntervalSince(feedback.processingStartedAt)
            let values = (0..<bars).map { index -> Double in
                if working {
                    guard animate else { return 0.18 }
                    let position = Double(index) / Double(max(1, bars - 1))
                    let wave = 0.5 + 0.5 * sin(position * .pi * 3 - time * 3.6)
                    return 0.08 + 0.32 * pow(wave, 3)
                }
                guard feedback.phase == .listening else { return 0 }
                let sourceIndex = index * (feedback.amplitudes.count - 1) / max(1, bars - 1)
                return feedback.amplitudes[sourceIndex]
            }
            GeometryReader { geometry in
                let gap: CGFloat = feedback.style == .solid ? 3 : 2
                let width = max(1, (geometry.size.width - CGFloat(bars - 1) * gap) / CGFloat(bars))
                HStack(spacing: gap) {
                    ForEach(0..<bars, id: \.self) { index in
                        HUDMeterBar(amplitude: values[index], width: width, maximumHeight: height)
                    }
                }.frame(width: geometry.size.width, height: height + 4)
                    .animation(animate && !working ? .spring(response: 0.18, dampingFraction: 0.86) : nil,
                               value: feedback.amplitudes)
            }
        }.frame(height: height + 4).accessibilityHidden(true)
    }

    private var phaseIndicator: some View {
        Group {
            switch feedback.phase {
            case .starting, .listening: Image(systemName: "mic").foregroundStyle(.white.opacity(0.7))
            case .processing, .inserting: Image(systemName: "ellipsis").foregroundStyle(.white.opacity(0.7))
            case .success: Image(systemName: "checkmark").foregroundStyle(.white.opacity(0.85))
            case .noSpeech: Image(systemName: "mic.slash").foregroundStyle(.white.opacity(0.6))
            case .warning: Image(systemName: "exclamationmark.triangle").foregroundStyle(Color(red: 0.84, green: 0.72, blue: 0.52))
            case .cancelled: Image(systemName: "xmark").foregroundStyle(.white.opacity(0.55))
            }
        }.id(feedback.phase).transition(.opacity)
    }

    private func actionButton(_ title: String, symbol: String, hint: String?, prominent: Bool, action: @escaping () -> Void) -> some View {
        let foreground: Color = prominent ? Color(white: 0.12) : Color.white.opacity(0.75)
        let background: Color = prominent ? Color.white.opacity(0.85) : Color.white.opacity(0.07)
        let actionName = title == "Finish" ? "Finish recording" : "Cancel dictation"
        let explanation = actionName + (hint.map { ", " + $0 } ?? "")
        return Button(action: action) {
            HStack(spacing: 7) {
                Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium))
                if let hint {
                    Text(hint).font(.system(size: 9, weight: .medium)).opacity(0.65)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10).frame(height: 28)
            .background(background, in: Capsule())
            .contentShape(Capsule())
        }.buttonStyle(.plain).disabled(feedback.isPreview)
            .help(explanation).accessibilityLabel(explanation)
    }

    private func iconButton(_ title: String, symbol: String, hint: String?, showsHint: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                if showsHint, let hint {
                    Text(hint).font(.system(size: 8, weight: .medium)).opacity(0.65)
                        .lineLimit(1).minimumScaleFactor(0.75).frame(width: hint == "Esc" ? 15 : 78)
                }
            }.foregroundStyle(.white.opacity(0.75)).padding(.horizontal, 7)
                .frame(minWidth: 25, minHeight: 28).background(.white.opacity(0.07), in: Capsule())
                .contentShape(Capsule())
        }.buttonStyle(.plain).help(title + (hint.map { " · " + $0 } ?? ""))
            .accessibilityLabel(title + (hint.map { ", " + $0 } ?? ""))
            .disabled(feedback.isPreview)
    }
}

/// Clamp interpolated spring values too: silence stays above zero and bounce stays inside the reserved row.
private struct HUDMeterBar: View, Animatable {
    nonisolated var amplitude: Double
    let width: CGFloat
    let maximumHeight: CGFloat
    nonisolated var animatableData: Double {
        get { amplitude }
        set { amplitude = newValue }
    }
    var body: some View {
        let bounded = amplitude.isFinite ? min(1.06, max(0, amplitude)) : 0
        let height = 3 + CGFloat(bounded) * (maximumHeight - 3)
        Capsule().fill(Color(white: 0.88)).frame(width: width, height: height)
    }
}

private struct HUDVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
