#!/usr/bin/env python3
"""Summarize file benchmarks. WER is for raw ASR against the spoken reference only."""
import re
import argparse
import json
from pathlib import Path
from statistics import median

def word_errors(reference, hypothesis):
    expected, actual = words(reference), words(hypothesis)
    previous = list(range(len(actual) + 1))
    for index, token in enumerate(expected, 1):
        current = [index]
        for column, recognized in enumerate(actual, 1):
            current.append(min(previous[column] + 1, current[-1] + 1,
                               previous[column - 1] + (token != recognized)))
        previous = current
    return previous[-1]

def words(text):
    return re.findall(r"\w+(?:['’]\w+)*", text.casefold())

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("reports", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    references = {case["id"]: case["text"] for case in json.loads((root / "Benchmarks/corpus.json").read_text())["cases"]}
    lines = ["# Synthetic file benchmark results", "", "These are pipeline smoke tests on synthesized speech, not human-dictation accuracy or release-to-insertion measurements. First run includes loading; warm medians exclude it. Small samples do not establish reliable tail latency. Raw WER ignores case/punctuation but does not equate written numbers with spoken numbers. Cleanup output must be reviewed separately.", "",
             "| Report | Engine / mode | Audio | First load | First total | Warm ASR | Warm cleanup | Warm total | Raw word errors |",
             "|---|---|---:|---:|---:|---:|---:|---:|---:|"]
    for path in sorted(args.reports.glob("*.json")):
        report = json.loads(path.read_text())
        if "runs" not in report:
            continue
        runs = report["runs"]
        if not runs:
            continue
        first = runs[0]
        warm = runs[1:]
        name = Path(report["sourceFile"]).stem
        reference = references.get(name)
        errors = f'{word_errors(reference, first["raw"])}/{len(words(reference))}' if reference else "—"
        asr = f'{median(r["transcriptionSeconds"] for r in warm):.3f}s' if warm else "—"
        cleanup = f'{median(r["refinementSeconds"] for r in warm):.3f}s' if warm else "—"
        total = f'{median(r["processingSeconds"] for r in warm):.3f}s' if warm else "—"
        lines.append(f'| [{path.stem}]({path.name}) | {first["engine"]} / {first["mode"]} | {first["audioSeconds"]:.2f}s | {first["loadSeconds"]:.3f}s | {first["processingSeconds"]:.3f}s | {asr} | {cleanup} | {total} | {errors} |')
    target = args.reports / "SUMMARY.md"
    target.write_text("\n".join(lines) + "\n")
    print(target)
