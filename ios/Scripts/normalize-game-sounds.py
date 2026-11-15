#!/usr/bin/env python3
"""Normalize and check the bundled GameSound and CallSound CAFs. See docs/game-audio.md."""
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
RESOURCES = ROOT / "ios/PaeoniaApp/Resources"
INVENTORY = Path(__file__).with_name("game-sounds-inventory.json")
# Each library's folder, the enum that names its sounds, and its file prefix. Game sounds have
# numbered variants listed in the inventory. A call sound is one file per case.
LIBRARIES = {
    "game": (RESOURCES / "GameSounds", ROOT / "ios/PaeoniaApp/Features/Games/Shared/Sound/GameSound.swift", "GameSound"),
    "call": (RESOURCES / "CallSounds", ROOT / "ios/PaeoniaApp/Services/Calls/CallSound.swift", "CallSound"),
}
# Each library's integrated loudness in LUFS and true peak ceiling in dBTP. Call sounds play
# louder, because a ringback has to carry from a phone's speaker across a room.
LEVELS = {"game": (-26.0, -3.0), "call": (-12.0, -1.0)}
# Call sounds are stereo with the same sound on both channels. `AVAudioPlayer` sends a mono
# file to the first output channel only, which on an iPhone held upright is the earpiece.
CHANNELS = {"game": 1, "call": 2}
LOUDNESS_TOLERANCE = 0.5


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def probe(library, path):
    info = json.loads(run("ffprobe", "-v", "error", "-show_streams", "-of", "json", str(path)))
    streams = info["streams"]
    if len(streams) != 1:
        raise ValueError(f"{path.name}: expected one audio stream")
    stream = streams[0]
    channels = CHANNELS[library]
    if (stream["codec_name"], stream["sample_rate"], stream["channels"]) != ("pcm_s16le", "44100", channels):
        raise ValueError(f"{path.name}: expected {channels}-channel 44.1 kHz signed 16-bit PCM")
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


def conforms(library, loudness, peak):
    target, ceiling = LEVELS[library]
    return abs(loudness - target) <= LOUDNESS_TOLERANCE and peak <= ceiling


def normalize(library, source, destination):
    target, ceiling = LEVELS[library]
    # Oversampling and a small margin keep the resampled, quantized CAF below the ceiling.
    limit = 10 ** ((ceiling - 0.5) / 20)
    frames = probe(library, source)
    loudness, peak = measure(source)
    gain = target - loudness
    for _ in range(12):
        filters = f"volume={gain}dB"
        if peak + gain > ceiling:
            filters += (f",aresample=192000,alimiter=limit={limit}:level=false:latency=true"
                        ":attack=5:release=50,aresample=44100")
        run("ffmpeg", "-v", "error", "-y", "-i", str(source), "-af", filters,
            "-ar", "44100", "-ac", str(CHANNELS[library]), "-c:a", "pcm_s16le", str(destination))
        if probe(library, destination) != frames:
            raise ValueError(f"{source.name}: normalization changed its frame count")
        actual, actual_peak = measure(destination)
        if conforms(library, actual, actual_peak):
            return actual, actual_peak
        gain += target - actual
        if abs(gain) > 40:
            break
    raise ValueError(f"{source.name}: could not meet loudness and peak limits")


def expected_files(library):
    _, enum, prefix = LIBRARIES[library]
    names = set(re.findall(r'case \w+ = "(\w+)"', enum.read_text()))
    if not names:
        raise ValueError(f"{enum.name}: no sound cases")
    if library == "call":
        return names, {f"{prefix}{name}.caf" for name in names}
    counts = json.loads(INVENTORY.read_text())
    if not isinstance(counts, dict) or set(counts) != names:
        raise ValueError("game-sounds-inventory.json must list every GameSound case exactly once")
    if any(type(count) is not int or count < 1 for count in counts.values()):
        raise ValueError("Game sound variant counts must be positive integers")
    return names, {f"{prefix}{name}{variant}.caf"
                   for name, count in counts.items() for variant in range(1, count + 1)}


def inventory(library, directory, only):
    _, enum, prefix = LIBRARIES[library]
    names, expected = expected_files(library)
    paths = sorted(directory.glob(f"{prefix}*.caf"))
    actual = {path.name for path in paths}
    suffix = "" if library == "call" else "([1-9][0-9]*)"
    for path in paths:
        match = re.fullmatch(f"{prefix}(.+?){suffix}\\.caf", path.name)
        if not match or match[1] not in names:
            raise ValueError(f"{path.name}: no matching case in {enum.name}")
    if actual - expected:
        raise ValueError("Unexpected files: " + ", ".join(sorted(actual - expected)))
    if only:
        selected = set(only)
        if selected - actual:
            raise ValueError("--only names a missing CAF")
        paths = [path for path in paths if path.name in selected]
    elif expected - actual:
        raise ValueError("Missing files: " + ", ".join(sorted(expected - actual)))
    if not paths:
        raise ValueError(f"No {library} sound CAFs found")
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    parser.add_argument("--library", choices=sorted(LIBRARIES), help="Only this library. Default: all")
    parser.add_argument("--directory", type=Path, help="The library's folder, for generated outputs")
    parser.add_argument("--only", nargs="+", help="Normalize only these generated CAF filenames")
    args = parser.parse_args()
    if args.only and not args.write:
        parser.error("--only is for generation, not the complete-library check")
    if (args.directory or args.only) and not args.library:
        parser.error("--directory and --only need --library")
    for tool in ["ffmpeg", "ffprobe"]:
        if not shutil.which(tool):
            parser.error(f"{tool} is required")
    libraries = [args.library] if args.library else sorted(LIBRARIES)
    for library in libraries:
        directory = args.directory or LIBRARIES[library][0]
        status = process(library, directory, inventory(library, directory, args.only), args.write)
        if status:
            return status
    return 0


def process(library, directory, paths, write):
    errors, results, replacements = [], [], []
    # Stage every result before replacing any original. Invalid input leaves the library intact.
    staging = tempfile.TemporaryDirectory(prefix="game-audio-", dir=directory) if write else nullcontext()
    with staging as scratch:
        for path in paths:
            probe(library, path)
            loudness, peak = measure(path)
            if not conforms(library, loudness, peak) and write:
                target = Path(scratch) / path.name
                loudness, peak = normalize(library, path, target)
                replacements.append((target, path))
            results.append(loudness)
            if not conforms(library, loudness, peak):
                errors.append(f"{path.name}: {loudness:.1f} LUFS, {peak:.1f} dBTP")
        if errors:
            print("\n".join(errors), file=sys.stderr)
            print("Run ios/Scripts/normalize-game-sounds.py --write", file=sys.stderr)
            return 1
        for target, path in replacements:
            target.chmod(path.stat().st_mode)
            os.replace(target, path)
    print(f"{len(paths)} {library} sounds checked, {len(replacements)} normalized; "
          f"{min(results):.1f} to {max(results):.1f} LUFS, true peaks <= {LEVELS[library][1]:.1f} dBTP")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, subprocess.CalledProcessError, OSError) as error:
        print(str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError):
            print(error.stderr, file=sys.stderr)
        sys.exit(1)
