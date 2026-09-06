#!/usr/bin/env python3
"""Generate Quibble's original, muted Soft feedback assets.

Generation is an offline development step; no inference or synthesis runs in
the application. Soft start uses NumPy (validated with 2.3.5); the other cues
use the standard library. No source samples are incorporated.

Examples:
  python3 Scripts/generate-feedback-sounds.py
  python3 Scripts/generate-feedback-sounds.py --cue start
  python3 Scripts/generate-feedback-sounds.py --output /tmp/quibble-soft
  python3 Scripts/generate-feedback-sounds.py --analyze-only \
    --baseline .build/feedback-sounds-2026-09-06/original \
    --reference .build/feedback-sounds-2026-09-06/reference.wav

Analysis additionally requires NumPy. Decode Ogg with macOS afconvert first:
  afconvert input.ogg reference.wav -f WAVE -d LEI16
"""

import argparse
import array
import hashlib
import json
import math
from pathlib import Path
import random
import sys
import wave


SAMPLE_RATE = 44_100
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "App" / "Resources"
# Soft start is a separate nonperiodic knock below. Other cues keep their
# original recipes and bytes. Error uses
# two repetitions of the same low body to remain distinguishable without a buzz.
# Tuple: file duration, peak dBFS, [(offset, length, initial Hz, final Hz,
#                                decay / second, relative amplitude, seed)].
CUES = {
    "stop": (0.120, -16.5, [(0, .114, 175, 120, 34, 1, 72)]),
    "complete": (0.185, -17.0, [(0, .179, 200, 225, 23, 1, 73)]),
    "error": (0.265, -16.5, [(0, .118, 158, 135, 30, 1, 74),
                             (.130, .129, 158, 135, 28, .82, 75)]),
    "cancel": (0.130, -18.0, [(0, .124, 160, 105, 33, 1, 76)]),
}
CUE_NAMES = ("start", *CUES)
START_SAMPLE_RATE = 16_000


