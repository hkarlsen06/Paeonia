# Paeonia iOS

Native iOS app workspace placeholder.

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
  - passkeys
- Associated Domains:
  - `applinks:paeonia.no`
  - `webcredentials:paeonia.no`
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
