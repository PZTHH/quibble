# Quantized Cohere feasibility

Retrieved: 2026-09-05. Directional after: 2026-10-05.

Quibble's pinned MLX audio runtime supports affine quantized Cohere weights, including the 4-bit checkpoint derived from the FP16 checkpoint already in use. This is a community conversion, not a separate official Cohere release.

## Sources

| Claim | Primary source, read 2026-09-05 |
|---|---|
| The candidate uses 4-bit affine quantization, group size 64 | [Pinned model card](https://huggingface.co/beshkenadze/cohere-transcribe-03-2026-mlx-4bit/blob/104bc4391b5b1a12b040859793d7148525e1a08c/README.md), [configuration](https://huggingface.co/beshkenadze/cohere-transcribe-03-2026-mlx-4bit/blob/104bc4391b5b1a12b040859793d7148525e1a08c/config.json) |
| The publisher reports a Kaldi → Khaldi spelling regression on one sample | Same pinned model card; this is the publisher's observation, not a broad accuracy evaluation |
| Our runtime configures quantized modules before loading weights and validates their inventory | [Cohere loader at the pinned runtime revision](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribe.swift) |

The local safetensors headers describe approximately 4.132 GB of FP16 weight data versus 1.505 GB in the 4-bit checkpoint: about 64% less. The latter still contains some FP16 tensors and quantization metadata, so its size is not exactly one quarter of FP16. This is weight storage, not whole-app memory. S1-mini remains BF16 at about 1.503 GB for this comparison.

The candidate is pinned in `cohere-4bit-model.json` and `Models.lock.json`, with a local download receipt in `Models/cohere-4bit`. Build 3 defaults to 4-bit, with FP16 retained in the speech-model picker. The running GUI showed the 4-bit selection, loaded the models successfully, and retained Microphone and Accessibility permissions.

## Local comparison

Completed 24 runs: four clips × two precisions × three runs. Both use the same signed app executable and unchanged BF16 S1-mini. Network access was denied for each process. FP16 was rerun in this session. The 4-bit candidate was initially supplied through an isolated model-root folder, so its JSON engine label is `cohere`; the folder and pinned artifact identify precision.

| Clip | FP16 peak MLX | 4-bit peak MLX | FP16 warm total | 4-bit warm total |
|---|---:|---:|---:|---:|
| short | 6.52 GB | 2.96 GB | 0.236 s | 0.134 s |
| correction | 6.56 GB | 3.05 GB | 0.373 s | 0.241 s |
| technical | 6.60 GB | 3.17 GB | 0.528 s | 0.352 s |
| long | 6.81 GB | 3.69 GB | 1.235 s | 0.843 s |

Raw and cleaned text matched exactly between FP16 and 4-bit in every paired run, including the technical clip and negation/correction examples. Peak MLX active memory fell by roughly 46–55%; warm file processing was faster on all four clips. This is not current resident memory or full system footprint.

These synthetic clips do not establish parity on human accents, rare terms or noisy speech. The publisher’s reported name regression remains relevant. Keep FP16 available as an alternative and expand the accuracy corpus before treating quantization as quality-neutral.

The app's new `--cohere-4bit` benchmark selection was first observed failing to select that engine before implementation. After the change, three network-denied runs selected `cohere-4bit`, produced the expected short transcript without fallback, and stayed below 4 GB peak MLX active memory. See `quantization/native-4bit-selection.json`. Build 3's signature satisfies build 2's designated requirement; see `quantization/update-identity.json`.
