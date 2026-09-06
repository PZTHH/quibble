# Build 8: audio-backed vocabulary

Evaluated 2026-09-05 on this M5 Max Mac. This is a measured improvement, **not completion of the arbitrary-name accuracy requirement**. No model weights were fine-tuned. Human pronunciation and accent validation remain open.

## Implemented behavior

All four selectable ASR models now use the same vocabulary stage. Their original transcript is retained. A quantized Whisper Turbo helper listens to the same recording with the saved spellings in its native previous-text prompt. Only aligned replacements ending in an enabled vocabulary entry can be applied. Surrounding words, spacing and punctuation come from the original transcript, never from the helper's full sentence.

Case-only and space-joining changes (for example quick time → QuickTime) require agreement from S1-mini running its ordinary normalization prompt **without a dictionary prefix**. If S1 is unavailable these ambiguous changes are skipped. Explicit user correction rules take precedence. Unconditional spelling-distance guesses and Qwen's unguarded vocabulary context were removed from normal dictation. Basic cleanup remains a separately selected mode and can format the resulting transcript; Minimal dictation keeps only accepted vocabulary edits.

The span guard rejects unknown targets, added/deleted words, protected URLs/email/code, overlapping edits, ambiguous repeated source occurrences and changes that swallow neighbors. These are structural protections, not a proof that an acoustic model chose the right person. Misses remain preferable to forcing a dictionary word into unrelated speech. Multiword entries with only a partial-token change can still be skipped; homophonous saved names cannot be uniquely resolved from spelling alone.

The helper loads only with enabled entries, reuses its weights between dictations, and participates in idle unloading. No-vocabulary dictation does not load it. Whole terms must fit Whisper's prompt budget; a diagnostic warning reports a truncated vocabulary. Missing assets preserve the original transcript plus approved explicit rules and produce a warning. The local Whisper adapter has no download API or automatic tokenizer-download fallback; installation is explicit through Models library.

Vocabulary's Record test uses the real dictation pipeline and shows individual before/after replacements. Typed Test exact rules previews only explicit rules. Models library includes the helper with pinned weights and independently pinned tokenizer assets.

## Actual app-pipeline results

Audio is macOS Samantha synthetic speech using pronunciation respellings. These are reproducible engineering cases, not an estimate of accuracy on human speech. The same complete word list is supplied to every case, with no oracle selection of the desired answer.

| Set | Models | Correct intended spellings | Vocabulary changes to unrelated controls |
|---|---|---|---|
| Initial 13 clips | Cohere 4-bit, Cohere FP16, Parakeet, Qwen ASR | 6/7 on each | 0/6 on each |
| Separate 24 clips | All four | 6/12 on each | 0/12 on each |
| Initial set with Basic cleanup | Cohere 4-bit | 6/7 | 0/6 |

The separate set's exact sentence totals are 18/24 for Cohere variants and Parakeet, 17/24 for Qwen. Qwen initially heard “seam” instead of “scene”; vocabulary preserved that unrelated ASR error. One missed preferred accented spelling is ambiguous in this fixture because both Siobhan and Siobhán appear in its combined dictionary. Caoimhe, Eoin, Tadhg, Dearbhla and Donnacha were also missed. These failures remain visible in the results, not filtered out of the denominator.

Additional controls preserve ordinary “quibble,” keep a dictated instruction as text, recognize the QuickTime application, and return no text for digital silence. QuickTime Player's existing primary-ASR capitalization remains unchanged. The running GUI was also exercised by importing the Superwhisper test recording with the user's existing saved entry and inactive explicit aliases: original “Please open Super Whisper.” became “Please open Superwhisper.” No microphone recording or insertion into another app was needed for this check.

Evidence:
- `results/audio-vocabulary-integrated.json`: 52 real pipeline runs across all four ASRs.
- `results/audio-vocabulary-integrated-holdout.json`: 96 real pipeline runs; these use actual primary-ASR transcripts, replacing the earlier constructed baseline projection test.
- `results/audio-vocabulary-integrated-cleanup.json`: 13 Basic cleanup runs.
- `results/audio-vocabulary-controls.json`: four additional controls, including silence.
- `results/vocabulary-disabled-baseline.json` and `results/vocabulary-disabled-cleanup-baseline.json`: no-vocabulary controls.
- `results/vocabulary-missing-tokenizer.json`: missing-tokenizer fallback retains raw text and reports the expected warning under network denial.
- `results/audio-vocabulary-final-smoke.json`: all 13 outputs match after removing the upstream download fallback.
- `results/vocabulary-helper-assets.json`: all 11 catalog assets match pinned source hashes and sizes (468,081,051 bytes).

