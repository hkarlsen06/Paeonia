# AGENTS.md

This file provides guidance to coding agents when working in the Paeonia repository.

## Project Overview

Paeonia is an iOS-first private relationship app for couples who want to feel close through distance. The product should prioritize reliability, polish, privacy, local-first behavior, and small daily rituals.

Product constraints:

- Native iOS app built with SwiftUI.
- Static Next.js marketing/legal site deployed to Cloudflare Pages.
- Local-first persistence using the existing storage layer.
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

Repository structure:

```text
paeonia/
├── marketing/            # Static Next.js site for paeonia.no
├── ios/                  # Native iOS application
│   ├── PaeoniaApp/       # Main iOS app target
│   ├── PaeoniaWidget/    # Widget target, if/when added
│   ├── PaeoniaAppTests/  # Unit tests
│   ├── PaeoniaAppUITests/# UI tests
│   └── Scripts/          # Build/localization/release scripts
├── supabase/             # Self-hosted Supabase backend
├── docs/                 # Architecture and product documentation
├── AGENTS.md
└── README.md
```

Use `paeonia.no` as the canonical public domain for marketing, support, legal pages, and universal links.
Use `api.paeonia.no` as the canonical Supabase API domain for production client configuration, Auth callbacks, Storage, Realtime, and Edge Functions. Do not use the raw Supabase project URL in production OAuth, app, or web configuration when the custom domain can be used.

Do not create placeholder directories or files unless they are needed for the current task.

## Agent Orientation

When ownership is unclear or exploration would span the project, consult `docs/implementation-map.md`. A known-file typo or narrow edit does not require a repository tour.

For release planning, use `docs/mvp-release-checklist.md`. Paeonia no longer uses a phase roadmap as the active execution plan; the checklist is the source of truth for what remains before MVP submission.

Keep `AGENTS.md` for durable rules and constraints. Put feature ownership maps, implementation slices, and command references in focused docs instead:

- `docs/implementation-map.md`: first stop for "which file owns this behavior?"
- `docs/mvp-release-checklist.md`: active MVP release-readiness checklist.
- `docs/phase-3-data-contract.md`: product/data-model decisions before schema work.
- `docs/phase-3-migration-checklist.md`: Supabase migration slice plan and RLS helper checklist.
- `docs/couple-question-guidelines.md`: required reading before writing, seeding, localizing, or versioning couple questions.
- `docs/marketing-app-contract.md`: public routes, Universal Links, Cloudflare static files, and marketing app structure.
- `supabase/README.md`: backend working rules, local command examples, and question catalog notes.

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

### Placeholder And Stub Behavior

- Do not wire up placeholder states for features that are not finished, such as a button that shows "Coming soon", a stub alert, an empty screen, or a no-op handler, unless we explicitly plan to ship the feature in that interim state.
- Such placeholders are not free: they get replaced with the real implementation during normal development before release, so the interim state becomes dead code the developer has to find and remove later.
- If a feature is not ready to wire up, leave it unwired rather than adding a fake destination. Prefer not adding the entry point yet, or stop and ask how the developer wants the unfinished feature surfaced.
- If a temporary placeholder is genuinely wanted, confirm that intent first, and only then add it.

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

- Before writing, seeding, localizing, or versioning couple/daily questions, read `docs/couple-question-guidelines.md`. Questions are authored by Paeonia, not by either partner, and must not sound like they came from the partner.

### Git

- Do not include `Co-Authored-By` lines in commit messages.
- Never push automatically. Commit when requested, but wait for explicit user approval before pushing.
- Commits must always be signed. Never disable commit signing.
- If commit signing fails, stop and report the signing failure instead of creating an unsigned commit.
- Before committing, inspect the full diff and write a commit message that describes the meaning of the change.

## Development Defaults

