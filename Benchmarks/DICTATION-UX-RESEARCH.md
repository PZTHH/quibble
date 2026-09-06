# Desktop dictation UX: Superwhisper, Wispr Flow, and the next Quibble slice

Retrieved: 2026-09-05 · Directional after: 2026-10-05

## Answer

The strongest next step is a welcoming Home screen with a clear shortcut, current mode, and recoverable recent dictations. Put personalization and configuration in predictable sidebar groups, and make the recording indicator communicate state without demanding attention. These are recommendations inferred from the evidence below, not claims that either competitor is flawless.

Keep Quibble's two working modes, local processing, vocabulary audio helper, and insertion pipeline. App-context rewriting and voice commands remain outside this UI slice, per the user's scope. Do not turn a visual refresh into another transcription-model change.

## Observed visual references

The following are direct observations of the Superwhisper interface in the screenshots supplied in this workspace. They were inspected on 2026-09-05; the captured app version and capture dates are unknown. They establish the supplied design reference, not the exact appearance of the newest release.

| Observation | Source | Read on |
|---|---|---|
| Home uses a broad sidebar, generous spacing, light grouped surfaces, a microphone label in the toolbar, a compact statistics strip, and a short list of starting actions with keycaps. | [Local home reference](../Docs/References/Superwhisper/README.md) (`SuperWhisper-Home.png`) | 2026-09-05 |
| History uses a toolbar search field and chronological groups. Failed/no-speech recordings remain visible as rows. | [Local history reference](../Docs/References/Superwhisper/README.md) (`SuperWhisper-History.png`) | 2026-09-05 |
| Vocabulary places one wide add field above a sparse list. Preferred spellings and explicit replacements are visually distinguishable; replacements show an arrow between forms. | [Local vocabulary reference](../Docs/References/Superwhisper/README.md) (`SuperWhisper-Vocabulary.png`) | 2026-09-05 |
| Modes are large, easy-to-scan rows with a current-mode marker. A mode-switch shortcut sits at the bottom. | [Local modes reference](../Docs/References/Superwhisper/README.md) (`SuperWhisper-Modes.png`) | 2026-09-05 |
| Configuration makes appearance and recording-window choices visual, then lists shortcuts with descriptions and keycaps. | [Local configuration reference](../Docs/References/Superwhisper/README.md) (`SuperWhisper-Configuration.png`) | 2026-09-05 |
| Models use a searchable table with provider, type, comparative indicators, and download/storage information. This is a model-management surface rather than the daily starting screen. | [Local models library reference](../Docs/References/Superwhisper/README.md) (`SuperWhisper-Sound-Models-Library.png`) | 2026-09-05 |

