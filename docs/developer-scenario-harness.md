# Developer Scenario Harness

The Debug-only `Scenarios` scheme provides two complementary testing tools. Neither
tool is allowed to contact production services.

## State scenarios

State scenarios open one production screen or component with deterministic data.
Use them for loading, empty, populated, error, offline, and edge-case visual states.
They may intentionally make destructive or external actions no-ops, but they must
render the production view rather than recreating part of its layout.

Examples: `paywall-trial`, `questions-error`, and `memories-populated`.

## Interactive local flows

The **Interactive local flows** catalog section runs the real `RootView`,
`RootViewModel`, access resolver, and feature views. Only external boundaries are
replaced with in-memory implementations.

- `local-flow-fresh`: begin signed out and use either provider button.
- `local-flow-onboarding`: begin at profile setup.
- `local-flow-paywall`: begin before the simulated subscription purchase.
- `local-flow-pairing`: begin entitled and unpaired. Create an invite, then tap
  **Check pairing** to simulate the partner joining.
- `local-flow-paired`: begin in the paired app with local questions, memories,
  settings, countdown, location, and widget dependencies.

The purchase button grants local entitlement, invite acceptance creates the local
relationship, sign-out and deletion clear the local session, leaving the
relationship returns to pairing, notification preferences mutate in memory, memory
edits use an in-memory repository, and daily answers use the normal local-first
queue. No OAuth sheet, StoreKit transaction, APNs registration, Supabase request,
or production write occurs.

The circular-arrow control resets the active scenario to its original seed. The
wrench returns to the catalog without losing the catalog's scroll position.

## Launching

For ordinary use in Xcode:

1. Choose the shared **Scenarios** scheme in the scheme selector.
2. Choose a simulator and press Run.
3. Tap any entry under **Interactive local flows** or **State · ...**.

No environment variable is needed when using the catalog. To bypass the catalog
and open one scenario on every run, choose **Product > Scheme > Edit Scheme > Run >
Arguments**, add `PAEONIA_SCENARIO` under **Environment Variables**, and set its
value to the scenario ID, for example:

```text
PAEONIA_SCENARIO=local-flow-fresh
```

UI tests use the same environment variable on `XCUIApplication`.

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
   StoreKit/OAuth result.
6. Ensure reset constructs a fresh dependency graph. Do not share scenario state
   with `UserDefaults`, the production local store, App Groups, keychain, or files.
7. Give important controls stable accessibility identifiers and add at least one UI
   regression test for each new cross-screen local flow.
8. Keep the `App` scheme as the live configured app. A future dedicated live
   integration mode must use an explicitly non-production backend and visibly name
   that environment; never relabel the production path as a test environment.

Feature dependencies that must reach routed screens belong in
`RootFeatureDependencies`. Small focused views can continue using initializer
injection directly. If adding a dependency requires copying production UI into the
harness, the dependency boundary is in the wrong place.

## Safety checklist

Before adding or changing a scenario, verify:

- The scenario is compiled only in Debug.
- Supabase, OAuth, StoreKit, APNs, App Groups, and production persistence cannot be
  reached from the injected dependency graph.
- Interactive mutations are observable after navigation or refresh.
- The corresponding production initializer still uses its normal live default.
- The scenario can be reset and launched directly by ID.
