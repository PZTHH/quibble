# SpellMapper feasibility and first isolated evaluation

Retrieved and evaluated: 2026-09-05. Directional after: 2026-10-05.

## Decision

**Technically feasible and much smaller than the generic cleanup models, but the first direct-candidate evaluation does not pass Quibble's quality requirements. Do not port or ship it yet.** A two-thread CPU harness runs its neural forward pass in approximately 20 ms on this Mac. It recovers some difficult names, but misses others and sometimes changes unrelated text or consumes the wrong span. [Main evidence](competitor-probes/spellmapper-name-results.json), [untuned additional cases](competitor-probes/spellmapper-additional-results.json), measured 2026-09-05.

SpellMapper is specifically trained for an ASR hypothesis plus candidate vocabulary. Its output classifies characters as belonging to one of ten candidates or none; it does not generate arbitrary replacement text. The official pipeline also includes learned n-gram candidate retrieval and alignment filtering. These are useful architectural differences from a generic LLM, not guarantees of rare-name quality. [NVIDIA documentation](https://docs.nvidia.com/nemo-framework/user-guide/24.07/nemotoolkit/nlp/spellchecking_asr_customization.html), read 2026-09-05.

## Available artifact, size, and license

The NVIDIA documentation links to one English checkpoint repository found in Hugging Face model search: `bene-ges/spellmapper_asr_customization_en`. Snapshot revision: **10fd0674ab417c2337f236308005c6a598fd4a1e**. Its model card declares **CC BY 4.0**. The NeMo implementation carries **Apache 2.0** notices; these are separate licenses. [Pinned model card](https://huggingface.co/bene-ges/spellmapper_asr_customization_en/blob/10fd0674ab417c2337f236308005c6a598fd4a1e/README.md), [source license](https://github.com/NVIDIA-NeMo/Speech/blob/265bd739c77c86ac423942d650eed6fc232e4fc6/LICENSE), read 2026-09-05.

| Artifact | Verified size | Pinned direct download |
|---|---:|---|
| Checkpoint archive | 268,216,320 bytes | [training_10m_5ep.nemo](https://huggingface.co/bene-ges/spellmapper_asr_customization_en/resolve/10fd0674ab417c2337f236308005c6a598fd4a1e/training_10m_5ep.nemo) |
| Learned n-gram mappings | 113,870,348 bytes | [replacement_vocab_filt.txt](https://huggingface.co/bene-ges/spellmapper_asr_customization_en/resolve/10fd0674ab417c2337f236308005c6a598fd4a1e/replacement_vocab_filt.txt) |
| Dummy-candidate phrase pool | 93,015,503 bytes | [big_sample.txt](https://huggingface.co/bene-ges/spellmapper_asr_customization_en/resolve/10fd0674ab417c2337f236308005c6a598fd4a1e/big_sample.txt) |

Sizes come from the [pinned Hugging Face tree API](https://huggingface.co/api/models/bene-ges/spellmapper_asr_customization_en/tree/10fd0674ab417c2337f236308005c6a598fd4a1e), read 2026-09-05; a local copy is in [hf-tree.json](competitor-probes/spellmapper/hf-tree.json). The checkpoint SHA-256 was independently verified as `0295a34a5522257bdae22c714ca990c5e5a5eb444e82597944785fcfae93516d`. Retrieval resources were not downloaded for this probe.

The uncompressed `.nemo` tar contains a 267,962,485-byte PyTorch state dictionary, BERT configuration, tokenizer vocabulary, label map, and model YAML. Embedded configuration specifies six BERT layers, hidden size 768, twelve attention heads, intermediate size 3072, 11 segment types, vocabulary 30,522, and 512 positional embeddings. Training used the TinyBERT 6L/768D base. Loaded parameters total **66,978,827**, occupying **267,915,308 bytes in FP32**. [Extracted config](../Models/spellmapper-candidate/1497138a953d4ba3aaec7f5db189c7af__encoder_config.json), [model YAML](../Models/spellmapper-candidate/model_config.yaml), [measured metadata](competitor-probes/spellmapper-name-results.json), inspected 2026-09-05.

## Minimal runtime and porting feasibility

The isolated harness needs PyTorch and Transformers; it does not import NeMo, Lightning, Hydra, or training data loaders. It loads the bundled vocabulary into `BertTokenizer`, executes the same BERT weights once for character tokens and again for subwords, gathers matching subword states, concatenates both representations, and applies a 1536-to-11 linear head. Span probabilities use softmax after averaging logits. The inspected upstream inference method explicitly falls back to CPU when CUDA is absent. [Model forward and inference source](https://github.com/NVIDIA-NeMo/Speech/blob/265bd739c77c86ac423942d650eed6fc232e4fc6/nemo/collections/nlp/models/spellchecking_asr_customization/spellchecking_model.py), read 2026-09-05.

Engineering inference: an MLX or Core ML port is plausible because the forward computation uses ordinary encoder attention, layer normalization, GELU, gather, concatenation, and a linear head. It is not a drop-in autoregressive model conversion. A port must preserve 11 segment embeddings, character/subword alignment, both encoder passes, pooling, and deterministic span selection, then prove numerical and output parity. Half-precision parameters would be approximately 134 MB before runtime overhead; no reduced-precision accuracy or native runtime memory was measured. No ready-made official MLX/Core ML artifact was found in the inspected sources. [Input builder](https://github.com/NVIDIA-NeMo/Speech/blob/265bd739c77c86ac423942d650eed6fc232e4fc6/nemo/collections/nlp/data/spellchecking_asr_customization/bert_example.py), [forward source](https://github.com/NVIDIA-NeMo/Speech/blob/265bd739c77c86ac423942d650eed6fc232e4fc6/nemo/collections/nlp/models/spellchecking_asr_customization/spellchecking_model.py), read 2026-09-05.

Full retrieval adds NumPy/Numba-based utilities and an index built from the saved dictionary and n-gram mapping file. The phrase pool supplies filler candidates. The official script splits long input into overlapping windows and uses dynamic-programming alignment as an additional filter. Those costs and recall effects were deliberately excluded from this first neural screening. [Inference script](https://github.com/NVIDIA-NeMo/Speech/blob/265bd739c77c86ac423942d650eed6fc232e4fc6/examples/nlp/spellchecking_asr_customization/run_infer.sh), [retrieval/filter utilities](https://github.com/NVIDIA-NeMo/Speech/blob/265bd739c77c86ac423942d650eed6fc232e4fc6/nemo/collections/nlp/data/spellchecking_asr_customization/utils.py), read 2026-09-05.

## What was actually evaluated

The checkpoint is under `Models/spellmapper-candidate`, outside the app model catalog. The runtime is isolated in `.build/spellmapper-venv`. Model loading uses `torch.load(..., weights_only=True)` after rejecting unsafe tar paths and links; no unrestricted pickle load or `extractall` is used. BERT and classifier weights load strictly; the historical position-ID buffer is intentionally omitted. Full NeMo execution parity has not been established. [Harness](competitor-probes/spellmapper/probe.py), inspected and executed 2026-09-05.

Preferred entries were passed directly, with no user-authored mishearings. Ten candidate slots were filled with a fixed dummy list, and every one-to-three-word span was scored. Thresholds **0.5, 0.7, 0.8, 0.9, 0.95, 0.99** and primary threshold **0.9** were fixed before results were read. The additional 24 cases were evaluated without tuning. The upstream length penalty, banned replacement rules, and overlap resolution were retained. This is a **direct neural candidate experiment**, not the complete official retrieval/DP pipeline. [Method and reproduction](competitor-probes/spellmapper/README.md).

| Threshold | Main 18 exact | Main positive / 9 | Main negatives changed / 9 | Additional 24 exact | Additional positive / 12 | Additional negatives changed / 12 |
|---|---:|---:|---:|---:|---:|---:|
| 0.5 | 10 | 6 | 5 | 15 | 4 | 1 |
| 0.7 | 11 | 6 | 4 | 14 | 3 | 1 |
| 0.8 | 10 | 5 | 4 | 12 | 1 | 1 |
| 0.9, preregistered primary | 9 | 4 | 4 | 12 | 1 | 1 |
| 0.95 | 9 | 4 | 4 | 13 | 1 | 0 |
| 0.99 | 9 | 3 | 3 | 12 | 0 | 0 |

Evidence: [main results](competitor-probes/spellmapper-name-results.json), [additional results](competitor-probes/spellmapper-additional-results.json), measured 2026-09-05. Fixtures are hand-authored ASR-like text, not a human-audio benchmark.

Raw confidence for Shivon → Siobhan was 0.959, Neve → Niamh 0.984, and Ashling → Aisling 0.978. Length penalties lowered the first two below the primary threshold. Searsha → Saoirse was near zero. At lower threshold, `Call` could become Caoimhe. On the additional set, `They may join us on Friday` became `They Mae join us on Friday` even at 0.9, and a Dearbhla substitution consumed the preceding `to`. [Per-span probabilities and outputs](competitor-probes/spellmapper-name-results.json), [additional evidence](competitor-probes/spellmapper-additional-results.json), measured 2026-09-05.

Median forward latency was **19.7 ms** and **19.6 ms** across the two corpora, using two CPU threads and no GPU. Model load, including checksum verification and assembly, took about **0.71–0.73 s**. Peak Python process RSS was about **1.04 GB** and includes imports, checkpoint loading, and construction; it is not a native app memory estimate. [Recorded metadata](competitor-probes/spellmapper-name-results.json), [additional metadata](competitor-probes/spellmapper-additional-results.json), measured 2026-09-05.

## Remaining questions

- Full n-gram retrieval and DP alignment may reduce false edits or incorrect boundaries; their measured end-to-end quality and load remain unknown.
- Candidate filler/order sensitivity, accents, larger dictionaries, long utterances, and real human speech need testing before any production decision.
- This checkpoint is English-only, and the current source marks its NeMo classes deprecated. That does not prevent this standalone CPU run, but it argues for pinning and owning any eventual inference port.
- The current evidence supports a small specialized model as an architectural direction, **not this checkpoint as an adequate completed solution**.

No App or QuibbleCore source was changed.
