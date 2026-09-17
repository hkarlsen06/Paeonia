# Question Catalog Content

This folder tracks source-controlled content for database-authored Paeonia questions.
Schema changes still belong in `supabase/migrations/`; question rows are content.

Before adding, versioning, or localizing questions, follow
`docs/couple-question-guidelines.md`.

## Structure

Use collection folders that match `public.question_collections.kind`:

```text
supabase/questions/
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
`-- mini_game/
```

`<question_key>` maps to `public.questions.key` and should stay stable for the
same prompt intent. Version folders map to
`public.question_versions.version_number` using zero-padded names such as `v001`
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
  `resurface_after_months`.
- `version.md`: `version_number`, `status`, `active_from`, `retired_at`,
  `answer_kinds`.
- `locales/<locale>.md`: `locale`, `prompt`, `short_prompt`.

Keep generated database metadata intact when backfilling existing rows. For new
drafts, use the same fields with draft status until content is applied.

## Sync Script

Use `scripts/sync-question-catalog` from the repository root to validate and
upload source-controlled question content.

```bash
scripts/sync-question-catalog --database-url "$PAEONIA_MDR_DB_URL"
scripts/sync-question-catalog --database-url "$PAEONIA_MDR_DB_URL" --apply
```

Do not use `--linked` for production; it targets the retired hosted project.
The MDR database URL must be percent-encoded and typically points through an
SSH tunnel, like `scripts/supabase-db.sh` uses.

The default mode is a dry run: it reads the database, reports new question keys,
new version folders, missing localizations, and status changes, but does not
write. `--apply` uploads pending changes with one transaction. For MCP or
SQL-editor workflows, use `scripts/sync-question-catalog --emit-sql`.

Existing version prompts, short prompts, and answer kinds are immutable. If the
script reports drift for an existing version, create the next `vNNN` folder
instead of editing the old version in place.
