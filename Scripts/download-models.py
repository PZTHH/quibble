#!/usr/bin/env python3
"""Fetch pinned model files only. Inference itself uses local directories.

No account or audio upload. Downloads go into the gitignored Models directory.
Partial files remain resumable; successful files receive a local SHA-256 receipt.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]

def download(model):
    folder = ROOT / "Models" / model["name"]
    folder.mkdir(parents=True, exist_ok=True)
    receipt_path = folder / "download-receipt.json"
    old = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    checksums = {}
    for name in model["files"]:
        destination = folder / name
        if not (destination.exists() and old.get("revision") == model["revision"]
                and name in old.get("sha256", {})):
            partial = folder / (name + ".partial")
            source = model.get("fileSources", {}).get(name, model)
            url = f'https://huggingface.co/{source["repository"]}/resolve/{source["revision"]}/{name}'
            print(f'Downloading {model["name"]}/{name}', flush=True)
            subprocess.run(["curl", "-L", "--fail", "--retry", "3", "--retry-all-errors", "--connect-timeout", "30", "--continue-at", "-",
                            "--output", str(partial), url], check=True)
            expected = model.get("fileBytes", {}).get(name)
            if expected is not None and partial.stat().st_size != expected:
                raise RuntimeError(f"Unexpected download size: {partial}")
            partial.replace(destination)
        digest = hashlib.sha256()
        with destination.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        checksums[name] = digest.hexdigest()
        if name in old.get("sha256", {}) and checksums[name] != old["sha256"][name]:
            raise RuntimeError(f"Local file changed: {destination}; remove it and rerun.")
        receipt_path.write_text(json.dumps({"repository": model["repository"],
            "revision": model["revision"], "sha256": checksums}, indent=2) + "\n")
    print(f'Ready: {folder}', flush=True)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("names", nargs="*", help="Model names from Models.lock.json; defaults to all")
    args = parser.parse_args()
    models = json.loads((ROOT / "Models.lock.json").read_text())["models"]
    names = set(args.names) or {m["name"] for m in models}
    unknown = names - {m["name"] for m in models}
    if unknown:
        parser.error(f"Unknown model(s): {', '.join(sorted(unknown))}")
    for model in models:
        if model["name"] in names:
            download(model)
