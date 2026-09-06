import Foundation

/// A specifically configured shortcut, never an inference from an installed app.
public struct KnownShortcutConflict: Equatable, Sendable {
    public enum Source: String, Hashable, Sendable {
        case macOS, raycast
    }

    public let source: Source
    public let keyCode: UInt16
    public let modifiers: UInt64

    public var sourceName: String { source == .macOS ? "macOS" : "Raycast" }

    public func matches(_ binding: ShortcutBinding) -> Bool {
        keyCode == binding.keyCode && modifiers == binding.modifiers
    }

    public func message(for binding: ShortcutBinding) -> String {
        switch source {
        case .macOS: "\(binding.display) is enabled in macOS Keyboard Shortcuts."
        case .raycast: "\(binding.display) is configured to open Raycast."
        }
    }

    /// Legacy Raycast's stored physical-key format. Unknown formats are not guesses.
    public static func raycastLegacyPreference(_ value: String) -> Self? {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 2, let last = parts.last,
              !last.isEmpty, last.allSatisfy({ $0.isASCII && $0.isNumber }),
              let keyCode = UInt16(last), keyCode <= 126,
              ![54, 55, 56, 57, 58, 59, 60, 61, 62, 63].contains(keyCode) else { return nil }
        let flags: [Substring: UInt64] = [
            "Control": ShortcutBinding.control, "Option": ShortcutBinding.option,
            "Shift": ShortcutBinding.shift, "Command": ShortcutBinding.command,
        ]
        var modifiers: UInt64 = 0
        for part in parts.dropLast() {
            // Repeated modifiers represent double taps in Raycast, not a chord.
            guard let flag = flags[part], modifiers & flag == 0 else { return nil }
            modifiers |= flag
        }
        return Self(source: .raycast, keyCode: keyCode, modifiers: modifiers)
    }

    /// CopySymbolicHotKeys returns Carbon modifiers, not CGEvent flags.
    public static func macOSSymbolicHotKey(keyCode: Int, carbonModifiers: UInt32, enabled: Bool) -> Self? {
        // cmdKey, shiftKey, optionKey, controlKey from Carbon Events.h.
        let supportedMask: UInt32 = 256 | 512 | 2048 | 4096
        guard enabled, (0...126).contains(keyCode),
              carbonModifiers & ~supportedMask == 0 else { return nil }
        let mapping: [(UInt32, UInt64)] = [
            (256, ShortcutBinding.command), (512, ShortcutBinding.shift),
            (2048, ShortcutBinding.option), (4096, ShortcutBinding.control),
        ]
        let modifiers = mapping.reduce(UInt64(0)) { result, pair in
            carbonModifiers & pair.0 == 0 ? result : result | pair.1
        }
        return Self(source: .macOS, keyCode: UInt16(keyCode), modifiers: modifiers)
    }
}
