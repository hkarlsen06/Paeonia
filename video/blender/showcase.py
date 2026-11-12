# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["skia-python", "numpy"]
# ///
"""Paeonia's promotional film, 29.5 s at 886 x 1920, App Store Connect's app preview size. Skia draws every frame
around the 3D layer from phone3d.py and cuts the music to it. Run from the repository root:

  /Applications/Blender.app/Contents/MacOS/Blender -b -P video/blender/phone3d.py -- [--preview] [--locale no]
  uv run video/blender/showcase.py [--preview] [--still F F ...] [--locale en-US] [--captures DIR]

Writes video/blender/out/paeonia-showcase-<locale>.mp4, or -preview.mp4 at half size from the preview layer.
--still writes those frames and a contact sheet to video/blender/out/stills/ instead.
--placeholders DIR writes marked stand-in captures and screen recordings for every locale into DIR, to render with
before the real ones.
--fit measures where the widget drawing sits in the captures, to copy into REGIONS in timeline.py.
--check compares the replayed drawings with their PencilKit previews, checks the timing rules and the cut music.

The music is "Day Dreamin' with U" by Michael Ramir C. from Mixkit, under the Mixkit Stock Music Free License:
https://assets.mixkit.co/music/988/988.mp3. Download it to video/blender/music.mp3. The license lets the film use
it, but not redistribute the file on its own, so it stays out of this public repository.
"""
import argparse
import json
import math
import os
import re
import subprocess
import sys
from functools import cache
from pathlib import Path
from multiprocessing import Pool
from typing import NamedTuple

import numpy as np
import skia

from strokes import Strokes, inpaint
from timeline import (ASSETS, BEAT, CAPTURE, CAPTURES, CONFIG, COUNTDOWN, DISSOLVE, DRAWINGS, END, FOOTAGE, FPS,
                      FRAMES, H, LOCALES, MEMORIES, OUT, PLAY, POSTERS, QUESTION, REGIONS, ROOT, SCREENS, SHOTS,
                      SUBJECT, TEXT, W, WIDGET, at, canvas_radius, capture, clip_at, clip_time, footage_time, layer,
                      on_glass, recording, showing)

MUSIC, SR = ROOT / 'video/blender/music.mp3', 48000
BRAND = ROOT / 'video/brand'
RGBA = skia.ColorType.kRGBA_8888_ColorType
SAMPLING = skia.SamplingOptions(skia.FilterMode.kLinear, skia.MipmapMode.kLinear)
HEADLINE, MARK, WORDMARK, TAGLINE, SMALL, BADGE = 72, 340, 148, 46, 32, 100


def hexc(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))


WHITE, BLACK, TEXT_COLOR, ACCENT = (255, 255, 255), (0, 0, 0), hexc(CONFIG['text']), hexc(CONFIG['accent'])
GLOW, GLOW_ALPHA = hexc(CONFIG['glow']), int(CONFIG['glow'][7:9], 16) / 255
SHADOW, SHADOW_ALPHA = hexc(CONFIG['shadow']), int(CONFIG['shadow'][7:9], 16) / 255
GRADIENT = [hexc('#' + c) for c in re.findall(r'#(\w{6})', CONFIG['background'])]
STOPS = [int(p) / 100 for p in re.findall(r'(\d+)%', CONFIG['background'])]
ANGLE = math.radians(int(re.search(r'(\d+)deg', CONFIG['background'])[1]))

# On-screen text, as (panel, line) in the "panels" of paeonia-3d.json, where line 0 is the headline and 1 the body.
# The film reuses the approved App Store copy, so any locale the screenshots have renders here as well.
COPY = {'drawing': (0, 0), 'drawing body': (0, 1), 'question': (1, 0), 'play': (2, 0), 'moments': (4, 0)}
# Headlines, as (copy, frame the first word rises on, frame the words leave on). A rise of None means the words are
# already up on the first frame.
# Each leaves just before its scene's last bar line and the next rises just before the bar, so its words have
# settled by the second beat. The question's headline leaves before the photo tap instead, since the camera then
# moves in close and the phone fills the space above it.
HEADLINES = [('drawing', None, at(QUESTION, 0, -14)), ('question', at(QUESTION, 0, -2), at(QUESTION, 5, 3)),
             ('play', at(PLAY, 0, -2), at(MEMORIES, 0, -14)), ('moments', at(MEMORIES, 0, -2), at(END, 0, -14))]
# The music is the track cut on its bar lines, as (first bar of the track counted from 1, bars). Two soft intro bars,
# ten bars from the drums' entry, then the closing bar, whose ring-out is silent by the last frame.
BAR0, BAR_S = 1.99, 2.0  # 10 ms before the track's first downbeat, whose drum hits fall at 2.000 s, and the bar length
EDIT = [(15, 2), (17, 10), (54, None)]
RISE, SETTLE, HANDOVER = 20, 16, 8  # frames a lift takes to rise and to settle, and a replay to hand over


class Lift(NamedTuple):
    """A region rising off the glass. It has the frame it starts to rise, the frame it starts to settle back, its
    width on screen when up, how far its centre moves from its place on the glass, and how far it turns in degrees.
    Cards stack in the order of LIFTS, the later one in front."""
    rise: float
    settle: float
    width: float
    move: tuple = (0, 0)
    turn: float = 0


LIFTS = {
    'drawing widget': Lift(-RISE, at(COUNTDOWN, 0, 8), 540, (0, -10)),
    'countdown widget': Lift(at(COUNTDOWN, 0, 6), at(QUESTION, 0, -19), 330, (70, -30)),
    'photo 1': Lift(at(MEMORIES, 0, 8), at(END, 0, -26), 270, (-80, -40), -9),
    'photo 2': Lift(at(MEMORIES, 0, 14), at(END, 0, -22), 280, (10, -110), 2),
    'photo 3': Lift(at(MEMORIES, 0, 20), at(END, 0, -18), 270, (110, -40), 10),
}


class Replay(NamedTuple):
    """A drawing's strokes replaying on its canvas region. It has the frame the replay starts, the frame its last
    stroke ends, and how many strokes are already there when it starts. HANDOVER frames after the end the replay has
    dissolved into the capture's own pixels."""
    start: float
    end: float
    shown: int = 0


# The film opens with the first 12 of the route's 24 dashes drawn.
REPLAYS = {'widget canvas': Replay(0, at(WIDGET, 1, 13), 12)}
PHONE_GONE = at(END, 0, 18)  # the main phone has sunk out of the frame; its lifted cards fade with it
TOUCH = 8  # frames a tap of a screen recording shows as a dot on the glass


# Timing -----------------------------------------------------------------------------------------------------------

def clamp(x, a=0.0, b=1.0): return a if x < a else b if x > b else x
def lerp(a, b, x): return a + (b - a) * x
def prog(t, t0, t1): return clamp((t - t0) / (t1 - t0))
def io3(x): return 4 * x ** 3 if x < 0.5 else 1 - (2 - 2 * x) ** 3 / 2
def back(x, s=0.9): return 1 + (s + 1) * (x - 1) ** 3 + s * (x - 1) ** 2


def spring(frames, z=0.8, w=11.0):
    """Unit step response of a damped spring, `frames` after it starts; 0 before."""
    tau = frames / FPS
    if tau <= 0: return 0.0
    wd = w * math.sqrt(1 - z * z)
    return 1 - math.exp(-z * w * tau) * (math.cos(wd * tau) + z * w / wd * math.sin(wd * tau))


