# Hugging Face ASR recognition benchmarks for Quibble

Retrieved: 2026-09-05. Directional after: 2026-09-12.

## Answer

Bundle the **public English short-form eight-dataset mean WER** from Hugging Face’s Open ASR Leaderboard. Lower is better. Seven Quibble catalog entries map to six upstream results; Whisper Base and Small have no comparable row in this snapshot and remain unrated. The score is an upstream reference, not an evaluation of Quibble’s quantized weights or complete workflow. [Pinned results](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/eec9efdf93683faf1dfb36c7d77b3c12d746215e/english_short_latest.csv), read 2026-09-05.

The data lives in `App/Resources/ASRBenchmarks.json`. It is a bundled snapshot: no network lookup at application runtime, no imported GPU speed rating.

## Exact task and version

Use the unweighted mean of these eight WER percentage columns from the **same** CSV revision `eec9efdf93683faf1dfb36c7d77b3c12d746215e`:

1. AMI-Cleaned
2. Earnings22-Cleaned-AA-chunked
3. Gigaspeech-Cleaned
4. LS Clean
5. LS Other
6. SPGISpeech
7. Voice Arena Monsoon
8. Voxpopuli-AA-Cleaned

Recomputing each mapped row’s eight-column mean reproduces its `avg` value. **This is not the current default UI average**: that view also includes private scripted/conversational averages. The public subset is deliberate and consistent across all mapped models. The version registry identifies the current data source; the UI computes averages from selected datasets. [Pinned registry](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/blob/c469d4f9f92c51969eed6b536e57b8dde62bcf58/init.py), [pinned averaging code](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/blob/c469d4f9f92c51969eed6b536e57b8dde62bcf58/app.py), read 2026-09-05.

The leaderboard documents macro-averaging, short-form test splits, normalization of punctuation/case/numbers and filler words, and the special concatenated scoring for chunked Earnings22. Those preprocessing choices mean this metric does not measure preservation of punctuation, personal names, or dictation-specific formatting. [Pinned methodology](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/blob/c469d4f9f92c51969eed6b536e57b8dde62bcf58/constants.py), read 2026-09-05.

## Catalog mapping

Every numeric value below comes from the same [pinned results CSV](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/eec9efdf93683faf1dfb36c7d77b3c12d746215e/english_short_latest.csv), read 2026-09-05. Display to two decimals, retain source precision in JSON.

| Quibble catalog ID | Evaluated upstream checkpoint | Mean WER % |
|---|---|---:|
| `cohere-4bit` | `CohereLabs/cohere-transcribe-03-2026` | 4.67000 |
| `cohere` | `CohereLabs/cohere-transcribe-03-2026` | 4.67000 |
| `parakeet` | `nvidia/parakeet-tdt-0.6b-v3` | 4.85875 |
| `qwen3-asr-4bit` | `Qwen/Qwen3-ASR-1.7B-hf` | 4.31125 |
| `qwen3-asr-06b-4bit` | `Qwen/Qwen3-ASR-0.6B-hf` | 5.04500 |
| `whisper-turbo-vocabulary-4bit` | `openai/whisper-large-v3-turbo` | 6.36000 |
| `whisper-large-vocabulary-4bit` | `openai/whisper-large-v3` | 5.78000 |
| `whisper-base-4bit` | `openai/whisper-base` | Unavailable |
| `whisper-small-4bit` | `openai/whisper-small` | Unavailable |

Whisper Base/Small have no row among the snapshot’s 62 model rows. Do not substitute their English-only `.en` checkpoints, smaller distilled models, or historical benchmark versions. Text cleanup/instruction models are not ASR checkpoints and have no score here.

## Interpretation and UI requirements

- Label **WER · lower is better**, with “upstream benchmark” visible or immediately available. Do not label WER “percent accurate” or convert it to an invented star/quality score.
- Keep weight format as a separate factual chip. Cohere FP16 and 4-bit share the same upstream reference; this does **not** establish that their actual local WER is equal.
- Show no score for missing checkpoints. Do not assign zero or an estimated value.
- Use the existing Mac session timing measurements for speed. Upstream throughput measures a different runtime/hardware configuration.
- Prompt cleanup and guarded vocabulary run after the raw ASR and are outside this benchmark.
- The snapshot pins the results CSV, not the evaluated model-weight commit; those weight revisions are not reported in the CSV.

These are integration decisions based on the source scope, not claims that Hugging Face tested Quibble.

## Qwen mapping evidence

Qwen’s [Qwen3-ASR-1.7B-hf model card](https://huggingface.co/Qwen/Qwen3-ASR-1.7B-hf/blob/bcd2b5b7f32b480ab5790554cfa8347f246a14f3/README.md) identifies the Transformers-native Qwen3-ASR family. Read 2026-09-05.

Qwen’s [Qwen3-ASR-0.6B-hf model card](https://huggingface.co/Qwen/Qwen3-ASR-0.6B-hf/blob/7f1569a48a89f3e3f4dc3a5c9d28bddd903bc76c/README.md) identifies the Transformers-native Qwen3-ASR family. Read 2026-09-05.

The source leaderboard evaluated these `-hf` editions. Quibble’s catalog points to MLX conversions of the corresponding non-`-hf` upstream model family. The bundled notes explicitly preserve that distinction. Byte-for-byte checkpoint equivalence and local 4-bit WER are **unconfirmed**; no equivalent-result claim is made.

## Verification and open questions

The generation script checked all seven mappings against exact source model IDs, required all eight dataset columns, recomputed their decimal means, and asserted agreement with the CSV `avg`. The JSON contains each per-dataset WER for audit. No `.en` substitutions were made.

Source CSV SHA-256: `07f02da66f62ea16ee6999163109544e8ffccc5476fd4b73149bc21b1e987451`.

Still unconfirmed: exact MLX/4-bit recognition WER, Whisper Base/Small on this dataset version, representative personal-vocabulary performance, and whether results generalize to the user’s voice/languages. A future local benchmark should run matched recordings/settings and report its own results separately.
