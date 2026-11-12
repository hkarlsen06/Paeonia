#!/usr/bin/env python3
"""Report what moved, cut or flashed in a screen recording.

    scripts/lib/motion-report.py <video> --out <dir> [--action <start-seconds> <end-seconds>]

Prints one line per stretch of change, in time order, and writes a contact
sheet for each stretch (segment-<n>.png), a slit-scan for each MOTION
(segment-<n>-slit.png) and report.txt with the same lines to <dir>.

Works on the real frame timestamps, because `simctl io recordVideo` writes a
frame only when the screen changes.
"""

from __future__ import annotations

import argparse
import math
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple, Union

# Set from simulator recordings: H.264 shifts a still screen by about 2
# brightness levels, the simulator leaves up to 100 ms between the frames of one
# motion, and the shortest pause between two motions was 337 ms.
ANALYSIS_WIDTH = 200
PIXEL_THRESHOLD = 4
NOISE_LEVEL = 2
NOISE_FLOOR = 0.0005
SPLIT_GAP = 0.15
FLASH_MAX_CHANGES = 4
FLASH_MAX_SECONDS = 0.1
FLASH_RESIDUE = 0.1
JUMP_RATIO = 3.0
JUMP_WINDOW = 2
JUMP_MIN_AREA = 0.002
JUMP_MIN_STEP = 10
SHEET_TILES = 40
SHEET_COLUMNS = 8
SHEET_TILE_WIDTH = 240
SLIT_LENGTH = 1000
SLIT_STEPS = 1000

MASK = bytes(0 if value < PIXEL_THRESHOLD else 1 for value in range(256))
ABOVE_NOISE = bytes(max(0, value - NOISE_LEVEL) for value in range(256))
CHANGED = bytes(0 if value < PIXEL_THRESHOLD else value for value in range(256))


class ReportError(Exception):
    pass


@dataclass(frozen=True)
class Box:
    x: int
    y: int
    width: int
    height: int

    def union(self, other: Box) -> Box:
        x, y = min(self.x, other.x), min(self.y, other.y)
        right = max(self.x + self.width, other.x + other.width)
        bottom = max(self.y + self.height, other.y + other.height)
        return Box(x, y, right - x, bottom - y)

    def __str__(self) -> str:
        return f"box x={self.x} y={self.y} {self.width}x{self.height}"


@dataclass(frozen=True)
class Change:
    index: int
    t: float
    gap: float
    area: float
    box: Box
    mask: bytes


@dataclass(frozen=True)
class Jump:
    t: float
    area: float
    ratio: float


@dataclass(frozen=True)
class Cut:
    pass


@dataclass(frozen=True)
class Flash:
    pass


@dataclass(frozen=True)
class Motion:
    jumps: Tuple[Jump, ...]
    longest_gap: float


Kind = Union[Cut, Flash, Motion]


@dataclass(frozen=True)
class Segment:
    changes: Tuple[Change, ...]
    kind: Kind
    area: float
    follows_cut: bool = False

    @property
    def start(self) -> float:
        return self.changes[0].t

    @property
    def end(self) -> float:
        return self.changes[-1].t

    @property
    def box(self) -> Box:
        box = self.changes[0].box
        for change in self.changes[1:]:
            box = box.union(change.box)
        return box

    @property
    def first_frame(self) -> int:
        return self.changes[0].index - 1

    @property
    def last_frame(self) -> int:
        return self.changes[-1].index


@dataclass(frozen=True)
class Video:
    path: Path
    width: int
    height: int
    times: Tuple[float, ...]


@dataclass(frozen=True)
class Frames:
    """Small grayscale copies of every frame, and the difference to the frame before."""

    width: int
    height: int
    frames: bytes
    diffs: bytes

    @property
    def size(self) -> int:
        return self.width * self.height

    def frame(self, index: int) -> bytes:
        return self.frames[index * self.size:(index + 1) * self.size]

    def diff(self, index: int) -> bytes:
        return self.diffs[(index - 1) * self.size:index * self.size]

    def strength(self, index: int) -> int:
        """How much frame index differs from the one before, summed over pixels, with the noise taken off."""
        return sum(self.diff(index).translate(ABOVE_NOISE))

    def step(self, index: int) -> float:
        """How much the pixels that changed in frame index changed, on average."""
        diff = self.diff(index)
        return sum(diff.translate(CHANGED)) / max(1, diff.translate(MASK).count(1))


