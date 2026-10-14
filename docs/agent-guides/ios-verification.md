# iOS verification

## Testing Requirements

Agents should add or update tests when implementing behavior.

### Default Rule

- Feature work should include test coverage for changed behavior, not just compile-clean code.
- If behavior changes and no tests are added, explain why in the final handoff.

### What To Test

- Happy path: primary user flow works and returns expected values.
- Edge cases: invalid input, empty states, timezone boundaries, date changes, offline states.
- Regression guard: at least one test that would fail if the changed logic was removed.
- Bug fixes: add a test that reproduces the bug when feasible.

### Important Test Areas

- prompt reveal logic
- streak and streak repair logic
- countdown date math
- timezone behavior
- notification scheduling
- couple pairing state
- memory timeline ordering
- local save/load behavior
- sync conflict behavior
- widget payload generation
- privacy/export/delete flows

### Where To Place Tests

- Business logic, repositories, services, sync, and view models: `ios/PaeoniaAppTests/`
- UI launch/smoke and critical interactions: `ios/PaeoniaAppUITests/`

Prefer small focused unit tests over broad UI tests unless behavior is UI-only.

## iOS Build And Test Commands

Agents do not build just to check that a change compiles. The developer runs several agents in parallel and builds on their own device, which catches compile errors and warnings. Extra agent builds slow that loop down and fight over the simulator and DerivedData. Do not work around this with scratch copies of the repo or loops that wait for another agent's build.

Building and running the app on a device is fine when the task needs to see runtime behavior that reading the code can't settle, such as a layout, animation, or navigation bug. Use a connected device, or the shared simulator when none is connected, as [Devices And Simulators](../../AGENTS.md#devices-and-simulators) describes.

Do not run tests without asking. If you think a test run is needed, ask the developer. They run tests once all agents have finished. In the handoff, list what you did not verify and what to check on the device.

The developer uses these wrappers from the repository root:

```bash
./scripts/xcode-build-agent.sh
./scripts/xcode-test-agent.sh
```

`XCODE_BUILD_AGENT_ACTION=build-for-testing ./scripts/xcode-build-agent.sh` also compiles the test targets. The pre-push hook runs it when Swift files change.

Agents in other worktrees share the connected device and the `Shared iPhone` simulator. `xcode-test-agent.sh` holds the `simulator` lock while it runs, and waits when another worktree holds it. For a simulator session of several commands, such as `sim-sign-in` and end-to-end play, take the lock with `scripts/lock acquire simulator`, release it with `scripts/lock release simulator`, and see who holds what with `scripts/lock status`.

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