def kf(t, *keys):
    """Keys are (frame, value[, ease]); a key's ease shapes the move that ends on it."""
    if t <= keys[0][0]: return keys[0][1]
    for (t0, v0, *_), (t1, v1, *e) in zip(keys, keys[1:]):
        if t < t1:
            x = (e[0] if e else io3)((t - t0) / (t1 - t0))
            return tuple(lerp(a, b, x) for a, b in zip(v0, v1)) if isinstance(v0, tuple) else lerp(v0, v1, x)
    return keys[-1][1]


# Drawing ----------------------------------------------------------------------------------------------------------

def argb(c, a=1.0): return skia.ColorSetARGB(round(255 * clamp(a)), *c)
def paint(c=WHITE, a=1.0, **kw): return skia.Paint(Color=argb(c, a), AntiAlias=True, **kw)
def rrect(l, t, r, b, rad): return skia.RRect.MakeRectXY(skia.Rect.MakeLTRB(l, t, r, b), rad, rad)


def poly(w, h, dst):
    """The matrix that takes a w x h box onto the four corners dst (top left, top right, bottom right, bottom left)."""
    m = skia.Matrix()
    m.setPolyToPoly([skia.Point(0, 0), skia.Point(w, 0), skia.Point(w, h), skia.Point(0, h)],
                    [skia.Point(*p) for p in dst])
    return m


def backdrop(cv, t):
    """The brand gradient and the glow behind the phone. The film drifts a little along the App Store strip's
    gradient and comes back to where it started, so the last frame meets the first; the glow pulses with the bass."""
    p = kf(t, (0, 0.0), (at(PLAY), 0.10), (at(MEMORIES), 0.16), (at(END), 0.22), (FADE, 0.22), (FRAMES - 2, 0.0))
    length = W / 0.18  # the frame is a sixth of the strip
    dx, dy = math.sin(ANGLE), -math.cos(ANGLE)  # CSS angles: 0deg points up, 90deg right
    x0 = -p * length
    cv.drawPaint(skia.Paint(Shader=skia.GradientShader.MakeLinear(
        [skia.Point(x0, 0), skia.Point(x0 + dx * length, dy * length)], [argb(c) for c in GRADIENT], STOPS)))
    pulse = A.pulse[min(max(round(t), 0), FRAMES - 1)]
    phone_h = 0.82 * (SUBJECT[3] - SUBJECT[1])
    subject = ((SUBJECT[0] + SUBJECT[2]) / 2, (SUBJECT[1] + SUBJECT[3]) / 2)
    gx, gy = kf(t, (at(END), subject), (at(END, 3), (W / 2, H / 2)), (FADE, (W / 2, H / 2)),
                (FRAMES - 2, subject))
    m = skia.Matrix.Translate(gx, gy)
    m.preScale(0.55 * phone_h, 0.45 * phone_h)  # CSS: radial-gradient(0.55h 0.45h at the phone, glow, transparent)
    cv.drawPaint(skia.Paint(Shader=skia.GradientShader.MakeRadial(
        skia.Point(0, 0), 1, [argb(GLOW, GLOW_ALPHA * pulse), argb(GLOW, 0)], [0, 1], skia.TileMode.kClamp, 0, m)))


def image(pixels):
    """An H x W x 3 array of 0 to 255 values as an opaque Skia image."""
    rgba = np.dstack([np.clip(np.rint(pixels), 0, 255).astype(np.uint8), np.full(pixels.shape[:2], 255, np.uint8)])
    return skia.Image.fromarray(np.ascontiguousarray(rgba), RGBA).withDefaultMipmaps()


# Lift-outs and overlays on the glass -------------------------------------------------------------------------------

def quad(name, t):
    """Corners of a region on screen at time t, between the frames phone3d.py tracked."""
    f = clamp(t, 0, FRAMES - 1)
    i = min(int(f), FRAMES - 2)
    a, b, x = A.track[name][i], A.track[name][i + 1], f - i
    return [(lerp(a[k], b[k], x), lerp(a[k + 1], b[k + 1], x)) for k in range(0, 8, 2)]


def centre(points): return sum(p[0] for p in points) / 4, sum(p[1] for p in points) / 4


def raised(name, t):
    """0 on the glass, 1 lifted (overshooting a little on the way up)."""
    lift = LIFTS[name]
    return back(prog(t, lift.rise, lift.rise + RISE)) * (1 - io3(prog(t, lift.settle, lift.settle + SETTLE)))


def target(name, t):
    """Corners of the lifted card, which faces the camera at the lift's width, moved and turned."""
    lift = LIFTS[name]
    l, tp, r, b = REGIONS[name].box
    w, h = lift.width, lift.width * (b - tp) / (r - l)
    cx, cy = centre(quad(name, t))
    cx, cy = cx + lift.move[0], cy + lift.move[1]
    c, s = math.cos(math.radians(lift.turn)), math.sin(math.radians(lift.turn))
    return [(cx + x * c - y * s, cy + x * s + y * c) for x, y in ((-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2),
                                                                  (-w / 2, h / 2))]


def card(cv, name, e, alpha, content):
    """The region `name` raised by e from its place on the glass, as a soft shadow and then the content drawn by
    content(canvas) in the region's own capture pixels, clipped to its corners."""
    t = A.t
    l, tp, r, b = REGIONS[name].box
    w, h, radius = r - l, b - tp, REGIONS[name].radius
    dst = [(lerp(p[0], q[0], e), lerp(p[1], q[1], e)) for p, q in zip(quad(name, t), target(name, t))]
    m = poly(w, h, dst)
    s = clamp(e)
    outline = skia.Path()
    outline.addRRect(rrect(0, 0, w, h, radius))
    outline.transform(m)
    cv.save()
    cv.translate(0, 30 * s)
    cv.drawPath(outline, paint(SHADOW, SHADOW_ALPHA * s * alpha, MaskFilter=skia.MaskFilter.MakeBlur(
        skia.kNormal_BlurStyle, 6 + 22 * s)))
    cv.restore()
    cv.save()
    cv.concat(m)
    cv.clipRRect(rrect(0, 0, w, h, radius), True)
    if alpha < 1: cv.saveLayerAlpha(None, round(255 * alpha))
    content(cv)
    if alpha < 1: cv.restore()
    cv.restore()
    return m


def lifts(cv, t):
    """Parts of the screen rise off the glass toward the viewer, then settle back. A card starts exactly on its
    region of the 3D screen, so the lift reads as the pixels themselves coming loose; the glass under it darkens like
    the shadow it leaves."""
    alpha = 1 - prog(t, at(END, 0, -4), PHONE_GONE)
    up = [(name, raised(name, t)) for name in LIFTS]
    up = [(name, e) for name, e in up if e > 0.002 and alpha > 0]
    for name, e in up:
        l, tp, r, b = REGIONS[name].box
        hole = skia.Path()
        hole.addRRect(rrect(0, 0, r - l, b - tp, REGIONS[name].radius))
        hole.transform(poly(r - l, b - tp, quad(name, t)))
        cv.drawPath(hole, paint(BLACK, 0.4 * clamp(3 * e) * alpha))
    for name, e in up:
        def content(c, name=name):
            c.drawImage(A.crops[name], 0, 0, SAMPLING)
            if name == 'drawing widget': replay(c, 'widget canvas', t, REGIONS[name].box)
        card(cv, name, e, alpha, content)


