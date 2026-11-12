#!/usr/bin/env python3
"""Capture App Store PNGs from the real app on the test couple's seeded account.

Run from the repository root after scripts/local-backend, scripts/app-store-content
and scripts/sim-sign-in, with the simulator signed in as Hjalmar:

    python3 scripts/capture-app-store-screenshots.py --locale en-US --ids ids.json \\
        --agent-device "<agent-device command with its --platform, --udid, --config and --session flags>" \\
        [--screens 01-widget,02-question,...] [--simulator "Paeonia Screenshots"] [--output DIR]

The simulator is an iPhone 17 Pro Max or an iPad Pro 13-inch, and FAMILIES says
what differs between the two. Captures are named <family>-<screen>.png, such as
iPad-04-home.png.

--ids is the JSON line scripts/app-store-content prints last. The screens open
through Paeonia's deep links. simctl openurl asks "Open in Paeonia?" first, so
the links go through agent-device's `open <app> <url>`, which does not.

01-widget is the Home Screen. The script lays it out with Paeonia only: the
large drawing widget on top, the other widgets of the family's home_screen
beside and below it, and the Paeonia app alone in the dock. Every other app
moves to the App Library. It
writes SpringBoard's IconState.plist while the simulator is shut down, so the
first run reboots the simulator. agent-device may install its runner again after
that reboot, and the runner then takes a second page, which shows page dots on
01-widget. Remove the runner from the Home Screen (long press, Remove App,
Remove from Home Screen) and capture 01-widget again. Set the dark plum Home
Screen wallpaper by hand once per simulator: add the image from
scripts/app-store-wallpaper.mjs with `xcrun simctl addmedia`, then in Photos use Share > Use as Wallpaper > Customize
Home Screen > Gradient. A photo wallpaper renders black on the simulator, so the
gradient picks up its plum colour instead. Before the capture, the script turns
on large app icons, which hide the labels under the widgets. On an iPhone it goes
through SpringBoard's edit mode (Edit > Customize > Large app icons), and iOS keeps
the icon size with the wallpaper, so set the wallpaper first. On an iPad it writes
the default behind Settings > Home Screen & App Library > Use Large App Icons, and
turns off the App Library and the recent apps in the dock the same way. It also
turns off the Search button above the dock, which is Settings > Home Screen & App
Library > Search > Show on Home Screen.

The simulator is outside the shared pool that the ios-agent xcrun and xcodebuild
wrappers on this Mac allow, and agent-device's runner builds through them, so a
run needs the explicitly authorized, temporary exception that root AGENTS.md
describes. After each reboot the runner builds again in the shared Xcode queue,
so the first agent-device command can time out while other builds run.

The screens are captured in the order of SCREENS, all from one seeding, so the
drawing's time and the streak match everywhere. Each locale needs a fresh local
backend (`scripts/local-backend --reseed`), since today's answers can't change.
Seed with `scripts/app-store-content --partner-answer-only`, so only Elena has
answered today's question, and sign in after seeding: an app that saw the
drawing before the seeding moved its time keeps the old time. On the first
launch, deny location, open Elena's gift and tap Later and Not now through the
welcome. Then clear Home the way a person would: Not now on the location card,
the close button on Things to try together and on When will you meet next.
Leave notifications off, because an app allowed to show badges puts a number on
its Home Screen icon. Home is captured while today's question still waits for
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
that every capture has the family's size: 1320 x 2868, the 6.9-inch App Store
size, or 2064 x 2752, the 13-inch iPad size. An iPad shows today's date beside
the time. For the screens
in SPOTLIGHTS it saves the spotlit element's accessibility frame next to the
capture, as <capture>.spotlight.json, which scripts/render-3d-screenshots.mjs
reads for a device with a spotlight. It hides the Dynamic Island, which
SpringBoard otherwise draws as a black pill over screens such as the Ludo table.

--record films 03-ludo and 06-draw for the promotional film in video/ instead:

    ... --record --simulator "$SIM" --screens 03-ludo,06-draw

It writes <family>-<screen>.mp4, the whole screen at a constant 30 fps in
H.264, and <family>-<screen>.events.json, the times of what happens in it in
seconds from the mp4's first frame, with "taps" as {t, x, y} and x and y as
fractions of the screen. The script finds the times in the frames: where the
screen starts moving after each action it sends, and where it stops. It prints
the longest run of repeated frames inside each motion, since a busy Mac makes
the simulator stutter; record again when ios-agent status shows builds. A pause
in the app, such as Elena's die resting before her pawn moves, repeats frames
too. A
recording runs on any iPhone simulator, such as a shared one taken with
scripts/lock and opened with device_open for --agent-device. It skips the Home
Screen steps and the size check, but still sets the language, which reboots
the simulator when it changes it, because the status bar shows 9:41 only in
English. The script records through agent-device, which keeps touches out of
the video.

03-ludo flicks Hjalmar's die (a tap on the die does nothing), taps the pawn at
LUDO_PAWNS[0], and after a 6 flicks again and taps the other pawn. Then it makes
Elena's move through the backend, as Elena, so her die rolls and her pawn hops
on screen. The pawn points are the seeded position's, so each take of 03-ludo
needs a fresh seeding. 06-draw starts recording on Home, opens the game, waits
DRAW_PLAYBACK_SECONDS for Elena's drawing to play back to its last stroke, taps
the whole word, and keeps the reveal until it settles. It uses up the round, so
seed again before another take. Stop the app before you seed again: an app
signed in as Hjalmar on the new backend starts a Draw & Guess game with his
turn, and scripts/app-store-content then refuses. The script prints where it
left each raw recording.
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
from typing import NamedTuple
import uuid


ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "no.paeonia.app"
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
    "01-widget": ("paeonia://us", 10),
    "04-home": ("paeonia://us", 10),
    "05-memories": ("paeonia://memories", 8),
    "02-chat": ("paeonia://daily/chat?questionId={question_id}", 8),
    "03-ludo": ("paeonia://games/ludo", 25),
    "06-draw": ("paeonia://games/draw-and-guess", 35),
}
# How many letters of the Draw & Guess word 06-draw types before the capture.
GUESS_LETTERS = 2
# The screens --record films.
RECORDINGS = ("03-ludo", "06-draw")
# Where Hjalmar's die rests and his two pawns stand in the seeded Ludo position, as fractions of
# the screen, which the camera keeps on iPhones of the same shape. The pawn in front comes first.
LUDO_DIE = (0.457, 0.605)
LUDO_PAWNS = [(0.522, 0.575), (0.217, 0.555)]
# Frames the die takes to hop to the next player's tray, LudoSceneStyle.trayHopDuration.
TRAY_HOP_FRAMES = round(0.42 * 30)
# Elena's moves to try, as (die, pawn), until the server allows one. A 6 would give her another roll.
PARTNER_MOVES = [(die, pawn) for die in (4, 5, 3, 2, 1) for pawn in (0, 1)]
# Seconds Elena's snail takes to play back from the moment the Draw & Guess link opens.
DRAW_PLAYBACK_SECONDS = 17
# A recording's frame rate, the seconds it keeps before the first action and after the last motion,
# and the share of the screen, at a sixth of its size, that must change by more than MOTION_LEVEL
# of 255 for a frame to count as moving. MOTION_GAP frames without motion end a motion.
RECORD_FPS = 30
LEAD_SECONDS = 1.5
TAIL_SECONDS = 3
MOTION_LEVEL = 10
MOTION_PIXELS = 15
MOTION_GAP = 9
# The Draw & Guess canvas inside its border and above the speed bonus line, and the answer slots with the
# letter tiles, as (x, y, width, height) in fractions of the screen.
DRAW_CANVAS = (0.06, 0.19, 0.88, 0.40)
DRAW_TILES = (0, 0.62, 1, 0.28)
# Frames between two letter taps at the least, changed pixels in DRAW_TILES that mean a tile flies to its
# slot, changed pixels in DRAW_CANVAS that mean the screen changed rather than a stroke grew, the most
# that the empty canvas appearing changes (see first_stroke), and the still
# frames that end the reveal, which pauses for up to 0.6 s between its steps.
TAP_FRAMES = 6
TILE_PIXELS = 150
SCREEN_CHANGE_PIXELS = 1000
CANVAS_PIXELS = 8000
CELEBRATION_GAP = 30
# Screens whose capture gets a spotlight in the render, and the --ids key of the text that the
# spotlit element's accessibility label contains. The countdown card's label holds its title.
SPOTLIGHTS = {"04-home": "countdown_title"}
WIDGET_EXTENSION = "no.paeonia.app.widget"


class Family(NamedTuple):
    """What differs between an iPhone and an iPad simulator.

    size is the capture size, which is also the App Store size. home_screen is the Home Screen
    of 01-widget in grid order, as (widget kind, size). springboard holds the SpringBoard defaults
    prepare() writes, which SpringBoard applies at once. edit_mode is where an iPhone gets large
    icons, which iOS keeps with the wallpaper rather than in a default: the point of the long press
    on the dock beside Paeonia that starts edit mode, since the widgets fill the page, and the tap
    above the Customize sheet that closes it. An iPad has a default for it instead.
    """
    size: tuple
    home_screen: list
    springboard: dict
    edit_mode: tuple | None


# Settings > Home Screen & App Library > Search > Show on Home Screen.
NO_SEARCH = {"SBHomeScreenShowsSearchAffordance": False}
# SpringBoard applies it at once.
ISLAND_HIDDEN = {"SBSuppressDynamicIslandCompletely": True}
FAMILIES = {
    # The large drawing fills the top four rows and the two small widgets the last two.
    "iPhone": Family((1320, 2868), [("PaeoniaWidget", "large"), ("PaeoniaHomeStreakWidget", "small"),
                                    ("PaeoniaHomeCountdownWidget", "small")],
                     NO_SEARCH, ((80, 905), (220, 450))),
    # Each of Paeonia's five Home Screen widgets once. They fill the top two rows and half the third;
    # filling more of a 13-inch page would repeat a widget. The defaults are Use Large App Icons and
    # the two Dock switches in Settings > Home Screen & App Library, so Paeonia is alone in the dock.
    "iPad": Family((2064, 2752), [("PaeoniaWidget", "large"), ("PaeoniaHomeStreakWidget", "small"),
                                  ("PaeoniaHomeCountdownWidget", "small"), ("PaeoniaHomeDaysTogetherWidget", "medium"),
                                  ("PaeoniaHomeDailyQuestionWidget", "medium")],
                   {**NO_SEARCH, "SBHomeLargeIcons": True, "SBAppLibraryInDockEnabled": False,
                    "SBRecentsEnabled": False}, None),
}


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


def lay_out_home_screen(udid, home_screen):
    """Gives the Home Screen one page of Paeonia widgets and Paeonia alone in the dock. Reboots when it changes it."""
    path = Path.home() / f"Library/Developer/CoreSimulator/Devices/{udid}/data/Library/SpringBoard/IconState.plist"
    state = plistlib.loads(path.read_bytes())
    page = [home_screen_widget(kind, size) for kind, size in home_screen]
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


def prepare(udid, locale, family, home_screen):
    """Boots the simulator in the locale's language with the App Store status bar, and Home Screen when asked."""
    languages, region = LANGUAGES[locale]
    simctl("bootstatus", udid, "-b", stdout=subprocess.DEVNULL)
    if home_screen:
        lay_out_home_screen(udid, family.home_screen)
    current = simctl("spawn", udid, "defaults", "read", "-g", "AppleLanguages", capture_output=True).stdout
    if f'"{languages}"' not in current and languages not in current.split():
        simctl("spawn", udid, "defaults", "write", "-g", "AppleLanguages", "-array", languages)
        simctl("spawn", udid, "defaults", "write", "-g", "AppleLocale", region)
        shut_down(udid)
        simctl("bootstatus", udid, "-b", stdout=subprocess.DEVNULL)
    springboard = {**family.springboard, **ISLAND_HIDDEN} if home_screen else ISLAND_HIDDEN
    for key, value in springboard.items():
        simctl("spawn", udid, "defaults", "write", "com.apple.springboard", key, "-bool", "YES" if value else "NO")
    # An iPad shows the date beside the time. An ISO --time from an earlier override would keep its own
    # date, with a wrong weekday, until the override is cleared.
    simctl("status_bar", udid, "clear")
    simctl("status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi",
           "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
           "--batteryState", "discharging", "--batteryLevel", "100")
    # Location stays off, so iOS shows no prompt and no location arrow in the status bar.
    simctl("privacy", udid, "revoke", "location", BUNDLE_ID)
    # The Ludo board shows how to zoom until this phone has zoomed it once, and the first
    # Draw & Guess replay shows how to speed it up.
    simctl("spawn", udid, "defaults", "write", BUNDLE_ID, "paeonia.games.ludo.hasZoomedBoard.v2", "-bool", "YES")
    simctl("spawn", udid, "defaults", "write", BUNDLE_ID, "games.drawAndGuess.holdHintShown", "-bool", "YES")
    # agent-device drives the app through XCTest, which iOS counts as assistive technology, so the
    # Debug app would show its optional tools, such as Board controls and drawing descriptions.
    simctl("spawn", udid, "defaults", "write", BUNDLE_ID, "paeonia-scenario-assistive-technology", "none")


