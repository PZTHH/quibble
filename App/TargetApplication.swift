import AppKit
import ApplicationServices

// Delivery and readback are separate: some editors accept paste without exposing AXValue.
enum InsertionResult: Equatable {
    case confirmed, unconfirmed, notSent(String)
    var isConfirmed: Bool { self == .confirmed }
    var wasSent: Bool { if case .notSent = self { return false }; return true }
    func message(in name: String, pasteShortcut: String = "⌃⌘V") -> String {
        switch self {
        case .confirmed: return "Inserted into \(name)."
        case .unconfirmed: return "Paste sent to \(name). This editor did not confirm it. Check the field before using \(pasteShortcut) to paste again. Your transcript is retained in Quibble."
        case .notSent(let reason): return reason + " Your transcript is ready to copy or paste with \(pasteShortcut)."
        }
    }
}

@MainActor
struct TargetApplication {
    let pid: pid_t
    let name: String
    let bundleID: String
    let element: AXUIElement
    let window: AXUIElement?
    let original: String?
    let selection: CFRange?

    static func capture() -> TargetApplication? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        let window = axElement(attribute(application, kAXFocusedWindowAttribute))
        // Opaque editors sometimes expose only their window. Keep a best-effort destination.
        guard let field = axElement(attribute(application, kAXFocusedUIElementAttribute)) ?? window else { return nil }
        return capture(pid: app.processIdentifier, name: app.localizedName ?? "Application",
            bundleID: app.bundleIdentifier ?? "", field: field, window: window, read: attribute)
    }

    static func capture(pid: pid_t, name: String, bundleID: String, field: AXUIElement,
                        window: AXUIElement? = nil,
                        read: (AXUIElement, String) -> CFTypeRef?) -> TargetApplication? {
        let role = read(field, kAXRoleAttribute) as? String ?? ""
        let subrole = read(field, kAXSubroleAttribute) as? String
        // Reject known non-input controls, but do not maintain an app or editor-role allow-list.
        let nonInput = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXSliderRole,
                        kAXMenuItemRole, kAXMenuBarRole, kAXImageRole, kAXStaticTextRole,
                        "AXLink", kAXPopUpButtonRole]
        guard subrole != kAXSecureTextFieldSubrole, !nonInput.contains(role),
              (read(field, kAXEnabledAttribute) as? Bool) != false else { return nil }
        let value = read(field, kAXValueAttribute) as? String
        // Large/opaque values disable verification, not insertion.
        let original = value.flatMap { $0.utf16.count <= 32_000 ? $0 : nil }
        let range = selectedRange(read(field, kAXSelectedTextRangeAttribute))
        let selection = range.flatMap { range -> CFRange? in
            guard range.location >= 0, range.length >= 0,
                  range.location <= Int.max - range.length else { return nil }
            if let original, range.location + range.length > original.utf16.count { return nil }
            return range
        }
        return TargetApplication(pid: pid, name: name, bundleID: bundleID,
            element: field, window: window, original: original, selection: selection)
    }

    static func captureDiagnostic() -> String {
        guard AXIsProcessTrusted() else { return "Accessibility access is unavailable." }
        guard let app = NSWorkspace.shared.frontmostApplication else { return "No foreground application." }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return "Quibble is still the foreground app. Switch to another app's editor."
        }
        guard let target = capture() else {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            let focused = axElement(attribute(application, kAXFocusedUIElementAttribute))
            let role = focused.flatMap { attribute($0, kAXRoleAttribute) as? String } ?? "no focused element"
            return "\(app.localizedName ?? "Application") · \(role) · no eligible input destination."
        }
        return "\(target.name) · \(target.original == nil ? "text readback unavailable" : "text readable") · \(target.selection == nil ? "selection unavailable" : "selection available") · clipboard paste"
    }

    func sameDestination(as current: TargetApplication) -> Bool {
        guard pid == current.pid, CFEqual(element, current.element) else { return false }
        if let window { guard let other = current.window, CFEqual(window, other) else { return false } }
        return true
    }

    func stillMatches(_ current: TargetApplication?) -> Bool {
        guard let current, sameDestination(as: current) else { return false }
        if let original, original != current.original { return false }
        if let selection {
            guard let other = current.selection, selection.location == other.location,
                  selection.length == other.length else { return false }
        }
        return true
    }

    func editedInsertion(_ text: String) -> String? {
        guard let current = Self.capture(), sameDestination(as: current),
              let original, let selection, let value = current.original else { return nil }
        let source = original as NSString
        let prefix = source.substring(to: selection.location)
        let suffix = source.substring(from: selection.location + selection.length)
        guard value.hasPrefix(prefix), value.hasSuffix(suffix),
              value.utf16.count >= prefix.utf16.count + suffix.utf16.count else { return nil }
        let edited = (value as NSString).substring(with: NSRange(location: prefix.utf16.count,
            length: value.utf16.count - prefix.utf16.count - suffix.utf16.count))
        guard edited.count <= text.count + 160 else { return nil }
        return edited
    }

    func insert(_ text: String, using io: any InsertionIO = SystemInsertionIO(),
                onPasteSent: (() -> Void)? = nil) async -> InsertionResult {
        guard !text.isEmpty else { return .notSent("No text to insert.") }
        // Fast ASR can finish before the dictation/recovery modifiers have been released.
        for _ in 0..<30 {
            if io.modifiersReleased { break }
            await io.wait(milliseconds: 25)
            if Task.isCancelled { return .notSent("Insertion cancelled.") }
        }
        guard !Task.isCancelled else { return .notSent("Insertion cancelled.") }
        guard io.modifiersReleased else { return .notSent("Release the shortcut keys before pasting.") }
        guard stillMatches(io.currentTarget()) else { return .notSent("The input destination changed.") }
        let saved = io.snapshotClipboard()
        guard stillMatches(io.currentTarget()) else { return .notSent("The input destination changed.") }
        guard io.clipboardChangeCount == saved.changeCount else { return .notSent("The clipboard changed.") }
        let staged = io.stage(text)
        let ownedChange = io.clipboardChangeCount
        guard staged else {
            io.restore(saved, ifOwned: ownedChange)
            return .notSent("Could not prepare the clipboard.")
        }
        guard stillMatches(io.currentTarget()), io.modifiersReleased else {
            io.restore(saved, ifOwned: ownedChange)
            return .notSent("The input destination or shortcut keys changed.")
        }
        guard io.clipboardChangeCount == ownedChange else { return .notSent("The clipboard changed.") }
        guard io.postPaste() else {
            io.restore(saved, ifOwned: ownedChange)
            return .notSent("Could not send the paste shortcut.")
        }
        // Presentation can finish promptly; readback and clipboard ownership
        // remain part of this same single-dispatch transaction.
        onPasteSent?()
        let expected: String? = if let original, let selection {
            (original as NSString).replacingCharacters(in: NSRange(location: selection.location, length: selection.length), with: text)
        } else { nil }
        // Opaque fields and unchanged replacements cannot acknowledge this paste.
        // Retain its clipboard contents without blocking the next recording for a futile readback.
        guard let expected, expected != original else { return .unconfirmed }
        // Never send a second insertion after dispatch: a missing acknowledgement is ambiguous.
        for _ in 0..<20 {
            await io.wait(milliseconds: 50)
            if io.readValue(element) == expected {
                io.restore(saved, ifOwned: ownedChange)
                return .confirmed
            }
        }
        // Keep the transcript available for manual paste when the editor cannot acknowledge.
        // If the user copied something meanwhile, do not touch their new clipboard contents.
        return .unconfirmed
    }

    fileprivate static func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
    }
    private static func axElement(_ raw: CFTypeRef?) -> AXUIElement? {
        guard let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(raw, to: AXUIElement.self)
    }
    private static func selectedRange(_ raw: CFTypeRef?) -> CFRange? {
        guard let raw, CFGetTypeID(raw) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(unsafeDowncast(raw, to: AXValue.self), .cfRange, &range) ? range : nil
    }
}

