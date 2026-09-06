# ACP as an assistant connection for Quibble

Retrieved: **2026-09-06**. Directional after: **2026-09-13** for adapter/runtime versions and **2026-09-20** for protocol guidance. All linked sources below were fetched on the retrieval date. No agent was installed, authenticated, or prompted; no app source was changed for this report.

## Recommendation

The likely intended name is **Agent Client Protocol (ACP)**; “agent context protocol” is ambiguous. ACP is a plausible way to connect Quibble's **Ask** interface to an existing agent such as Codex. It can replace Quibble's own direct model request layer with a local agent connection. It does not remove cloud inference, account requirements, usage limits, or the work of controlling permissions and context.

Given the user's preference, implement an **optional ACP connection experiment**, beginning with protocol tests and explicit, text-only drafting. Keep ordinary Dictate independent. The simple product experience should be “Connect an assistant → Ask → review result,” while adapter/version and permission details live in diagnostics.

This revises the earlier Responses-first recommendation: ACP now deserves a first prototype when using an existing agent/account is a priority. Direct Responses remains the smaller dependency surface for a tightly controlled cloud text feature. Direct Codex app-server remains a reasonable alternative if Codex is the only intended agent. The tradeoff is portability versus another compatibility layer, not local versus cloud intelligence.

## The three interfaces are different

