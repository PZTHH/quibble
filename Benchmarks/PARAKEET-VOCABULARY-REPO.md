# Parakeet: vocabulary at speech decoding time

Retrieved: 2026-09-05. Directional after: 2026-10-05.

## Finding

NVIDIA NeMo has an implemented, documented phrase-boosting path for Parakeet TDT. It changes token scores during decoding, uses a user phrase list, and requires neither ASR retraining nor an additional neural language model. Quibble's pinned Swift adapter has not ported that capability. A small local prototype is therefore warranted; a model change alone would not enable it.

This is a stronger starting point for an ASR-side vocabulary implementation than an arbitrary dictionary prefix. It is not a guarantee that any saved name will be recognized. The paper explicitly discusses degradation of words outside the dictionary under greedy decoding.

## Primary evidence

All sources read 2026-09-05.

| Claim | Exact source |
|---|---|
| GPU-PB supports RNN-T/TDT, CTC, and AED; greedy and beam decoding; phrase lists; no retraining | [NVIDIA word boosting documentation](https://docs.nvidia.com/nemo/speech/nightly/asr/asr_customization/word_boosting.html) |
| TDT greedy decoder preserves the acoustic blank/nonblank decision, biases only nonblank token choices, and leaves duration logits separate | [NeMo TDT decoder at 60ce9407ef60a3327ffaf2c15931b9b3b834afc2](https://github.com/NVIDIA-NeMo/NeMo/blob/60ce9407ef60a3327ffaf2c15931b9b3b834afc2/nemo/collections/asr/parts/submodules/transducer_decoding/tdt_label_looping.py#L426) |
| Trie uses failure links, deeper token rewards, and refunds unfinished phrase preference on backoff; completed phrases retain preference | [Context graph](https://github.com/NVIDIA-NeMo/NeMo/blob/60ce9407ef60a3327ffaf2c15931b9b3b834afc2/nemo/collections/asr/parts/context_biasing/context_graph_universal.py), [compiled graph storage](https://github.com/NVIDIA-NeMo/NeMo/blob/60ce9407ef60a3327ffaf2c15931b9b3b834afc2/nemo/collections/asr/parts/context_biasing/boosting_graph_batched.py) |
| Native configuration includes context score, depth scaling, fusion weight, unknown-token score and case-insensitive BPE variants | [BoostingTreeModelConfig](https://github.com/NVIDIA-NeMo/NeMo/blob/60ce9407ef60a3327ffaf2c15931b9b3b834afc2/nemo/collections/asr/parts/context_biasing/boosting_graph_batched.py#L54) |
| Greedy phrase boosting can degrade unrelated words; beam and unknown-token score are discussed mitigations | [TurboBias paper, §II-C](https://arxiv.org/html/2508.07014v2#S2.SS3) |
| Swift public `generate` has no vocabulary argument, and the model's decoder layers and decode methods are internal/private | [ParakeetModel.swift at bf14ae0c26e4e85553dd989571cae29d70fa6735](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/Parakeet/ParakeetModel.swift) |
| Swift serial TDT chooses token and duration inside a compiled MLX function; token bias belongs before token argmax | [Compiled TDT step](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/Parakeet/ParakeetModel.swift#L894) |
| CTC word spotting is a separate option and needs a CTC output path; it is not the same as TDT phrase boosting | [NVIDIA CTC-WS documentation](https://docs.nvidia.com/nemo/speech/nightly/asr/asr_customization/word_boosting.html#ctc-ws-context-biasing-word-boosting-without-external-lm) |

## Mac implementation boundary

NVIDIA's optimized implementation uses its GPU language-model infrastructure and optional Triton/CUDA acceleration. Quibble cannot enable that kernel by passing an option to MLX. The graph scoring algorithm can be implemented in Swift/MLX; the paper's throughput results on an RTX A6000, batch size 32, are not Mac performance measurements.

A production port should expose a maintained decoding configuration/API in the pinned package, tokenize with the checkpoint's actual SentencePiece model, cache the graph when vocabulary changes, preserve blank and duration handling, and bound memory for large dictionaries. An untracked modification inside an SPM checkout is not a shipping integration.

## Local probe

`competitor-probes/parakeet-bias/` contains a reversible, benchmark-only patch and runner. The probe executes the pinned NVIDIA Python `ContextGraph` without modifying its algorithm; optional visualization/type imports are stubbed. It exports dense scores/transitions for a small dictionary, then uses a narrow MLX hook at the serial TDT token selection step. Canonical and lowercase spellings are separate paths; this is not the full newer variable-BPE implementation.

No extra neural weights, cleanup, aliases, or app context are used. The runner denies network and processes generated local audio sequentially. Dense graph tables and JSON are measurement scaffolding, not the proposed production representation. See [quality evaluation](VOCABULARY-QUALITY-EVALUATION.md) for results and limitations.

## Unconfirmed / next decision

- Whether beam decoding or variable-BPE paths give enough additional recall to justify a maintained Swift port.
- Real human dictation accuracy, accents, and the user's exact uncommon-name case.
- False-positive rate with hundreds/thousands of saved terms, including names absent from the utterance.
- Whether a shared phrase-scoring component can improve Cohere as well; its decoder has a different EOS treatment and needs a separate experiment.
