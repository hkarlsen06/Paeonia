# Paeonia film

`blender/` renders Paeonia's 29.5-second promotional film at 886 x 1920 and 30 fps, in English (`en-US`) and Norwegian (`no`). The size is App Store Connect's app preview size for every iPhone from 5.8 to 6.9 inches, and the same file works for social media.

Two scripts make each film:

- `blender/phone3d.py` renders the phones in Blender on a transparent background, with the captures and screen recordings on their glass. It also writes `track.json`, which holds the on-screen corners of every region in `REGIONS`, and of both phones' screens, on every frame.
- `blender/showcase.py` draws the rest with skia-python: background, headlines, the parts of the screen that lift off the glass, the replayed widget drawing, the touch dots of the recordings' taps and the end card. It cuts the music to the bar lines and writes the mp4.

`blender/timeline.py` holds what both scripts share: the frame grid, the scene bars, the main phone's screens, how each screen recording is cut, and the region table.

## Before the first render

You need Blender 5.3 at `/Applications/Blender.app`, `uv` and `ffmpeg`.

1. Download the music to `video/blender/music.mp3`. It is "Day Dreamin' with U" by Michael Ramir C. from Mixkit, under the Mixkit Stock Music Free License: `https://assets.mixkit.co/music/988/988.mp3`. The license does not let us redistribute the file on its own, so git ignores it.
2. Put the captures in `ios/ASConnectScreenshots/<version>/raw/<locale>/iPhone-<screen>.png`, as `scripts/capture-app-store-screenshots.py` writes them. The film uses the stills `01-widget`, `02-chat`, `04-home` and `05-memories` at 1320 x 2868.
3. Put the screen recordings of Ludo and Draw & Guess beside them as `iPhone-03-ludo.mp4` and `iPhone-06-draw.mp4`, at a constant 30 fps in portrait. `scripts/capture-app-store-screenshots.py --record` makes them and their events files on an iPhone simulator of any size. `phone3d.py` scales them to the 1320 x 2868 capture box. Each has a `.events.json` beside it, such as `iPhone-03-ludo.events.json`, with the seconds of named moments from the mp4's first frame and a `taps` list of `{"t", "x", "y"}`, where x and y are fractions of the screen. The first and last tap also count as the events `first tap` and `last tap`. A missing recording or an event the cut needs stops both scripts.

`FOOTAGE` in `timeline.py` cuts each recording as a list of clips. A clip names the film frame it starts on and the event it puts at that frame, so the table holds no numbers of its own for a locale. A clip plays at its speed, or with `fit`, at the speed that brings a later event to the next clip's start. The Ludo clips need `die tap`, `piece starts` and `partner die starts`. The Draw & Guess clips need `drawing done` and at least one tap.

Without real captures, make marked stand-ins and pass their folder to both scripts with `--captures`. It also writes stand-in recordings with invented events, which show their own time, their last event and their taps:

```bash
uv run video/blender/showcase.py --placeholders video/blender/out/placeholders
```

## Render

Run these from the repository root. A preview is half size with fewer samples.

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P video/blender/phone3d.py -- --preview --locale en-US
uv run video/blender/showcase.py --preview --locale en-US
```

For the full-quality film, leave out `--preview`:

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P video/blender/phone3d.py -- --locale en-US
uv run video/blender/showcase.py --locale en-US
```

Repeat with `--locale no` for Norwegian. The film is `video/blender/out/paeonia-showcase-<locale>.mp4`, or `-preview.mp4`. The full-quality file is H.264 High@4.0 at a constant 11 Mbps with 256 kbps AAC at 48 kHz and -16 LUFS, which is Apple's app preview specification.

On this Mac the 3D layer takes about 0.2 s a frame as a preview, so 3 minutes for the 885 frames. At full quality it takes from 1 s a frame when the Mac is otherwise idle to 2.4 s while other builds and simulators run, so 15 to 35 minutes. `showcase.py` takes about 20 s for a preview and 2 minutes at full quality.

To look at single frames, run `phone3d.py` with `--stills 0,90,150` and `showcase.py` with `--still 0 90 150`. `phone3d.py` makes the glass textures of a recording only for the frames it renders, in `footage/` in the layer folder. The second writes the frames and a contact sheet to `video/blender/out/stills/`. A sheet of every 15th frame shows the pacing of the whole film:

```bash
uv run video/blender/showcase.py --preview --still $(seq 0 15 884)
```

## When the captures change

Every part of a capture that lifts off the glass or gets strokes drawn on it is a box in `REGIONS` in `blender/timeline.py`, in capture pixels. Check them against new captures and render the 3D layer again, because `track.json` follows the boxes. A box may hold one value per locale when a translation moves it.

The `widget canvas` is the square the widget drawing's 320-point canvas fills in the capture. The replayed strokes hand over to the capture's own pixels at the end, so this box must match to the pixel. `--fit` measures it from the captures and prints boxes to copy into the table:

```bash
uv run video/blender/showcase.py --fit
```

`--check` compares each replayed drawing with its PencilKit preview. It also checks these timing rules:

- Every headline stays fully up for at least 1.5 s.
- Nothing moves at the poster frames 3.0 s and 5.0 s.
- The envelope stays fully up for at least 1.2 s, and both chat answers stay up together for at least 2.5 s.
- On the end card, the subscription line rises only after the tagline has been fully up for 0.7 s, and everything is fully up for at least 1 s before the fade.
- The cut music is 29.5 s long with every cut on the track's beat grid.

## The drawing

The film replays the strokes of the widget drawing in `scripts/assets/app-store/`. The `.strokes.json` files beside its `.pkdrawing` payloads come from the payloads themselves. After a payload changes, export them again:

```bash
swift scripts/app-store-drawing.swift --strokes scripts/assets/app-store/widget-drawing-plane-*.pkdrawing
```

## Other assets

`brand/` holds Apple's App Store badges. The headlines, colours and font come from `scripts/assets/app-store/paeonia-3d.json`, the same file as the App Store screenshots. The tagline and the subscription line come from `ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings`. The peony mark is the app's `PaeoniaMark` image.
