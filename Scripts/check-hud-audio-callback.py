#!/usr/bin/env python3
"""Check the production AudioQueue callback on a background executor using synthetic PCM.

Requires macOS and a Swift 6 Xcode toolchain (selected through xcrun or
DEVELOPER_DIR). Creates its own temporary module; no app build, microphone,
model download, or existing .build output is used.
"""

from pathlib import Path
import subprocess
import sys
import tempfile


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    analyzer = root / "Sources/QuibbleCore/HUDSpectrumAnalyzer.swift"
    monitor = root / "App/HUDSpectrumMonitor.swift"
    recorder = root / "App/MicrophoneRecorder.swift"
    devices = root / "App/AudioInputDevices.swift"
    fixture = root / "Scripts/Fixtures/HUDAudioCallbackProbe.swift"
    compiler = [
        "xcrun", "swiftc", "-swift-version", "6",
        "-Xfrontend", "-enable-actor-data-race-checks", "-parse-as-library",
    ]
    print("Checking shared PCM callback isolation and WAV finalization; no microphone is opened.", flush=True)
    try:
        with tempfile.TemporaryDirectory(prefix="quibble-hud-callback-") as directory:
            work = Path(directory)
            module = work / "QuibbleCore.swiftmodule"
            object_file = work / "HUDSpectrumAnalyzer.o"
            probe = work / "HUDAudioCallbackProbe.swift"
            executable = work / "HUDAudioCallbackProbe"
            # Concatenation lets the fixture exercise the actual private C callback
            # without exposing app test hooks or copying recording logic.
            probe.write_text(devices.read_text() + "\n" + monitor.read_text() + "\n" + recorder.read_text() + "\n" + fixture.read_text())
            subprocess.run(compiler + [
                "-emit-module", "-emit-object", "-module-name", "QuibbleCore",
                "-emit-module-path", str(module), str(analyzer), "-o", str(object_file),
            ], check=True, cwd=root)
            subprocess.run(compiler + [
                "-I", str(work), str(probe), str(object_file), "-o", str(executable),
            ], check=True, cwd=root)
            subprocess.run([str(executable)], check=True, cwd=root)
    except (OSError, subprocess.CalledProcessError) as error:
        print(f"HUD audio callback regression failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
