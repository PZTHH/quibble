# Build 26 — setup, model library, and repository preparation

Date: 2026-09-06. Hardware: M5 Max, 48 GB; macOS 26.6.1. Development build, not a notarized release. GitHub publication remains pending the user's explicit “it's ready.”

## Delivered behavior

- Resumable four-step setup: permissions, selective model downloads, real shortcut practice, personalization.
- Idle illustration yields immediately to actual listening/processing; processing text follows the inference stage. Completed practice replaces the canned example with the user's transcript, with a brief first-success glow. Reduce Motion stops the demonstration and reward motion. Practice stays in Quibble while the guide is focused; other apps retain normal insertion.
- Downloads run sequentially through the existing checked downloader and remain visible across guide pages. Closing setup keeps them running. Cancellation/failure retains completed models and stops remaining transfers. Missing, incomplete, or unknown components do not count as ready.
- One row per logical speech model: 13 models, 24 downloadable representations. Weight formats live in Details. Existing explicit choices and installed quantized files win; new suggestions prefer quantized artifacts with recorded smoke tests and consider RAM and enabled writing steps. Q8 is suggested only within a conservative estimated budget, otherwise Q4 where available. Granite's supported Q5 preference and tiny official Moonshine float weights are exceptions. These are estimates, not measured quality/memory promises.
- Added native adapters for Canary AED v2, Nemotron 3.5, original Moonshine, and Granite 4.0; added Q8 alternatives including Parakeet v3. Exact artifact provenance and validation status remain visible. Current leading but unsupported architectures are documented in the coverage report instead of receiving a nonfunctional download button.
- README and AGENTS.md written. Setup/planning/history/reference material moved under Docs; links and ignore rules repaired. No original models, recordings, preferences, or reference images were deleted. Test downloads remained isolated from the app’s installed model set.

## Automated and integration evidence

- Root Swift suite: 163 tests, zero failures, exit 0 (`.build/build26-tests-final.log`).
- HUD callback probe: actual background audio callback, 64 spectrum bands, and shutdown passed; no microphone opened (`.build/build26-hud-callback.log`).
- Python suite: one test, zero failures, exit 0.
- ModelLibrary setup harness: readiness, installed-file skipping, ordering, concurrency, cancellation, conflicts, and unknown IDs passed.
- Real tiny-download harness: sequential successful transfers/receipts, actual second-file HTTP failure, and cancellation all passed. 3,199 fixture bytes plus a small error response; temporary data removed.
- Repository cleanup verifier: 12 moves; 8 reference images hash-identical; 59 links checked; 233 authored/source/fixture cases remain visible; 14 artifact cases ignored; zero errors. Root has no Git repository or remote.
- Read-only adapter review checked catalog/lock identity and unloading/chunk boundaries. It found Nemotron's Japanese/Chinese prompt-ID mismatch; production mapping now uses ja-JP/zh-CN. A compiled no-GPU enum probe checked every exposed language against the pinned prompt dictionary. This is not multilingual acoustic validation.

## File-based audio smoke tests

Short synthetic sentence: “Please send the revised document to Maya before Thursday afternoon.” Two runs per artifact, ASR only. All retained the words; Granite produced lowercase unpunctuated text. Eight exact artifacts completed 40 file-based runs across these four cases. First ASR includes first-use kernel work; model loading is separate. Values below are one observation, not stable benchmarks or an energy comparison.

| Artifact | First ASR | Warm ASR | Peak MLX allocation | Active after unload |
| --- | ---: | ---: | ---: | ---: |
| Moonshine Base (official original) | 1.610 s | 0.057 s | 0.317 GB | 20 B |
| Canary v2 Q8 | 1.908 s | 0.116 s | 1.310 GB | 5,960 B |
| Nemotron 3.5 Q8 | 1.428 s | 0.064 s | 0.843 GB | 3,592 B |
| Granite 4.0 Q5 | 3.321 s | 0.221 s | 3.575 GB | 4,540 B |
| Parakeet v3 Q8 | 0.459 s | 0.028 s | 1.150 GB | 3,556 B |
| Cohere Transcribe Q8 | 0.308 s | 0.080 s | 2.670 GB | 6,232 B |
| Whisper Turbo Q8 | 0.267 s | 0.108 s | 2.309 GB | 118,444 B |
| Qwen3 ASR 1.7B Q8 | 0.499 s | 0.120 s | 3.419 GB | 3,204 B |

The four new families plus Parakeet, Cohere, Qwen3 ASR 1.7B, and Whisper Turbo Q8 also processed the 40-second long fixture through the same app inference path, with no warnings and preserved opening/closing content. Moonshine used three sections, Canary/Granite two; Nemotron/Parakeet expose backend sentence alignment. Ordinary recognition differences remained (for example, “cleaned text” became “clean text”). These results do not establish a WER improvement, human-dictation accuracy, multilingual quality, or lower device power use.

Shared vocabulary plus cleanup: all eight tested artifacts produced the saved spelling “Siobhan” through the shared vocabulary/cleanup workflow, correcting Shivon/Shivan hypotheses where needed; all eight kept the unrelated Maya sentence intact. No warnings in the final sixteen runs. The initial isolated fixture used symlinked model directories, which the loaders did not enumerate; replacing only those temporary symlinks with APFS-cloned files fixed the test setup. The initial fallback results were not counted as successful vocabulary tests.

Raw synthetic reports are under ignored `.build/asr-validation/reports/`. MLX peak allocation differs from app resident memory and from weight-file size. Tests run sequentially and do not capture the microphone or paste into applications. Temporary model fixtures are separate from the user's installed Models folder.

## Native UI and remaining limits

Signed build 26 compiled successfully (`.build/build26-release.log`), passed deep/strict signature verification, and was installed at the stable development path after a fresh idle check. The installed CFBundleVersion is 26; permissions remained ready in this update and the current Cohere 4-bit selection was preserved. This is one observed update, not a universal TCC guarantee.

Native screenshots and accessibility state were reviewed at the actual window sizes: setup personalization, idle practice, bright Listening state, three grouped model choices, full library, and Details in downloaded-Q4 and undownloaded-Q8 states. Escape cancelled a live button-start practice without dismissing the guide. The user's subsequent real tests appeared inside the illustration, including “Okay, I'm speaking.” and “Hey, it's working.” Previewing Q8 in Details did not change the active Q4 mode. The guide was left on Try your voice.

The reward glow and exact processing-stage binding are implemented; screenshot inspection established the listening and completed states, not frame-by-frame animation timing. Download failure/cancellation behavior was verified through real-transfer harnesses, not by resetting user preferences to force every onboarding screen state. Reduce Motion code paths were reviewed but system accessibility preferences were not changed during this pass.

All ten task-created model fixture folders (eight downloaded artifacts plus two APFS-cloned helpers) were removed after validation. Reports and exact-source receipts remain under `.build/asr-validation/`; the user's original Models directory was untouched. Logical fixture size was about 13 GB; this is not a claim about physical space reclaimed from APFS clones.

Release work remains: wider hardware/language/editor coverage, trusted model hashes and repair, interrupted-download resumption, crash/device recovery, distribution model-folder migration, runtime/model notices, project licensing, notarization, and a signed update path. Local diarization and agent/voice-command features remain future work.

Related: [Apple Silicon runtime research](APPLE-SILICON-RUNTIME-2026-09-06.md), [ASR coverage and exact sources](ASR-MODEL-COVERAGE-2026-09-06.md), [repo cleanup](REPOSITORY-CLEANUP-2026-09-06.md).