- Run commands from the repository root unless explicitly stated otherwise.
- Prefer fast, focused verification commands.
- During interactive debugging where the user is rebuilding in Xcode, avoid duplicate builds and tests. Otherwise, complete focused verification, fix failures caused by the change, and rerun affected checks without an extra handoff. Broaden checks only when risk or failures justify them.
- Use the repository iOS wrappers; see [iOS verification](docs/agent-guides/ios-verification.md) when building, testing, or changing test behavior. Report anything left unverified.
- Avoid verbose command modes unless the extra output is needed to debug the issue.
- Use `rg` for searching text or files when available.
- Prefer existing project patterns over introducing new abstractions.
- Keep business logic out of SwiftUI view bodies.
- Use Tidex's project setup as the default template. Do not introduce a generated Xcode project, alternative build system, different package manager, or different deployment workflow without first discussing the tradeoff with the user.
- The Xcode project uses filesystem-synchronized groups (`PBXFileSystemSynchronizedRootGroup`), so new `.swift` files under synchronized source folders are auto-included. Do not edit `project.pbxproj` just to add those files.
- Install local hooks with `./scripts/install-git-hooks.sh` after cloning if they are not already active.

## Task-specific guidance

Read only guidance relevant to the change. Commands and source paths in these documents use the repository root unless stated otherwise.

- Native iOS work: [ios/AGENTS.md](ios/AGENTS.md).
- Backend, migrations, OAuth, or iOS auth/RPC integration: [supabase/AGENTS.md](supabase/AGENTS.md). Preserve exact production targets, migration history, RLS, grants, and request authorization. Production remains at `api.paeonia.no` on `mdr`; access is limited to the task-authorized operation.
- Marketing routes or deployment: [marketing/AGENTS.md](marketing/AGENTS.md).

## Product-Specific Quality Bar

Paeonia handles private relationship content. Treat reliability and privacy as core product requirements.

- Never silently drop user content.
- Avoid destructive local data changes unless explicitly requested or protected by backup/migration logic.
- Make delete/export/privacy flows explicit and testable.
- Be careful with notification content; avoid exposing sensitive relationship content on locked screens without a clear setting.
- Prefer forgiving streak rules over punitive engagement mechanics.
- Make timezone behavior explicit for couple-shared rituals.

## Writing style

Cut AI tells from all prose you write or edit, including docs, comments, release notes, and user-facing copy. Scan for the patterns below, rewrite while preserving meaning and matching the intended tone, then self-audit with "What makes this obviously AI generated?" and fix what remains. If a direct quote or a file format requires the original wording, keep it correct and apply these rules to the rest. Rule numbers are stable ids. A removed rule leaves a gap.

### Content

3. **Superficial -ing phrases.** "highlighting...", "ensuring...", "reflecting...", "showcasing...", "fostering...". Delete or expand with real sources.
5. **Vague attributions.** "Experts believe", "Industry reports suggest", "Some critics argue". Name the source or delete.

### Language

7. **AI vocabulary.** Additionally, crucial, delve, enduring, enhance, fostering, garner, interplay, intricate, landscape (abstract), pivotal, showcase, tapestry (abstract), testament, underscore, vibrant. Replace with plain words.
8. **Fancy ways to say "is".** "serves as", "stands as", "boasts", "features". Just say "is" or "has".
9. **"Not just X, but Y."** State the point directly instead.
10. **Rule of three.** Forcing ideas into groups of three. Use the natural number.
11. **Synonym cycling.** Protagonist, main character, central figure, hero all in one paragraph. Pick one, repeat it.
12. **False ranges.** "from X to Y" where X and Y aren't on a meaningful scale. List topics directly.

### Style

