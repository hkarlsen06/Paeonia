# Question Catalog Content

This folder tracks source-controlled content for Paeonia questions.
Schema changes belong in `backend/convex/schema.ts`; question rows are content.

Before adding, versioning, or localizing questions, follow
`docs/couple-question-guidelines.md`.

## Structure

Use collection folders that match `question_collections.kind`:

```text
backend/questions/
|-- system/
|   `-- <question_key>/
|       |-- question.md
|       `-- versions/
|           `-- v001/
|               |-- version.md
|               `-- locales/
|                   |-- en.md
|                   `-- nb.md
|-- custom/
|-- mini_game/
`-- topic/          (see Topics below)
```

`<question_key>` maps to `questions.key` and should stay stable for the
same prompt intent. Version folders map to
`question_versions.version_number` using zero-padded names such as `v001`
and `v002`.

Each version tracks its answer-kind contract in `version.md`. Locale files map to
`public.question_version_localizations` and must include the required locales,
`en` and `nb`, with full and short prompts.

When prompt meaning, short prompt meaning, answer kinds, or meaningful
localization changes, add a new version folder instead of editing a historical
version in place.

## File Format

Use YAML front matter in each file:

- `question.md`: `collection`, `key`, `status`, `resurfaceable`,
  `resurface_after_months`, and for topic questions `topic` and `sort_order`.
- `version.md`: `version_number`, `status`, `active_from`, `retired_at`,
  `answer_kinds`.
- `locales/<locale>.md`: `locale`, `prompt`, `short_prompt`, and for an
  `either_or` version also `option_a` and `option_b` (the two labels, 1-40
  characters, same `>-` block style). `either_or` combines only with `text`.

Keep generated database metadata intact when backfilling existing rows. For new
drafts, use the same fields with draft status until content is applied.

## Topics

Each topic is its own collection under `topic/`, with its questions inside it:

```text
topic/
`-- <topic_key>/
    |-- topic.md
    |-- locales/
    |   |-- en.md
    |   `-- nb.md
    `-- <question_key>/
        |-- question.md
        `-- versions/v001/...
```

- `topic.md`: `key`, `status`, `sort_order` (the shelf order), `private` (true
  for Flirt: its chat pushes name only the sender).
- `locales/<locale>.md`: `locale`, `title` (1-60 characters), `subtitle` (at
  most 160).
- A topic's `question.md` adds `topic` (the topic key) and `sort_order` (the
  order inside the topic, easiest first). Topic questions use
  `resurfaceable: false` and `resurface_after_months: null`, because a couple
  answers each one once.

The topic's `status` decides whether the app shows it. A draft topic stays
hidden even when its questions are active. Read the Topics and Flirt sections
of `docs/couple-question-guidelines.md` before writing topic questions.

## Sync Script

Use `scripts/sync-question-catalog` from the repository root to validate and
upload source-controlled question content. It parses this folder, then runs the
internal mutation `catalog:sync_catalog` with `npx convex run` from `backend/`.

```bash
scripts/sync-question-catalog
scripts/sync-question-catalog --apply
scripts/sync-question-catalog --emit-json
```

The target deployment comes from `backend/.env.local` for dev. For the hosted
deployment at `api.paeonia.no`, export `CONVEX_SELF_HOSTED_URL` and `CONVEX_SELF_HOSTED_ADMIN_KEY` in the shell, and set `CONVEX_DEPLOYMENT=` (empty) so the CLI ignores the dev deployment in `.env.local`,
first. Never commit either value.

The default mode is a dry run. It reads the deployment and reports new question
keys, new version folders, missing localizations, and status changes. It does
not write. `--apply` uploads the pending changes in chunks of 30 questions, after
a dry run of every chunk found no errors. `--emit-json` prints the payload and
exits, without contacting a deployment.

Existing version prompts, short prompts, and answer kinds are immutable. If the
script reports drift for an existing version, create the next `vNNN` folder
instead of editing the old version in place. An active version needs both `en`
and `nb` localizations and one or two answer kinds. The sync rejects anything
else.
