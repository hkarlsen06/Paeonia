---
name: paeonia-ios-whats-new
description: Write evidence-based Paeonia iOS App Store release notes in English and Norwegian Bokmal, update metadata, and regenerate local Fastlane files.
---

# Paeonia iOS What's New

Use this skill when the user wants Paeonia iOS App Store release notes, "What's New" copy, translated release notes, or expedited review notes.

## Inputs

- Expect a git reference for the last published build: tag, commit SHA, branch, or other valid ref.
- If the reference is missing, inspect the request and maintained release records for an unambiguous published baseline. Do not assume the newest tag was published. Ask only when the baseline cannot be established reliably.
- If the user gives editorial guidance, use it only when supported by the inspected changes.

## Review The Change Set

From the Paeonia repo root, inspect commits since the reference:

```bash
git log <ref>..HEAD --oneline -- ios/ supabase/
git log <ref>..HEAD --stat -- ios/ supabase/
git diff --name-only <ref>..HEAD -- ios/ supabase/
```

Focus on `ios/`. Include `supabase/` only when it changes user-visible iOS behavior such as auth, pairing, subscriptions, sync, notifications, media, privacy, or reliability.

## Decide What Belongs In Release Notes

Split changes into:

- User-facing: features, fixes, performance, UX polish, privacy, reliability, or behavior users may notice.
- Non-user-facing: refactors, cleanup, tests, internal tooling, migrations, or backend implementation details without visible app behavior.

Rules:

- List user-facing items individually.
- Collapse non-user-facing work into one final generic line.
- Do not expose internal terms like backend, JWT, RLS, migration, sync coordinator, pending mutation, entitlement, payload, or cron.
- Keep copy simple enough for an ordinary 16-year-old.
- Put the most important user benefit first.
- For expedited review messaging, lead with the critical fix or reliability issue.

## Writing Rules

- Write English and Norwegian Bokmal together.
- Keep each line as a `-` bullet unless there are no clear user-facing changes.
- Start bullets with clear action verbs such as `Added`, `Fixed`, `Improved`, `Lagt til`, `Rettet`, or `Forbedret`.
- Use natural Norwegian Bokmal, not literal translation.
- Keep each locale comfortably below the App Store `release_notes` limit of 4000 characters.

Include only claims supported by the inspected change set. Do not add a generic bug-fix or performance-improvement line for internal-only changes. If no user-visible release benefit is supported, report that and leave release-note fields unchanged unless the user supplies approved factual wording.

## Update Metadata And Generate Files

Unless the user explicitly asks for draft-only output, update only:

- `ios/Scripts/appstore-metadata-source.json`
  - `metadata.en.release_notes`
  - `metadata.nb.release_notes`

Then regenerate Fastlane metadata:

```bash
pnpm --dir ios generate-metadata
```

Inspect the generated diff and verify it matches the requested release notes; preserve unrelated source fields and investigate unexpected generated changes before accepting them. Do not upload metadata unless the user explicitly asks.

## Final Response

After updating the source file:

- Show the English and Norwegian release notes that were written.
- Mention the reference used.
- Mention `pnpm --dir ios upload-metadata` as the upload command.
