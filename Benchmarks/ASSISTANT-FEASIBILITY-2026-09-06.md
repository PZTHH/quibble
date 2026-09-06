# An optional assistant for Quibble

Retrieved: **2026-09-06**. Directional after: **2026-09-13** for prices and model defaults; recheck API/account requirements before implementation. This is an architecture and product recommendation, not an API integration or a measured model evaluation.

**Build scope:** GPT assistance and online ASR are proposed next integration slices. They are **not activated in this visual build**. The interface work does not connect accounts, upload speech/context, start background listening, or grant an assistant access to email. No API-key bootstrap tool was available in the current tool inventory; this research needed no credential.

## Recommendation

Build a hybrid app with two clear intentions: **Dictate** and **Ask**. Dictate should preserve today's quick, predictable text insertion. Ask should turn a spoken instruction plus deliberately attached context into a useful answer or editable draft. Local transcription remains a choice; it need not constrain the assistant's intelligence.

The best first experiment is: **hold an Ask shortcut → speak → optionally include selected text or the current window → receive an editable email/rewrite draft → insert it**. This directly addresses the user's example and tests whether avoiding a trip to a chat app is valuable. Restaurant research is a second, read-only action with visible sources. Background listening and sending email should follow evidence from those smaller tasks.

This recommendation is an inference from the verified interfaces below and Quibble's current architecture. It is not evidence that customers will prefer the feature. A generally capable assistant is technically plausible; reliably deciding when to act, acquiring the right context, and communicating its actions are the harder product problems.

## What is possible now

All sources in this table were opened or fetched on **2026-09-06**; claims apply to those documented interfaces, not to an implementation already present in Quibble.