## Resource cost

On this Mac, median vocabulary-stage time was about 107–109 ms across the initial sets. First helper use took about 260–279 ms; first ambiguous compound requiring S1 load took about 476–488 ms. Later ambiguous QuickTime checks took about 140–157 ms. These are short audio clips; longer recordings and other hardware will cost more. File benchmarks exclude microphone, shortcut and insertion latency.

The standalone helper retained about 477 MB of MLX allocations and reached about 1.91 GB peak during its probe. Cohere 4-bit plus helper and S1 reached about 3.24 GB active MLX allocation and 4.67 GB process-wide MLX peak in the integrated set. Cohere 4-bit with S1 and no vocabulary measured about 2.78 GB active in a separate short-clip control; ASR alone measured 1.57 GB. These are MLX allocations, **not total process RSS**. Peak values are process-wide and cannot be assigned to later individual engines after an earlier larger engine has run.

Explicit unload reduced active allocations from about 3.28 GB to 139 KB with a zero cache in the all-model run. Existing two-minute idle unloading invokes that same method. S1 is also needed in Minimal mode when checking an ambiguous compound; this is additional memory compared with ASR alone.

## Alternatives tested and rejected this turn

- Cohere candidate-vs-original transcript likelihood shared one acoustic prefill. It scored valid Caoimhe far worse than incorrect Kiva, while some ordinary-word substitutions scored closer than valid rare names. No universal threshold separated corrections from damage. `results/acoustic-vocabulary.json`.
- Whisper large-v3 4-bit did not improve the initial 6/7 result over Turbo, so the smaller ~468 MB download was selected. `results/whisper-large-vocabulary.json` and `results/whisper-vocabulary.json`.
- Generic LLM edit auditing, identity classification, pronunciation generation and semantic-role classification were unreliable. Independent Python MLX reproduced the suspicious classifier behavior, so it was not explained by the Swift adapter. These classifiers are not in dictation.
- S1 spelling prefixes and direct Parakeet/Cohere boosting remain rejected based on the previous evaluation. See [earlier qualification](VOCABULARY-QUALITY-EVALUATION.md), [Parakeet repository report](PARAKEET-VOCABULARY-REPO.md), [Cohere report](COHERE-VOCABULARY-REPO.md), and [competitor research](COMPETITOR-VOCABULARY.md).

## Reproduction and maintained code

`Quibble --audio-vocabulary-fixtures Models Benchmarks/whisper-vocabulary-fixtures.json OUTPUT.json --all-models` exercises the live inference entry point. Use `--cleanup` for the S1 path. Runs above used sandbox-exec with all network access denied.

The five Whisper files in `Inference/Sources/QuibbleWhisper` are a ~60 KB maintained copy from mlx-audio-swift commit bf14ae0c26e4e85553dd989571cae29d70fa6735, with MIT license and local-change provenance. The upstream dependency checkout is restored; the app does not depend on temporary probe patches. Model source revisions and per-file source routing are in `App/Resources/ModelCatalog.json`.

Primary references: [OpenAI Whisper decoder](https://github.com/openai/whisper/blob/main/whisper/decoding.py), [MLX Swift audio repository](https://github.com/Blaizzy/mlx-audio-swift/tree/bf14ae0c26e4e85553dd989571cae29d70fa6735), [quantized Turbo weights](https://huggingface.co/mlx-community/whisper-large-v3-turbo-4bit/tree/0f058d38170d183f9fdee07908f5b515d91793a8), [OpenAI tokenizer assets](https://huggingface.co/openai/whisper-large-v3-turbo/tree/41f01f3fe87f28c78e2fbf8b568835947dd65ed9).

## Verification and remaining acceptance

51 Swift tests pass with zero failures. Removing the ambiguity gate produced two expected failures; restoring it returned the suite to green. Release build and strict signature verification pass with the existing bundle identifier and team. Vocabulary UI was inspected in the running app, and imported audio produced the expected before/after text.

Next acceptance requires human recordings across accents and real user vocabulary, larger dictionaries, ambiguous homophones, repeated names and multiword entries. No tested method justifies a promise of zero incorrect or missed replacements. This build should be evaluated as a conservative improvement, with the uncommon-name milestone still open.
