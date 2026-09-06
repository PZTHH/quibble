# Read-only shortcut conflict checks

Reviewed 2026-09-06 for build 27. This is a bounded check of known configured bindings, not a universal global-shortcut ownership detector.

## Implementation and integration

- `App/ShortcutConflictMonitor.swift` exposes `ShortcutConflictMonitor.Snapshot`. Call `refresh()` on the main actor when settings become active, when opening the shortcut editor, and before saving a candidate. Do not poll per key event. The monitor installs no event tap or hotkey and changes no preferences.
- `snapshot.conflicts(with:)` returns exact keycode/modifier matches, deduplicated by source. Existing user bindings are not changed by the detector. `systemCheckAvailable` and `raycastStatus` describe coverage separately from conflicts; an unavailable check is non-blocking.
- `Sources/QuibbleCore/KnownShortcutConflict.swift` normalizes supported Carbon modifier flags and legacy Raycast physical-key strings. Unknown bits, unknown formats, double taps, and modifier-only Raycast shortcuts are not stripped into ordinary chords.

## Coverage and primary evidence

| Source | What can be checked | Limits and evidence |
| --- | --- | --- |
| macOS Keyboard Shortcuts | Enabled system-wide symbolic hotkeys returned by `CopySymbolicHotKeys`, with Carbon modifiers converted to the four CGEvent modifiers used by Quibble. | Apple's Xcode 26.6 SDK `HIToolbox.framework/Headers/CarbonEvents.h`, lines 15555–15601, documents the read-only array, lack of shortcut names, exclusion of application-specific command keys, and non-thread-safe behavior. `Events.h`, lines 110–127, defines the Carbon flags. |
| Legacy Raycast 1 main launcher | Best-effort read of the single `raycastGlobalHotkey` preference; only a recognized physical-key chord produces a known binding. The installed major version must be 1. | Raycast's own 2.2.0.0 packaged migration code recognizes the legacy `Command-49` / `Option-49` format and distinguishes repeated-modifier double taps. This confirms the format, not universal availability of that old preference; it was not verified against a running v1 installation. No default is substituted for a missing key. |
| Raycast 2 main launcher | Unavailable through this detector. | The inspected official 2.2.0.0 package reads `general_settings.global_hotkey` from a private settings database. A single-column, read-only query on this Mac returned `SQLITE_NOTADB`, consistent with an encrypted/unsupported store. No keys, unrelated rows, exports, or decryption were accessed. The shipping detector does not open that database and does not reuse potentially stale v1 settings. |
| Other app shortcuts | Not enumerated. | Apple's [CGEventTapInformation](https://developer.apple.com/documentation/coregraphics/cgeventtapinformation) reports event masks, process IDs, enablement, and latency—not individual key combinations or a global ownership map. The inspected `CoreGraphics.framework/Headers/CGEventTypes.h`, lines 462–474, confirms those fields. No competing hotkey registration, focus-change heuristic, or simulated shortcut probe is used. |

Raycast allows the launcher hotkey to be customized in **Settings → General → Raycast Hotkey**; having Raycast installed is not evidence of an Option–Space conflict. Its individual command hotkeys can also be global, and the current app supports physical keys, key equivalents, modifier-only bindings, and double taps. The legacy launcher check does not cover those command bindings. [Raycast Settings](https://manual.raycast.com/settings), [Raycast Command Aliases & Hotkeys](https://manual.raycast.com/command-aliases-and-hotkeys) (retrieved 2026-09-06).

The preference reader uses Apple's single-key [CFPreferencesCopyValue](https://developer.apple.com/documentation/corefoundation/cfpreferencescopyvalue(_:_:_:_:)) API, not a domain export. No first-party general-settings deep link was verified in this pass; link to the Raycast settings help page or show the app name rather than inventing a URL.

## Verification

`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path .build/shortcut-conflict-tests --filter KnownShortcutConflictTests` passed five tests, exit 0, on 2026-09-06. The parser and Carbon-conversion cases were first observed failing on nil stubs, then passed after implementation.

Fixtures cover Command–Space versus Option–Space, true Option–Space and multimodifier matches, Carbon modifier conversion, disabled and invalid system entries, and malformed/double-tap/modifier-only/Fn legacy formats. This targeted suite does not compile the App monitor or prove physical key delivery. The integration owner performs the signed build and native flow checks separately.
