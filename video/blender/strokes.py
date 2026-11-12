"""Replays the strokes of a drawing that `scripts/app-store-drawing.swift --strokes` exported, with Skia."""
import json
import math

import numpy as np
import skia


def paint(color=(255, 255, 255), alpha=1.0, **kw):
    return skia.Paint(Color=skia.ColorSetARGB(round(255 * max(0.0, min(1.0, alpha))), *color), AntiAlias=True, **kw)


class Strokes:
    """A drawing exported by `scripts/app-store-drawing.swift --strokes`, replayed in canvas points. Progress runs in
    units where a pen stroke takes a unit per PEN points, a bucket fill FILL units and the lift between two strokes
    GAP units, so the hand moves at one speed however the replay is timed."""
    PEN, FILL, GAP = 6.0, 3.0, 1.0

    def __init__(self, path):
        data = json.loads(path.read_text())
        self.side = data['canvasSide']
        self.strokes = []
        for s in data['strokes']:
            color = tuple(int(s['ink'][i:i + 2], 16) for i in (1, 3, 5))
            if 'fill' in s:
                outline = skia.Path()
                for ring in s['fill']:
                    outline.addPoly([skia.Point(ring[i], ring[i + 1]) for i in range(0, len(ring), 2)], True)
                xs = [ring[i] for ring in s['fill'] for i in range(0, len(ring), 2)]
                ys = [ring[i] for ring in s['fill'] for i in range(1, len(ring), 2)]
                self.strokes.append(dict(color=color, fill=outline, units=self.FILL,
                                         centre=((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2),
                                         reach=math.hypot(max(xs) - min(xs), max(ys) - min(ys)) / 2))
            else:
                points = np.array([p[:2] for p in s['points']])
                lengths = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(points, axis=0).T))])
                width = 2 * s['points'][0][3] - 4  # PencilKit draws a monoline point of size s as a line 2s - 4 wide
                self.strokes.append(dict(color=color, points=points, lengths=lengths, width=width,
                                         units=max(1.0, lengths[-1] / self.PEN)))

    def parts(self, order):
        """Stroke indices of the widget drawing's parts: the dashes of the route, the heart, the plane and the
        words, in the order given. Its strokes come in that drawing order, and the heart's outline is the stroke
        before the first bucket fill."""
        heart = next(i for i, s in enumerate(self.strokes) if 'fill' in s) - 1
        ranges = {'route': range(0, heart), 'heart': range(heart, heart + 2), 'plane': range(heart + 2, heart + 11),
                  'words': range(heart + 11, len(self.strokes))}
        return [i for part in order for i in ranges[part]]

    def total(self, indices):
        return sum(self.strokes[i]['units'] + self.GAP for i in indices) - self.GAP

    def draw(self, cv, u, indices=None, alpha=1.0):
        """The strokes in `indices` (all of them by default) as far as progress u. A pen stroke grows along its path,
        a fill spreads from its middle."""
        for i in indices if indices is not None else range(len(self.strokes)):
            s = self.strokes[i]
            if u <= 0: return
            x = min(1.0, u / s['units'])
            u -= s['units'] + self.GAP
            if 'fill' in s:
                cv.save()
                cv.clipPath(s['fill'], skia.ClipOp.kIntersect, True)
                spread = 0.15 + 0.85 * (1 - (1 - x) ** 3)
                cv.drawCircle(*s['centre'], spread * s['reach'] * 1.05, paint(s['color'], alpha))
                cv.restore()
                continue
            points, lengths = s['points'], s['lengths']
            reach = x * lengths[-1]
            n = int(np.searchsorted(lengths, reach, side='right'))
            path = skia.Path()
            path.moveTo(*points[0])
            for p in points[1:n]: path.lineTo(*p)
            if n < len(points):
                k = (reach - lengths[n - 1]) / max(1e-6, lengths[n] - lengths[n - 1])
                path.lineTo(*(points[n - 1] + (points[n] - points[n - 1]) * k))
            if len(points) == 1 or reach < 1e-3: path.lineTo(points[0][0] + 0.01, points[0][1])
            cv.drawPath(path, paint(s['color'], alpha, Style=skia.Paint.kStroke_Style, StrokeWidth=s['width'],
                                    StrokeCap=skia.Paint.kRound_Cap, StrokeJoin=skia.Paint.kRound_Join))

    def coverage(self, side, extra=0.0):
        """Where the finished drawing has ink, as a side x side array of 0 to 1, grown by `extra` pixels."""
        buf = np.zeros((side, side, 4), np.uint8)
        cv = skia.Surface(buf).getCanvas()
        cv.scale(side / self.side, side / self.side)
        self.draw(cv, 1e9)
        if extra:
            grow = extra * self.side / side
            for s in self.strokes:
                if 'fill' in s:
                    cv.drawPath(s['fill'], paint(Style=skia.Paint.kStroke_Style, StrokeWidth=2 * grow))
                else:
                    path = skia.Path()
                    path.addPoly([skia.Point(*p) for p in s['points']], False)
                    cv.drawPath(path, paint(Style=skia.Paint.kStroke_Style, StrokeWidth=s['width'] + 2 * grow,
                                            StrokeCap=skia.Paint.kRound_Cap, StrokeJoin=skia.Paint.kRound_Join))
        return buf[..., 3] / 255


def inpaint(pixels, unknown):
    """The pixels with the unknown ones filled from their surroundings, coarse to fine (pull-push), so a canvas keeps
    its own background gradient where the strokes were."""
    weight = (~unknown).astype(np.float32)[..., None]
    levels = [(pixels * weight, weight)]
    while min(levels[-1][1].shape[:2]) > 2:
        p, w = levels[-1]
        h2, w2 = p.shape[0] // 2 * 2, p.shape[1] // 2 * 2
        levels.append(tuple(a[:h2:2, :w2:2] + a[1:h2:2, :w2:2] + a[:h2:2, 1:w2:2] + a[1:h2:2, 1:w2:2]
                            for a in (p[:h2, :w2], w[:h2, :w2])))
    p, w = levels[-1]
    filled = p / np.maximum(w, 1e-6)
    for p, w in reversed(levels[:-1]):
        up = np.repeat(np.repeat(filled, 2, 0), 2, 1)
        up = np.pad(up, ((0, p.shape[0] - up.shape[0]), (0, p.shape[1] - up.shape[1]), (0, 0)), mode='edge')
        known = np.clip(w, 0, 1)
        filled = known * p / np.maximum(w, 1e-6) + (1 - known) * up
    return np.where(unknown[..., None], filled, pixels)
