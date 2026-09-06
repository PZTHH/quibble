# Static Hugging Face speed references in Models

Retrieved: 2026-09-06. Directional after: 2026-09-13.

## Decision

Models now compares static upstream Accuracy and Speed rankings. Both use the same pinned public English short-form snapshot; speed is the published inverse real-time factor (RTFx). The table explicitly labels its benchmark **HF · H200**. This replaces the earlier decision to show session measurements in the library. Measurements from this Mac remain in Diagnostics.

This is a comparison of the source benchmark's implementations, not predicted latency for Quibble's MLX runtimes or quantized variants. Higher RTFx is faster; a segment is an ordinal rank, not a proportional speed difference. Both Cohere variants deliberately share one upstream reference.

## Evidence

| Claim | Primary source | Read on |
|---|---|---|
| The English short-form CSV contains RTFx and per-dataset throughput for the same eight public datasets as our accuracy reference. | [Pinned results CSV](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/eec9efdf93683faf1dfb36c7d77b3c12d746215e/english_short_latest.csv) | 2026-09-06 |
| HF's display pools throughput by audio duration: total audio seconds divided by total compute seconds, using its published per-split durations. | [Pinned display and aggregation code](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/blob/c469d4f9f92c51969eed6b536e57b8dde62bcf58/app.py) | 2026-09-06 |
| Short-form evaluation jobs use NVIDIA H200 hardware; each model family has its own runtime image. | [Pinned evaluation README](https://github.com/huggingface/open_asr_leaderboard/blob/48219c6028db0517d704600d92f31edfc96e8c23/README.md#evaluate-a-model-as-of-24-july-2026) | 2026-09-06 |
| RTFx depends on hardware, batching, and audio characteristics, so it must not be presented as this Mac's latency. | [HF metric documentation](https://huggingface.co/learn/audio-course/chapter5/evaluation#inverse-real-time-factor-rtfx) | 2026-09-06 |
| The published Qwen launcher uses H200 jobs and batched evaluation. It is illustrative configuration, not proof of the exact run settings for every rated checkpoint. | [Pinned Qwen launcher](https://github.com/huggingface/open_asr_leaderboard/blob/48219c6028db0517d704600d92f31edfc96e8c23/qwen/submit_jobs.sh) | 2026-09-06 |

## Values shipped

Every value is copied from the same [results snapshot](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/eec9efdf93683faf1dfb36c7d77b3c12d746215e/english_short_latest.csv). Scores are left unchanged; the source ranking can put a larger checkpoint above its smaller sibling.

| Quibble model | Published RTFx | Relative speed segments |
|---|---:|---:|
| Parakeet v3 | 6076.07 | 6 / 6 |
| Cohere Transcribe, both variants | 906.56 | 5 / 6 |
| Qwen3 ASR 1.7B | 819.96 | 4 / 6 |
| Whisper Turbo | 791.52 | 3 / 6 |
| Qwen3 ASR 0.6B | 743.96 | 2 / 6 |
| Whisper Large v3 | 470.20 | 1 / 6 |
| Whisper Base / Small | Not available | Unrated |

No source row exists for the offered multilingual Base/Small checkpoints in this snapshot. English-only variants, historical cohorts, text models, and API services were not substituted. Exact model mapping is retained in `App/Resources/ASRBenchmarks.json` with the new speed scope and per-dataset values.

## Checks and limits

- Re-fetched HF repository metadata: results revision `eec9efdf93683faf1dfb36c7d77b3c12d746215e` and Space revision `c469d4f9f92c51969eed6b536e57b8dde62bcf58` remain current at retrieval.
- Verified CSV SHA-256 `07f02da66f62ea16ee6999163109544e8ffccc5476fd4b73149bc21b1e987451` against the bundled accuracy snapshot.
- Recomputed all seven catalog mappings using HF's eight split durations. Each agrees with published RTFx within 0.006, accounting for source rounding.
- Swift catalog tests observed six red assertions before the speed-ranking implementation, then passed: five tests, zero failures, exit 0. They cover missing/unscoped/nonpositive speed values and shared checkpoint ties. Syntax parsing passed. Parent handles the integrated Release build and live visual checks.
- Model weight commit, per-run batch settings, and exact local conversion performance are not established by the results CSV. Their Mac equivalence remains unconfirmed. Details keeps this limitation beside the values.

## Visual changes in this slice

The library uses compact labelled Accuracy/Speed segments, a dedicated muted gold Speed tint, 20-point table/detail surfaces, and 12-point selected rows with an outline, stronger fill, and checkmark. Online selection receives the same explicit outline. Sorting adds HF speed. Last-run Mac measurements are absent from both the library rows and their Details sheet.
