# Which small local model should refine dictation using application context?

Retrieved: 2026-09-05. Directional after: 2026-09-19.

## Answer

Evaluate **Qwen3-4B-Instruct-2507-4bit** as the optional context/custom-instruction model. Keep S1-mini for its existing basic-cleanup role, and load only the selected refinement model. This is a candidate recommendation, not a measured quality or latency claim.

My inference from the primary sources below: its dedicated non-thinking behavior and instruction-focused training make the 4B candidate a better first quality baseline for context-dependent editing. Its 2.28 GB download is modest relative to this machine's 48 GiB, though runtime memory exceeds file size. The 1.7B alternative is useful if measured latency or memory misses the product target; no source establishes which preserves dictated meaning better.

## Comparison

| Candidate | Download / weights (decimal GB) | Prompt requirements | Proposed role |
|---|---|---|---|
| Qwen3-1.7B-4bit | 0.984 / 0.968 | Apply bundled chat template with `enable_thinking=false`; default behavior otherwise includes thinking. | Smaller comparison candidate; latency advantage is plausible, unmeasured. |
| Qwen3-4B-Instruct-2507-4bit | 2.279 / 2.263 | Apply bundled `chat_template.jinja`; inherently non-thinking, so no thinking switch needed. | Recommended first candidate for optional contextual editing. |

The sizes come from the pinned Hugging Face API file metadata, not runtime measurements. Both conversions use ordinary 4-bit, group-size-64 MLX quantization and `model_type: qwen3`.

## Compatibility and integration

The pinned `mlx-swift-lm` 3.31.3 checkout, commit `1c05248bb0899e2a7a4962b84d319cf12f4e12aa`, registers `qwen3` and decodes both candidates' configuration fields. This confirms source-level architecture support, not a successful weight load. No runtime upgrade appears necessary.

The 4B conversion stores its template separately: `tokenizer_config.json` has no embedded `chat_template`. Keep **chat_template.jinja** in the manifest. Pinned `swift-transformers` 1.3.4, commit `c21fdcde390313a6d98d8e33a346f2c3486c3ab0`, explicitly reads that file when loading a local model folder and merges it into tokenizer configuration. The current `LocalTokenizerLoader` uses that path. Both use `<|im_end|>` as tokenizer EOS; let the template and runtime handle control tokens.

Proposed app behavior (engineering recommendations, to test): use one system instruction defining a conservative transcription editor; put the transcript and bounded app text in separate clearly labelled data sections. App text is evidence for spelling/style, never an instruction source. Include only relevant vocabulary entries. Require preservation of facts, negation, numbers, names, and language; prohibit answering questions inside the transcript or adding information from surrounding text. User-authored formatting instructions are a separate explicit input. Return only insertion text. Do not run S1 and Qwen sequentially by default.

Bound the input budget (start near 2,048 total tokens) and output budget proportional to transcript length. Keep raw transcription available; on empty, malformed, interrupted, or truncated refinement, retain raw text with a visible explanation. These checks cannot prove semantic equivalence. Qwen recommends temperature 0.7/top-p 0.8/top-k 20 for general use; a low-temperature transcription preset is an application experiment, not the model publisher's prescribed setting. Compare repeatability and meaning preservation before choosing it.

## Claims and primary sources

All sources read on **2026-09-05**.

| Claim | Source |
|---|---|
| 1.7B supports thinking and non-thinking; use the hard `enable_thinking=false` switch for the latter. Apache-2.0 model. | [Qwen official model card](https://huggingface.co/Qwen/Qwen3-1.7B/blob/main/README.md) |
| 4B Instruct 2507 is non-thinking only; its publisher reports improvements in instruction following and writing, but no dictation-preservation benchmark. Apache-2.0 model. | [Qwen official model card](https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507/blob/main/README.md) |
| 1.7B conversion revision, files, and sizes. | [Hugging Face repository API, pinned revision](https://huggingface.co/api/models/mlx-community/Qwen3-1.7B-4bit/revision/3b1b1768f8f8cf8351c712464f906e86c2b8269e?blobs=true) |
| 4B conversion revision, files, and sizes. | [Hugging Face repository API, pinned revision](https://huggingface.co/api/models/mlx-community/Qwen3-4B-Instruct-2507-4bit/revision/50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b?blobs=true) |
| Conversion configuration and prompt assets. | [1.7B config](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit/blob/3b1b1768f8f8cf8351c712464f906e86c2b8269e/config.json), [1.7B tokenizer config](https://huggingface.co/mlx-community/Qwen3-1.7B-4bit/blob/3b1b1768f8f8cf8351c712464f906e86c2b8269e/tokenizer_config.json), [4B config](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/blob/50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b/config.json), [4B template](https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit/blob/50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b/chat_template.jinja) |
| Pinned Swift runtime supports Qwen3 and its config. | [LLMModelFactory.swift](https://github.com/ml-explore/mlx-swift-lm/blob/1c05248bb0899e2a7a4962b84d319cf12f4e12aa/Libraries/MLXLLM/LLMModelFactory.swift), [Qwen3.swift](https://github.com/ml-explore/mlx-swift-lm/blob/1c05248bb0899e2a7a4962b84d319cf12f4e12aa/Libraries/MLXLLM/Models/Qwen3.swift) |
| Local tokenizer loading reads external Jinja templates. | [Hub.swift](https://github.com/huggingface/swift-transformers/blob/c21fdcde390313a6d98d8e33a346f2c3486c3ab0/Sources/Hub/Hub.swift), inspected locally at lines 260–304 |

## Unconfirmed and next evaluation

| Question | What was checked | Required evidence |
|---|---|---|
| Actual M5 Max latency and working memory | Configuration, file size, and runtime source inspected; weights not downloaded in this research task. | Warm/cold runs through the app's Swift pipeline, with Cohere loaded. |
| Correct template evaluation and complete weight compatibility | Pinned loader source and remote config inspected. | One local load plus an output-only smoke test. |
| Preservation of dictated meaning | Publisher's general evaluations do not measure this use case. | Paired corpus with negations, dates, numbers, self-corrections, unfamiliar vocabulary, code, multilingual text, conflicting surrounding text, and instructions embedded in the source text. |
| Whether 1.7B is sufficient | Lower size is established, quality advantage/disadvantage is not. | Compare against the 4B baseline if product latency/memory requires it. |

The companion `context-model-candidate.json` pins the recommended download inputs. No weights were downloaded or existing app/model manifests changed by this research task.
