#!/usr/bin/env python3
"""Capture App Store PNGs from the real app on the test couple's seeded account.

Run from the repository root after scripts/local-backend, scripts/app-store-content
and scripts/sim-sign-in, with the simulator signed in as Hjalmar:

    python3 scripts/capture-app-store-screenshots.py --locale en-US --ids ids.json \\
        --agent-device "<agent-device command with its --platform, --udid, --config and --session flags>" \\
        [--screens 01-widget,02-question,...] [--simulator "Paeonia Screenshots"] [--output DIR]

--ids is the JSON line scripts/app-store-content prints last. The screens open
through Paeonia's deep links. simctl openurl asks "Open in Paeonia?" first, so
the links go through agent-device's `open <app> <url>`, which does not.

01-widget is the Home Screen. The script lays it out with Paeonia only: the
large drawing widget on top, the streak and countdown widgets below it, and the
Paeonia app alone in the dock. Every other app moves to the App Library. It
writes SpringBoard's IconState.plist while the simulator is shut down, so the
first run reboots the simulator. Set the dark plum Home Screen wallpaper by hand
once per simulator: add the image from scripts/app-store-wallpaper.mjs with
`xcrun simctl addmedia`, then in Photos use Share > Use as Wallpaper > Customize
Home Screen > Gradient. A photo wallpaper renders black on the simulator, so the
gradient picks up its plum colour instead. Before the capture, the script turns
on large app icons, which hide the labels under the widgets, through SpringBoard's
edit mode (Edit > Customize > Large app icons). iOS keeps the icon size with the
wallpaper, so set the wallpaper first. It also turns off the Search button above
the dock, which is Settings > Home Screen & App Library > Search > Show on Home
Screen, by writing SBHomeScreenShowsSearchAffordance in com.apple.springboard.

The screens are captured in the order of SCREENS, all from one seeding, so the
drawing's time and the streak match everywhere. Each locale needs a fresh local
backend (`scripts/local-backend --reseed`), since today's answers can't change.
Seed with `scripts/app-store-content --partner-answer-only`, so only Elena has
answered today's question, and sign in after seeding: an app that saw the
drawing before the seeding moved its time keeps the old time. On the first
launch, open Elena's gift and tap Later and Not now through the welcome. Leave
notifications off, because an app allowed to show badges puts a number on its
Home Screen icon. Home is captured while today's question still waits for
Hjalmar. Then add Hjalmar's answer and the chat with `scripts/app-store-content
--chat-only` and capture the rest:

    ... --screens 01-widget,04-home,05-memories
    scripts/app-store-content --locale <en|nb> --chat-only
    ... --screens 02-chat,03-ludo,06-draw

06-draw is Draw & Guess, where Hjalmar guesses the drawing Elena sent. The
capture waits until the drawing has played back in full and the 30-second
speed bonus line has gone, so every locale shows the same screen. Then it taps
the first GUESS_LETTERS letters of the word from --ids, so the shot shows a
guess under way.

The script sets the simulator's language for the locale (rebooting when it
changes it) and the status bar to 9:41 with full bars and battery, and checks
that every capture is 1320 x 2868, the 6.9-inch App Store size. For the screens
in SPOTLIGHTS it saves the spotlit element's accessibility frame next to the
capture, as <capture>.spotlight.json, which scripts/render-3d-screenshots.mjs
reads for a phone with a spotlight.
"""

