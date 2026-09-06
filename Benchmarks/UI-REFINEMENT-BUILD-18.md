# Build 18: native window structure and clearer visual hierarchy

Date: 2026-09-06.

## Window and navigation

The small outer corners in build 17 had a structural cause: Quibble was a titlebar-only window. Apple explains that Tahoe gives toolbar windows larger corners while titlebar-only windows keep smaller ones. Build 18 uses a real unified toolbar and native NavigationSplitView. The system draws the frame; no rounded mask is applied to the root content. [Apple's AppKit design session](https://developer.apple.com/videos/play/wwdc2025/310/), retrieved 2026-09-06.

The toolbar provides the native sidebar toggle and quick tour. The sidebar uses grouped, full-width navigation buttons with a quiet selected background, a selected dot, stronger label weight, and a restrained focus outline. Arrow navigation moves keyboard focus and selection together; the focused row is scrolled into view. This replaces the previous uncoordinated custom icon tiles inside the system List selection.

Content uses the native window background for stable contrast. The native sidebar and toolbar provide glass. The earlier full-window material let the desktop wash over every content surface. Larger native outer corners and the floating sidebar were observed in the running app; the exact numerical native radius remains controlled by macOS.

## Visual changes

- Semantic colors have more saturation and contrast: blue for speech, green for vocabulary, lavender for writing, and muted gold for speed. Light and dark variants are bundled. There are no random model-family colors.
- Main card corners follow a 20-point scale, inset selections use 12 points, and smaller controls retain proportionate shapes. Shared card treatment is used in Settings, Modes, Permissions, and Diagnostics; existing main cards elsewhere follow the same radius.
- Navigation selection, hover/press response, page changes, model sorting/selection, Settings sections, and workflow selection use short state-driven transitions. Reduce Motion disables the added movement. These are finite transitions, without a new idle animation timer.
- Diagnostics replaces five repetitive timing tracks with a single colored breakdown and a compact duration/percentage legend. Local model speed measurements are available in a session disclosure. These exclude loading and writing and are not a controlled comparison across different recordings.
- Workflow diagrams use the same semantic colors to distinguish speech, vocabulary, writing, and destination steps.

## Model library

Models has separate labelled **Accuracy** and **Speed** segments. Both are static relative rankings from the pinned HF public English short-form benchmark. The table identifies **HF · H200**; Details contains exact source metrics and limitations. Mac measurements no longer appear in the library or model Details. Unknown Base/Small results remain unrated, rather than borrowing another checkpoint's score.

The selected row now has one inset rounded surface, a restrained outline, stronger model name, and a checkmark. The compact Accuracy label was observed wrapping during visual review and widened. Search, sort, Speech/Writing/Downloaded selection, and setup actions remain available.

See [HF speed evidence, source mapping, and limitations](HF-ASR-SPEED-BUILD-18.md). The values compare HF's upstream implementations on H200 hardware; they do not predict speed of Quibble's quantized models on this Mac.

## HUD

The existing layout and independent material choices remain. Studio has a status/time row, a 25-bar recent audio-level trace, and a separate action row. Strip and Compact use 13 and 9 bars. The trace consumes the existing recorder meter samples; it is not a spectral analysis or a second audio pipeline.

Finish displays the actual held dictation binding as a release hint. Cancel shows Esc only when that binding is held. Click-started recording and processing do not advertise those unavailable keyboard actions. Duplicated microphone/release prose was removed. Preview has a finite demo trace and a longer listening phase to make the layout easier to inspect. Phase and meter transitions honor Reduce Motion and stop animating when hidden. No new recurring timer was added.

## Assistant direction

Use **Agent Client Protocol (ACP)** as the next Ask connection experiment. Quibble would supply transcribed instructions and deliberately attached context to a connected agent such as Codex, then show an editable result. ACP does not provide ASR or eliminate cloud account limits.

The maintained Codex adapter supports the needed session/auth/event path, but permissions and runtime compatibility require testing. In particular, its currently tagged `read-only` mode maps to workspace-write permissions, so the name alone cannot establish a draft-only boundary. The next implementation slice is an offline protocol client with a fake subprocess, followed by a pinned, opt-in agent connection. No ACP agent was installed, authenticated, or activated in this build. See the [ACP integration report](ACP-INTEGRATION-2026-09-06.md) for primary sources and the revised plan.

## Verification

- Release compilation and the 92-test core suite passed on this tree. Final command logs: `.build/build18.log` and `.build/build18-tests.log`.
- The two added catalog tests were observed failing before implementation, then passing. They cover published speed ranking, shared variant ties, and missing/invalid/unscoped values.
- The pinned HF CSV was fetched and its SHA-256 checked against the bundled source manifest. All seven mapped model entries reproduce the pooled throughput to within published rounding.
- A fresh Swift 6 HUD state executable passed 1,000 meter updates, fixed history length, clamping, disabled-HUD history pause, reset, and held-shortcut state. It creates no windows or sounds.
- Live native window and model-row checks were performed at the current 850-point width. Sidebar Down followed by Space retained History as both the focused and selected page, verifying the focus correction. Final visual review includes model-label fit and the separation of layout/material controls.
- Final Studio/Frosted, Strip/Frosted, and Compact/Solid listening previews were inspected. Studio and Strip fit the configured Option–Space release hint and Esc hint; Compact exposed no action buttons. Studio + Frosted was restored. The final window has one native title, and the large native outer corners remain after the content contrast adjustment.
- Strict/deep signature verification passed on the final Release app. The signing team and bundle identity are unchanged.

Limits: an exhaustive light-appearance, VoiceOver, multi-display, cross-app insertion, long-custom-shortcut, and energy benchmark was not performed in this visual pass. The new HF speed display is not evidence of local model performance. Production storage/recovery and distribution work remains in the existing production review.
