# Xcode Project Setup

Use this checklist to create the Xcode-managed Paeonia project. The project should stay close to Tidex's setup unless a deviation is discussed first.

## Current State

Created:

- `ios/Paeonia.xcodeproj`
- `PaeoniaApp` target
- `PaeoniaWidgetExtension` target
- `PaeoniaNotificationService` target
- `PaeoniaAppTests` target
- `PaeoniaAppUITests` target
- shared `App` scheme
- `no.paeonia.app` bundle identifier
- iOS 26.5 minimum deployment target
- `Paeonia` display name
- app entitlements for Sign in with Apple, Associated Domains, App Groups, and Push Notifications
- widget entitlements for App Groups
- seed app and widget `Localizable.xcstrings` catalogs with generated symbol usage verified by the build wrapper

No target creation is currently pending in Xcode.

Xcode may still show local user schemes for extension targets if they were activated during target creation. The committed shared scheme remains `App`.

## Create Project

- Location: `ios/`
- Project file: `ios/Paeonia.xcodeproj`
- Product name: `Paeonia`
- Interface: SwiftUI
- Language: Swift
- Minimum deployment target: iOS 26.5
- Include tests: yes
- Use automatic signing initially.

## Targets

Create these targets from day one:

- `PaeoniaApp`
- `PaeoniaWidgetExtension`
- `PaeoniaNotificationService`
- `PaeoniaAppTests`
- `PaeoniaAppUITests`

Use shared scheme:

- `App`

## Bundle IDs

- Main app: `no.paeonia.app`
- Widget: `no.paeonia.app.widget`
- Notification service: `no.paeonia.app.notification-service`

## Capabilities

Main app:

- Sign in with Apple
- Associated Domains
- App Groups
- Push Notifications

Widget:

- App Groups

Notification service:

- No extra capability by default unless Xcode or APNs setup requires it.

## Entitlements

Associated Domains:

```text
applinks:paeonia.no
```

App Group:

```text
group.no.paeonia.app
```

## Build Settings

Apply the shared xcconfigs:

- Debug configuration includes `ios/debug.xcconfig`
- Release configuration includes `ios/release.xcconfig`

Ensure String Catalog symbol generation is enabled:

```text
STRING_CATALOG_GENERATE_SYMBOLS = YES
```

## Folder Structure

Create or preserve:

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

Feature code should live under `Features/<FeatureName>/`. Move code to `Shared/` only when it is genuinely reused.

## Localization

Create String Catalogs from the start:

- English
- Norwegian Bokmal

Rules:

- Use generated `LocalizedStringResource` symbols.
- Do not use raw localization keys.
- Add keys with dot notation so symbols generate cleanly.

## After Project Creation

Run:

```bash
pnpm open-ios
./scripts/xcode-build-agent.sh --json
```

The shared App scheme and the repository build/test wrappers generate the
git-ignored `ios/BuildNumber.xcconfig` before Xcode evaluates build settings.
Keep using that timestamp-based setup for builds and archives; do not commit a
static `CURRENT_PROJECT_VERSION`.

If the build wrapper fails because schemes or target names differ, fix the project setup rather than changing the wrapper away from Tidex conventions.