import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import struct
import subprocess
import tempfile
import time
import uuid


ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "no.paeonia.app"
SIZE = (1320, 2868)
LANGUAGES = {"en-US": ("en-US", "en_US"), "no": ("nb-NO", "nb_NO")}
# The button of the system "Open in Paeonia?" prompt, which a new simulator shows for deep links.
OPEN_BUTTON = {"en-US": "Open", "no": "Åpne"}
# SpringBoard's labels on the way to the icon size: the Edit button of the Home Screen's edit mode,
# its Customize item, and the size button, which names the size it switches to.
EDIT_BUTTON = {"en-US": "Edit", "no": "Rediger"}
CUSTOMIZE_ITEM = {"en-US": "Customize", "no": "Tilpass"}
LARGE_ICONS_BUTTON = {"en-US": "Large app icons", "no": "Store appsymboler"}
REGULAR_ICONS_BUTTON = {"en-US": "Regular app icons", "no": "Vanlige appsymboler"}
# Seconds for a cold launch to reach Home with the live data loaded.
LAUNCH_SECONDS = 12
# Mean difference per colour channel, out of 255, below which two captures count as the same screen.
DUPLICATE_THRESHOLD = 6
# Each screen's deep link and the seconds to wait for its live data, or the Ludo
# table, to load, or the Draw & Guess drawing to play back. They are captured in
# this order. Home comes before the chat, so it still invites Hjalmar to answer.
# Ludo comes after Home, because Elena's presence at the table puts a "here now"
# card at the top of Home.
# 01-widget opens the app so it syncs the widgets, then goes to the Home Screen.
SCREENS = {
    "01-widget": ("paeonia://home", 10),
    "04-home": ("paeonia://home", 10),
    "05-memories": ("paeonia://memories", 8),
    "02-chat": ("paeonia://daily/chat?questionId={question_id}", 8),
    "03-ludo": ("paeonia://games/ludo", 25),
    "06-draw": ("paeonia://games/draw-and-guess", 35),
}
# How many letters of the Draw & Guess word 06-draw types before the capture.
GUESS_LETTERS = 2
# Screens whose capture gets a spotlight in the render, and the --ids key of the text that the
# spotlit element's accessibility label contains. The countdown card's label holds its title.
SPOTLIGHTS = {"04-home": "countdown_title"}
# The Home Screen of 01-widget, in grid order: (widget kind, size). The large drawing fills
# the top four rows and the two small widgets the last two.
HOME_SCREEN = [("PaeoniaWidget", "large"), ("PaeoniaHomeStreakWidget", "small"),
               ("PaeoniaHomeCountdownWidget", "small")]
WIDGET_EXTENSION = "no.paeonia.app.widget"


def run(*args, **kwargs):
    return subprocess.run(args, check=True, cwd=ROOT, text=True, **kwargs)


def simctl(*args, **kwargs):
    return run("xcrun", "simctl", *args, **kwargs)


def device(name):
    inventory = json.loads(simctl("list", "devices", "available", "--json", capture_output=True).stdout)
    for runtime, devices in inventory["devices"].items():
        for candidate in devices:
            if ".iOS-" in runtime and name in (candidate["name"], candidate["udid"]):
                return candidate
    raise SystemExit(f"No available simulator named {name}.")


def shut_down(udid):
    """Shuts the simulator down and waits, because simctl returns while it is still shutting down."""
    simctl("shutdown", udid)
    while device(udid)["state"] != "Shutdown":
        time.sleep(1)


def home_screen_widget(kind, size):
    ids = (str(uuid.uuid5(uuid.NAMESPACE_URL, f"paeonia-app-store:{kind}:{size}:{part}")).upper() for part in "du")
    return {"widgetIdentifier": kind, "elementType": "widget", "containerBundleIdentifier": BUNDLE_ID,
            "bundleIdentifier": WIDGET_EXTENSION, "displayIdentifier": next(ids), "uniqueIdentifier": next(ids),
            "gridSize": size, "iconType": "custom", "allowsSuggestions": False, "allowsExternalSuggestions": False}


def apps_in(icons):
    """The bundle ids in a Home Screen icon list, including the ones inside folders."""
    if isinstance(icons, str):
        return [icons]
    if isinstance(icons, list):
        return [app for icon in icons for app in apps_in(icon)]
    return apps_in(icons.get("iconLists", []))


