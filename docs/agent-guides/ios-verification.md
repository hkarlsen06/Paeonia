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

During interactive debugging where the user is rebuilding in Xcode, avoid duplicate builds and tests. Otherwise run focused checks appropriate to the change, fix failures caused by the change, and rerun affected checks. Broaden verification only when risk or failures justify it. Report any remaining unverified behavior.

Use the existing repository wrappers for iOS builds and tests, rather than raw `xcodebuild`. Run commands from the repository root. A wrapper failure is a diagnostic to investigate within scope, not a reason to bypass it.

Build and test commands:

```bash
./scripts/xcode-build-agent.sh
./scripts/xcode-test-agent.sh
```

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