def replay(cv, name, t, inside):
    """A drawing replaying on its canvas region, drawn in the capture pixels of `inside` (left, top, ...), which holds
    the region. Behind the strokes is the canvas's own background; HANDOVER frames after the last stroke the replay
    has dissolved into the capture."""
    spec = REPLAYS[name]
    alpha = 1 - prog(t, spec.end, spec.end + HANDOVER)
    if t < spec.start - 2 or alpha <= 0: return
    strokes = A.strokes[name]
    l, tp, r, b = REGIONS[name].box
    shown = strokes.total(range(spec.shown)) + strokes.GAP if spec.shown else 0
    u = lerp(shown, strokes.total(range(len(strokes.strokes))), prog(t, spec.start, spec.end))
    cv.save()
    cv.translate(l - inside[0], tp - inside[1])
    cv.clipRRect(rrect(0, 0, r - l, b - tp, canvas_radius(r - l)), True)
    cv.saveLayerAlpha(None, round(255 * alpha))
    cv.drawImage(A.blank[name], 0, 0, SAMPLING)
    cv.scale((r - l) / strokes.side, (b - tp) / strokes.side)
    strokes.draw(cv, u)
    cv.restore()
    cv.restore()


def touches(cv, t):
    """Each tap in a screen recording as a soft white dot on the glass under the finger, and each swipe as a dot
    that moves with it. A touch on the main phone that the Draw & Guess phone covers is not shown."""
    front = skia.Path()
    front.addPoly([skia.Point(*p) for p in quad('draw screen', t)], True)
    for screen in FOOTAGE:
        name = 'draw screen' if screen == '06-draw' else 'screen'
        m = poly(*CAPTURE, quad(name, t))

        def dot(x, y, radius, alpha):
            px, py = m.mapXY(x * CAPTURE[0], y * CAPTURE[1])
            if name == 'screen' and front.contains(px, py): return
            cv.save()
            cv.concat(m)
            cv.drawCircle(x * CAPTURE[0], y * CAPTURE[1], radius,
                          paint(WHITE, 0.5 * alpha, MaskFilter=skia.MaskFilter.MakeBlur(skia.kNormal_BlurStyle, 10)))
            cv.restore()

        for frame, _, x, y in A.taps[screen]:
            age = t - frame
            if 0 <= age < TOUCH:
                dot(x, y, 66 + 10 * prog(age, 0, TOUCH), prog(age, 0, 2) * (1 - io3(prog(age, 3, TOUCH))))
        for down, up, x, y, to_x, to_y in A.swipes[screen]:
            if down - 2 <= t < up + 4:
                k = prog(t, down, up)
                dot(x + (to_x - x) * k, y + (to_y - y) * k, 66,
                    prog(t, down - 2, down) * (1 - io3(prog(t, up, up + 4))))


def tap_frames(screen, rec):
    """The film frame each tap of a recording falls on, with its seconds in the recording and its x and y, for the
    taps the cut plays through. A clip that dissolves in shows the clip before it up to its start, and the taps that
    clip reaches there; the stretch it skips shows none."""
    taps, clips = [], FOOTAGE[screen]
    for f in showing(screen):
        k = clip_at(screen, f)
        before, now = footage_time(screen, f - 1, rec), footage_time(screen, f, rec)
        if k and f == clips[k].start:
            if not clips[k].dissolve: continue
            now = clip_time(screen, k - 1, f, rec)
        # A clip with `fit` reaches its event within rounding of the frame it lands on.
        taps += [(f - (now - s) / (now - before), s, x, y) for s, x, y in rec.taps if before < s <= now + 1e-9]
    return taps


def swipe_frames(screen, rec):
    """Each swipe of a recording as the film frame the finger lands on, the frame it lifts on, and where it starts
    and ends on the screen."""
    def reached(seconds):
        return next(f for f in showing(screen) if footage_time(screen, f, rec) >= seconds - 1e-6)
    return [(reached(s), reached(s + drag), x, y, to_x, to_y) for s, x, y, to_x, to_y, drag in rec.swipes]


# Type -------------------------------------------------------------------------------------------------------------

@cache
def font(size):
    f = skia.Font(A.typeface, size)
    f.setSubpixel(True)
    f.setLinearMetrics(True)
    f.setHinting(skia.FontHinting.kNone)
    f.setEdging(skia.Font.Edging.kAntiAlias)
    return f


@cache
def blob(word, size): return skia.TextBlob.MakeFromShapedText(word, font(size))  # kerned; y = 0 is the ascent line


def wrap(advances, space, width):
    lines, used = [[]], 0.0
    for i, a in enumerate(advances):
        if lines[-1] and used + space + a > width:
            lines.append([])
            used = 0.0
        used += (space if lines[-1] else 0) + a
        lines[-1].append(i)
    return lines


@cache
def layout(markup, size, width, leading, align):
    """Words as (x, baseline, word, accent) in a box whose top left is 0, 0, and the block's height. <em> marks the
    accent and <br> a forced break; the lines between breaks are balanced like CSS text-wrap: balance."""
    segments, accent, glue = [[]], False, False
    for piece in re.split(r'(<br\s*/?>|</?em>)', markup):
        if piece.startswith('<br'):
            segments.append([])
            glue = False
        elif piece in ('<em>', '</em>'):
            accent = piece == '<em>'
        else:
            for j, word in enumerate(piece.split()):
                if j == 0 and glue and not piece[:1].isspace():  # no space at the tag, as in "</em>,"
                    segments[-1][-1] = (segments[-1][-1][0] + word, segments[-1][-1][1])
                else:
                    segments[-1].append((word, accent))
            glue = glue if not piece else bool(segments[-1]) and not piece[-1].isspace()
    words, row = [], 0
    space = font(size).measureText(' ')
    for tokens in segments:
        advances = [font(size).measureText(word) for word, _ in tokens]
        count = len(wrap(advances, space, width))
        lo, hi = max(advances), width
        for _ in range(16):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if len(wrap(advances, space, mid)) > count else (lo, mid)
        for line in wrap(advances, space, hi):
            used = sum(advances[i] for i in line) + space * (len(line) - 1)
            x = (width - used) / 2 if align == 'center' else 0.0
            for i in line:
                words.append((x, (row * leading + 0.86) * size, *tokens[i]))
                x += advances[i] + space
            row += 1
    return tuple(words), row * leading * size


def headline(cv, markup, box_, t, t_in, t_out=None, size=HEADLINE, align='left', leading=1.08, alpha=1.0,
             color=TEXT_COLOR, gap=2.5):
    """Words rise through their line one by one on a calm spring, then drift up and fade. With t_in None the words
    are already up."""
    left, top, right, _ = box_
    words, _ = layout(markup, size, right - left, leading, align)
    for n, (x, y, word, accent) in enumerate(words):
        e_in = 1.0 if t_in is None else spring(t - t_in - n * gap, 0.85, 10)
        e_out = io3(prog(t, t_out + n, t_out + n + 12)) if t_out is not None else 0.0
        if e_in <= 0.001 or e_out >= 0.999: continue
        cv.save()
        cv.clipRect(skia.Rect.MakeLTRB(left - 60, top + y - 1.1 * size, right + 60, top + y + 0.36 * size))
        baseline = top + y + (1 - e_in) * size * 0.9 - e_out * size * 0.6
        cv.drawTextBlob(blob(word, size), left + x, baseline + font(size).getMetrics().fAscent,
                        paint(ACCENT if accent else color, alpha * clamp(1.4 * e_in) * (1 - e_out)))
        cv.restore()


