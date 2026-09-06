# Timestamped transcription and speaker identification

Retrieved: 2026-09-06. Directional after: 2026-10-06.

## Answer

Show original ASR sections with their actual timing source. Parakeet already supplies acoustic alignment; Quibble’s current Whisper and Qwen adapters supply audio-window boundaries, which must be labeled as approximate sections. Cohere needs those outer window boundaries. For speaker labels now, use an explicitly selected OpenAI diarization model. MOSS-Transcribe-Diarize is a promising next local candidate, requiring a measured integration trial rather than an automatic download.

## Confirmed capabilities

All sources below were read on **2026-09-06**. “Current” refers to Quibble’s pinned runtime, not every implementation of the model.

| Model | Timing and speaker capability | Primary evidence |
|---|---|---|
| Cohere Transcribe | The released base model provides neither timestamps nor speaker diarization. Preserve real input-window timing only. | [Cohere’s limitations](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026#limitations) |
| Parakeet TDT v3 | NVIDIA exposes character, word, and segment timestamps. Quibble’s pinned Swift adapter returns aligned sentences with start/end times, without speaker labels. | [NVIDIA timestamp usage](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3#transcribing-with-timestamps), [pinned Swift alignment](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/Nemo/NemoAlignment.swift) |
| Qwen3-ASR | Its separate ForcedAligner supplies word/character timing. The current Swift ASR implementation reports input-chunk offsets and duration instead; it does not expose speaker identification. | [Qwen’s forced-aligner documentation](https://github.com/QwenLM/Qwen3-ASR/blob/7c6daf77a2421100f5fb066495372c00129d39ff/README.md#forcedaligner-usage), [pinned Swift ASR implementation](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/Qwen3ASR/Qwen3ASR.swift) |
| Whisper | Official Whisper can extract segment/word timestamps. Quibble’s vocabulary fork suppresses timestamp tokens and returns its actual 30-second input-window bounds; it does not identify speakers. | [Official transcription implementation](https://github.com/openai/whisper/blob/86098128c0b4f24f0e2aa2994de830614b474227/whisper/transcribe.py), [Quibble fork](../Inference/Sources/QuibbleWhisper/WhisperModel.swift), SHA-256 `82c1e8d3e1078c259cf93ab5cf7aa0fb38d84ba877493014ee5cdd393809e41c` |
| S1-mini | A text normalizer. It cannot recover acoustic timing or identify a speaker from audio it never receives. | [Superwhisper’s model card](https://huggingface.co/superwhisper/s1-mini) |
| GPT Transcribe | Current general-purpose file ASR and vocabulary/language hints. Speaker labels and detailed timestamps require specialized models. | [OpenAI file transcription guide](https://developers.openai.com/api/docs/guides/speech-to-text) |
| GPT-4o Transcribe Diarize | Returns genuine speaker-labeled start/end segments with `diarized_json`. Use `chunking_strategy=auto` for inputs over 30 seconds. Prompt and timestamp-granularity controls are unsupported. | [OpenAI diarization model](https://developers.openai.com/api/docs/models/gpt-4o-transcribe-diarize), [Audio API reference](https://platform.openai.com/docs/api-reference/audio/createTranscription) |
| MOSS-Transcribe-Diarize 0.9B | Authors describe joint transcription, timestamps, anonymous speakers, and hotword prompting. The pinned Swift dependency already includes an implementation; Quibble has not measured or shipped this model. | [OpenMOSS model card](https://huggingface.co/OpenMOSS-Team/MOSS-Transcribe-Diarize), [pinned Swift model](https://github.com/Blaizzy/mlx-audio-swift/blob/bf14ae0c26e4e85553dd989571cae29d70fa6735/Sources/MLXAudioSTT/Models/MossTranscribeDiarize/MossTranscribeDiarize.swift) |
| Multitalker Parakeet Streaming | A separate model from the installed TDT variant. NVIDIA’s recipe requires a diarizer and one ASR instance per speaker; it is not a free capability switch on ordinary Parakeet. | [NVIDIA model and architecture](https://huggingface.co/nvidia/multitalker-parakeet-streaming-0.6b-v1) |

The upstream MLX snapshot is pinned to `bf14ae0c26e4e85553dd989571cae29d70fa6735`. The local Whisper fork has no Git commit in this workspace; the hash above identifies the inspected snapshot. Official Whisper and Qwen references use the upstream commits retrieved on the inspection date; they establish upstream capability rather than a dependency upgrade.

## Implementation decisions

- `TranscriptSegment` stores original text, start/end seconds, optional speaker, and a source distinguishing acoustic model timing from input-window timing.
- History adds optional segments, so old records still decode. Editing or cleaning the prose does not reassign acoustic timestamps to rewritten words.
- The online speaker model is explicit. It uses the existing Keychain credential and fixed transcription endpoint. It does not send unsupported vocabulary hints or trigger a local model download.
- Speaker IDs from separate uploaded parts are scoped to that part. “A” in one request is not evidence that “A” in another request is the same person.
- Malformed speaker metadata rejects the entire cloud response. Overlap between valid speaker segments is retained.
- Long recordings can retain their measured duration and speaking pace. History admits up to 250,000 UTF-16 units per original/edited transcript, with an aggregate archive budget that also includes segment text. Capacity failures are explicit; this is not an unlimited transcript database.

Implementation evidence: [shared segments](../Sources/QuibbleCore/TranscriptSegment.swift), [cloud request/decoder](../Sources/QuibbleCore/CloudTranscription.swift), [history](../Sources/QuibbleCore/TranscriptHistory.swift), [focused tests](../Tests/QuibbleCoreTests/CloudTranscriptionTests.swift). These are the workspace changes made on the retrieval date, rather than upstream feature claims.

## Unconfirmed and next checks

| Question | What was checked | Remaining work |
|---|---|---|
| Local MOSS speed, memory, and speaker accuracy on this Mac | Official model card and existing Swift port; no new weights downloaded | Compare short and long two-speaker recordings, overlapping speech, speaker stability, and vocabulary precision before making it a selectable production model. |
| Live OpenAI diarization availability and quality for this account | Official request schema plus deterministic request/response fixtures; no live paid request | User-selected speaker mode with their configured key, followed by a known-speaker recording. |
| Stable speaker identity across independent chunks | No cross-request identity guarantee established in the fetched documentation | Keep part-scoped labels. A future full-recording diarization pass or explicit voice references needs its own evaluation. |
| Exact timing for the current Qwen and Whisper paths | Inspected actual generated segment dictionaries | Add and evaluate forced alignment or timestamp decoding separately; do not infer word times from character position. |
