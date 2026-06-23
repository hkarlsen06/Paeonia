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
- Auth uses Sign in with Apple, Google Sign-In, and passkeys only; no email/password or email magic-link auth for MVP.
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
Use `api.paeonia.no` as the canonical Supabase API domain for production client configuration, Auth callbacks, Storage, Realtime, and Edge Functions.

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
- Avoid verbose command modes unless the extra output is needed to debug the issue.
- Use `rg` for searching text or files when available.
- Prefer existing project patterns over introducing new abstractions.
- Keep business logic out of SwiftUI view bodies.
- Use Tidex's project setup as the default template. Do not introduce a generated Xcode project, alternative build system, different package manager, or different deployment workflow without first discussing the tradeoff with the user.
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

Once project-specific wrappers exist, use them instead of raw `xcodebuild`.

Recommended future commands:

```bash
./scripts/xcode-build-agent.sh
./scripts/xcode-test-agent.sh
```

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
- Use JWT verification only for direct user-called functions.

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
