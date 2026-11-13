#!/usr/bin/env python3
"""Capture App Store PNGs from the real app on the test couple's seeded account.

Run from the repository root after scripts/local-backend, scripts/app-store-content
and scripts/sim-sign-in, with the simulator signed in as Hjalmar:

    python3 scripts/capture-app-store-screenshots.py --locale en-US --ids ids.json \\
        --agent-device "<agent-device command with its --platform, --udid, --config and --session flags>" \\
        [--screens 01-widget,02-chat,...] [--simulator "Paeonia Screenshots"] [--output DIR]

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
drawing before the seeding moved its time keeps the old time. The script lets
Paeonia read the simulator's location and puts the simulator in Oslo, where the
seeding puts Hjalmar, so Home's map shows both of them. On the first launch,
open Elena's gift and tap Later and Not now through the welcome. Then clear Home
the way a person would: the close button on Things to try together and on When
will you meet next.
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

--record films 02-question, 03-ludo and 06-draw for the promotional film in video/
instead:

    ... --record --simulator "$SIM" --screens 02-question,03-ludo,06-draw

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

02-question starts on Home and needs the seeding of `scripts/app-store-content
--question-film`, which leaves today's question to Hjalmar. Before it records,
it closes Home's Things to try together and When do you meet next, then opens
the answer, taps its text field and closes it again, because the first
keyboard in an app process stutters. Then it taps the Home card's button, the
composer's photo button and the newest photo in the system picker, so add
scripts/assets/app-store/photos/question-snow.jpg to the simulator's photo
library first with `xcrun simctl addmedia`. Then it taps the text field, types
the film_answer from --ids one letter at a time and sends. The cover turns into
the question's conversation. An accessibility snapshot runs on the app's main
thread for about a second, which freezes the partner's answer opening, so the
script takes none for REVEAL_QUIET_SECONDS after the send. Once two snapshots in
a row then match, it swipes the conversation down with one SWIPE, so the earlier
day shows, and records until the list is still. It
does not take screenshots there, because an agent-device screenshot brings back
the hidden Dynamic Island. The on-screen keyboard stays hidden while the
simulator has a hardware keyboard, unless Automatic Keyboard Minimization is
off: `xcrun simctl spawn "$SIM" defaults write com.apple.keyboard.preferences
AutomaticMinimizationEnabled -bool NO`, which the app reads when it launches.
The composer keeps a draft, so clear the photo and the text after a take that
stopped before sending. After a take that sent, stop the app and run
`scripts/app-store-content --question-film` again, which clears Hjalmar's
answer. Before each take the script removes the app's QUESTION_CACHES, which
still hold the day that reset removed. With them the conversation can open on
the earlier day and the composer on the sent photo.

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
import shutil
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
# The screens --record films, in this order, and the ones SCREENS lacks with their link and wait.
RECORDINGS = ("02-question", "03-ludo", "06-draw")
# An empty link launches the app on Home and opens no link.
FILMS = {"02-question": ("", 10)}
# 02-question finds the Home card's answer button, the answer's text field and the send button by their
# accessibility identifiers, and the composer's photo button by its label, since it has no identifier. The
# photo remove button shows once a photo is staged.
ANSWER_ACTION = "home.dailyPrompt.action"
PHOTO_BUTTON = {"en-US": "Your photo", "no": "Bildet ditt"}
PHOTO_REMOVE = "daily.answer.photo.remove"
ANSWER_TEXT = "daily.answer.text"
SEND_ACTION = "daily.flow.primary"
CHAT_CLOSE = "daily.chat.close"
FLOW_CLOSE = "daily.flow.close"
# The close buttons of Home's cards for a new couple, Things to try together and When do you meet next. The
# couple in the film has been together for over a year, and the map shows more of Home without them. The app
# remembers that they were closed.
NEW_COUPLE_CARDS_CLOSE = ("home.firstSteps.close", "home.visit.moveDown")
# A node's frame, in this order. The snapshot lists the keys in no fixed order.
RECT_KEYS = ("x", "y", "width", "height")
# The app's files, in its Application Support folder, that 02-question removes before it launches the app.
# The app fills them again from the backend.
QUESTION_CACHES = ("ThreadChatCache", "DailyChallengeSnapshotCache", "DailyAnswerMediaDrafts")
# Milliseconds between typed letters, and the seconds the reveal gets to load both days' photos.
TYPE_DELAY_MS = 140
REVEAL_SECONDS = 12
# Seconds after the send tap with no snapshots. The reveal came to rest 3.6 to 5.2 s after the send in takes on this Mac.
REVEAL_QUIET_SECONDS = 7
# The brightness, of 255, above which a pixel is part of the answer's white letters. The pink cursor
# (at most 170) and the grey placeholder stay under it, so the count of such pixels in the text field
# grows with each letter and ignores the cursor's blink. At full size a letter adds 35 such pixels or
# more, a period included, and compression moves the count by less than TEXT_STEP between frames.
TEXT_LEVEL = 200
TEXT_STEP = 25
# The swipe that scrolls the conversation back to the earlier day: its start and its travel as fractions of
# the screen, and its milliseconds. The list keeps moving after the finger lifts, and this speed ends with both
# of the earlier day's answers above the message field. A faster swipe stops at the top of the list, where
# the message field covers Hjalmar's earlier photo and line. A 0.38 swipe left his line half under the field,
# and a 0.35 swipe left most of the earlier question above the screen.
SWIPE = ((0.5, 0.4), (0, 0.36), 400)
# The seconds the list gets to come to rest after the swipe.
SCROLL_SECONDS = 9
# The band of the conversation, as (x, y, width, height) in fractions of the screen, that holds today's divider
# and question once the conversation rests on today, before the partner's answer opens below it. The band
# matches its look at the end of the reveal when less than TODAY_SHARE of it differs. The list can rest a point
# off its last place for a few frames, which changes about 2% of the band. The answer's sparkles change 4 to 5%.
TODAY_BAND = (0, 0.13, 1, 0.17)
TODAY_SHARE = 1 / 40
# The answer cover's header row, as (x, y, width, height) in fractions of the screen. It changes from
# the partner's status to the conversation's title only when the conversation takes over, while the
# keyboard's drop and the send button's spinner before it stay below the row.
COVER_HEADER = (0, 0.075, 1, 0.06)
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
# Hjalmar's seeded location, OSLO in scripts/app-store-content, which the simulator reports as its own.
OSLO = (59.9133, 10.7389)


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
    # Home shows its map only when Paeonia can read this phone's location. Granting it ahead
    # means iOS asks nothing, and the status bar shows no location arrow.
    simctl("privacy", udid, "grant", "location", BUNDLE_ID)
    simctl("location", udid, "set", ",".join(map(str, OSLO)))
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


def snapshot_nodes(agent_device, interactive=True):
    """The accessibility tree as a list of nodes, the app first, with frames in points. The interactive
    tree can leave out a text field that has no focus."""
    tree = run(*agent_device[:1], "snapshot", *(["-i"] if interactive else []), "--json", *agent_device[1:],
               capture_output=True).stdout
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


def wait_for_node(agent_device, what, match, seconds=30):
    """The first accessibility node that match accepts, from snapshots taken until one shows."""
    deadline = time.monotonic() + seconds
    while not (found := next((node for node in snapshot_nodes(agent_device, False) if match(node)), None)):
        if time.monotonic() > deadline:
            raise SystemExit(f"Found no {what} on the screen in {seconds} s.")
        time.sleep(0.5)
    return found


def wait_until_still(agent_device):
    """Returns once two accessibility snapshots in a row hold the same elements in the same places. A snapshot
    takes a second or two, so the screen has been still for at least that long."""
    def layout():
        return [(node.get("type"), node.get("label"), *(round(node["rect"][key]) for key in RECT_KEYS))
                for node in snapshot_nodes(agent_device, False)]
    previous = layout()
    while (current := layout()) != previous:
        previous = current


def node_center(node, screen):
    """The middle of a node's frame as fractions of the screen."""
    rect = node["rect"]
    return ((rect["x"] + rect["width"] / 2) / screen[0], (rect["y"] + rect["height"] / 2) / screen[1])