def use_large_icons(agent_device, locale, edit_mode):
    """Gives an iPhone Home Screen large app icons, which drop the labels under the widgets.

    iOS keeps the icon size with the wallpaper, not in a defaults key, so this goes through
    SpringBoard: edit mode, Edit > Customize, then the size button, unless it already offers
    regular icons. edit_mode is the point of the long press that starts edit mode and the tap
    that closes the Customize sheet and ends it.
    """
    def device(*args, **kwargs):
        return run(*agent_device[:1], *args, *agent_device[1:], **kwargs)

    press, dismiss = edit_mode
    device("open", "com.apple.springboard", stdout=subprocess.DEVNULL)
    device("longpress", *map(str, press), "1500", stdout=subprocess.DEVNULL)
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
    device("press", *map(str, dismiss), stdout=subprocess.DEVNULL)
    time.sleep(1.5)


def convex_as(subject, function, args, check=True):
    """Runs a Convex function on the local backend as the account with this Clerk subject."""
    env = {key: value for key, value in os.environ.items()
           if key not in ("CONVEX_SELF_HOSTED_URL", "CONVEX_SELF_HOSTED_ADMIN_KEY", "CONVEX_DEPLOYMENT")}
    env["PATH"] = f"/opt/homebrew/opt/node@22/bin:{env['PATH']}"
    result = subprocess.run(["npx", "convex", "run", function, json.dumps(args), "--identity",
                             json.dumps({"subject": subject}), "--codegen", "disable", "--typecheck", "disable"],
                            cwd=ROOT / "backend", env=env, capture_output=True, text=True)
    if check and result.returncode:
        raise SystemExit(f"{function} failed: {result.stderr.strip()}")
    return result


