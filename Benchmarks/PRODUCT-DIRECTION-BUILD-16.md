# Quibble: a simpler app and an optional assistant

Date: 2026-09-06 · Signed local build: 16

## Product decision

Keep fast dictation as the dependable everyday path. Add an explicitly invoked **Ask** experience for drafting, rewriting selected text, answering questions, and eventually taking actions. Local ASR is a useful option; it does not need to constrain every other capability.

The [assistant feasibility report](ASSISTANT-FEASIBILITY-2026-09-06.md) contains dated official sources, provider contracts, cost examples, account options, privacy details, and proposed evaluation criteria. It recommends Responses for the initial bounded draft experiment. Codex app-server is a viable, broader integration to evaluate if Quibble should become a full agent client. Documentation establishes feasibility; usefulness, network latency, energy, and user preference still require actual trials.

GPT assistance and external ASR have **not** been connected in build 16. The app still transcribes locally, and nearby-text refinement remains paused. No background listening or cloud fallback was added.

## Implemented in this build

| Area | Result |
|---|---|
| Models | Compact rows with publisher icons, relative HF Accuracy segments, measured local speed when available, local size, selection/download action, and a menu. Search, sort, and Speech / Writing / Downloaded segments keep the main choices bounded. |
| Writing models | S1 appears as the ordinary polish choice. Additional local instruction models sit inside a collapsed section. Existing custom modes remain intact. Adding and enabling a writing step are labeled explicitly; re-enabling a saved step preserves its prompt. |
| Model storage | Each stored model has a recoverable Move to Trash action. Confirmation names modes and shared vocabulary helpers that depend on it. Inference unloads before removal; processing/download guards prevent conflicting actions. No automatic removal of user downloads. |
| HUD | Studio gives time, detail, and labeled Finish/Cancel controls. Glass keeps detail and compact controls in a translucent strip. Compact is a small passive indicator. Phases with no controls pass clicks through. The panels remain nonactivating. |
| Sounds | New original Soft cues and the previous Original set are selectable and previewable. Soft becomes the default when no preference exists. These are newly synthesized tones; similarity to Superwhisper Classic has not been established. |
| Surfaces and color | Main content and primary cards use 26-point continuous corners. Sidebar icons have restrained backgrounds: slate for speech, sage for vocabulary, lavender for modes, neutral for utilities. The native selection accent follows macOS. Smaller controls retain proportionate radii. A future OS name/radius has not been treated as a verified specification. |
| Speaking pace | Home shows estimated words per minute after ten measured seconds. It uses original ASR words and total recorded duration, including pauses. Cleanup/manual edits, imported files, and old records lacking duration cannot inflate the estimate. Statistics follow retained history and are cached on history changes. |

The WPM card intentionally does not claim time saved or a multiplier over typing. A useful follow-up would be an optional personal typing baseline, with the comparison labeled as an estimate. No population-average typing speed has been silently assigned to the user.

## Resource impact

This pass adds no inference stage, idle network polling, continuous window capture, or always-on microphone. Existing two-minute idle unloading remains. The sound assets total about 96 KB and are loaded only on cue playback. WPM is derived when history changes, rather than during audio-meter updates. Glass has compositor cost that has not been profiled; Studio and Compact provide opaque alternatives.

Downloaded size and working memory are separate. Moving an unused model to Trash makes it recoverable, so disk space is not necessarily reclaimed until the user empties Trash. The app does not empty it. No extra models need to be downloaded merely to view the library.

## Next implementation steps

1. **Reliability foundation alongside provider work.** Fix the existing S1 completion-limit guard and durable workflow-save reporting; add private crash-audio cleanup, trusted model integrity checks, and a distribution-safe model path. These remain findings in the [production review](PRODUCTION-REVIEW-2026-09-06.md), not completed fixes in this visual pass.
2. **One connected ASR provider.** Add explicit account/key setup, Keychain storage, concrete capability metadata, cancellation, visible usage, and error recovery. Benchmark native vocabulary hints against the current guarded workflow. Keep cloud fallback an explicit preference. Add a second provider after the first contract and behavior are verified.
3. **An Ask draft prototype.** Dedicated shortcut, local or selected cloud ASR, deliberately attached selected text or one requested window capture, one Responses request, and an editable result with Insert/Copy/Discard. The spoken instruction and background context stay structurally separate. Do not auto-insert partial streams or infer an unknown recipient address.
4. **Measure whether it helps.** Use email drafts, replies, rewrites, and questions. Compare review/edit time, preserved names and numbers, unsupported additions, latency, cost, and device load. Add a short personal trial before a broader pilot. One cloud text provider can serve both polish and custom instructions when the results justify replacing the local distinction.
5. **Expand deliberately.** Read-only restaurant research with sources, then account-backed drafts and separately reviewed actions. Consider a wake word or Realtime after repeated use demonstrates the need. The user's “timestamps” idea still needs a precise meaning before implementation.

Public distribution also needs signing/notarization, update and permission-retention testing on a second Mac, dependency notices, a controlled cross-app/device matrix, accessibility review, and version control/CI. Build 16 is a usability improvement, not a declaration that those release gates are closed.

## Verification

- Final Release `xcodebuild`: exit 0, `BUILD SUCCEEDED`; `.build/build16.log`. The only reported warning is skipped AppIntents metadata extraction because the app has no AppIntents dependency.
- Strict/deep code-signature verification: exit 0. Bundle version is 16; the bundle ID and signing team remain unchanged.
- Final Swift suite: 74 tests, 0 failures, exit 0; `.build/build16-tests-final.log`. Duration migration and weighted pace were observed failing before their implementations, then passing. Tests also cover insufficient/invalid samples and history restoration/edit/removal/undo behavior.
- Python benchmark metric test: 1 test, exit 0.
- Live review: Superwhisper's actual compact Models table was inspected. Quibble's final Home, Speech and Writing layouts were inspected at the current 850-point window width in dark appearance. The removal confirmation and Cancel path were exercised, including shared S1 dependencies; no real model was removed during QA.
- All three full-size HUD previews were inspected in the running final build. Studio/Glass preview controls are disabled; Compact exposes no buttons. Studio was restored after the comparison; Soft remained selected. The user authorized the final relaunch after keeping their session text.
- Limits: actual new HUD-button clicks during live dictation, native cross-app click-through, light appearance/VoiceOver/multi-display coverage, perceived sound quality, and real removal/restoration of model folders have not been end-to-end tested in this pass. Previous global shortcut/insertion confirmation is prior evidence, not a substitute for those checks.