def run(command: Sequence[str], **kwargs) -> subprocess.CompletedProcess:
    result = subprocess.run(command, capture_output=True, **kwargs)
    if result.returncode != 0:
        message = result.stderr.decode(errors="replace").strip().splitlines()
        raise ReportError(f"{command[0]} failed: " + (message[-1] if message else f"exit {result.returncode}"))
    return result


def probe(path: Path) -> Tuple[int, int]:
    result = run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                  "-show_entries", "stream=width,height", "-of", "csv=p=0", str(path)])
    fields = result.stdout.decode().strip().split(",")
    if len(fields) != 2 or not all(field.isdigit() for field in fields):
        raise ReportError(f"{path} has no video stream")
    return int(fields[0]), int(fields[1])


def decode(path: Path, width: int, height: int, scratch: Path) -> Tuple[Video, Frames]:
    small_height = max(2, round(ANALYSIS_WIDTH * height / width))
    frames_file, diffs_file = scratch / "frames.raw", scratch / "diffs.raw"
    graph = (f"[0:v]scale={ANALYSIS_WIDTH}:{small_height}:flags=area,format=gray,showinfo,split[f][d0];"
             "[d0]tblend=all_mode=difference[d]")
    result = run(["ffmpeg", "-hide_banner", "-nostdin", "-i", str(path), "-filter_complex", graph,
                  "-map", "[f]", "-fps_mode", "passthrough", "-f", "rawvideo", "-y", str(frames_file),
                  "-map", "[d]", "-fps_mode", "passthrough", "-f", "rawvideo", "-y", str(diffs_file)])
    times = tuple(float(match) for match in
                  re.findall(rb"Parsed_showinfo.* n: *\d+ .*pts_time:(-?[\d.]+)", result.stderr))
    frames = Frames(ANALYSIS_WIDTH, small_height, frames_file.read_bytes(), diffs_file.read_bytes())
    decoded = len(frames.frames) // frames.size
    differences = len(frames.diffs) // frames.size
    if not times or decoded != len(times) or differences != len(times) - 1:
        raise ReportError(f"frames and timestamps disagree: {decoded} frames, {len(times)} timestamps, "
                          f"{differences} differences")
    if any(later < earlier for earlier, later in zip(times, times[1:])):
        raise ReportError("frame timestamps go backwards")
    return Video(path, width, height, times), frames


def measure(video: Video, frames: Frames) -> Tuple[List[Change], int]:
    """Returns the changes between consecutive frames, and how many were too small to count."""
    floor = NOISE_FLOOR * frames.size
    scale_x, scale_y = video.width / frames.width, video.height / frames.height
    changes, ignored = [], 0
    for index in range(1, len(video.times)):
        mask = frames.diff(index).translate(MASK)
        count = mask.count(1)
        if count == 0:
            continue
        if count < floor:
            ignored += 1
            continue
        box = mask_box(mask, frames.width)
        full = Box(math.floor(box.x * scale_x), math.floor(box.y * scale_y),
                   math.ceil(box.width * scale_x), math.ceil(box.height * scale_y))
        changes.append(Change(index, video.times[index], video.times[index] - video.times[index - 1],
                              count / frames.size, full, mask))
    return changes, ignored


def mask_box(mask: bytes, width: int) -> Box:
    top, bottom = mask.find(1) // width, mask.rfind(1) // width
    left, right = width, -1
    for row in range(top, bottom + 1):
        start = row * width
        first = mask.find(1, start, start + width)
        if first >= 0:
            left = min(left, first - start)
            right = max(right, mask.rfind(1, start, start + width) - start)
    return Box(left, top, right - left + 1, bottom - top + 1)


def changed_fraction(a: bytes, b: bytes) -> float:
    return sum(1 for x, y in zip(a, b) if abs(x - y) >= PIXEL_THRESHOLD) / len(a)


def union_area(changes: Sequence[Change]) -> float:
    union = 0
    for change in changes:
        union |= int.from_bytes(change.mask, "big")
    size = len(changes[0].mask)
    return union.to_bytes(size, "big").count(1) / size


