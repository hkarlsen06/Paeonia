# Paeonia iOS

Native iOS app workspace for the app, widget, notification service extension, and test targets.

Project setup rule: use an Xcode-managed `.xcodeproj`, matching Tidex. Keep the setup nearly identical to Tidex, and discuss deviations before applying them.

Foundation decisions: minimum deployment target iOS 27.0, Sign in with Apple and Google Sign-In only, `applinks:paeonia.no`, URL scheme `paeonia://`, English and Norwegian Bokmal with generated String Catalog symbols.

The shared `App` scheme and the Debug-only `Scenarios` scheme, and both Xcode wrappers, run
`scripts/generate-ios-build-number.sh` before Xcode evaluates the build. The
generated `ios/BuildNumber.xcconfig` stays git-ignored. Do not commit a build
number or replace this with a static `CURRENT_PROJECT_VERSION`.

## Developer scenarios

The `Scenarios` scheme opens a production screen with deterministic local state, without accounts, pairing, purchases or the hosted backend. [docs/developer-scenario-harness.md](../docs/developer-scenario-harness.md) says how to launch one and the rules for adding one. An unknown `PAEONIA_SCENARIO` ID opens the catalog, never the production app.
