# Paeonia iOS

Native iOS app workspace for the Paeonia app, widget, notification service extension, and test targets.

Locked foundation decisions:

- Minimum deployment target: iOS 26.5
- Initial targets:
  - app
  - widget
  - notification service extension
  - unit tests
  - UI tests
- Auth surfaces:
  - Sign in with Apple
  - Google Sign-In
- Associated Domains:
  - `applinks:paeonia.no`
- URL scheme:
  - `paeonia://`
- Localization:
  - English
  - Norwegian Bokmal
  - Xcode String Catalogs
  - generated `LocalizedStringResource` symbols only

Project setup rule:

- Use an Xcode-managed `.xcodeproj`, matching Tidex.
- Keep the setup nearly identical to Tidex.
- Discuss improvements or deviations before applying them.

Known app configuration:

- Display name: `Paeonia`
- Bundle ID: `no.paeonia.app`
- Widget bundle ID: `no.paeonia.app.widget`
- Notification service bundle ID: `no.paeonia.app.notification-service`
- App Group: `group.no.paeonia.app`
- App URL scheme: `paeonia`

Target names:

- Main app target: `PaeoniaApp`
- Widget target: `PaeoniaWidgetExtension`
- Notification service target: `PaeoniaNotificationService`
- Unit tests: `PaeoniaAppTests`
- UI tests: `PaeoniaAppUITests`
- Shared app scheme: `App`
- Shared developer-state scheme: `Scenarios` (Debug-only)

Folder structure should follow the Tidex feature-first pattern:

```text
ios/PaeoniaApp/
├── App/
├── Features/
├── Services/
├── Storage/
├── Models/
├── Shared/
├── Resources/
└── Supporting/
```

Tidex-style support files already exist:

- `Version.xcconfig`
- `debug.xcconfig`
- `release.xcconfig`
- `.swiftlint.yml`
- root `scripts/xcode-build-agent.sh`
- root `scripts/xcode-test-agent.sh`

The shared App and Scenarios schemes and both Xcode wrappers run
`scripts/generate-ios-build-number.sh` before Xcode evaluates the build. The
generated `ios/BuildNumber.xcconfig` stays git-ignored; do not commit a build
number or replace this with a static `CURRENT_PROJECT_VERSION`.

## Developer scenarios

Use the `Scenarios` scheme to open a production screen with deterministic local
state, without creating accounts, pairing, purchasing access, or contacting the
production backend.

To browse the catalog in Xcode:

1. Choose `Scenarios` from the scheme menu in the Xcode toolbar.
2. Choose an iPhone simulator or connected development device.
3. Run the app. Select a scenario from the catalog.
4. Use the wrench button to return to the catalog.

To launch one scenario directly in Xcode:

1. Choose **Product > Scheme > Edit Scheme…**.
2. Select the `Scenarios` scheme, then **Run > Arguments**.
3. Under **Environment Variables**, add `PAEONIA_SCENARIO` and set its value to
   the scenario ID shown in monospace under the scenario's name in the catalog,
   such as `questions`, `paywall-trial`, or `memories-populated`.
4. Enable the variable and run. Disable or remove it to return to the catalog on
   the next launch.

UI tests use the same contract:

```swift
let app = XCUIApplication()
app.launchEnvironment["PAEONIA_SCENARIO"] = "questions"
app.launch()
```

Unknown scenario IDs intentionally open the catalog instead of falling through
to the production app. The normal `App` scheme remains the production launch
path.

State scenarios are deterministic snapshots. Scenarios under **Interactive local
flows** use the production root and support local sign-in, onboarding, simulated
purchase, pairing, and paired feature interactions. See
`docs/developer-scenario-harness.md` for behavior, safety boundaries, reset controls,
and the required pattern for future features.
