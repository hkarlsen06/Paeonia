# Paeonia iOS agent guidance

Use SwiftUI, feature-first organization, and the existing MVVM/storage boundaries. Keep business logic outside views. Follow the root product and privacy constraints.

- For architecture, state, persistence, concurrency, or readiness changes, read [iOS architecture](../docs/agent-guides/ios-architecture.md). Loading keys must exclude cosmetic identity updates; preserve stable first presentation and offline content.
- For user-facing copy or catalog edits, read [localization](../docs/agent-guides/ios-localization.md). Use generated String Catalog symbols, English and Norwegian Bokmal, and translator comments.
- For visual or interaction changes, read [design](../docs/agent-guides/ios-design.md). Preserve the single plum theme, semantic tokens, Dynamic Type, Reduce Motion, contrast, VoiceOver, and the established wordmark, banner, and confirmation surfaces.
- For behavior changes or test work, read [verification](../docs/agent-guides/ios-verification.md). Build and test through the wrapper scripts it names, and run the app on the shared simulator to see your change work. Never run on a connected iPhone or iPad. The root AGENTS.md says which simulator to use.
- For auth, RPC, or backend client changes, read [backend guidance](../backend/AGENTS.md). Live data arrives through ConvexMobile subscriptions (see "Live data" below). Writes and one-shot reads go over HTTP through `PaeoniaShared/PaeoniaConvexClient.swift`. Backend function names and argument names (`p_` prefix) are the contract, so rename them on both sides together.

Paths and commands in the linked guides are relative to the repository root. Read relevant details rather than all guides for every edit.

## Game audio

Before adding or changing game sounds, read [the audio standard](../docs/game-audio.md). Normalize bundled effects with `python3 ios/Scripts/normalize-game-sounds.py --write`, and use the shared `GameSound` levels for playback.

## Distortion waves

`DistortionWavesKit` comes from Libraries.dev (`https://github.com/Jakubantalik/Libraries.dev`, MIT), linked into the app target only. It follows branch `main`, and `Package.resolved` pins the commit, so update it on purpose and look at the wave again after. Docs: `https://libraries.dev/waves.html`. Its Metal shader needs Xcode's separately downloaded Metal toolchain for the Xcode the wrappers select. This Mac has it for Xcode 27.3 beta 2 and CI downloads it. If a build reports it missing, ask the developer before downloading it.

- Play a wave with `@Environment(\.screenWave)`, giving the frame it starts from in global coordinates and a `DistortionWaveStyle`. `PaeoniaScreenWaveHost` (`Shared/DesignSystem/Components/PaeoniaScreenWave.swift`) sits once on the app's root and once in `DeveloperScenarioHost`, like the petal shower. It covers the whole window, bars included, and bends a picture of the window. Never mount a `DistortionWave` inside a screen, because it stops at the navigation and tab bars, and never in a window or cover of its own.
- The host takes the picture because SwiftUI cannot pass UIKit-backed views or materials (the PencilKit canvas, the bars, MapLibre, camera previews, glass) through the kit's shaders, and the kit mounts each side three times plus a hidden warm-up. So never give `DistortionWave` a live screen as a side.
- The host skips the wave under Reduce Motion and VoiceOver, takes no touches until it ends, ends it when the window changes size, fades the picture out at the end, and sets `cornerRadius` to the window's measured corners (`PaeoniaAppWindow.cornerRadius`). Callers only pick the style.
- A wave shows the screen as it was at the start for about two seconds. Don't play one where the screen moves on at once, such as the onboarding drawing steps, or from a sheet, which draws above the app's root and so above the wave.
- Xcode's build system compiles the `.metal` shader. `swift build` alone leaves it out, so check a wave through the Xcode wrappers and `scripts/scenario-record`, never only with `scripts/swift-typecheck`.

## Partner names

A person can give their partner a nickname, and the server keeps it private to them. Every screen, widget and VoiceOver label shows the nickname where it would show the partner's name.

- `PartnerName` (`PaeoniaApp/Services/Access/PartnerName.swift`) is the one place that decides the name. `AccessRouteResolution.partnerName` builds it from the access snapshot. Views and view models take the resolved name (`display`, `displayOrFallback`, or the `partnerDisplayName` strings that already hold it) and pass it down. A new feature that needs the partner's name takes it from the same place, never from a new server field.
- The partner's own name is `PartnerName.accountName` and `RemoteRelationshipState.partnerAccountName`. Only `PartnerName.swift` and `Features/Settings/PartnerNickname/` read it. The SwiftLint rule `partner_account_name_read` (`.swiftlint.yml`) flags a read anywhere else, and `no_raw_display_name_key` flags a new response model that decodes a server `display_name`.
- A widget gets the name from App Group data written from the resolved name (`WidgetSyncIdentityStore`) or from a server field that already applied the nickname. Push titles and `sender_name` come from the server.
- The server cannot show a nickname in a name it did not resolve, so a new backend field that carries a partner's name must go through `nameForViewer` (see `backend/AGENTS.md`).

## Live data

- Convex subscriptions hydrate the local store. They never feed views directly. View models re-read the store when `LocalStoreChanges.changes(in:)` reports a write, and they keep reading local data first. Repositories call `LocalStoreChanges.post` after each committed write, so add the call to any new shared repository.
- Writes go through the pending-operation outbox and `PaeoniaConvexClient`.
- `LiveQueryService.subscribe(_:args:as:)` decodes with `PaeoniaConvexClient.decoder`. Pass `Double` for `v.number()` arguments and omit optional keys instead of passing `nil`.
- A new live feed is a `LiveFeed` registered in `LiveFeedRegistry.makeFeeds`. A feed must stop writing once its task is cancelled.
- Every open app holds its subscriptions, and each costs server CPU whenever it re-runs, so a feed declares its `activation` deliberately. `.always` (the default) is for data that matters on every screen or that a background job reads, such as a tab badge, Home, a notification or a background upload, unless another feed or a touch covers it. Otherwise use `.whileNeeded(topics)`, and publish the topics from the screen through `LiveFeedDemand`. The coordinator stops an unneeded feed 30 seconds later.
- Never call `logout()` on the live Convex client. It signs out of Clerk. Sign out through Clerk and the client follows.
- The widget extension and notification extension stay HTTP-only. Do not link ConvexMobile into them.
- The ConvexMobile static library has no x86_64 simulator slice, so the project excludes x86_64 for simulator builds.
