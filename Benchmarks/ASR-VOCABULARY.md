# Vocabulary inside speech recognition

Checked 2026-09-05.

The pinned Cohere adapter (`bf14ae0c26e4e85553dd989571cae29d70fa6735`) builds a fixed language/punctuation prompt. Its public generation API has no vocabulary or hotword argument. Adding words to a post-processing replacement table does not change recognition.

The same runtime's `Qwen3ASRModel.generate` overload accepts `context` before audio decoding. Its local loader is `fromModelDirectory`, so using this capability needs no runtime upgrade or cloud inference. Quibble's experimental adapter supplies only the user's preferred terms to that input, never text from another application. This is probabilistic recognition guidance, not a forced replacement rule.

Sources:
- [Pinned Cohere tokenizer](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/CohereTranscribe/CohereTranscribeTokenizer.swift)
- [Pinned Qwen3 ASR implementation](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift)
- [Qwen model publisher](https://huggingface.co/Qwen/Qwen3-ASR-1.7B)
- [Pinned 4-bit conversion](https://huggingface.co/mlx-community/Qwen3-ASR-1.7B-4bit/tree/78a389c776a5483b2d0d4ea5494e11012e0d6159)
- [S1-mini publisher](https://huggingface.co/superwhisper/s1-mini): transcript cleanup, not speech recognition.

Context-aware text refinement was withdrawn after user testing showed copying of nearby text into dictation. The earlier eight synthetic refinement fixtures were insufficient evidence for that feature. S1-mini is again the only active cleanup model.

Evaluation of ASR vocabulary hints is recorded separately below; do not infer quality from API support alone.