def close_new_couple_cards(agent_device):
    """Closes the Home cards in NEW_COUPLE_CARDS_CLOSE that show."""
    shown = {node.get("identifier") for node in snapshot_nodes(agent_device)}
    for identifier in NEW_COUPLE_CARDS_CLOSE:
        if identifier in shown:
            run(*agent_device[:1], "press", f'id="{identifier}"', *agent_device[1:], stdout=subprocess.DEVNULL)
            time.sleep(1)


def warm_keyboard(agent_device):
    """Shows the keyboard once before the recording and closes the answer again, leaving Home as a fresh launch
    shows it. The first keyboard in an app process blocks the app for about 0.2 s, which stutters its rise."""
    for identifier in (ANSWER_ACTION, ANSWER_TEXT, FLOW_CLOSE):
        wait_for_node(agent_device, identifier, lambda node: node.get("identifier") == identifier)
        if identifier == FLOW_CLOSE:
            time.sleep(2)  # The keyboard has risen.
        run(*agent_device[:1], "press", f'id="{identifier}"', *agent_device[1:], stdout=subprocess.DEVNULL)
    wait_for_node(agent_device, "Home's question card", lambda node: node.get("identifier") == ANSWER_ACTION)
    wait_until_still(agent_device)


def film_question(recording, agent_device, locale, text):
    """Hjalmar opens today's question from Home, adds the newest photo from the picker, types text and sends."""
    def find(what, match, seconds=30):
        return wait_for_node(agent_device, what, match, seconds)

    def by_id(identifier):
        return lambda node: node.get("identifier") == identifier

    card = find("answer button on Home's question card", by_id(ANSWER_ACTION))
    time.sleep(LEAD_SECONDS + 0.5)
    recording.touch("card tap", node_center(card, recording.screen))
    photo = find("photo button in the composer",
                 lambda node: node.get("label") == PHOTO_BUTTON[locale] or node.get("identifier") == PHOTO_REMOVE)
    if photo.get("identifier") == PHOTO_REMOVE:
        raise SystemExit("The composer still holds a photo from an earlier take. Remove it, close the answer, "
                         "stop the app and record again.")
    time.sleep(2)
    recording.touch("photo tap", node_center(photo, recording.screen))
    # The picker shows the newest photo first, in a grid of cells about a third of the screen wide.
    newest = find("photo in the picker", lambda node: node.get("type") == "Image" and node["rect"]["width"] > 100)
    time.sleep(1.5)
    recording.touch("photo pick", node_center(newest, recording.screen))
    find("staged photo", by_id(PHOTO_REMOVE))
    time.sleep(2.5)
    recording.touch("field tap", node_center(find("answer text field", by_id(ANSWER_TEXT)), recording.screen))
    time.sleep(2)
    # The field moved up with the keyboard. Its frame is where the letters show.
    rect = find("answer text field", by_id(ANSWER_TEXT))["rect"]
    area = (rect["x"] / recording.screen[0], rect["y"] / recording.screen[1],
            rect["width"] / recording.screen[0], rect["height"] / recording.screen[1])
    recording.act("typing", "type", text, "--delay-ms", str(TYPE_DELAY_MS))
    recording.actions[-1] = (*recording.actions[-1][:2], area)
    recording.act("typed")
    time.sleep(1.5)
    recording.touch("send tap", node_center(find("send button", by_id(SEND_ACTION)), recording.screen))
    time.sleep(REVEAL_QUIET_SECONDS)
    find("conversation", by_id(CHAT_CLOSE), REVEAL_SECONDS)
    wait_until_still(agent_device)
    (x, y), (dx, dy), ms = SWIPE
    points = [round(value * side) for value, side in zip((x, y, dx, dy), recording.screen * 2)]
    recording.act("swipe", "gesture", "pan", *map(str, points), str(ms), point=((x, y), (x + dx, y + dy), ms / 1000))
    time.sleep(SCROLL_SECONDS)


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


