# AGENTS.md

This file provides guidance to coding agents when working in the Paeonia repository.

## Project Overview

Paeonia is an iOS-first private relationship app for couples who want to feel close through distance. The product should prioritize reliability, polish, privacy, local-first behavior, and small daily rituals.

Initial direction:

- Native iOS app built with SwiftUI.
- Static Next.js marketing/legal site deployed to Cloudflare Pages.
- Local-first persistence, likely SwiftData.
- Clear MVVM boundaries.
- Type-safe localization from the beginning.
- Shared daily prompts, memories, countdowns, widgets, respectful notifications, and couple pairing.
- Minimum deployment target is iOS 26.5.
- Initial iOS targets include app, widget, notification service extension, unit tests, and UI tests.
- Auth uses Sign in with Apple and Google Sign-In only for MVP; no separate sign-up page, passkey flow, email/password, or email magic-link auth for MVP.
- Project setup should stay nearly identical to Tidex. Discuss deviations with the user before making them.
- Associated Domains should be configured from the start for `applinks:paeonia.no`.
- Localization must use Xcode String Catalog generated symbols from day one. Start with English and Norwegian Bokmal.

## Repository Structure

Target structure:

```text
paeonia/
├── marketing/            # Static Next.js site for paeonia.no
├── ios/                  # Native iOS application
│   ├── PaeoniaApp/       # Main iOS app target
│   ├── PaeoniaWidget/    # Widget target, if/when added
│   ├── PaeoniaAppTests/  # Unit tests
│   ├── PaeoniaAppUITests/# UI tests
│   └── Scripts/          # Build/localization/release scripts
├── supabase/             # Backend, if/when added
├── docs/                 # Architecture and product documentation
├── AGENTS.md
└── README.md
```

Use `paeonia.no` as the canonical public domain for marketing, support, legal pages, and universal links.
Use `api.paeonia.no` as the canonical Supabase API domain for production client configuration, Auth callbacks, Storage, Realtime, and Edge Functions. Do not use the raw Supabase project URL in production OAuth, app, or web configuration when the custom domain can be used.

Do not create placeholder directories or files unless they are needed for the current task.

## Agent Behavior Guidelines

### Parallel Agent Safety

The developer may run multiple agents in parallel in the same worktree.

- If you see unrelated changes, do not touch, revert, reformat, or clean them up.
- Treat unrelated diffs as owned by the user or another agent.
- Only modify files and hunks required for the task.
- If unrelated changes block the task, stop and ask before proceeding.

### File Creation

- Do not create summary documents, audit reports, or extra markdown files unless explicitly requested.
- Prefer code changes and concise chat summaries over new documentation artifacts.
- Keep edits scoped to the requested work.

### File Size And Splitting

- Avoid letting Swift files grow into broad catch-all files.
- There is no hard line limit, but treat large files as a design signal.
- When a file becomes substantial, actively look for natural split points before adding more code:
  - feature subviews
  - button/card/style definitions
  - repository protocols and implementations
  - pure date/calculation logic
  - sync or persistence helpers
  - preview/test fixtures
- Split only when it improves readability, ownership, or testability. Do not fragment code into tiny files just to satisfy a number.
- The pre-commit hook runs SwiftLint and prints an advisory for large staged Swift files. Treat that advisory as a prompt to think, not as an automatic mandate.

### Product Copy Clarity

- All user-facing copy must be understandable to an ordinary 16-year-old.
- Avoid technical implementation wording in the UI.
- Do not expose internal terms like sync coordinator, entitlement, RLS, cron, JWT, pending mutation, backend, payload, tombstone, or migration to users.
- Translate technical state into human outcomes:
  - "Saved on this phone. We'll send it when you're online." instead of "Pending sync mutation."
  - "Your partner will see this when it finishes sending." instead of "Upload queued."
  - "You no longer have access to this relationship." instead of "Entitlement removed."
- Error messages must say what happened and what the user can do next.
- If a phrase sounds correct to an engineer but awkward for a normal teenager, rewrite it.

### Git

- Do not include `Co-Authored-By` lines in commit messages.
- Never push automatically. Commit when requested, but wait for explicit user approval before pushing.
- Commits must always be signed. Never disable commit signing.
- If commit signing fails, stop and report the signing failure instead of creating an unsigned commit.
- Before committing, inspect the full diff and write a commit message that describes the meaning of the change.

