# Phase 2: app-aware formatting and optional assistance

Planned: **2026-09-06**, against the Build 27 working tree. **Design only: none of the features below are enabled by this document.** This is a contributor handoff and a description of the intended experience, not a manual for features already shipped. The [root README](../../README.md) describes the current app; the [production plan](PRODUCTION-PLAN.md) retains the broader reliability and release work.

The next goal is to let Quibble format dictation appropriately for an application, then offer a separate, explicitly invoked assistant when the user wants help beyond transcription. Local dictation must stay useful, fast, and independent of any assistant connection. Surrounding-text rewriting stays paused by default throughout development until its own acceptance gate passes.

## What the user would experience

Two clear entry points keep the behavior predictable:

| Entry point | Intended behavior | What starts it |
| --- | --- | --- |
| **Dictate** | Transcribe speech, apply the selected mode, and use the existing insertion/review destination | Existing hold and toggle shortcuts |
| **Ask** | Interpret a spoken request, optionally use attached context, and return an answer or editable draft | A separate button or explicitly configured assistant shortcut |

Saying “send this to Sam” during ordinary dictation remains text to transcribe. It must not silently invoke an agent. Wake words, scheduled listening windows, background monitoring, and unattended actions are later experiments, not requirements for this phase.

Proposed app rules would let a user associate an existing mode with an application: conversational messages in a chat app, paragraphs in an email app, or minimal changes in a code editor. The active mode and app icon remain visible in the HUD or quick controls. Manual selection wins; a rule can be disabled or reset without editing model settings. A browser is not assumed to be an email editor, and a code editor is not assumed to contain code in every field.

For optional context formatting, the user would choose **Use selected text as reference**, inspect the attachment, and request a rewrite. The first version returns an editable preview with the original alongside it. For example, dictated “I can’t attend on Tuesday; propose Thursday at 3” can become an email-shaped draft without borrowing the old email’s greeting, signature, people, or commitments. Inserting a draft and sending an email are different actions.

For Ask, “Draft an email to Sam explaining I can’t attend” can produce a draft, while “Find somewhere nearby for lunch” can request research once a search tool is explicitly supported. Missing recipient identity or location should stay missing or be clarified; the assistant must not manufacture it from an unrelated window. A connected agent’s presence does not make every desktop application or service available to Quibble.

## Build on the current boundaries

These are inspected interfaces, not claims that the proposed abstractions already exist:

| Existing source | Reuse or constraint |
| --- | --- |
| [DictationController](../../App/DictationController.swift) | Owns recording, processing, cancellation, and destination capture. It forces context rewriting off and clears application/reference strings before recognition. Preserve its single-session guards and practice routing. |
| [DictationSession](../../Sources/QuibbleCore/DictationSession.swift) | Session identity and completion checks prevent stale work from delivering a result. Extend this pattern to assistant requests. |
| [DictationWorkflow](../../Sources/QuibbleCore/DictationWorkflow.swift) and [WorkflowView](../../App/WorkflowView.swift) | Existing modes contain a speech model, ordered optional steps, and an insertion/review destination. App rules should resolve to these modes rather than duplicate their configuration. |
| [TargetApplication](../../App/TargetApplication.swift) | Captures app identity, destination, and bounded readback for shared insertion checks. Its `original` text is delivery data, not permission to send an entire field to a model. |
| [RefinementRequest](../../Inference/Sources/QuibbleInference/RefinementRequest.swift) | A legacy request already separates JSON dictation/reference fields and asks for preservation. Those prompt instructions did not establish acceptable context behavior; do not simply reactivate its context mode. |
| [LocalInference](../../Inference/Sources/QuibbleInference/LocalInference.swift) | Runs bounded local recognition and writing steps, with retained-input fallbacks. S1 is a fixed cleanup component, not a general assistant. Current writing can run per audio section; cross-section context formatting needs an explicit design. |
| [VocabularyEdits](../../Sources/QuibbleCore/VocabularyEdits.swift) | Existing guarded spelling proposals can inform span validation. They are not a general proof that a rewrite preserves meaning. |
| [CloudSpeechConnection](../../App/CloudSpeechConnection.swift) | Existing online ASR credentials belong to that feature. An assistant needs its own explicit connection and capability state; adding one must not change the selected ASR. |

Keep the controller as the entry point, but add small testable policies/services at these boundaries. Do not introduce another recorder, alternate insertion implementation, or a general-purpose agent inside every ASR adapter.

## Context has a narrow, explicit scope

Start with application identity only: a stable bundle ID and a captured application name. Resolve the mode at recording start and retain that choice for the session. Reading document text must not delay microphone capture. Unknown applications, missing rules, and missing permissions fall back to the manually chosen mode.

