# Build 23: recording, feedback, and transcript timelines

Date: 2026-09-06. This is a development build, with the existing bundle identifier and Apple Development signing identity.

## Recording and feedback

- Hold Option–Space to dictate, or press Control–Option–Space to start and press again to finish. Settings → Shortcuts configures these independently. Escape cancels shortcut recording.
- Removed the one-minute recording timeout. A transient macOS event-tap timeout checks the physical keys before ending a held recording.
- Long recordings are decoded sequentially in sections of at most 60 seconds. Boundaries prefer a pause near the end of a section; every decoded sample is retained exactly once. Audio decoding uses bounded buffers instead of loading the entire file into memory. Models remain reusable between sections and unload after the existing idle period.
- The HUD uses thin neutral bars showing current frequency energy. Silence settles to a flat baseline; processing uses a separate animated wave. The three layouts and two materials remain independent settings, with reduced-motion and reduced-transparency support.
- Completion shows the destination app icon and distinguishes confirmed insertion from an unconfirmed paste. No-speech input has a dedicated state and creates no empty history entry.
- A local SoundAnalysis preflight rejects only confidently speech-free mono input. Short, uncertain, quiet, unsupported, and multichannel input continues to ASR. Multichannel audio is downmixed before transcription, preserving speech confined to the right channel.

## History and speakers

History review offers Text and Timeline views, with copy actions for each. Timeline text is the original ASR output; cleanup or manual edits do not acquire invented acoustic timing.

Parakeet supplies aligned sentence timestamps. The current Qwen, Whisper, and Cohere adapters expose input-section timing rather than word alignment. The interface identifies that difference.

Models → Online transcription includes **OpenAI Speakers**, configured with the existing Keychain-based API-key setup. It requests anonymous speaker-labeled segments from the dedicated diarization model. This is post-transcription labeling, not live identification or recognition of named people. Independent uploaded sections have separate label scopes. The model does not accept vocabulary prompts; explicit spelling rules remain available.

See the [model capability research](SPEAKERS-SEGMENTS-2026-09-06.md) for primary sources and local alternatives. MOSS is a candidate for a later measured local integration; it has not been downloaded or exposed as a supported model.

## Checks and remaining limits

Build 22 exposed a real recording-start crash during review: the new audio-tap closure inherited `MainActor`, while AVFAudio invoked it on its audio queue. Build 23 constructs that callback in a `nonisolated` factory with an explicitly `@Sendable` closure. The HUD was temporarily disabled while the fix was built, then restored. The user confirmed that shortcut dictation worked with the HUD enabled; its resulting transcript and timestamp were inspected in the running app.

| Check | Result |
| --- | --- |
| Full core, vocabulary, and insertion suite | `swift test --scratch-path .build/core-tests`: 134 tests, zero failures, exit 0. Final log: `.build/build23-tests.log`. |
| Audio-thread crash regression | The previous callback reproduced the same actor-isolation SIGTRAP as the installed app. The fixed production callback ran on a detached task with Swift 6 actor checks, published 64 bands, and rejected input after shutdown; exit 0. |
| Release build and signing | Xcode Release build 23 succeeded, exit 0. `codesign --verify --deep --strict` passed for the staged and installed app. Bundle identity and development team were preserved. Log: `.build/build23-staged.log`. |
| Longer audio, actual inference | A 97.87-second synthetic recording completed with Qwen ASR, vocabulary, and S1 cleanup. Both repeated paragraphs and the middle technical passage survived; PostgreSQL was preserved. Two sections had unique IDs and bounds near 0–57.8 and 57.8–97.87 seconds. One cold run took 7.17 seconds with 4.71 GB peak MLX allocation (not total app RAM). Report: `.build/long-audio-speech-final.json`. |
| Leading silence | A 66-second file starting with 61 seconds of silence retained the spoken section, correct timestamp offset, workflow metadata, and the warning that custom instructions run per section. Report: `.build/leading-silence-result.json`. |
| Conservative speech preflight | Automated silence/noise, normal/quiet speech, missing-file, and right-channel-only stereo checks passed. Eight additional short, whispered, and multilingual fixtures were retained as speech or uncertain. These are smoke tests, not broad voice-activity accuracy estimates. |
| No-speech behavior in the app | Imported two seconds of digital silence. Home showed “No speech detected”; the previous transcript remained unchanged and History still contained its single existing dictation. |
| Visual review | Inspected Home, History, the real transcript Timeline, Models, both shortcut settings, online speaker setup, and Diagnostics in the running app. Reviewed Studio speech/processing preview frames and the three HUD layouts in the rendering gallery. |
| Speaker setup routing | Reproduced Speakers opening the ordinary Dictation setup. Replaced separate sheet state with an item-based presentation and verified that Speakers now opens with Speaker labels selected. No key was entered and no paid cloud request was made. |

The app remains on Qwen ASR with Basic cleanup, Studio layout, Frosted material, Soft sounds, and the HUD enabled. Hold and toggle routing, repeat suppression, cancellation, and event-tap recovery have automated state coverage. The user's successful live shortcut test does not establish compatibility with every keyboard, microphone, or destination app.

The remaining release work includes notarized distribution, update migration tests with release signing, broader hardware/input-device testing, human speech and overlapping-speaker evaluations, and live testing of paid diarization with a configured account. A successful synthetic long-recording test is not an accuracy benchmark. Uninterrupted speech at an unavoidable section boundary can still challenge an ASR model; custom writing instructions apply separately to each section and report that limitation.