def headlines(cv, t):
    for key, t_in, t_out in HEADLINES:
        if (t_in is None or t >= t_in - 1) and t < t_out + 30:
            headline(cv, A.copy[key], TEXT, t, t_in, t_out)
            if key == 'drawing':  # the only scene with a line under its headline, as in the App Store panel
                _, height = layout(A.copy[key], HEADLINE, TEXT[2] - TEXT[0], 1.08, 'left')
                top = TEXT[1] + height + 0.38 * HEADLINE
                headline(cv, A.copy['drawing body'], (TEXT[0], top, TEXT[2], TEXT[3]), t, t_in, t_out + 3,
                         size=0.48 * HEADLINE, leading=1.32, alpha=0.72)


def svg_image(path, height):
    """The SVG rendered `height` pixels tall. Skia's SVG renderer skips <style>, so class fills are written inline."""
    text = path.read_text()
    for name, fill in re.findall(r'\.(\w+)\s*{\s*fill:\s*(#\w+);?\s*}', text):
        text = text.replace(f'class="{name}"', f'fill="{fill}"')
    dom = skia.SVGDOM.MakeFromStream(skia.MemoryStream.MakeCopy(text.encode()))
    w0, h0 = (float(v) for v in re.search(r'viewBox="[\d.-]+ [\d.-]+ ([\d.]+) ([\d.]+)"', text).groups())
    dom.setContainerSize(skia.Size(w0, h0))
    k = height / h0
    surf = skia.Surface(round(w0 * k), round(height))
    c = surf.getCanvas()
    c.scale(k, k)
    dom.render(c)
    return surf.makeImageSnapshot().withDefaultMipmaps()


# The end card ------------------------------------------------------------------------------------------------------

# The phone sinks away from END. The mark rises on the downbeat of the music's last chord and the wordmark right after
# it. The tagline then rises a word every TAGLINE_GAP frames, and the subscription line only once the tagline has been
# fully up for a moment. From FADE everything fades to the first frame's plum.
CARD = {'mark': at(END), 'wordmark': at(END, 0, 6), 'tagline': at(END, 0, 22), 'small': at(END, 0, 82),
        'badge': at(END, 0, 98)}
TAGLINE_GAP, SMALL_GAP = 3.5, 3
FADE = FRAMES - 16


def wordmark():
    """The wordmark and the box of its ink, found by drawing it. The blob's own bounds leave room for the font's
    widest glyph on every side, so they do not centre the letters."""
    blob = skia.TextBlob.MakeFromShapedText('Paeonia', font(WORDMARK))
    loose = blob.bounds().roundOut()
    buf = np.zeros((loose.height(), loose.width(), 4), np.uint8)
    skia.Surface(buf).getCanvas().drawTextBlob(blob, -loose.left(), -loose.top(), paint(WHITE))
    rows, columns = (np.flatnonzero((buf[..., 3] > 127).any(axis)) for axis in (1, 0))
    return blob, skia.Rect.MakeLTRB(loose.left() + columns[0], loose.top() + rows[0], loose.left() + columns[-1] + 1,
                                    loose.top() + rows[-1] + 1)


def lockup():
    """Top edge of each line of the end card, stacked around the middle of the frame and kept above its bottom 15 %,
    where the App Store puts its controls."""
    tag_w = TEXT[2] - TEXT[0]
    _, tag_h = layout(A.tagline, TAGLINE, tag_w, 1.2, 'center')
    _, small_h = layout(A.small, SMALL, tag_w, 1.3, 'center')
    gaps = 90, 40, 26, 64
    heights = MARK / 2, A.wordmark[1].height(), tag_h, small_h, BADGE
    total = sum(heights) + sum(gaps)
    y = min(H / 2 - total / 2, 0.85 * H - total)
    tops = {}
    for key, height, gap in zip(('mark', 'wordmark', 'tagline', 'small', 'badge'), heights, (*gaps, 0)):
        tops[key] = y
        y += height + gap
    return tops


def endcard(cv, t):
    if t < CARD['mark'] - 1: return
    fade = 1 - io3(prog(t, FADE, FRAMES - 2))
    lock = lockup()

    def rise(key, drop):
        e = spring(t - CARD[key], 0.85, 10)
        return e, (1 - e) * drop, clamp(1.5 * e) * fade

    e, dy, alpha = rise('mark', 40)
    if e > 0.001:
        cv.drawImageRect(A.mark, skia.Rect.MakeXYWH(W / 2 - MARK / 2, lock['mark'] + dy, MARK, MARK / 2), SAMPLING,
                         paint(a=alpha))
    e, dy, alpha = rise('wordmark', 40)
    if e > 0.001:
        blob, ink = A.wordmark
        cv.drawTextBlob(blob, W / 2 - ink.centerX(), lock['wordmark'] + dy - ink.top(), paint(TEXT_COLOR, alpha))
    headline(cv, A.tagline, (TEXT[0], lock['tagline'], TEXT[2], 0), t, CARD['tagline'], None, size=TAGLINE,
             align='center', leading=1.2, alpha=fade, color=ACCENT, gap=TAGLINE_GAP)
    headline(cv, A.small, (TEXT[0], lock['small'], TEXT[2], 0), t, CARD['small'], None, size=SMALL, align='center',
             leading=1.3, alpha=0.72 * fade, gap=SMALL_GAP)
    e, dy, alpha = rise('badge', 24)
    if e > 0.001:
        bw = A.badge.width() * BADGE / A.badge.height()
        cv.drawImageRect(A.badge, skia.Rect.MakeXYWH(W / 2 - bw / 2, lock['badge'] + dy, bw, BADGE), SAMPLING,
                         paint(a=alpha))


# Frame ------------------------------------------------------------------------------------------------------------

def scene(cv, t, layer):
    A.t = t
    backdrop(cv, t)
    cv.drawImageRect(layer, skia.Rect.MakeWH(W, H), SAMPLING)
    touches(cv, t)
    lifts(cv, t)
    headlines(cv, t)
    endcard(cv, t)
    cv.drawPaint(skia.Paint(Shader=skia.GradientShader.MakeRadial(
        skia.Point(W / 2, H / 2), 1300, [argb(BLACK, 0), argb(BLACK, 0.3)], [0.55, 1.0])))


def size(scale):
    """Pixel size of the output; H.264 needs an even width, so a half-size preview gains a column."""
    return 2 * math.ceil(W * scale / 2), round(H * scale)


def frame(i):
    """Frame i, with the 2D motion blurred over a 180 degree shutter. The 3D layer brings its own blur."""
    w, h = size(A.scale)
    buf = np.zeros((h, w, 4), np.uint8)
    cv = skia.Surface(buf).getCanvas()
    layer = skia.Image.open(str(A.layer / f'{i:04d}.png'))
    acc = np.zeros((h, w, 3), np.float32)
    for k in range(A.samples):
        cv.save()
        cv.scale(A.scale, A.scale)
        scene(cv, i + ((k + 0.5) / A.samples - 0.5) * 0.5, layer)
        cv.restore()
        acc += buf[..., :3]
    return np.rint(acc / A.samples).astype(np.uint8)


class A:
    """Per-process assets, filled by init()."""


