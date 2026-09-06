import Foundation

public struct ShortcutBinding: Codable, Equatable, Sendable {
    public var keyCode: UInt16
    public var modifiers: UInt64
    public var keyName: String
    // Match the four device-independent CGEvent modifier bits.
    public static let shift: UInt64 = 1 << 17
    public static let control: UInt64 = 1 << 18
    public static let option: UInt64 = 1 << 19
    public static let command: UInt64 = 1 << 20
    public static let modifierMask = shift | control | option | command
    public static let dictation = Self(keyCode: 49, modifiers: option, keyName: "Space")
    public static let toggleDictation = Self(keyCode: 49, modifiers: control | option, keyName: "Space")
    public static let pasteLast = Self(keyCode: 9, modifiers: control | command, keyName: "V")
    public init(keyCode: UInt16, modifiers: UInt64, keyName: String) {
        self.keyCode = keyCode; self.modifiers = modifiers; self.keyName = keyName
    }
    public var keys: [String] {
        [(Self.control, "⌃"), (Self.option, "⌥"), (Self.shift, "⇧"), (Self.command, "⌘")]
            .compactMap { modifiers & $0.0 != 0 ? $0.1 : nil } + [keyName]
    }
    public var display: String { keys.joined(separator: " ") }
    public func conflicts(with other: Self) -> Bool { keyCode == other.keyCode && modifiers == other.modifiers }
    public var validationError: String? {
        guard modifiers & (Self.control | Self.option | Self.command) != 0,
              modifiers & ~Self.modifierMask == 0 else { return "Include Control, Option or Command." }
        guard keyCode <= 126, ![53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode),
              !keyName.isEmpty, keyName.count <= 24 else { return "Choose a key with modifiers. Escape is reserved for cancellation." }
        if modifiers == Self.command && [0, 6, 7, 8, 9, 12, 13, 48, 49].contains(keyCode) {
            return "That combination is a common system or editing shortcut. Add another modifier."
        }
        return nil
    }
}

public struct ShortcutState: Sendable {
    public enum Event: Sendable { case down, up, modifiersChanged }
    public enum Action: Equatable, Sendable { case press, release, toggle, cancel, pasteLast }
    public struct Result: Equatable, Sendable {
        public let consume: Bool
        public let action: Action?
        public init(consume: Bool = false, action: Action? = nil) { self.consume = consume; self.action = action }
    }
    public var dictation: ShortcutBinding
    public var toggleDictation: ShortcutBinding
    public var pasteLast: ShortcutBinding
    // Set by the recorder owner, so a rejected shortcut never arms Escape.
    public var toggleRecording = false
    public init(dictation: ShortcutBinding = .dictation, toggleDictation: ShortcutBinding = .toggleDictation, pasteLast: ShortcutBinding = .pasteLast) {
        self.dictation = dictation; self.toggleDictation = toggleDictation; self.pasteLast = pasteLast
    }
    private var held = false
    private var consumedKeys: Set<UInt16> = []
    public mutating func reset() { held = false; toggleRecording = false; consumedKeys.removeAll() }
    /// A slow event tap is recoverable. Reconcile hardware state without cancelling a live toggle.
    public mutating func recoverAfterTimeout(pressedKeys: Set<UInt16>, modifiers: UInt64) -> Result {
        consumedKeys.formIntersection(pressedKeys)
        guard held else { return Result() }
        guard pressedKeys.contains(dictation.keyCode), modifiers & dictation.modifiers == dictation.modifiers else {
            held = false
            return Result(action: .release)
        }
        return Result()
    }
    public mutating func handle(_ event: Event, key: UInt16 = 0, modifiers: UInt64 = 0, repeated: Bool = false) -> Result {
        if event == .up, consumedKeys.remove(key) != nil {
            if held && key == dictation.keyCode { held = false; return Result(consume: true, action: .release) }
            return Result(consume: true)
        }
        if event == .modifiersChanged && held && modifiers & dictation.modifiers != dictation.modifiers {
            held = false
            return Result(action: .release)
        }
        guard event == .down else { return Result() }
        if consumedKeys.contains(key) { return Result(consume: true) }
        if (held || toggleRecording) && key == 53 {
            held = false; toggleRecording = false
            consumedKeys.insert(key); return Result(consume: true, action: .cancel)
        }
        if !held && !repeated && key == pasteLast.keyCode && modifiers & ShortcutBinding.modifierMask == pasteLast.modifiers {
            consumedKeys.insert(key); return Result(consume: true, action: .pasteLast)
        }
        if !repeated && key == toggleDictation.keyCode && modifiers & ShortcutBinding.modifierMask == toggleDictation.modifiers {
            consumedKeys.insert(key); return Result(consume: true, action: .toggle)
        }
        if !repeated && key == dictation.keyCode && modifiers & ShortcutBinding.modifierMask == dictation.modifiers {
            held = true; consumedKeys.insert(key); return Result(consume: true, action: .press)
        }
        return Result()
    }
}
