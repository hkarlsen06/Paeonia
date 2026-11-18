# Testing on the developer's iPhone and iPad

The developer's iPhone and iPad each run Paeonia signed in to `api.paeonia.no`, as the two partners of one couple. While a device is plugged into this Mac, or reachable on its network, an agent can install its worktree's build, drive the app and read the device's logs with `scripts/devices`. Each device works on its own, so one connected device is enough for most work. Calls between the partners need both.

Use a device for anything it shows better than a simulator: how the real app looks and feels with real data, iPad layouts on real hardware, performance, scrolling and animation smoothness, the camera, haptics, sound, widgets, notifications and pushes, background work, and calls, screen sharing and Picture in Picture. The developer prefers a device to a simulator for this (2026-11-17). Keep developer scenarios and UI tests on the simulator, because they need fixture data, and a device shows the developer's real account.

| | iPhone | iPad |
|---|---|---|
| Name | Cold Harbor, iPhone 18 Pro Max | Allentown, iPad Pro 11-inch (4th generation) |
| Partner signed in | Hjalmar | Henrik |
| Points per screenshot pixel | 1/3 | 1/2 |

## When you may use them

- Use a device whenever `scripts/devices status` shows it connected. If your change needs one that is not, ask the developer to connect it and say what you will test.
- The iPhone is the developer's own phone. What you do on it is real: a call rings out loud and lands in Recents, a message reaches the partner, a notification shows on the other device.
- Keep the app's data. `install` installs over the app, which keeps it. Never uninstall the app, sign out, leave the couple or delete content you did not create for the test.
- Do not change device settings unless the test needs it, and set them back afterwards.
- The accounts hold the developer's test data. Content you create to test something, such as a message, a drawing or a memory, is fine. Remove it afterwards when the app lets you.
- Each device has its own lock (`device-iphone`, `device-ipad` in `scripts/lock`), which `scripts/devices` takes, so two worktrees can each use one device. Run `scripts/devices release` when you are done. It also restarts Paeonia if it is running, because an app that `agent-device` drove keeps showing extra controls until it restarts. A session nobody used for 10 minutes frees itself.

## Commands

```sh
scripts/devices status                        # which device is connected, and who holds it
scripts/devices install                       # build this worktree, install on every connected device, launch
scripts/devices install ipad                  # one device only
scripts/devices iphone open no.paeonia.app    # start the iPhone's session, or bring Paeonia back, with a snapshot
scripts/devices ipad snapshot -i              # the iPad's buttons and texts, with @refs
scripts/devices iphone press 'label="Spill"'
scripts/devices ipad wait text "Svar" 15000
scripts/devices iphone screenshot ~/agent-shots/paeonia/$(date +%F)-ring/iphone.png  # make the folder first
scripts/devices logs ipad "2026-11-17 15:08:30"            # Paeonia's log lines since then
scripts/devices logs ipad "2026-11-17 15:08:30" CallStats  # one category
scripts/devices release                       # or: release ipad
```

Start each device's session with `open` before any other command. Everything after the device name goes to `agent-device` (`agent-device help` lists its commands, such as `scroll`, `fill`, `back`, `appstate` and `record`), with that device's session. Coordinates for `press <x> <y>` are points, the screenshot's pixels divided by 3 on the iPhone and 2 on the iPad. System UI, such as a system sheet, an alert or the call banner, is in no snapshot, so tap it by coordinates after a screenshot. `open <bundle id or URL>` opens another app, which then becomes the session's app until you open Paeonia again. Save screenshots straight into a `~/agent-shots/paeonia/<date>-<topic>/` folder, not `/tmp`. T3 shows every image you read as a card that loads the file from that path, so a screenshot read from `/tmp` turns into "Image unavailable" once it is deleted, and Claude's Read hook refuses images under `/tmp`.

Both devices show the app in Norwegian. The tabs are "Oss" (Us), "Samtaler" (Chats), "Spill" (Games), "Minner" (Memories) and "Mer" (More).

## A call between the two

Calls need both devices.

1. `scripts/devices install`, then `scripts/devices iphone open no.paeonia.app` and the same for the iPad.
2. `scripts/devices iphone press 'label="Ring Henrik"'` and `scripts/devices ipad wait text "Svar" 15000`.
3. Screenshot the ringing device, answer with `press 'label="Svar"'` ("Avvis" declines) and check `scripts/devices ipad appstate`. `runningForeground` means Paeonia stayed in front.
4. Hang up with `press 'label="Legg på"'`. The other buttons are "Demp" (mute), "Høyttaler" (speaker), "Kamera" and "Del skjermen din" (share your screen).
5. Read both devices' call reports with `scripts/call-reports --hosted 2`. They list the path, round trip, loss, and each video's frames a second, size, encoder and freezes.

To share a screen with motion on it, press "Del skjermen din", screenshot, and tap "Del hele skjermen" in the system's sheet by coordinates (about 220, 554 on the iPhone). Then play a video in another app, such as `scripts/devices iphone open com.google.ios.youtube "https://www.youtube.com/watch?v=aqz-KE-bpKQ"`. Open Paeonia again before you tap in it, and leave nothing playing when you finish.

## Measuring smoothness

An `agent-device` recording on a device runs at 7.5 frames a second, too slow to show a hitch, so measure one with Instruments instead. Find the app's process id with `xcrun devicectl device info processes --device <udid> | grep PaeoniaApp$`, then start `xcrun xctrace record --template 'Animation Hitches' --device <udid> --attach <pid> --time-limit 15s --output <scratch>/hitches.trace` as a background command, and drive the animation while it records. The trace finishes writing some time after the time limit, and the background command ends only then, so export the trace once it has ended. Read the `hitches` table (`xcrun xctrace export --input <trace> --xpath '/trace-toc/run[@number="1"]/data/table[@schema="hitches"]'`): no rows means no hitches. The `displayed-surfaces-per-second` table shows that the animation drew, about 55 to 60 a second while it runs. A trace is about 1 GB, so delete it afterwards.

## Logs

`scripts/devices logs <device> "<start>" [category]` collects the device's whole system log since `<start>` into a `.logarchive`, says where, and prints Paeonia's lines, or only one category's, such as `CallStats` or `CallAudio`. The device keeps only lines logged at the default level or above, so `.info` and `.debug` lines are not in it. It needs a USB cable, because collecting over the network fails with "Device not configured", and it opens the macOS password dialog, which the developer answers. Search the archive with `/usr/bin/log show <archive> --predicate '...'`. zsh has its own `log` command, so write the full path. For calls, the system's call services log as `callservicesd` and `InCallService`, and `shouldPresentDismissedForCall` there says why the system showed a banner, its full-screen call UI or nothing.

## First-time setup

These are done on this Mac, and only need doing again on a new Mac or after a reset:

- Developer mode for the Mac's developer tools (`sudo DevToolsSecurity -enable`), so `agent-device` can drive a device without a prompt for each command.
- Developer Mode on each device, and each device trusted by this Mac.
- `agent-device` from T3's tools (`~/.t3/tools/agent-device`). Its runner app (`no.hkarlsen.agentdevice.runner`) is signed with team 48ZSLD4RMP and installs itself on a device at the first `open`.