## Development Defaults

- Run commands from the repository root unless explicitly stated otherwise.
- Prefer fast, focused verification commands.
- Do not run build or test commands by default. They make each turn significantly slower, and the developer will build locally when needed.
- Only run builds or tests when the user explicitly asks. You may suggest a relevant build or test command in the final handoff.
- Avoid verbose command modes unless the extra output is needed to debug the issue.
- Use `rg` for searching text or files when available.
- Prefer existing project patterns over introducing new abstractions.
- Keep business logic out of SwiftUI view bodies.
- Use Tidex's project setup as the default template. Do not introduce a generated Xcode project, alternative build system, different package manager, or different deployment workflow without first discussing the tradeoff with the user.
- The Xcode project uses filesystem-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so new `.swift` files under synchronized source folders are auto-included. Do not edit `project.pbxproj` just to add those files.
- Install local hooks with `./scripts/install-git-hooks.sh` after cloning if they are not already active.

## Marketing Site Guidelines

The `marketing/` app should follow Tidex's simple static-site pattern:

- Use Next.js with static export.
- Deploy to Cloudflare Pages.
- Keep public/legal/support pages in the marketing app.
- Use `paeonia.no` as the canonical domain.
- Use stable routes for App Store and in-app references:
  - `/`
  - `/privacy`
  - `/terms`
  - `/support`
  - `/join/[inviteCode]` or another universal-link route chosen before implementation
- Avoid server-only runtime dependencies unless the deployment target changes.
- Keep legal/version metadata structured once legal pages exist.

## iOS Architecture Guidelines

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

## Localization

Localization is required for all user-facing strings.

Start with English and Norwegian Bokmal. The setup must make later languages straightforward.

### Rules

- Use Xcode String Catalogs.
- Use generated `LocalizedStringResource` symbols in Swift code.
- Do not use raw string keys in localization calls.
- Avoid patterns such as:
  - `String(localized: "settings.saveButton")`
  - `Text("settings.saveButton", tableName: "Localizable")`
  - `LocalizedStringResource("settings.saveButton", table: "Localizable")`
  - `NSLocalizedString("settings.saveButton", ...)`
- If a key has no generated symbol, add or rename the catalog entry so a symbol is generated.
- Prefer `FormatStyle` for dates, numbers, percentages, and countdowns.
- Use the system locale. Do not override locale globally unless there is a specific product requirement.
- Keep source copy simple enough to translate naturally. Avoid idioms, jokes, technical shorthand, and nested clauses.

### Key Naming

Use dot-notation keys:

```text
feature.context.description
```

Examples:

```text
dailyPrompt.reveal.title
pairing.invite.button
countdown.daysRemaining
settings.notifications.title
```

Generated symbols should be used like:

```swift
Text(.dailyPromptRevealTitle)
String(localized: .countdownDaysRemaining(Int32(days)))
```

### Editing String Catalogs

For ordinary plain string entries, use the repo helper instead of hand-editing `.xcstrings` JSON:

```bash
./scripts/xcstrings-set ios/PaeoniaApp/Resources/Localization/Localizable.xcstrings pairing.invite.button \
  --comment "Button that starts partner invitation" \
  --en "Invite partner" \
  --nb "Inviter partner"
```

- New keys must include English, Norwegian Bokmal, and a translator comment.
- The helper preserves existing catalog order by default to keep diffs focused. Pass `--sort-keys` only when intentionally normalizing a catalog.
- Use `--locale <code>=<value>` for additional languages if the catalog grows beyond `en` and `nb`.
- Use Xcode's String Catalog editor or XLIFF export/import for pluralization, substitutions, device variants, or bulk translator workflows.
- After catalog changes, verify generated symbols in Swift code still match the key names. Run a build only when explicitly requested or when symbol generation needs to be checked.

## Design System

Use semantic colors and design tokens. Do not scatter hardcoded colors, spacing, or typography values through feature views.

Paeonia uses one canonical plum-led brand theme for MVP. Do not design or implement separate light and dark native app appearances unless the user explicitly reopens that product decision. Accessibility settings still matter: preserve Dynamic Type, Reduce Motion, contrast, and VoiceOver behavior within the plum theme.

