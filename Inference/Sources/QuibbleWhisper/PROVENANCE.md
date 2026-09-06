# Quibble Whisper adapter

Vendored five Whisper source files only from https://github.com/Blaizzy/mlx-audio-swift at bf14ae0c26e4e85553dd989571cae29d70fa6735 (2026-09-05). MIT license retained alongside the source. Other audio models still use the pinned upstream package.

Local changes: import public STT types from MLXAudioSTT; add a whole-term, token-budgeted vocabulary prompt using Whisper start-of-previous-text tokens; keep language metadata indexed into the base prompt. Remove network download APIs and tokenizer fallback: fromDirectory requires local tokenizer assets. No weight or decoder-logit changes. Remove this copy when upstream exposes a compatible initial-prompt API. Compare these files to the pinned upstream Whisper directory when upgrading.
