"""Check generated Paeonia illustrations and import them into the iOS asset catalog.

Run with a Python that has Pillow, outside the repository:

    python3 -m venv /tmp/paeonia-art-venv && /tmp/paeonia-art-venv/bin/pip install pillow
    /tmp/paeonia-art-venv/bin/python -I art_asset.py check a.png b.png ...
    /tmp/paeonia-art-venv/bin/python -I art_asset.py import a.png GameHubThing 240 [--opaque] [--folder GameHub]
    /tmp/paeonia-art-venv/bin/python -I art_asset.py zones plate.png ...
    /tmp/paeonia-art-venv/bin/python -I art_asset.py selftest

`check` reports each file's size, alpha, corners, edge fringe and the object's
bounds, and writes a preview on the plum background to /tmp/paeonia-art-preview.png.
`zones` checks a 1024 x 1536 hub card painting against docs/games/hub-artwork.md:
the chip band's brightest point and how dark the text zone gets.
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


def zones(paths):
    """The chip band (pixels 0 to 160) must stay at or below 0.09 relative luminance at its
    brightest (99th percentile, so a stray pixel does not count), which keeps the green chip
    and the blush badge at 3:1. The text zone should be deep plum by pixel 1000."""
    failed = False
    for path in paths:
        image = Image.open(path).convert("RGB")
        if image.size != (1024, 1536):
            print(f"FAIL {os.path.basename(path)}: {image.size[0]}x{image.size[1]}, expected 1024x1536")
            failed = True
            continue
        band = sorted(luminance(p) for p in image.crop((0, 0, 1024, 160)).resize((256, 40)).getdata())
        brightest = band[int(len(band) * 0.99)]
        bottom = image.crop((0, 1000, 1024, 1536)).resize((1, 1)).getpixel((0, 0))
        ok = brightest <= 0.09
        failed |= not ok
        print(
            f"{'ok  ' if ok else 'FAIL'} {os.path.basename(path)}: chip band brightest {brightest:.3f} "
            f"(max 0.09), text zone below 1000 averages #{bottom[0]:02X}{bottom[1]:02X}{bottom[2]:02X}"
        )
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
    # An opaque painting needs no alpha, and JPEG is about a tenth of the PNG's size.
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
    if args[:1] == ["zones"] and len(args) > 1:
        sys.exit(zones(args[1:]))
    if args == ["selftest"]:
        sys.exit(selftest())
    print(__doc__)
    sys.exit(2)
