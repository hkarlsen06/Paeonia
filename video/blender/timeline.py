"""Frame grid, region table and phone geometry shared by phone3d.py, which renders the 3D layer in Blender, and
showcase.py, which draws the rest."""
import json
import re
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
SUBJECT = 0, 600, W, 1880  # pixel box (left, top, right, bottom) the camera frames the phones in
TEXT = 64, 168, W - 64, 560  # headlines stay in this box, above the phones

# The music is 120 BPM and cut on its bar lines (EDIT in showcase.py), so a bar of the film is 2 s.
BEAT = 15  # frames
BAR = 4 * BEAT
# The bar each scene starts on, counted from the film's first frame.
WIDGET, COUNTDOWN, HOME, CHAT, PLAY, DRAW, MEMORIES, SPOTLIGHT, ROUTE, END = 0, 1, 2, 3, 5, 6, 8, 10, 12, 13
POSTERS = 90, 150  # frames that must be clean holds: 3.0 s and 5.0 s


def at(bar, beats=0, frames=0):
    """The frame a bar line or a beat after it falls on, plus a number of frames."""
    return round(bar * BAR + beats * BEAT + frames)


# The main phone's screen through the film, as (frame the change is centred on, screen). Each change dissolves over
# DISSOLVE frames. 06-draw is on a second phone of its own in the games scene.
SHOTS = [(0, '01-widget'), (at(HOME, 0, 2), '04-home'), (at(CHAT, 0, -4), '02-chat'), (at(PLAY, 0, -4), '03-ludo'),
         (at(MEMORIES, 0, -4), '05-memories'), (at(SPOTLIGHT, 0, -4), '04-home')]
DISSOLVE = 10
SCREENS = '01-widget', '02-chat', '03-ludo', '04-home', '05-memories', '06-draw'


class Region(NamedTuple):
    """A part of a capture: its screen, its box (left, top, right, bottom) in capture pixels, or one box per locale
    when a translation moves it, and its corner radius in capture pixels."""
    screen: str
    box: tuple | dict
    radius: float = 0


# Every part of a capture the film lifts off the glass or draws strokes on. The boxes are measured on the captures,
# so this is the one table to tune when they change. A canvas is the square the drawing's 320 pt canvas fills in the
# capture, where the film replays the strokes. `showcase.py --fit` measures it, and its corners round like the app's
# DrawingCanvasShape, by 28/360 of its side.
REGIONS = {
    'drawing widget': Region('01-widget', (75, 287, 1245, 1457), 84),
    'widget canvas': Region('01-widget', (212, 340, 1108, 1236)),
    'streak widget': Region('01-widget', (75, 1523, 625, 2073), 84),
    'countdown widget': Region('01-widget', (695, 1523, 1245, 2073), 84),
    'envelope': Region('04-home', (40, 950, 1280, 1400), 64),
    'countdown tile': Region('04-home', (60, 1423, 636, 1999), 72),
    'partner answer': Region('02-chat', {'en-US': (144, 730, 983, 1050), 'no': (144, 664, 1010, 984)}, 54),
    'your answer': Region('02-chat', {'en-US': (230, 1074, 1284, 1328), 'no': (277, 1008, 1284, 1328)}, 54),
    'photo 1': Region('05-memories', (684, 547, 1212, 1075), 40),
    'photo 2': Region('05-memories', (684, 1370, 1212, 1898), 40),
    'photo 3': Region('05-memories', (684, 2193, 1212, 2590), 40),
    'snail canvas': Region('06-draw', (61, 481, 1259, 1679)),
}
# The drawing each canvas shows, as the stem of its stroke file in scripts/assets/app-store/. {lang} is the
# drawing's language in LOCALES.
DRAWINGS = {'widget canvas': 'widget-drawing-plane-{lang}', 'snail canvas': 'game-drawing-snail'}


def canvas_radius(side):
    return side * 28 / 360


def box(name, locale):
    value = REGIONS[name].box
    return value[locale] if isinstance(value, dict) else value


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