def gray_frames(video, area, shrink=1):
    """Each 30 fps frame's area, shrink times smaller, as gray bytes. area is (x, y, width, height) in
    fractions of the screen. Frame i of the video is item i."""
    width, height = (int(side) for side in run(
        "ffprobe", "-v", "error", "-select_streams", "v", "-show_entries", "stream=width,height",
        "-of", "csv=p=0", str(video), capture_output=True).stdout.strip().split(","))
    # ffmpeg crops and scales a YUV 4:2:0 video to even sizes, so the frames are split at the same sizes.
    crop = [round(fraction * side / 2) * 2 for fraction, side in zip(area, (width, height, width, height))]
    out = [crop[2] // shrink // 2 * 2, crop[3] // shrink // 2 * 2]
    frames = subprocess.run(["ffmpeg", "-v", "error", "-i", str(video), "-vf",
                             f"fps={RECORD_FPS},crop={crop[2]}:{crop[3]}:{crop[0]}:{crop[1]},"
                             f"scale={out[0]}:{out[1]},format=gray", "-f", "rawvideo", "-"],
                            check=True, capture_output=True).stdout
    size = out[0] * out[1]
    return [frames[i:i + size] for i in range(0, len(frames) - size + 1, size)]


def bright_pixels(video, area):
    """For each 30 fps frame, how many pixels in area are brighter than TEXT_LEVEL."""
    bright = bytes(1 if value > TEXT_LEVEL else 0 for value in range(256))
    return [frame.translate(bright).count(1) for frame in gray_frames(video, area)]


def looks_like(frame, other):
    """Whether fewer than TODAY_SHARE of two gray frames' pixels differ by more than MOTION_LEVEL."""
    return sum(1 for a, b in zip(frame, other) if abs(a - b) > MOTION_LEVEL) < len(frame) * TODAY_SHARE


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
    # The heart between the two photos on Home pulses, so the cover that opens over Home counts only from
    # a change the size of a screen.
    opens = SCREEN_CHANGE_PIXELS if screen == "02-question" else MOTION_PIXELS
    offset = motion_from(full, round(max(first - 1, 0) * RECORD_FPS), opens) - first * RECORD_FPS
    # Each name's first action. The first action's own lag is in the offset, so a later action may show
    # sooner after it was sent. Searching from half a second earlier allows for that.
    anchor = {name: round((t - 0.5) * RECORD_FPS + offset) for name, t, _ in reversed(actions)}
    if screen == "02-question":
        def start(name):
            return motion_from(full, anchor[name])
        taps = [(start(name), point) for name, _, point in actions if name not in ("typing", "typed", "swipe")]
        card, send = motion_from(full, anchor["card tap"], opens), start("send tap")
        taps[0] = (card, taps[0][1])
        # The picker and the photo it hands back have settled before the text field is tapped.
        staged = max(i for i in range(start("photo pick"), anchor["field tap"]) if moving(full, i)) + 1
        # Each letter adds white pixels to the field. Frame i of the video is index i of the counts.
        letters = bright_pixels(video, actions[[name for name, _, _ in actions].index("typing")][2])
        # The tap shows only a cursor. Then the photo shrinks to its thumbnail while the keyboard rises, one motion
        # that starts with a change the size of a screen. Small changes, such as the keyboard's suggestions, can
        # come seconds later. The field moves through its final frame while the keyboard rises, so the letters
        # count from after that, and until a second after the typing command returned, well before the send
        # button lights up.
        keyboard = motion_end(full, motion_from(full, start("field tap"), SCREEN_CHANGE_PIXELS)) + 1
        typed = [i for i in range(max(anchor["typing"], keyboard), anchor["typed"] + RECORD_FPS)
                 if abs(letters[i] - letters[i - 1]) >= TEXT_STEP]
        if not typed:
            raise SystemExit("Found no letters appearing in the answer's text field.")
        reveal = motion_from(frame_changes(video, COVER_HEADER), send)
        # The swipe can reach the app seconds after it is sent, so its motion is found from the end: it is the
        # last motion, and the list rests for over a second before it.
        last = max(i for i in range(send, len(full) + 1) if moving(full, i))
        if last > len(full) - TAIL_SECONDS * RECORD_FPS:
            raise SystemExit("The list still moved near the end of the recording. Record again when the Mac is idle.")
        scroll = last
        while any(moving(full, i) for i in range(scroll - MOTION_GAP, scroll)):
            scroll -= 1
        settled = max(i for i in range(send, scroll) if moving(full, i)) + 1
        # The conversation first shows where the phone's copy of the chat put it, then moves to today. It rests on
        # today once today's band looks as it does when the reveal has settled, for three frames in a row.
        band = gray_frames(video, TODAY_BAND, 3)
        today = next((i for i in range(reveal, settled + 1)
                      if all(looks_like(band[j], band[settled]) for j in range(i, i + 3))), None)
        if today is None:
            raise SystemExit("The conversation never rested on today before the reveal settled.")
        # The partner's answer opens with a burst of petals. Their first frame is a small cluster, the first change
        # after today that is smaller than a screen change. The simulator can stop drawing on that frame for a
        # quarter of a second, so the film cuts from it to the next frame that changes. The photo of the answer
        # just sent can fade in meanwhile, but in steps the size of a screen change.
        petals = next((i for i in range(today + 1, settled) if moving(full, i)
                       and not moving(full, i, SCREEN_CHANGE_PIXELS)), None)
        if petals is None:
            raise SystemExit("Found no petals bursting from the partner's answer.")
        (_, _, (origin, target, seconds)), = [action for action in actions if action[0] == "swipe"]
        # In pairs, each motion's start and end, so the repeated-frame report covers them. The rest come last.
        return {"card tap": card, "question shown": motion_end(full, card) + 1, "photo tap": start("photo tap"),
                "photo staged": staged, "field tap": start("field tap"), "keyboard up": keyboard,
                "typing starts": typed[0], "typing done": typed[-1], "reveal starts": reveal,
                "reveal settled": settled, "scroll starts": scroll, "scroll settled": last + 1,
                "today shown": today, "petals start": petals, "petals move": motion_from(full, petals + 1),
                "send tap": send}, taps, [(scroll, origin, target, seconds)]
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
        return events, taps, []
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
            "celebration settled": motion_end(full, taps[-1][0], CELEBRATION_GAP)}, taps, []


