#!/usr/bin/env python3
"""Create deterministic-content synthetic speech files for pipeline smoke tests."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
out = root / "BenchmarkAudio"
out.mkdir(exist_ok=True)
for case in json.loads((root / "Benchmarks/corpus.json").read_text())["cases"]:
    target = out / (case["id"] + ".aiff")
    subprocess.run(["say", "-v", "Samantha", "-r", "150", "-o", str(target), case["text"]], check=True)
    print(target)
