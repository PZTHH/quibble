# Build 12: calmer macOS presentation and sourced ASR accuracy

Retrieved and implemented: 2026-09-05. HIG guidance directional after 2026-12-05; benchmark snapshot directional after 2026-09-12.

## Guidance and decisions

| Apple guidance | Quibble change | Source, read 2026-09-05 |
|---|---|---|
| Use color consistently and provide labels/symbols as alternatives to color. | System accent for actions/selection; neutral content and chart cards; green success and orange warnings retain their meanings. Removed decorative section/family colors. | [Color](https://developer.apple.com/design/human-interface-guidelines/color) |
| macOS sidebar icons generally follow the chosen accent; familiar symbols and concise groups aid navigation. | Native SwiftUI sidebar List replaces custom button rows, adding native selection and arrow-key navigation. Developer and Diagnostics are grouped under Advanced. | [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars) |
| Materials establish functional/content hierarchy; custom glass effects should be used sparingly. | Preserve the requested shared native background, simplify cards and tour art, and allow the material to follow window activation instead of forcing its active state. No custom glass effects added to content. | [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) |
| Use a limited number of prominent actions and standard button styles. | Primary actions follow system accent; Details uses a standard button and ellipsis, with supporting model information disclosed inside. | [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) |
| Gauges represent a numerical value within a range and can explain that range. | Model accuracy is WER on a documented 0–20% error scale, explicitly lower-is-better. Local speed is separate. Diagnostics uses aligned, labeled duration bars rather than a multi-color stacked legend. | [Gauges](https://developer.apple.com/design/human-interface-guidelines/gauges) |

These are scoped design decisions informed by HIG, not a claim of full HIG conformance. Application icons, compact history, workflow editing and replayable tour remain. Inference, vocabulary corrections, insertion, permissions and model selection were not changed in this pass.

## Hugging Face WER

The user clarified that precision meant recognition accuracy, then requested Hugging Face arena data. Model cards now use Hugging Face Open ASR Leaderboard results, including Voice Arena Monsoon as one of eight common public English datasets. Seven local entries map to six upstream checkpoints; Base and Small have no comparable result. Weight format remains a factual chip and no longer appears as an accuracy bar.

The app clearly marks these as **HF upstream model** scores. They do not measure the exact MLX/quantized edition or Quibble's vocabulary/cleanup pipeline. In particular, FP16 and 4-bit Cohere share one upstream reference, and Qwen's scored editions use the official Transformers-native `-hf` checkpoints. Local Mac session timing remains the speed source. No GPU throughput is presented as Mac performance and no network access is added to the running app.

See [pinned benchmark data, mappings and methodology](HF-ASR-BENCHMARKS.md). The parent independently fetched the pinned source CSV, verified its SHA-256, and recomputed all seven mapped eight-column averages with exact decimal arithmetic. Every mean matched the bundled value.

## Validation

- Signed Release build 12, existing bundle ID and development identity.
- 65 core tests, zero failures, including decoding the actual benchmark resource, pinned source/task checks, and unavailable-model behavior. Existing vocabulary, history and insertion tests remain in the suite.
- Live native sidebar selection and arrow-key navigation verified. Current appearance inspected at the 850-point minimum width, including Home and model cards.
- Model Details exposes WER, benchmark scope, evaluated checkpoint, snapshot date, caveat and source link. Unknown entries remain unrated rather than becoming zero-error scores.
- A final GUI import of the existing synthetic phrase returned `Please open Superwhisper.`. Populated neutral Diagnostics bars and the aligned WER/local-speed cards were visually inspected; the original FP16 selection remains active.
- Final logs: `.build/build12-final.log` and `.build/build12-tests.log`.

This pass does not remeasure local recognition WER, conduct a new cross-app insertion matrix, validate a distribution-signing update, or complete a full light/dark/high-contrast/VoiceOver audit. System semantic colors and native controls improve adaptation, but broader accessibility and release validation remain open.
