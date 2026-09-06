# Complete model icons and honest ASR rating coverage

Retrieved: 2026-09-06 · Directional after: 2026-09-12

## Answer

The three missing publisher marks were Moonshine Tiny, Moonshine Base, and IBM Granite. Both Moonshine entries now use Moonshine AI’s official Hugging Face organization avatar; Granite uses IBM Granite’s official avatar. The original PNG bytes are bundled without alteration, following the existing publisher-icon catalog. Exact URLs, retrieval dates, and SHA-256 hashes are recorded in [MODEL-ICON-SOURCES.json](MODEL-ICON-SOURCES.json). Their official profile metadata is the primary provenance, checked on 2026-09-06: [Moonshine AI](https://huggingface.co/api/organizations/moonshine-ai/overview), [IBM Granite](https://huggingface.co/api/organizations/ibm-granite/overview).

The missing rating references are multilingual Whisper Base, multilingual Whisper Small, and Moonshine Base. None has a row in the current **eight public English dataset** CSV, freshly retrieved at revision `eec9efdf93683faf1dfb36c7d77b3c12d746215e` on 2026-09-06. Its 62 rows include Moonshine Tiny and Streaming Tiny, which are different checkpoints. No sibling scores were substituted. [Pinned HF results](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/eec9efdf93683faf1dfb36c7d77b3c12d746215e/english_short_latest.csv)

The library now displays one neutral **Not ranked** badge for these three families, with a precise explanation and source link in Details. Empty dashed meters no longer resemble a low measured score. Existing published scores and speed metadata are unchanged. Implementation: [ModelLibraryView.swift](../App/ModelLibraryView.swift), [ASRBenchmarkCatalog.swift](../Sources/QuibbleCore/ASRBenchmarkCatalog.swift), [ASRBenchmarks.json](../App/Resources/ASRBenchmarks.json), inspected 2026-09-06.

## Primary evidence

| Claim | Source | Read on |
|---|---|---|
| Official Moonshine avatar is the crescent-and-waveform publisher mark; the same mark covers Tiny and Base. | [Official organization metadata](https://huggingface.co/api/organizations/moonshine-ai/overview); [exact PNG](https://cdn-avatars.huggingface.co/v1/production/uploads/6509fc8d11afda55cae0b2e7/6tyQ-L7VxHMOSKIOff09A.png) | 2026-09-06 |
| Official IBM Granite avatar is the white IBM mark on blue. | [Official organization metadata](https://huggingface.co/api/organizations/ibm-granite/overview); [exact PNG](https://cdn-avatars.huggingface.co/v1/production/uploads/639bcaa2445b133a4e942436/CEW-OjXkRkDNmTxSu8Egh.png) | 2026-09-06 |
| Current English short-form results omit `openai/whisper-base`, `openai/whisper-small`, and both current/legacy publisher names for `moonshine-base`. | [Pinned CSV, revision eec9efdf](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/eec9efdf93683faf1dfb36c7d77b3c12d746215e/english_short_latest.csv) | 2026-09-06 |
| Moonshine Base has historical HF evaluation; it should not be described as never evaluated. The July 7 snapshot reports a seven-dataset cleaned average of 8.604285714% WER and 2766.87 RTFx. | [Historical CSV, revision db66be50](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/db66be50b203d97d14b7447446da244f98670a35/english_short_latest.csv) | 2026-09-06 |
| The historical Moonshine average lacks Voice Arena Monsoon and uses the older Earnings22 split, so it does not share the current rating scale. This is an inference from the two CSV headers and the HF version registry. | [Current CSV](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/eec9efdf93683faf1dfb36c7d77b3c12d746215e/english_short_latest.csv); [historical CSV](https://huggingface.co/datasets/hf-audio/open-asr-leaderboard-results/blob/db66be50b203d97d14b7447446da244f98670a35/english_short_latest.csv); [HF version registry, c469d4f9](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/blob/c469d4f9f92c51969eed6b536e57b8dde62bcf58/init.py) | 2026-09-06 |
| Current HF UI defaults also include two private dataset groups. Quibble’s explicitly labeled eight-public-dataset snapshot is a different scope. | [HF version registry, c469d4f9](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/blob/c469d4f9f92c51969eed6b536e57b8dde62bcf58/init.py) | 2026-09-06 |

Current CSV SHA-256: `07f02da66f62ea16ee6999163109544e8ffccc5476fd4b73149bc21b1e987451`.
Historical CSV SHA-256: `0bb823fa873c41b54fea5eb3d5da7b65d54594158018c367aad341f646d2fa8f`.
Moonshine PNG SHA-256: `e04a25bf2fa3e9bfa4af002dd7ffeaf22b2782d22eb5f69acf97129009cac60f`.
IBM Granite PNG SHA-256: `b4c42cc14b9475ef087b9f6b69d4a1187ea9ae9d2e5d99815fa273ae1297816f`.

## Verification

On 2026-09-06:

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path .build/model-visual-coverage-tests --filter ModelCatalogTests`: exit 0, 9 tests, 0 failures. New checks require every speech artifact’s benchmark reference to resolve either to measured accuracy/speed or explicit missing-data metadata. Legacy snapshots decode without that optional metadata; a stale missing-data note cannot override a valid measurement.
- `xcrun swiftc -typecheck App/ModelIcon.swift` using Xcode: exit 0.
- `xcrun swiftc -frontend -parse App/ModelIcon.swift App/ModelLibraryView.swift` using Xcode: exit 0. This is syntax checking, not a complete application build.
- All seven publisher assets matched their recorded SHA-256 hashes and image-set filenames. The two new 200×200 PNGs were visually inspected. All 11 published reference rows and the speed metadata compare identically to the pre-edit snapshot.

No ASR weights were downloaded, no inference ran, and no application build or live UI inspection was performed in this subtask. Full application compilation and row/Details layout checks remain with the integration task. The focused test log and retrieved metadata are in `.build/model-visual-coverage-2026-09-06/`.

## Unconfirmed

| Question | What I tried | Best lead |
|---|---|---|
| Do separate Voice Arena/private results contain additional coverage for the three unranked checkpoints? | The HF Space registry points to `hf-audio/voicearena_shortform_results`. An unauthenticated metadata request returned HTTP 401. No credential lookup or authenticated request was attempted. This does not affect the confirmed absence from the public CSV, which already includes Voice Arena Monsoon for its listed models. | [HF version registry](https://huggingface.co/spaces/hf-audio/open_asr_leaderboard/blob/c469d4f9f92c51969eed6b536e57b8dde62bcf58/init.py) |

## Follow-up

Add ratings for the three unranked checkpoints when HF publishes results using the same evaluation scope. A separate local Mac benchmark would be useful for actual dictation latency, but its numbers must retain their own hardware and fixture labels instead of sharing the upstream H200 scale.
