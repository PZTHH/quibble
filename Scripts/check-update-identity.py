#!/usr/bin/env python3
"""Check an updated app against the previous app's designated requirement.

Run on two different signed builds. Does not grant, reset or modify permissions.
"""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess

def run(*command):
    result = subprocess.run(command, text=True, capture_output=True, check=True)
    return result.stdout + result.stderr

def inspect(app):
    run("codesign", "--verify", "--deep", "--strict", str(app))
    details = run("codesign", "--display", "--verbose=4", str(app))
    requirement = run("codesign", "--display", "-r-", str(app))
    requirement = next(line.removeprefix("designated => ") for line in requirement.splitlines() if line.startswith("designated => "))
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    def value(key):
        return next((line.split("=", 1)[1] for line in details.splitlines() if line.startswith(key + "=")), None)
    return {"bundleID": info["CFBundleIdentifier"], "version": info["CFBundleVersion"],
            "team": value("TeamIdentifier"), "cdhash": value("CDHash"), "requirement": requirement}

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("previous", type=Path)
    parser.add_argument("updated", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    before, after = inspect(args.previous), inspect(args.updated)
    if before["bundleID"] != after["bundleID"] or before["team"] != after["team"]:
        parser.error("Bundle or team identity changed")
    if not before["team"] or before["team"] == "not set":
        parser.error("No stable Apple signing team; ad-hoc builds cannot validate this requirement")
    if before["cdhash"] == after["cdhash"]:
        parser.error("These are not different signed builds")
    run("codesign", "--verify", "-R=" + before["requirement"], str(args.updated))
    result = {"previous": before, "updated": after, "updatedSatisfiesPreviousRequirement": True,
              "permissionRetention": "Not proven by this check; requires actual grants and a same-location app replacement test."}
    text = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(text)
    print(text)
