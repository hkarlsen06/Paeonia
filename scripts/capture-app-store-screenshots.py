#!/usr/bin/env python3
"""Capture App Store PNGs from the real app on the test couple's seeded account.

Run from the repository root after scripts/local-backend, scripts/app-store-content
and scripts/sim-sign-in, with the simulator signed in as Hjalmar:

    python3 scripts/capture-app-store-screenshots.py --locale en-US --ids ids.json \\
        --agent-device "<agent-device command with its --platform, --udid, --config and --session flags>" \\
        [--screens 01-widget,02-question,...] [--simulator "Paeonia Screenshots"] [--output DIR]

--ids is the JSON line scripts/app-store-content prints last. The screens open
through Paeonia's deep links. simctl openurl asks "Open in Paeonia?" first, so
the links go through agent-device's `open <app> <url>`, which does not. The
simulator's Home Screen must already hold the large Paeonia drawing widget on
the page it shows, because 01-widget is the Home Screen after the app closes.

02-question is the moment Elena's answer is revealed: the script opens today's
question, types Hjalmar's answer from --ids, sends it, and captures the reveal.
So seed with `scripts/app-store-content --for-reveal`, capture every screen but
06-chat, add the chat with `scripts/app-store-content --chat-only`, then capture
06-chat and 03-ludo.

The script sets the simulator's language for the locale (rebooting when it
changes it) and the status bar to 9:41 with full bars and battery, and checks
that every capture is 1320 x 2868, the 6.9-inch App Store size.
"""

import argparse
import json
import os
from pathlib import Path
import re
import shlex
import struct
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ID = "no.paeonia.app"
SIZE = (1320, 2868)
LANGUAGES = {"en-US": ("en-US", "en_US"), "no": ("nb-NO", "nb_NO")}
# The button of the system "Open in Paeonia?" prompt, which a new simulator shows for deep links.
OPEN_BUTTON = {"en-US": "Open", "no": "Åpne"}
# Seconds for a cold launch to reach Home with the live data loaded.
LAUNCH_SECONDS = 12
# Mean difference per colour channel, out of 255, below which two captures count as the same screen.
DUPLICATE_THRESHOLD = 6
# Each screen's deep link and the seconds to wait for its live data, or the Ludo
# table, to load. They are captured in this order. Ludo comes last, because
# Elena's presence at the table puts a "here now" card at the top of Home.
SCREENS = {
    "01-widget": (None, 4),
    "02-question": ("paeonia://daily/today", 4),
    "04-home": ("paeonia://home", 10),
    "05-memories": ("paeonia://memories", 8),
    "06-chat": ("paeonia://daily/chat?questionId={question_id}", 8),
    "03-ludo": ("paeonia://games/ludo", 25),
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


def prepare(udid, locale):
    """Boots the simulator in the locale's language with the App Store status bar."""
    languages, region = LANGUAGES[locale]
    simctl("bootstatus", udid, "-b", stdout=subprocess.DEVNULL)
    current = simctl("spawn", udid, "defaults", "read", "-g", "AppleLanguages", capture_output=True).stdout
    if f'"{languages}"' not in current and languages not in current.split():
        simctl("spawn", udid, "defaults", "write", "-g", "AppleLanguages", "-array", languages)
        simctl("spawn", udid, "defaults", "write", "-g", "AppleLocale", region)
        simctl("shutdown", udid)
        simctl("boot", udid)
        simctl("bootstatus", udid, "-b", stdout=subprocess.DEVNULL)
    simctl("status_bar", udid, "override", "--time", "9:41", "--dataNetwork", "wifi",
           "--wifiMode", "active", "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
           "--batteryState", "discharging", "--batteryLevel", "100")
    # The Ludo board shows how to zoom until this phone has zoomed it once.
    simctl("spawn", udid, "defaults", "write", BUNDLE_ID, "paeonia.games.ludo.hasZoomedBoard.v2", "-bool", "YES")


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


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--locale", choices=LANGUAGES, required=True)
    parser.add_argument("--ids", type=Path, required=True, help="the JSON line scripts/app-store-content printed")
    parser.add_argument("--agent-device", required=True, help="agent-device command prefix pinned to the simulator")
    parser.add_argument("--screens", default=",".join(SCREENS))
    parser.add_argument("--reveal-delay", type=float, default=1.0,
                        help="seconds from sending Hjalmar's answer to capturing the reveal")
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
        if screen == "02-question":
            run(*agent_device[:1], "fill", 'role="text-view"', ids["own_answer"], *agent_device[1:],
                stdout=subprocess.DEVNULL)
            run(*agent_device[:1], "click", 'id="daily.flow.primary"', *agent_device[1:], stdout=subprocess.DEVNULL)
            time.sleep(args.reveal_delay)
        capture(udid, folder / f"iPhone-{screen}.png")
        print(f"Captured {args.locale}/iPhone-{screen}.png", flush=True)


if __name__ == "__main__":
    main()
