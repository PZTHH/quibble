# Phase 1 evidence and remaining checks

> Vocabulary status, 2026-09-05: the visual editor and explicit correction rules are implemented, but preferred-word-only recognition of uncommon names did not meet the user’s quality requirement. The universal vocabulary milestone remains open. The CPU measurements below describe the first implementation, not acceptance of that milestone. See [current evaluation](../../Benchmarks/VOCABULARY-QUALITY-EVALUATION.md).

Started 2026-09-05. This report records implementation and verification separately. The feature roadmap is in [original research plan](../Planning/RESEARCH-PLAN.md).

## Environment

- Apple M5 Max, 48 GiB memory, arm64.
- Xcode 26.6 (17F113); commands explicitly use `/Applications/Xcode.app/Contents/Developer` because the system default points to Command Line Tools.
- Existing Apple Development certificate, team `CU2YB94J43`.
- Stable application identifier: `com.pezhvak.quibble`.
- Directly built development app; this is not a notarized public release.

## Implemented prototype

- SwiftUI macOS app with dictation, permissions, local model selection and timing views.
- Hold Option–Space to record; release to finish; Escape cancels while the shortcut is held.
- Microphone recording and local audio import, capped at 60 seconds.
- Local Cohere and Parakeet adapters plus optional S1-mini cleanup. Model files are downloaded separately and pinned in `Models.lock.json`.
- Build 3 defaults to quantized Cohere 4-bit, with FP16 available in the model picker. The paired synthetic comparison reduced peak MLX memory from 6.5–6.8 GB to 3.0–3.7 GB and matched all transcripts; see `Benchmarks/QUANTIZATION.md` for limits and timings.
- Exact mode skips refinement. Cleanup failure preserves raw output with a visible explanation.
- Build 6 uses clipboard paste for all destinations. Text/selection readback is optional; available destination identity and baseline data are checked before sending. Uncertain delivery is distinct from confirmed insertion, with no automatic retry.
- Clipboard change-count protection, restore after confirmation, and Control–Command–V recovery at the current cursor. No synthetic submit key.
- Temporary microphone audio removal on normal completion, cancellation and app termination.
- CLI benchmark path uses the same inference actor as the GUI. Reports distinguish loading, ASR, refinement and total file processing.
- A signed-build identity comparison script; it does not modify permission databases.

## Verification ledger

| Check | Evidence / status |
|---|---|
| Cancelled inference cannot replace a new session | Swift test observed failing, then passing after guard added. |
| Repeated press does not replace active recording | Swift test observed failing, then passing after guard added. |
| Dropped negation is counted as a word error | Python test observed failing, then passing after edit-distance implementation. |
| Project and entitlements syntax | `plutil -lint` passed. |
| macOS integration Swift 6 type checking | Callback isolation and clipboard type errors reproduced and fixed; platform files type-check with exit 0. |
| Inference package compilation | `swift build --package-path Inference --target QuibbleInference -j 8` passed. This does not validate runtime shader loading. |
| Full signed app build | Builds 1 and 2 passed with exit 0; signatures verify. The downloaded Metal compiler is selected through the user toolchain override documented in [Metal toolchain setup](../Setup/METAL-TOOLCHAIN.md). |
| Local model downloads | Completed for Cohere, Parakeet and S1-mini, with local integrity receipts. |
| Synthetic speech fixtures | Generated using local Samantha voice; valid AIFF audio confirmed. |
| Live inference and offline benchmark | 24 successful network-denied runs across both engines, plus exact/silence/length-limit/missing-cleanup checks. See `Benchmarks/FINDINGS.md`. |
| UI visual inspection | Dictation and model pages inspected; GUI audio import produced the expected transcript. |
| Permission continuity across signed builds | Build 2 satisfies build 1's requirement. Both grants remained allowed after same-location replacement; recording and event-tap startup worked without a new grant. |
| Real microphone, shortcut and insertion | User's physical Option–Space dictation inserted the pangram into TextEdit. Recording/cancellation and TextEdit Undo/Redo verified. One warm release-to-result observation was 0.277 s, plus a 0.004 s insertion attempt. |
| Build 6 missing-value regression | Actual capture function rejected an AXTextArea fixture with missing AXValue before the fix; the same test passed after the shared capture/paste refactor. |
| Build 6 transaction checks | `swift test --scratch-path .build/core-tests`: 26 tests, 0 failures, exit 0. Includes 18 insertion checks: opaque editors, Unicode/multiline payloads, delayed acknowledgement, focus changes, modifier release, no duplicate retry, and real isolated pasteboard preservation. |
| Build 6 live result | User answered “it works” after trying normal dictation. The app subsequently displayed “Inserted into Notes”: 1.248 s audio, 0.666 s release-to-result, 0.060 s insertion. Other tested app names and exact field scenarios were not supplied. |
| Build 6 permissions | Updated signed app reports Microphone and Accessibility allowed, with its global shortcut enabled. No permission reset or new grant performed. |
| Build 7 vocabulary and device load | Shared CPU vocabulary across four ASR routes, visual editor, explicit corrections, suggestions, import/export and undo. 39 Swift tests; 66 CPU cases; 24 cross-model positive/negative audio runs; six unchanged baseline runs. See `Benchmarks/VOCABULARY-AND-RESOURCE-USE.md`. |
| Preferred-word quality evaluation, 2026-09-05 | User-reported name-quality gap remains open. Evaluated S1 prefixes, local resolvers, and 338 native Cohere/Parakeet bias runs; experimental hooks restored. 44 tests pass, signed Release build verified and reopened. See `Benchmarks/VOCABULARY-QUALITY-EVALUATION.md`. |

## Compatibility matrix

The status column separates observed behavior from proposed checks. Pending scenarios are not compatibility claims.

| Target / scenario | Required observation | Status |
|---|---|---|
| TextEdit | Insert at caret; replace selection; undo | Caret insertion and Undo/Redo observed; selection replacement pending |
| Notes | Receive normal global dictation | Build 6 reports confirmed insertion following the user's successful live test; broader selection/undo cases pending |
| Apple Mail compose | Insert without sending; preserve existing text | Pending |
| Chat compose | Insert without submitting message | Pending |
| Browser textarea / contenteditable | Selection, focus and paste behavior | Pending |
| Code editor | Preserve literal text; no command execution | Pending |
| Focus changes during inference | Keep result for copy; no wrong-field insertion | Pending |
| Secure/password field | No capture or automatic insertion | Pending |
| Permission denied or revoked | Show actual state, retain manual import/copy | Pending |
| Clipboard modified during insertion | Do not restore over a newer copy | Pending |
| Signed update in the same location | No additional microphone/Accessibility grant required | Observed for development builds 1 → 2 on this Mac |

## Deliberate phase boundaries

This is an English prototype. Editable vocabulary and repeated-correction suggestions are implemented. Qwen3 ASR accepts preferred terms during recognition; all speech models now also use shared CPU corrections. Ambiguous phrases need an approved correction rule. Context-aware rewriting and custom instructions are paused after user-reported unwanted copying of surrounding text. History persistence, a production updater and voice commands remain later work. S1-mini uses its fixed supported cleanup prompt; it is not presented as a general instruction model.

Synthetic speech can reveal integration problems and gross changes of meaning. It cannot establish accuracy on a person's accent, microphone, quiet speech or background noise. A baseline with less RAM and a slower chip also remains untested.
