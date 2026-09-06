# Additional local models and truthful ASR controls

Retrieved: 2026-09-05. Directional after: 2026-09-19.

## Answer

The current runtime can plausibly expose five more speech choices without adding a new inference dependency: Whisper Turbo, Whisper Large v3, Whisper Small, Whisper Base, and Qwen3 ASR 0.6B. Turbo and Large already have local vocabulary-probe weights; reusing their directories avoids redundant storage. Small/Base and Qwen 0.6B are compatible by configuration and loader inspection, but need an actual load/transcription check before being described as tested. The tiny Whisper variants offer substantial storage savings; recognition quality and runtime memory cannot be inferred from download size.

For custom instructions, retain Qwen3 4B Instruct as the existing option and optionally offer dense Qwen3 0.6B/1.7B as experimental smaller choices. The pinned MLXLLM factory supports `qwen3`; their local chat templates support disabling thinking. S1-mini remains purpose-built cleanup, not the default executor for arbitrary custom prompts.

Do not expose every field in the generic STT parameters struct. Several are ignored by the specific backends. Qwen's ASR temperature, in particular, divides logits before argmax and is not a stochastic sampler. Parakeet ignores the token limit and temperature entirely.

## Candidate catalog

The machine-readable deliverable is `.build/model-catalog-candidates.json`. It contains full pinned revisions, download file lists, tokenizer overlays, and exact file sizes from Hugging Face's model API. `.build/model-research-metadata.json` preserves API metadata/config responses. Only metadata and the Base/Small safetensors headers were retrieved during this research; no weights were downloaded.

All sizes below are decimal MB of the files actually listed for Quibble, including tokenizer files. They are **download/storage**, not RAM. Source links point to the pinned conversion repos. Read on 2026-09-05.

