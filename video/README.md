# Paeonia film

`blender/` renders Paeonia's 29.5-second promotional film at 886 x 1920 and 30 fps, in English (`en-US`) and Norwegian (`no`). The size is App Store Connect's app preview size for every iPhone from 5.8 to 6.9 inches, and the same file works for social media.

Two scripts make each film:

- `blender/phone3d.py` renders the phones in Blender on a transparent background, with the captures and screen recordings on their glass. It also writes `track.json`, which holds the on-screen corners of every region in `REGIONS`, and of both phones' screens, on every frame.
- `blender/showcase.py` draws the rest with skia-python: background, headlines, the parts of the screen that lift off the glass, the replayed widget drawing, the touch dots of the recordings' taps and swipes and the end card. It cuts the music to the bar lines and writes the mp4.

`blender/timeline.py` holds what both scripts share: the frame grid, the scene bars, the main phone's screens, how each screen recording is cut, and the region table.

## Before the first render

You need Blender 5.3 at `/Applications/Blender.app`, `uv` and `ffmpeg`.

1. Download the music to `video/blender/music.mp3`. It is "Day Dreamin' with U" by Michael Ramir C. from Mixkit, under the Mixkit Stock Music Free License: `https://assets.mixkit.co/music/988/988.mp3`. The license does not let us redistribute the file on its own, so git ignores it.
2. Put the captures in `ios/ASConnectScreenshots/<version>/raw/<locale>/iPhone-<screen>.png`, as `scripts/capture-app-store-screenshots.py` writes them. The film uses the stills `01-widget` and `05-memories` at 1320 x 2868.
3. Put the screen recordings of the daily question, Ludo and Draw & Guess beside them as `iPhone-02-question.mp4`, `iPhone-03-ludo.mp4` and `iPhone-06-draw.mp4`, at a constant 30 fps in portrait. `scripts/capture-app-store-screenshots.py --record` makes them and their events files on an iPhone simulator of any size. `phone3d.py` scales them to the 1320 x 2868 capture box. Each has a `.events.json` beside it, such as `iPhone-03-ludo.events.json`, with the seconds of named moments from the mp4's first frame and a `taps` list of `{"t", "x", "y"}`, where x and y are fractions of the screen. A `swipes` list holds each swipe as `{"t", "x", "y", "to_x", "to_y", "seconds"}`, with the seconds the finger drags. The first and last tap also count as the events `first tap` and `last tap`. A missing recording or an event the cut needs stops both scripts.

`FOOTAGE` in `timeline.py` cuts each recording as clips. Each clip names the film frame it starts on and the event it puts there, so the table holds no numbers of its own for a locale. The events each recording must carry are listed beside its cut in `timeline.py`, and a missing event stops both scripts. The question recording comes from `scripts/app-store-content --question-film` and then `scripts/capture-app-store-screenshots.py --record --screens 02-question`. Three stretches of it never play, because the app shows the list in two places for a moment while the conversation opens, and the simulator can stop drawing for a quarter of a second after the petals start. Tune the numbers to new footage and run `--check`.

Without real captures, make marked stand-ins and pass their folder to both scripts with `--captures`. It also writes stand-in recordings with invented events, which show their own time, their last event, their taps and lines of text at 32 and 17 pt, the sizes of the question and of a line under a photo:

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

## Render only what changed

Both scripts keep what they made, so a change costs only the frames it touches. Do not render the whole 3D layer again for a change that leaves most of it alone.

- `phone3d.py` writes one PNG per film frame to `video/blender/out/layer-<locale>/`. With `--stills` or `--screen` it renders only the frames you name and leaves every other PNG in that folder as it is. A full render takes about 18 minutes per language, and a part takes about 1 second per frame.
- `showcase.py` always composites the whole film from that folder, in about 2 minutes per language.

| What changed | What to run |
|---|---|
| Headlines, tap dots, lifted cards, the end card, the music cut | Only `showcase.py`. No Blender frames change. |
| A new take of a recording, or the cut of one recording in `FOOTAGE` | `phone3d.py` with `--screen` and that recording, then `showcase.py`. |
| A new still capture | `phone3d.py` with `--screen` and that capture, then `showcase.py`. |
| The camera table or a phone's poses | `phone3d.py` with `--stills` and the range of frames between the keys you changed and their neighbours, then `showcase.py`. |
| The phone model, the lights, the frame size, or the start of a scene that moves every scene after it | A full `phone3d.py` render. |

```bash
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P video/blender/phone3d.py -- --locale en-US --screen 02-question
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup -P video/blender/phone3d.py -- --locale en-US --stills 84-397
uv run video/blender/showcase.py --locale en-US
```

`--screen` covers the frames that screen is on a phone, with the dissolves into and out of it. Run each command once per language. Afterwards, look at the film's frames on both sides of the range you rendered, since a change that reached further than you thought shows there as a jump.

To look at single frames, run `phone3d.py` with `--stills 0,90,150` and `showcase.py` with `--still 0 90 150`. `phone3d.py` makes the glass textures of a recording only for the frames it renders, in `footage/` in the layer folder. The second writes the frames and a contact sheet to `video/blender/out/stills/`. A sheet of every 15th frame shows the pacing of the whole film:

```bash
uv run video/blender/showcase.py --preview --still $(seq 0 15 884)
```

## When the captures change

Every part of a capture that lifts off the glass or gets strokes drawn on it is a box in `REGIONS` in `blender/timeline.py`, in capture pixels. Check them against new captures and render the 3D layer again, because `track.json` follows the boxes.

The `widget canvas` is the square the widget drawing's 320-point canvas fills in the capture. The replayed strokes hand over to the capture's own pixels at the end, so this box must match to the pixel. `--fit` measures it from the captures and prints boxes to copy into the table:

```bash
uv run video/blender/showcase.py --fit
```

`--check` compares each replayed drawing with its PencilKit preview and enforces the film's timing rules (headline and hold durations, the poster frames at 2.0 s and 5.0 s, the end card's order, and the music cut on the beat grid). It reads the question recording, so pass `--captures` when you render with stand-ins.

## The drawing

The film replays the strokes of the widget drawing in `scripts/assets/app-store/`. The `.strokes.json` files beside its `.pkdrawing` payloads come from the payloads themselves. After a payload changes, export them again:

```bash
swift scripts/app-store-drawing.swift --strokes scripts/assets/app-store/widget-drawing-plane-*.pkdrawing
```

## The website

paeonia.no plays the film in the page's language, in a section below the hero. After a full-quality render of both languages, make the website's 3 MB copies and their posters in `marketing/static/film/`:

```bash
scripts/marketing-film
```

In a worktree, where the renders are missing, point `PAEONIA_FILMS` at the folder that holds them, such as the main checkout's `video/blender/out`.

## Other assets

`brand/` holds Apple's App Store badges. The headlines, colours and font come from `scripts/assets/app-store/paeonia-3d.json`, the same file as the App Store screenshots. The tagline comes from `ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings`. The peony mark is the app's `PaeoniaMark` image.