13. **Em dash overuse.** Avoid em dashes entirely. Use periods or commas only (no parentheses, no en dashes, no hyphen-as-dash substitutes). If a thought needs separation, end the sentence or use a comma.
14. **Colon overuse.** Colons are fine before a list or example. Not as mid-sentence connectors. "If you're coming from traditional automation: instead of registering event handlers, you describe conditions" adds nothing with the colon. Rewrite to let the point stand on its own without comparison framing. "Describing when the scheduler should fire works best as plain English." Same meaning, no crutch punctuation.
15. **Boldface overuse.** Don't bold every proper noun or acronym.
16. **Inline-header lists.** The tell is a bold label and colon that restates the line: "**Performance:** Performance improved...". Convert those to prose. A bold lead-in that ends in a period, names the item, and is followed by genuinely new detail ("**Schema in TypeScript.** Tables live in one file.") is fine, not a tell.
17. **Title case headings.** Use sentence case.
18. **Decorative emojis.** Remove from headings and bullets.
19. **Curly quotes.** Replace with straight quotes.

### Communication artifacts

20. **Chatbot phrases.** "I hope this helps!", "Let me know if...", "Of course!", "Certainly!", "Found the smoking gun!" Remove.
22. **Sycophantic tone.** "Great question! You're absolutely right!" Respond directly.

### Filler

23. **Filler phrases.** "In order to" becomes "To". "Due to the fact that" becomes "Because". "It is important to note that" gets deleted.
24. **Excessive hedging.** "could potentially possibly be argued that it might" becomes "may".
25. **Generic conclusions.** "The future looks bright." State specific plans or facts.

### Jargon

26. **Abstract metaphor nouns.** Substrate, wedge, vector, locus, vantage, nexus, primitive (as noun), harness (as metaphor), surface (as in "API surface"), bedrock, scaffolding (as metaphor), modality, paradigm, gold-plating, ratchet (as metaphor), evacuate (for moving code), endgame, north star, flywheel. These read as technical but usually have a plainer concrete word. "Substrate" becomes "base". "Wedge in" becomes "add". "Vector" becomes "way" or "method". "Gold-plating" becomes "more than the job needs". "Ratchet" becomes the mechanism's real name or "a limit that only tightens". "Evacuate" becomes "move out". "Endgame" becomes "the last phase". Pick the concrete word.

### Plain speech

27. **Say what it does, not how it feels.** "the database stays close at hand", "SQL you can read", "types that follow your schema" name a feeling. The fix names the mechanism or a number: "`.toSQL()` returns the exact string sent to the database", "a column rename fails the build". Ask what the sentence tells the reader to do or know, then write that. If you can't restate it as a concrete instruction, fact, or number, cut it. One more check: if the sentence could appear unchanged in another project's docs, it says nothing about this one. Cut it.
28. **Shorten or split dense sentences.** If the reader has to backtrack to parse a sentence, break it in two or drop clauses. One idea per sentence.
29. **Active voice.** Prefer it. Catch "is/are/was/were + past participle" and name the actor: "queries are validated" becomes "the compiler validates queries", "the file is parsed by the loader" becomes "the loader parses the file". Passive is fine only when the actor is unknown or genuinely doesn't matter.
30. **Cut adverbs, or use a stronger verb.** "runs quickly" becomes "is fast" or the number. "significantly improves" becomes the measured delta. An adverb propping up a weak verb means the verb is wrong.
31. **Prefer the plain word.** "utilize" becomes "use", "leverage" becomes "use", "facilitate" becomes "help", "numerous" becomes "many", "in the event that" becomes "if". The fancier synonym is rarely clearer.
32. **Mannered prose.** Metaphor or flourish where a literal phrase exists: aphorisms ("wire it or delete it"), rhetorical fragments for effect, personified code ("the plan holds it"), figurative verbs ("rides along", "stands on"), stock framing phrases. "A dial worth turning" becomes "a parameter worth varying". Say what you mean. Rule 26 covers the metaphor nouns.
33. **Over-compression.** Dropped articles, verbless fragments, symbol-speak, and abbreviations that make the reader decode instead of read. "Parser rejects bad date → exit 2, no write" becomes "The parser rejects a bad date, exits with code 2, and writes nothing." Write whole sentences with their articles and verbs, and spell out arrows and abbreviations.

# Bro keep going

Before you stop, ask yourself "is there a next step that the user would want me to do?" if so, keep going jobs not finished.
