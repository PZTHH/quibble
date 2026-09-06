# Cohere Transcribe: repository-level vocabulary options

Retrieved: 2026-09-05. Directional after: 2026-10-05.

## Finding

**There is no documented ready-made personal-vocabulary option in the inspected Cohere Transcribe interfaces. There are usable decoder-level hooks for implementing and testing one ourselves.** Cohere's representative explicitly confirmed the missing guidance-word option in April; the current Transformers processor and Quibble's current MLX Swift adapter still expose task/language control rather than vocabulary hints. [Cohere discussion #32](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026/discussions/32), [current processor](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/models/cohere_asr/processing_cohere_asr.py#L58), [Swift adapter](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift#L311), read 2026-09-05.

The most relevant next experiment is **phrase-aware biasing or bounded hypothesis rescoring inside Cohere's decoder, reusing its existing audio encoder**. This is an engineering proposal, not an existing proven feature. It could avoid keeping another model resident, but quality and decoder latency must be measured before adoption.

## Snapshots and access

| Component | Pinned snapshot inspected |
|---|---|
| Official model card | [CohereLabs/cohere-transcribe-03-2026, b1eacc2686a3d08ceaae5f24a88b1d519620bc09](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026/blob/b1eacc2686a3d08ceaae5f24a88b1d519620bc09/README.md) |
| Native Transformers implementation | [huggingface/transformers, f62dc9bf2c90353b442a56e74391fbb8c689b55e](https://github.com/huggingface/transformers/tree/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/models/cohere_asr) |
| Quibble's actual MLX Swift dependency | [Blaizzy/mlx-audio-swift, bf14ae0c26e4e85553dd989571cae29d70fa6735](https://github.com/Blaizzy/mlx-audio-swift/tree/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe) |
| Python MLX comparison | [Blaizzy/mlx-audio, 41537ec5cf79bcf731a0dd6749cac12ab554a691](https://github.com/Blaizzy/mlx-audio/blob/41537ec5cf79bcf731a0dd6749cac12ab554a691/mlx_audio/stt/models/cohere_asr/cohere_asr.py) |

All snapshots were read on 2026-09-05. The Swift repository's current main resolved to Quibble's existing pin, so an ordinary dependency update does not reveal a newer vocabulary implementation. The official Hugging Face model card was accessible, but raw custom Python implementation files returned HTTP 401 because that repository gates file access. They were not retrieved through mirrors or bypassed. Findings about Python internals therefore rely on the public native Transformers implementation, not an assertion that the gated legacy remote-code implementation is identical.

## What the official discussion and current APIs establish

| Mechanism | Evidence | Meaning for Quibble |
|---|---|---|
| Guidance words / name list | Cohere Labs member `ekagra-ranjan` answered on April 9 that the option was not available. [Discussion #32](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026/discussions/32) | Direct primary confirmation, rather than inferring solely from absent parameters. |
| Later word-boosting request | June 24 request remains unanswered in the public discussion payload. [Discussion #43 API](https://huggingface.co/api/models/CohereLabs/cohere-transcribe-03-2026/discussions/43) | No later implementation announcement was found there. |
| Processor `text=` | Tokenized text becomes `labels`; decoder inputs are independently built from language and punctuation controls. [Processor lines 108–115](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/models/cohere_asr/processing_cohere_asr.py#L108) | This is a training-target path, not a vocabulary or context prompt. |
| Decoder prompt | Fixed special-token sequence includes start-of-context, start-of-transcript, language, punctuation, no-ITN, no-timestamps, no-diarization. [Prompt builder](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/models/cohere_asr/processing_cohere_asr.py#L58) | A token named start-of-context does not prove the model was trained to interpret an arbitrary spelling list. |
| Decoder prefix | `decoder_input_ids` and cached decoder states are accepted by forward/generation. [Model source](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/models/cohere_asr/modeling_cohere_asr.py#L546) | Technically possible to seed a continuation. No documented separation between arbitrary dictionary text and transcript output; requires an experiment. |

Read dates for every row: 2026-09-05. These findings concern the March multilingual checkpoint and inspected implementation, not every future Cohere release.

## Useful generic Transformers hooks

`CohereAsrForConditionalGeneration` inherits `GenerationMixin`. Its output includes logits, encoder outputs, and past key/value states. The mixin accepts custom `logits_processor`, `sequence_bias`, `prefix_allowed_tokens_fn`, and beam-search generation parameters. Those are real library facilities, but they are **generic decoding controls**, not evidence that Cohere has trained or validated a custom-name subsystem. [Cohere inheritance/forward](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/models/cohere_asr/modeling_cohere_asr.py#L546), [generate API](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/generation/utils.py#L2388), read 2026-09-05.

`SequenceBiasLogitsProcessor` adds a bias to a sequence's final token when the already-decoded suffix matches the preceding tokens. Single-token entries are biased everywhere. Consequently, a full multi-token name may receive no help entering its first token. The source recommends considering prefixes and beam methods; it also warns that tokenization differs with a leading space. [Exact processor](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/generation/logits_process.py#L1211), read 2026-09-05.

Inference: a trie that tracks preferred phrase prefixes is more appropriate to investigate than boosting every token appearing anywhere in the user's dictionary. Keep the unchanged hypothesis eligible, cap cumulative preference, and measure false name insertions. Hard token constraints force an allowed continuation and should not be mistaken for a confidence-sensitive vocabulary hint. [Prefix constraint implementation](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/generation/logits_process.py#L1484), read 2026-09-05.

## Exact integration points in Quibble's Swift adapter

1. **Before token choice:** `generateSingleChunk` obtains `context.logits`, then immediately calls `sample` at line 427. The equivalent streaming loop does the same. A bounded bias processor belongs here, before selection. [Decode loop](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift#L407).
2. **Reuse audio features:** `encodeAndPrefill` computes the encoder output, optional bridge projection, decoder prompt, and KV cache. Candidate branches could share the audio-side representation while maintaining separate decoder history. [Prefill](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift#L640).
3. **Teacher-forcing precedent:** internal `streamingDecodeTokenIds` consumes `confirmedTokenIds`, updates decoder state and logits, then resumes normal generation. This is an existing pattern for forced-prefix or likelihood-scoring probes. It is not a vocabulary feature. [Confirmed-prefix loop](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift#L789).
4. **Tokenize saved spellings:** `CohereTranscribeTokenizer.encode(text:)` is public and supports ordinary SentencePiece text. The model's tokenizer property is private, and encoder/decoder/head access is internal. This calls for a narrowly maintained package change or upstream API rather than an external wrapper pretending to have access. [Tokenizer](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribeTokenizer.swift#L27), [access levels](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift#L279).

All four points inspected 2026-09-05. Current sampling is argmax at zero temperature or categorical sampling otherwise; no beam implementation or vocabulary callback is exposed. Python MLX likewise constructs its fixed language/punctuation prompt internally and runs its own generation loop. [Swift sampling](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift#L721), [Python MLX generation](https://github.com/Blaizzy/mlx-audio/blob/41537ec5cf79bcf731a0dd6749cac12ab554a691/mlx_audio/stt/models/cohere_asr/cohere_asr.py#L857).

## Fine-tuning

The native model exposes differentiable logits and a labels-based loss, so fine-tuning is technically supported at the model level. A merged Transformers change fixed its double label-shift training loss; use a pinned version with the fix for any training experiment. [Merged PR #46895](https://github.com/huggingface/transformers/pull/46895), [fixed source](https://github.com/huggingface/transformers/blob/f62dc9bf2c90353b442a56e74391fbb8c689b55e/src/transformers/models/cohere_asr/modeling_cohere_asr.py#L638), read 2026-09-05.

I did not find an official turnkey personal-vocabulary adapter or released training recipe in the inspected model card and discussion. The official fine-tuning-guide request remains open. [Discussion #9](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026/discussions/9), read 2026-09-05. LoRA or training Cohere to condition on an explicit dictionary would therefore be a separate model-development project, not a quick setting; it also conflicts with treating a single added word as sufficient training data.

## Recommended bounded experiment

Engineering recommendation: start with an opt-in benchmark-only decoder bias hook, using the installed quantized Cohere weights, cached encoder output, no extra language model, and a fixed modest bias grid. Test preferred words without aliases; include one-word and larger dictionaries, absent-name negatives, ordinary-word collisions, sentence-initial/mid-sentence tokenization, and phrase completion. Record baseline and biased token scores, exact transcript preservation, added names, latency, and memory. If greedy prefix bias fails, a small beam or candidate-versus-original rescoring is the next measured step, rather than a stronger unconditional bias.

Unconfirmed: whether any such hook meets Quibble's recall/false-positive requirements; whether a small beam's quality improvement justifies its device load; whether arbitrary text inserted before the fixed task prefix is usefully understood by this checkpoint. No new weights were downloaded and no production files were edited for this research.
