#!/usr/bin/env python3
"""Normalize and check bundled GameSound CAFs. See docs/game-audio.md."""
import argparse
from contextlib import nullcontext
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SOUNDS = ROOT / "ios/PaeoniaApp/Resources/GameSounds"
ENUM = ROOT / "ios/PaeoniaApp/Features/Games/Shared/Sound/GameSound.swift"
INVENTORY = Path(__file__).with_name("game-sounds-inventory.json")
TARGET_LUFS = -26.0
LOUDNESS_TOLERANCE = 0.5
MAX_TRUE_PEAK = -3.0
# Oversampling and a small margin keep the resampled, quantized CAF below the ceiling.
LIMIT = 10 ** (-3.5 / 20)


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def probe(path):
    info = json.loads(run("ffprobe", "-v", "error", "-show_streams", "-of", "json", str(path)))
    streams = info["streams"]
    if len(streams) != 1:
        raise ValueError(f"{path.name}: expected one audio stream")
    stream = streams[0]
    if (stream["codec_name"], stream["sample_rate"], stream["channels"]) != ("pcm_s16le", "44100", 1):
        raise ValueError(f"{path.name}: expected mono 44.1 kHz signed 16-bit PCM")
    return stream["duration_ts"]


def measure(path):
    # R128 needs a 400 ms block. Padding is measurement-only; the CAF keeps its duration.
    result = subprocess.run([
        "ffmpeg", "-hide_banner", "-nostats", "-i", str(path), "-af",
        "apad=whole_dur=0.4,ebur128=peak=true", "-f", "null", "-",
    ], check=True, capture_output=True, text=True)
    summary = result.stderr.rsplit("Summary:", 1)[-1]
    loudness = re.search(r"I:\s*([-\w.]+) LUFS", summary)
    peak = re.search(r"Peak:\s*([-\w.]+) dBFS", summary)
    if not loudness or not peak:
        raise ValueError(f"{path.name}: FFmpeg did not return loudness and true peak")
    values = float(loudness[1]), float(peak[1])
    if not all(math.isfinite(value) for value in values):
        raise ValueError(f"{path.name}: silence or invalid audio")
    return values


def conforms(loudness, peak):
    return abs(loudness - TARGET_LUFS) <= LOUDNESS_TOLERANCE and peak <= MAX_TRUE_PEAK


def normalize(source, destination):
    frames = probe(source)
    loudness, peak = measure(source)
    gain = TARGET_LUFS - loudness
    for _ in range(12):
        filters = f"volume={gain}dB"
        if peak + gain > MAX_TRUE_PEAK:
            filters += (f",aresample=192000,alimiter=limit={LIMIT}:level=false:latency=true"
                        ":attack=5:release=50,aresample=44100")
        run("ffmpeg", "-v", "error", "-y", "-i", str(source), "-af", filters,
            "-ar", "44100", "-ac", "1", "-c:a", "pcm_s16le", str(destination))
        if probe(destination) != frames:
            raise ValueError(f"{source.name}: normalization changed its frame count")
        actual, actual_peak = measure(destination)
        if conforms(actual, actual_peak):
            return actual, actual_peak
        gain += TARGET_LUFS - actual
        if abs(gain) > 40:
            break
    raise ValueError(f"{source.name}: could not meet loudness and peak limits")


def inventory(directory, only):
    names = set(re.findall(r'case \w+ = "(\w+)"', ENUM.read_text()))
    counts = json.loads(INVENTORY.read_text())
    if not isinstance(counts, dict) or set(counts) != names:
        raise ValueError("game-sounds-inventory.json must list every GameSound case exactly once")
    if any(type(count) is not int or count < 1 for count in counts.values()):
        raise ValueError("Game sound variant counts must be positive integers")
    expected = {f"GameSound{name}{variant}.caf"
                for name, count in counts.items() for variant in range(1, count + 1)}
    paths = sorted(directory.glob("GameSound*.caf"))
    actual = {path.name for path in paths}
    for path in paths:
        match = re.fullmatch(r"GameSound(.+?)([1-9][0-9]*)\.caf", path.name)
        if not match or match[1] not in names:
            raise ValueError(f"{path.name}: no matching GameSound case")
    if actual - expected:
        raise ValueError("Unexpected variants: " + ", ".join(sorted(actual - expected)))
    if only:
        selected = set(only)
        if selected - actual:
            raise ValueError("--only names a missing CAF")
        paths = [path for path in paths if path.name in selected]
    elif expected - actual:
        raise ValueError("Missing variants: " + ", ".join(sorted(expected - actual)))
    if not paths:
        raise ValueError("No game sound CAFs found")
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    parser.add_argument("--directory", type=Path, default=SOUNDS)
    parser.add_argument("--only", nargs="+", help="Normalize only these generated CAF filenames")
    args = parser.parse_args()
    if args.only and not args.write:
        parser.error("--only is for generation, not the complete-library check")
    for tool in ["ffmpeg", "ffprobe"]:
        if not shutil.which(tool):
            parser.error(f"{tool} is required")
    paths = inventory(args.directory, args.only)
    errors, results, replacements = [], [], []
    # Stage every result before replacing any original. Invalid input leaves the library intact.
    staging = tempfile.TemporaryDirectory(prefix="game-audio-", dir=args.directory) if args.write else nullcontext()
    with staging as scratch:
        for path in paths:
            probe(path)
            loudness, peak = measure(path)
            if not conforms(loudness, peak) and args.write:
                target = Path(scratch) / path.name
                loudness, peak = normalize(path, target)
                replacements.append((target, path))
            results.append(loudness)
            if not conforms(loudness, peak):
                errors.append(f"{path.name}: {loudness:.1f} LUFS, {peak:.1f} dBTP")
        if errors:
            print("\n".join(errors), file=sys.stderr)
            print("Run ios/Scripts/normalize-game-sounds.py --write", file=sys.stderr)
            return 1
        for target, path in replacements:
            target.chmod(path.stat().st_mode)
            os.replace(target, path)
    print(f"{len(paths)} sounds checked, {len(replacements)} normalized; "
          f"{min(results):.1f} to {max(results):.1f} LUFS, true peaks <= {MAX_TRUE_PEAK:.1f} dBTP")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        print(str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
