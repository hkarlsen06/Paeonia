"""Check generated Paeonia illustrations and import them into the iOS asset catalog.

Run with a Python that has Pillow, outside the repository:

    python3 -m venv /tmp/paeonia-art-venv && /tmp/paeonia-art-venv/bin/pip install pillow
    /tmp/paeonia-art-venv/bin/python -I art_asset.py check a.png b.png ...
    /tmp/paeonia-art-venv/bin/python -I art_asset.py import a.png GameHubThing 240 [--opaque] [--folder GameHub]
    /tmp/paeonia-art-venv/bin/python -I art_asset.py backdrop /tmp/paeonia-art/backdrop.png
    /tmp/paeonia-art-venv/bin/python -I art_asset.py text /tmp/paeonia-art/backdrop.png
    /tmp/paeonia-art-venv/bin/python -I art_asset.py selftest

`check` reports each file's size, alpha, corners, edge fringe and the object's
bounds, and writes a preview on the plum background to /tmp/paeonia-art-preview.png.
`backdrop` renders the hub card backdrop that GameHubBackdrop draws in code.
`text` simulates the hub card's shadow and blur on a 1024 x 1536 render of it and checks
each line of the card's text against the contrast docs/games/hub-artwork.md asks for.
`import` trims the transparent margin, scales the longest side down to the given
pixel count (three times the largest size the app shows it at), and writes a
universal imageset. With --opaque it keeps the whole image and writes a JPEG. Run `import` from the repository root.
"""

import json
import os
import sys

from PIL import Image

PLUM = (0x38, 0x0F, 0x27, 255)
CATALOG = "ios/PaeoniaApp/Resources/Assets.xcassets"
PREVIEW = "/tmp/paeonia-art-preview.png"


def object_bounds(image):
    """The box around every pixel that is more than faintly opaque."""
    return image.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()


def fringe_share(image):
    """Share of the half-transparent edge pixels that are pale grey or white, which is
    what a background the cutout did not fully remove leaves behind."""
    edge = pale = 0
    for r, g, b, a in image.getdata():
        if 16 < a < 240:
            edge += 1
            if min(r, g, b) > 200 and max(r, g, b) - min(r, g, b) < 24:
                pale += 1
    return pale / edge if edge else 0.0


