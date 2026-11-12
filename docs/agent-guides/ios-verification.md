# iOS verification

## Testing rules

The root [AGENTS.md](../../AGENTS.md#testing) says when a change needs a test. Agents do not add tests otherwise.

### Where tests go

- `ios/PaeoniaAppUITests/`: user journeys through the production root. Launch an interactive local flow with `app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-<seed>"` and find controls by accessibility identifier, never by copy, so the tests pass in any language. Add an identifier to the control when it has none. `AccountJourneyUITests` and `PaeoniaAppUITests` show the pattern.
- `ios/PaeoniaAppTests/`: integration tests that wire a real view model, repository and local store with a fake only at the network or OS boundary, the two-phone game simulations under `Games/Simulation/` and `Games/ExquisiteCorpse/Simulation/`, and unit tests for the pure logic the root rules list.

Prefer the UI test when the bug would show on screen, and the integration test when it would show in what is stored or sent. A unit test of a view model's loading flag, banner text or animation timing catches nothing that the device check misses.

Optional-tool journeys use `launchWithExtraAccessibilityTools()` to turn those switches on. The settings journey models the input to Paeonia's optional-control policy with the Debug-only `-paeonia-scenario-assistive-technology none` or `active` argument. XCTest itself is an accessibility client, so its ordinary launch cannot establish a no-assistive-technology precondition. The scenario logs the unmodified system value and simulated value. Override only Paeonia's presentation input. Setting SwiftUI's global `accessibilityEnabled` to false leaves the tree too sparse for XCTest navigation. These fixtures do not run or verify VoiceOver or Voice Control. Actual Dynamic Type checks still use the device preference and UIKit precondition.

XCUITest on iOS 27 has these quirks:

- With five tabs, the system tab bar drops every tab button's accessibility identifier, whichever tab API sets it. Find a tab by position: `app.tabBars.firstMatch.buttons.element(boundBy:)`.
- An alert action is a button inside a button with the same identifier, so `app.alerts.buttons[id]` matches two elements and the tap fails. Use `.matching(identifier:).firstMatch`.
- An identifier on a broad feature container can replace the identifier of its only exposed native action. The Consensio Lock and drawing-game Done journeys reproduced this. Put control identifiers on the actual action and screen identifiers on an inert heading when needed. Native Form rows can also be virtualized, so scroll before requiring an offscreen row to exist.

### Dead ends in test speed

Each of these cost a 3 to 10 minute test run to learn. Don't retry them.

- `-parallel-testing-enabled YES` clones the shared simulator, even with one worker, and was slower anyway, because almost every unit test is `@MainActor`. The test wrapper passes `-parallel-testing-enabled NO`, so never run `xcodebuild test` without it.
- The 2 ms `Task.sleep` in the game simulations' `pump()` is needed. With `Task.yield()` the seeds fail at once.
- Simulation seeds run 4 at a time (`SimReport.play`). With 10 or more at once the main actor starves and Draw & Guess seeds fail falsely.
- If xcodebuild hangs after "Executed N tests", the simulator the run used is in a bad state. Take it with `scripts/lock acquire "<name>"`, then `xcrun simctl shutdown` and `boot` it.

## iOS Build And Test Commands

Agents build, run tests and drive the app themselves to prove a change works. Work in your own git worktree off `main`, and run every build and test through the wrappers below.

Before you queue a build or a test run, run `scripts/app-typecheck`. It type-checks the app files your worktree changed from `main` against the whole app target, in about 15 seconds and outside the build queue. Name files to check only those, or pass `--all` to check every app file in about a minute. Use `--all` after you change a signature, because the default reports errors only in the files it checks. It needs one earlier build in the worktree, passed or failed, and it skips files outside the app target, such as tests. A String Catalog key you added works at once. A new image or color gets its symbol at the next build.

To fix a compiler warning or error that reading the code can't settle, reproduce it in a small standalone file and run `scripts/swift-typecheck <file>`. It uses the app target's Swift settings and finishes in seconds. Try candidate fixes in the same file.

Drive the app on the shared simulator to see a change that shows on screen, such as a layout, animation, or navigation change. Physical unit tests use only the approved spare selected by `ios-agent`; keep UI scenarios and fixtures on the simulator. [Devices And Simulators](../../AGENTS.md#devices-and-simulators) names the simulators to use. To see a screen that a developer scenario shows, run `scripts/scenario-screenshot <scenario-id> --out <file.png>`. It builds, takes a simulator, launches the scenario, saves the screenshot and gives the simulator back. Run it with your change stashed and again without it for a before and after. To see how a change moves, run `scripts/scenario-record <scenario-id>`, which [Checking how a change moves](#checking-how-a-change-moves) describes.

Run the iOS tests that cover your change. Backend tests are fine to run any time.

Run these wrappers from the repository root:

```bash
./scripts/xcode-build-agent.sh
./scripts/xcode-test-agent.sh
```

`xcode-test-agent.sh` runs only the unit tests. Add `--ui` to run the UI tests too, or pick tests with `-- -only-testing:<target>/<suite>`.

The Mac's `ios-agent` controller serializes CLI builds and tests, defaults Xcode to six jobs, and exposes connected phones through `./scripts/xcode-test-agent.sh --devices`. Audited device-safe test selections prefer the approved spare when it is ready. Full suites and UI fixtures use a shared simulator. `Shared iPhone` stays booted, and `Shared iPhone 2` and `Shared iPhone 3` boot only while the ones before them are busy.

The controller source is `scripts/ios-agent`. Every agent on this Mac runs the installed copy, and the post-merge and post-commit hooks install a change when it lands on `main`. `./scripts/ios-agent install-user` does the same by hand. It installs what `HEAD` of `main` commits, after that commit's `scripts/test-ios-agent.py` passes, and refuses a `main` whose history of the file does not contain the installed copy. `ios-agent status` says when the installed copy differs from `main`. On a new Mac, install its prepared launchers with `sudo install -m 755 ~/.local/lib/ios-agent/xcodebuild ~/.local/lib/ios-agent/xcrun /usr/local/bin/`. Keep `/usr/local/bin` before `/usr/bin` in `PATH`. Absolute Xcode binaries and builds launched from the Xcode app bypass this CLI controller.

Installation also enables the `no.hkarlsen.ios-agent` launch agent. Every 30 seconds it looks for extra shared simulators that lack an explicitly enabled, live reservation. It shuts one down after five minutes without a reservation, or at once when the kernel reports critical memory pressure. The warning level does not count, because a second booted simulator alone puts this Mac there. A boot takes about 45 seconds and five cores, and nearly half of the runs on an extra simulator start within five minutes of the last. The simulator lock registers those reservations before booting an extra slot. Logs are in `~/Library/Logs/ios-agent.log`.

`XCODE_BUILD_AGENT_ACTION=build-for-testing ./scripts/xcode-build-agent.sh` also compiles the test targets. The pre-push hook runs it when Swift files change. CI runs it with `XCODE_BUILD_AGENT_FAIL_ON_WARNINGS=1`, so any compiler warning fails the iOS job.

The project compiles with `MemberImportVisibility`, so a file that uses a member from PencilKit, StoreKit, SwiftData or a similar module must import that module itself. `@testable import PaeoniaApp` does not bring it in. After a bulk trim of Swift files, put back any import removed from a file that still exists, look for orphaned attributes such as a `@Test(arguments:)` with no function under it, and run `build-for-testing`. SwiftLint catches neither. When you pipe a wrapper's output, use `set -o pipefail`: the wrapper prints `STATUS: FAILURE`, but the pipe still exits 0.

Agents in every worktree and every repo on this Mac share three simulators. `Shared iPhone` stays booted. `Shared iPhone 2` and `Shared iPhone 3` boot only while the ones before them are busy, and stay booted for five minutes after their release. The user can make the pool smaller with `IOS_AGENT_SIMULATORS=1` or `2`. `scripts/lock` has one machine-wide lock per simulator, in `/tmp/agent-locks`, and Tidex's `scripts/lock` takes the same locks. `scripts/lock acquire simulator` takes a free one, prints its name and boots it if needed. [Devices And Simulators](../../AGENTS.md#devices-and-simulators) says how to drive one by hand. `scripts/lock status` shows who holds each one.

`xcode-test-agent.sh` runs in two phases. It builds for testing in the machine-wide build queue, which `ios-agent` owns, then tests. Unit tests prefer the approved spare returned by `ios-agent physical-destination`. UI tests, simulator fixtures and an unavailable spare use a shared simulator under its lock. `./scripts/xcode-test-agent.sh --devices` reports discovery and eligibility. An explicit `XCODE_TEST_AGENT_DESTINATION` remains authoritative. Physical app data is preserved. A test run does not wait in the build queue, so one agent tests while another compiles. Test runs on the same phone wait for each other. `xcode-build-agent.sh` waits only in the build queue. Agents in every repo share that queue, first come, first served, so one build runs on this Mac at a time. `ios-agent status` lists who is building, who waits and who holds each simulator. A wrapper that has to wait prints `queued for build: position 2 of 3; running now: Tidex/t3-1a2b3c build since 14:02:10`, or `[lock] waiting.` with the holder of the simulator. A build or phone test run that holds its queue for more than 30 minutes while others wait is stopped and exits 124. A waiting run that a tool timeout ends keeps its place for 15 minutes, so start it again. Its last line is the summary, for example `SUMMARY: SUCCESS queued=312s compiled=95s tested=140s simulator="Shared iPhone 2"`. `queued` is the time it waited in the build queue, for a simulator or phone, and for a simulator to boot. `--json` puts the same fields in the JSON. xcodebuild runs at lower CPU priority with two compile jobs. `XCODE_AGENT_JOBS` accepts positive integers; the user can override it, `XCODE_AGENT_NICE` and `IOS_AGENT_HOLD_LIMIT_MINUTES`. `scripts/scenario-screenshot` compiles through the same queue before acquiring a simulator.

### Signing a simulator in

The app offers only Apple and Google sign-in. The test couple lives on the development Clerk instance, which only local backends trust, so start `scripts/local-backend` in your worktree, then build and install the app from that worktree. To sign the simulator into one of the two test accounts, run:

```bash
scripts/sim-sign-in "<simulator name or UDID>" <first|second>
```

`first` is Shared and `second` is Panci, the test couple. `scripts/local-backend` runs `scripts/test-couple`, which creates them, onboards them with a photo, gives Shared a test grant and pairs them. The session stays in the simulator's keychain, so this is needed once per simulator. Add `--reset` to switch a simulator to the other account.

### Testing a branch's backend changes

A deploy replaces every function on `api.paeonia.no`, so a deploy from one branch removes what another branch deployed. Never deploy a branch there. Test it end to end against a local backend started from its own worktree:

1. Run `scripts/local-backend` from the worktree root and keep it running, for example as a background command. The first run copies the hosted data, so both test accounts are paired. It writes the untracked `ios/local.xcconfig`, which points Debug builds of this worktree at the local backend. `backend/AGENTS.md` has the details.
2. Take a simulator for the whole session with `SIM="$(scripts/lock acquire simulator)"`, so no other worktree installs over your build. Then build the Debug app from this worktree and install it on `"$SIM"`. The backend URL is fixed at build time, so a build from another worktree or from before step 1 still talks to `api.paeonia.no`. Installing over an earlier build keeps the app's local data, so run `xcrun simctl uninstall "$SIM" no.paeonia.app` first when the app last ran against a different backend. Do not erase the simulator.
3. Sign in with `scripts/sim-sign-in`. It only talks to Clerk to sign in, so the same command works for a local backend.

The simulator reaches the Mac's `127.0.0.1` directly, and App Transport Security allows plain `http` to it, so the app needs no exception. Delete `ios/local.xcconfig` and rebuild to point the worktree's Debug builds back at `api.paeonia.no`.

Only `main` is deployed to `api.paeonia.no`, with `scripts/deploy-backend`, after the branch is merged.

### Checking how a change moves

A screenshot looks the same whether a change animates or cuts. Record the scenario instead:

```bash
scripts/scenario-record <scenario-id> [--out <dir>] [--then '<command>'] [--seconds <n>] [--wait <n>] [--no-build]
```

It builds, takes a simulator, installs, records the screen and uninstalls, like `scripts/scenario-screenshot`. It then prints one line for each stretch of change in the recording, in time order, and the output folder last:

```text
action ran from 0.08 to 5.69 s
1  5.74-6.11 s  MOTION  0.38 s over 21 changed frames, 2% of the screen, box x=72 y=283 1074x1025, longest gap between frames 28 ms
```

- `MOTION` is change spread over several frames. The line gives its duration, its frame count and the box that changed. A `JUMP` note names one frame that changed far more than the frames around it.
- `CUT` is a change between two frames with nothing in between. A missing animation shows as a `CUT`. A `MOTION` that `starts ... after the cut` in the line above is a snap followed by a glide, or a screen that appeared and then animated.
- `FLASH` is a change that went back within a few frames.

The lines say what the recording shows. A `CUT` is a bug only where the screen should have animated, so compare the lines with what you meant to build.

**An animation that plays when the screen opens.** Run the command with no `--then`. It records the launch for 20 s, so the first lines are the system's launch animation, the launch screen and the scenario appearing. Your motion is among the last lines.

**An animation that follows a tap.** The tap tool is bound to one simulator, so hold that simulator for the whole session:

1. Take a simulator with `SIM="$(scripts/lock acquire simulator)"` and open it with `device_open`.
2. Run one command with the returned `agent-device`, such as `open com.apple.Preferences`. Its first command on a simulator can take a minute, and a tap sent then may not land.
3. Run `scripts/scenario-record <scenario-id> --then '<agent-device> open no.paeonia.app && <agent-device> press <x> <y>'`. It waits until the scenario is on screen and still, starts recording and runs the command. `press` takes points, which are the screenshot's pixels divided by 3. The `action ran` line says when the command ran, and your motion is the line after it. When nothing follows it, the tap did not land.
4. Repeat step 3 for the before and after. The script leaves a simulator you already held with you. Close the device and run `scripts/lock release simulator` when you are done.

`--then` refuses to run when the worktree holds no simulator. A lock the script took itself could be a different simulator from the one your tap tool is open on, and the tap would then land on another agent's screen.

**Before and after.** Run it with your change stashed and again without, with a different `--out`, and quote both lines. `--no-build` reuses the last build for another recording of the same code. A recording takes 30 to 90 s without the build.

The output folder holds `recording.mp4` and two kinds of picture. Read them when a line does not settle the question:

- `segment-<n>.png` shows the real frames of line `n`, left to right.
- `segment-<n>-slit.png` is a slit-scan of a `MOTION`. It takes one strip of pixels along the path of the motion from every frame and lays the strips side by side in time order, so position against time shows as a curve. An ease bends at both ends, a constant speed is a straight line, and a jump is a break in the curve.

Limits:

- A recording launches the scenario with `-paeonia-scenario-assistive-technology none`. A tap tool is an accessibility client, and without the argument the app would add its optional controls to the screen while you record.
- The comparison uses brightness, so it misses a change of colour at the same brightness, and a fade fainter than about two brightness levels per frame.
- A change smaller than 0.05% of the screen in a frame counts as video noise. The report says how many frames it ignored, and a small spinner is among them.
- The simulator's frame gaps do not show how a phone performs. Measure dropped frames on a device, as [Launch performance and colour](#launch-performance-and-colour) describes.
- `recordVideo` writes a frame only when the screen changes. If you analyse `recording.mp4` yourself, use the real frame times (`ffprobe -show_entries frame=pts_time`), because `fps=` resampling invents timing. Grey rectangles on a still view are recorder artifacts.

### Launch performance and colour

- Simulator launch traces overstate CPU cost. dyld_sim adds about 1.5 s, and Swift conformance scans look expensive. Judge launch speed only from a device run the developer asked for: a Release build, temporary `os_signpost` points of interest that you don't commit, and `xcrun xctrace record --template "App Launch" --instrument "Points of Interest" --device <udid> --launch -- no.paeonia.app`. Adding the HTTP Traffic instrument hangs the recording. To see dropped frames in the launch intro, record the same way with `--template "Animation Hitches"` and read its `hitches` table.
- The main thread is not idle during a launch. In November 2026 on an iPhone 17 Pro and an iPhone 18 Pro it used about 560 ms of CPU in the first 1.5 s, mostly SwiftUI updates, with 60 to 70 ms in MapLibre. The saved Home showed under the intro 165 to 250 ms after the process started.
- Measure CPU from the time-profile table with `@record-waiting-threads='0'`, since the other one counts blocked time. Its rows carry a 1 ms weight even when the run sampled every 5 ms, which xctrace reports as `requested sampling period (1000000ns) differs from configured (5000000ns)`. Multiply the sample count by the real gap between samples instead of summing weights, and prefer runs that sampled every 1 ms, since 5 ms runs read about a third higher.
- Check that each trace's `life-cycle-period` table shows `Foreground - Active` for the whole recording. A phone that locks or runs another app's tests during a run leaves the foreground early, and that run measures something else.
- The app keeps the Convex token from Clerk in the keychain for its 15 minutes (`ConvexTokenStore`). A launch within that time sends it without asking Clerk. To measure a launch that fetches a new token, wait 15 minutes after the last run, or sign out and in.
- On the simulator, the first 1 to 3 s of a cold launch show a SplashBoard snapshot from the app container. It holds sRGB pixels tagged as Display P3, so the plum and petals look more saturated until `LaunchExperienceView` draws. The `LaunchBackground` asset is not what you see, so don't fix that colour jump in the assets.
- On a device, widget pushes reload widgets only with Settings > Developer > WidgetKit Developer Mode on. Ask the developer to turn it on before blaming code. `log collect` from the phone fails over the CoreDevice tunnel, but `xcrun devicectl device copy from --domain-type appGroupDataContainer --domain-identifier group.no.paeonia.app` reads `Library/Preferences/group.no.paeonia.app.plist`.

### Refreshing the launch order file

The Release app links with `ios/Scripts/launch.order`, which lists the functions a cold launch runs so the linker places them together and the device loads fewer pages at launch. The list goes stale as code changes. A symbol that no longer exists is ignored without a warning, and a new launch function only loses the benefit. Refresh it after large launch-path changes with `ios/Scripts/generate-launch-order-file.sh`. It builds an instrumented Release copy, runs it on `Shared iPhone` while holding that simulator's lock, and puts the previously installed app back. The simulator must be signed in to a paired account. The script takes several minutes and needs no test run.

### Toolchain

The wrappers select an installed Xcode with iOS SDK 27.3 or newer through `scripts/lib/paeonia-xcode.sh`. They set `DEVELOPER_DIR` for their own process and do not change the global Xcode selection. Xcode 26.5's `actool` crashed while compiling the Icon Composer icon at `ios/PaeoniaApp/Resources/AppIcon/paeonia_app.icon` with `attempt to insert nil object from objects[0]`. If that error comes back, the toolchain is too old. Do not replace the layered `.icon` with a flat `AppIcon.appiconset` PNG. A flat PNG once had a transparent background and showed black in dark mode. `ASSETCATALOG_COMPILER_APPICON_NAME` stays `paeonia_app`.

Use `swiftlint --quiet` for focused Swift lint checks. Lint does not establish compilation or runtime correctness. Preserve useful wrapper diagnostics and report the actual verification result.
