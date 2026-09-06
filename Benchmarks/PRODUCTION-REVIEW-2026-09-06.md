# Production review and implementation plan — 2026-09-06

Scope: first-party App, QuibbleCore, inference adapters, tests, build scripts, catalog, package configuration and release documentation. Third-party dependency internals are outside this audit. This is a code and local validation review, not a claim of production certification.

## Current implementation pass

- [x] Capability badges with semantic colors and explicit supported/unsupported details based on the actual adapters.
- [x] Separate speech and text processing in the model library; improve sidebar and Settings grouping.
- [x] Solid, translucent and compact HUD options with local previews, reduced-transparency fallback and consistent status cues.
- [x] Editable dictation and paste-last shortcuts, persistent settings, collision validation and correct modifier/repeat/release handling.
- [x] Earlier press acknowledgement, clear release state, no transcript insertion from HUD previews.
- [x] Signed Release build, core tests, app verification and prioritized production findings.

## Review findings

The findings below are open release gates. Code-based findings describe reachable behavior; destructive crash/disk-full/corruption scenarios were not injected into the user’s working data.

### Release blockers — fix before a public beta

1. **P1 — A truncated cleanup response can be accepted as complete.** `LocalInference.normalize` collects `.chunk` output but never checks the generation `.info` stop reason, whereas `refineContext` does. Its output cap is roughly 1.3 times the input tokens plus 32. If the cap is reached, a nonempty partial answer can pass the workflow's usable-output check and reach insertion. [Evidence](../Inference/Sources/QuibbleInference/LocalInference.swift#L353). **Next:** require a normal completion signal, retain the input otherwise, and run a forced-token-cap integration test. This pass has not changed inference semantics.

