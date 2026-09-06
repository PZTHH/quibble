# Parakeet phrase-boosting probe

This is measurement scaffolding, not a shipping implementation. It uses the installed Parakeet model and the pinned NeMo context graph in `../nemo/`. NeMo source retains its Apache-2.0 notices and license; the patched MLXAudio package retains its upstream license.

1. Use the isolated `.build/spellmapper-venv` environment (Python 3.12; `sentencepiece==0.2.1`, existing NumPy). No full NeMo installation or extra ASR weights are needed.
2. Run `build_graph.py Models/parakeet Benchmarks/vocabulary-name-audio.json .build/parakeet-bias-graph.json` with that interpreter, from the repo root. It checks token IDs against the checkpoint vocabulary and tests scoring/backoff examples.
3. Run `python3 Benchmarks/competitor-probes/parakeet-bias/apply_probe.py`. It verifies the package revision, saves exact before/after sources and patches, and alters only the serial decoder hook plus the benchmark loader. The SPM checkout is read-only by default; the script temporarily enables writing and restores its mode.
4. Build the Release app using the documented Xcode/Metal command. Do not launch a second inference process during measurement.
5. Run `python3 Benchmarks/competitor-probes/parakeet-bias/run_probe.py`. It uses `sandbox-exec` with network denied and two runs per audio clip/configuration, sequentially. Inputs are the previously generated `.build/name-audio/*.aiff` files described in `Benchmarks/vocabulary-name-audio.json`.
6. Run `python3 Benchmarks/competitor-probes/parakeet-bias/apply_probe.py --restore` and rebuild the ordinary app. Restoration refuses to overwrite unexpected changes. Do not stack the Cohere and Parakeet loader patches.

The hook preserves the original blank/nonblank choice and duration prediction; only a nonblank token choice can be biased. The graph resets for each utterance/chunk and advances only on emitted nonblank tokens. A zero-weight run checks baseline parity through the hook.

The graph uses canonical/lowercase SentencePiece sequences, not NeMo's full variable-BPE graph. Dense tables intentionally simplify the experiment and must be replaced with a bounded sparse/cached representation before production. Measured active MLX memory excludes Python preparation, Swift graph storage and other resident process memory. Timing reports are file ASR stage times, not release-to-insert latency.

`run_probe.py --engine cohere-4bit --graph .build/cohere-bias-graph.json --prefix cohere-bias` shares the runner with the separate Cohere patch in `../cohere-bias/`. Build its graph using `build_graph.py ... --cohere`; that uses AED depth scaling 1 and protects EOS with the row's maximum score plus a completed-phrase bonus, following the TurboBias heuristic. Cohere's Swift tokenizer is checked against the exported phrase token IDs at load time.
