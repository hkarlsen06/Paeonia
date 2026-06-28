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
same prompt intent. Version folders map to `public.question_versions.version_number`
using zero-padded names such as `v001` and `v002`.

Each version should track its answer kind contract in `version.md`. Locale files
map to `public.question_version_localizations` and must include both required
locales, `en` and `nb`, with the full prompt and short prompt.

When a prompt meaning, short prompt meaning, answer kinds, or meaningful
localization changes, add a new version folder instead of editing a historical
version in place.

## File Format

Use YAML front matter in each file:

- `question.md`: `collection`, `key`, `status`, `resurfaceable`, and
  `resurface_after_months`.
- `version.md`: `version_number`, `status`, `active_from`, `retired_at`, and
  `answer_kinds`.
- `locales/<locale>.md`: `locale`, `prompt`, and `short_prompt`.

Keep generated database metadata intact when backfilling existing rows. For new
drafts, use the same fields with draft status until the content is applied.
