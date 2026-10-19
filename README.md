# Paeonia

**Pronunciation:** pay-OH-nee-uh

Paeonia is a private relationship app for couples who want to feel close through distance. It is named after the botanical genus for peonies, one of the founder's favorite flowers, making the name both personal and emotionally rooted.

**Canonical domain:** `paeonia.no`

**Convex API domain:** `api.paeonia.no` (HTTP actions on `actions.paeonia.no`)

**Backend hosting:** Self-hosted Convex on the `one-s` server, with Clerk for sign-in. See `backend/AGENTS.md`.

## Product Idea

Long-distance relationship apps often have the right intention but poor execution: unreliable widgets, broken streaks, lost content, weak polish, and shallow daily prompts. Paeonia should be built around the opposite promise:

> A private place for the two of you.

The app should help couples create small, reliable daily rituals that make distance feel less passive.

## Core Jobs

- Help couples feel present in each other's day without needing a full conversation.
- Create tiny shared rituals that are easy to keep up.
- Make distance feel more active, mutual, and intentional.
- Preserve memories, notes, photos, and milestones.
- Reduce the friction of finding something meaningful to do together.
- Support busy schedules, time zones, and asynchronous interaction.
- Protect trust by never losing private content or breaking couple state.

## Product Principles

- **Reliability first:** no broken streaks, missing answers, duplicate notifications, lost photos, or confusing sync states.
- **Small moments over heavy sessions:** the app should fit naturally into everyday life.
- **Private by default:** the couple's space should feel safe, intimate, and clearly protected.
- **Polished native experience:** fast launch, smooth transitions, tasteful haptics, strong empty states, and consistent design.
- **Respectful engagement:** no manipulative streak pressure or guilt loops.
- **Offline tolerant:** core content should remain accessible even with poor connectivity.

## MVP

1. Couple pairing
2. Daily check-in questions
3. Private answers with reveal after both partners respond
4. Shared streaks with forgiving repair rules and expiry reminders
5. Memory timeline with notes and up to 5 images per partner
6. Partner widget with stroke-based drawing support
7. Relationship milestone countdowns
8. Respectful push notifications
9. Hard paywall where one paying partner unlocks access for both
10. Local-first offline support
11. Privacy, export, delete, and notification settings

## Lessons To Carry From Tidex

### Feature-First Structure

Organize by product feature, not just by file type.

```text
marketing/      # Static SvelteKit marketing/legal site for paeonia.no
ios/
├── PaeoniaApp/
│   ├── App/
│   ├── Features/
│   │   ├── Pairing/
│   │   ├── DailyPrompt/
│   │   ├── Memories/
│   │   ├── PartnerWidget/
│   │   ├── Countdown/
│   │   ├── Onboarding/
│   │   └── Settings/
│   ├── Services/
│   │   ├── Auth/
│   │   ├── Notifications/
│   │   ├── Sync/
│   │   ├── Media/
│   │   └── Subscription/
│   ├── Storage/
│   │   ├── Models/
│   │   ├── Repositories/
│   │   └── LocalStore.swift
│   ├── Models/
│   ├── Shared/
│   └── Resources/
├── PaeoniaWidget/
├── PaeoniaAppTests/
├── PaeoniaAppUITests/
└── Scripts/
```

### MVVM Boundaries

- SwiftUI views render state and forward actions.
- View models own presentation state and async UI flows.
- Repositories own local data access.
- Services own platform and backend integrations.
- Pure domain logic stays outside SwiftUI views.

### Local-First Storage

Use SwiftData as the primary source of truth. Reads should come from local storage. Writes should update local state immediately and sync afterward.

This keeps the app usable when offline and prevents the UI from being blocked by network state.

### Repository Layer

Avoid querying SwiftData directly from views. Use repositories such as:

- `CoupleRepository`
- `PromptRepository`
- `MemoryRepository`
- `CountdownRepository`
- `PartnerStatusRepository`
- `NotificationPreferencesRepository`

Repositories should be injectable so tests can use in-memory implementations.

### Sync As A Separate Concern

Treat sync as a background system, not as the UI's source of truth.

Important sync concepts:

- dirty local records
- soft deletes
- server revision tracking
- conflict resolution
- local optimistic updates
- clear sync error states

### Type-Safe Localization

Use Xcode String Catalogs from day one.

- Add every user-facing string to the catalog.
- Use generated `LocalizedStringResource` symbols.
- Avoid raw localization keys in Swift code.
- Validate localization with scripts.
- Prefer `FormatStyle` for dates, numbers, and countdowns.

Example:

```swift
Text(.dailyPromptRevealTitle)
String(localized: .countdownDaysRemaining(Int32(days)))
```

### Design System

Use semantic tokens rather than hardcoded values.

Examples:

- `paeoniaBackground`
- `paeoniaSurface`
- `paeoniaTextPrimary`
- `paeoniaTextSecondary`
- `paeoniaAccent`
- `paeoniaError`
- `paeoniaSuccess`

Define shared spacing, typography, corner radii, animation durations, and haptic patterns early.

### Testing Expectations

Most tests are integration and end-to-end tests: UI tests that walk a journey through the interactive local flows, backend `convex-test` tests of the function contracts, and iOS tests that wire real view models, repositories and the local store. Unit tests cover pure logic where a bug is costly and hard to see from outside, such as time zone math, access rules, sync ordering and game rules. The [Testing](AGENTS.md#testing) rules in `AGENTS.md` say when a change needs a new test.

### Build And Release Discipline

Carry over the Tidex habit of scripted validation:

- lint
- build
- test
- localization validation
- App Store metadata generation
- release note generation

## Possible Taglines

- A private place for the two of you.
- Small moments, kept close.
- For love across distance.
- Stay close, even apart.
- A daily ritual for two.
- Where your relationship lives.

## Current Favorite Positioning

> Paeonia is a private place for two people to stay close through distance, built around reliable daily rituals, shared memories, and small moments that make the relationship feel present.