def lay_out_home_screen(udid):
    """Gives the Home Screen one page of Paeonia widgets and Paeonia alone in the dock. Reboots when it changes it."""
    path = Path.home() / f"Library/Developer/CoreSimulator/Devices/{udid}/data/Library/SpringBoard/IconState.plist"
    state = plistlib.loads(path.read_bytes())
    page = [home_screen_widget(kind, size) for kind, size in HOME_SCREEN]
    if state["iconLists"] == [page] and state["buttonBar"] == [BUNDLE_ID]:
        return
    shut_down(udid)
    state = plistlib.loads(path.read_bytes())  # SpringBoard saves it again while it shuts down.
    state["ignored"] = sorted({*state.get("ignored", []), *apps_in([*state["iconLists"], state["buttonBar"]])}
                              - {BUNDLE_ID})
    state["iconLists"] = [page]
    state["listUniqueIdentifiers"] = state["listUniqueIdentifiers"][:1]
    state["buttonBar"] = [BUNDLE_ID]
    path.write_bytes(plistlib.dumps(state, fmt=plistlib.FMT_BINARY))
    simctl("bootstatus", udid, "-b", stdout=subprocess.DEVNULL)


def prepare(udid, locale):
    """Boots the simulator in the locale's language with the App Store status bar and Home Screen."""
    languages, region = LANGUAGES[locale]
    simctl("bootstatus", udid, "-b", stdout=subprocess.DEVNULL)
    lay_out_home_screen(udid)
    current = simctl("spawn", udid, "defaults", "read", "-g", "AppleLanguages", capture_output=True).stdout
    if f'"{languages}"' not in current and languages not in current.split():
        simctl("spawn", udid, "defaults", "write", "-g", "AppleLanguages", "-array", languages)
        simctl("spawn", udid, "defaults", "write", "-g", "AppleLocale", region)
        shut_down(udid)
        simctl("bootstatus", udid, "-b", stdout=subprocess.DEVNULL)
    # Settings > Home Screen & App Library > Search > Show on Home Screen. SpringBoard applies it at once.
    simctl("spawn", udid, "defaults", "write", "com.apple.springboard", "SBHomeScreenShowsSearchAffordance",
           "-bool", "NO")
    simctl("status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi",
           "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
           "--batteryState", "discharging", "--batteryLevel", "100")
    # Location stays off, so iOS shows no prompt and no location arrow in the status bar.
    simctl("privacy", udid, "revoke", "location", BUNDLE_ID)
    # The Ludo board shows how to zoom until this phone has zoomed it once, and the first
    # Draw & Guess replay shows how to speed it up.
    simctl("spawn", udid, "defaults", "write", BUNDLE_ID, "paeonia.games.ludo.hasZoomedBoard.v2", "-bool", "YES")
    simctl("spawn", udid, "defaults", "write", BUNDLE_ID, "games.drawAndGuess.holdHintShown", "-bool", "YES")


def use_large_icons(agent_device, locale):
    """Gives the Home Screen large app icons, which drop the labels under the widgets.

    iOS keeps the icon size with the wallpaper, not in a defaults key, so this goes through
    SpringBoard: edit mode, Edit > Customize, then the size button, unless it already offers
    regular icons. A long press on the dock beside Paeonia starts edit mode, because the
    widgets fill the page. A tap above the Customize sheet closes it and ends edit mode.
    """
    def device(*args, **kwargs):
        return run(*agent_device[:1], *args, *agent_device[1:], **kwargs)

    device("open", "com.apple.springboard", stdout=subprocess.DEVNULL)
    device("longpress", "80", "905", "1500", stdout=subprocess.DEVNULL)
    time.sleep(2)
    device("press", f'label="{EDIT_BUTTON[locale]}"', stdout=subprocess.DEVNULL)
    time.sleep(1.5)
    device("press", f'label="{CUSTOMIZE_ITEM[locale]}"', stdout=subprocess.DEVNULL)
    time.sleep(1.5)
    tree = device("snapshot", "-i", capture_output=True).stdout
    if f'"{LARGE_ICONS_BUTTON[locale]}"' in tree:
        device("press", f'label="{LARGE_ICONS_BUTTON[locale]}"', stdout=subprocess.DEVNULL)
        time.sleep(1.5)
    elif f'"{REGULAR_ICONS_BUTTON[locale]}"' not in tree:
        raise SystemExit("The Home Screen's Customize sheet did not open, so the icons may still be small.")
    device("press", "220", "450", stdout=subprocess.DEVNULL)
    time.sleep(1.5)


