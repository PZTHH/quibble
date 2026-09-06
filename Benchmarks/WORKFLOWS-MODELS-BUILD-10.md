# Build 10: models, workflows and developer controls

Implemented and checked 2026-09-05 on this M5 Max, macOS 26.6.1. This is a working prototype increment, not a production-release acceptance report.

## What changed

- Models library: 13 choices, comprising nine speech engines and four text models. Search and role/download filters, sizes, local disk use, language information, supported controls, experimental status, source/license attribution and pinned download revisions are visible. New choices include Whisper Base/Small/Turbo/Large v3, Qwen ASR 0.6B, and Qwen instruction models at 0.6B and 1.7B alongside the existing 4B model. Different sizes are model variants, not 13 unrelated architectures.
- Modes: create, edit, duplicate, remove/undo and select named workflows. Speech recognition runs first; users can add, reorder or skip up to six vocabulary, S1 cleanup and custom-instruction steps. Custom instructions use a compatible Qwen text model. Output either inserts through the existing global dictation path or stays in Quibble for review. Local recording and imported audio always stay in Quibble. These are ordered pipelines, not arbitrary scripts or branching graphs.
- Developer: supported per-mode token limit, temperature, language and chunk duration; read-only local model configuration; raw transcript, backend segments, available token statistics, audio level, stage inputs, prompts, model proposals and accepted outputs. Exports include transcript/prompt contents and remain explicitly user initiated. Confidence, token IDs and log probabilities are not fabricated when the runtime does not expose them.
- Memory: manual current MLX active/cache and historical peak readings, plus unload-now. These measurements are not whole-process resident memory. Models remain demand loaded, disabled steps do no processing, and the existing idle-unload policy remains. The vocabulary helper shares its instance when Whisper Turbo is also the primary speech engine.
- Appearance: one native blurred material behind the sidebar and content, coordinated translucent cards, and the fullscreen button removed. Close, minimize and resizing remain available. Step controls have distinct accessibility labels.

The workflow is captured when recording starts, so edits cannot change a recording's pipeline halfway through. A failed optional step retains its input and surfaces a warning. Punctuation-only, incomplete and detected vocabulary-damaging refinements are rejected; these checks do not establish complete semantic equivalence for arbitrary prompts.

The shared audio vocabulary helper and scoped edit guard remain in place across all nine speech engines. Application-context rewriting remains disabled. User vocabulary and the original active Basic cleanup mode were preserved; the temporary GUI validation workflow was removed.

## Evidence

The Release app builds with Xcode 26.6 and the installed Metal toolchain, using the existing bundle ID and development signing team. The final core suite contains 63 tests, including workflow ordering, persistence/migration, validation, invalid output rejection and actual catalog decoding. Red runs were observed for new behavioral checks before implementation. Final logs are `.build/build10-final.log` and `.build/workflow-tests.log`.

There were 24 sequential inference scenarios with network access denied:

| Coverage | Scenarios | Observed outcome |
|---|---:|---|
| Nine speech engines, positive and negative synthetic audio | 18 | Saved `Superwhisper` spelling recovered in the positive phrase; it was not injected into the negative phrase |
| Qwen 4B and 1.7B custom bullet prompt | 2 | Correct bullet output on the short fixture |
| Qwen 0.6B custom bullet prompt | 1 | Model proposed only a dash; guard rejected it and retained incoming text |
| Reordered workflow | 1 | Prompt and vocabulary ran in the requested order |
| Raw workflow with no refinement steps | 1 | Output matched primary ASR |
| Missing instruction model | 1 | Warning shown and incoming text retained |

The scripted assertions also checked that disabled stages took zero processing time and did not alter text, and that each stage received the previous stage's accepted output. Compact results are in [build 10 result summaries](results/build10/); full local fixtures/runners are in `.build/build10-smoke/`. Durations in the summaries are stage measurements on short synthetic audio, not release-to-insert or quality rankings.

In the live signed app, a temporary workflow was created, edited, reordered, activated and used on imported audio. Developer controls persisted a token-limit change, and traces showed the custom prompt plus the skipped cleanup stage. The output was `- Please open Superwhisper.`. Manual memory refresh showed 4.31 GB active, 0.03 GB cache and 4.66 GB historical peak; unloading reduced active/cache to 0.00 GB while leaving the peak at 4.66 GB. Model search/details and the unified window appearance were inspected. The final app was reopened after removing the temporary mode and restoring Basic cleanup.

## Limits and next work

- Small-model and multilingual accuracy remain experimental. Two synthetic phrases per speech engine do not establish rare-name recognition or human-dictation accuracy. Whisper Turbo rendered the negative phrase as “QuickTime” in its primary transcript, illustrating that the no-vocabulary-injection check is narrower than exact transcription accuracy.
- The 0.6B text model failed this prompt despite loading correctly. It remains visibly experimental; larger models also need broader prompt evaluation.
- Existing model folders are checked for required nonempty files, not rehashed against the catalog revision. New manifests add exact file-size checks. Repair, resume, low-disk handling and full artifact integrity remain open.
- No new end-to-end global insertion matrix or signed-update permission-retention test was performed in this pass. The shared insertion path and signing identity remain unchanged; neither establishes universal compatibility or permission continuity by itself.
- No whole-process RAM, energy, multilingual, long-audio or second-machine benchmark was performed. More instruction passes can increase latency and memory.
- Next production work should prioritize model install/recovery and guided setup, then a human-speech quality/latency matrix and broader insertion/recovery checks. Automatic app selection, surrounding-text context and voice commands remain later work.

See [runtime/model research](MODEL-CONTROLS-RESEARCH.md) for primary sources, precise backend limitations and licensing notes.