def classify(changes: Sequence[Change], frames: Frames, tick: float) -> Kind:
    if len(changes) == 1:
        return Cut()
    first, last = changes[0], changes[-1]
    if len(changes) <= FLASH_MAX_CHANGES and last.t - first.t <= FLASH_MAX_SECONDS:
        residue = changed_fraction(frames.frame(first.index - 1), frames.frame(last.index))
        if residue <= FLASH_RESIDUE * max(change.area for change in changes):
            return Flash()
    # Sizes add up how much each pixel changed, so that a fade whose steps sit
    # near PIXEL_THRESHOLD does not look like a run of spikes. A frame that
    # took longer carries more change, so sizes are per frame time.
    sizes = [frames.strength(change.index) * tick / max(tick, change.gap if position else tick)
             for position, change in enumerate(changes)]
    jumps = []
    for position, change in enumerate(changes):
        # The status bar draws its own frames between the app's, so a change
        # is compared with two changes on each side, not only its neighbours.
        around = sizes[max(0, position - JUMP_WINDOW):position] + sizes[position + 1:position + 1 + JUMP_WINDOW]
        ratio = sizes[position] / max(around)
        if ratio >= JUMP_RATIO and change.area >= JUMP_MIN_AREA and frames.step(change.index) >= JUMP_MIN_STEP:
            jumps.append(Jump(change.t, change.area, ratio))
    return Motion(tuple(jumps), max(change.gap for change in changes[1:]))


def segment(changes: Sequence[Change], frames: Frames, tick: float) -> List[Segment]:
    groups: List[List[Change]] = []
    for change in changes:
        if groups and change.t - groups[-1][-1].t <= SPLIT_GAP:
            groups[-1].append(change)
        else:
            groups.append([change])
    segments = []
    for group in groups:
        kind = classify(group, frames, tick)
        # A screen that appears and then animates would read as one motion with
        # a jump in it, so a jump on the first frame gets its own line as a cut.
        if isinstance(kind, Motion) and kind.jumps and kind.jumps[0].t == group[0].t:
            rest = group[1:]
            segments.append(Segment((group[0],), Cut(), group[0].area))
            segments.append(Segment(tuple(rest), classify(rest, frames, tick), union_area(rest), follows_cut=True))
        else:
            segments.append(Segment(tuple(group), kind, union_area(group)))
    return segments


def percent(fraction: float) -> str:
    value = fraction * 100
    return f"{value:.0f}%" if value >= 1 else f"{value:.2g}%"


def ms(seconds: float) -> str:
    return f"{seconds * 1000:.0f} ms"


def describe(number: int, item: Segment, tick: float) -> str:
    line = describe_kind(number, item, tick)
    if item.follows_cut:
        line += f", starts {ms(item.changes[0].gap)} after the cut in line {number - 1}"
    return line


def describe_kind(number: int, item: Segment, tick: float) -> str:
    if isinstance(item.kind, Cut):
        return (f"{number}  {item.start:.2f} s  CUT  {percent(item.area)} of the screen changed between two frames "
                f"with nothing in between, {item.box}")
    span = f"{item.start:.2f}-{item.end:.2f} s"
    duration = item.end - item.start
    if isinstance(item.kind, Flash):
        frames_shown = max(1, round(duration / tick))
        return (f"{number}  {span}  FLASH  {percent(item.area)} of the screen changed for {ms(duration)} "
                f"(about {frames_shown} frame{'s' if frames_shown > 1 else ''}) and went back to how it was, "
                f"{item.box}")
    line = (f"{number}  {span}  MOTION  {duration:.2f} s over {len(item.changes)} changed frames, "
            f"{percent(item.area)} of the screen, {item.box}, longest gap between frames {ms(item.kind.longest_gap)}")
    for jump in item.kind.jumps:
        line += (f", JUMP at {jump.t:.2f} s: {percent(jump.area)} of the screen changed in one frame, "
                 f"{jump.ratio:.0f} times the frames around it")
    return line


@dataclass(frozen=True)
class Image:
    """One picture of a segment: the ffmpeg filter that picks its frames, and what to say about it."""

    chain: str
    note: str


