---
name: paeonia-ios-whats-new
description: Write evidence-based Paeonia iOS App Store release notes in English and Norwegian Bokmal, update metadata, and regenerate local ASC metadata.
---

# Paeonia iOS what's new

## Inputs

- Expect a git reference for the last published build: tag, commit SHA, branch, or other valid ref.
- If the reference is missing, inspect the request and maintained release records for an unambiguous published baseline. Do not assume the newest tag was published. Ask only when the baseline cannot be established reliably.
- If the user gives editorial guidance, use it only when supported by the inspected changes.

## Review the change set

From the Paeonia repo root, inspect commits since the reference:

```bash
git log <ref>..HEAD --oneline -- ios/ backend/
git log <ref>..HEAD --stat -- ios/ backend/
git diff --name-only <ref>..HEAD -- ios/ backend/
```

Focus on `ios/`. Include `backend/` only when it changes user-visible iOS behavior such as auth, pairing, subscriptions, sync, notifications, media, privacy, or reliability.

## Decide what belongs in release notes

Split changes into:

- User-facing: features, fixes, performance, UX polish, privacy, reliability, or behavior users may notice.
- Non-user-facing: refactors, cleanup, tests, internal tooling, migrations, or backend implementation details without visible app behavior.

Rules:

- List user-facing items individually.
- Collapse non-user-facing work into one final generic line.
- Follow the root `AGENTS.md` Product Copy Clarity rules: no internal terms, copy an ordinary 16-year-old understands.
- Put the most important user benefit first.
- For expedited review messaging, lead with the critical fix or reliability issue.

## Writing rules

- Write English and Norwegian Bokmal together.
- Keep each line as a `-` bullet unless there are no clear user-facing changes.
- Start bullets with clear action verbs such as `Added`, `Fixed`, `Improved`, `Lagt til`, `Rettet`, or `Forbedret`.
- Use natural Norwegian Bokmal, not literal translation.
- Keep each locale comfortably below the App Store `release_notes` limit of 4000 characters.

Include only claims supported by the inspected change set. Do not add a generic bug-fix or performance-improvement line for internal-only changes. If no user-visible release benefit is supported, report that and leave release-note fields unchanged unless the user supplies approved factual wording.

## Update metadata and generate files

Unless the user explicitly asks for draft-only output, update only:

- `ios/Scripts/appstore-metadata-source.json`
  - `metadata.en.release_notes`
  - `metadata.nb.release_notes`

Then regenerate ASC metadata:

```bash
bun run --cwd ios generate-metadata
```

Inspect the generated diff and verify it matches the requested release notes; preserve unrelated source fields and investigate unexpected generated changes before accepting them. Do not upload metadata unless the user explicitly asks.

## Final response

Show the English and Norwegian release notes, the reference used, and the dry-run (`bun run app-store metadata`) and upload (`--apply`) commands.