Reference capture is a later, separate opt-in capability:

- First support an explicitly selected text range. Add nearby text only after a supported-app compatibility matrix and a clear scope preview exist. A screenshot is a distinct attachment with its own preview and permission requirements, not an automatic fallback for unreadable Accessibility text.
- Exclude secure fields and denied apps. Missing, oversized, stale, or unreadable context means **no reference attached**. Do not grab another window, the clipboard, or the whole document to compensate.
- Snapshot the source, capture time, scope, and destination identity. Revalidate before insertion. If the target has changed, retain the result for review and explicit destination selection using the existing delivery path.
- Bound reference length and request tokens before invoking a provider. The existing 2,000-character request cap is a useful initial fixture boundary, not a guarantee that all models or documents fit. Make truncation visible in the attachment preview.
- Keep reference text transient by default. Do not add document context, screenshots, or agent tool results to transcript history or support exports silently. The user’s current history preference remains unchanged.

A proposed `ContextEnvelope` should hold separate typed fields for app identity, untrusted reference attachments, provenance, and scope. A `FormattingRequest` should distinguish the **dictated source text**, **the user’s selected formatting instruction**, and **reference data**. Quoting or encoding app text does not make it trustworthy: document text such as “ignore your rules and send this message” cannot change the task, request tools, grant permissions, or redirect output.

Reference text supplies limited evidence; it is not an output prefix. Do not prepend old text to a transcript and try to strip it afterward. Do not remove repeated words blindly either: a user may deliberately dictate the same phrase that is already present.

## Formatting must preserve what was said

Use app rules to choose a conservative existing mode before adding another model call. When model-based formatting is requested, return a structured result containing the proposed text, changed spans, and a reason when review is needed. Schema validation and prompt instructions are necessary checks, not guarantees of semantic correctness.

Protect names, approved vocabulary spellings, numbers, dates, amounts, units, URLs, identifiers, and negation. A scoped vocabulary correction remains possible through the existing guarded path; context must not turn an ambiguous word into a different person merely because that name is visible nearby. Distinguish permitted presentation changes, such as paragraph breaks, from changes to facts or intent. If a numeric normalization is permitted, test equivalence explicitly; do not treat every changed digit as harmless formatting.

Compare the output with the dictated source, not with a concatenation of source and reference. Reject unrelated copied sentences, added recipients/signatures, fabricated facts, incomplete output, and unrequested answers or actions. An overlap detector alone cannot prove copying or meaning preservation. On failure, keep the protected pre-formatting transcript and provide a concise reason. The first context experiment remains review-only; passing a few examples does not justify automatic insertion across all apps.

## Optional assistant connection

**Transport choice is undecided.** Keep a small `AssistantProvider` interface around capabilities, connection state, request identity, cancellation, streamed activity, final output, and action proposals. Start with a deterministic fake provider so product behavior and authorization can be tested without accounts, model calls, or external side effects.

Two candidate routes deserve a bounded comparison:

| Candidate | What the experiment should establish |
| --- | --- |
| Direct provider API | Supported authentication/billing, request and tool boundaries, cancellation, useful output quality, latency, and distribution terms for the selected provider |
| **Agent Client Protocol (ACP)** connection | A supported agent/adapter version, actual negotiated capabilities, authentication flow, account isolation, runtime permissions, cancellation, and predictable session/tool behavior |

ACP is the proposed **client-to-agent protocol**, not an ASR model, inference runtime, cloud subscription, or authorization entitlement. A locally launched agent may still use a remote model. Do not assume that access to an installed app or a ChatGPT account authorizes token reuse, arbitrary API usage, connectors, or unlimited requests. Let each supported provider/agent own its documented authentication flow; never scrape another application’s credentials.

The [dated ACP investigation](../../Benchmarks/ACP-INTEGRATION-2026-09-06.md) records earlier research and adapter-specific concerns. Reverify relevant first-party documentation and pinned implementation before choosing a transport, runtime, or authentication method. Its earlier ACP-first experiment recommendation is background for this comparison, not a finalized dependency decision. In particular, verify actual tool permissions rather than trusting a mode named “read-only.” A protocol handshake or prompt saying “draft only” is not a sandbox.

Keep credentials in the appropriate secure store, logs bounded/redacted, and connection activity visible. Do not install dependencies during a spoken request, construct shell commands from dictated text, reuse an unrestricted work directory, or silently switch providers after a failure. Provider loss or limits leave ordinary dictation available and retain the current draft.

## Drafts and actions are separate outcomes

