# Verifying a Libraries.dev effect

## On the simulator

The drawing screen's scenario is `widget-drawing` (scenario ids are kebab-case). Its uploader fakes every send as delivered.

1. Take a simulator and open that same one: `SIM="$(scripts/lock acquire simulator)"`, then `device_open` the device named `$SIM`. The lock can hand out Shared iPhone 2 or 3, so read the name every time. `scenario-record` exits 64 when the `--then` command's `agent-device` targets another simulator than the one this worktree holds.
2. Run one `agent-device` command, such as `open com.apple.Preferences`, so the first tap of the recording lands.
3. Record a send. Taps are in points on the iPhone 17 Pro simulator:

   ```bash
   scripts/scenario-record widget-drawing --no-build --out ~/agent-shots/paeonia/<date>-<topic>/<name> --seconds 9 \
     --then "$AD open no.paeonia.app && sleep 1.5 && $AD press 86 686 && sleep 0.5 && $AD press 166 630 && sleep 0.5 && $AD press 200 380 && sleep 1 && $AD press 293 798"
   ```

   That picks pink (86, 686), the paint bucket (166, 630), fills the canvas (200, 380) and taps Send (293, 798). A pen stroke from `agent-device swipe` or `gesture pan` draws nothing visible, and the fill is the only ink that shows. The fill does not always land: a fill is a change of about 40% of the screen in the report, and when it is missing the canvas in the picture is empty.
4. Close the device panel session, then `scripts/lock release simulator`.

## Reading the report

- The wave is one `MOTION` of about 1.7 s over 99% of the screen, its box starting at `y=0`. A box starting at about `y=96` means it stopped under the navigation bar.
- The end fade is a `MOTION` of about 0.15 s and 3%. A `CUT` there of over 20% means the picture and the live screen do not line up.
- A stall is a `CUT` in the middle of the wave after a long gap between frames. Check `uptime` first: at a load average over 20 the simulator drops frames on its own. Judge smoothness on the iPhone instead.
- To check the coloured edge against the screen's corners, crop a corner from `recording.mp4` near the end of the wave: `ffmpeg -ss <t> -i recording.mp4 -frames:v 1 -vf "crop=600:600:0:2022" corner.png`.

## On the iPhone

`docs/agent-guides/devices.md` says how to install and drive the developer's iPhone, and how to measure hitches. For the drawing screen: open the Us tab ("Oss"), tap the button "Den delte tegne-widgeten", choose the fill ("Fyll") and a colour, and tap the canvas. A send there is real: the drawing goes to the partner's widget. Say in your summary how many test drawings you sent.
