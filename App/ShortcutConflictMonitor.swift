import AppKit
import Carbon.HIToolbox
import QuibbleCore

/// Reads known configured shortcuts. It never registers a competing hotkey or event tap.
/// Refresh on settings activation/editor presentation and before saving, never per key event.
@MainActor
final class ShortcutConflictMonitor {
    enum RaycastStatus: Equatable, Sendable {
        case notInstalled
        case unavailable
        case checked
    }

    struct Snapshot: Equatable, Sendable {
        var knownBindings: [KnownShortcutConflict] = []
        var systemCheckAvailable = false
        var raycastStatus: RaycastStatus = .unavailable
        var checkedAt: Date?

        func conflicts(with binding: ShortcutBinding) -> [KnownShortcutConflict] {
            // macOS can return several enabled entries for the same combination.
            var sources: Set<KnownShortcutConflict.Source> = []
            return knownBindings.filter { $0.matches(binding) && sources.insert($0.source).inserted }
        }
    }

    private(set) var snapshot = Snapshot()

    @discardableResult
    func refresh() -> Snapshot {
        let system = readSystemShortcuts()
        let raycast = readRaycastLauncher()
        snapshot = Snapshot(
            knownBindings: system.bindings + (raycast.binding.map { [$0] } ?? []),
            systemCheckAvailable: system.available,
            raycastStatus: raycast.status,
            checkedAt: Date()
        )
        return snapshot
    }

    private func readSystemShortcuts() -> (available: Bool, bindings: [KnownShortcutConflict]) {
        // Apple's API is not thread safe and only covers Keyboard Shortcuts in System Settings.
        // It does not expose names, application menus, or other processes' event-tap bindings.
        var unmanaged: Unmanaged<CFArray>?
        let status = CopySymbolicHotKeys(&unmanaged)
        guard status == noErr else {
            unmanaged?.release()
            return (false, [])
        }
        guard let rows = unmanaged?.takeRetainedValue() as? [[String: Any]] else { return (false, []) }
        let bindings = rows.compactMap { row -> KnownShortcutConflict? in
            guard let keyCode = row[kHISymbolicHotKeyCode as String] as? NSNumber,
                  let modifiers = row[kHISymbolicHotKeyModifiers as String] as? NSNumber,
                  let enabled = row[kHISymbolicHotKeyEnabled as String] as? Bool else { return nil }
            return .macOSSymbolicHotKey(
                keyCode: keyCode.intValue, carbonModifiers: modifiers.uint32Value, enabled: enabled
            )
        }
        return (true, bindings)
    }

    private func readRaycastLauncher() -> (status: RaycastStatus, binding: KnownShortcutConflict?) {
        let bundleID = "com.raycast.macos"
        let appURL = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        guard let appURL else { return (.notInstalled, nil) }
        guard let version = Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              version.split(separator: ".").first == "1" else {
            // Raycast 2 moved its launcher setting into a private encrypted store.
            // Do not read/decrypt that store or use potentially stale migrated v1 preferences.
            return (.unavailable, nil)
        }
        // Best effort for legacy releases: one explicit key, no domain export or fallback default.
        guard let value = CFPreferencesCopyValue(
            "raycastGlobalHotkey" as CFString, bundleID as CFString,
            kCFPreferencesCurrentUser, kCFPreferencesAnyHost
        ) as? String,
              let binding = KnownShortcutConflict.raycastLegacyPreference(value) else {
            return (.unavailable, nil)
        }
        return (.checked, binding)
    }
}
