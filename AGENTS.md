# Working on Quibble

Quibble is a native macOS dictation app in active development. Read the relevant code and recent `Benchmarks/` notes before changing behavior. Older review findings are dated snapshots, not an authoritative list of current bugs.

## Scope and collaboration

- Keep changes focused and reviewable. Use independent workers for bounded tasks with explicit file ownership; this workspace is shared.
- Preserve the user’s current preferences, vocabulary, modes, model files, and opted-in history. Do not reset settings or delete downloads to simulate a new installation. Use isolated temporary data for destructive/failure tests.
- Continue authorized implementation and reversible validation without adding routine approval gates. User instructions and existing authorization take precedence over these conventions.
- **The repository is public at `PZTHH/quibble` under Apache-2.0.** Before any push, inspect what would be committed for credentials, private benchmark material, personal data, and licensing; `.gitignore` covers models, recordings, and raw results, but it is not a review. Do not add a new remote or change the license without the user’s instruction. A public repository is still not a notarized release.

## Product direction

- Make everyday dictation simple. Teach setup once; use visual status, concise labels, and progressive disclosure for technical detail.
- Use native macOS window and control behavior. Prefer restrained semantic colors, consistent spacing and radii, and subtle purposeful motion. Honor Reduce Motion, Reduce Transparency, keyboard navigation, and accessibility labels. Avoid fluorescent or arbitrarily assigned colors.
- Keep local work and memory load low without making unmeasured quality claims. Load models when needed, avoid concurrent inference, and preserve idle unloading. Never download a large model merely because a view opens.
- Keep HUD layout separate from material. Metering shows current sound with a stable silent state; it must not invent speech activity. Processing animation is a separate state.
- Application-context rewriting, agent assistance, and voice commands remain future work unless explicitly included in the current task. Do not re-enable surrounding-text rewriting as part of unrelated cleanup.

## Architecture and files

- `App/`: SwiftUI/AppKit UI and platform integration. `DictationController` owns the current lifecycle; reuse its guards and the shared `ModelLibrary` instead of creating competing recorders/downloaders.
- `Sources/QuibbleCore/`: testable session, shortcut, workflow, vocabulary, history, audio, and metadata logic.
- `Inference/Sources/QuibbleInference/`: model orchestration and adapters. `QuibbleWhisper/` is a deliberately scoped vendored adapter; retain provenance and license when updating it.
- `Models.lock.json` and `App/Resources/ModelCatalog.json`: CLI and bundled model manifests. Keep corresponding entries, revisions, and capabilities consistent.
- `Scripts/generate-project.py`: source for the generated Xcode project. The App group is filesystem-synchronized. When adding App files, inspect the root `Package.swift` targets’ explicit source/exclusion lists as well.
- `README.md`: current app and build introduction. `Docs/README.md` indexes setup, planning, historical notes, and local visual references. Put detailed research, measurements, reproductions, and historical change logs in dated `Benchmarks/` documents.
- Keep the repository root for entry points and build manifests. Store setup notes in `Docs/Setup/`, plans in `Docs/Planning/`, competitor reference images in `Docs/References/`, and the README's own interface screenshots in `Docs/Screenshots/`; maintain links when moving documentation. Refresh a screenshot when the interface it shows changes, and keep real transcripts, history, and vocabulary out of it. Reference screenshots and raw local results are ignored for future source control, but remain available locally. Do not move or delete models, recordings, or test fixtures during documentation cleanup.

## Recording, insertion, and privacy invariants

- Never quit, relaunch, or replace Quibble while it is recording, processing, or inserting. Check the actual running UI immediately before installation; the user may be dictating into the current conversation. Session-only history is lost on restart.
- Preserve both hold-to-dictate and toggle dictation. Do not reintroduce a one-minute recording cutoff or treat transient event-tap timeout as an unconditional key release.
- Start microphone capture promptly. Do not solve cue leakage by deleting a fixed opening interval or filtering words such as “um” from transcripts. Keep stop cues after recording ends and preserve genuine short/quiet speech.
- **Swift 6 audio callbacks must not inherit MainActor isolation.** `QueueMicrophoneCapture` C callbacks must remain outside MainActor and touch only synchronized sendable state. `HUDSpectrumMonitor` analyzes the same PCM written to the WAV and must not open a second microphone client. Calling a closure created in a MainActor method from AVAudioNode’s tap thread previously crashed the app. Keep audio callbacks lightweight and run the dedicated regression below.
- One verified destination, one paste attempt. Preserve destination/selection/clipboard ownership checks, secure-field exclusion, and no automatic retry after ambiguous delivery. Never send an extra Enter key or claim confirmed insertion without evidence.
- Keep speech detection shared across transcription routes. Uncertain analysis must not silently discard possible speech. Original imported audio is user data and must remain untouched.
- Keep local inference local without hidden cloud fallback. Online models require explicit selection and configuration. Never expose API keys in logs, preferences, source, or screenshots.
- Vocabulary changes must remain bounded to supported candidates. Protect unrelated text and explicit user rules; evaluate missed terms and false corrections. A small edit distance is not proof of correctness.
- Timeline text is original ASR output. Distinguish acoustic alignment from audio-section boundaries. Speaker labels are anonymous and scoped to their request/section; never infer identity continuity across independent chunks.
- Preserve unreadable storage originals and report persistence failures. No telemetry or automatic transcript upload. Support/benchmark exports may contain private text and prompts.

