# Cross-app insertion: Superwhisper, Wispr Flow, and Quibble

Retrieved: 2026-09-05. Directional after: 2026-10-05.

## Answer

The documented common approach is clipboard-based paste, with recovery when delivery cannot be confirmed. Reading the destination's text is a separate capability. Quibble should use one insertion service across applications, with capability-based verification and an explicit alternate typing mode. Notes should be one regression case in a broader compatibility matrix.

This document records the research and proposed design, followed by implementation evidence. Research alone does not establish compatibility.

## First-party evidence

All sources below were read on 2026-09-05. Statements concern desktop insertion unless otherwise specified.

| Finding | Source |
|---|---|
| Flow stages the transcript on the local clipboard and invokes Cmd+V on macOS. It explicitly describes the same paste approach across apps, without remote-client-specific handling. | [Flow: remote desktops](https://docs.wisprflow.ai/articles/7336156466-use-flow-with-remote-desktops-citrix-rdp-vdi) |
| Flow restores the previous clipboard after successful paste; on failure it leaves the transcript available for manual paste. It provides Copy Last Transcript and Paste Last Transcript. | [Flow: text not pasting](https://docs.wisprflow.ai/articles/7971211038-fix-text-not-pasting-after-dictation) |
| Flow documents fields that never report their contents back: it assumes insertion succeeded there and offers recovery if text is missing. The article covers several platforms and does not name the desktop fields or precise detection mechanism. | [Flow: field detection and insertion](https://docs.wisprflow.ai/articles/1621472516-flow-fails-to-detect-text-fields-or-inserts-incorrectly-on-non-qwerty-keyboard-layouts) |
| Superwhisper exposes automatic paste, clipboard restoration, and simulated individual keystrokes for destinations where paste is restricted. Its recording window can wait for paste confirmation or close regardless. | [Superwhisper: advanced settings](https://superwhisper.com/docs/get-started/settings-advanced) |
| Superwhisper 2.18.3 (September 3) made clipboard preservation the default and fixed redirected-paste behavior when confirmation was unavailable. This supersedes the advanced-settings page's older default description. Version 2.17.0 documents paste-confirmation fixes for Slack and Discord. | [Superwhisper: changelog](https://superwhisper.com/changelog) |

Neither company's public documentation establishes its exact macOS event API, Accessibility traversal, wait durations, or full success-detection algorithm. Those details remain unconfirmed; the proposed design below is our engineering decision, not a claim about private source code.

## Quibble's current problem

Source inspected on 2026-09-05: `App/TargetApplication.swift`, working tree without a Git revision. `capture()` requires one of three Accessibility roles, a readable full text value of at most 32,000 UTF-16 units, and a valid selection range. Consequently, a field can be rejected before paste is even attempted. The previously observed empty Notes editor had an AXTextArea role and a valid selection, but no AXValue. That satisfies the rejection condition independently of the ASR engine.

`insert()` also prefers the Accessibility selected-text setter over normal paste. Its clipboard fallback restores the previous clipboard after a fixed 500 ms, before checking whether delivery was confirmed. This is a potential timing weakness; a race has not yet been reproduced. The final success check requires an exact readable value, so inability to observe a paste is conflated with delivery uncertainty.

The current failure is therefore architectural. Changing a Notes bundle-ID rule would not address other editors with incomplete Accessibility data.

## Proposed shared insertion service

1. **Capture destination identity independently of readable text.** Track the foreground process, focused window and element when exposed. Store readable value and selection as optional verification data. Use available editability signals rather than a three-role whitelist. Missing text alone must not reject a destination. Known secure or non-editable controls remain excluded; missing focus metadata requires an explicit best-effort policy rather than pretending it identifies a field.
2. **Use normal paste as the default transport.** Snapshot clipboard representations, stage plain text, recheck focus and ownership, and issue one paste. Do not rewrite the editor's whole value. Keep the HUD nonactivating. Preserve Unicode, paragraphs, and selected-text replacement through the target editor's normal paste handling.
3. **Separate delivery from confirmation.** Represent outcomes as confirmed, sent-but-unconfirmed, and not-sent, rather than parsing human-readable status strings. Poll for confirmation when a reliable baseline is available. Lack of readback must not prevent the initial paste or trigger a second insertion.
4. **Manage clipboard lifetime deliberately.** Restore only while Quibble still owns the clipboard and after confirmation or a tested delivery grace period. For unconfirmed delivery, retain the transcript and offer recovery; preserve the previous clipboard snapshot until the transaction is resolved. Never overwrite something the user copied in the meantime. Exact timing is a measurement task, not a constant copied from competitor documentation.
5. **Provide explicit recovery.** Add Copy Last Transcript and a configurable Paste Last Transcript shortcut. Recovery captures the user's current destination. Do not silently retry an ambiguous attempt: the first paste may have succeeded and a retry would duplicate it.
6. **Add optional simulated typing.** Make it a user-selected transport for paste-blocked destinations, rather than automatically typing after a possibly successful paste. Validate keyboard layouts, Unicode, long text, and newline behavior before enabling it broadly.
7. **Handle focus changes consistently.** If the user changes destination while transcription is running, retain the transcript and let them explicitly paste it at the new cursor. Do not activate an old window or send text to an unrelated application unexpectedly.

These changes do not require sending surrounding text to an AI model. Application-aware rewriting remains paused. Correction learning can use readable fields when available and simply remain unavailable where edits cannot be observed.

## Validation plan

The matrix lists required coverage. Notes insertion was subsequently confirmed in build 6 (see evidence below); the broader cases remain pending. Prior transcription benchmarks and a successful test in one native app do not validate all destinations.

| Editor family | Representative destination | Cases |
|---|---|---|
| Native plain/rich text | TextEdit and Notes | Empty editor, insertion in the middle, selected replacement, multiline, undo |
| Electron | VS Code editor and a chat composer | Custom Accessibility roles, delayed readback, focus changes |
| Browser | Textarea and contenteditable in Safari/Chromium | Empty/nonempty text, rich editor normalization, Unicode |
| Terminal | Local terminal with a harmless input buffer | Paste delivery, no synthetic submission key, multiline handling |
| Restricted/remote | A paste-blocked fixture; remote client if available | Explicit alternate transport, no duplicate retry, recovery |

Automated regression cases should include missing AXValue, absent selection, nonstandard editor roles, changed focus, user clipboard changes during delivery, delayed acknowledgement, and ambiguous completion. A small controllable native fixture can expose these capabilities consistently; actual apps still require end-to-end checks.

Record destination family, transport, confirmation capability, outcome, and elapsed time without logging document contents. Remove the temporary Notes-specific diagnostic control once the generic test harness replaces it.

## Build 6 implementation evidence — 2026-09-05

- `App/TargetApplication.swift` now uses clipboard paste as its single default transport. Missing text, missing selection and custom editor roles no longer prevent capture. Available identity, text and selection still guard against a changed destination. Known secure, disabled and non-input controls are excluded. Editors exposing only a focused window receive best-effort handling.
- Confirmation is optional and represented separately from dispatch. A readable field is checked for up to one second after sending. Only confirmed changes restore the old clipboard; unavailable or ambiguous readback leaves the transcript for recovery, without issuing another insertion. The timing is our initial bounded implementation, not a competitor-derived guarantee.
- The global Control–Command–V shortcut explicitly pastes the retained transcript at the current destination. The service waits up to 750 ms for shortcut modifiers to be released before dispatch. The Notes-specific diagnostic action was removed.
- The regression test runs the actual capture function with the missing-value editor metadata that exposed the defect. It failed before the fix and passed afterward. The complete Swift suite then passed with 26 tests and zero failures (exit 0), including 18 insertion checks. Two use real isolated NSPasteboard instances to verify multiple-item/type restoration and preservation of a newer copy.
- The user confirmed “it works” after testing build 6 with normal dictation. A subsequent UI inspection showed “Inserted into Notes,” with 1.248 seconds of audio, 0.666 seconds release-to-result and 0.060 seconds for insertion. Other tested apps were not identified; the broader matrix remains pending. The updated UI also reported both existing permissions allowed.
- Native UI automation could edit a background window without changing the foreground app, so its attempted TextEdit diagnostic was not counted as successful live delivery.
- Optional simulated typing and configurable recovery bindings are still future work. The current patch addresses the observed shared paste failure; it does not claim universal compatibility or a paste-blocked-app fallback.

## Unconfirmed and open questions

| Question | Evidence gap / next step |
|---|---|
| Exact competitor event dispatch and clipboard timing | Official documentation describes behavior, not source code. Do not attribute a particular CGEvent or AppleScript implementation to either product. |
| Reliable handling when no focused element is exposed | Establish a conservative app/window-level fallback policy and test it with deliberately inaccessible editors. |
| Clipboard restoration when readback is unavailable | Measure slow consumers and decide the user-visible recovery policy; there is no universal receipt for a paste shortcut. |
| Typing-mode keyboard-layout coverage | Validate using actual input sources; a physical key-code assumption is insufficient. |
| Universal app compatibility | Not established. Competitors document restrictions and recovery paths; ship a tested matrix and explicit outcomes rather than promising every field will always accept synthetic input. |