Suggested semantic colors:

- `paeoniaBackground`
- `paeoniaBackgroundSecondary`
- `paeoniaSurfacePrimary`
- `paeoniaSurfaceSecondary`
- `paeoniaTextPrimary`
- `paeoniaTextSecondary`
- `paeoniaTextMuted`
- `paeoniaAccent`
- `paeoniaError`
- `paeoniaSuccess`
- `paeoniaWarning`

Also centralize:

- spacing
- corner radii
- typography roles
- animation durations
- haptic patterns
- reusable button and card styles

Use cards only when the framed surface has product meaning, such as a distinct repeated item, modal, or tool. Prefer few or no cards, and do not wrap ordinary screen content in cards by default. Place content directly in the screen layout with intentional spacing and hierarchy. Put primary CTA clusters near the bottom of the screen when it improves thumb reach and matches the flow. In bottom button clusters, text-only actions without visible button backgrounds should still occupy button-sized hit targets and be spaced like adjacent buttons, not tucked close to the primary CTA.

### Brand Wordmark

- When `Paeonia` is shown as a standalone single-word app name in the iOS app or widget surfaces, use the shared `PaeoniaWordmark` logo lockup in the app target, or the same mark-left, serif, semibold wordmark treatment in targets that cannot import it.
- Size may change with layout hierarchy, but the wordmark font treatment should stay consistent.
- When `app.tagline` is presented as the slogan paired with the stylized wordmark, use `PaeoniaBrandLockup` so the logo-plus-wordmark row is constrained to the same visual width as the tagline. Use the same serif, semibold wordmark family treatment at the appropriate size for that layout.
- Do not apply the wordmark style automatically when `Paeonia` appears as part of a sentence or longer phrase; use the surrounding copy style in those cases.

### Error Presentation

- Present transient user-facing errors through the app-level top dropdown banner.
- Mount the shared banner once at the root and send feature errors into that shared surface.
- Do not add new inline red error panels or system alerts for ordinary recoverable errors.
- Keep full-screen error states only when the whole screen cannot continue and needs a retry action.

### Confirmation Dialogs

- Confirmations and destructive choices use the centered system alert dialog, app-wide. Use SwiftUI `.alert(_:isPresented:actions:message:)`.
- Do not use `.confirmationDialog` (the bottom action sheet) for these. It anchors to the bottom or renders as a popover and is not the intended presentation.
- This is separate from error presentation: errors still go to the top banner (see above); the centered alert is only for confirmations the user must explicitly approve (for example: clear canvas, delete account, leave relationship).
- Title states the action, the message states the consequence and reversibility, the destructive button uses a verb with the `.destructive` role, and the cancel button uses the `.cancel` role.

## Testing Requirements

Agents should add or update tests when implementing behavior.

### Default Rule

- Feature work should include test coverage for changed behavior, not just compile-clean code.
- If behavior changes and no tests are added, explain why in the final handoff.

### What To Test

- Happy path: primary user flow works and returns expected values.
- Edge cases: invalid input, empty states, timezone boundaries, date changes, offline states.
- Regression guard: at least one test that would fail if the changed logic was removed.
- Bug fixes: add a test that reproduces the bug when feasible.

### Important Test Areas

- prompt reveal logic
- streak and streak repair logic
- countdown date math
- timezone behavior
- notification scheduling
- couple pairing state
- memory timeline ordering
- local save/load behavior
- sync conflict behavior
- widget payload generation
- privacy/export/delete flows

### Where To Place Tests

Once the iOS project exists:

- Business logic, repositories, services, sync, and view models: `ios/PaeoniaAppTests/`
- UI launch/smoke and critical interactions: `ios/PaeoniaAppUITests/`

Prefer small focused unit tests over broad UI tests unless behavior is UI-only.

## iOS Build And Test Commands

Do not run iOS build or test wrappers by default. Only run them when the user explicitly asks, though you may recommend one of these commands in the final handoff when it would be useful.

When the user asks you to build or test and project-specific wrappers exist, use them instead of raw `xcodebuild`.

Recommended future commands:

```bash
./scripts/xcode-build-agent.sh
./scripts/xcode-test-agent.sh
```

### Toolchain Requirement