def strings(key):
    catalog = json.loads((ROOT / 'ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings').read_text())
    return catalog['strings'][key]['localizations'][LOCALES[A.locale]]['stringUnit']['value']


def load_captures(folder, locale):
    """Every capture as it looks on the glass, as H x W x 3 arrays of 0 to 255 values."""
    pixels = {}
    for screen in SCREENS:
        path = capture(folder, locale, screen)
        if not path.exists(): sys.exit(f'Missing capture {path}. Pass --captures, or make stand-ins with '
                                       f'--placeholders.')
        array = skia.Image.open(str(path)).toarray()[..., :3]
        if array.shape[:2] != CAPTURE[::-1]: sys.exit(f'Wrong capture size: {path}')
        pixels[screen] = on_glass(array.astype(np.float32))
    return pixels


def drawing(name, locale):
    return Strokes(ASSETS / f"{DRAWINGS[name].replace('{lang}', LOCALES[locale])}.strokes.json")


def load_card():
    """What the end card draws in A.locale."""
    A.tagline, A.small = strings('app.tagline'), strings('paywall.subtitle')
    A.mark = svg_image(ROOT / 'ios/PaeoniaApp/Resources/Assets.xcassets/PaeoniaMark.imageset/paeonia-mark.svg',
                       MARK)
    A.wordmark = wordmark()
    A.badge = svg_image(BRAND / f"app-store-{'no' if A.locale == 'no' else 'en'}.svg", 2 * BADGE)


def init(opts):
    for key, value in opts.items(): setattr(A, key, value)
    A.track = json.loads((A.layer / 'track.json').read_text())
    A.typeface = skia.Typeface.MakeFromFile(str(ASSETS / CONFIG['font']))
    panels = CONFIG['panels'][A.locale]
    A.copy = {key: panels[panel][line] for key, (panel, line) in COPY.items()}
    load_card()
    glass = load_captures(A.captures, A.locale)
    A.crops = {}
    for name in LIFTS:
        l, t, r, b = REGIONS[name].box
        A.crops[name] = image(glass[REGIONS[name].screen][t:b, l:r])
    A.strokes, A.blank = {}, {}
    for name in REPLAYS:
        l, t, r, b = REGIONS[name].box
        strokes = drawing(name, A.locale)
        A.strokes[name] = strokes
        A.blank[name] = image(inpaint(glass[REGIONS[name].screen][t:b, l:r], strokes.coverage(r - l, 3) > 0.01))


# Sound ------------------------------------------------------------------------------------------------------------