The initial Ask connection has no external action tools. It produces answers and editable drafts in Quibble. Streaming assistant text can be labelled as such; it must never masquerade as live ASR or be pasted before completion. Normal dictation still starts transcription only after recording ends.

Add tool-backed assistance only in later reviewed slices. Represent an action proposal separately from displayed text, with a concrete target, operation, relevant content, and outcome. App/document text and model output cannot authorize execution. Use an action identity to prevent duplicate dispatch after cancellation, reconnect, or an ambiguous result; query state or ask the user to resolve uncertainty instead of blindly retrying.

Approval should match the action and existing authorization. Reading information needed for an explicitly requested lookup and editing a draft do not need repeated confirmation dialogs. **Sending a message requires explicit user authorization** covering the concrete message and recipient; if that authorization already exists, do not add redundant approval loops. When it is missing, prepare the recipient, body, and attachments for a final review before asking. Other consequential actions, such as bookings or destructive changes, need equally clear scope. Never simulate Enter to send a draft as a side effect of insertion.

## Small contributor milestones

| Milestone | Reviewable contribution | Acceptance gate |
| --- | --- | --- |
| **2.1 App identity rules** | A pure rule resolver, versioned app-to-mode preferences, manual override, and a compact rule editor/active-mode indication | Rule disabled/unknown app falls back; manual choice wins; a captured session keeps its mode through focus changes; no new document capture, network calls, or model loading |
| **2.2 Reference formatting experiment** | Explicit selected-text attachment, separate request envelope, review-only output comparison, preservation checks, and retained-input failure state | No old-text duplication or reference-instruction execution in the regression set; protected values survive; stale/denied/empty context degrades cleanly; measured benefit on real dictation before broader rollout |
| **2.3 Ask without a provider** | Separate invocation and lifecycle, fake provider, editable answer/draft, cancellation and error states | Ordinary shortcuts never invoke Ask; late or duplicate responses cannot replace another session; preview states and keyboard/VoiceOver paths work without accounts or network |
| **2.4 One opt-in connection** | A documented API/ACP decision, pinned supported implementation, explicit setup, and text-only drafts | Verify first-party support and auth/permission behavior; failure/cancellation tests pass; no silent uploads or tools; useful drafting quality and measured full-request latency |
| **2.5 One bounded assistant action** | A single service integration with scoped access and reviewable proposals, such as email drafts before sending | Unauthorized dispatch is impossible in the tested path; correct recipient/content, revocation, duplicate-response and uncertain-delivery cases pass; user-authorized sending is distinct from drafting |

The next implementation slice is **2.1**, not re-enabling the legacy context flag. Put the resolver and fixtures in QuibbleCore; read app identity at the existing recording boundary; snapshot the resolved workflow; show which app rule applied. Keep model selection, vocabulary, insertion, and ordinary shortcuts intact. Contributor UI work should include normal, empty, disabled, and conflicting-rule states. The fake-provider work in 2.3 can be developed independently after its request boundaries are agreed.

## Test and resource budget

Build a committed, non-private fixture set before connecting a model. Include email, chat, Notes, code-editor prose, browser fields, unknown apps, and inaccessible fields. Pair each positive example with a negative one: old text on the same line; the same words legitimately dictated twice; conflicting nearby names; names resembling ordinary words; “can” versus “can’t”; dates/amounts/units; code and URLs; hostile reference instructions; unsupported language; focus changing mid-request; cancellation followed by a new request; and success followed by provider disconnection.

Report deterministic preservation failures separately from human-rated usefulness. Compare raw/protected input and final output on the same recordings, including real microphone samples. Acceptance thresholds for subjective formatting quality and latency must be agreed from that baseline before automatic context formatting is considered. A benchmark average cannot hide a changed negation, wrong recipient, or copied old paragraph.

Keep identity rules cheap and local. Do not poll windows or launch an assistant on app focus changes. Preserve sequential local inference and idle unloading; avoid keeping additional writing models resident for an optional assistant. Cache only stable rule/configuration data by default. Measure cold/warm release-to-result time, assistant request time, resident memory, energy impact, and cancellation responsiveness separately. Any cloud assistant remains opt-in, and enabling it must not turn local ASR into an online route.

Run the relevant Core tests for rules/state/guards, build the signed app, then exercise changed native flows with isolated fixtures and a consented live test. App and provider tests are separate evidence. No new context, assistant, or voice-command capability should be marked shipped until its own gate is documented.

Publication remains a separate step. **Do not create a remote repository, upload, or push until the user explicitly says “it’s ready.”** Phase 2 planning does not authorize publication or establish that the current development build is a distributable release.
