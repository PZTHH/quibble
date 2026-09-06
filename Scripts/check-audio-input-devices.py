#!/usr/bin/env python3
"""Check per-app microphone preference state and read-only CoreAudio enumeration.
No audio capture, system default changes, credentials, or app build.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="quibble-input-devices-") as directory:
    executable = Path(directory) / "Probe"
    subprocess.run(["xcrun", "swiftc", "-swift-version", "6", "-parse-as-library",
                    "-Xfrontend", "-enable-actor-data-race-checks",
                    str(root / "App/AudioInputDevices.swift"),
                    str(root / "Scripts/Fixtures/AudioInputDevicesProbe.swift"),
                    "-o", str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
