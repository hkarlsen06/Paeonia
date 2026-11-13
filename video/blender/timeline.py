"""Frame grid, region table and phone geometry shared by phone3d.py, which renders the 3D layer in Blender, and
showcase.py, which draws the rest."""
import json
import math
import re
import subprocess
from pathlib import Path
from typing import NamedTuple

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'scripts/assets/app-store'
CONFIG = json.loads((ASSETS / 'paeonia-3d.json').read_text())
VERSION = re.search(r'^MARKETING_VERSION = (\S+)', (ROOT / 'ios/Version.xcconfig').read_text(), re.M)[1]
CAPTURES = ROOT / 'ios/ASConnectScreenshots' / VERSION / 'raw'
OUT = ROOT / 'video/blender/out'
LOCALES = {'en-US': 'en', 'no': 'nb'}  # the language of each film's drawing and of its Localizable.xcstrings copy

W, H, FPS = 886, 1920, 30  # App Store Connect's app preview size for every iPhone from 5.8 to 6.9 inches
FRAMES = 885  # 29.5 s
# Pixel box (left, top, right, bottom) the camera frames the phones in. Between the close-ups it puts the main phone
# from about y 560 to y 1845, so the phone and the headline above it fill the frame of an App Store app preview. The
# box runs past the frame's bottom edge.
SUBJECT = 0, 447, W, 1983
TEXT = 64, 230, W - 64, 560  # headlines stay in this box, above the phones

# The music is 120 BPM and cut on its bar lines (EDIT in showcase.py), so a bar of the film is 2 s.
BEAT = 15  # frames
BAR = 4 * BEAT
# The bar each scene starts on, counted from the film's first frame. The drums come in on bar 2, at 4 s.
WIDGET, COUNTDOWN, QUESTION, PLAY, DRAW, MEMORIES, END = 0, 0.5, 1.5, 6.5, 8, 10.5, 12
POSTERS = 60, 150  # frames that must be clean holds: 2.0 s and 5.0 s


def at(bar, beats=0, frames=0):
    """The frame a bar line or a beat after it falls on, plus a number of frames."""
    return round(bar * BAR + beats * BEAT + frames)


# The main phone's screen through the film, as (frame the change is centred on, screen). Each change dissolves over
# DISSOLVE frames. 06-draw is on a second phone of its own, which is in the film over the frames of SECOND_PHONE.
SHOTS = [(0, '01-widget'), (at(QUESTION), '02-question'), (at(PLAY, 0, -4), '03-ludo'),
         (at(MEMORIES, 0, -4), '05-memories')]
DISSOLVE = 10
SECOND_PHONE = at(DRAW, 0, -16), at(MEMORIES, 0, 5)
SCREENS = '01-widget', '05-memories'  # the stills; the other screens are recordings


class Clip(NamedTuple):
    """A stretch of a screen recording. From film frame `start` the recording plays at `speed`, placed so that its
    event `event` falls `after` film frames past `start`. With `fit`, a later event, the speed is instead the one that
    brings that event to the next clip's start. A clip runs until the next clip of the same screen, and the first one
    also covers the frames before its start. With `dissolve`, the clip fades in over that many frames from its start,
    over the clip before it held on the frame that clip reached at the start."""
    start: int
    event: str
    after: float = 0
    speed: float = 1.0
    fit: str | None = None
    dissolve: int = 0


# The film frames 02-question's moments fall on. The card tap comes 3 frames before the drums, so the answer cover
# starts to open on their first downbeat. The question stays at its full size until the tap on the text field, the
# keyboard rises and the photo shrinks at their own pace, the typing takes 1 s, the conversation comes in on a bar
# line, and the swipe to the earlier day starts about 1.5 s after the partner's answer has opened. The list coasts
# for 2.5 s after the swipe, which the film plays in under 1 s. Fit these to the recording; FOOTAGE plays the
# stretches between them.
CARD_TAP = at(QUESTION, 2, -3)
QUESTION_SHOWN = at(QUESTION, 3)
PHOTO_TAP = at(QUESTION, 4, 6)
FIELD_TAP = at(QUESTION, 5, 6)
TYPING = at(QUESTION, 6, 13)
TYPED = at(QUESTION, 8, 14)
SEND = at(QUESTION, 9, 6)
REVEAL = at(QUESTION, 10)
SCROLL = at(QUESTION, 15, 8)
SCROLLED = at(QUESTION, 17, 5)
PICKER_DISSOLVE = 7  # frames from the photo tap to the photo in the composer, so the picker never shows
REVEAL_DISSOLVE = 8  # frames from the sending answer to the conversation resting on today