def show_partner_at_table(subject):
    """Marks Elena present at the Ludo table for the next minute, so the screen shows both players."""
    env = {key: value for key, value in os.environ.items()
           if key not in ("CONVEX_SELF_HOSTED_URL", "CONVEX_SELF_HOSTED_ADMIN_KEY", "CONVEX_DEPLOYMENT")}
    env["PATH"] = f"/opt/homebrew/opt/node@22/bin:{env['PATH']}"
    subprocess.run(["npx", "convex", "run", "games:set_game_presence", '{"p_kind":"ludo","p_present":true}',
                    "--identity", json.dumps({"subject": subject}), "--codegen", "disable", "--typecheck", "disable"],
                   check=True, cwd=ROOT / "backend", env=env, stdout=subprocess.DEVNULL)


def thumbnail(path):
    """The capture as a 33 x 72 grid of RGB values, read from a BMP that sips writes."""
    with tempfile.TemporaryDirectory() as folder:
        bmp = Path(folder) / "thumb.bmp"
        run("sips", "-z", "72", "33", "-s", "format", "bmp", str(path), "--out", str(bmp), stdout=subprocess.DEVNULL)
        data = bmp.read_bytes()
    offset, width, height, bits = (struct.unpack_from("<I", data, 10)[0], *struct.unpack_from("<ii", data, 18),
                                   struct.unpack_from("<H", data, 28)[0])
    step, row = bits // 8, (width * bits // 8 + 3) // 4 * 4
    return [data[offset + y * row + x * step + c] for y in range(abs(height)) for x in range(width) for c in range(3)]


def assert_distinct(path):
    """Fails when the capture looks like another capture of the same locale, such as a screen that never opened."""
    mine = thumbnail(path)
    for other in sorted(path.parent.glob("iPhone-*.png")):
        if other == path:
            continue
        difference = sum(abs(a - b) for a, b in zip(mine, thumbnail(other))) / len(mine)
        if difference < DUPLICATE_THRESHOLD:
            raise SystemExit(f"{path.name} looks like {other.name} (mean difference {difference:.1f} of 255), "
                             "so the screen probably did not open. Check the simulator and capture it again.")


