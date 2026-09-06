# Builds 30–31 — menu bar and microphone routing

Date: 2026-09-06. Delivered as build 31.

## Requested behavior

- A visible quotation-mark menu icon.
- Transcribe File…, History, Settings…, Microphone and Mode submenus, and Quit Quibble.
- Navigation opens the app's existing pages; it does not embed settings or history in the menu.
- Updater investigation only, low priority.

## Implementation

`MenuBarController` retains one native `NSStatusItem` with a square status-button slot and an 18-point template image. It uses the approved quotation mark, with a system-symbol fallback if the asset cannot load, and a microphone while recording. It explicitly inserts the item rather than relying on the prior custom, resizable SwiftUI `MenuBarExtra` label. The item remains owned outside the settings view's lifetime.

Navigation is shared with the existing main window. File import reuses the controller's guarded audio chooser and transcription pipeline; if setup is open, its dismissal completes before showing the chooser. The application delegate explicitly prevents termination when the last window closes.

The native menu is populated from current microphone and saved-mode data when opened. It marks current choices and guards changes while recording, processing, or inserting. Opening a page remains available while busy. Quit is the ordinary app-termination action.

Microphone routing uses a per-app device UID preference, System Default resolved at each utterance, and one audio stream shared by the recording and HUD spectrum, without changing the system input. Explicit unavailable selections fail instead of silently falling back to another device. An active capture is pinned to both its UID and current HAL device ID. Capture/disconnection/finalization errors stop the session visibly and preserve the partial temporary WAV for possible manual recovery until orderly exit; they never auto-insert a truncated utterance. See [microphone implementation and limits](MICROPHONE-INPUT-SELECTION-2026-09-06.md).

## Reproduction limits

The old build's `MenuBarExtra` still existed in source. Its custom template logo had compiled but had not been visually checked in the actual menu bar in build 29. In this turn, CUA exposed Quibble's main window but not its system status item; attempts to inspect SystemUIServer timed out, and menu-bar keyboard focus did not expose it. The user's missing-icon report is the behavioral evidence. The exact old failure mechanism remains unconfirmed; the native-menu contract probe is **not** an old-code reproduction of invisible status-bar pixels.

macOS can also omit menu items when the status area is crowded. An item being logically inserted is not proof that every display arrangement shows it. The user subsequently confirmed that the icon and menu work on build 30.

## Evidence

- `swift test --scratch-path .build/core-tests`: 173 tests, zero failures, exit 0.
- `python3 -m unittest discover -s Scripts -p 'test_*.py'`: one test, zero failures, exit 0.
- `Scripts/check-menu-bar.py`: isolated native menu with the real branding PNG and fixture controllers; retained item, template/size, exact requested menu, checkmarks, selectors, busy guards, unavailable-device row, and consume-once navigation passed. It does not test the live SwiftUI window lifecycle or actual microphone hardware.
- Focused microphone probes: both exited 0 when rerun by the main agent. Actual background C callback, shared-PCM spectrum/meters, final partial buffer, finalized WAV metadata, interruption errors, UID persistence/default following, missing/reconnected device state; native read-only enumeration found two inputs.
- Signed Xcode builds 30 and 31 succeeded, exit 0. Existing Keychain deprecation/AppIntents metadata warnings remain. Both passed strict signature checks and the preceding installed build's designated requirement. The complete bundle was installed at the existing Release path after fresh idle checks and UI quits; installed `CFBundleVersion` is 31. No TCC reset or signing identity change.
- Native UI: actual menu tree exposed Transcribe File…, History, Settings…, the two microphone choices plus System Default, the two saved modes, and Quit. The user confirmed “Icon and menu work” on build 30. A brief built-in/default-route capture started, stopped, and produced a transcript; this was not a controlled no-speech or transcript-accuracy test.
- Closing build 30's main window left its same process running (`pgrep`); subsequent CUA activation reopened the window with its transcript retained. The isolated SwiftUI lifecycle probe also demonstrated the sole-Window baseline terminating, while the delegate override survived with zero windows and a saved `openWindow` action reopened exactly one. The main agent reran the corrected probe, exit 0, and read its fresh log. [Apple Window lifecycle](https://developer.apple.com/documentation/swiftui/window), [last-window delegate behavior](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)).
- Native submenu validation exposed a real follow-up defect: NSMenu automatically re-enabled child selectors when opened. Adding `submenu.update()` to the probe failed at the busy-disabled assertion, exit 1/SIGTRAP. Setting `autoenablesItems = false` on both submenus made the same probe pass, exit 0; action-level busy guards already prevented mutation. This small adjustment is build 31, which was reopened and inspected in its idle Home state.

## Remaining coverage

The live microphone check covers the default input on this Mac. USB/Bluetooth/Continuity input conversion, physical unplug/reconnect, final-word-at-release acoustic timing, and older OS/hardware still need coverage. The injected tests are not physical device tests. The guide-dismissal-to-file-chooser route was reviewed and shares the existing importer; that exact live interaction was not exercised. The user confirmed menu navigation; the integrated close-and-reopen check used app activation, not a separately observed menu click after closure. No updater was installed or tested.

## Updater

See [updater prerequisites](UPDATER-PLAN-2026-09-06.md). Sparkle is the proposed future update engine. No updater dependency, feed, signing key, network publication, or automatic update was added.
