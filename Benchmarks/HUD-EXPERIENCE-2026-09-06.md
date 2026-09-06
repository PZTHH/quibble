# HUD and sound refinement

Date: 2026-09-06

## Three distinct options

- **Studio** is a 352 × 116 card with 26-point continuous corners. It shows the full status, supporting detail, elapsed recording time, microphone state, and labeled Finish / Cancel actions. The old persisted `Solid` value maps to this presentation.
- **Glass** is a 316 × 62 translucent strip with stage detail and compact Finish / Cancel buttons. It has 26-point continuous corners and retains more of the space around the destination field.
- **Compact** is a 188 × 40 passive capsule. It shows a short state, waveform, and recording time. It has no controls and passes mouse events through to the app underneath. Release the shortcut to finish; Escape while holding still cancels through the existing shortcut handler.

All three keep the original nonactivating NSPanel behavior. No controller, recording, inference, shortcut, or insertion path was changed. Preview controls are disabled and the preview panel ignores mouse events. Studio and Glass use the existing `onFinish` and `onCancel` hooks in actual dictation.

The listening accent is the existing muted speech color. Successful completion uses the muted vocabulary color; a soft amber is reserved for attention. Glass falls back to an opaque background with Reduce Transparency. Reduce Motion removes waveform interpolation and replaces progress spinners with static symbols.

Settings now shows miniature layouts that reflect these differences, a separate sound section, and full-size previews. Settings cards use 26-point corners.

## Original sound design

`soft-start.wav`, `soft-stop.wav`, `soft-complete.wav`, `soft-error.wav`, and `soft-cancel.wav` are newly synthesized original assets. No Superwhisper sound files were copied, sampled, extracted, or transformed.

The Soft set uses rounded sine tones with subdued second/third harmonics, a 9 ms attack, exponential decay, and a 28 ms smooth release. Start rises from D5 to A5; stop falls from E5 to A4; completion rises from E5 to A5; warning falls from A4 to F-sharp4; cancellation is a brief G4. Cues last 168–258 ms.

The five assets total 95,922 bytes as 44.1 kHz mono, 16-bit PCM WAV. Digital peaks range from 0.223 to 0.328 full scale before the existing 0.4 playback volume. Each starts and ends at zero; the generator asserted there was no clipping.

Users can choose Soft or the existing Original cues. Soft is the new default. The selection is saved in `feedbackSoundStyle`; if a selected asset is missing, playback falls back to the matching existing cue. Disabling Sound cues also stops current playback and cancels the sound preview. A preview plays a bounded start/stop pair; actual dictation cancels queued sound previews.

No audio work runs while idle. Assets are loaded only when a cue is played. The HUD uses the existing recording meter updates and adds no timer or display polling.

## Verification

- `swiftc -typecheck -swift-version 5 App/DictationFeedback.swift .build/hud-palette-stub.swift` completed with exit 0. This checks the feedback implementation against the real AppKit/SwiftUI SDK with only the existing palette stubbed.
- `swiftc -typecheck -swift-version 5 -I .build/core-tests/arm64-apple-macosx/debug/Modules App/DictationFeedback.swift App/SettingsView.swift .build/hud-palette-stub.swift .build/hud-settings-stubs.swift` completed with exit 0. This also checks Settings against the real QuibbleCore module, with the unchanged controller interface and auxiliary shortcut views stubbed.
- WAV generator validated file format, bounded peaks, duration, and zero-value boundaries for each generated asset.
- Full app build, live visual review at supported widths, actual finish/cancel interaction in Studio/Glass, click-through in Compact, and sound preference playback require parent integration verification. Sound similarity is not asserted; the aim is a soft, concise character using original tones.
