import AppKit
import SwiftUI
import QuibbleCore

enum ShortcutAction: String, CaseIterable, Identifiable {
    case hold, toggle, pasteLast
    var id: String { rawValue }
    var title: String {
        switch self { case .hold: "Hold to dictate"; case .toggle: "Press to start / stop"; case .pasteLast: "Paste last transcript" }
    }
    var preferenceKey: String {
        switch self { case .hold: "dictationShortcut.v1"; case .toggle: "toggleShortcut.v1"; case .pasteLast: "pasteShortcut.v1" }
    }
    var defaultBinding: ShortcutBinding {
        switch self { case .hold: .dictation; case .toggle: .toggleDictation; case .pasteLast: .pasteLast }
    }
}

struct ShortcutEditor: View {
    @ObservedObject var controller: DictationController
    let action: ShortcutAction
    @Environment(\.dismiss) private var dismiss
    @State private var candidate: ShortcutBinding?
    @State private var error: String?
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(action.title).font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Image(systemName: "keyboard").font(.system(size: 34)).foregroundStyle(.secondary)
            Text("Press your new key combination").font(.headline)
            ShortcutKeys(keys: candidate?.keys ?? ["⌃ / ⌥ / ⌘", "+", "Key"])
            ShortcutCapture { binding in
                candidate = binding
                error = controller.shortcutValidation(binding, for: action)
            }.frame(height: 1)
            Text(error ?? "Include Control, Option or Command. Escape cancels.")
                .font(.callout).foregroundStyle(error == nil ? Color.secondary : .orange)
            HStack {
                Button("Use default") {
                    candidate = action.defaultBinding
                    error = controller.shortcutValidation(action.defaultBinding, for: action)
                }
                Spacer()
                Button("Save shortcut") {
                    guard let candidate else { return }
                    if controller.saveShortcut(candidate, for: action) { dismiss() }
                    else { error = controller.shortcutValidation(candidate, for: action) }
                }.buttonStyle(.borderedProminent).disabled(candidate == nil || error != nil)
            }
        }.padding(24).frame(width: 460)
            .onAppear { controller.suspendShortcuts(true); controller.refreshShortcutConflicts() }
            .onDisappear { controller.suspendShortcuts(false) }
            .onChange(of: controller.shortcutConflictSnapshot) { _, _ in
                if let candidate { error = controller.shortcutValidation(candidate, for: action) }
            }
    }
}

private struct ShortcutCapture: NSViewRepresentable {
    var onCapture: (ShortcutBinding) -> Void
    final class CaptureView: NSView {
        var onCapture: ((ShortcutBinding) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in guard let self else { return }; self.window?.makeFirstResponder(self) }
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard event.type == .keyDown, event.keyCode != 53 else { return false }
            capture(event); return true
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { super.keyDown(with: event); return }
            capture(event)
        }
        private func capture(_ event: NSEvent) {
            guard !event.isARepeat else { return }
            let special: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "Forward Delete",
                123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
                122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
            let name = special[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? "Key \(event.keyCode)"
            onCapture?(.init(keyCode: event.keyCode, modifiers: UInt64(event.modifierFlags.rawValue) & ShortcutBinding.modifierMask, keyName: name))
        }
    }
    func makeNSView(context: Context) -> CaptureView { let view = CaptureView(); view.onCapture = onCapture; return view }
    func updateNSView(_ view: CaptureView, context: Context) { view.onCapture = onCapture }
}
