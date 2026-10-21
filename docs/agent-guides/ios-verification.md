# iOS verification

## Testing rules

The root [AGENTS.md](../../AGENTS.md#testing) says when a change needs a test. Agents do not add tests otherwise.

### Where tests go

- `ios/PaeoniaAppUITests/`: user journeys through the production root. Launch an interactive local flow with `app.launchEnvironment["PAEONIA_SCENARIO"] = "local-flow-<seed>"` and find controls by accessibility identifier, never by copy, so the tests pass in any language. Add an identifier to the control when it has none. `AccountJourneyUITests` and `PaeoniaAppUITests` show the pattern.
- `ios/PaeoniaAppTests/`: integration tests that wire a real view model, repository and local store with a fake only at the network or OS boundary, the two-phone game simulations under `Games/Simulation/` and `Games/ExquisiteCorpse/Simulation/`, and unit tests for the pure logic the root rules list.

Prefer the UI test when the bug would show on screen, and the integration test when it would show in what is stored or sent. A unit test of a view model's loading flag, banner text or animation timing catches nothing that the device check misses.

## iOS Build And Test Commands

Agents do not build just to check that a change compiles. The developer runs several agents in parallel and builds on their own device, which catches compile errors and warnings. Extra agent builds slow that loop down and fight over the simulator and DerivedData. Do not work around this with scratch copies of the repo or loops that wait for another agent's build.

To fix a compiler warning or error that reading the code can't settle, reproduce it in a small standalone file and run `scripts/swift-typecheck <file>`. It uses the app target's Swift settings and finishes in seconds. Try candidate fixes in the same file.

Building and running the app on the shared simulator is fine when the task needs to see runtime behavior that reading the code can't settle, such as a layout, animation, or navigation bug. Never use a connected iPhone or iPad. [Devices And Simulators](../../AGENTS.md#devices-and-simulators) names the simulators to use.

Do not run iOS tests without asking. Backend tests are fine to run any time. If you think a test run is needed, ask the developer. They run tests once all agents have finished. In the handoff, list what you did not verify and what to check on the device.

The developer uses these wrappers from the repository root:

```bash
./scripts/xcode-build-agent.sh
./scripts/xcode-test-agent.sh
```

`xcode-test-agent.sh` runs only the unit tests. Add `--ui` to run the UI tests too, or pick tests with `-- -only-testing:<target>/<suite>`.

`XCODE_BUILD_AGENT_ACTION=build-for-testing ./scripts/xcode-build-agent.sh` also compiles the test targets. The pre-push hook runs it when Swift files change. CI runs it with `XCODE_BUILD_AGENT_FAIL_ON_WARNINGS=1`, so any compiler warning fails the iOS job.

Agents in other worktrees share the `Shared iPhone` simulator. `xcode-test-agent.sh` holds the `simulator` lock while it runs. It waits while any other run holds it, including one from the same worktree, since several agents can share a worktree. For a simulator session of several commands, such as `sim-sign-in` and end-to-end play, take the lock with `scripts/lock acquire simulator`, release it with `scripts/lock release simulator`, and see who holds what with `scripts/lock status`.

### Signing a simulator in

The app offers only Apple and Google sign-in. To sign the Debug build on a simulator into one of the two test accounts on `api.paeonia.no`, install the app, then run:

```bash
scripts/sim-sign-in "<simulator name or UDID>" <first|second>
```

`first` is Hjalmar and `second` is Elena, the test couple. The session stays in the simulator's keychain, so this is needed once per simulator. Add `--reset` to switch a simulator to the other account.

### Testing a branch's backend changes

A deploy replaces every function on `api.paeonia.no`, so a deploy from one branch removes what another branch deployed. Never deploy a branch there. Test it end to end against a local backend started from its own worktree:

1. Run `scripts/local-backend` from the worktree root and keep it running, for example as a background command. The first run copies the hosted data, so both test accounts are paired. It writes the untracked `ios/local.xcconfig`, which points Debug builds of this worktree at the local backend. `backend/AGENTS.md` has the details.
2. Take the `simulator` lock for the whole session, so no other worktree installs over your build. Then build the Debug app from this worktree and install it on `Shared iPhone`. The backend URL is fixed at build time, so a build from another worktree or from before step 1 still talks to `api.paeonia.no`. Installing over an earlier build keeps the app's local data, so run `xcrun simctl uninstall "Shared iPhone" no.paeonia.app` first when the app last ran against a different backend. Do not erase the simulator or create another one.
3. Sign in with `scripts/sim-sign-in`. It only talks to Clerk to sign in, so the same command works for a local backend.

The simulator reaches the Mac's `127.0.0.1` directly, and App Transport Security allows plain `http` to it, so the app needs no exception. Delete `ios/local.xcconfig` and rebuild to point the worktree's Debug builds back at `api.paeonia.no`.

Only `main` is deployed to `api.paeonia.no`, with `scripts/deploy-backend`, after the branch is merged.

### Toolchain Requirement

Build with Xcode 27.0 beta by setting `DEVELOPER_DIR` for the command or by selecting the beta globally with `xcode-select`. On macOS 27 beta, GM Xcode 26.5's `actool` crashes when compiling the app's Icon Composer icon at `ios/PaeoniaApp/Resources/AppIcon/paeonia_app.icon`.

Known bad pairing:

```bash
/Applications/Xcode.app
```

Known working beta toolchain:

```bash
DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer" ./scripts/xcode-build-agent.sh
```

Failure symptom:

```text
Exception while running actool: *** -[__NSPlaceholderArray initWithObjects:count:]: attempt to insert nil object from objects[0]
```

This is a toolchain bug, not a project icon bug. Do not replace the layered `.icon` with a flat `AppIcon.appiconset` PNG workaround; a prior flat PNG workaround had a transparent background and rendered incorrectly against black in iOS 26/27 dark mode. `ASSETCATALOG_COMPILER_APPICON_NAME` must remain `paeonia_app` so the layered icon keeps the correct plum dark-mode background.

Use `swiftlint --quiet` for focused Swift lint checks. Lint does not establish compilation or runtime correctness. Preserve useful wrapper diagnostics and report the actual verification result.
