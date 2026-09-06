# Model identity and navigation pass

Completed 2026-09-05.

## This pass

- [x] Replace generic model symbols with bundled publisher icons in Models, model details, Home and mode summaries. Keep names visible; use a neutral fallback for future model families.
- [x] Make quantized/full-weight variants easier to distinguish with a small labeled badge.
- [x] Add library sorting by benchmark accuracy, download size and name. Unknown accuracy remains last, and equal scores keep catalog order.
- [x] Make an empty model search recoverable with Clear filters.
- [x] Show which mode a model action affects, including an explanation when the step limit disables an action.
- [x] Verify the signed Release build and core suite; inspect the running app's cards, details, sorting, empty search and mode summaries.

## Next candidates

- Keyboard and VoiceOver pass across workflow editing, downloads and vocabulary.
- Light appearance, increased contrast and reduced transparency checks.
- Guided first dictation and clearer recovery from interrupted model downloads.
- More compact model comparison at larger window sizes, based on actual usage.
- Controlled local model speed comparison using the same audio, separate from last-run samples.

## Asset provenance

Publisher avatars come from the publishers' Hugging Face profiles: [Cohere Labs](https://huggingface.co/CohereLabs), [NVIDIA](https://huggingface.co/nvidia), [Qwen](https://huggingface.co/Qwen), [OpenAI](https://huggingface.co/openai), and [Superwhisper](https://huggingface.co/superwhisper). Exact URLs, retrieval dates and file hashes are in `MODEL-ICON-SOURCES.json`. They identify original model publishers; community conversion attribution remains in model details. Publisher marks remain their owners' property. No endorsement is implied.

Five static assets total approximately 16 KB. No runtime network requests, polling, animation or inference work is added.

## Verification

- Release `xcodebuild`, exit 0, `BUILD SUCCEEDED` (`.build/build14-final.log`).
- `swift test --scratch-path .build/core-tests`, exit 0, 66 tests, zero failures (`.build/build14-tests.log`).
- `codesign --verify --deep --strict`, exit 0; stable bundle ID and signing team retained.
- Running app at 850 × 702: inspected all five publisher icons, Home model shortcut, model details, Modes summaries and selected state. Verified accuracy order (Qwen first, shared Cohere scores tied), smaller downloads first, alphabetical order, and unrated Whisper models after rated models. Empty search recovers through Clear filters; single-result count reads “1 model”.
- Final build reopened on Models. User's Qwen3 ASR / Basic cleanup selection retained. No model downloads or inference settings changed during UI verification.

This pass does not constitute a full VoiceOver or appearance-matrix audit. Those remain on the follow-up list above. The six-step action explanation was reviewed in code; no user's workflow was modified to force that state.
