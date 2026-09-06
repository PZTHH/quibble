# Muted Soft feedback cues

Date: **2026-09-06**. Scope: five `soft-*.wav` resources and a reproducible generator. Swift playback, the Original sound option, shortcuts, and UI behavior were not changed in this pass.

## Design decision

Replace the pitched Soft chimes with short, damped gestures: a rounded start, a lower stop, a gentle completion, a sinking cancel, and two low pulses for an error. The user's supplied `ElevenLabs_Generation_4.ogg` informed the darker spectrum and decaying envelope. The new assets are original synthesis; they contain no extracted reference samples and do not recreate a competitor's sound file.

The new cues have most of their energy around 130–230 Hz, restrained filtered texture, and weak inharmonic body components. They use continuous pitch movement inside a single gesture rather than separate notes. A smooth 8 ms attack, tapered release, subsonic filtering, and a final 6 ms edge fade avoid sharp cut-ins and cut-offs. The error repeats the same low body after 130 ms so it is identifiable without a brighter warning chime.

**I analyzed waveform, spectrum, and envelope; I did not listen to the reference or the result.** Lower spectral brightness is verified. Whether the sound feels muffled, tactile, premium, sufficiently audible, and clearly differentiated still needs listening on the user's speakers/headphones. These are design intentions, not listening-test results.

## Reference analysis

Input: `/Users/march/Downloads/ElevenLabs_Generation_4.ogg`.

macOS `afinfo` identified stereo Opus at 48 kHz. `afconvert` decoded 96,000 valid frames: **2.000 seconds** of stereo 16-bit PCM. Analysis below averages channels for spectral measurements; peak measurement checks both original channels.

- Sample peak: **−12.24 dBFS**; mono RMS: **−26.90 dBFS**.
- Dominant full-spectrum peak: approximately **11 Hz**. Approximately **99.74% of total spectral power lies below 120 Hz**, much of it below ordinary audible bass. The full-power centroid is therefore only **14.1 Hz**, which must not be interpreted as a perceived pitch or conventional loudness measure.
- Above 120 Hz, the energy-weighted centroid is approximately **428 Hz**; remaining local peaks include roughly **140, 200, 260, and 436 Hz**. Their absolute contribution is small.
- Energy is strongest in the first approximately **350 ms**; the 10 ms RMS envelope remains above 10% of its maximum until roughly **1.14 seconds**, with a quieter residual tail until the end.

The app assets deliberately retain a short, low body rather than copying that 2-second tail or its subsonic dominance. Matching the reference's unweighted RMS would waste headroom on frequencies that may not reproduce usefully on small speakers. The reference was not truncated into an app cue.

Decoded analysis file: `.build/feedback-sounds-2026-09-06/reference.wav`.

## Objective comparison

“Centroid” below means a whole-file **power-weighted FFT centroid**, computed consistently before and after. It is a useful spectral comparison, not a psychoacoustic brightness or preference score. All before/after files are mono 44.1 kHz, 16-bit PCM.

| Cue | Old duration | New duration | Old → new centroid | Old → new sample peak | New 95% power rolloff |
|---|---:|---:|---:|---:|---:|
| Start | 213 ms | **145 ms** | 651 → **207 Hz** | −10.84 → **−15.50 dBFS** | 248 Hz |
| Stop | 193 ms | **120 ms** | 537 → **151 Hz** | −9.68 → **−16.50 dBFS** | 192 Hz |
| Complete | 258 ms | **185 ms** | 788 → **215 Hz** | −12.43 → **−17.00 dBFS** | 227 Hz |
| Error | 253 ms | **265 ms** | 412 → **148 Hz** | −13.04 → **−16.50 dBFS** | 177 Hz |
| Cancel | 168 ms | **130 ms** | 395 → **136 Hz** | −12.58 → **−18.00 dBFS** | 185 Hz |

The spectral centroids decreased **64–73%**. Power above 1 kHz is also lower for every cue, now at most **0.00013%**. Old Soft sounds already contained little high-frequency noise; much of the audible difference is expected to come from lowering their prominent tonal bands, shortening the ringing, and removing the two-note pattern.

New unweighted RMS levels range from **−26.87 to −30.09 dBFS**, compared with approximately −21.43 to −23.50 dBFS before. This is intentionally quieter, but output-device audibility has not been validated. The unchanged player uses an additional `NSSound.volume = 0.4`; these peak figures describe the WAV assets before that gain.

## Reproducibility and validation

`Scripts/generate-feedback-sounds.py` creates the five resources using only the Python standard library. Deterministic seeds generate the subtle texture; the filters, envelope, and pitch parameters are explicit. Generation does not require NumPy, ffmpeg, model inference, the reference file, or network access. The application continues to play bundled WAVs without runtime synthesis. The five new resources total **74,746 bytes**.

Regenerate:

```sh
python3 Scripts/generate-feedback-sounds.py
```

Compare without overwriting the app assets:

```sh
python3 Scripts/generate-feedback-sounds.py --output .build/feedback-sounds-2026-09-06/regenerated
```

Optional analysis requires NumPy; it reports PCM metadata, SHA-256, peaks, RMS, clipping, boundary samples, spectral bands, centroid, and rolloff:

```sh
python3 Scripts/generate-feedback-sounds.py --analyze-only \
  --baseline .build/feedback-sounds-2026-09-06/original \
  --reference .build/feedback-sounds-2026-09-06/reference.wav
```

The workspace's bundled Python with NumPy was used for analysis. Before replacing assets, all five old Soft WAVs were copied to **`.build/feedback-sounds-2026-09-06/original/`**. Complete measured before/after data is in **`.build/feedback-sounds-2026-09-06/analysis.json`**.

Fresh validation completed successfully:

- All five assets decode as mono 44.1 kHz / 16-bit PCM and remain below 350 ms.
- No clipped samples; peaks remain at or below −15.5 dBFS.
- First and last samples are exactly zero in every asset.
- Every new centroid is below 45% of its previous value; every file has less power above 1 kHz.
- Regenerating to a separate directory produced **byte-identical** WAVs.

These checks prove file integrity and objective signal changes. They do not establish perceptual quality. The next useful check is the in-app preview and a real press/release dictation on normal speakers, specifically checking whether Start and Stop remain easy to distinguish and whether the quieter completion is audible. If adjustment is needed, change the compact gesture or playback level before reintroducing bright high notes.