| Capability | Verified basis | Implication for Quibble |
|---|---|---|
| Send a transcript and image to GPT | Responses accepts text/image input, and vision input can be supplied as a base64 data URL. [Responses reference](https://developers.openai.com/api/reference/cli/resources/responses/methods/create), [Images and vision](https://developers.openai.com/api/docs/guides/images-vision) | A local transcript and one requested screenshot can be a bounded request. The model does not automatically see the user's desktop. |
| Capture a chosen window on macOS | Apple's ScreenCaptureKit sample supports window/display filters and requests Screen Recording permission. [Apple capture guide](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos) | Prefer selected text first; offer a window thumbnail attachment when text is unavailable or layout matters. The existing Accessibility grant should not be presented as screen-capture permission. |
| Run explicit external actions | Function calls return arguments; application code executes the action and returns its result. [Function calling](https://developers.openai.com/api/docs/guides/function-calling) | Quibble must implement the executor, validation, state, errors, and confirmation UI. A model response alone is not evidence that an email was sent. |
| Research places to eat | Responses web search retrieves current information and returns URL citations, which must be visible and clickable. [Web search](https://developers.openai.com/api/docs/guides/tools-web-search) | Start with recommendations using a user-supplied area, preferences, and source links. A booking requires a separate provider integration and explicit action. |
| Connect accounts and MCP tools | Responses connectors require an OAuth access token supplied by the application. MCP tool access can be filtered and approval-controlled; remote servers must be trusted. [MCP and Connectors](https://developers.openai.com/api/docs/guides/tools-connectors-mcp) | Account connection is a real feature with lifecycle management. Existing ChatGPT/Codex connections should not be assumed to transfer to a Responses integration. |
| Create and send email drafts | Gmail exposes distinct draft creation and sending operations. [Gmail drafts](https://developers.google.com/workspace/gmail/api/guides/drafts) | Start by drafting inside Quibble and inserting into the user's compose field. Later offer provider-backed drafts, followed by an explicit Send action. |
| Email authorization | Gmail's `gmail.compose` scope includes draft management **and sending** and is restricted; `gmail.send` is sensitive. Public apps using relevant scopes have verification requirements, and transmitting/storing restricted data on servers can require a security assessment. [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes) | “Draft-only” must be enforced by Quibble's exposed tools even if the OAuth token permits sending. Do not describe a broad token as technically unable to send. |

### Responses, Realtime, or Codex?

| Approach | Fit and tradeoff | Recommendation |
|---|---|---|
| Responses with a completed local transcript | One bounded request, optional context, streamed text, and controlled tools. Quibble owns the small amount of conversation state it needs. [Responses reference](https://developers.openai.com/api/reference/cli/resources/responses/methods/create) | **First implementation.** Appropriate for formatting, drafting, questions, and deliberate actions. |
| Realtime voice agent | Keeps an audio connection open and supports live assistant conversation. Transcription-only sessions produce text without assistant responses; these are separate session purposes. [Realtime guide](https://developers.openai.com/api/docs/guides/realtime) | Add when back-and-forth speech, interruption, or spoken responses become a demonstrated need. It adds streaming/session/turn management; it is not required for push-to-talk email drafting. |
| Codex SDK | Official guidance emphasizes programmatic coding/internal workflows. The TypeScript SDK needs Node 18+; the Python SDK controls a local app-server and includes a pinned runtime dependency. [Codex SDK](https://learn.chatgpt.com/docs/codex-sdk) | Useful for a later coding assistant or internal experiment. It introduces another runtime into a lean native dictation app. |
| Codex app-server | Designed for custom clients with authentication, history, streamed events, and approvals. Managed ChatGPT OAuth and API-key authentication are documented. External-token auth and some dynamic tooling surfaces are experimental. [App-server](https://learn.chatgpt.com/docs/app-server) | **Technically viable alternative**, particularly if a full Codex client is the desired product. Pin and test its runtime/protocol and own the approval/account UI. This is substantially broader than a text refinement stage. |

Codex subscription login and general API access are separate integration choices. Official authentication guidance describes ChatGPT subscription access, API-key usage billing, and Platform API keys for general API calls. Do not reuse private desktop session credentials or promise the user's existing subscription covers Quibble's Responses usage. Commercial distribution/branding and exact end-user entitlement for a custom Codex client remain unconfirmed in this investigation. [Authentication](https://learn.chatgpt.com/docs/auth), read 2026-09-06.

### Activation without constant device load

These are proposed interaction designs, not measured results:

1. **Dedicated Ask shortcut:** reuse the reliable press/release path; show an unmistakable Ask state before recording. No intent classifier is needed to decide whether ordinary dictation is an instruction.
2. **“Hey GPT” inside an explicitly started recording:** after local ASR, an unambiguous leading phrase could switch to Ask. Show the recognized instruction for review. Quoted examples and “don't ask GPT…” need negative tests. This is not an always-on wake word.
3. **Optional local wake word later:** a small detector can gate the main recorder, leaving ASR/refinement unloaded while idle. Porcupine documents macOS support and custom trigger models, with an AccessKey requirement. Its Mac energy use, licensing fit, false activations, and the phrase “Hey GPT” have not been tested here. [Porcupine](https://picovoice.ai/docs/porcupine/), [macOS support](https://picovoice.ai/docs/quick-start/porcupine-macos/), read 2026-09-06.
4. **“Timestamps” needs clarification before building:** it could mean scheduled listening windows, a timed temporary listening session, or markers inside a recording. These imply different products. Scheduling should enable a visible listening mode only after explicit setup, not silently create permission to transmit ambient conversations or execute tasks.

## Context that does not repeat old text

Proposed request structure: separate fields for the **spoken instruction**, **selected text to transform**, and **background window context**. Context is evidence; it is never prepended to the output transcript and never treated as a source of new instructions.

Capture only when Ask starts or the user attaches context. Show an app/window chip and an inspectable preview; allow removing it. Prefer exact selected text, then bounded accessible text, then a single requested screenshot. Avoid continuous screenshot polling or full-document crawling. Exclude secure fields and user-excluded apps, expire old captures, and verify the destination again before insertion if the active app changed.

For “format this into an email to this person,” return an editable subject/body and a recipient candidate with provenance. Missing or ambiguous recipient information stays a question or empty field; it must not become an invented email address. Initially offer **Insert**, **Copy**, and **Discard**. External text may contain instructions to an assistant; tool authorization must come from the user's request and app policy, not from text visible in an email or website.

This preserves the user's desire for intelligent context while containing the specific earlier failure: app text leaking into every dictation.

## External transcription providers

| Adapter | Verified interface and vocabulary support | Compatibility constraints |
|---|---|---|
| OpenAI file transcription | Current guidance recommends `gpt-transcribe` at `/v1/audio/transcriptions`. It accepts `prompt`, literal `keywords`, and expected `languages`; keywords are hints, not guaranteed output. Supported uploads include WAV, with a 25 MB limit. [File transcription](https://developers.openai.com/api/docs/guides/speech-to-text), read 2026-09-06 | Existing bounded WAV capture is a natural input. Validate provider-specific hint characters/limits; do not send the singular `language` field together with `languages`. Word timestamps, diarization, and translation have specialized model/format requirements and need separate capability flags. |
| Deepgram Nova-3 | Its prerecorded API accepts uploaded audio; Nova-3 has `keyterm` prompting for monolingual and multilingual recognition. Terms are repeated query parameters without weights, with a 500-token budget. [Prerecorded audio](https://developers.deepgram.com/docs/pre-recorded-audio), [Keyterm prompting](https://developers.deepgram.com/docs/keyterm), read 2026-09-06 | A separate provider adapter is required; this is not the OpenAI multipart contract. Encode each term correctly and choose a bounded relevant subset. Supplier accuracy claims are not Quibble benchmarks. |

Concrete first adapter contracts, verified from those same provider guides:

- **OpenAI:** `POST https://api.openai.com/v1/audio/transcriptions`, bearer authentication, multipart WAV `file` plus `model=gpt-transcribe`; optional `keywords[]`, `languages[]`, and `prompt`. Normalize JSON `text` and returned `languages`; keep provider details outside the insertion pipeline.
- **Deepgram:** `POST https://api.deepgram.com/v1/listen?model=nova-3`, `Authorization: Token …`, `Content-Type: audio/wav`, raw WAV body, and separately encoded repeated `keyterm` query parameters. Normalize `results.channels[0].alternatives[0].transcript`; retain provider timing/confidence only when present. Make smart formatting an explicit behavior choice to avoid cleaning the same text twice.

Proposed abstraction: `TranscriptionProvider` owns request encoding, supported languages/hints, normalized output, timeout/cancel behavior, and usage metadata. Capability badges should come from these concrete adapters. An “OpenAI-compatible” custom endpoint should be an advanced option with a connection test and declared features, not assumed to implement every hint/timestamp field.

Make **On this Mac** and **Connected services** separate choices in the simplified library. Download only a selected local model and its active workflow dependencies. Cloud ASR can keep local model weights unloaded; the microphone, audio encoding, network traffic, and any remaining local vocabulary helper still consume resources. For minimum load, evaluate each cloud provider's native hints first, and make a local audio helper optional rather than an invisible second ASR run. Never send audio to a cloud fallback just because local inference failed unless the user has enabled that behavior.

## Cost, latency, and privacy

Current standard short-context prices provide a scale, not a quote: GPT-5.6 Luna is $0.20 per million input tokens and $1.20 per million output tokens; GPT-5.4 Mini is $0.75/$4.50; `gpt-transcribe` is $0.0045/minute; web search is $10/1,000 calls plus search-content tokens. A hypothetical 2,000-input/500-output-token text request costs **$0.001–$0.00375** across those two text models, excluding images, cache writes, reasoning/output beyond the assumption, tools, and backend overhead. One search adds at least **$0.01** in tool fees. Ten daily transcription minutes for 30 days would be **$1.35** in transcription charges. These are arithmetic scenarios, not observed Quibble costs or quality rankings. [OpenAI pricing](https://developers.openai.com/api/docs/pricing), read 2026-09-06.

Use a small vision/tool-capable model as an evaluation candidate, escalating only when tests justify it. Luna's documented image input, function calling, and web-search support make it a candidate; no quality or latency claim is established by its feature list. [Luna model page](https://developers.openai.com/api/docs/models/gpt-5.6-luna), read 2026-09-06.

Measure release-to-first-result and release-to-usable-result on the actual network, with cold and warm local ASR. Keep context/output bounded, perform one generation for a simple draft, avoid an extra classifier call, stream review text, and cancel promptly. Do not automatically insert a partial stream. For cloud ASR, compare “upload on release” with explicitly enabled live transcription before committing to the extra session complexity.

API content is not used for training by default. Responses can retain application state by default; `store:false` avoids that normal response storage but does **not** mean zero retention. Abuse-monitoring and caching exceptions remain; third-party MCP servers have their own policies. The data guide lists `/audio/transcriptions` separately with no abuse-monitoring or application-state retention. Keep endpoint-specific disclosures accurate and recheck them before release. [Your data](https://developers.openai.com/api/docs/guides/your-data), read 2026-09-06.

For a personal beta, the user's own provider key can be entered explicitly and stored in Keychain. For a distributed service funded by Quibble, keep the developer's key in a backend with user authentication, quotas, and spending controls. Never bundle that key or log authorization headers. This design follows the official requirement to secure API keys and avoid hard-coding secrets. [Production best practices](https://developers.openai.com/api/docs/guides/production-best-practices), read 2026-09-06.

## A small, useful implementation sequence

These are recommendations rather than completed work:

1. **Finish simplifying the current app.** Present one speech engine and one text behavior. Hide local cleanup versus instruction-model mechanics in advanced details; retain working local models until cloud behavior is evaluated. “As spoken,” “Polished,” and later “Ask” express user intent better than loading three model families into the main navigation.
2. **Add the provider/account foundation.** Explicit cloud opt-in, Keychain storage, model/capability metadata, cancellation, usage visibility, and no silent local-to-cloud fallback. Implement one external ASR adapter first; benchmark the second before exposing a long catalog.
3. **Ship an internal Ask draft experiment.** Local ASR plus one Responses request, selected-text attachment, optional requested window capture, editable result, safe insertion, and no email sending tool. A single cloud text provider can handle both cleanup and instructions, removing that distinction from the ordinary UI.
4. **Add useful read-only tools.** Restaurant research with current sources and user-selected location; optional account-based context only when it materially beats selecting text.
5. **Add provider-backed drafts and actions.** Separate prepare/review/commit, recipient checks, request deduplication, result verification, and actionable failures. Retry reads safely; after an ambiguous send timeout, reconcile provider state before sending again.
6. **Consider wake words and Realtime.** Proceed only if repeated use shows that the shortcut or silent text result is an actual obstacle.

## Evaluation before claiming it is better

Proposed acceptance experiment: use 40–60 consented or synthetic tasks across short email drafts, replies, rewrites, questions, and restaurant requests. Compare direct dictation, current local cleanup, Ask with transcript only, and Ask with explicit context. Score task completion, preservation of names/numbers/intent, unsupported additions, recipient accuracy, manual edits, completion time, measured cost, and device energy/memory. Include failed capture, changed windows, empty speech, network loss, cancellation, and hostile instructions embedded in context.

Critical regression gates: no writes from ordinary dictation; no surrounding text copied unless requested; no generated missing facts treated as known; no duplicate sends after retry; no context/audio upload while Ask/cloud is disabled. Vocabulary evaluation should count both corrected target names and false replacements in ordinary words.

For usefulness, run a short personal trial first, then a small pilot: record which tasks users repeat voluntarily and whether the feature saves time after review/correction. Satisfaction, willingness to connect email/pay, and preferences for wake words are **unconfirmed**. Existing competitors and available APIs demonstrate possibility, not appreciation. If context adds more correction time than it saves, keep transcript-only Ask as the default.

## Local baseline and open questions

Read-only inspection on 2026-09-06 found no cloud provider client in `App`, `Sources`, or the inference sources. `DictationController` forcibly pauses nearby-text context, captures the insertion target separately, and unloads idle inference after 120 seconds. `DictationWorkflow` supports vocabulary, S1 cleanup, and custom-prompt steps. `LocalInference` owns those local model containers. These are useful boundaries for adding a provider abstraction; they are not evidence of an assistant integration already being present.

The workspace has no Git revision. Snapshot SHA-256 values at inspection time:

| File | SHA-256 |
|---|---|
| `App/DictationController.swift` | `438c7cd099450db73a9c0f18b16fe9266b6d7bf51f629e1ae552d2650072241e` |
| `Sources/QuibbleCore/DictationWorkflow.swift` | `a597561d03e0ba934109061fdbe8c3c929c6e3771dbc1c7327610d37a6e300e7` |
| `Inference/Sources/QuibbleInference/LocalInference.swift` | `344b9c9cd5b21875b03be2e69d94863c2ce31007f120591b5a25d63f06f0205f` |

Unconfirmed: “timestamps” meaning; preferred email provider; exact API/account availability for the eventual user population; custom Codex-client distribution terms; real network latency and energy; wake-word licensing/performance; and whether users prefer this over switching to their existing assistant. These were not resolved by documentation, and no credentials, private email, paid inference, or account connections were accessed for this report.
