# iOS verification

## Testing rules

The root [AGENTS.md](../../AGENTS.md#testing) says when a change needs a test. Agents do not add tests otherwise.

### Where tests go

- `ios/PaeoniaAppUITests/`: user journeys through the production root. Launch an interactive local flow with `app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-<seed>"` and find controls by accessibility identifier, never by copy, so the tests pass in any language. Add an identifier to the control when it has none. `AccountJourneyUITests` and `PaeoniaAppUITests` show the pattern.
- `ios/PaeoniaAppTests/`: integration tests that wire a real view model, repository and local store with a fake only at the network or OS boundary, the two-phone game simulations under `Games/Simulation/` and `Games/ExquisiteCorpse/Simulation/`, and unit tests for the pure logic the root rules list.

Prefer the UI test when the bug would show on screen, and the integration test when it would show in what is stored or sent. A unit test of a view model's loading flag, banner text or animation timing catches nothing that the device check misses.

XCUITest on iOS 27 has two quirks:

- With five tabs, the system tab bar drops every tab button's accessibility identifier, whichever tab API sets it. Find a tab by position: `app.tabBars.firstMatch.buttons.element(boundBy:)`.
- An alert action is a button inside a button with the same identifier, so `app.alerts.buttons[id]` matches two elements and the tap fails. Use `.matching(identifier:).firstMatch`.

### Dead ends in test speed

Each of these cost a 3 to 10 minute test run to learn. Don't retry them.

- `-parallel-testing-enabled YES` clones the shared simulator, even with one worker, and was slower anyway, because almost every unit test is `@MainActor`. The test wrapper passes `-parallel-testing-enabled NO`, so never run `xcodebuild test` without it.
- The 2 ms `Task.sleep` in the game simulations' `pump()` is needed. With `Task.yield()` the seeds fail at once.
- Simulation seeds run 4 at a time (`SimReport.play`). With 10 or more at once the main actor starves and Draw & Guess seeds fail falsely.
- If xcodebuild hangs after "Executed N tests", the simulator the run used is in a bad state. Take it with `scripts/lock acquire "<name>"`, then `xcrun simctl shutdown` and `boot` it.

## iOS Build And Test Commands

Agents build, run tests and drive the app themselves to prove a change works. Work in your own git worktree off `main`, and run every build and test through the wrappers below.

To fix a compiler warning or error that reading the code can't settle, reproduce it in a small standalone file and run `scripts/swift-typecheck <file>`. It uses the app target's Swift settings and finishes in seconds. Try candidate fixes in the same file.

Drive the app on the shared simulator to see a change that shows on screen, such as a layout, animation, or navigation change. Never use a connected iPhone or iPad. [Devices And Simulators](../../AGENTS.md#devices-and-simulators) names the simulators to use.

Run the iOS tests that cover your change. Backend tests are fine to run any time.

Run these wrappers from the repository root:

```bash
./scripts/xcode-build-agent.sh
./scripts/xcode-test-agent.sh
```

`xcode-test-agent.sh` runs only the unit tests. Add `--ui` to run the UI tests too, or pick tests with `-- -only-testing:<target>/<suite>`.

`XCODE_BUILD_AGENT_ACTION=build-for-testing ./scripts/xcode-build-agent.sh` also compiles the test targets. The pre-push hook runs it when Swift files change. CI runs it with `XCODE_BUILD_AGENT_FAIL_ON_WARNINGS=1`, so any compiler warning fails the iOS job.

The project compiles with `MemberImportVisibility`, so a file that uses a member from PencilKit, StoreKit, SwiftData or a similar module must import that module itself. `@testable import PaeoniaApp` does not bring it in. After a bulk trim of Swift files, put back any import removed from a file that still exists, look for orphaned attributes such as a `@Test(arguments:)` with no function under it, and run `build-for-testing`. SwiftLint catches neither. When you pipe a wrapper's output, use `set -o pipefail`: the wrapper prints `STATUS: FAILURE`, but the pipe still exits 0.

Agents in every worktree and every repo on this Mac share three simulators, `Shared iPhone`, `Shared iPhone 2` and `Shared iPhone 3`. `scripts/lock` has one machine-wide lock per simulator, in `/tmp/agent-locks`, and Tidex's `scripts/lock` takes the same locks. `scripts/lock acquire simulator` takes a free one, prints its name and boots it if needed. [Devices And Simulators](../../AGENTS.md#devices-and-simulators) says how to drive one by hand. `scripts/lock status` shows who holds each one.

`xcode-test-agent.sh` runs in two phases. It builds for testing under the machine-wide xcodebuild lock, `/tmp/xcode-agent.lock`, and releases it. Then it tests under one simulator's lock: the one your worktree holds, else the first free one. So another agent compiles while your tests run. `xcode-build-agent.sh` holds only the xcodebuild lock. Tidex, Kvil and Notex agents take the same xcodebuild lock, so one agent's build runs on this Mac at a time. A wrapper that has to wait prints `waiting for another agent's xcodebuild to finish` or `[lock] waiting.` with the holder. Its last line is the summary, for example `SUMMARY: SUCCESS queued=312s compiled=95s tested=140s simulator="Shared iPhone 2"`. `queued` is the time it waited for both locks and for a simulator to boot. `--json` puts the same fields in the JSON. xcodebuild runs at lower CPU priority. Set `XCODE_AGENT_NICE` or `XCODE_AGENT_JOBS` to change that.

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

### Checking short animations

Reading the code does not show how a motion under two seconds looks. Record it on the simulator and read the frames:

1. Build into a scratch `-derivedDataPath` under `/tmp` without the lock. Then take a simulator with `SIM="$(scripts/lock acquire simulator)"`, install, and start `xcrun simctl io "$SIM" recordVideo <file>.mp4`.
2. Launch the developer scenario with `-paeonia-scenario <id> -paeonia-scenario-hide-controls YES`. Scenario screens fade in, which hides the first 0.3 s. To tap through a flow while recording, drive the app with `agent-device` (`open no.paeonia.app --relaunch --launch-args -paeonia-scenario --launch-args <id>`, `click 'label="..."'`, `press x y`). A tap can land 1 to 3 s after the command, so record for at least 6 s. `@e` refs go stale after a relaunch, so use `press` or `click 'label="..."'`.
3. `recordVideo` writes a frame only when the screen changes, so `fps=` resampling invents timing. List the real frames with `ffprobe -show_entries frame=pts_time`, find the action in a 4 fps overview, then tile the real frames with `ffmpeg -vf "select='between(t,a,b)',crop=...,tile=8x5" -fps_mode passthrough` and read the sheets. Measure positions numerically, for example bright-row runs per frame in Python, instead of judging by eye. Grey rectangles on a static view are recorder artifacts.
4. Release the lock and delete the scratch folder.

### Launch performance and colour

- Simulator launch traces overstate CPU cost. dyld_sim adds about 1.5 s, and Swift conformance scans look expensive. On the developer's iPhone the launch waited on the network with the main thread nearly idle. Judge launch speed only from a device run the developer asked for: a Release build, temporary `os_signpost` points of interest that you don't commit, and `xcrun xctrace record --template "App Launch" --instrument "Points of Interest" --device <udid> --launch -- no.paeonia.app`. Adding the HTTP Traffic instrument hangs the recording. For CPU, read the time-profile table with `@record-waiting-threads='0'`, since the other one counts blocked time. Space runs 70 s apart so the Clerk token expires.
- On the simulator, the first 1 to 3 s of a cold launch show a SplashBoard snapshot from the app container. It holds sRGB pixels tagged as Display P3, so the plum and petals look more saturated until `LaunchExperienceView` draws. The `LaunchBackground` asset is not what you see, so don't fix that colour jump in the assets.
- On a device, widget pushes reload widgets only with Settings > Developer > WidgetKit Developer Mode on. Ask the developer to turn it on before blaming code. `log collect` from the phone fails over the CoreDevice tunnel, but `xcrun devicectl device copy from --domain-type appGroupDataContainer --domain-identifier group.no.paeonia.app` reads `Library/Preferences/group.no.paeonia.app.plist`.

### Refreshing the launch order file

The Release app links with `ios/Scripts/launch.order`, which lists the functions a cold launch runs so the linker places them together and the device loads fewer pages at launch. The list goes stale as code changes. A symbol that no longer exists is ignored without a warning, and a new launch function only loses the benefit. Refresh it after large launch-path changes with `ios/Scripts/generate-launch-order-file.sh`. It builds an instrumented Release copy, runs it on `Shared iPhone` while holding that simulator's lock, and puts the previously installed app back. The simulator must be signed in to a paired account. The script takes several minutes and needs no test run.

### Toolchain

Build with the selected Xcode, `/Applications/Xcode.app` (Xcode 27.1). The wrappers need no `DEVELOPER_DIR`. Xcode 26.5's `actool` crashed while compiling the Icon Composer icon at `ios/PaeoniaApp/Resources/AppIcon/paeonia_app.icon` with `attempt to insert nil object from objects[0]`. If that error comes back, the toolchain is too old. Do not replace the layered `.icon` with a flat `AppIcon.appiconset` PNG. A flat PNG once had a transparent background and showed black in dark mode. `ASSETCATALOG_COMPILER_APPICON_NAME` stays `paeonia_app`.

Use `swiftlint --quiet` for focused Swift lint checks. Lint does not establish compilation or runtime correctness. Preserve useful wrapper diagnostics and report the actual verification result.
