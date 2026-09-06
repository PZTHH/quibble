# Quibble build 9: daily-use interface and transcript recovery

Date: 2026-09-05. Build: 9. Native macOS SwiftUI application.

## Delivered behavior

- Home shows readiness, the actual selected writing mode, Option–Space instructions, recording/import actions, an editable latest result, and recent dictations.
- Navigation groups Home/History, personalization, and application configuration. The menu bar can reopen Quibble.
- History searches both original and final text plus the source application. Entries show time, mode, delivery state, review/copy actions, and removal with one-step undo. Delivery labels distinguish confirmed insertion, paste sent, and a result ready to paste.
- Original text is available through a disclosure in the review sheet. Editing the current Home transcript also updates its history entry and uses the existing correction-learning path.
- History remains in memory by default. Opt-in storage is local text only, at most 100 entries/seven days, with a one-million UTF-16-unit total string budget to keep encoded JSON within the 8 MB read limit. Expiry runs on load, new entries, History opening, and app foreground refresh. There is no new periodic timer. Turning persistence off deletes its file while retaining the current session.
- Stored archives use a versioned envelope, atomic writes, restrictive file/directory permissions, and an error state that preserves unreadable existing files. Save errors leave current-session text available.
- The two supported writing modes have short explanations and illustrative examples. No unsupported tone/context modes were added.
- Vocabulary emphasizes preferred-word entry and an actual recording test. Exact-rule testing and technical explanation are collapsed; inactive legacy rules no longer look like a failed saved word.
- The floating HUD adds a second line, a Finish recording control, and reduced-motion handling for its input meter. It remains a nonactivating panel. Existing sound files and global insertion behavior are unchanged.

## Research used

The user opened **Superwhisper 2.18.3**. Its live mode editor, vocabulary, configuration, and model library were inspected. Compact summary rows, grouped controls, and progressive disclosure informed this slice. See [research with source links and live observations](DICTATION-UX-RESEARCH.md).

**Wispr Flow 1.6.774** was installed from its official vendor endpoint and signature/notarization checked. Only onboarding was inspected. Its main Hub was blocked by a sign-in problem; the user explicitly asked to continue without Flow. Website illustrations are not treated as measurements of its main desktop UI.

## Verification

| Check | Evidence |
|---|---|
| Core suite | Fresh `swift test --scratch-path .build/core-tests`, exit 0; **57 tests, 0 failures**. Log: `.build/ux-history-tests.log`. |
| Release build | Fresh `xcodebuild` Release with the installed Metal toolchain, exit 0, BUILD SUCCEEDED. Log: `.build/ux-verified-build-9.log`. |
| Signature | `codesign --verify --deep --strict`, exit 0. Stable `com.pezhvak.quibble` designated requirement and existing Apple Development identity retained. |
| History regression | Reproduced an allowed set of long escaped transcripts creating a 9,220,040-byte archive that the old 8 MB read guard rejected. Added a total-string bound; the same test now saves and reloads all retained entries. Red log: `.build/ux-history-size-red.log`. |
| Storage tests | Session-only writes no archive; opt-in restores original/final text; opt-out removes the saved copy; expiry/count bounds; removal/undo; unreadable archives preserved; total-size round trip. Tests use isolated temporary directories/defaults. |
| Actual inference → UI | Imported synthetic `.build/name-audio/vocabulary.aiff` through the native file picker. Raw `Please open Super Whisper.` became `Please open Superwhisper.` and appeared in Home and History. The current app selection reported Cohere FP16 with Basic cleanup; model preferences were not changed. This is a smoke test, not a new quality benchmark. |
| Actual History workflow | Command–F focused search; searching `super whisper` matched the original text; review exposed raw/final; copied final text was pasted back into search to verify clipboard content; removal showed Undo; Undo restored the entry. |
| Visual QA | Empty/populated Home, History, transcript review, mode cards, Vocabulary, and Settings inspected in the native app at 1040 px and 850 px widths. Final vocabulary disclosure verified after rebuilding. |
| Mode controls | Switched to Minimal dictation and observed selection, then restored Basic cleanup. |
| Session privacy | After closing/relaunching the session-only app, Home/history no longer showed the synthetic entry. Local retention was not enabled in the user's profile. |
| HUD | Success preview inspected directly after closing the main window: readable two-line capsule and completion icon. Live microphone finish/cancel behavior, all HUD states, multi-display/full-screen behavior, and light-mode/VoiceOver QA remain to be checked. |
| Permissions | The running preview still showed Microphone and Accessibility Allowed. This is not a new end-to-end update-retention microphone/insertion test. |

## Device load and limits

This slice adds no models, inference passes, network calls, or background polling. History is bounded text, not retained audio; writes are event-driven and existing edit observation is debounced. The existing two-minute model idle unload remains. No new RSS/energy measurement was performed, so this report does not claim a measured memory reduction.

History currently records successful nonempty transcription results, including delivery failures. It does not retain failed recognition attempts, replay audio, or reprocess old audio. Undo is one entry and session-local. Surrounding-text rewriting remains paused; voice commands remain later scope.

The next useful slice is guided setup and model management: clearer speech/refinement roles, honest download/current-memory labels, microphone and shortcut configuration, and reliable download/repair recovery. Broader app compatibility, distribution signing, and updater validation remain separate release gates.
