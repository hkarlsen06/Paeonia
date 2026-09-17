# iOS Architecture Guidelines

Use Tidex's maintainable architecture lessons as the baseline, adapted for Paeonia.

### Feature-First Organization

Organize by product feature:

```text
ios/PaeoniaApp/
├── App/                  # App entry, lifecycle, root navigation
├── Features/             # Pairing, DailyPrompt, Memories, Countdown, Settings
├── Services/             # Auth, notifications, media, sync, subscriptions
├── Storage/              # SwiftData models, repositories, sync/local store
├── Models/               # Domain models and DTOs
├── Shared/               # Reusable components, extensions, design system
└── Resources/            # Assets, localization, sounds
```

Keep this feature-first structure as a hard maintainability rule. Do not flatten screens into one folder or mix feature implementation details into shared/global modules unless they are genuinely reusable.

Within a substantial feature, prefer responsibility-based subfolders over a generic feature-local `Shared/` folder. This is an example shape, not a literal template:

```text
ios/PaeoniaApp/Features/FeatureName/
├── Models/      # Feature-wide domain/UI models and remote DTOs
├── Data/        # Feature services, repositories, caches, drafts, and sync adapters
├── Components/  # Reusable UI pieces used by multiple flows in this feature
├── Timeline/    # Example product surface folder; use the real surface name
├── Editor/      # Example supporting flow folder; use the real flow name
└── Milestones/  # Example product logic folder; use the real logic name
```

Name flow and logic folders after the product responsibility they own, such as `AnswerFlow/`, `History/`, `Audio/`, `Streak/`, `Timeline/`, `Canvas/`, `Offer/`, or `Invite/`. Do not create generic `PrimaryFlow/`, `SecondaryFlow/`, `PureLogic/`, or `Shared/` buckets when a more precise responsibility name fits. Keep app-wide `Shared/` reserved for components, extensions, and design-system code that is genuinely reused across features.

### MVVM Boundaries

- SwiftUI views render state and forward user actions.
- Use SwiftUI as much as possible for app UI and interaction implementation.
- If UIKit appears necessary to solve a task, stop before implementing it and report why SwiftUI is insufficient, what UIKit API would be used, and the expected tradeoff.
- View models own presentation state and async UI flows.
- Repositories own local data access.
- Services own platform, backend, notification, media, and subscription integrations.
- Pure product logic should live outside SwiftUI views.

Examples of pure/testable logic:

- prompt reveal rules
- streak repair rules
- countdown calculations
- time-zone handling
- pairing state transitions
- notification planning
- memory ordering
- sync conflict handling

### Stable Presentation Readiness

For any screen that can be the first app surface after launch, do not dismiss the launch/loading screen until the screen has a stable first presentation.

- View models for launch-adjacent screens must expose `isPresentationReady` by conforming to `PresentationReadinessProviding`.
- `isPresentationReady` means all data that can materially change the first visible layout, offer, eligibility, entitlement, pairing, or primary CTA has either loaded successfully or reached a final unavailable/error state.
- While `isPresentationReady == false`, keep showing the existing app loading surface instead of rendering partial feature UI.
- The app loading surface should be visually blank and copy-free; it may be present for only a split second, so do not add explanatory loading text that users cannot read.
- Keep the last known stable state visible during refreshes. Do not clear existing content, pricing, trial, pairing, entitlement, or invite state just because a new fetch has started.
- Transient errors may be shown through the top banner, but clearing the banner must not make `isPresentationReady` false again if the underlying fetch has already settled.
- Add or update focused tests when introducing readiness gates, especially for blocked or slow fetches and for error-clearing behavior.

### Local-First Data Flow

Default to local-first behavior:

- Read from local persistence first.
- Write locally immediately.
- Mark records as pending/dirty if remote sync is needed.
- Sync in the background.
- Keep the UI usable offline where possible.
- Surface sync errors clearly without blocking ordinary app use.

### Dependency Injection

- Prefer initializer injection for view models, repositories, and services.
- Use protocols where they materially improve testability.
- Avoid unnecessary global singletons.
- Shared production instances are acceptable for app-wide coordination, but business logic should remain testable.

### Swift Concurrency

- Keep UI-facing view models on `@MainActor`.
- Use actors for serialized mutable state, save pipelines, or sync coordination.
- Handle task cancellation in async flows.
- Avoid heavy work in SwiftUI `body` or computed properties.
- Use `Sendable` for values crossing concurrency boundaries when appropriate.

#### `.task(id:)` keys must be load-bearing only

`SwiftUI`'s `.task(id:)` cancels its running task and restarts it whenever the `id` value changes. So the `id` must contain *only* the inputs that determine what the task loads — never cosmetic data that arrives or refreshes shortly after launch.

- Symptom of getting this wrong: a network request fails with `NSURLErrorCancelled` (`URLError.cancelled`, code `-999`) a beat after the screen appears, then a manual retry works. The launch-time load was aborted because some unrelated field in the `id` changed mid-flight.
- Concrete case (do not reintroduce): the daily challenge load was keyed on the whole `DailyChallengeParticipants` value (current/partner ids **plus** display names and profile-photo asset ids). Names and avatars populate asynchronously, so each one cancelled the in-flight `get_today_daily_questions` fetch. Fixed by keying `.task(id:)` on `currentUserID` alone and feeding cosmetic identity through a separate non-reloading path (`DailyChallengeViewModel.refreshParticipants` via `.onChange`).
- Rule: key the load on identity that genuinely changes *what* is fetched (usually a user/couple id). Route display-only updates (names, photos, labels) through `.onChange` into a method that refreshes rendering without re-fetching. When in doubt, prefer a narrow, stable `id` and a separate cosmetic-update path.
- Note that swallowing `URLError.cancelled` (treating it like Swift's `CancellationError`) hides the *banner*, but the load is still wastefully cancelled and may not auto-retry. Fix the `id`, don't just silence the error.
