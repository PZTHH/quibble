# Build 11: visual navigation and compact daily screens

Implemented 2026-09-05. This pass improves the working native app's presentation and discoverability; it does not change the ASR or vocabulary inference pipeline.

## Plan and implementation

The initial plan was to add a consistent color system, replace repeated instructions with a short replayable tour, compact history around application identity, compact model cards around useful measurements, and visualize diagnostics. Three parallel agents implemented Home/history, Models, and Diagnostics; the parent integrated navigation, tour, compatible history metadata, and final verification.

- **Navigation:** colored rounded icon tiles, matching selected-row tint and a selection dot. Labels and selected accessibility traits remain, so navigation does not depend on color alone. The unified native blurred background and absence of a fullscreen button remain.
- **Tour:** four short illustrated pages covering dictation, vocabulary, workflows and history. Completing or skipping persists a versioned completion preference. Replay is available from the sidebar. No permissions, downloads, vocabulary or modes are changed by the tour.
- **Home/history:** fewer instructions, compact transcript previews, colored delivery badges and icon actions with accessibility labels. Installed application icons resolve from bundle IDs with a bounded lazy cache; unavailable apps receive a fallback. Older name-only history can use an exact running-app match. New records include an optional application bundle ID, with backward-compatible decoding and the existing storage size limit extended to include it. Session-only history remains the default.
- **Models:** three compact cards fit in the minimum-width window where the earlier layout showed roughly two. Family colors, weight format/parameter chips, selected outlines and experimental/recommended icons replace long descriptions; descriptions and provenance remain in Details. Meters show numeric **weight precision**, not recognition accuracy, and actual ASR speed or text-stage duration. Untested values are dashed. ASR meters use a shared session scale. Each known model retains only its latest scalar timing sample in memory; samples clear on quit and involve no polling or background benchmark. Different clips are not a controlled ranking.
- **Diagnostics:** a two-column metric grid, colored aggregate processing breakdown with numeric legend, and expandable measurement/stage details. Loading is counted once. Post-inference active MLX allocation is distinguished from historical peak and total app RAM. The insertion check remains an explicit action with its effect described before the button.
- **Other screens:** workflow steps have distinct colors; explanatory text is disclosed on demand. Settings use icon labels and shortcut keycaps; permission details are collapsed.

## Verification

- Signed Release build 11 built successfully with the existing Xcode/Metal toolchain and signing identity.
- `swift test --scratch-path .build/core-tests`: **64 tests, zero failures**, exit 0. New history identity roundtrip test first failed because the identifier was dropped, then passed with the optional metadata field. Existing migration, retention and vocabulary/insertion checks also passed.
- The native tour was stepped through all four pages, completed, and checked after restart; replay remains available.
- Home, Models, populated History/review and populated Diagnostics were inspected in the running app at the 850-point minimum window width. Original transcript disclosure and history remove/Undo were exercised on synthetic fixtures.
- Two GUI imports of the same synthetic phrase passed through the existing Basic cleanup workflow, once with Cohere FP16 and once with Cohere 4-bit. Both returned `Please open Superwhisper.`. Both model speed samples remained visible after switching models. The user's original FP16 speech selection was restored.
- A third import in the final build confirmed the balanced Diagnostics grid and unchanged fixture output. Tour replay was reopened for the user.
- `NSWorkspace` resolved valid installed Notes and TextEdit icons; an unavailable identifier followed the fallback path. End-to-end new history icons from a real global microphone dictation were not exercised in this pass.
- Final logs: `.build/build11-final.log`, `.build/build11-tests.log`. The expected red test is `.build/build11-history-red.log`.

## Scope limits

There is no representative recognition-accuracy rating yet; numeric weight format must not be read as one. The two short synthetic imports validate wiring, not quality rankings, energy use or long-dictation latency. This pass adds no continuous animation, timer, background benchmarking or new inference model loads beyond the user's selected workflow. It does not constitute a new cross-app insertion matrix, distribution update/permission-retention test, or full light/dark/high-contrast/VoiceOver audit. Those remain release-hardening work.
