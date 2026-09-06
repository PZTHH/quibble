# Isolated SpellMapper CPU probe

Run 2026-09-05. See [feasibility and results](../../SPELLMAPPER-FEASIBILITY.md).

Checkpoint: `bene-ges/spellmapper_asr_customization_en` revision `10fd0674ab417c2337f236308005c6a598fd4a1e`, CC BY 4.0. Source: `NVIDIA-NeMo/Speech` revision `265bd739c77c86ac423942d650eed6fc232e4fc6`, Apache 2.0; source notices and LICENSE-NeMo retained.

`bert_example.py` is upstream's example builder with only the NeMo deprecation-logging import replaced by a no-op. `postprocess.py` contains extracted upstream `check_banned_replacements`, `substitute_replacements_in_text`, and `apply_replacements_to_text`; the optional DP branch is not called. `probe.py` reimplements the small forward wrapper with Hugging Face BERT and strict checkpoint loading.

This tests preferred spellings directly, up to ten real entries. Fixed dummy candidates fill the remaining slots; dummies can never be emitted. Unlike full SpellMapper, every one-to-three-word span is considered rather than relying on n-gram retrieval. Upstream length penalties and overlap resolution are preserved. No DP alignment filter is used. Thus this is a screening of the neural component under a specified candidate/span policy, not a claim about the full app or official end-to-end implementation.

Thresholds were fixed before seeing either output: 0.5, 0.7, 0.8, 0.9, 0.95, 0.99. Primary threshold is 0.9. No thresholds were tuned on the additional cases. Both sets include ordinary-text negatives; exact output requires preservation of casing, punctuation, and surrounding words. Fixtures are synthetic text examples, not recorded speech. Outputs retain every span's raw and length-penalized probabilities plus per-character class probabilities.

From Quibble root, with checkpoint and extracted config/vocabulary in `Models/spellmapper-candidate`:

```sh
OMP_NUM_THREADS=2 VECLIB_MAXIMUM_THREADS=2 .build/spellmapper-venv/bin/python Benchmarks/competitor-probes/spellmapper/probe.py Models/spellmapper-candidate Benchmarks/vocabulary-name-evaluation.json Benchmarks/competitor-probes/spellmapper-name-results.json
OMP_NUM_THREADS=2 VECLIB_MAXIMUM_THREADS=2 .build/spellmapper-venv/bin/python Benchmarks/competitor-probes/spellmapper/probe.py Models/spellmapper-candidate Benchmarks/competitor-probes/handy-additional-fixtures.json Benchmarks/competitor-probes/spellmapper-additional-results.json
```

Dependency versions are in `requirements.lock.txt`; the main dependencies are Torch 2.8.0, Transformers 4.44.2, and NumPy 2.2.6 under Python 3.12. Runtime model downloads are disabled. No full NeMo installation or GPU execution is required. The checkpoint is only loaded with `weights_only=True`; archive members are validated and never extracted with unrestricted `extractall`.

The local CPU runs succeeded; neither corpus met Quibble's quality requirements. Preserve failed outputs as evidence rather than treating parameter size or speed as success.
