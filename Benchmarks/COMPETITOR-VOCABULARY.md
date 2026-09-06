# How dictation competitors implement personal vocabulary

Retrieved: 2026-09-05. Directional after: 2026-10-05.

## Answer

The evidence supports a layered implementation: recognition hints when the speech engine supports them, preferred spellings in a separate cleanup instruction when a general instruction model is available, and optional explicit replacements for persistent errors. Those mechanisms are distinct. Competitor claims do not establish that an arbitrary rare name works after one entry on every local model. See the primary sources below, all read on the retrieval date.

I found no primary evidence that Superwhisper or Wispr Flow inserts a vocabulary list into S1-mini's transcript and then strips it from the result. The closest inspectable implementations, VoiceInk and OpenWhispr, put vocabulary in a **system instruction separate from the transcript**. Quibble's proposed S1 prefix experiment therefore needs its own quality evidence; it is not a verified competitor technique. [VoiceInk source](https://github.com/Beingpax/VoiceInk/blob/8f089cb4bf2c9c2f217b0cc0af909d9052ff6288/VoiceInk/Features/Enhancement/Workflows/AIEnhancementService.swift#L153), [OpenWhispr prompt builder](https://github.com/OpenWhispr/openwhispr/blob/a9cf27b49bdcc9069922641ec39ac06d3483a125/src/config/prompts/index.ts#L48).

## Documented proprietary products

| Product | Verified behavior | What remains undisclosed | Source, read 2026-09-05 |
|---|---|---|---|
| Superwhisper | Vocabulary words accompany audio as recognition hints. Replacements run programmatically after transcription, ignore source capitalization, and preserve the configured output spelling. Documentation recommends replacements for persistent mistakes. | Exact per-engine hint implementation, ranking, and cleanup fallback; uncommon-name accuracy. | [Vocabulary documentation](https://superwhisper.com/docs/get-started/interface-vocabulary) |
| Superwhisper | Changelog reports larger vocabulary lists in 2.16.0, improved vocabulary and forced alignment for offline Whisper in 2.16.2, and on-device S1-mini cleanup in 2.18.0. | Forced alignment's precise role and how vocabulary reaches S1-mini. These release notes do not disclose that algorithm. | [Official changelog](https://ai.superwhisper.com/changelog) |
| Wispr Flow | Single-word entries boost recognition. Explicit misspelling rules perform replacements; its guidance says rules are more reliable for consistently repeated errors. Desktop entries can be starred for priority. | Whether boosting occurs in acoustic decoding, a later model, or both; prompt, models, and scoring. | [Dictionary documentation](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary) |
| Wispr Flow | Public transcription API accepts `context.dictionary_context`, speaker names, conversation participants, and nearby textbox contents as distinct fields alongside audio. | Public schema is an interface, not proof of internal architecture or exact desktop-app payload. | [Request schema](https://api-docs.wisprflow.ai/request_schema) |
| Wispr Flow | Auto-learned terms become vocabulary additions; only manually authored misspelling entries become replacement rules. | Learning confidence, repetitions required, phonetic matching, and all field-monitoring details. | [Official abbreviations guidance](https://docs.wisprflow.ai/articles/5052432796-copy-of-general-article) |
| Wispr Flow | Full dictation uses cloud transcription; current iOS behavior offers an on-device rough draft when the cloud cannot be reached. | No evidence that its full dictionary performance is reproducible in a comparably small offline model. | [Failure/retry and offline-draft documentation](https://docs.wisprflow.ai/articles/2503460374-retry-failed-transcriptions) |

The older Superwhisper vocabulary guide warns that large lists may hurt accuracy; its newer changelog reports work supporting very large lists. Treat the guide's warning as a reason to test dictionary size, not a measured current list limit. [Vocabulary guide](https://superwhisper.com/docs/get-started/interface-vocabulary), [changelog](https://ai.superwhisper.com/changelog), read 2026-09-05.

## Inspectable implementations

Source snapshots were resolved through each repository's GitHub commit API on 2026-09-05. Links below are immutable commit URLs. Source inspection proves code behavior, not recognition quality. A later isolated probe ran Handy's exact correction functions, as documented below; no complete competitor app was benchmarked.

### Handy: native hints plus CPU phonetic correction

Commit `fbd4e15fa14a721c66c57006ae110428b9e255b3`.

The local transcription manager passes comma-separated custom words as Whisper's initial prompt. Non-Whisper paths receive its fallback text correction; the Whisper path skips that fallback because it already received hints. [Transcription manager](https://github.com/cjpais/Handy/blob/fbd4e15fa14a721c66c57006ae110428b9e255b3/src-tauri/src/managers/transcription.rs#L1299), read 2026-09-05.

The fallback normalizes ASCII alphanumeric keys, tests one to three word spans, and scores normalized Levenshtein distance. Equal Soundex codes multiply the score by 0.3; the default acceptance threshold is 0.18. Safeguards reject candidates over 50 characters, large length differences, unsupported scripts, and spans crossing interior punctuation. It chooses the closest candidate. There is no ordinary-word dictionary check or runner-up confidence margin in the inspected matcher. This is a practical CPU baseline, but its spelling-based Soundex algorithm is not evidence of broad international-name accuracy. [Matcher and tests](https://github.com/cjpais/Handy/blob/fbd4e15fa14a721c66c57006ae110428b9e255b3/src-tauri/src/audio_toolkit/text.rs#L80), [default threshold](https://github.com/cjpais/Handy/blob/fbd4e15fa14a721c66c57006ae110428b9e255b3/src-tauri/src/settings.rs#L596), read 2026-09-05.

### VoiceInk: preferred words in general cleanup instructions

Commit `8f089cb4bf2c9c2f217b0cc0af909d9052ff6288`.

General enhancement appends a custom-vocabulary section to the system message. It asks the model to use the entries as the spelling authority and resolve plausible phonetic errors without forcing unrelated substitutions. The transcript is separately enclosed in transcript tags. This path supports Ollama as well as other providers. Crucially, the dedicated `voiceInkRefine` branch returns before that prompt assembly and sends only the transcript; its behavior cannot be used as evidence that every small specialized normalizer accepts dictionary instructions. [Enhancement service](https://github.com/Beingpax/VoiceInk/blob/8f089cb4bf2c9c2f217b0cc0af909d9052ff6288/VoiceInk/Features/Enhancement/Workflows/AIEnhancementService.swift#L153), read 2026-09-05.

Separate replacements are applied before AI enhancement. Their implementation sorts longer triggers first, supports comma-separated variations, performs case-insensitive matching, and uses script-aware word boundaries. [Pipeline](https://github.com/Beingpax/VoiceInk/blob/8f089cb4bf2c9c2f217b0cc0af909d9052ff6288/VoiceInk/Features/Recording/Workflows/TranscriptionPipeline.swift#L151), [replacement service](https://github.com/Beingpax/VoiceInk/blob/8f089cb4bf2c9c2f217b0cc0af909d9052ff6288/VoiceInk/Features/Dictionary/Workflows/WordReplacementService.swift), read 2026-09-05.

### OpenWhispr: dual prompting, automatic learning, and echo recovery

Commit `a9cf27b49bdcc9069922641ec39ac06d3483a125`.

OpenWhispr supplies dictionary words to local Whisper as an initial prompt. Its cleanup prompt builder appends dictionary spellings to the system prompt, while wrapping the actual transcript separately. The local reasoning provider uses that system/user separation too. [Local ASR path](https://github.com/OpenWhispr/openwhispr/blob/a9cf27b49bdcc9069922641ec39ac06d3483a125/src/helpers/audioManager.js#L2023), [prompt builder](https://github.com/OpenWhispr/openwhispr/blob/a9cf27b49bdcc9069922641ec39ac06d3483a125/src/config/prompts/index.ts#L32), [local reasoning](https://github.com/OpenWhispr/openwhispr/blob/a9cf27b49bdcc9069922641ec39ac06d3483a125/src/services/ai/inferenceProviders/local.ts#L17), read 2026-09-05.

Post-paste edit events are debounced and fed into an automatic correction learner. Accepted corrected words are stored as learned dictionary additions and surfaced in a toast. The learner compares the edited region, rejects large rewrites, duplicates, case-only changes, and very short words, and allows normalized edit distance up to 0.65. It adds the preferred word, rather than storing a mandatory replacement pair. These heuristics are inspectable, but are not a semantic guarantee against learning unrelated edits. [Event handling](https://github.com/OpenWhispr/openwhispr/blob/a9cf27b49bdcc9069922641ec39ac06d3483a125/src/helpers/ipcHandlers.js#L1017), [learner](https://github.com/OpenWhispr/openwhispr/blob/a9cf27b49bdcc9069922641ec39ac06d3483a125/src/utils/correctionLearner.js#L137), read 2026-09-05.

Its ASR prompt-echo recovery is particularly relevant to Quibble's experiment: when Whisper appears to output its dictionary prompt, the app can retry the audio without the prompt and without VAD. Strict echoes that cannot be recovered produce a distinct error. This is **ASR recovery**, not a technique that prepends a fake vocabulary sentence to cleanup and removes it by position. [Recovery implementation](https://github.com/OpenWhispr/openwhispr/blob/a9cf27b49bdcc9069922641ec39ac06d3483a125/src/helpers/audioManager.js#L2054), [echo analyzer](https://github.com/OpenWhispr/openwhispr/blob/a9cf27b49bdcc9069922641ec39ac06d3483a125/src/utils/dictionaryEchoFilter.js), read 2026-09-05.

## Recommendations for Quibble — engineering inference

These recommendations are our interpretation of the sources above, not verified competitor internals or a replacement for Quibble's benchmarks.

1. Make the ordinary action “Add word.” Internally route the saved spelling into native ASR hints and whichever measured fallback can recover it. Keep explicit aliases as an optional advanced repair, rather than the primary uncommon-name workflow.
2. Benchmark the S1-mini prefix idea against a separate-instruction model and native ASR hints using identical audio and preferred-word-only dictionaries. Include no-name negatives, multiple plausible names, and real spoken names with divergent spelling. Score added or missing text as failure even if the desired name is correct.
3. Consider a phonetic CPU **candidate gate**, inspired by Handy, before model correction. Measure its recall separately: a gate that rejects Siobhan/Shivon makes downstream model quality irrelevant. Do not automatically substitute every Soundex collision; include competing candidates and ordinary-word negatives.
4. If a specialized normalizer cannot reliably consume side information, do not disguise that failure with stronger string replacement. Select a better measured recognizer or constrained correction model, and expose any quality/latency tradeoff honestly.
5. Feed confirmed edit learning into preferred spellings first, with visible Undo. Broader automatically learned pronunciation/alias rules require stronger evidence because a mistaken rule can alter future unrelated dictations.
6. Keep low device load an evaluation dimension: extra model residency, cold and warm latency, and unnecessary inference rate. The existence of CPU correction and local cleanup implementations shows options to test, not that either preserves enough quality for this user.

## Follow-up: exact Handy fallback benchmark

On 2026-09-05, the unchanged Rust correction functions were extracted into a small harness with the pinned algorithm dependencies and Handy's default threshold. Quibble's existing 18-case preferred-word-only evaluation produced **9/18 exact matches**, correcting 5/9 positive cases and falsely altering 5/9 negative cases. A separate 24-case hand-authored text set produced 14/24 exact matches, with 4/12 positive cases fully corrected and 2/12 negatives altered. These are text probes, not human-audio accuracy measurements. [Reproduction instructions and method](competitor-probes/README.md), [main results](competitor-probes/handy-name-results.json), [additional results](competitor-probes/handy-additional-results.json).

The implementation left Shivon/Siobhan, Searsha/Saoirse, Neve/Niamh, and Keeva/Caoimhe unresolved. It also changed the ordinary word “name” into Niamh and changed “send” into Sinead in another fixture. It therefore fails Quibble's current requirements as both an automatic replacement policy and an unchanged exclusive candidate gate. The broader recommendation to investigate phonetic candidates remains an experiment, not an endorsement of this baseline. [Complete outputs](competitor-probes/handy-name-results.json), [additional outputs](competitor-probes/handy-additional-results.json), measured 2026-09-05.

## Unconfirmed and open questions

| Question | What was checked | Status |
|---|---|---|
| Does Superwhisper prefix vocabulary into S1-mini input and strip it? | Vocabulary docs, modes docs, current changelog, search of official material | Unconfirmed; no disclosed implementation found. |
| How does Wispr Flow implement boosting and automatic learning internally? | Official dictionary and abbreviation docs, public API schema, offline behavior | Interface and product behavior confirmed; algorithms and model boundaries undisclosed. |
| Does a single saved rare name work on every competitor model? | Official claims and three pinned source implementations | Not established; no per-engine accuracy benchmark found. |
| Does Handy's phonetic matcher meet Quibble's name and false-positive requirements? | Exact extracted Rust implementation, 42 text cases at its default threshold | No on these fixtures; both missed names and unintended changes are observed. Human-audio evaluation remains separate. |
| Does app context materially improve the preferred-word-only path? | Flow API and context documentation; VoiceInk prompt assembly | Plausible but outside the currently authorized active-context feature scope; keep Quibble's context refinement paused. |

No production code was edited for this investigation. Source snapshots were downloaded to `/tmp/quibble-vocabulary-research` for inspection. The isolated Handy harness, MIT attribution, fixtures, and evidence are under `Benchmarks/competitor-probes/`.
