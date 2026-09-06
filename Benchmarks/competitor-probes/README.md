# Competitor vocabulary probes

Run on 2026-09-05. These are offline **text correction** probes, not audio recognition benchmarks or tests of the complete competitor apps.

## Exact Handy fallback

`handy/src/handy.rs` contains unchanged functions extracted from [Handy text.rs at fbd4e15fa14a721c66c57006ae110428b9e255b3](https://github.com/cjpais/Handy/blob/fbd4e15fa14a721c66c57006ae110428b9e255b3/src-tauri/src/audio_toolkit/text.rs). Only unused imports and the unrelated code after `extract_punctuation` were omitted. Handy's MIT license and copyright notice are preserved in `handy/LICENSE-Handy`.

The harness uses `natural` 0.5.0 and `strsim` 0.11.1, matching Handy's pinned Cargo.lock, plus the same serde/serde_json versions for fixture I/O. `handy/Cargo.lock` records this small harness's resolved dependency graph. No Handy app or GPU model is built or run. Threshold is the app's default 0.18.

Reproduce from the Quibble root:

```sh
cargo run --release --locked --manifest-path Benchmarks/competitor-probes/handy/Cargo.toml --target-dir /tmp/quibble-handy-probe-target -- Benchmarks/vocabulary-name-evaluation.json Benchmarks/competitor-probes/handy-name-results.json
cargo run --release --locked --offline --manifest-path Benchmarks/competitor-probes/handy/Cargo.toml --target-dir /tmp/quibble-handy-probe-target -- Benchmarks/competitor-probes/handy-additional-fixtures.json Benchmarks/competitor-probes/handy-additional-results.json
```

The first command may download Rust crates. The correction computation makes no network calls; subsequent runs can use `--offline`.

## Results

| Corpus | Exact output | Positive cases fully corrected | Negative cases falsely changed |
|---|---:|---:|---:|
| Existing Quibble 18-case evaluation | 9/18 | 5/9 | 5/9 |
| Additional 24-case uncommon-name and ordinary-text set | 14/24 | 4/12 | 2/12 |

Existing fixtures and preferred-word lists are unchanged. Additional cases are hand-authored plausible phonetic text errors, **not observed ASR output**, and do not claim a universal pronunciation for each name. Each row uses only the preferred `words` list; no manually configured aliases or corrections are passed. Exact output includes case, punctuation, and preservation of all surrounding words. `negative` means the expected string exactly equals the input; `false_correction` means that string was changed.

Important observed failures:

- `Shivon → Siobhan`, `Searsha → Saoirse`, `Neve → Niamh`, and `Keeva → Caoimhe` were not recovered.
- `The weather may improve tomorrow.` became `The weather Mae improve tomorrow.` with only Mae saved.
- `I need a new name for this.` became `I need a new Niamh for this.` with only Niamh saved.
- `Please send the draft to Shunade.` became `Please Sinead the draft to Sinead.` with only Sinead saved. The intended name was corrected, but surrounding content was damaged, so the row fails.
- Ordinary `apple`, `obsidian`, `quick time`, and `quibble` were changed to saved brand spellings in contexts where that was not intended.

Initial first-pass medians were approximately 7–11 microseconds per short fixture; the final verification run recorded 18.6 microseconds for the main set and 16.8 microseconds for the additional set. These are informal timing observations, not a statistically controlled performance comparison. Its tiny CPU cost does not make it acceptable as Quibble's production correction policy. It also cannot serve unchanged as the only candidate gate because it rejects the difficult names we need to recover.

The main evidence is the complete per-case outputs in `handy-name-results.json` and `handy-additional-results.json`. No production Quibble code or user vocabulary was changed.