# The screen recordings, cut against their events so every locale's recording lines up without numbers of its own.
# Ludo: the die is flicked a third of a second after the screen is fully in and rolls at its own pace. The recording
# then waits several seconds for the pawn's tap, so the film cuts to just before the pawn hops, and holds before the
# partner's turn, which would otherwise start at a different moment in each locale. Draw & Guess: the drawing's last
# strokes play at twice their speed as the phone arrives, the guess cuts in just before its first letter, its letters
# play in a second, and the celebration then plays at its own pace.
FOOTAGE = {
    '02-question': (Clip(CARD_TAP, 'card tap', fit='question shown'),
                    Clip(QUESTION_SHOWN, 'question shown', fit='photo tap'),
                    Clip(PHOTO_TAP, 'photo staged', speed=0, dissolve=PICKER_DISSOLVE),
                    Clip(FIELD_TAP - 2, 'field tap', 2),
                    Clip(TYPING, 'typing starts', fit='typing done'),
                    Clip(TYPED, 'typing done', speed=0), Clip(SEND - 2, 'send tap', 2),
                    Clip(REVEAL, 'today shown', dissolve=REVEAL_DISSOLVE),
                    Clip(SCROLL, 'scroll starts', fit='scroll settled'), Clip(SCROLLED, 'scroll settled')),
    '03-ludo': (Clip(at(PLAY, 0, 10), 'die tap'), Clip(at(PLAY, 0, 56), 'piece starts', 8),
                Clip(at(DRAW, 0, 30), 'partner die starts', speed=0)),
    '06-draw': (Clip(at(DRAW, 0, 24), 'drawing done', speed=2),
                Clip(at(DRAW, 0, 27), 'first tap', 2, fit='last tap'), Clip(at(DRAW, 0, 57), 'last tap')),
}


class Recording(NamedTuple):
    """A screen recording: its mp4, the seconds of each named event from its first frame, its taps as (seconds, x, y)
    with x and y as fractions of the screen, its swipes as (seconds, x, y, x it ends on, y it ends on, seconds the
    finger drags), and the seconds of its last frame."""
    path: Path
    events: dict
    taps: list
    swipes: list
    length: float


def recording(folder, locale, screen):
    """The recording that stands in for a capture: <capture>.mp4 beside its <capture>.events.json. The first and last
    tap count as the events 'first tap' and 'last tap'."""
    path = capture(folder, locale, screen).with_suffix('.mp4')
    notes = path.with_suffix('.events.json')
    for p in (path, notes):
        if not p.exists():
            raise SystemExit(f'Missing recording {p}. Pass --captures, or make stand-ins with showcase.py '
                             f'--placeholders.')
    events = json.loads(notes.read_text())
    taps = sorted((tap['t'], tap['x'], tap['y']) for tap in events.pop('taps', []))
    if taps:
        events['first tap'], events['last tap'] = taps[0][0], taps[-1][0]
    swipes = [tuple(swipe[key] for key in ('t', 'x', 'y', 'to_x', 'to_y', 'seconds'))
              for swipe in events.pop('swipes', [])]
    missing = {name for clip in FOOTAGE[screen] for name in (clip.event, clip.fit) if name} - set(events)
    if missing:
        raise SystemExit(f'{notes} has no {", ".join(sorted(missing))}')
    frames = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-count_packets', '-show_entries',
                             'stream=nb_read_packets', '-of', 'csv=p=0', str(path)],
                            capture_output=True, text=True, check=True).stdout
    return Recording(path, events, taps, swipes, (int(frames) - 1) / FPS)


def clip_at(screen, frame):
    """Index in FOOTAGE[screen] of the clip that plays at film frame `frame`."""
    return max([0] + [i for i, clip in enumerate(FOOTAGE[screen]) if clip.start <= frame])


def clip_time(screen, k, frame, rec):
    """Seconds into the recording at film frame `frame` as clip k of `screen` plays it, held on the recording's first
    and last frames."""
    clips = FOOTAGE[screen]
    clip = clips[k]
    speed = clip.speed
    if clip.fit:
        speed = (rec.events[clip.fit] - rec.events[clip.event]) * FPS / (clips[k + 1].start - clip.start - clip.after)
    return min(max(rec.events[clip.event] + (frame - clip.start - clip.after) * speed / FPS, 0.0), rec.length)


def footage_time(screen, frame, rec):
    """Seconds into the recording of `screen` at film frame `frame`."""
    return clip_time(screen, clip_at(screen, frame), frame, rec)