def finish_recording(screen, recording, path):
    """Cuts the raw recording to its actions, writes it at a constant 30 fps in H.264 with its events
    file, and prints how many frames repeat inside each motion."""
    changes = frame_changes(recording.path)
    events, taps, swipes = find_events(screen, recording.actions, recording.path, changes)
    first = max(0, min(events.values()) - round(LEAD_SECONDS * RECORD_FPS))
    last = min(len(changes), max(events.values()) + TAIL_SECONDS * RECORD_FPS)
    run("ffmpeg", "-v", "error", "-y", "-i", str(recording.path), "-vf",
        f"fps={RECORD_FPS},trim=start_frame={first}:end_frame={last + 1},setpts=PTS-STARTPTS",
        "-c:v", "libx264", "-preset", "slow", "-crf", "14", "-pix_fmt", "yuv420p", "-an",
        "-movflags", "+faststart", str(path))
    names = list(events)
    for start, end in zip(names[::2], names[1::2]):
        if events[end] <= events[start]:
            continue
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
    if swipes:
        seconds["swipes"] = [{"t": round((frame - first) / RECORD_FPS, 3), "x": round(origin[0], 4),
                              "y": round(origin[1], 4), "to_x": round(target[0], 4), "to_y": round(target[1], 4),
                              "seconds": duration} for frame, origin, target, duration in swipes]
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
    available = RECORDINGS if args.record else SCREENS
    requested = set((args.screens or ",".join(available)).split(","))
    if unknown := requested - set(available):
        raise SystemExit(f"Unknown screens: {', '.join(sorted(unknown))}")
    screens = [screen for screen in available if screen in requested]

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
        url, wait = {**SCREENS, **FILMS}[screen]
        # Every screen starts from a fresh launch. A deep link opens beneath a full-screen
        # cover, such as the reveal, so a cover left from an earlier screen or run would
        # hide it. Terminating fails when the app is not running, which is fine.
        subprocess.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], stderr=subprocess.DEVNULL)
        if args.record and screen == "02-question":
            data = Path(simctl("get_app_container", udid, BUNDLE_ID, "data", capture_output=True).stdout.strip())
            for cache in QUESTION_CACHES:
                shutil.rmtree(data / "Library/Application Support" / cache, ignore_errors=True)
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
                if screen == "02-question" and "film_answer" not in ids:
                    raise SystemExit("--ids has no film_answer. Seed with scripts/app-store-content --question-film.")
        if url:
            run(*agent_device[:1], "open", BUNDLE_ID, re.sub(r"\{(\w+)\}", lambda m: ids[m.group(1)], url),
                *agent_device[1:], stdout=subprocess.DEVNULL)
            time.sleep(1)
            tree = run(*agent_device[:1], "snapshot", "-i", *agent_device[1:], capture_output=True).stdout
            if "[alert]" in tree:
                run(*agent_device[:1], "click", f'label="{OPEN_BUTTON[args.locale]}"', *agent_device[1:],
                    stdout=subprocess.DEVNULL)
        if args.record:
            path = folder / f"{name}-{screen}.mp4"
            if screen == "02-question":
                time.sleep(wait)
                close_new_couple_cards(agent_device)
                warm_keyboard(agent_device)
                recording.start()
                film_question(recording, agent_device, args.locale, ids["film_answer"])
            elif screen == "03-ludo":
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