def capture(udid, path):
    simctl("io", udid, "screenshot", "--type", "png", str(path), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    header = path.read_bytes()[:24]
    size = struct.unpack(">II", header[16:24])
    if header[:8] != b"\x89PNG\r\n\x1a\n" or size != SIZE:
        raise SystemExit(f"{path.name} is {size}, not a {SIZE[0]} x {SIZE[1]} PNG")
    assert_distinct(path)


def snapshot_nodes(agent_device):
    """The accessibility tree as a list of nodes, the app first, with frames in points."""
    tree = run(*agent_device[:1], "snapshot", "-i", "--json", *agent_device[1:], capture_output=True).stdout
    return json.loads(tree)["data"]["nodes"]


def start_guess(agent_device, word):
    """Taps letter tiles until the answer starts with the first GUESS_LETTERS letters of word.

    An answer slot is labelled "<Letter> <n>, <letter or empty>" and a tile "<Letter> <letter>", in
    the app's language. A rerun finds the letters already typed and only adds the missing ones.
    """
    while True:
        nodes = snapshot_nodes(agent_device)
        labels = [node.get("label") or "" for node in nodes]
        typed = sum(1 for label in labels if re.fullmatch(r"\S+ \d+, \S", label))
        if typed >= GUESS_LETTERS:
            return
        letter = word[typed].upper()
        tiles = [node for node in nodes if re.fullmatch(rf"\S+ {re.escape(letter)}", node.get("label") or "")]
        if not tiles:
            raise SystemExit(f"No letter tile {letter} on the Draw & Guess screen.")
        rect = tiles[0]["rect"]
        run(*agent_device[:1], "press", str(round(rect["x"] + rect["width"] / 2)),
            str(round(rect["y"] + rect["height"] / 2)), *agent_device[1:], stdout=subprocess.DEVNULL)
        time.sleep(1.5)


def save_spotlight(agent_device, text, path):
    """Saves the frame of the one element whose label contains text, in capture pixels, next to the capture.

    The renderer reads it from <capture>.spotlight.json, so the spotlight follows the app's layout.
    """
    nodes = snapshot_nodes(agent_device)
    matches = [node for node in nodes if text in (node.get("label") or "")]
    if len(matches) != 1:
        raise SystemExit(f"Found {len(matches)} elements labelled with {text!r} on {path.name}, not 1.")
    scale = SIZE[0] / nodes[0]["rect"]["width"]  # The first node is the app, as wide as the screen.
    frame = {key: round(matches[0]["rect"][key] * scale) for key in ("x", "y", "width", "height")}
    path.with_suffix(".spotlight.json").write_text(json.dumps(frame) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locale", choices=LANGUAGES, required=True)
    parser.add_argument("--ids", type=Path, required=True, help="the JSON line scripts/app-store-content printed")
    parser.add_argument("--agent-device", required=True, help="agent-device command prefix pinned to the simulator")
    parser.add_argument("--screens", default=",".join(SCREENS))
    parser.add_argument("--simulator", default="Paeonia Screenshots")
    parser.add_argument("--output", type=Path, default=ROOT / "ios/ASConnectScreenshots/trial-1/raw")
    args = parser.parse_args()
    ids = json.loads(args.ids.read_text().strip().splitlines()[-1])
    requested = set(args.screens.split(","))
    if unknown := requested - set(SCREENS):
        raise SystemExit(f"Unknown screens: {', '.join(sorted(unknown))}")
    screens = [screen for screen in SCREENS if screen in requested]

    udid = device(args.simulator)["udid"]
    prepare(udid, args.locale)
    folder = args.output / args.locale
    folder.mkdir(parents=True, exist_ok=True)
    agent_device = shlex.split(args.agent_device)
    if "01-widget" in screens:
        use_large_icons(agent_device, args.locale)
    for screen in screens:
        url, wait = SCREENS[screen]
        # Every screen starts from a fresh launch. A deep link opens beneath a full-screen
        # cover, such as the reveal, so a cover left from an earlier screen or run would
        # hide it. Terminating fails when the app is not running, which is fine.
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], stderr=subprocess.DEVNULL)
        if url is not None:
            # Launched through agent-device, so the link below opens without "Open in Paeonia?".
            run(*agent_device[:1], "open", BUNDLE_ID, *agent_device[1:], stdout=subprocess.DEVNULL)
            time.sleep(LAUNCH_SECONDS)
            if screen == "03-ludo":
                show_partner_at_table(ids["partner_clerk_subject"])
            run(*agent_device[:1], "open", BUNDLE_ID, re.sub(r"\{(\w+)\}", lambda m: ids[m.group(1)], url),
                *agent_device[1:], stdout=subprocess.DEVNULL)
            time.sleep(1)
            tree = run(*agent_device[:1], "snapshot", "-i", *agent_device[1:], capture_output=True).stdout
            if "[alert]" in tree:
                run(*agent_device[:1], "click", f'label="{OPEN_BUTTON[args.locale]}"', *agent_device[1:],
                    stdout=subprocess.DEVNULL)
        time.sleep(wait)
        if screen == "01-widget":
            # The second press goes to the first page, where the widgets are. Apps installed
            # since the layout, such as agent-device's runner, land on a later page.
            for _ in range(2):
                run(*agent_device[:1], "home", *agent_device[1:], stdout=subprocess.DEVNULL)
                time.sleep(3)
            time.sleep(3)
        if screen == "06-draw":
            start_guess(agent_device, ids["guess_word"])
        capture(udid, folder / f"iPhone-{screen}.png")
        if screen in SPOTLIGHTS:
            save_spotlight(agent_device, ids[SPOTLIGHTS[screen]], folder / f"iPhone-{screen}.png")
        print(f"Captured {args.locale}/iPhone-{screen}.png", flush=True)


if __name__ == "__main__":
    main()