| Interface | What it connects | Role in Quibble |
|---|---|---|
| **ACP** | A client UI and an agent, including sessions, streamed output, context, and permission requests. The protocol explicitly permits client UIs beyond code editors. [ACP overview](https://agentclientprotocol.com/protocol/v1/overview) | Quibble becomes a client; it can render agent activity without implementing every agent's native protocol. |
| **MCP** | An AI application and external tools/data sources. [MCP introduction](https://modelcontextprotocol.io/docs/2026-07-28/getting-started/intro) | Email, search, or Quibble-specific actions can be tools used by the connected agent. MCP does not supply the assistant UI, model account, or speech transcription by itself. |
| **Codex app-server** | A custom client and the Codex runtime, with authentication, conversation history, approvals, and streamed events. [Official OpenAI app-server documentation](https://learn.chatgpt.com/docs/app-server) | Direct Codex integration, or the underlying connection used by the maintained Codex ACP adapter. |

Proposed data flow:

```text
User starts Ask → Quibble transcribes speech → explicit instruction + selected context
             → ACP adapter → Codex app-server → model/service
             ← streamed answer and action requests ←
             → editable result → user chooses Insert
```

The arrow to the model/service remains a network boundary. A local subprocess is not evidence that its inference is on-device.

## Current maintained Codex adapter

The old `zed-industries/codex-acp` README directs new installations to **`@agentclientprotocol/codex-acp`**. The maintained adapter runs over stdio, starts Codex app-server, and translates requests/events. Its README documents ChatGPT/API-key authentication, text/images/embedded context, configuration, MCP integration, and tool events. [Migration notice](https://github.com/zed-industries/codex-acp/blob/296069e841634cd4bb9bc4515602d836e49231ec/README.md), [adapter README at v1.10.0](https://github.com/agentclientprotocol/codex-acp/blob/v1.10.0/README.md).

The latest release fetched was **v1.10.0**, published **2026-09-04**, at commit `061f9a4a2e463a220d7a3ab2ae5e9732837085ef`. Its lockfile resolves ACP SDK **1.4.0** and Codex **0.153.3**. The package manifest permits a Codex semver range, so reproducible distribution needs a tested locked dependency set. [Release](https://github.com/agentclientprotocol/codex-acp/releases/tag/v1.10.0), [manifest](https://github.com/agentclientprotocol/codex-acp/blob/v1.10.0/package.json), [lockfile](https://github.com/agentclientprotocol/codex-acp/blob/v1.10.0/package-lock.json).

Local read-only inspection found `/opt/homebrew/bin/codex`, version **0.151.0**. Its help exposes app-server/stdio support but no native `acp` subcommand. Compatibility with adapter 1.10.0 was **not tested**. Prefer the adapter's tested Codex dependency; do not force `CODEX_PATH` to this older installed CLI merely because it exists.

Tagged adapter source advertises loading, resuming, listing, closing and deleting sessions, plus image/embedded context support. It does **not** advertise audio input. Quibble should pass its transcript, not assume the adapter is an ASR endpoint. [Initialization implementation](https://github.com/agentclientprotocol/codex-acp/blob/v1.10.0/src/CodexAcpServer.ts).

## Account and subscription reality

ACP discovers auth methods during initialization; the client follows the advertised flow rather than inventing a login procedure. [ACP authentication](https://agentclientprotocol.com/protocol/v1/authentication). The Codex adapter offers browser ChatGPT login, API-key auth, and capability-gated device-code/custom-gateway methods. [Tagged auth implementation](https://github.com/agentclientprotocol/codex-acp/blob/v1.10.0/src/CodexAuthMethod.ts).

Official OpenAI guidance distinguishes ChatGPT subscription access from API-key usage billing. Workspace entitlements and policies still apply; general API calls still use Platform API credentials. [Authentication](https://learn.chatgpt.com/docs/auth). A successful Codex login can therefore provide an agent path without a separately entered model API key, but ACP itself grants no subscription entitlement or unlimited/free usage. Exact Quibble end-user eligibility, commercial distribution terms, shared-account behavior, and connector availability remain **unconfirmed**.

Let the agent own supported authentication. Do not read private desktop tokens, copy credentials, silently reuse another app's account, or imply a Quibble logout necessarily signs out only Quibble. Inspect account/profile isolation and retention behavior before offering shared sessions.

## Implementation conditions that matter

**Protocol:** target negotiated ACP **v1** first. The currently published v2 announcement marks it draft and advises against enabling it by default in production. [v2 status](https://agentclientprotocol.com/announcements/acp-v2-draft). Initialize and check actual capabilities; missing capabilities are unsupported. [Initialization](https://agentclientprotocol.com/protocol/v1/initialization).

**Transport:** v1 stdio is UTF-8 newline-delimited JSON-RPC; stdout contains protocol messages and stderr carries logs. HTTP remains a draft transport in the fetched v1 guide. [Transports](https://agentclientprotocol.com/protocol/v1/transports). Proposed client: an asynchronous Swift process/pipe connection with framing limits, request IDs, separate bounded/redacted logs, process-exit handling, and no UI-thread blocking. Launch a vetted executable directly with arguments, not a shell assembled from dictated text. Avoid downloading `npx latest` during a user's Ask request.

**Permissions:** ACP is a trusted-agent integration, not a sandbox. Agents execute tools and may request approval; refusing to expose client filesystem/terminal methods does not remove the agent's own filesystem/shell tools. [Architecture](https://agentclientprotocol.com/get-started/architecture), [Tool calls](https://agentclientprotocol.com/protocol/v1/tool-calls).

There is a concrete trap in adapter 1.10.0: the `read-only` mode ID maps to **workspace-write** with user/on-request approvals. The default `agent` mode uses automatic review. Do not treat either label as a guarantee of a draft-only runtime. A future Quibble connection must enforce and test its actual Codex permission profile, tool availability, working directory and inherited configuration. A prompt saying “do not use tools” is not a permission boundary. [Tagged mode implementation](https://github.com/agentclientprotocol/codex-acp/blob/v1.10.0/src/AgentMode.ts).

**Context:** text is baseline; images and embedded resources require negotiated prompt capabilities. [Content](https://agentclientprotocol.com/protocol/v1/content). Proposed first request: spoken instruction and explicitly selected text, represented separately. Add a one-time requested window screenshot only after its consent/preview flow works. Keep captured text untrusted, prevent it from changing action permissions, and verify the insertion target before committing output. ACP does not acquire the active window automatically.

**Cancellation:** v1 `session/cancel` stops a prompt turn; the client must cancel pending permission requests and wait for the final cancelled stop reason. Generic request cancellation is optional. [Prompt lifecycle](https://agentclientprotocol.com/protocol/v1/prompt-turn), [Cancellation](https://agentclientprotocol.com/protocol/v1/cancellation). Proposed behavior: immediately stop accepting a result for insertion, cancel outstanding approvals, then reconcile process/tool completion. A timeout or killed process must never cause a possibly completed email action to be retried blindly.

**History:** sessions own context/history, and loading versus resuming have distinct replay behavior. [Session setup](https://agentclientprotocol.com/protocol/v1/session-setup). In adapter 1.10.0, `closeSession` unsubscribes and `deleteSession` calls Codex **archive**. Do not promise that Close or Delete erases captured window text. [Tagged session implementation](https://github.com/agentclientprotocol/codex-acp/blob/v1.10.0/src/CodexAcpClient.ts).

**Load:** proposed policy is start on Ask, retain briefly for repeated use, and stop only when idle with no pending actions. Measure cold-start time, RSS, CPU, network use and end-to-end latency for the adapter plus Codex process. Low inference load is plausible with remote models; actual overhead and latency in Quibble remain unmeasured.

## Next implementation slices

1. **Offline transport foundation:** define an assistant-provider interface and test a Swift ACP client against a deterministic fake subprocess. Cover fragmented messages, invalid/oversized JSON, process exits, cancellation races, approval requests, and unsupported capabilities. No account or model request is needed.
2. **Opt-in Codex connection:** pin adapter/runtime, expose connection status and supported login, and prove the permission profile with a restricted test workspace. Validate account, session, logout and history behavior. Do not offer a “draft-only” claim until negative action tests support it.
3. **Ask drafting:** one explicit shortcut, transcript plus selected text, streamed review card, Insert/Copy/Discard. Never automatically send ordinary dictation to an agent. Test name/number preservation and output usefulness against current local cleanup.
4. **Context and tools:** add requested screenshots, then sourced web research and allowlisted MCP tools. Preparing an email draft and sending it remain separate actions. Show the exact recipient and content before a send is authorized.
5. **Evaluate portability:** add a second ACP agent only when the user wants it and the same tests pass. Keep agent-specific extensions behind negotiated capabilities. Defer wake words, unattended sessions, and background automation until the basic Ask interaction earns repeated use.

The next slice is a client/protocol foundation, not an always-listening assistant. This report did not activate any ACP connection or alter the existing transcription providers.

## Independent Tahoe window finding

Apple's WWDC25 AppKit session explicitly explains why the current window can have smaller corners despite a new SDK: **toolbar windows use larger corners that scale with toolbar size; titlebar-only windows retain smaller corners**. A genuine native toolbar is the public route to Tahoe's toolbar-window geometry. Hidden-titlebar styling and a window material alone do not create one. [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/), transcript in the App structure chapter.

The inspected build 17 plist reports SDK **26.5** and Xcode **26.6**, with no design-compatibility override found. `WindowAppearance.swift` now leaves native masking alone, but `QuibbleApp.swift` has no actual toolbar at inspection. Recommendation: introduce meaningful native toolbar controls with an appropriate toolbar style, preserve native traffic lights, and let macOS compute the frame. The exact numeric radius is not promised by these docs; a root view clip changes content, not native window geometry. No app/window edits were made for this investigation.
