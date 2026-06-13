# Phase 1 Decisions

These decisions should be confirmed before the next foundation step.

## iOS Project

- Minimum deployment target: iOS 26.6.
- Targets to create initially:
  - app
  - widget
  - notification service extension
  - unit tests
  - UI tests
- The widget is a central MVP surface and should be present from day one.
- The notification service extension is needed for the planned notification experience.
- Configure Associated Domains immediately:
  - `applinks:paeonia.no`
- Configure App Groups immediately:
  - `group.no.paeonia.app`
- Project format:
  - Xcode-managed `.xcodeproj`, matching Tidex.
  - Do not switch to a generated project tool unless the user explicitly approves that deviation.

## Authentication

- Supabase Auth is the current default.
- MVP auth methods are locked to:
  - Sign in with Apple
  - Google Sign-In
  - passkeys
- Do not implement email/password or email magic-link auth for MVP.
- Implement all three as first-class MVP auth surfaces.

## Dependencies

- Use Tidex-style dependency ranges for JavaScript packages.
- Keep the overall project setup nearly identical to Tidex.
- Discuss improvements/deviations before applying them.
- Prefer project-native Apple frameworks for iOS unless an external dependency removes real complexity.
- Confirm new iOS package dependencies before adding them.

## Localization

- Use Xcode String Catalogs from day one.
- Use generated `LocalizedStringResource` symbols, never raw localization keys.
- Start with English and Norwegian Bokmal.
- Structure localization so additional languages can be added later without refactoring.

## Folder Structure

- Follow Tidex's feature-first structure.
- Use a top-level `Features/` folder.
- Keep feature-specific views, view models, components, models, and utilities inside their owning feature.
- Use `Shared/` only for genuinely reusable components/utilities.

## Marketing

- `paeonia.no` is the canonical domain.
- The marketing app is static Next.js for Cloudflare Pages.
- Placeholder legal copy is not final and must not be treated as production legal text.