struct InsertionClipboard {
    let changeCount: Int
    let items: [NSPasteboardItem]
}

// The live service and deterministic tests exercise the same transaction, including timing,
// focus checks, clipboard ownership and the single-dispatch rule.
@MainActor
protocol InsertionIO {
    var modifiersReleased: Bool { get }
    var clipboardChangeCount: Int { get }
    func currentTarget() -> TargetApplication?
    func snapshotClipboard() -> InsertionClipboard
    func stage(_ text: String) -> Bool
    func restore(_ snapshot: InsertionClipboard, ifOwned changeCount: Int)
    func postPaste() -> Bool
    func readValue(_ element: AXUIElement) -> String?
    func wait(milliseconds: Int) async
}

@MainActor
final class SystemInsertionIO: InsertionIO {
    private let board: NSPasteboard
    init(pasteboard: NSPasteboard = .general) { board = pasteboard }
    var modifiersReleased: Bool {
        CGEventSource.flagsState(.combinedSessionState).intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift]).isEmpty
    }
    var clipboardChangeCount: Int { board.changeCount }
    func currentTarget() -> TargetApplication? { TargetApplication.capture() }
    func snapshotClipboard() -> InsertionClipboard {
        let change = board.changeCount
        let items: [NSPasteboardItem] = board.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types { if let data = item.data(forType: type) { copy.setData(data, forType: type) } }
            return copy
        } ?? []
        return InsertionClipboard(changeCount: change, items: items)
    }
    func stage(_ text: String) -> Bool {
        board.clearContents()
        return board.setString(text, forType: .string)
    }
    func restore(_ snapshot: InsertionClipboard, ifOwned changeCount: Int) {
        guard board.changeCount == changeCount else { return }
        board.clearContents()
        if !snapshot.items.isEmpty { board.writeObjects(snapshot.items) }
    }
    func postPaste() -> Bool {
        guard let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return true
    }
    func readValue(_ element: AXUIElement) -> String? {
        TargetApplication.attribute(element, kAXValueAttribute) as? String
    }
    func wait(milliseconds: Int) async { try? await Task.sleep(for: .milliseconds(milliseconds)) }
}