def synthesize_start():
    """The tested 85 ms knock: filtered noise, without a voiced oscillator.

    Use an explicit PCG64 generator so a future change to default_rng's
    default bit generator cannot silently change the shipped cue.
    """
    import numpy as np

    seconds, cutoff, decay = 0.085, 700, 0.014
    count = round(seconds * START_SAMPLE_RATE)
    noise = np.random.Generator(np.random.PCG64(512)).normal(size=count)
    spectrum = np.fft.rfft(noise)
    frequencies = np.fft.rfftfreq(count, 1 / START_SAMPLE_RATE)
    spectrum *= 1 / np.sqrt(1 + (frequencies / cutoff) ** 8)
    spectrum *= frequencies / np.sqrt(frequencies ** 2 + 80 ** 2)
    noise = np.fft.irfft(spectrum, count)
    time = np.arange(count) / START_SAMPLE_RATE
    envelope = (1 - np.exp(-time / 0.0015)) * np.exp(-time / decay)
    envelope *= np.minimum(1, (seconds - time) / 0.01)
    samples = noise * envelope
    samples = samples / max(abs(samples)) * 0.15
    # Match the tested fixture's PCM16 truncation, rather than rounding.
    return (np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes()


def smoothstep(value):
    value = max(0.0, min(1.0, value))
    return value * value * (3 - 2 * value)


def lowpass(samples, cutoff, passes=1):
    alpha = 1 - math.exp(-2 * math.pi * cutoff / SAMPLE_RATE)
    result = samples
    for _ in range(passes):
        previous = 0.0
        filtered = []
        for sample in result:
            previous += alpha * (sample - previous)
            filtered.append(previous)
        result = filtered
    return result


def highpass(samples, cutoff=45):
    # Two cascaded gentle stages remove DC/subsonic energy from the transient.
    result = samples
    for _ in range(2):
        low = lowpass(result, cutoff)
        result = [sample - bass for sample, bass in zip(result, low)]
    return result


def pulse(length, initial_hz, final_hz, decay, seed):
    count = round(length * SAMPLE_RATE)
    rng = random.Random(seed)
    texture = lowpass([rng.uniform(-1, 1) for _ in range(count)], 600, 2)
    # Filtered noise is restrained texture rather than a bright impact click.
    texture_scale = math.sqrt(sum(x * x for x in texture) / count) or 1
    phase = 0.0
    samples = []
    for index in range(count):
        t = index / SAMPLE_RATE
        frequency = final_hz + (initial_hz - final_hz) * math.exp(-t * 38)
        phase += 2 * math.pi * frequency / SAMPLE_RATE
        body = (math.sin(phase) + .13 * math.sin(phase * 1.67 + .3)
                + .035 * math.sin(phase * 2.31))
        brushed = .065 * texture[index] / texture_scale * math.exp(-t * 45)
        envelope = (smoothstep(t / .008) * math.exp(-t * decay)
                    * smoothstep((length - t) / .032))
        samples.append((body + brushed) * envelope)
    return samples


def synthesize(cue):
    duration, peak_db, pulses = CUES[cue]
    samples = [0.0] * round(duration * SAMPLE_RATE)
    for offset, length, initial_hz, final_hz, decay, amplitude, seed in pulses:
        start = round(offset * SAMPLE_RATE)
        for index, value in enumerate(pulse(length, initial_hz, final_hz, decay, seed)):
            if start + index < len(samples):
                samples[start + index] += value * amplitude
    samples = lowpass(highpass(samples), 550, 3)
    # Six milliseconds of fade include the lowpass tail, preventing a cut edge.
    count = len(samples)
    for index in range(count):
        edge = min(index, count - index - 1) / (.006 * SAMPLE_RATE)
        samples[index] *= smoothstep(edge)
    peak = max(map(abs, samples))
    gain = 10 ** (peak_db / 20) / peak
    pcm = array.array("h", [round(value * gain * 32767) for value in samples])
    assert pcm[0] == pcm[-1] == 0
    assert max(map(abs, pcm)) < 32767
    return pcm


def generate(output, cues=CUE_NAMES):
    output.mkdir(parents=True, exist_ok=True)
    for cue in cues:
        if cue == "start":
            data = synthesize_start()
            rate = START_SAMPLE_RATE
        else:
            pcm = synthesize(cue)
            if sys.byteorder != "little":
                pcm.byteswap()
            data = pcm.tobytes()
            rate = SAMPLE_RATE
        with wave.open(str(output / f"soft-{cue}.wav"), "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(rate)
            audio.writeframes(data)


def analyze(path):
    import numpy as np
    with wave.open(str(path)) as audio:
        channels, width, rate, frames = (audio.getnchannels(), audio.getsampwidth(),
                                       audio.getframerate(), audio.getnframes())
        if width != 2:
            raise ValueError(f"Expected 16-bit PCM: {path}")
        stereo = np.frombuffer(audio.readframes(frames), dtype="<i2").reshape(-1, channels)
        samples = stereo.mean(axis=1) / 32768
    energy = abs(np.fft.rfft(samples)) ** 2
    frequencies = np.fft.rfftfreq(frames, 1 / rate)
    total = float(energy.sum())
    peak = float(np.max(np.abs(stereo / 32768)))
    rms = float(np.sqrt(np.mean(samples * samples)))
    bands = [(0, 120), (120, 250), (250, 500), (500, 1000),
             (1000, 2000), (2000, rate / 2)]
    return {
        "file": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "duration_ms": round(frames / rate * 1000, 2), "sample_rate": rate,
        "channels": channels, "bits": width * 8,
        "peak_dbfs": round(20 * math.log10(peak), 2),
        "rms_dbfs": round(20 * math.log10(rms), 2),
        "dc_mean": round(float(samples.mean()), 8),
        "first_sample": stereo[0].tolist(), "last_sample": stereo[-1].tolist(),
        "clipped_samples": int(np.sum(np.abs(stereo.astype(np.int32)) >= 32767)),
        "power_centroid_hz": round(float(np.sum(energy * frequencies) / total), 2),
        "power_rolloff95_hz": round(float(frequencies[np.searchsorted(np.cumsum(energy), total * .95)]), 2),
        "power_above_1000_pct": round(float(energy[frequencies >= 1000].sum() / total * 100), 5),
        "power_bands_pct": {f"{int(lo)}-{int(hi)}": round(float(energy[(frequencies >= lo) & (frequencies < hi)].sum() / total * 100), 4)
                            for lo, hi in bands},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--cue", choices=("all", *CUE_NAMES), default="all",
                        help="Generate only this cue, leaving every other file untouched (default: all)")
    parser.add_argument("--analyze-only", action="store_true")
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--reference", type=Path, help="16-bit decoded reference WAV")
    args = parser.parse_args()
    if not args.analyze_only:
        cues = CUE_NAMES if args.cue == "all" else (args.cue,)
        generate(args.output, cues)
        print(f"Generated {', '.join(cues)} Soft cue(s) in {args.output}")
    else:
        paths = sorted(args.output.glob("soft-*.wav"))
        if args.baseline:
            paths += sorted(args.baseline.glob("soft-*.wav"))
        if args.reference:
            paths.append(args.reference)
        print(json.dumps([analyze(path) for path in paths], indent=2))


if __name__ == "__main__":
    main()
