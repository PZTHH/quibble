# Repository organization

Checked: 2026-09-06. Documentation and ignore-rule cleanup only; no app, model, runtime, test, signing, or installation behavior changed in this slice. Publication remains pending the user’s explicit “it’s ready.”

## Moves

| Previous root location | Current location |
| --- | --- |
| `METAL-TOOLCHAIN.md` | [Docs/Setup/METAL-TOOLCHAIN.md](../Docs/Setup/METAL-TOOLCHAIN.md) |
| `PRODUCTION-PLAN.md` | [Docs/Planning/PRODUCTION-PLAN.md](../Docs/Planning/PRODUCTION-PLAN.md) |
| `RESEARCH-PLAN.md` | [Docs/Planning/RESEARCH-PLAN.md](../Docs/Planning/RESEARCH-PLAN.md) |
| `PHASE-1.md` | [Docs/History/PHASE-1.md](../Docs/History/PHASE-1.md) |
| Eight `SuperWhisper-*.png` screenshots | `Docs/References/Superwhisper/`; see the [local reference inventory](../Docs/References/Superwhisper/README.md) |

[README](../README.md), [AGENTS](../AGENTS.md), the moved documents, and the [dictation UX research](DICTATION-UX-RESEARCH.md) now use the organized paths. [Docs/README.md](../Docs/README.md) is the documentation index. Screenshot citations point to their reference inventory, so a future source checkout does not contain links to omitted PNG files. The original images remain locally available and byte-identical.

Detailed benchmark research, authored fixtures, source probes, and the active model/runtime investigations retain their established paths. Script/source searches found no references requiring code changes for these documentation moves. All eight top-level Python scripts in `Scripts/` still have a concrete project-generation, download, benchmark, sound-generation, or regression-check purpose; none was removed or relocated.

## Local artifacts

Approximate `du -sh` inventory, measured on this checkout before any disk-space cleanup:

| Directory | Local size | Handling |
| --- | ---: | --- |
| `Models/` | 20 GB | Downloaded weights preserved |
| `.build/` | 6.1 GB | Build/staging/probe artifacts preserved |
| `DerivedData/` | 2.6 GB | Stable installed app and Xcode output preserved |
| `Inference/` | 1.2 GB | Runtime source and dependency/build cache preserved |
| `BenchmarkAudio/` | 3.3 MB | Existing local audio preserved |
| `Benchmarks/` | 4.6 MB | Reports, fixtures, probes, and measurements preserved |
| `Docs/` | 2.2 MB | Organized notes and original screenshots |

These are directory disk-usage observations, not app memory requirements or a claim that all contents are disposable.

The expanded [.gitignore](../.gitignore) distinguishes build/dependency caches, downloaded weights, local audio/exports, generated benchmark results, competitor screenshots, editor state, and local signing/configuration secrets. Authored test audio, benchmark fixtures, source probes, license/provenance files, app icon assets, and manifests remain visible. The authored results summary also remains visible. No broad ignore rule hides all JSON, images, audio, or benchmark source.

## Verification and limits

- All 12 files exist at their new paths; the old root paths are absent. SHA-256 comparisons confirm all eight PNG files are unchanged.
- Local Markdown targets in changed documents resolve, and the small documentation diff was inspected. Original historical claims were retained rather than rewritten as current facts.
- Git ignore semantics were checked read-only using existing dependency metadata, without initializing a repository. Source/fixture/license paths remain visible while representative local/private artifact paths are excluded.
- No files were deleted, no weights were downloaded, no app was relaunched, and no remote, repository, upload, commit, or publication was created. App and inference source, tests, active catalogs, and signing configuration were not edited by this cleanup.

The local move manifest, hashes, before-copies, diff, and verification results are in `.build/repo-cleanup-2026-09-06/`. No app build or inference test was needed for these documentation-only moves.

Remaining cleanup needs a separate decision: old build/probe caches could reclaim space, but may include useful reproduction evidence; model removal belongs in the app’s deliberate per-model flow; raw benchmark output and older reference probes need privacy/license review before publication. Ignore rules do not perform that review or establish distribution readiness. No recorded project-wide license or Git remote has been invented.