Build with Xcode 27.0 beta by setting `DEVELOPER_DIR` for the command or by selecting the beta globally with `xcode-select`. On macOS 27 beta, GM Xcode 26.5's `actool` crashes when compiling the app's Icon Composer icon at `ios/PaeoniaApp/Resources/AppIcon/paeonia_app.icon`.

Known bad pairing:

```bash
/Applications/Xcode.app
```

Known working beta toolchain:

```bash
DEVELOPER_DIR="/Users/hjalmarkarlsen/Documents/Xcode-beta.app/Contents/Developer" xcodebuild ...
```

Failure symptom:

```text
Exception while running actool: *** -[__NSPlaceholderArray initWithObjects:count:]: attempt to insert nil object from objects[0]
```

This is a toolchain bug, not a project icon bug. Do not replace the layered `.icon` with a flat `AppIcon.appiconset` PNG workaround; a prior flat PNG workaround had a transparent background and rendered incorrectly against black in iOS 26/27 dark mode. `ASSETCATALOG_COMPILER_APPICON_NAME` must remain `paeonia_app` so the layered icon keeps the correct plum dark-mode background.

If wrappers do not exist yet:

- Use the project's documented build/test commands.
- If no documented commands exist, use the least noisy focused command available and report exactly what was run.
- Prefer `swiftlint --quiet` for fast Swift checks once SwiftLint is configured.

## Supabase Guidelines

Use this section only if/when Paeonia adds Supabase.

Production Supabase API domain: `api.paeonia.no`.

When configuring OAuth providers, include the Supabase Auth callback on the custom domain:

```text
https://api.paeonia.no/auth/v1/callback
```

For Google OAuth client setup, use `https://paeonia.no` as the web origin and `https://api.paeonia.no/auth/v1/callback` as the authorized redirect URI.

### Tool Discovery

Supabase MCP tools may be lazy-loaded in Codex sessions. For any Supabase task, first call `tool_search` for:

```text
Supabase execute_sql get_project_url list_tables
```

Prefer `mcp__supabase__.execute_sql` for database inspection and narrow, targeted data fixes when available. Use ad hoc service-role scripts only as a fallback when MCP tools are unavailable or insufficient, and explain why.

### GitHub Integration Deployments

Paeonia uses Supabase's GitHub integration for remote deploys. On push to `origin` for the remote branch configured in Supabase, the Git integration automatically handles the Supabase deploy steps:

- New migrations are applied.
- Edge Functions declared in `config.toml` are deployed.
- Storage buckets declared in `config.toml` are deployed.
- All other configurations, including API, Auth, and seed files, are ignored by default.

### Edge Functions

- Edit Edge Functions locally in `supabase/functions/`.
- Deploy via Supabase CLI, not MCP deploy tools.
- Always include `--no-verify-jwt` when deploying functions that are intended for webhooks, cron, service-role flows, or other non-user JWT callers.
- For direct user-called functions, do not enable Supabase's "Verify JWT with legacy secret" / platform `verify_jwt` gate when the app uses modern publishable keys. Set `verify_jwt = false` in `supabase/config.toml` and perform auth inside the function with the request `Authorization` header and `auth.getUser()`.
- Edge Functions that need user auth should read modern `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS` when available, with legacy key env vars only as local compatibility fallbacks.

### SQL And Migrations

- Always create new migration files with `supabase migration new <migration_name>`, then edit the generated file.
- Keep migration files in `supabase/migrations/`.
- Do not push remote migrations with the Supabase CLI. Commit the migration files and let Supabase's Git integration apply them when the configured branch is pushed to `origin`.
- Keep SQL source files in `supabase/sql/functions/` in sync with actual database definitions if that structure is added.
- Use `supabase db pull` only when intentionally baselining or reconciling remote-first schema changes.

## Product-Specific Quality Bar

Paeonia handles private relationship content. Treat reliability and privacy as core product requirements.

- Never silently drop user content.
- Avoid destructive local data changes unless explicitly requested or protected by backup/migration logic.
- Make delete/export/privacy flows explicit and testable.
- Be careful with notification content; avoid exposing sensitive relationship content on locked screens without a clear setting.
- Prefer forgiving streak rules over punitive engagement mechanics.
- Make timezone behavior explicit for couple-shared rituals.