def show_partner_at_table(subject):
    """Marks Elena present at the Ludo table for the next minute, so the screen shows both players."""
    convex_as(subject, "games:set_game_presence", {"p_kind": "ludo", "p_present": True})


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
    """Fails when the capture looks like another capture of the same locale and device, such as a screen that never opened."""
    mine = thumbnail(path)
    device_family = path.name.split("-")[0]
    for other in sorted(path.parent.glob(f"{device_family}-*.png")):
        if other == path:
            continue
        difference = sum(abs(a - b) for a, b in zip(mine, thumbnail(other))) / len(mine)
        if difference < DUPLICATE_THRESHOLD:
            raise SystemExit(f"{path.name} looks like {other.name} (mean difference {difference:.1f} of 255), "
                             "so the screen probably did not open. Check the simulator and capture it again.")


def capture(udid, path, size):
    simctl("io", udid, "screenshot", "--type", "png", str(path), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    header = path.read_bytes()[:24]
    actual = struct.unpack(">II", header[16:24])
    if header[:8] != b"\x89PNG\r\n\x1a\n" or actual != size:
        raise SystemExit(f"{path.name} is {actual}, not a {size[0]} x {size[1]} PNG")
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


def save_spotlight(agent_device, text, path, size):
    """Saves the frame of the one element whose label contains text, in capture pixels, next to the capture.

    The renderer reads it from <capture>.spotlight.json, so the spotlight follows the app's layout.
    """
    nodes = snapshot_nodes(agent_device)
    matches = [node for node in nodes if text in (node.get("label") or "")]
    if len(matches) != 1:
        raise SystemExit(f"Found {len(matches)} elements labelled with {text!r} on {path.name}, not 1.")
    scale = size[0] / nodes[0]["rect"]["width"]  # The first node is the app, as wide as the screen.
    frame = {key: round(matches[0]["rect"][key] * scale) for key in ("x", "y", "width", "height")}
    path.with_suffix(".spotlight.json").write_text(json.dumps(frame) + "\n")


class Recording:
    """A screen recording through agent-device and the actions sent during it, in seconds from its start."""

    def __init__(self, agent_device, path, screen):
        self.agent_device, self.path, self.screen, self.actions = agent_device, path, screen, []

    def device(self, *args):
        run(*self.agent_device[:1], *args, *self.agent_device[1:], stdout=subprocess.DEVNULL)

    def start(self):
        self.device("record", "start", str(self.path), "--scope", "device", "--hide-touches")
        self.started = time.monotonic()

    def act(self, name, *command, point=None):
        """Notes the action, then sends the agent-device command. point is where it touches, in fractions."""
        self.actions.append((name, time.monotonic() - self.started, point))
        if command:
            self.device(*command)

    def touch(self, name, point, *gesture):
        """Taps point, given in fractions of the screen, or pans from it with gesture's (dx, dy, ms)."""
        x, y = (str(round(fraction * side)) for fraction, side in zip(point, self.screen))
        self.act(name, *(("gesture", "pan", x, y, *map(str, gesture)) if gesture else ("press", x, y)), point=point)

    def stop(self):
        self.device("record", "stop")


def ludo_game(subject):
    games = json.loads(convex_as(subject, "boardGames:get_board_games", {}).stdout)["games"]
    return next(game for game in games if game["kind"] == "ludo")


def film_ludo(recording, subject):
    """Hjalmar throws and moves until his turn passes, then Elena makes her move through the backend."""
    # Her presence lasts a minute, and the table asks Hjalmar to invite her once it ends.
    show_partner_at_table(subject)
    game = ludo_game(subject)
    hjalmar = game["turn_user_id"]
    time.sleep(LEAD_SECONDS)
    for pawn in LUDO_PAWNS:
        recording.touch("die tap", LUDO_DIE, 10, -120, 220)
        time.sleep(4)  # The die lands within 2.05 s on a phone.
        recording.touch("pawn tap", pawn)
        version, deadline = game["version"], time.monotonic() + 15
        while (game := ludo_game(subject))["version"] == version:
            if time.monotonic() > deadline:
                raise SystemExit("The pawn tap made no move. Check LUDO_PAWNS against the seeded position.")
            time.sleep(0.5)
        if game["turn_user_id"] != hjalmar:
            break
    else:
        raise SystemExit("Hjalmar rolled two 6s, which moved both pawns. Seed again and record again.")
    time.sleep(3)
    for die, pawn in PARTNER_MOVES:
        # The phone shows her move before the CLI returns, so the action counts from the call.
        recording.act("partner move")
        result = convex_as(subject, "boardGames:make_move", {
            "p_game_id": game["id"], "p_expected_version": game["version"], "p_move": (die - 1) * 3 + pawn,
            "p_stake": None, "p_client_operation_id": str(uuid.uuid4()), "p_client_id": str(uuid.uuid4()),
            "p_client_sequence": 1, "p_local_created_at": time.strftime("%Y-%m-%dT%H:%M:%S.000Z", time.gmtime())},
            check=False)
        if not result.returncode:
            break
        recording.actions.pop()
        if "not allowed" not in result.stderr:
            raise SystemExit(f"Elena's move failed: {result.stderr.strip()}")
    time.sleep(8)


def film_draw(recording, word, nodes):
    """Waits for the drawing to play back, then taps the word's letters in one agent-device batch, which
    taps at a steadier pace than one command a letter."""
    opened = recording.actions[-1][1]
    time.sleep(max(0, recording.started + opened + DRAW_PLAYBACK_SECONDS - time.monotonic()))
    width, height = recording.screen
    tiles = [node for node in nodes if re.fullmatch(r"\S+ \S", node.get("label") or "")]
    steps, points = [], []
    for letter in word.upper():
        tile = next((tile for tile in tiles if tile["label"].endswith(f" {letter}")), None)
        if tile is None:
            raise SystemExit(f"No letter tile {letter} on the Draw & Guess screen.")
        tiles.remove(tile)
        x, y = (tile["rect"][key] + tile["rect"][side] / 2 for key, side in (("x", "width"), ("y", "height")))
        steps.append({"command": "press", "input": {"target": {"kind": "point", "x": round(x), "y": round(y)}}})
        points.append((x / width, y / height))
    recording.act("letter taps", "batch", "--steps", json.dumps(steps))
    recording.actions[-1] = (*recording.actions[-1][:2], points)
    time.sleep(10)  # The reveal's last step, the reaction row, comes about 4.5 s after the last letter.


def frame_changes(video, area=None):
    """For each 30 fps frame after the first, how many pixels at a sixth of the size changed by more than
    MOTION_LEVEL, and whether the full frame repeats the one before. area is (x, y, width, height) in
    fractions of the screen."""
    crop = "crop=iw*{2}:ih*{3}:iw*{0}:ih*{1},".format(*area) if area else ""
    filters = f"fps={RECORD_FPS},{crop}scale=iw/6:ih/6,format=gray,tblend=all_mode=difference"
    diffs = subprocess.run(["ffmpeg", "-v", "error", "-i", str(video), "-vf", filters, "-f", "rawvideo", "-"],
                           check=True, capture_output=True).stdout
    sums = [line.split(",")[-1] for line in run(
        "ffmpeg", "-v", "error", "-i", str(video), "-vf", f"fps={RECORD_FPS}", "-f", "framemd5", "-",
        capture_output=True).stdout.splitlines() if not line.startswith("#")]
    size = len(diffs) // (len(sums) - 1)
    moved = bytes(0 if value <= MOTION_LEVEL else 1 for value in range(256))
    return [(diffs[i * size:(i + 1) * size].translate(moved).count(1), sums[i + 1] == sums[i])
            for i in range(len(sums) - 1)]


def moving(changes, frame, pixels=MOTION_PIXELS):
    return changes[frame - 1][0] >= pixels


def motion_from(changes, frame, pixels=MOTION_PIXELS):
    """The first frame at or after frame that moves."""
    return next(i for i in range(max(frame, 1), len(changes) + 1) if moving(changes, i, pixels))


def motion_end(changes, frame, gap=MOTION_GAP):
    """The last moving frame of the motion that frame starts, which ends once gap frames in a row stay still."""
    last = frame
    for i in range(frame + 1, len(changes) + 1):
        if moving(changes, i):
            last = i
        elif i - last >= gap:
            break
    return last


def first_stroke(canvas, frame):
    """The replay's first stroke: the first frame after frame that adds a little to a canvas that was still
    for 3 frames since the empty canvas appeared. The canvas appears at once, as one frame that changes
    SCREEN_CHANGE_PIXELS to CANVAS_PIXELS between still frames. The push into view changes it over many
    frames, and the switch to the Games tab on the way changes nearly all of it."""
    def still(i):
        return not moving(canvas, i)
    appeared = None
    for i in range(max(frame, 4), len(canvas) - 3):
        if moving(canvas, i, SCREEN_CHANGE_PIXELS):
            appeared = i if still(i - 1) and still(i + 1) and not moving(canvas, i, CANVAS_PIXELS) else None
        elif appeared and moving(canvas, i) and all(still(j) for j in range(i - 3, i)):
            return i
    raise SystemExit("Found no first stroke of the Draw & Guess replay in the recording.")


def find_events(screen, actions, video, full):
    """The frames of what happens, and of each tap with its point, found from the frames after each action.
    full is frame_changes(video). The first action's motion tells how far the video's clock is from the
    script's."""
    first = actions[0][1]
    offset = motion_from(full, round(max(first - 1, 0) * RECORD_FPS)) - first * RECORD_FPS
    # Each name's first action. The first action's own lag is in the offset, so a later action may show
    # sooner after it was sent. Searching from half a second earlier allows for that.
    anchor = {name: round((t - 0.5) * RECORD_FPS + offset) for name, t, _ in reversed(actions)}
    if screen == "03-ludo":
        taps = [(motion_from(full, round((t - 0.5) * RECORD_FPS + offset)), point) for _, t, point in actions if point]
        # A move ends with the die hopping to the next player's tray, right as the last pawn lands.
        die, tap = motion_from(full, anchor["die tap"]), motion_from(full, anchor["pawn tap"])
        lands = motion_end(full, tap) - TRAY_HOP_FRAMES
        piece = lands
        while any(moving(full, i) for i in range(piece - 3, piece)):
            piece -= 1
        # The pawns light up 0.2 s or more after the die comes to rest.
        events = {"die tap": die, "die settled": motion_end(full, die, 5), "piece starts": piece, "piece lands": lands}
        if "partner move" in anchor:
            partner = motion_from(full, anchor["partner move"])
            events |= {"partner die starts": partner,
                       "partner piece lands": motion_end(full, partner) - TRAY_HOP_FRAMES}
        return events, taps
    # Each letter's tile starts to move toward its slot. The canvas area leaves out the speed bonus
    # line under it, which moves the whole time.
    tiles, canvas = frame_changes(video, DRAW_TILES), frame_changes(video, DRAW_CANVAS)
    # The tiles stay still while the drawing plays, so the taps are the tile motions after the first stroke.
    stroke = first_stroke(canvas, anchor["open link"])
    taps, frame = [], stroke
    for point in actions[-1][2]:
        taps.append((frame := motion_from(tiles, frame, TILE_PIXELS), point))
        frame += TAP_FRAMES
    done = max(i for i in range(1, taps[0][0]) if moving(canvas, i))
    return {"drawing starts": stroke, "drawing done": done,
            "celebration starts": taps[-1][0],
            "celebration settled": motion_end(full, taps[-1][0], CELEBRATION_GAP)}, taps


def finish_recording(screen, recording, path):
    """Cuts the raw recording to its actions, writes it at a constant 30 fps in H.264 with its events
    file, and prints how many frames repeat inside each motion."""
    changes = frame_changes(recording.path)
    events, taps = find_events(screen, recording.actions, recording.path, changes)
    first = max(0, min(events.values()) - round(LEAD_SECONDS * RECORD_FPS))
    last = min(len(changes), max(events.values()) + TAIL_SECONDS * RECORD_FPS)
    run("ffmpeg", "-v", "error", "-y", "-i", str(recording.path), "-vf",
        f"fps={RECORD_FPS},trim=start_frame={first}:end_frame={last + 1},setpts=PTS-STARTPTS",
        "-c:v", "libx264", "-preset", "slow", "-crf", "14", "-pix_fmt", "yuv420p", "-an",
        "-movflags", "+faststart", str(path))
    names = list(events)
    for start, end in zip(names[::2], names[1::2]):
        repeats = [changes[i - 1][1] for i in range(events[start] + 1, events[end] + 1)]
        longest = run_length = 0
        for repeat in repeats:
            run_length = run_length + 1 if repeat else 0
            longest = max(longest, run_length)
        print(f"{path.name}: {start} to {end}, {len(repeats)} frames, {sum(repeats)} repeat the one before, "
              f"longest run {longest}", flush=True)
    seconds = {name: round((frame - first) / RECORD_FPS, 3) for name, frame in events.items()}
    seconds["taps"] = [{"t": round((frame - first) / RECORD_FPS, 3), "x": round(point[0], 4), "y": round(point[1], 4)}
                       for frame, point in taps]
    path.with_suffix(".events.json").write_text(json.dumps(seconds, indent=2, ensure_ascii=False) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locale", choices=LANGUAGES, required=True)
    parser.add_argument("--ids", type=Path, required=True, help="the JSON line scripts/app-store-content printed")
    parser.add_argument("--agent-device", required=True, help="agent-device command prefix pinned to the simulator")
    parser.add_argument("--screens")
    parser.add_argument("--record", action="store_true", help="film the screens in RECORDINGS instead")
    parser.add_argument("--simulator", default="Paeonia Screenshots")
    parser.add_argument("--output", type=Path, default=ROOT / "ios/ASConnectScreenshots/trial-1/raw")
    args = parser.parse_args()
    ids = json.loads(args.ids.read_text().strip().splitlines()[-1])
    requested = set((args.screens or ",".join(RECORDINGS if args.record else SCREENS)).split(","))
    if unknown := requested - set(RECORDINGS if args.record else SCREENS):
        raise SystemExit(f"Unknown screens: {', '.join(sorted(unknown))}")
    screens = [screen for screen in SCREENS if screen in requested]

    simulator = device(args.simulator)
    udid = simulator["udid"]
    name = "iPad" if "iPad" in simulator["deviceTypeIdentifier"] else "iPhone"
    family = FAMILIES[name]
    prepare(udid, args.locale, family, home_screen=not args.record)
    folder = args.output / args.locale
    folder.mkdir(parents=True, exist_ok=True)
    agent_device = shlex.split(args.agent_device)
    if "01-widget" in screens and family.edit_mode:
        use_large_icons(agent_device, args.locale, family.edit_mode)
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
            if args.record:
                screen_size = tuple(snapshot_nodes(agent_device)[0]["rect"][key] for key in ("width", "height"))
                recording = Recording(agent_device, Path(tempfile.mkdtemp()) / "raw.mp4", screen_size)
                if screen == "06-draw":
                    recording.start()
                    recording.act("open link")
            run(*agent_device[:1], "open", BUNDLE_ID, re.sub(r"\{(\w+)\}", lambda m: ids[m.group(1)], url),
                *agent_device[1:], stdout=subprocess.DEVNULL)
            time.sleep(1)
            tree = run(*agent_device[:1], "snapshot", "-i", *agent_device[1:], capture_output=True).stdout
            if "[alert]" in tree:
                run(*agent_device[:1], "click", f'label="{OPEN_BUTTON[args.locale]}"', *agent_device[1:],
                    stdout=subprocess.DEVNULL)
        if args.record:
            path = folder / f"{name}-{screen}.mp4"
            if screen == "03-ludo":
                time.sleep(wait)
                recording.start()
                film_ludo(recording, ids["partner_clerk_subject"])
            else:
                film_draw(recording, ids["guess_word"], snapshot_nodes(agent_device))
            recording.stop()
            finish_recording(screen, recording, path)
            print(f"Recorded {args.locale}/{path.name} from {recording.path}", flush=True)
            continue
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
        path = folder / f"{name}-{screen}.png"
        capture(udid, path, family.size)
        if screen in SPOTLIGHTS:
            save_spotlight(agent_device, ids[SPOTLIGHTS[screen]], path, family.size)
        print(f"Captured {args.locale}/{path.name}", flush=True)


if __name__ == "__main__":
    main()