2. **P1 — “Downloaded” does not establish model integrity.** `ModelLibrary.refresh` accepts any nonempty required files. Downloads check HTTP/content length and optional catalog sizes, but there is no trusted expected digest in the app's manifest and existing installs are not revalidated. Same-length corruption remains accepted. The CLI's locally generated receipt detects subsequent changes, but is not an upstream trust anchor. [App checks](../App/ModelLibrary.swift#L34), [CLI downloader](../Scripts/download-models.py#L15). **Next:** ship pinned expected hashes, verify staging before promotion, record verified receipts, expose Repair, and test truncation and same-size corruption in an isolated model directory.

3. **P1 — Clean installation still depends on the developer checkout.** The bundled plist supplies `$(SRCROOT)/Models`, overriding the controller's Application Support fallback. A copied app on another Mac starts with a developer-specific path. [Configuration](../Config/Info.plist#L5), [initialization](../App/DictationController.swift#L125). **Next:** remove this override from distribution, preserve existing explicit user paths, offer a migration rather than moving model files silently, and test with an empty user account.

4. **P1 — No distribution/update pipeline.** Current signing is Apple Development, version 0.1.0. The source tree has no release archive/export/notarization/stapling pipeline, signed updater or rollback procedure. The update-identity script appropriately says designated-requirement compatibility does not prove permission retention. [Signing](../Config/Signing.xcconfig#L5), [identity checker](../Scripts/check-update-identity.py#L20). **Next:** prepare a separate distribution configuration, dependency/model notices and a same-location signed-update test with real grants on a second Mac. Do not promise updates will never require permission recovery.

5. **P1 — Crash recovery does not sweep abandoned microphone files.** A recording is written to a UUID-named temporary WAV. Normal completion, cancel and orderly quit delete it; startup does not identify leftovers from a crash or forced quit. [Creation](../App/DictationController.swift#L264), [cleanup](../App/DictationController.swift#L335). **Next:** use an app-owned private temporary directory, age-bound startup cleanup limited to files it owns, and test forced termination in a disposable account. Imported user audio must never be swept.

6. **P1 — Vocabulary loading is less defensive than history loading.** `VocabularyStore.init` decodes the entire local file without a size cap or archive-entry validation. History has explicit read and retention bounds. Vocabulary writes do not set the explicit private permissions used by history, and the dismissed-suggestions set has no cap. [Vocabulary store](../App/VocabularyStore.swift#L27), [learning](../Sources/QuibbleCore/Vocabulary.swift#L72), [history](../Sources/QuibbleCore/TranscriptHistory.swift#L39). **Next:** bound reads and learning data, validate schema/entries while preserving legacy conflicts for repair, apply consistent file permissions, and add malformed/oversized storage tests. Preserve unreadable originals.

### Reliability and quality gaps — close during beta preparation

7. **P1 — Synchronous recognition cannot stop promptly mid-decode.** The orchestrator checks cancellation around primary ASR calls. The vendored Whisper token loop has no cancellation check, so Cancel suppresses delivery but may leave compute running until the decoder returns. [Orchestration](../Inference/Sources/QuibbleInference/LocalInference.swift#L190), [decode loop](../Inference/Sources/QuibbleWhisper/WhisperModel.swift#L245). **Next:** propagate cooperative cancellation through adapters and measure time-to-idle and memory release for each engine. Keep the existing no-overlapping-inference guard.

8. **P1 — End-to-end failure coverage is not yet a release gate.** Core tests cover insertion transactions, workflow validation, vocabulary guards, persistence and now shortcut state. They do not establish live behavior across Notes, Electron, browser contenteditable, terminals, secure input, sleep/wake, device unplug, or revoked permissions. No automated UI suite or CI workflow is present. [Tests](../Tests), [sleep/permission handling](../App/DictationController.swift#L145). **Next:** make a repeatable native/Electron/browser matrix and fault scenarios, then run on a smaller-memory Apple Silicon Mac and the oldest supported macOS. Secure fields must remain excluded; ambiguous paste must not be retried automatically.

9. **P2 — App inspection can still delay microphone readiness.** Build 15 acknowledges the press before setup, but target capture and recorder initialization remain synchronous on the main actor. AX calls have no explicit short timeout, and permission refresh also prunes history. [Start path](../App/DictationController.swift#L249), [target capture](../App/TargetApplication.swift#L27). **Next:** measure press-to-HUD and press-to-first-audio separately; bound AX latency and separate target identity from expensive readback. Test an unresponsive editor and fast taps. The new acknowledgement is not a measured latency guarantee.

10. **P2 — Download recovery and capacity handling are incomplete.** A partial destination folder requires the user to move it manually; downloads do not resume through the UI, preflight free space, or recover old staging folders after a crash. Each progress delegate callback queues a main-actor update without throttling. [Download lifecycle](../App/ModelLibrary.swift#L47). **Next:** explicit queued/downloading/verifying/failed states, resumable staging and Repair, bounded UI progress updates, disk-full/interrupted-download tests. Do not overwrite arbitrary user model folders.

11. **P2 — Model quality and speed claims need a controlled local corpus.** HF scores are upstream references, and the segmented Accuracy meter is ordinal rank, not percent correct. Local speed samples use different recordings. Vocabulary prompting accepts words in list order and stops at the first term that exceeds the prompt budget, making later entries less likely to be considered. [Benchmarks](HF-ASR-BENCHMARKS.md), [prompt budget](../Inference/Sources/QuibbleWhisper/WhisperModel.swift#L18). **Next:** matched real-microphone positive/negative vocabulary cases, accents/noise and repeated names; report false corrections, omissions, p50/p95 latency and resident memory for exact local variants. Evaluate prioritization without broadening substitutions. Do not equate constrained edits with semantic certainty.

12. **P2 — Audio and memory lifecycle handling is basic.** The default recorder has no input-device chooser, route-loss/delegate recovery or calibrated voice activity detection. There is a 60-second cap and a digital-silence threshold. Models unload after two idle minutes, but no memory-pressure response or supported-hardware gate is implemented. [Recorder](../App/DictationController.swift#L266), [audio validation](../Inference/Sources/QuibbleInference/LocalInference.swift#L173). **Next:** device interruption/error handling, clear duration feedback, memory-pressure policy, measured cold/warm behavior and minimum-device guidance.

13. **P2 — Support exports include content by default.** `exportMetrics` exports the complete inference result, including transcript, stage inputs/outputs and custom prompts. UI text discloses this, but there is no metrics-only/redacted option. [Export](../App/DictationController.swift#L495). **Next:** default to a redacted support bundle; let the user deliberately include transcript/prompt content and preview the export contents. Do not add automatic telemetry as a workaround.

14. **P2 — Storage recovery needs a usable repair flow.** Vocabulary preserves unreadable files but disables writes; corrupt workflows fall back to session-only changes. This protects originals but leaves no guided export/repair/reset recovery. Workflow `save` can report success after a persist error, allowing an editor to close before durable storage is confirmed. [Workflow persistence](../Sources/QuibbleCore/DictationWorkflow.swift#L91), [vocabulary guard](../App/VocabularyStore.swift#L98). **Next:** distinguish session updates from durable writes, keep failed saves visibly open, add recovery actions with backup and migration fixtures.

15. **P2 — Release engineering and accessibility remain incomplete.** This workspace is not a Git repository, has no CI, and the root package deliberately excludes most App and inference code from its unit-test targets. The Xcode generator must remain synchronized with hand edits. Benchmark entry points are included in the shipping app binary. There is no full app-icon asset, localization catalog, release notices inventory or complete VoiceOver/contrast/keyboard-layout audit. [Package](../Package.swift), [generator](../Scripts/generate-project.py), [app entry](../App/QuibbleApp.swift#L7). **Next:** version control and repeatable checks, separate benchmark tooling, an explicit supported-platform build configuration, dependency notices, a release checklist and accessibility test matrix. No broad dependency vulnerability audit was performed here.

## Strengths to preserve

- Clipboard transactions check destination identity, selection, modifiers and clipboard ownership before sending one paste. Missing acknowledgement does not trigger a second insertion. Secure fields and known non-input controls are rejected.
- Vocabulary applies bounded, non-overlapping saved-word proposals and protects paths/URLs/code-like spans. Cleanup that changes protected terms falls back to its input. This constrains scope without promising perfect semantic recognition.
- Inference uses local model directories with no cloud fallback. Model downloads are pinned to revisions. Model switching clears the previous primary engine, and the app avoids overlapping inference.
- History is opt-in, versioned, bounded and atomically written; unreadable originals are preserved. Vocabulary edits publish after a successful durable write.
- Model benchmark provenance, quantization caveats, per-stage diagnostics and current-versus-peak allocation distinctions are explicit.

## Suggested next implementation order

1. Complete-output guards and durable-save reporting, with focused regressions.
2. Model integrity/repair, private crash cleanup and bounded vocabulary loading.
3. Clean-install model path migration and guided first dictation.
4. Cancellation/audio-device resilience and the cross-app/device test matrix.
5. Distribution signing, notices, notarization and a real signed update on a second Mac.

The requested visual/shortcut improvements are a usability pass. The findings above remain open until each has its own implementation and proving check.

## Verification of this implementation pass

- Signed Release build: `xcodebuild`, exit 0, `BUILD SUCCEEDED`; codesign deep/strict verification succeeded. Bundle ID and signing team remain unchanged.
- Swift package: 70 tests, zero failures, exit 0. Four shortcut tests were observed failing before their respective implementations, then passing: custom chord/repeat/release, modifier-first release, cancel/paste handling, and binding validation. Logs are `.build/build15-*-red.log` and `.build/build15-tests-final.log`.
- Python benchmark metrics: `python3 -m unittest discover -s Scripts -p 'test_*.py'`, one test, exit 0.
- Live UI: colored capability pills, role group headings and expanded supported/unavailable details; Feedback/Shortcuts/Device sections; shortcut capture, duplicate rejection, save, reset, and restored Option–Space after restart.
- User confirmed Control–Option–D starts, stops and inserts correctly in a normal field. UI automation sends keys directly to the app and did not exercise the system event tap; the user’s test is the evidence for global operation.
- Solid, Glass and Compact full-size previews were inspected using the same SwiftUI HUD component. Glass selection survived restart. Preview controls do not record, run models or paste. The user confirmed HUD feedback during actual custom-shortcut dictation. A full multi-display/full-screen and VoiceOver audit remains open.
- Original Option–Space dictation, Control–Command–V paste-last, Solid HUD style, Qwen ASR and Basic cleanup were retained/restored after testing. No user vocabulary or model files were changed.
- This pass adds no inference stage, background network fetch, periodic idle animation or model memory allocation. HUD metering continues only during recording; previews are bounded, user-triggered tasks. Blur has a compositor cost that has not been profiled here.

API reference consulted: [NSEvent characters(byApplyingModifiers:)](https://developer.apple.com/documentation/appkit/nsevent/characters(byapplyingmodifiers:)) for display names using unmodified characters. Shortcut matching uses physical key codes and explicit modifier masks; cross-application shortcut-conflict detection is not implemented.

## Color refinement

The user's final direction is muted/pastel color with consistent semantics. Informational colors now have explicit light/dark asset variants: slate blue for speech/language, ASR meters and the listening waveform, sage teal for vocabulary/cleanup, and dusty lavender for generation customization (custom instructions and adjustable decoder controls). Unsupported capabilities stay neutral. Native selection and action controls retain the system accent; success and warnings retain their status meanings. No per-model rainbow is introduced.

The palette has separate light/dark variants. A numerical contrast check against a white light surface and an 18%-gray dark surface with the badge tint gave ratios of 5.39–5.83:1; this is a palette check, not a substitute for the outstanding full accessibility/appearance audit.
