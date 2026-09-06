# Build 13: segmented relative Accuracy meter

2026-09-05. The Models page now uses **Accuracy** at first glance, with more filled segments indicating better relative benchmark standing. Exact upstream WER and its source remain in Details.

The meter is an ordinal comparison across the distinct published WER values in Quibble's full bundled benchmark snapshot. It is not a percent-correct metric or a measure of the size of the accuracy gap. Search and role filters do not change the scale. Equal WER values share a standing, including local variants mapped to the same upstream result. Missing scores stay unrated. The visible caption says “Relative · HF benchmark”; the explanation is available under About the meters and through accessibility labels.

The current six standings are Qwen ASR 1.7B (6/6), Cohere (5/6), Parakeet v3 (4/6), Qwen ASR 0.6B (3/6), Whisper Large v3 (2/6), and Whisper Turbo (1/6). The source and local-quantization caveats from [the benchmark research](HF-ASR-BENCHMARKS.md) remain. This presents small differences more distinctly without claiming proportional improvements or changing the underlying measurements.

Validation: the new lower-error/shared-score/missing-score test failed before the ranking implementation. The full suite then passed with 66 tests and zero failures. Signed Release build 13 and the live Models page were checked. No inference, downloads, vocabulary, workflow or local speed measurement changes.
