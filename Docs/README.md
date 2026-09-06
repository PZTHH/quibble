# Documentation

Start with the [app and build guide](../README.md). [AGENTS.md](../AGENTS.md) records development, privacy, signing, and verification conventions.

## Setup and planning

| Document | Purpose |
| --- | --- |
| [Metal toolchain setup](Setup/METAL-TOOLCHAIN.md) | The current Mac’s Xcode component workaround; recheck when Xcode changes |
| [Production plan](Planning/PRODUCTION-PLAN.md) | Product milestones and dated implementation updates |
| [Updater prerequisites](../Benchmarks/UPDATER-PLAN-2026-09-06.md) | Future Sparkle integration, distribution signing, release hosting, and update verification; research only |
| [Phase 2 plan](Planning/PHASE-2.md) | Proposed app-aware formatting and optional assistant work, contributor milestones, and acceptance gates; not implemented features |
| [App icon source](Design/AppIcon/README.md) | Approved quotation-mark design, integrated Icon Composer source, and earlier concepts |
| [Standalone logo options](Design/LogoExplorations/README.md) | Earlier explorations; quotation duet selected |
| [Original research plan](Planning/RESEARCH-PLAN.md) | Initial feasibility research and long-term scope |
| [Phase 1 report](History/PHASE-1.md) | Early implementation and verification history |

The planning and historical documents are dated snapshots. The root README describes the current app; later implementation evidence can supersede older findings.

## Research and evidence

[Benchmarks/](../Benchmarks/) retains the research, measurements, fixtures, and reproducible probes at their established paths. Begin with the [production review](../Benchmarks/PRODUCTION-REVIEW-2026-09-06.md), then read the later notes relevant to a change. Raw result directories can contain private text and are excluded from future source control; authored fixtures and probe licenses remain visible.

[Design inspiration: Superwhisper](References/Superwhisper/README.md) records what that app's interface taught Quibble's design. The screenshots behind the research stay local: they are another product's interface, carry no redistribution permission, and are not Quibble app assets.

## Keeping the repository organized

Keep entry points and build manifests at the root. Put setup instructions in `Setup/`, plans in `Planning/`, and early standalone reports in `History/`. Continue placing detailed dated implementation and benchmark evidence in `Benchmarks/`. Repository paths in prose and shell commands are relative to the checkout root unless stated otherwise; Markdown links resolve relative to their document.

Model weights, benchmark audio, build products, and user exports remain local. Moving documentation must not reset settings, alter downloads, or remove recordings. Ignore rules are a convenience for a future publication review, not a privacy or license audit.

The [2026-09-06 organization note](../Benchmarks/REPOSITORY-CLEANUP-2026-09-06.md) records the moves, preserved local data, and verification.