## Signing and installation

The existing development app uses bundle ID `com.pezhvak.quibble`, Apple Development signing from `Config/Signing.xcconfig`, and the team ID in `Config/Signing.local.xcconfig`, which is untracked and specific to this Mac. Its stable path is:

`/Applications/Quibble.app`

Keep that identity and path stable for this installation. Do not alternate ad-hoc/development/distribution signing or reset TCC to make a test pass. Developers on other machines copy `Config/Signing.local.xcconfig.example` and set their own team there. `Config/Distribution.xcconfig` and `Scripts/build-release.sh` cover builds that leave this Mac; they clear the checkout models path and require Developer ID signing. Compatible designated requirements are a prerequisite, not proof that permissions survive a real update. The installation moved from the checkout's `DerivedData` products folder to `/Applications` on 2026-09-06, at build 32; Microphone and Accessibility grants carried across that move because the designated requirement matched. A stale bundle may remain under `DerivedData/Build/Products/Release/`; it is build output, not the installation.

Build into a staging directory so compilation cannot mutate the running app bundle:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Quibble.xcodeproj -scheme Quibble -configuration Release \
  -derivedDataPath DerivedData -clonedSourcePackagesDirPath Inference/.build \
  -destination 'platform=macOS,arch=arm64' \
  -toolchain com.apple.dt.toolchain.Metal.32023.883 \
  CONFIGURATION_BUILD_DIR="$PWD/.build/install-staging" build

codesign --verify --deep --strict --verbose=2 .build/install-staging/Quibble.app
```

The Metal override is specific to this Mac; see [Metal toolchain setup](Docs/Setup/METAL-TOOLCHAIN.md). Do not change the system-wide developer directory or patch Xcode to work around it.

After a fresh idle check, quit through the app UI, copy the complete staged signed bundle with `ditto` to the existing path, verify its signature again, and reopen that path. Do not use the staging app as the daily installation. Check `CFBundleVersion` in the installed bundle before reporting which build is running. Increase `CURRENT_PROJECT_VERSION` for a delivered update; do not change signing identity as part of versioning.

## Verification

Run checks appropriate to the change and read their fresh output/exit codes before claiming success. Reproduce a behavioral bug with a meaningful failing check when practical; avoid tests that only mirror a reversible cosmetic edit.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --scratch-path .build/core-tests

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 Scripts/check-hud-audio-callback.py

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 Scripts/check-audio-input-devices.py

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  python3 Scripts/check-menu-bar.py

python3 -m unittest discover -s Scripts -p 'test_*.py'
```

The package suite intentionally excludes most App and MLX code. It does not replace a signed Xcode build or a live check of the changed flow. Run the HUD callback probe for audio/HUD lifecycle changes. Use existing local model weights for inference checks; avoid unnecessary downloads and overlapping benchmarks while the app is active.

For UI work, inspect the real native app after building, including useful empty/loading/error states and keyboard navigation. Use available UI tools for UI actions; do not send shell-driven keystrokes or use accessibility scripting as a hidden substitute. Keep permission grants with the user when required by their current instructions.

Document what actually ran: automated tests, file-based inference, native UI inspection, and user-reported live dictation are different evidence. Never call a physical global-shortcut test verified merely because a UI tool sent keys to a window.

## Claims and release readiness

- “Accuracy” is relative upstream benchmark standing, not `100 − WER` or an exact local success rate. Published HF speed is hardware-specific; local timing belongs in Diagnostics. Keep download size, current memory, and peak MLX allocation distinct.
- Model capability labels must match the current adapter, not just an upstream model card. Recheck primary sources when refreshing moving facts; retain source revision, date, hardware, and quantization caveats.
- Do not turn a successful test on one Mac/editor into a universal compatibility, permission-retention, or quality promise. Preserve explicit gaps around local diarization, older hardware/OS coverage, integrity checks, device/crash recovery, and distribution.
- A development-signed build is not a notarized release. Follow current user authorization for publishing, then verify clean install/update behavior and required notices before calling a release ready.