def footage_mix(screen, frame, rec):
    """What the glass shows of the recording at film frame `frame`, as (seconds, weight) pairs: one, or two while a
    clip dissolves in, eased like the dissolves between SHOTS."""
    k = clip_at(screen, frame)
    clip = FOOTAGE[screen][k]
    now = clip_time(screen, k, frame, rec)
    x = (frame - clip.start + 0.5) / clip.dissolve if clip.dissolve else 1
    if x >= 1: return [(now, 1.0)]
    w = (1 - math.cos(math.pi * x)) / 2
    return [(clip_time(screen, k - 1, clip.start, rec), 1 - w), (now, w)]


def showing(screen):
    """The film frames a recorded screen is on a phone, dissolves included."""
    if screen == '06-draw':
        return range(*SECOND_PHONE)
    i = [s for _, s in SHOTS].index(screen)
    end = SHOTS[i + 1][0] + DISSOLVE // 2 + 1 if i + 1 < len(SHOTS) else FRAMES
    return range(SHOTS[i][0] - DISSOLVE // 2, end)


class Region(NamedTuple):
    """A part of a capture: its screen, its box (left, top, right, bottom) in capture pixels and its corner radius in
    capture pixels."""
    screen: str
    box: tuple
    radius: float = 0


# Every part of a capture the film lifts off the glass or draws strokes on. The boxes are measured on the captures,
# so this is the one table to tune when they change. The canvas is the square the drawing's 320 pt canvas fills in the
# capture, where the film replays the strokes. `showcase.py --fit` measures it, and its corners round like the app's
# DrawingCanvasShape, by 28/360 of its side.
REGIONS = {
    'drawing widget': Region('01-widget', (75, 287, 1245, 1457), 84),
    'widget canvas': Region('01-widget', (212, 340, 1108, 1236)),
    'streak widget': Region('01-widget', (75, 1523, 625, 2073), 84),
    'countdown widget': Region('01-widget', (695, 1523, 1245, 2073), 84),
    'photo 1': Region('05-memories', (684, 547, 1212, 1075), 40),
    'photo 2': Region('05-memories', (684, 1370, 1212, 1898), 40),
    'photo 3': Region('05-memories', (684, 2193, 1212, 2590), 40),
}
# The drawing each canvas shows, as the stem of its stroke file in scripts/assets/app-store/. {lang} is the
# drawing's language in LOCALES.
DRAWINGS = {'widget canvas': 'widget-drawing-plane-{lang}'}


def canvas_radius(side):
    return side * 28 / 360


def capture(folder, locale, screen):
    return Path(folder) / CONFIG['capture'].replace('{locale}', locale).replace('{device}', 'iPhone').replace(
        '{screen}', screen)


def layer(locale, preview):
    """Folder of the 3D layer's frames for a locale."""
    return OUT / f'layer-{locale}{"-preview" if preview else ""}'


# iPhone 17 Pro Max in millimetres, as in scripts/lib/device3d.mjs.
PHONE_W, PHONE_H, PHONE_D, PHONE_R, EDGE = 78, 163.4, 8.75, 13.5, 1.4
GLASS_W, GLASS_H = PHONE_W - 2 * EDGE, PHONE_H - 2 * EDGE
PX_PER_MM = 460 / 25.4  # 460 ppi, so a 1320 x 2868 capture fills the display exactly
CAPTURE = 1320, 2868
CANVAS = round(GLASS_W * PX_PER_MM), round(GLASS_H * PX_PER_MM)
OFFSET = (CANVAS[0] - CAPTURE[0]) // 2, (CANVAS[1] - CAPTURE[1]) // 2  # capture corner on the glass texture
SCREEN_RADIUS = 186


def glare(x, y):
    """The faint glare scripts/lib/device3d.mjs lays over the glass, at glass texture pixels x, y. It is the share of
    white mixed in, from 8 % at the top left corner to none past 46 % of the way down."""
    cw, ch = CANVAS
    t = (x * cw + y * 0.6 * ch) / (cw ** 2 + (0.6 * ch) ** 2)
    return np.where(t < 0.46, np.interp(t, [0, 0.46], [0x14 / 255, 0x05 / 255]), 0)


def on_glass(pixels):
    """A capture (H x W x 3, 0 to 255) as it looks on the glass, with the glare mixed in."""
    y, x = np.mgrid[0:CAPTURE[1], 0:CAPTURE[0]] + 0.5
    g = glare(x + OFFSET[0], y + OFFSET[1])[..., None]
    return pixels * (1 - g) + 255 * g
