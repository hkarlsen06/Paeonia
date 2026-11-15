# Developer scenario harness

The Debug-only `Scenarios` scheme provides two complementary testing tools. Neither
tool is allowed to contact production services.

## State scenarios

A state scenario opens one production screen or component with deterministic data. It may make destructive or external actions no-ops, but it must render the production view rather than recreating part of its layout.

## Interactive local flows

The **Interactive local flows** catalog section runs the real `RootView`,
`RootViewModel`, access resolver, and feature views. Only external boundaries are
replaced with in-memory implementations.

The catalog lists each flow's starting state. `local-flow-pairing` has no simulated partner joining.

The purchase button grants local entitlement, invite acceptance creates the local
relationship, sign-out and deletion clear the local session, leaving the
relationship returns to pairing, notification preferences mutate in memory, memory
edits use an in-memory repository, and daily answers use the normal local-first
queue. No sign-in sheet, StoreKit transaction, APNs registration, Convex request,
or production write occurs.

The circular-arrow control resets the active scenario to its original seed. The
wrench returns to the catalog without losing the catalog's scroll position.

## Launching

Choose the shared `Scenarios` scheme in Xcode and open the catalog. To skip the catalog, set `PAEONIA_SCENARIO=<scenario id>` under Edit Scheme > Run > Arguments > Environment Variables. The ID is shown in monospace under each scenario's name. UI tests set the same variable on `XCUIApplication`. An unknown ID opens the catalog. A local flow also reads `PAEONIA_LAUNCH_LINK`, such as `paeonia://recap/2026-09-14`, and starts with that link, the way a push tapped while the app was closed does.

## Contract for future features

Every new user-facing feature must decide which coverage it needs:

1. Add state scenarios for materially different first-frame states: loading,
   content, empty, recoverable error, offline/pending, and permission denial where
   applicable.
2. Add the feature's real view to an interactive local flow when the user can mutate
   it or when it participates in root routing.
3. Put external work behind a protocol and inject the protocol at the feature or
   root composition boundary. The local implementation must be deterministic and
   stateful enough for subsequent screens to observe the mutation.
4. Reuse the production view and view model. Never rebuild a subset of the screen in
   a developer-only view; that hides real controls and inevitably drifts.
5. Route local writes through the same repository, queue, or view-model method as
   production. Replace only the remote endpoint, platform authorization, or opaque
   StoreKit or sign-in result.
6. Ensure reset constructs a fresh dependency graph. Do not share scenario state
   with `UserDefaults`, the production local store, App Groups, keychain, or files.
7. Give important controls stable accessibility identifiers and add one UI test
   for each new cross-screen journey in a local flow. This is one of the testing
   rules in the root `AGENTS.md`.
8. Keep the `App` scheme as the live configured app.

Feature dependencies that must reach routed screens belong in
`RootFeatureDependencies`. Small focused views can continue using initializer
injection directly. If adding a dependency requires copying production UI into the
harness, the dependency boundary is in the wrong place.

## Safety checklist

Before adding or changing a scenario, verify:

- The scenario is compiled only in Debug.
- Convex, Clerk, StoreKit, APNs, App Groups, and production persistence cannot be
  reached from the injected dependency graph.
- Interactive mutations are observable after navigation or refresh.
- The corresponding production initializer still uses its normal live default.
- The scenario can be reset and launched directly by ID.