def check(paths):
    tiles = []
    failed = False
    for path in paths:
        image = Image.open(path).convert("RGBA")
        width, height = image.size
        corners = [image.getpixel(p)[3] for p in ((0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1))]
        bounds = object_bounds(image)
        fringe = fringe_share(image)
        ok = max(corners) == 0 and bounds is not None and fringe < 0.15
        failed |= not ok
        print(
            f"{'ok  ' if ok else 'FAIL'} {os.path.basename(path)}: {width}x{height}, "
            f"corner alpha {max(corners)}, fringe {fringe:.0%}, object box {bounds}"
        )
        thumb = image.crop(bounds) if bounds else image
        thumb.thumbnail((240, 240))
        tile = Image.new("RGBA", (260, 260), PLUM)
        tile.alpha_composite(thumb, ((260 - thumb.width) // 2, (260 - thumb.height) // 2))
        tiles.append(tile)
    sheet = Image.new("RGBA", (260 * len(tiles), 260), PLUM)
    for index, tile in enumerate(tiles):
        sheet.paste(tile, (260 * index, 0))
    sheet.save(PREVIEW)
    print(f"preview: {PREVIEW}")
    return 1 if failed else 0


def luminance(rgb):
    """Relative luminance of an sRGB color with 0 to 255 channels."""
    def linear(channel):
        channel /= 255
        return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
    r, g, b = rgb
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)


# The card frame's Gaussian blur and shadow under the text. Keep in step with
# GameHubTextScrim in GameHubCardFrame.swift and the blur in GameHubArtworkParts.swift.
BLUR_STRENGTH = 1.0
SHADOW_AT_NAME = 0.25
SHADOW_AT_BOTTOM = 0.5
PLUM = (42, 11, 30)
BLUSH = (251, 243, 247)
# Text lines at the narrowest card (335 pt): the band each line can fall in, in points below
# the 720 px text line (with or without the chip row above the name), the text color, its
# opacity, and the contrast it needs.
TEXT_LINES = [
    ("name", 4, 85, BLUSH, 1.0, 3.0),
    ("status", 49, 111, BLUSH, 0.74, 4.5),
    ("your turn", 49, 111, BLUSH, 1.0, 4.5),
    ("link", 159, 231, BLUSH, 0.74, 4.5),
]
CARD_HEIGHT_BELOW_TEXT = 260
# Where the card's text starts, in canvas pixels. Keep in step with
# GameHubArtworkLayout.sceneShare.
TEXT_TOP = 720


def mix(a, b, t):
    return tuple(x * (1 - t) + y * t for x, y in zip(a, b))


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


def text(paths):
    """Simulate the frame's shadow and blur on a 1024 x 1536 card backdrop and check every
    text line against the contrast it needs, at the narrowest card (335 pt). Each line's
    worst point is its 0.5th percentile, so a stray pixel does not count."""
    from PIL import ImageFilter

    px_per_pt = 1024 / 335
    top, bottom = TEXT_TOP, TEXT_TOP + CARD_HEIGHT_BELOW_TEXT * px_per_pt
    failed = False
    for path in paths:
        image = Image.open(path).convert("RGB")
        if image.size != (1024, 1536):
            print(f"FAIL {os.path.basename(path)}: {image.size[0]}x{image.size[1]}, expected 1024x1536")
            failed = True
            continue
        small = image.resize((256, 384))
        blurred = small.filter(ImageFilter.GaussianBlur(15))
        results = []
        for label, start, end, color, alpha, need in TEXT_LINES:
            ratios = []
            # The backdrop is checked at a quarter size, so pixel rows are divided by 4.
            for y in range(int((top + start * px_per_pt) / 4), int((top + end * px_per_pt) / 4)):
                depth = min(max((y * 4 - top) / (bottom - top), 0), 1)
                shadow = SHADOW_AT_NAME + (SHADOW_AT_BOTTOM - SHADOW_AT_NAME) * depth
                for x in range(15, 241):
                    under = mix(small.getpixel((x, y)), blurred.getpixel((x, y)), BLUR_STRENGTH)
                    under = mix(under, PLUM, shadow)
                    ratios.append(contrast(mix(under, color, alpha), under))
            ratios.sort()
            worst = ratios[int(len(ratios) * 0.005)]
            ok = worst >= need
            failed |= not ok
            results.append(f"{label} {worst:.1f}{'' if ok else ' LOW'}")
        print(f"{'ok  ' if 'LOW' not in ' '.join(results) else 'FAIL'} {os.path.basename(path)}: " + ", ".join(results))
    return 1 if failed else 0


def import_asset(path, name, longest, opaque=False, folder="GameHub"):
    image = Image.open(path).convert("RGBA")
    if not opaque:
        image = image.crop(object_bounds(image))
    scale = longest / max(image.size)
    if scale < 1:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)
    if opaque:
        image = image.convert("RGB")
    group = os.path.join(CATALOG, folder)
    if not os.path.exists(os.path.join(group, "Contents.json")):
        os.makedirs(group, exist_ok=True)
        with open(os.path.join(group, "Contents.json"), "w") as file:
            json.dump({"info": {"author": "xcode", "version": 1}}, file, indent=2)
    imageset = os.path.join(group, f"{name}.imageset")
    os.makedirs(imageset, exist_ok=True)
    # An opaque picture needs no alpha, and JPEG is about a tenth of the PNG's size.
    filename = f"{name}.jpg" if opaque else f"{name}.png"
    if opaque:
        image.save(os.path.join(imageset, filename), quality=88, optimize=True, progressive=True)
    else:
        image.save(os.path.join(imageset, filename), optimize=True)
    contents = {"images": [{"filename": filename, "idiom": "universal"}], "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(imageset, "Contents.json"), "w") as file:
        json.dump(contents, file, indent=2)
    size_kb = os.path.getsize(os.path.join(imageset, filename)) // 1024
    print(f"{name}: {image.size[0]}x{image.size[1]} px, aspect {image.size[0] / image.size[1]:.3f}, {size_kb} KB")
    return 0

# GameHubBackdrop in GameHubArtworkParts.swift, in canvas pixels. Keep in step with it.
BACKDROP_SKY = [(0, PLUM), (0.46, (0x38, 0x0F, 0x27)), (1, PLUM)]
BACKDROP_HILLS = [(190, 880, 660), (834, 880, 660)]
BACKDROP_SEAM = (482, 542)
BACKDROP_SHADE = (0x4F, 0x20, 0x3A)
BACKDROP_SHADE_STOPS = [(240, 0), (480, 0.25), (760, 0.6), (1536, 1)]


def ramp(value, stops):
    """The value of a gradient with `stops` [(position, value)] at `value`."""
    for (start, low), (end, high) in zip(stops, stops[1:]):
        if value <= end:
            t = min(max((value - start) / (end - start), 0), 1)
            return mix(low, high, t) if isinstance(low, tuple) else low + (high - low) * t
    return stops[-1][1]


def backdrop(path):
    """Render the hub card backdrop at 1024 x 1536, for `text` and for mockups."""
    pink, lavender = (0xF2, 0x7E, 0xB2), (0xB9, 0x9C, 0xF2)
    image = Image.new("RGB", (1024, 1536))
    for y in range(1536):
        sky = ramp(y / 1536, BACKDROP_SKY)
        shade = ramp(y, BACKDROP_SHADE_STOPS)
        for x in range(1024):
            inside = any((x - cx) ** 2 + (y - cy) ** 2 <= r * r for cx, cy, r in BACKDROP_HILLS)
            if inside:
                hill = mix(pink, lavender, ramp(x, [(BACKDROP_SEAM[0], 0), (BACKDROP_SEAM[1], 1)]))
                color = mix(hill, BACKDROP_SHADE, shade)
            else:
                color = sky
            image.putpixel((x, y), tuple(round(c) for c in color))
    image.save(path)
    print(f"wrote {path}")
    return 0


def selftest():
    """A clean cutout passes and one with a white halo fails."""
    clean = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    for x in range(20, 44):
        for y in range(20, 44):
            clean.putpixel((x, y), (242, 126, 178, 255))
    halo = clean.copy()
    for x in range(18, 46):
        for y in (18, 19, 44, 45):
            halo.putpixel((x, y), (250, 250, 250, 120))
    assert object_bounds(clean) == (20, 20, 44, 44)
    assert fringe_share(clean) == 0
    assert fringe_share(halo) > 0.9
    assert abs(luminance((255, 255, 255)) - 1) < 1e-9 and luminance((0, 0, 0)) == 0
    assert 0.05 < luminance((0x6A, 0x2E, 0x52)) < 0.06
    print("selftest ok")
    return 0


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["check"] and len(args) > 1:
        sys.exit(check(args[1:]))
    if args[:1] == ["import"] and len(args) >= 4:
        folder = args[args.index("--folder") + 1] if "--folder" in args else "GameHub"
        sys.exit(import_asset(args[1], args[2], int(args[3]), "--opaque" in args, folder))
    if args[:1] == ["text"] and len(args) > 1:
        sys.exit(text(args[1:]))
    if args[:1] == ["backdrop"] and len(args) == 2:
        sys.exit(backdrop(args[1]))
    if args == ["selftest"]:
        sys.exit(selftest())
    print(__doc__)
    sys.exit(2)