def contact_sheet(video: Video, item: Segment) -> Image:
    indexes = list(range(item.first_frame, item.last_frame + 1))
    note = ""
    if len(indexes) > SHEET_TILES:
        note = f"{SHEET_TILES} of {len(indexes)} frames, evenly spaced, "
        indexes = sorted({indexes[round(i * (len(indexes) - 1) / (SHEET_TILES - 1))] for i in range(SHEET_TILES)})
    columns = min(len(indexes), SHEET_COLUMNS)
    rows = math.ceil(len(indexes) / columns)
    select = "+".join(f"eq(n,{index})" for index in indexes)
    first, last = video.times[indexes[0]], video.times[indexes[-1]]
    return Image(f"select='{select}',scale={SHEET_TILE_WIDTH}:-2,tile={columns}x{rows}:padding=4:margin=4",
                 f"{note}{first:.2f} to {last:.2f} s, read left to right")


@dataclass(frozen=True)
class Slit:
    image: Image
    vertical: bool
    length: int


def slit_strip(video: Video, frames: Frames, item: Segment) -> Slit:
    # Something that moves along a line changes it in every frame, and changes
    # a line across its path only while it passes. So the strip is the column
    # or row that changed in the most frames, also when something else changed
    # elsewhere at the same time. It covers the part that changed, plus a margin.
    def line(mask: bytes, position: int, vertical: bool) -> bytes:
        return mask[position::frames.width] if vertical else mask[position * frames.width:(position + 1) * frames.width]

    def busiest(vertical: bool) -> Tuple[Tuple[int, int], int]:
        scores = []
        for position in range(frames.width if vertical else frames.height):
            counts = [line(change.mask, position, vertical).count(1) for change in item.changes]
            scores.append((sum(1 for count in counts if count), sum(counts)))
        return max(scores), scores.index(max(scores))

    (down, column), (along_row, row) = busiest(True), busiest(False)
    vertical = down >= along_row
    position = column if vertical else row
    across, along = (frames.width, frames.height) if vertical else (frames.height, frames.width)
    lines = [line(change.mask, position, vertical) for change in item.changes]
    first = min(strip.find(1) for strip in lines if 1 in strip)
    last = max(strip.rfind(1) for strip in lines)
    full_across, full_along = (video.width, video.height) if vertical else (video.height, video.width)
    scale_across, scale_along = full_across / across, full_along / along
    margin = max(16, round(0.05 * (last - first + 1) * scale_along))
    offset = max(0, math.floor(first * scale_along) - margin)
    length = min(full_along, math.ceil((last + 1) * scale_along) + margin) - offset
    at = min(math.floor((position + 0.5) * scale_across), full_across - 1)
    scaled = min(length, SLIT_LENGTH)
    if vertical:
        crop, where = f"crop=1:{length}:{at}:{offset},scale=1:{scaled}", f"column x={at}, y={offset}-{offset + length}"
    else:
        crop, where = f"crop={length}:1:{offset}:{at},scale={scaled}:1", f"row y={at}, x={offset}-{offset + length}"
    chain = f"select='between(n,{item.first_frame},{item.last_frame})',format=rgb24,{crop}:flags=area"
    return Slit(Image(chain, where), vertical, scaled)


def slit_scan(video: Video, item: Segment, slit: Slit, raw: bytes, out: Path) -> str:
    strip_bytes = slit.length * 3
    strips = [raw[i:i + strip_bytes] for i in range(0, len(raw), strip_bytes)]
    times = video.times[item.first_frame:item.last_frame + 1]
    if len(strips) != len(times):
        raise ReportError(f"slit-scan got {len(strips)} strips for {len(times)} frames")
    pad = max(0.05, 0.1 * (item.end - item.start))
    start, end = item.start - pad, item.end + pad
    rows, current = [], 0
    for step in range(SLIT_STEPS):
        t = start + (end - start) * step / (SLIT_STEPS - 1)
        while current + 1 < len(times) and times[current + 1] <= t:
            current += 1
        rows.append(strips[current])
    # Each strip is one row of a raw image with time running down. A column
    # strip is then transposed so that time runs left to right.
    transpose = ",transpose=cclock_flip" if slit.vertical else ""
    run(["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{slit.length}x{SLIT_STEPS}", "-i", "-", "-vf", f"format=rgb24{transpose}", "-frames:v", "1",
         "-y", str(out)], input=b"".join(rows))
    direction = "left to right" if slit.vertical else "top to bottom"
    return f"{slit.image.note}, time {start:.2f} to {end:.2f} s {direction}"