| App ID / candidate | Download | Weights | Evidence and role |
|---|---:|---:|---|
| `whisper-turbo-vocabulary-4bit` / Whisper Turbo | 468.08 MB | 463.46 MB | [Pinned MLX conversion](https://huggingface.co/mlx-community/whisper-large-v3-turbo-4bit/tree/0f058d38170d183f9fdee07908f5b515d91793a8). Reuse the existing helper folder; 4 decoder layers. Helper use already tested in build 8. |
| `whisper-large-vocabulary-4bit` / Whisper Large v3 | 882.08 MB | 877.69 MB | [Pinned MLX conversion](https://huggingface.co/mlx-community/whisper-large-v3-4bit/tree/d179def5a85bbcc230fae176f7bd71dd57cb8f45). Reuse existing probe folder; 32 decoder layers. More compute than Turbo is an architecture-based expectation, not a fresh benchmark. |
| `whisper-small-4bit` / Whisper Small | 143.30 MB | 139.11 MB | [Pinned MLX conversion](https://huggingface.co/mlx-community/whisper-small-4bit/tree/1ac90abbb1b2f53863bfd2a483a3c31d792c3e5b). Config and tensor header match the existing adapter; 80 mel bins, 768 hidden width. Untested primary candidate. |
| `whisper-base-4bit` / Whisper Base | 46.40 MB | 42.22 MB | [Pinned MLX conversion](https://huggingface.co/mlx-community/whisper-base-4bit/tree/50e8af4ebba739430129a6ab975a9b368a9a2fc4). Config and tensor header match the adapter; 80 mel bins, 512 hidden width. Untested primary candidate. |
| `qwen3-asr-06b-4bit` / Qwen3 ASR 0.6B | 712.78 MB | 708.24 MB | [Pinned MLX conversion](https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-4bit/tree/313d850181767edf09f00a9c289becca70e58cd0). Same `qwen3_asr` loader family as current 1.7B. Model config declares 30 language names. |
| `qwen3-0.6b-4bit` / Qwen3 0.6B | 351.38 MB | 335.45 MB | [Pinned MLX conversion](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/tree/73e3e38d981303bc594367cd910ea6eb48349da8). Small optional instruction executor; exact prompt following unmeasured. |
| `qwen3-1.7b-4bit` / Qwen3 1.7B | 984.01 MB | 968.08 MB | [Pinned MLX conversion](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit/tree/3b1b1768f8f8cf8351c712464f906e86c2b8269e). Optional middle-size instruction executor; exact prompt following unmeasured. |

The conversion model cards declare Apache-2.0. This describes their published metadata, not a legal assessment. Whisper adapter source uses the upstream MIT license separately.

### Whisper tokenizer compatibility

The MLX conversion directories supply `multilingual.tiktoken`, but Quibble's `AutoTokenizer` path needs Transformers-format tokenizer assets. Keep the existing model-specific overlay mechanism. The candidate file uses:

| Model | OpenAI tokenizer repo | Pinned revision |
|---|---|---|
| Base | [openai/whisper-base](https://huggingface.co/openai/whisper-base/tree/e37978b90ca9030d5170a5c07aadb050351a65bb) | `e37978b90ca9030d5170a5c07aadb050351a65bb` |
| Small | [openai/whisper-small](https://huggingface.co/openai/whisper-small/tree/973afd24965f72e36ca33b3055d56a652f456b4d) | `973afd24965f72e36ca33b3055d56a652f456b4d` |
| Large v3 | [openai/whisper-large-v3](https://huggingface.co/openai/whisper-large-v3/tree/06f233fe06e710322aca913c1bc4249a0d71fce1) | `06f233fe06e710322aca913c1bc4249a0d71fce1` |
| Turbo | [openai/whisper-large-v3-turbo](https://huggingface.co/openai/whisper-large-v3-turbo/tree/41f01f3fe87f28c78e2fbf8b568835947dd65ed9) | `41f01f3fe87f28c78e2fbf8b568835947dd65ed9` |

Base/Small use vocabulary size 51,865; v3/Turbo use 51,866. Their tokenizer assets should not be indiscriminately shared. The existing Large vocabulary probe used Turbo tokenizer assets; both are v3, but the new candidate pins Large's own generation/tokenizer assets. The parent implementation should preserve working installed assets or explicitly validate a changed overlay.

The vendored loader's `WhisperConfig.init(from:)` supports the `n_audio_*`/`n_text_*` layout, and `WhisperModel.sanitizeMlxWhisper` remaps `.blocks.` keys, quantized embeddings, and affine layers. Header reads confirmed Base/Small convolution layout `[out, kernel, in]`, matching this path. Existing older `*-mlx` repos that only provide `weights.npz` are not direct candidates for this loader.

## Backend controls actually honored

Primary source: `Inference/.build/checkouts/mlx-audio-swift`, commit `bf14ae0c26e4e85553dd989571cae29d70fa6735`, read 2026-09-05. Paths below are relative to that checkout's `Sources/MLXAudioSTT`. Whisper refers to Quibble's vendored source derived from the same revision. The APIs were read directly, including the token-selection code, rather than inferred from parameter names.

| Backend | Effective controls | Ineffective, unavailable, or qualified controls | Exact source |
|---|---|---|---|
| Cohere | Max generated tokens; temperature (0 = greedy, positive = categorical); forced language; chunk duration; minimum chunk duration; verbose printing | Top-p/top-k are copied but not used by its sampler. No repetition penalty, beam search, KV quantization or confidence in the current generation path. Punctuation is hardcoded on; timestamps off. | `Models/CohereTranscribe/CohereTranscribe.swift`: `generate`, `prepareGenerationContext`, `sample`; `CohereTranscribeTokenizer.swift` |
| Parakeet | Chunk duration; public `computeDType` (default bfloat16, float32 alternative) | Token limit, temperature, top-p/top-k, min-chunk and repetition controls ignored. Language only labels output; it does not force the recognizer. `maxSymbols` is read-only model config. Decoder trace callback/types are internal, so unavailable without patching the dependency. | `Models/Parakeet/ParakeetModel.swift`: properties, `generate`, `decodeTDTEncoded` |
| Qwen3 ASR | Max generated tokens; language; context prefix; chunk/min-chunk; repetition penalty and its context window | Temperature is accepted but only rescales logits before argmax, leaving ordering unchanged in normal finite arithmetic. No top-p/top-k or generic KV fields used. Repetition penalty !=1 disables the default degeneracy backstop, so avoid presenting it as free quality improvement. | `Models/Qwen3ASR/Qwen3ASR.swift`: `generateSingleChunk` lines1220–1345, `generate` lines1358–1439 |
| Whisper adapter | Max tokens **per 30-second chunk**, limited by 448-position decoder minus prompt; temperature (greedy/categorical); explicit language; bounded vocabulary prompt | Generic chunk duration/min-chunk ignored: fixed 30-second windows. No top-p/top-k, beam search, repetition penalty, confidence, true word timestamps or KV controls. Language auto-detection is not implemented as a distinct pass despite the upstream README comment. | `Inference/Sources/QuibbleWhisper/WhisperModel.swift`: `generate`, `transcribeChunk`, `sample`; `WhisperTokenizer.swift`: `buildPromptTokens` |

Defaults should stay greedy, language English as before, token cap 512 for Cohere/Qwen and a decoder-bounded cap for Whisper. Bounds are product choices and should be labeled caps, not accuracy controls. A smaller cap can truncate valid speech. Keep arbitrary ASR context off in the main dictation pipeline: primary Whisper hints stay empty, and the already guarded vocabulary helper remains responsible for saved names. The helper currently forces English, so global language controls do not by themselves validate multilingual vocabulary correction.

Cohere's explicit language map is `en fr de es it pt nl pl el ar ja zh vi ko`. Unknown input falls back to English. Qwen's candidate config declares Chinese, English, Cantonese, Arabic, German, French, Spanish, Portuguese, Indonesian, Italian, Korean, Russian, Thai, Vietnamese, Japanese, Turkish, Hindi, Malay, Dutch, Swedish, Danish, Finnish, Polish, Czech, Filipino, Persian, Greek, Romanian, Hungarian, Macedonian. Validate against model-supported names/aliases rather than allowing arbitrary text that appears accepted. Whisper can map the language codes in its pinned tokenizer; require a supported explicit language until an actual language-detection pass is implemented.

## What a Developer tab can truthfully show

| Data | Availability and limitation | Source, read 2026-09-05 |
|---|---|---|
| Raw ASR / after-vocabulary / final text | Already available from Quibble pipeline; useful stage comparison without model changes. | `Inference/Sources/QuibbleInference/LocalInference.swift`, build9 baseline; `InferenceResult` |
| Audio length, stage wall times, load time | Already measured in Quibble. Real-time factor can be computed as ASR seconds / audio seconds, explicitly separate from total pipeline latency. | Same `LocalInference.swift` |
| Prompt/generated/total token counts | Cohere, Qwen, Whisper fill these. Parakeet leaves STTOutput defaults at zero; UI should say unavailable instead of claiming zero tokens. | Upstream `Models/GLMASR/STTOutput.swift` and each backend's output initializer |
| Generated tokens/sec | Cohere/Qwen/Whisper populate it, but backend accounting differs. Do not rank different architectures as though this is a common benchmark; wall-time on the same audio is better. | Same output initializers |
| Segments | Parakeet returns sentence spans derived from decoded token alignment. Qwen returns audio chunk ranges. Whisper returns fixed-window ranges. Label Qwen/Whisper as chunk ranges, never word timestamps. | `Models/Nemo/NemoAlignment.swift`, Qwen/Whisper `generate` |
| Language | Cohere/Whisper primarily return forced language. Parakeet returns supplied metadata. Qwen may parse detected language with no forced language. Distinguish requested language from detected language. | Each backend's `generate`/parser |
| Memory | MLX active/cache/peak counters available. MLX allocations are not process RSS; historical global peak requires careful reset semantics. Download bytes are separate. | Quibble `memoryUsage()` / MLX `Memory` |
| Confidence/logprobs/token IDs | No calibrated confidence, token logprobs or token-ID sequence is exposed by these synchronous STTOutput paths. Internally generated tokens are discarded. Do not invent percentages. | `STTOutput.swift`; backend token loops |
| Inference configuration | Engine and pinned revision, requested/effective controls, sampling algorithm, limits, vocabulary enabled/count, model loading state. Supported without extra compute. | Catalog and generation call sites |

A developer-only transcript export should require an explicit action and distinguish local diagnostics from automatic telemetry. Keep tracing bounded and in memory by default; no need for continuous polling, repeated GPU inference, or retaining audio.

## Instruction model controls

Primary source: `Inference/.build/checkouts/mlx-swift-lm`, commit `1c05248bb0899e2a7a4962b84d319cf12f4e12aa`, read 2026-09-05. `Libraries/MLXLLM/LLMModelFactory.swift` registers `qwen3` and `qwen2`. `Libraries/MLXLMCommon/Evaluate.swift` implements `GenerateParameters` and samplers.

MLXLLM actually supports max tokens, temperature, top-p/top-k/min-p, repetition/presence/frequency penalties and their windows, prefill step size, and KV cache controls. Unlike Qwen's **ASR** path, its text-model sampler does use these filters when temperature is nonzero. Show only the small stable subset first; KV quantization should be a separately tested experiment, not a default optimization.

For Qwen3 0.6/1.7, pass `additionalContext: ["enable_thinking": false]` through Quibble's existing local tokenizer adapter. The [Qwen3 model card](https://huggingface.co/Qwen/Qwen3-0.6B) documents this hard switch and distinguishes it from a `/no_think` soft prompt. Validate stop reason and reject empty or truncated results. Keep existing greedy text cleanup as a measured Quibble choice; upstream chat recommendations are not evidence of best dictation formatting quality.

## Unconfirmed / next checks

| Question | What was checked | Remaining proof |
|---|---|---|
| Do Small/Base/Qwen0.6 actually transcribe through the shipped binary? | API revisions, full file manifests/config, compatible model factories; Base/Small tensor headers | One offline smoke transcription per new backend variant, then real voice/accent/negative fixtures before recommending |
| Are smaller instruction models good enough for custom workflows? | Dense Qwen3 architecture and tokenizer compatibility | Same prompt fixtures including names, code, repeated phrases, empty input, and incomplete output; compare against existing4B |
| Is quality preserved at lower memory? | Exact weight storage measured only | Fresh warm/cold wall-time and MLX active/peak plus process RSS on same audio; no RAM claims from weights |
| Can confidence be shown? | Current output types and generation implementation | Requires new backend instrumentation and calibration; not available now |
| Can Whisper auto-detect language? | Read actual prompt construction and generation | Implement and test an audio-conditioned language-token pass; no verified auto mode now |
| Are all custom workflow orders sensible? | Existing audio→vocabulary→text dependencies | ASR stays first; text steps ordered and optionally skipped; saved-word preservation after each generative step; reject invalid workflows rather than silently doing something else |
