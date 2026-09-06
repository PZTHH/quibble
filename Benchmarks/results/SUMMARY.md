# Synthetic file benchmark results

These are pipeline smoke tests on synthesized speech, not human-dictation accuracy or release-to-insertion measurements. First run includes loading; warm medians exclude it. Small samples do not establish reliable tail latency. Raw WER ignores case/punctuation but does not equate written numbers with spoken numbers. Cleanup output must be reviewed separately.

| Report | Engine / mode | Audio | First load | First total | Warm ASR | Warm cleanup | Warm total | Raw word errors |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| [cohere-correction-offline](cohere-correction-offline.json) | cohere / cleanup | 9.63s | 0.492s | 0.930s | 0.239s | 0.103s | 0.344s | 0/27 |
| [cohere-long-offline](cohere-long-offline.json) | cohere / cleanup | 40.01s | 0.497s | 1.671s | 0.680s | 0.424s | 1.107s | 5/109 |
| [cohere-short-cleanup](cohere-short-cleanup.json) | cohere / cleanup | 3.94s | 0.665s | 5.910s | 0.156s | 0.055s | 0.212s | 0/10 |
| [cohere-short-offline](cohere-short-offline.json) | cohere / cleanup | 3.94s | 0.502s | 0.731s | 0.132s | 0.049s | 0.182s | 0/10 |
| [cohere-technical-offline](cohere-technical-offline.json) | cohere / cleanup | 16.24s | 0.489s | 1.189s | 0.318s | 0.161s | 0.480s | 1/38 |
| [parakeet-correction-offline](parakeet-correction-offline.json) | parakeet / cleanup | 9.63s | 0.474s | 0.694s | 0.039s | 0.111s | 0.152s | 0/27 |
| [parakeet-long-offline](parakeet-long-offline.json) | parakeet / cleanup | 40.01s | 0.475s | 1.098s | 0.128s | 0.467s | 0.599s | 5/109 |
| [parakeet-short-offline](parakeet-short-offline.json) | parakeet / cleanup | 3.94s | 0.670s | 2.167s | 0.025s | 0.053s | 0.080s | 0/10 |
| [parakeet-technical-offline](parakeet-technical-offline.json) | parakeet / cleanup | 16.24s | 0.481s | 0.858s | 0.060s | 0.182s | 0.244s | 3/38 |
