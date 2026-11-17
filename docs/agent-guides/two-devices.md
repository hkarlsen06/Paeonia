# Testing on the developer's two devices

The developer's iPhone and iPad are signed in as the two partners of a couple on `api.paeonia.no`. While they are plugged into this Mac, an agent can install its worktree's build on both, drive them, and read their logs with `scripts/devices`. Use them for what a simulator cannot show: calls between two people, VoIP pushes, the system call UI and its banners, screen sharing, the camera, Picture in Picture, call audio and real network paths. The developer prefers this to a simulator for that work (2026-11-17).

| | iPhone | iPad |
|---|---|---|
| Name | Cold Harbor, iPhone 18 Pro Max | Allentown, iPad Pro 11-inch (4th generation) |
| Partner signed in | Hjalmar | Henrik |
| Points per screenshot pixel | 1/3 | 1/2 |

## When you may use them

- Use them when `scripts/devices status` shows both connected. If your change needs them and they are not, ask the developer to plug them in, and say what you will test.
- The iPhone is the developer's own phone. Calls ring both devices out loud and land in the Phone app's Recents.
- Keep the app's data. `install` installs over the app, which keeps it. Never uninstall the app, sign out, leave the couple or delete content on them.
- Do not change device settings unless the test needs it, and set them back afterwards.
- The accounts and their data are the developer's test data on `api.paeonia.no`. Calls, messages and pushes between the two are fine.
- `scripts/devices` takes the `devices` lock (`scripts/lock`), so one worktree drives the devices at a time. Run `scripts/devices release` when you are done. A session nobody used for 10 minutes frees itself.

## Commands

```sh
scripts/devices status                        # which device is connected, and who holds the lock
scripts/devices install                       # build this worktree for devices, install on both, launch
scripts/devices install ipad                  # one device only
scripts/devices iphone open no.paeonia.app    # start or bring back the iPhone's session, with a snapshot
scripts/devices ipad snapshot -i              # the iPad's buttons and texts, with @refs
scripts/devices iphone press 'label="Ring Henrik"'
scripts/devices ipad wait text "Svar" 15000
scripts/devices ipad screenshot /tmp/ipad.png
scripts/devices logs ipad "2026-11-17 15:08:30"   # system log since then, prints CallStats
scripts/devices release
```

Everything after the device name goes to `agent-device` (`agent-device help` lists its commands), with that device's session. `open` also gets the device's UDID. Coordinates for `press <x> <y>` are points, the screenshot's pixels divided by 3 on the iPhone and 2 on the iPad. System UI such as the screen sharing picker and the call banner is in no snapshot, so tap it by coordinates after a screenshot. Copy screenshots you show the developer to `~/agent-shots/paeonia/`.

Both devices show the app in Norwegian. The labels a call test uses are "Ring Henrik" and "Ring Hjalmar" on the Us tab, "Svar" (answer), "Avvis" (decline), "Legg på" (hang up), "Demp" (mute), "Kamera" and "Del skjermen din" (share your screen).

## A call test

1. `scripts/devices install`, then `scripts/devices iphone open no.paeonia.app` and the same for the iPad.
2. `scripts/devices iphone press 'label="Ring Henrik"'` and `scripts/devices ipad wait text "Svar" 15000`.
3. Screenshot the ringing device, answer with `press 'label="Svar"'` and check `scripts/devices ipad appstate`. `runningForeground` means Paeonia stayed in front.
4. Hang up with `press 'label="Legg på"'`.
5. Read both phones' call reports with `scripts/call-reports --hosted 2`. They list the path, round trip, loss, and each video's frames a second, size, encoder and freezes.

To share a screen with motion on it, press "Del skjermen din", screenshot, and tap "Del hele skjermen" in the system's sheet by coordinates (about 220, 554 on the iPhone). Then play a video in another app, such as `scripts/devices iphone open com.google.ios.youtube "https://www.youtube.com/watch?v=aqz-KE-bpKQ"`, which moves the session to YouTube. Open Paeonia again before you tap in it, and leave nothing playing when you finish.

## Logs

`scripts/devices logs <device> "<start>"` collects the device's whole system log since `<start>` into a `.logarchive` and prints Paeonia's `CallStats` lines. It needs a USB cable, because collecting over Wi-Fi fails with "Device not configured", and it opens the macOS password dialog, which the developer answers. Search the archive it names with `/usr/bin/log show <archive> --predicate '...'`. zsh has its own `log` command, so write the full path. The system's call services log as `callservicesd` and `InCallService`. `shouldPresentDismissedForCall` there says why the system showed a banner, its full-screen call UI or nothing.

## First-time setup

These are done on this Mac, and only need doing again on a new Mac or after a reset:

- Developer mode for the Mac's developer tools (`sudo DevToolsSecurity -enable`), so `agent-device` can drive a device without a prompt for each command.
- Developer Mode on both devices, and each device trusted by this Mac.
- `agent-device` from T3's tools (`~/.t3/tools/agent-device`). Its runner app (`no.hkarlsen.agentdevice.runner`) is signed with team 48ZSLD4RMP and installs itself on a device at the first `open`.