def draw(video: Video, frames: Frames, segments: Sequence[Segment], out: Path, scratch: Path) -> List[str]:
    """Writes every segment's pictures from one pass over the video, and returns a line for each."""
    chains: List[str] = []
    outputs: List[List[str]] = []
    slits = {}
    for number, item in enumerate(segments, 1):
        sheet = contact_sheet(video, item)
        chains.append(sheet.chain)
        outputs.append(["-frames:v", "1", "-y", str(out / f"segment-{number}.png")])
        if isinstance(item.kind, Motion):
            slits[number] = slit_strip(video, frames, item)
            chains.append(slits[number].image.chain)
            outputs.append(["-fps_mode", "passthrough", "-f", "rawvideo", "-y", str(scratch / f"slit-{number}.raw")])
    graph = (f"[0:v]split={len(chains)}" + "".join(f"[in{i}]" for i in range(len(chains))) + ";"
             + ";".join(f"[in{i}]{chain}[out{i}]" for i, chain in enumerate(chains)))
    command = ["ffmpeg", "-hide_banner", "-nostdin", "-loglevel", "error", "-i", str(video.path),
               "-filter_complex", graph]
    for i, arguments in enumerate(outputs):
        command += ["-map", f"[out{i}]"] + arguments
    run(command)

    lines = []
    for number, item in enumerate(segments, 1):
        lines.append(f"segment {number} frames: {out / f'segment-{number}.png'} ({contact_sheet(video, item).note})")
        if number in slits:
            image = out / f"segment-{number}-slit.png"
            raw = (scratch / f"slit-{number}.raw").read_bytes()
            lines.append(f"segment {number} slit-scan: {image} ({slit_scan(video, item, slits[number], raw, image)})")
    return lines


def report(path: Path, out: Path, action: Optional[Tuple[float, float]]) -> List[str]:
    for tool in ("ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            raise ReportError(f"{tool} is not installed. Install it with: brew install ffmpeg")
    if not path.is_file():
        raise ReportError(f"no video at {path}")
    width, height = probe(path)
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("segment-*.png"):
        old.unlink()
    with tempfile.TemporaryDirectory(prefix="motion-report-") as scratch:
        video, frames = decode(path, width, height, Path(scratch))
        changes, ignored = measure(video, frames)
        gaps = [later - earlier for earlier, later in zip(video.times, video.times[1:])]
        tick = max(0.001, statistics.median(gaps)) if gaps else 1 / 60
        segments = segment(changes, frames, tick)
        image_lines = draw(video, frames, segments, out, Path(scratch)) if segments else []

    lines = [f"recorded {video.times[-1]:.1f} s, {len(video.times)} frames, {width}x{height}"]
    if ignored:
        lines.append(f"ignored {ignored} frame{'s' if ignored > 1 else ''} that changed less than "
                     f"{percent(NOISE_FLOOR)} of the screen, as video noise")
    timeline = [(item.start, describe(number, item, tick)) for number, item in enumerate(segments, 1)]
    if action:
        timeline.append((action[0], f"action ran from {action[0]:.2f} to {action[1]:.2f} s"))
    if not segments:
        lines.append("nothing moved: no two frames differ by more than video noise")
    lines += [text for _, text in sorted(timeline, key=lambda entry: entry[0])]
    return lines + image_lines


def main() -> int:
    parser = argparse.ArgumentParser(description="Report what moved, cut or flashed in a screen recording.")
    parser.add_argument("video", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--action", type=float, nargs=2, metavar=("START", "END"))
    arguments = parser.parse_args()
    try:
        lines = report(arguments.video, arguments.out, tuple(arguments.action) if arguments.action else None)
    except ReportError as error:
        print(f"motion-report: {error}", file=sys.stderr)
        return 1
    text = "\n".join(lines) + "\n"
    (arguments.out / "report.txt").write_text(text)
    sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
