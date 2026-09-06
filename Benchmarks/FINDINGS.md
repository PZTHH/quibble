# Phase 1 measurements

Measured 2026-09-05 on Apple M5 Max, 48 GiB RAM, macOS 26.6.1. These are short feasibility tests, not a claim of production accuracy or universal app compatibility.

Follow-up: build 3 now defaults to Cohere 4-bit. The initial measurements below used FP16 Cohere; see the [paired quantization comparison](QUANTIZATION.md) for the newer memory and speed results.

## Local inference

Four Samantha-generated clips (3.94, 9.63, 16.24 and 40.01 seconds) were processed three times by each speech engine with S1-mini cleanup: **24 successful runs with network access denied** using `/usr/bin/sandbox-exec -p '(version 1) (allow default) (deny network*)'`. The application executable, pinned models and inference actor were the same ones used by the GUI. No cleanup fallback warnings occurred in these runs.

Warm total file-processing medians, excluding each job's first run:

| Clip | Cohere + S1-mini | Parakeet + S1-mini |
|---|---:|---:|
| Short sentence, 3.94 s audio | 0.182 s | 0.080 s |
| Spoken correction, 9.63 s | 0.344 s | 0.152 s |
| Technical text, 16.24 s | 0.480 s | 0.244 s |
| Longer notes, 40.01 s | 1.107 s | 0.599 s |

The initial unrestricted Cohere smoke run took about 5.5 seconds for file processing, including loading and first-use GPU work. Later fresh-process runs benefited from system caches. Loading alone therefore does not describe the full cold-start delay. Peak MLX allocation was about 5.6–5.8 GB for Cohere plus S1 and 3.8 GB for Parakeet plus S1; this excludes other process memory.

Both engines recognized the short and correction clips without normalized raw word errors. S1-mini changed “Tuesday, no, sorry, Thursday” to Thursday, preserving “Do not send the old report.” In the technical clip, Cohere produced “Postgresql”; Parakeet produced “PostGur SQL”, which cleanup retained. This is a concrete reason to keep editable vocabulary in the roadmap. Cohere remains the prototype default; Parakeet is a useful speed comparison, not yet a quality-equivalent replacement.

The longer transcript preserved the negation and numeric meaning and received paragraph breaks. Raw error counts include harmless number formatting such as “fifteen” → “15”, and both models returned “clean text” where the synthetic reference says “cleaned text”. See [all outputs and timings](results/SUMMARY.md). Human accents, microphone noise, p50/p95 release-to-insertion latency, thermal behavior and a slower baseline Mac remain unmeasured.

## Additional behavior checks

- Exact mode retained the spoken correction in raw form and performed no refinement.
- One second of digital silence returned empty text.
- A 61-second recording was rejected before inference.
- With S1-mini absent, the app returned the raw speech transcript with an explicit cleanup warning.
- GUI import of the correction clip produced the expected cleaned sentence.
- GUI microphone recording started and cancellation returned to idle before and after the update.

## Signed update

Builds 1 and 2 have different code hashes, the same bundle identifier and signing team, and matching designated requirements. Build 2 satisfies build 1's requirement; see [signature evidence](update-identity.json).

The user granted Microphone and Accessibility to build 1. After quitting it, replacing the bundle at the same path with build 2, and relaunching, the GUI still reported both as allowed. Recording started without a new grant, and the global event tap enabled after relaunch. This is evidence for this development-signed update on this Mac, not a guarantee for changing certificates, signing classes, app locations or macOS versions.

The user's physical Option–Space test succeeded in TextEdit: “The quick brown fox jumps over the lazy dog.” appeared after the existing test prefix. For 6.474 seconds of microphone audio, the timing UI showed 0.277 seconds from release to result and a 0.004-second insertion attempt (about 0.281 seconds combined). This is one warm observation, not a latency percentile. The [exported transcript and inference timings](live-textedit.json) preserve the result; release/insertion timings were observed in the GUI and are not included in that export format.

TextEdit Undo removed only the inserted sentence and Redo restored it. The automation tool's own Option–Space press had entered a non-breaking space without triggering Quibble; the successful physical-keyboard test establishes the shortcut works on this Mac. Selection replacement, other applications, clipboard races and focus-race compatibility still need broader testing.
