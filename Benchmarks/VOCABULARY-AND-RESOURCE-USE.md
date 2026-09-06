# Vocabulary across models and device load

> Vocabulary status, 2026-09-05: the visual editor and explicit correction rules are implemented, but preferred-word-only recognition of uncommon names did not meet the user’s quality requirement. The universal vocabulary milestone remains open. The CPU measurements below describe the first implementation, not acceptance of that milestone. See [current evaluation](VOCABULARY-QUALITY-EVALUATION.md).

Measured: 2026-09-05, build 7, Apple M5 Max / 48 GiB. External sources read on that date; directional after 2026-10-05. These are small integration checks, not broad human-speech accuracy claims.

## Decision

Use a model-independent CPU vocabulary processor and keep the existing ASR/S1 weights. Do not add a language model to the normal dictation pipeline for vocabulary. Native Qwen ASR hints remain an additional capability; every enabled ASR route gets the same local correction processor.

The processor applies user-approved phrase corrections, then handles uniquely matching unusual spelling variants. Automatic matching is deliberately narrow: a word of at least six normalized characters, the same three-character prefix, and at most one character edit. The system spelling service protects recognized ordinary words. Short names, split phrases and uncertain matches need an explicit correction rule. For example, a saved `Superwhisper` can correct `Superwhisker`; `super whisper → Superwhisper` needs an approved rule on a recognizer that does not handle the hint itself. Native recognition hints and this matcher are guidance, not guarantees.

URLs, email addresses, backtick spans, paths and underscore identifiers are excluded from automatic edits. Rules are non-cascading, conflicting rules are rejected when saved, and disabled entries are ignored. Cleanup retains the corrected pre-cleanup transcript if it changes the spelling or count of protected saved terms. This check protects spellings, not semantic equivalence in general.

Implementation: `Sources/QuibbleCore/VocabularyProcessor.swift`, `App/VocabularySpelling.swift`, `Inference/Sources/QuibbleInference/LocalInference.swift`, inspected as build 7 working-tree code on 2026-09-05.

## Why no extra model?

Evaluated a 351 MB download of [Qwen3-0.6B-4bit, pinned revision](https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/tree/73e3e38d981303bc594367cd910ea6eb48349da8), plus the already-downloaded Qwen3 4B instruction model. Each was asked to accept or reject proposed term edits using only the transcript and dictionary candidates. Both ran with network access denied.

| Candidate | Probe outcome | Median per-call time, including load |
|---|---|---|
| Qwen3 0.6B 4-bit | 0/20 strict JSON matches; even extracting fenced arrays yielded only 7/20 expected selections, with 7 unwanted selections on negative examples | 0.367 s |
| Qwen3 4B Instruct 4-bit | 11/20 expected selections, with 7 unwanted selections on negative examples | 0.394 s |

Examples included ordinary uses of apple, obsidian, quick time and quibble. Some proposed edits were intentionally unsuitable; one was a no-op. This is a screening probe of this prompt/architecture, not a benchmark of the models' general ability. The results do not justify adding their inference cost or trusting their decisions in dictation. The raw probes, prompt and pinned candidate manifest are retained for reproducibility; the candidate is not in the app's model catalog.

S1-mini is a fixed-function normalizer, not a general instruction-following vocabulary resolver. Its supported prompt remains unchanged. [Publisher documentation](https://huggingface.co/superwhisper/s1-mini), read 2026-09-05.

## Vocabulary evidence

- **66/66 CPU checks**: 22 explicit positive/negative cases, three runs each. Includes preferred-word-only unusual misspellings, approved phrases, capitalization, Unicode, ordinary words, conflicting near-matches, URLs and code. This corpus tests a narrower task than the model probe; the two scores are not directly comparable.
- CPU median across those checks: **0.020 ms**; maximum **10.24 ms**, including first system-spelling use. A running-app first preview measured **14.5 ms**. A compiled 1,000-entry vocabulary on unrelated text averaged **0.052 ms** over 100 runs.
- **16/16 positive audio runs**: four ASR choices × cleanup on/off × two runs. All returned `Please open Superwhisper and use it for the meeting notes.` The explicit test dictionary included the observed split-phrase aliases. It was separate from the user's dictionary.
- **8/8 unrelated audio runs**: four ASR choices × two runs with cleanup and the same dictionary. All retained `Please send the revised document to Maya before Thursday afternoon.`
- Shared correction time in the positive audio runs was about **1.1–1.3 ms initially**, then **0.08–0.11 ms warm**. These explicit-rule runs do not exercise expensive system-spelling initialization.
- Six default Cohere 4-bit baseline runs across correction/negation, technical and long fixtures matched earlier raw and cleaned transcripts exactly. No model precision or weights were changed for this update.
- **39 Swift tests passed**, including migration, conservative matching, protected spellings, real isolated clipboard behavior, atomic save failure, conflicting rules, import/export and undo. The hidden-alias migration, preferred-word typo, URL/code boundary and undo-after-new-observations cases were observed failing before their fixes.

Evidence: `results/vocabulary-cpu.json`, `results/vocabulary-production/*.json`, `results/vocabulary-production-summary.json`, `results/vocabulary-mini-selection.json`, `results/vocabulary-4b-selection.json`, and the test sources.

## Resource behavior

- Vocabulary matching is CPU-only, compiled per vocabulary snapshot, with a bounded spelling-result cache. Unrelated text does not query the system spelling service. It creates no GPU inference workload.
- MLX's reusable allocation cache is limited to approximately **32 MiB**. This does not cap active model memory; the same model weights and computation remain in use.
- A cancellable timer unloads models after **two idle minutes**. Starting recording or inference cancels the pending timer. The model actor checks cancellation before releasing its models.
- Explicit unload verification after two Cohere 4-bit + S1 runs: active MLX allocation **2,759,674,456 → 6,232 bytes**; cache **33,554,752 → 0 bytes**. Evidence: `results/vocabulary-production/unload.memory.json`. This proves the unload operation releases MLX allocations; it is not total process RSS, and the automatic two-minute path still needs a live long-idle observation.
- Peak MLX allocation in default correction/technical/long comparisons remained approximately **3.05 / 3.17 / 3.69 GB**, effectively unchanged from the earlier baseline. Idle unloading lowers retained allocations; it does not eliminate the working memory required while transcribing.

Settings now label active MLX allocation after inference separately from the historical process peak. Neither is presented as current whole-app RAM. No polling loop was added for memory reporting.

## Product behavior and remaining checks

The Vocabulary page has Words, Corrections and Suggestions, per-entry enable controls, explicit alias activation, before/after highlighting, microphone testing, JSON import preview/export, and undo. Existing hidden aliases remain off during migration. Minimal dictation applies enabled vocabulary without AI cleanup; turn vocabulary off for unmodified recognizer output, including no native hints.

The native dark-mode page and the preferred-word-only preview were visually inspected. Persistence/import/export were verified at the store boundary. Live microphone testing of the new complete path and broader personal vocabulary quality remain user-validation items. JSON is the supported import/export format in this build; CSV and pronunciation-based matching remain future work.

The first vocabulary milestone delivers a conservative cross-model path. It does not promise arbitrary phonetic name recovery, model-assisted semantic disambiguation, or the entire production roadmap. Guided onboarding, a full model-manager redesign, history and release distribution are later milestones.
