# iOS architecture guidelines

Organize by product feature, as the existing `ios/PaeoniaApp/` folders do. Do not flatten screens into one folder or put feature details into shared modules unless they are reused. App-wide `Shared/` holds only components, extensions and design-system code that several features use.

Inside a substantial feature, use subfolders named for the responsibility they own, such as `AnswerFlow/`, `History/`, `Audio/`, `Streak/`, `Canvas/`, `Offer/` or `Invite/`, next to `Models/`, `Data/` and `Components/`. Do not create `PrimaryFlow/`, `SecondaryFlow/`, `PureLogic/` or a feature-local `Shared/`.

Use SwiftUI for all UI and interaction. If UIKit looks necessary, stop before implementing it and report why SwiftUI is insufficient, which UIKit API you would use, and the tradeoff.

Prefer initializer injection. Keep UI-facing view models on `@MainActor`, and handle task cancellation in async flows.

### One enum per lifecycle

When two or more stored properties together say what stage something is in, such as `isSending` with `sendFailed`, or a phase with flags that only matter in some phases, store one enum and derive the booleans from it. Each separate flag can be set or cleared on its own, so a code path that forgets one leaves a combination no screen expects. Reuse the shared types before you add one:

- `GameSendState` (`Features/Games/Models/`) is how a game's queued moves are doing. A game screen reads `sendState.isHeldOnPhone` or `sendState.isFailing`, never its own flags.
- `SyncRunLock` (`Services/Sync/PaeoniaSyncService.swift`) holds the sync service's one run slot. Only `finishPrivacyPurgeQuiescence` ends a privacy purge's hold.
- `MainTabView.isModalOpen` lists every sheet and cover on the tab view. A sheet or cover added there goes into that list, so moments that open by themselves wait for it.
- `ThreadChatDelivery` (`Features/Chat/ThreadChatModels.swift`) is where a chat message stands: sent, sending or failed.
- `ImageLoad<Key>` (`Services/Media/ImageLoad.swift`) is a view's photo load. It keeps the key with the image or the failure, so a reused view never shows the last photo's result.
- `PendingSyncFailure` (`Storage/Repositories/PendingSyncOperationTypes.swift`) records why a queued write's try failed, classified with `PaeoniaFailure` when it happens. Read `failedWhileOnline` or `lastFailureKind`, never the text in `lastError`.

### Stable presentation readiness

For any screen that can be the first app surface after launch, do not dismiss the launch/loading screen until the screen has a stable first presentation.

- View models for launch-adjacent screens must expose `isPresentationReady`.
- `isPresentationReady` means all data that can materially change the first visible layout, offer, eligibility, entitlement, pairing, or primary CTA has either loaded successfully or reached a final unavailable/error state.
- While `isPresentationReady == false`, keep showing the existing app loading surface instead of rendering partial feature UI.
- The app loading surface should be visually blank and copy-free; it may be present for only a split second, so do not add explanatory loading text that users cannot read.
- Keep the last known stable state visible during refreshes. Do not clear existing content, pricing, trial, pairing, entitlement, or invite state just because a new fetch has started.
- Transient errors may be shown through the top banner, but clearing the banner must not make `isPresentationReady` false again if the underlying fetch has already settled.

### Swift concurrency gotchas

#### Pass stored `@MainActor` closures through a closure literal

Passing a stored `@MainActor () async -> T` property straight into another view's closure parameter warns "converting non-Sendable function value ... may introduce data races". Adding `@Sendable` to both types does not stop it. Pass a closure that calls it instead: `Row(load: { await load() })`. This happens with Xcode 27 and this project's approachable-concurrency settings.

#### Test actors conform to `nonisolated` protocols in an extension

In `PaeoniaAppTests`, write `actor FakeCache { ... }` followed by `extension FakeCache: ProfilePhotoImageCaching {}` when the protocol is declared `nonisolated protocol`. With the conformance on the actor itself, Xcode 27 can fail with "'nonisolated' on an actor's synchronous initializer is invalid". It fails when a file that calls the actor's initializer is type-checked before the file that declares the actor, so whether it fails depends on how the build batches files. A local build can pass while CI fails. The app target is not affected because it defaults to `MainActor` isolation and the test target does not.

#### `.task(id:)` keys hold only inputs that change what loads

`SwiftUI`'s `.task(id:)` cancels its running task and restarts it whenever the `id` value changes. So the `id` must contain *only* the inputs that determine what the task loads — never cosmetic data that arrives or refreshes shortly after launch.

- A request that fails with `NSURLErrorCancelled` (`-999`) a beat after the screen appears, and works on manual retry, means a cosmetic field in the `id` changed mid-flight. The daily challenge load once keyed on all `DailyChallengeParticipants`, so each name and avatar that arrived cancelled the fetch. It now keys on `currentUserID` and refreshes cosmetic identity through `.onChange` (`DailyChallengeViewModel.refreshParticipants`).
- Key the load on identity that changes what is fetched, usually a user or couple id. Route names, photos and labels through `.onChange` into a method that refreshes rendering without fetching.
- Swallowing `URLError.cancelled` hides the banner but leaves the load cancelled and possibly not retried. Fix the `id`.
