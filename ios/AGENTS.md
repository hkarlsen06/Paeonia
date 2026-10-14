# Paeonia iOS agent guidance

Use SwiftUI, feature-first organization, and the existing MVVM/storage boundaries. Keep business logic outside views. Follow the root product and privacy constraints.

- For architecture, state, persistence, concurrency, or readiness changes, read [iOS architecture](../docs/agent-guides/ios-architecture.md). Loading keys must exclude cosmetic identity updates; preserve stable first presentation and offline content.
- For user-facing copy or catalog edits, read [localization](../docs/agent-guides/ios-localization.md). Use generated String Catalog symbols, English and Norwegian Bokmal, and translator comments.
- For visual or interaction changes, read [design](../docs/agent-guides/ios-design.md). Preserve the single plum theme, semantic tokens, Dynamic Type, Reduce Motion, contrast, VoiceOver, and the established wordmark, banner, and confirmation surfaces.
- For behavior changes or test work, read [verification](../docs/agent-guides/ios-verification.md). Do not build just to check that code compiles, and ask before any test run. Runs on a device are fine when you need to see runtime behavior. The root AGENTS.md says which device or simulator to use.
- For auth, RPC, or backend client changes, read [backend guidance](../backend/AGENTS.md), including the function contracts and explicit authorization checks. Live data arrives through ConvexMobile subscriptions (see "Live data" below). Writes and one-shot reads go over the HTTP API through `PaeoniaShared/PaeoniaConvexClient.swift` (`POST /api/query`, `/api/mutation` and `/api/action`, with the Clerk session token as the bearer). `PaeoniaShared/PaeoniaClerk.swift` configures Clerk for the app and widget. Backend function names and argument names (`p_` prefix) are the contract, so rename them on both sides together.

Paths and commands in the linked guides are relative to the repository root. Read relevant details rather than all guides for every edit.

## Live data

- Convex subscriptions hydrate the local store. They never feed views directly. View models re-read the store when `LocalStoreChanges.changes(in:)` reports a write, and they keep reading local data first.
- Writes keep going through the pending-operation outbox and `PaeoniaConvexClient`. One-shot reads use `query`, writes use `mutation`.
- `LiveQueryService.subscribe(_:args:as:)` (`PaeoniaApp/Services/Live`) returns an `AsyncStream<LiveResult<T>>` and resubscribes with backoff. It decodes with `PaeoniaConvexClient.decoder`, so `Remote*` DTOs work unchanged. Pass `Double` for `v.number()` arguments and omit optional keys instead of passing `nil`.
- A live feed is a `LiveFeed` that runs subscriptions for a `SyncSession` and writes results into a repository or cache. Register it with one line in `LiveFeedRegistry.makeFeeds`. `LiveSyncCoordinator` restarts feeds when the session changes, and stops them on sign-out and around a privacy purge. A feed must stop writing once its task is cancelled.
- Repositories call `LocalStoreChanges.post` after each committed write. Add the call to any new shared repository.
- Never call `logout()` on the live Convex client. It signs out of Clerk. Sign out through Clerk and the client follows.
- The widget extension and notification extension stay HTTP-only. Do not link ConvexMobile or ClerkConvex into them.
- The ConvexMobile static library has no x86_64 simulator slice, so the project excludes x86_64 for simulator builds.
