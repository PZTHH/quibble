# Build 28 — concise shortcut copy and next-phase handoff

Verified 2026-09-06.

- Removed the scenario-specific shortcut coverage explanation and its disclosure from setup, the shortcut editor, and Settings. Actual conflict detection and validation are unchanged. Settings shows a compact status with a short generic help tooltip; an unavailable system check does not claim success.
- Added the contributor-facing [Phase 2 plan](../Docs/Planning/PHASE-2.md) for application-specific formatting and separately invoked optional agent assistance. This is planning only.
- Prepared a [review-only app icon concept and Icon Composer handoff](../Docs/Design/AppIcon/README.md). The user has the final design decision. No production icon was installed; no GitHub publication occurred.

Validation: Release Xcode build succeeded, exit 0 (`.build/build28.log`). Staged and installed bundles passed strict signature verification. Installed `CFBundleVersion` is 28 at the stable development path; installation followed a fresh idle check and UI quit. Native Settings → Shortcuts was visually inspected: compact “No known conflicts” status, unchanged existing bindings, and no scenario disclosure. Source search found no remaining removed-copy references. No inference or insertion code changed, so no model downloads or repeated ASR runs were needed.