The parent also inspected Wispr Flow’s official product-page illustrations in the browser on 2026-09-05: a compact waveform capsule flanked by cancel/finish controls, and preferred-word chips with a single add-word action ([product page](https://wisprflow.ai/)). These are marketing illustrations, not proof of the current installed desktop layout. No complete Wispr Flow desktop Hub screenshot was inspected. Its layout below is documented behavior, not a visual measurement. Superwhisper's official documentation image links returned HTTP403 through the browser retrieval tool; the user's local references supplied the visual evidence instead.

## Documented workflows

| Area | First-party finding | Source | Read on |
|---|---|---|---|
| Flow Home | Desktop separates its Hub from the floating Flow Bar. Home displays the dictation shortcut, searchable transcripts grouped by day, and hover actions such as copy. History is stored locally per device. | [Navigate Flow](https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android) | 2026-09-05 |
| Flow organization | Dictionary and Style are top-level destinations; settings separate shortcuts/microphone/language, system behavior, and privacy/account controls. | [Navigate Flow](https://docs.wisprflow.ai/articles/5096240724-navigating-the-wispr-flow-app-desktop-ios-and-android) | 2026-09-05 |
| Superwhisper recovery | History can be opened from settings, the menu bar, or mini-window context menu. It supports original/processed transcript views, copying, and reprocessing using the currently selected mode. Search is documented as searching original transcription only. | [History](https://superwhisper.com/docs/get-started/interface-history) | 2026-09-05 |
| Flow insertion recovery | When no field is focused, Flow documents showing the transcript and copying it to the clipboard. A paste-last-transcript shortcut provides another recovery path. This makes a failed delivery distinct from failed recognition. | [Fix text insertion](https://docs.wisprflow.ai/articles/1621472516-flow-fails-to-detect-text-fields-or-inserts-incorrectly-on-non-qwerty-keyboard-layouts) | 2026-09-05 |
| Flow failure states | History can identify interrupted transcription, no microphone, and silent audio; dismissed/processing entries can offer recovery. Error messages can name the active microphone. | [Transcription errors](https://docs.wisprflow.ai/articles/3155947051-troubleshooting-guide-for-no-model-available-error) | 2026-09-05 |
| Superwhisper modes | Modes combine voice processing with optional AI processing; model management and advanced options are separate from basic mode use. Voice-to-text omits AI processing. | [Modes](https://superwhisper.com/docs/modes/modes) | 2026-09-05 |
| Superwhisper HUD | Recording feedback includes a waveform, processing status, current mode, finish, and cancel. Its compact variant reveals controls on hover and exposes history/settings through a context menu. | [Recording window](https://superwhisper.com/docs/get-started/interface-rec-window) | 2026-09-05 |
| Flow HUD | Desktop documentation exposes show/hide and temporary hiding, plus a right-click menu for microphone, language, and pasting the last transcript. | [Flow Bar troubleshooting](https://docs.wisprflow.ai/articles/5002934560-why-is-the-wispr-bar-is-not-appearing-or-disappearing) | 2026-09-05 |
| Superwhisper vocabulary | Recognition hints and deterministic replacements serve different purposes. The publisher warns that hints may affect punctuation/language/formatting and recommends replacements for persistent errors. | [Vocabulary](https://superwhisper.com/docs/get-started/interface-vocabulary) | 2026-09-05 |
| Flow vocabulary | Add a preferred word, save, then dictate to test. The dictionary supports search and optional misspelling rules. Its guidance also says explicit replacements are more reliable for recurring errors than a preferred spelling alone. | [Dictionary](https://docs.wisprflow.ai/articles/4052411709-teach-flow-your-words-with-the-dictionary) | 2026-09-05 |
| Progressive disclosure | Flow's August2026 notes describe virtual microphones behind an expander and shortcut hints generated from the user's own keys. These are concrete examples of keeping uncommon controls out of the default path. | [What's new](https://wisprflow.ai/whats-new) | 2026-09-05 |
| Accessibility | Flow documents focus indicators, reduced-motion support, and announced states, while also acknowledging gaps in keyboard navigation and icon labels. Competitor appearance should not be treated as accessibility validation. | [Accessibility](https://docs.wisprflow.ai/articles/3941699399-keyboard-and-screen-reader-accessibility-in-wispr-flow) | 2026-09-05 |

## Recommended bounded implementation

These are Quibble design decisions inferred from the sources, not competitor facts.

1. **Home:** a short readiness/shortcut card, two clear mode choices, a primary recording action, and recent dictations. Keep empty states useful. Hide diagnostics and model-allocation details until requested; avoid invented time-saved statistics.
2. **Recoverable history:** save original and final text locally with time, source app, and mode. Show final text first, with copy and an original-text disclosure. Search both forms. Offer deletion and a clear retention preference. Never imply text was inserted unless the insertion result supports it. A local text history is a useful first slice; audio replay/reprocessing requires a separate retention design.
3. **Navigation:** group Home/History and Modes/Vocabulary above Settings/Models. Permissions should be actionable setup status and available in settings; diagnostics should remain accessible without dominating navigation.
4. **Vocabulary:** preserve single-field preferred-word entry; keep explicit replacements optional. Use a real recording test for recognition and show the exact before/after changes. Avoid making phonetics or misspelling rules mandatory.
5. **HUD polish:** compact rounded shape, actual input-level motion while recording, a quiet processing indicator, and an understandable recovery state. Use text/accessibility labels as well as color. Do not show a live transcript unless genuine streaming exists.

Verify the slice with a fresh build and keyboard/visual review: empty and populated Home/History, search, copy, deletion, changing mode, missing permissions/models, short successful dictation, and failed insertion recovery. Do not change the working global insertion behavior merely to match a competitor's presentation.

## Unconfirmed and conflicts

| Question | What was checked | Consequence |
|---|---|---|
| Exact current Wispr desktop Hub styling | Official documentation and installed 1.6.774 onboarding inspected; main Hub blocked by sign-in. User asked to continue without it. | Do not treat the website or onboarding as proof of the main Hub layout. |
| Flow desktop HUD docking | Accessibility documentation describes desktop edge docking; Flow Bar troubleshooting says edge-docking/drag belong only to Android. | Treat desktop docking as unconfirmed; do not base this slice on it. |
| Exact Superwhisper screenshot version | User-supplied workspace screenshots and current official docs. | Treat local screenshots as visual direction, not current feature/version proof. |
| Competitor vocabulary algorithms | Official behavior documentation only. | Do not infer proprietary implementation or promise identical accuracy. |

## Open questions

- Which history-retention default best fits Quibble's local-first promise? Make the chosen policy visible and reversible.
- Audio playback and retry would improve recovery further, but should follow a deliberate storage/retention decision.

## Live desktop inspection, 2026-09-05

The user opened the installed **Superwhisper 2.18.3** settings window. Version was read from `/Applications/superwhisper.app/Contents/Info.plist`; the following observations come directly from its native accessibility tree and screenshots, not its website:

- The settings window is compact (approximately 750 × 500). Its persistent sidebar keeps Home, Modes, Vocabulary, Configuration, Sound, Models library, and History readily available.
- Modes first appear as compact summary rows. Opening a mode reveals grouped preset/tone, language/voice model/language model, application activation, and shortcut controls; advanced settings are collapsed. Quibble currently has two working modes, so two example cards remain appropriate without adding unsupported controls.
- Vocabulary has one prominent add field, an Enter shortcut, and sparse word/replacement rows. This reinforces keeping preferred-word entry simple and explicit replacement rules secondary.
- Configuration uses visual theme and recording-window choices, followed by grouped shortcut rows with keycaps and short explanations.
- Models library is a searchable, filterable table with installed size, type, favorites, and local/cloud indicators. Quibble's smaller all-local catalog does not require copying the larger provider table.

No Superwhisper settings or vocabulary were changed during inspection. The comparison supports a calm daily-use surface with progressively disclosed configuration; it does not establish anything about proprietary recognition algorithms.

**Wispr Flow 1.6.774** was downloaded from its [official direct-download endpoint instructions](https://docs.wisprflow.ai/articles/6203703148-redirect-loops-when-attempting-to-download-the-app-from-the-wispr-flow-website) and installed in `/Applications/Wispr Flow.app`. Its Developer ID signature verified and Gatekeeper accepted its notarization. Initial live inspection shows a staged signup/permissions/setup/learn/personalize flow, a single browser sign-in action, and illustrated examples. The main Hub requires sign-in. The user reported a problem with its sign-in window and explicitly asked to continue without Flow. Its main Hub and live dictation controls remain unverified; no account was created or permissions granted by the agent.