def music():
    """The film's music, which is the bars of EDIT back to back. Each jump crossfades over the 30 ms before it, so
    every downbeat keeps its attack. A 0.12 s fade in starts it and a 0.5 s fade out ends it, so the film loops
    without a click."""
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(MUSIC), '-f', 'f32le', '-ac', '2', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    track = np.frombuffer(raw, np.float32).reshape(-1, 2)
    out = np.zeros((FRAMES * SR // FPS, 2), np.float32)
    t = np.arange(len(out)) / SR
    fade = 0.03

    def ramp(x): return 0.5 - 0.5 * np.cos(np.pi * np.clip(x, 0, 1))

    start = 0.0
    for i, (bar, bars) in enumerate(EDIT):
        end = start + bars * BAR_S if bars else t[-1] + 1
        weight = (ramp((t - start + fade) / fade) if i else 1.0) * ramp((end - t) / fade)
        source = np.rint((t - start + BAR0 + (bar - 1) * BAR_S) * SR).astype(int)
        keep = (weight > 0) & (source < len(track)) & (source >= 0)
        out[keep] += track[source[keep]] * np.broadcast_to(weight, t.shape)[keep, None]
        start = end
    out *= (ramp(t / 0.12) * ramp((t[-1] - t) / 0.5))[:, None]  # the ring-out is down to -46 dB; end it at zero
    return out


def bass_pulse(audio):
    """Per frame, how hard the bass hits: 1 when quiet, up to 1.35, with a quick decay like a meter."""
    step = SR // FPS
    low = np.array([np.abs(np.fft.rfft(audio[i * step:(i + 1) * step].mean(1), 2 * step)[:6]).sum()  # under 150 Hz
                    for i in range(FRAMES)])
    for i in range(1, FRAMES): low[i] = max(low[i], 0.82 * low[i - 1])
    return list(1 + 0.35 * np.clip(low / np.percentile(low, 95), 0, 1.2))


def write_wav(audio, path):
    import wave
    mix = audio * min(1.0, 0.97 / np.abs(audio).max())
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(np.rint(mix * 32767).astype('<i2').tobytes())


def loudness(path):
    """Two-pass loudnorm to -16 LUFS: measure the mix, then apply the gain linearly so its dynamics stay intact."""
    log = subprocess.run(['ffmpeg', '-hide_banner', '-nostats', '-i', str(path), '-af',
                          'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    m = json.loads(log[log.rindex('{'):log.rindex('}') + 1])
    return (f"loudnorm=I=-16:TP=-1.5:LRA=11:measured_I={m['input_i']}:measured_TP={m['input_tp']}"
            f":measured_LRA={m['input_lra']}:measured_thresh={m['input_thresh']}:offset={m['target_offset']}"
            f":linear=true,aresample={SR}")


# Tools ------------------------------------------------------------------------------------------------------------

# Invented events of the stand-in recordings, in seconds, with their length. 02-question taps the card, the add
# photo button, a photo in the picker, the text field and send, and then swipes to the earlier day.
STAND_IN = {
    '02-question': (22, {'card tap': 2.0, 'question shown': 2.6, 'photo tap': 4.4, 'photo staged': 7.4,
                         'field tap': 8.0, 'keyboard up': 8.6, 'typing starts': 9.0, 'typing done': 13.0,
                         'send tap': 13.4, 'reveal starts': 13.9, 'today shown': 14.4, 'reveal settled': 15.6,
                         'scroll starts': 17.2, 'scroll settled': 19.0,
                         'taps': [(2.0, 0.5, 0.4), (4.4, 0.18, 0.62), (5.6, 0.3, 0.35), (8.0, 0.5, 0.8),
                                  (13.4, 0.88, 0.6)],
                         'swipes': [dict(t=17.2, x=0.5, y=0.4, to_x=0.5, to_y=0.76, seconds=0.4)]}),
    '03-ludo': (10, {'die tap': 1.0, 'die settled': 1.8, 'piece starts': 2.1, 'piece lands': 2.9,
                     'partner die starts': 5.0, 'partner piece lands': 6.6, 'taps': [(1.0, 0.5, 0.86)]}),
    '06-draw': (12, {'drawing starts': 0.5, 'drawing done': 5.5, 'celebration starts': 8.6,
                     'celebration settled': 10.0,
                     'taps': [(6.4, 0.2, 0.8), (6.8, 0.6, 0.8), (7.3, 0.4, 0.86), (7.7, 0.7, 0.86), (8.2, 0.3, 0.8)]}),
}


def placeholder(c, screen, locale):
    c.drawPaint(skia.Paint(Shader=skia.GradientShader.MakeLinear(
        [skia.Point(0, 0), skia.Point(0, CAPTURE[1])], [argb(hexc('#3a1029')), argb(hexc('#1f0716'))])))
    c.save()
    c.translate(CAPTURE[0] / 2, CAPTURE[1] / 2)
    c.rotate(-60)
    for row in range(-6, 7):
        c.drawString('PLACEHOLDER', -font(150).measureText('PLACEHOLDER') / 2, row * 420, font(150), paint(WHITE, 0.05))
    c.restore()
    c.drawString(f'{screen}  {locale}', 90, 2690, font(90), paint(WHITE, 0.85))
    c.drawString('placeholder, not a real capture', 90, 2780, font(48), paint(ACCENT))


def placeholders(folder):
    """Stand-in captures, marked as such, with each region of REGIONS where the table puts it and the real drawing on
    its canvas, and stand-in screen recordings that show their time, their last event, their taps and text at the
    app's sizes, so the whole film renders before the real captures exist."""
    A.typeface = skia.Typeface.MakeFromFile(str(ASSETS / CONFIG['font']))
    tint = [(242, 126, 178), (111, 177, 240), (242, 184, 75), (91, 185, 139), (185, 156, 242), (232, 93, 134)]
    for locale in CONFIG['panels']:
        A.locale = locale
        (folder / locale).mkdir(parents=True, exist_ok=True)
        for k, screen in enumerate(SCREENS):
            surf = skia.Surface(*CAPTURE)
            c = surf.getCanvas()
            placeholder(c, screen, locale)
            for j, (name, region) in enumerate(REGIONS.items()):
                if region.screen != screen: continue
                l, t, r, b = REGIONS[name].box
                color = tint[(j + k) % len(tint)]
                if name in DRAWINGS:
                    c.drawRRect(rrect(l, t, r, b, canvas_radius(r - l)), paint(hexc('#380f27')))
                    c.save()
                    c.translate(l, t)
                    c.clipRRect(rrect(0, 0, r - l, b - t, canvas_radius(r - l)), True)
                    strokes = drawing(name, locale)
                    c.scale((r - l) / strokes.side, (b - t) / strokes.side)
                    strokes.draw(c, 1e9)
                    c.restore()
                    continue
                c.drawRRect(rrect(l, t, r, b, region.radius), paint(color, 0.35))
                c.drawRRect(rrect(l, t, r, b, region.radius), paint(color, Style=skia.Paint.kStroke_Style,
                                                                    StrokeWidth=6))
                c.drawString(name, l + 30, t + 70, font(52), paint(WHITE))
            surf.makeImageSnapshot().save(str(capture(folder, locale, screen)), skia.kPNG)
        for screen, (seconds, events) in STAND_IN.items():
            path = capture(folder, locale, screen).with_suffix('.mp4')
            notes = {**events, 'taps': [dict(t=t, x=x, y=y) for t, x, y in events['taps']]}
            path.with_suffix('.events.json').write_text(json.dumps(notes, indent=2) + '\n')
            ff = subprocess.Popen(['ffmpeg', '-v', 'error', '-y', '-f', 'rawvideo', '-pix_fmt', 'rgba', '-s',
                                   f'{CAPTURE[0]}x{CAPTURE[1]}', '-r', str(FPS), '-i', '-', '-vf',
                                   'scale=1206:2622', '-c:v', 'libx264', '-crf', '20', '-pix_fmt', 'yuv420p',
                                   str(path)], stdin=subprocess.PIPE)
            surf = skia.Surface(*CAPTURE)
            c = surf.getCanvas()
            for f in range(seconds * FPS):
                now = f / FPS
                placeholder(c, screen, locale)
                last = max(((t, name) for name, t in events.items() if name not in ('taps', 'swipes') and t <= now),
                           default=None)
                c.drawString(f'{now:5.2f} s', 90, 900, font(220), paint(WHITE))
                if last: c.drawString(last[1], 90, 1100, font(110), paint(ACCENT))
                c.drawRect(skia.Rect.MakeXYWH(0, 1300, CAPTURE[0] * now / seconds, 40), paint(WHITE, 0.6))
                for y, points in ((1520, 32), (1700, 17), (1900, 17), (2100, 17), (2300, 17), (2500, 17)):
                    c.drawString(f'{points} pt text, as the app draws it', 90, y, font(3 * points), paint(WHITE))
                for t, x, y in events['taps']:
                    if t <= now < t + 0.3:
                        c.drawCircle(x * CAPTURE[0], y * CAPTURE[1], 80, paint(ACCENT))
                ff.stdin.write(surf.makeImageSnapshot().toarray().tobytes())
            ff.stdin.close()
            if ff.wait(): sys.exit('ffmpeg failed')
    print(f'Wrote placeholder captures and recordings for {", ".join(CONFIG["panels"])} to {folder}')


def soften(pixels, radius):
    """A box blur of `radius` pixels, run twice, so coarse search steps see a smooth difference."""
    r = int(radius)
    if r < 1: return pixels
    for axis in (0, 1, 0, 1):
        c = np.cumsum(np.pad(pixels, [(r + 1, r) if a == axis else (0, 0) for a in range(3)], mode='edge'), axis)
        pixels = (np.take(c, range(2 * r + 1, c.shape[axis]), axis) - np.take(c, range(0, c.shape[axis] - 2 * r - 1),
                                                                              axis)) / (2 * r + 1)
    return pixels


def fit(folder):
    """For each canvas in REGIONS, the box where the replayed drawing best covers the drawing in the capture.
    Starting from the table's box, it moves and scales the box while that lowers the difference between where the
    capture shows the drawing's inks and where the replay puts strokes, from coarse steps on blurred masks down to a
    quarter pixel."""
    for locale in CONFIG['panels']:
        A.locale = locale
        glass = load_captures(folder, locale)
        for name in DRAWINGS:
            strokes = drawing(name, locale)
            l, t, r, b = REGIONS[name].box
            margin = 80
            x0, y0 = max(0, l - margin), max(0, t - margin)
            region = glass[REGIONS[name].screen][y0:min(CAPTURE[1], b + margin), x0:min(CAPTURE[0], r + margin)]
            inks = {s['color'] for s in strokes.strokes}
            ink = np.max([np.clip(1 - np.abs(region - c).max(2) / 60, 0, 1) for c in inks], axis=0)
            # The search moves the drawing's middle and scales about it, so a change of size does not move it.
            ys, xs = np.nonzero(strokes.coverage(strokes.side * 4) > 0.5)
            mx, my = (xs.min() + xs.max() + 1) / 8, (ys.min() + ys.max() + 1) / 8

            def corner(guess):
                cx, cy, side = guess
                return cx - mx * side / strokes.side, cy - my * side / strokes.side

            def cost(guess, blur):
                (gl, gt), side = corner(guess), guess[2]
                buf = np.zeros(region.shape[:2] + (4,), np.uint8)
                cv = skia.Surface(buf).getCanvas()
                cv.translate(gl - x0, gt - y0)
                cv.scale(side / strokes.side, side / strokes.side)
                strokes.draw(cv, 1e9)
                return float(np.abs(soften(buf[..., 3:] / 255, blur) - soften(ink[..., None], blur)).mean())

            guess = [l + mx * (r - l) / strokes.side, t + my * (r - l) / strokes.side, float(r - l)]
            step = 32.0
            while step >= 0.25:
                blur = step / 2
                best = cost(guess, blur)
                moved = False
                for axis in range(3):
                    for sign in (-1, 1):
                        trial = guess.copy()
                        trial[axis] += sign * step
                        value = cost(trial, blur)
                        if value < best: best, guess, moved = value, trial, True
                if not moved: step /= 2
            (gl, gt), side = corner(guess), guess[2]
            print(f'{locale} {name}: ({gl:.1f}, {gt:.1f}, {gl + side:.1f}, {gt + side:.1f}), the table has '
                  f'{(l, t, r, b)}, {cost(guess, 0) * 100:.2f} % of the area differs')


def check(captures):
    """Overlays each finished replay on its PencilKit preview, checks that every headline stays readable for 1.5 s,
    that the poster frames hold still, how the question recording is cut, the order of the end card, and the cut
    music's length and bar lines."""
    ok = True
    for stem in ('widget-drawing-plane-en', 'widget-drawing-plane-nb'):
        strokes = Strokes(ASSETS / f'{stem}.strokes.json')
        reference = skia.Image.open(str(ASSETS / f'{stem}-preview.png')).toarray()[..., :3].astype(int)
        side = reference.shape[0]
        buf = np.zeros((side, side, 4), np.uint8)
        cv = skia.Surface(buf).getCanvas()
        cv.clear(argb(hexc('#380f27')))
        cv.scale(side / strokes.side, side / strokes.side)
        strokes.draw(cv, 1e9)
        inner = slice(side // 16, -side // 16)
        diff = np.abs(buf[inner, inner, :3].astype(int) - reference[inner, inner]).max(2)
        print(f'{stem}: replay vs PencilKit preview, mean difference {diff.mean():.2f} of 255, '
              f'{(diff > 64).mean() * 100:.3f} % of pixels off by more than 64')
        ok &= diff.mean() < 1 and (diff > 64).mean() < 0.001
    A.typeface = skia.Typeface.MakeFromFile(str(ASSETS / CONFIG['font']))
    settled = next(f for f in range(1, 90) if spring(f, 0.85, 10) > 0.995)
    words_up = []  # (headline, frame it rises on, frame its last word has settled, frame it leaves), every locale
    for locale, panels in CONFIG['panels'].items():
        for key, t_in, t_out in HEADLINES:
            panel, line = COPY[key]
            words, _ = layout(panels[panel][line], HEADLINE, TEXT[2] - TEXT[0], 1.08, 'left')
            up = 0 if t_in is None else t_in + (len(words) - 1) * 2.5 + settled
            words_up.append((key, t_in or 0, up, t_out))
            ok &= (t_out - up) / FPS >= 1.5
            print(f'{locale} {key}: every word fully up for {(t_out - up) / FPS:.1f} s')
    for f in POSTERS:
        moving = [name for name in LIFTS if abs(raised(name, f + 1) - raised(name, f - 1)) > 0.002]
        moving += [name for name, spec in REPLAYS.items() if spec.start <= f <= spec.end + HANDOVER]
        moving += [key for key, rise, up, t_out in words_up if rise <= f < up or t_out <= f < t_out + 30]
        moving += [screen for start, screen in SHOTS[1:] if abs(f - start) <= DISSOLVE / 2 + 1]
        moving += [screen for screen, clips in FOOTAGE.items() for clip in clips[1:]
                   if clip.start - 1 <= f <= clip.start + clip.dissolve + 1]
        print(f'poster frame {f}: ' + (f'moving: {", ".join(sorted(set(moving)))}' if moving else 'a clean hold'))
        ok &= not moving

    def least(label, frames, seconds):
        print(f'{label}: {frames / FPS:.2f} s, at least {seconds} s')
        return frames / FPS >= seconds

    for locale in CONFIG['panels']:
        ok &= check_question(locale, recording(captures, locale, '02-question'), least)
    for locale in CONFIG['panels']:
        A.locale = locale
        words = {key: len(layout(strings(string), size, TEXT[2] - TEXT[0], leading, 'center')[0])
                 for key, string, size, leading in (('tagline', 'app.tagline', TAGLINE, 1.2),
                                                    ('small', 'paywall.subtitle', SMALL, 1.3))}
        tagline_up = CARD['tagline'] + (words['tagline'] - 1) * TAGLINE_GAP + settled
        ok &= least(f'{locale} tagline fully up before the subscription line rises', CARD['small'] - tagline_up, 0.7)
        all_up = max(CARD['mark'] + settled, CARD['wordmark'] + settled, CARD['badge'] + settled, tagline_up,
                     CARD['small'] + (words['small'] - 1) * SMALL_GAP + settled)
        ok &= least(f'{locale} end card fully up before it fades', FADE - all_up, 1.0)
        # Each line of the settled end card has as much ink left of the frame's middle as right of it. The rows
        # where two lines meet are left out, since the edge of one line's ink can reach a pixel into the next.
        load_card()
        buf = np.zeros((H, W, 4), np.uint8)
        endcard(skia.Surface(buf).getCanvas(), FADE)
        tops = [*lockup().values(), H]
        for key, top, bottom in zip(lockup(), tops, tops[1:]):
            columns = np.flatnonzero((buf[round(top) + 2:round(bottom) - 2, :, 3] > 127).any(0))
            off = (columns[0] + columns[-1] + 1) / 2 - W / 2
            print(f'{locale} end card {key}: {off:+.1f} px from the middle, at most 2 px')
            ok &= abs(off) <= 2
    audio = music()
    seconds = len(audio) / SR
    print(f'music: {seconds:.3f} s for {FRAMES / FPS:.3f} s of film')
    ok &= abs(seconds - FRAMES / FPS) < 1e-6
    # At every beat after a cut, the film's strongest onset sits as far from the beat as the track's does at the
    # same beat, so the cut keeps the track's grid.
    raw = subprocess.run(['ffmpeg', '-v', 'error', '-i', str(MUSIC), '-f', 'f32le', '-ac', '1', '-ar', str(SR), '-'],
                         capture_output=True, check=True).stdout
    film, track = onsets(audio.mean(1)), onsets(np.frombuffer(raw, np.float32))

    def offset(flux, seconds, before=0.1):
        """Seconds from `seconds` to the strongest onset from `before` ahead of it to 0.1 s after it."""
        k, ahead = round(seconds * 200), round(before * 200)
        return (np.argmax(flux[k - ahead:k + 21]) - ahead) / 200

    start = 0.0
    for bar, bars in EDIT:
        source = BAR0 + (bar - 1) * BAR_S
        # A cut's own downbeat is searched from its crossfade on, since the bar before it comes from elsewhere.
        shifts = [offset(film, start + b / 2, 0.03 if b == 0 else 0.1) - offset(track, source + b / 2,
                                                                                  0.03 if b == 0 else 0.1)
                  for b in range(0 if start else 1, 4)]
        print(f'film {start:5.2f} s = track bar {bar} at {source:.3f} s: onsets of its beats moved by '
              f'{", ".join(f"{1000 * d:+.0f}" for d in shifts)} ms')
        ok &= max(abs(d) for d in shifts) <= 0.01
        start += (bars or 0) * BAR_S
    return ok


def check_question(locale, rec, least):
    """The question recording's cut: the question holds at full size until the tap on the text field, the picker is
    cut out by a dissolve from the photo tap to the photo in the composer, the typing is quick, the conversation
    comes in on a beat, today's answers hold before the swipe and the earlier day holds until the change to Ludo, and
    only the card, photo, field and send taps show a dot."""
    screen, ok = '02-question', True
    clips = FOOTAGE[screen]
    if missing := {'photo tap', 'send tap', 'reveal settled', 'scroll settled'} - set(rec.events):
        sys.exit(f'{rec.path} has no {", ".join(sorted(missing))}')

    def reached(event):
        """The first film frame that shows the event, or a moment after it."""
        return next(f for f in showing(screen) if footage_time(screen, f, rec) >= rec.events[event] - 1e-6)

    ok &= least(f'{locale} question at full size', reached('field tap') - reached('question shown'), 1.2)
    k = next(i for i, clip in enumerate(clips) if clip.dissolve)
    held = clip_time(screen, k - 1, clips[k].start, rec)
    lands = (clips[k].event == 'photo staged' and abs(held - rec.events['photo tap']) < 0.5 / FPS
             and 6 <= clips[k].dissolve <= 8)
    print(f'{locale} picker cut: a {clips[k].dissolve}-frame dissolve from {held:.2f} s to {clips[k].event} at '
          f'{rec.events[clips[k].event]:.2f} s, from the photo tap at {rec.events["photo tap"]:.2f} s')
    ok &= lands
    typing = (reached('typing done') - reached('typing starts')) / FPS
    print(f'{locale} typing: {typing:.2f} s, at most 1.5 s')
    ok &= typing <= 1.5
    reveal = reached('today shown')
    print(f'{locale} conversation comes in at {reveal / FPS:.2f} s, on a beat no later than 9.5 s')
    ok &= reveal % BEAT == 0 and reveal <= 9.5 * FPS
    ok &= least(f"{locale} today's answers still before the swipe",
                reached('scroll starts') - reached('reveal settled'), 1.4)
    ludo = next(start for start, name in SHOTS if name == '03-ludo')
    ok &= least(f'{locale} earlier day still before the change to Ludo', ludo - reached('scroll settled'), 1.0)
    dots = sorted(s for _, s, _, _ in tap_frames(screen, rec))
    wanted = sorted(rec.events[name] for name in ('card tap', 'photo tap', 'field tap', 'send tap'))
    print(f'{locale} tap dots at {", ".join(f"{s:.2f}" for s in dots)} s of the recording, only the card, photo, field '
          f'and send taps')
    ok &= len(dots) == len(wanted) and all(abs(a - b) < 1e-6 for a, b in zip(dots, wanted))
    return ok


def onsets(mono):
    """Spectral flux every 5 ms, which is how much the log spectrum rose since the step before, summed over bands."""
    hop, n = SR // 200, 1024
    frames = np.lib.stride_tricks.sliding_window_view(np.pad(mono, (n // 2, n // 2)), n)[::hop] * np.hanning(n)
    spectrum = np.log1p(np.abs(np.fft.rfft(frames, axis=1)))
    return np.concatenate([[0], np.maximum(np.diff(spectrum, axis=0), 0).sum(1)])


def main():
    parser = argparse.ArgumentParser(prog='showcase.py')
    parser.add_argument('--preview', action='store_true', help='half size, from the preview 3D layer')
    parser.add_argument('--still', type=int, nargs='+', metavar='FRAME')
    parser.add_argument('--locale', default='en-US', choices=list(CONFIG['panels']))
    parser.add_argument('--captures', default=str(CAPTURES))
    parser.add_argument('--placeholders', metavar='DIR')
    parser.add_argument('--fit', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.placeholders: return placeholders(Path(args.placeholders))
    if args.fit: return fit(args.captures)
    if not MUSIC.exists(): sys.exit(f'Download the music to {MUSIC} first; see the top of this file.')
    if args.check: sys.exit(0 if check(args.captures) else 'check failed')
    frames = args.still or range(FRAMES)
    folder = layer(args.locale, args.preview)
    missing = [i for i in frames if not (folder / f'{i:04d}.png').exists()]
    if missing: sys.exit(f'{len(missing)} frames of the 3D layer are missing from {folder}; run phone3d.py first.')
    recordings = {screen: recording(args.captures, args.locale, screen) for screen in FOOTAGE}
    taps = {screen: tap_frames(screen, rec) for screen, rec in recordings.items()}
    swipes = {screen: swipe_frames(screen, rec) for screen, rec in recordings.items()}
    audio = music()
    opts = dict(layer=folder, scale=0.5 if args.preview else 1.0, samples=3 if args.preview else 6,
                locale=args.locale, captures=args.captures, pulse=bass_pulse(audio), taps=taps, swipes=swipes)
    w, h = size(opts['scale'])
    with Pool(max(1, (os.cpu_count() or 2) - 1), initializer=init, initargs=(opts,)) as pool:
        if args.still:
            stills = OUT / 'stills'
            stills.mkdir(parents=True, exist_ok=True)
            shots = pool.map(frame, args.still)
            cols = min(10, len(shots))
            sw, sh = w // 2, h // 2
            sheet = np.zeros((math.ceil(len(shots) / cols) * sh, cols * sw, 3), np.uint8)
            for k, (i, shot) in enumerate(zip(args.still, shots)):
                still = skia.Image.fromarray(np.dstack([shot, np.full((h, w, 1), 255, np.uint8)]), RGBA)
                still.save(str(stills / f'{args.locale}-{i:04d}.png'), skia.kPNG)
                small = still.resize(sw, sh, SAMPLING).toarray()[..., :3]
                sheet[k // cols * sh:(k // cols + 1) * sh, k % cols * sw:(k % cols + 1) * sw] = small
            contact = stills / f'{args.locale}-contact.png'
            skia.Image.fromarray(np.dstack([sheet, np.full(sheet.shape[:2] + (1,), 255, np.uint8)]), RGBA).save(
                str(contact), skia.kPNG)
            print(f'Wrote {len(shots)} stills and {contact.name} to {stills}')
            return
        OUT.mkdir(parents=True, exist_ok=True)
        wav = OUT / f'audio-{args.locale}.wav'
        write_wav(audio, wav)
        video = OUT / f'paeonia-showcase-{args.locale}{"-preview" if args.preview else ""}.mp4'
        # App Store Connect's app preview specification: H.264 High@4.0 at a constant 11 Mbps (Apple asks for 10 to
        # 12), AAC 256 kbps at 48 kHz, -16 LUFS.
        quality = ['-preset', 'medium', '-crf', '20'] if args.preview else [
            '-preset', 'slow', '-profile:v', 'high', '-level:v', '4.0', '-b:v', '11M', '-minrate', '11M',
            '-maxrate', '11M', '-bufsize', '11M', '-x264-params', 'nal-hrd=cbr', '-g', '60']
        ff = subprocess.Popen(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'rawvideo',
                               '-pix_fmt', 'rgb24', '-s', f'{w}x{h}', '-r', str(FPS), '-i', '-', '-i', str(wav),
                               '-map', '0:v', '-map', '1:a', '-c:v', 'libx264', *quality,
                               '-vf', 'scale=out_color_matrix=bt709:out_range=tv,format=yuv420p', '-r', str(FPS),
                               '-color_primaries', 'bt709', '-color_trc', 'bt709', '-colorspace', 'bt709',
                               '-af', loudness(wav), '-c:a', 'aac', '-b:a', '256k', '-ar', str(SR), '-ac', '2',
                               '-shortest', '-movflags', '+faststart', str(video)], stdin=subprocess.PIPE)
        for i, data in enumerate(pool.imap(frame, frames, chunksize=4)):
            ff.stdin.write(data.tobytes())
            if i % 120 == 0: print(f'frame {i}/{FRAMES}', flush=True)
        ff.stdin.close()
        if ff.wait(): sys.exit('ffmpeg failed')
        print(f'Wrote {video}')


if __name__ == '__main__':
    main()
