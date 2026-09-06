# Build 24: feedback cues should not become words

Date: 2026-09-06.

## Reproduction

The original 145 ms Soft start sound was a periodic 245→170 Hz gesture. Playing its samples at the app's 0.4 gain and following them with silence returned `uncertain` from the speech preflight. Qwen then transcribed that cue-only input as **“Oh.”** The native regression failed with the same forwarding decision: `.build/cue-replay/cue-red.log` (one test, one failure, exit 1). The ASR report is `.build/cue-replay/asr-old-cue.json`.

Short input exposed a separate problem: SoundAnalysis emitted no windows for a clip shorter than its 0.5-second window. Even the Legacy cue alone therefore reached ASR. The short-cue regression reproduced this before the classifier change (`.build/cue-replay/short-cue-red.log`).

## Changes

- Soft start is now an 85 ms muffled, unpitched knock. It retains a quiet, low-frequency character without the old voiced oscillator. The other sound assets are unchanged.
- The speech classifier analyzes a temporary one-second padded copy when a mono clip is shorter than 0.5 seconds. The original audio and its timestamps remain untouched. The temporary copy is deleted on success, failure, or cancellation.
- Valid empty mono recordings return no speech. Unreadable or unsupported input still reaches existing error handling.
- Recording is stopped before playing the stop cue. A previous completion or preview sound is stopped before opening a new recording.
- Microphone capture still begins immediately. There is no fixed leading trim, delayed listening period, or rule deleting words such as “um” or “hmm.”

## Evidence

The replacement cue was classified as no speech in all 18 tested gain/delay/simple-room simulations. All 36 short-word and whispered-voice combinations, including genuine “Um” and words overlapping the cue, remained speech. These simulations do not cover every real speaker, room, microphone, or output volume.

The generator reproduces the shipped asset byte-for-byte. SHA-256: `b4734e9424ce32b6a1e7dae12785196e1f8df91981f11b2ddfe9a607c8e5b634`. `Scripts/generate-feedback-sounds.py --cue start` regenerates only this cue; NumPy is an offline development dependency and is not loaded by the application.

Final verification:

- `swift test --scratch-path .build/core-tests`: **139 tests, zero failures, exit 0** (`.build/build24-tests.log`). This includes actual shipped cue assets, normal/quiet short words, unchanged original files, temporary-copy cleanup, and valid empty recordings.
- Xcode Release **build 24 succeeded**, exit 0 (`.build/build24-staged.log`). Deep, strict code-signature verification passed before and after installation at the existing app path; the installed sound matches the verified asset byte-for-byte.
- Fresh production-detector replay kept both short start cues and the delayed room-filtered replacement out of ASR. Immediate overlapping voice, short “Um,” and short “Yes” were retained (`.build/cue-replay/root-final-replay.tsv`).
- Imported the installed app's exact 85 ms `soft-start.wav` through the real app. It displayed **No speech detected**, left the previous transcript intact, and created no new dictation.
- The live microphone recording completed with HUD and sound cues enabled. It contained singing, which the user confirmed was present, so this was a successful voice-preservation check rather than a quiet-room acoustic test.
- The durable HUD background-callback regression also passed: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 Scripts/check-hud-audio-callback.py`. It compiles current source in a fresh temporary directory and checks the actual audio callback with Swift 6 actor assertions.

The previous [recording, HUD, shortcut, and timeline update](BUILD-23-RECORDING-HISTORY.md) remains included. Speaker functionality and its limits are documented in the [model research](SPEAKERS-SEGMENTS-2026-09-06.md).
