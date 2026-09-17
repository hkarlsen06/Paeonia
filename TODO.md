## Adopt Supabase declarative schemas with pg-delta

Decision: adopted on 2026-07-23 with Supabase CLI 2.109.1. `supabase/schemas/`
is the readable DDL source of truth; migrations remain immutable deployment and
transition history.

- [x] Verified the supported CLI surface: `supabase db diff --use-pg-delta`,
  `schema_paths`, and `supabase/schemas/*.sql`; the public-alpha sync command is
  obsolete.
- [x] Inventoried tables, constraints, indexes, RLS, functions, triggers,
  views, grants, extensions, cron, Storage, and schema-adjacent data.
- [x] Documented the hand-written migration lane for data, managed or
  unsupported state, privileges, renames, and destructive transitions.
- [x] Generated the baseline from an unseeded clean migration reset and proved
  zero-diff parity both locally and against the linked Paeonia project.
- [x] Kept Auth and Storage platform schemas managed while explicitly
  round-tripping Paeonia's two Auth triggers and two Storage policies.
- [x] Defined one readable source of truth; do not introduce a competing
  `supabase/sql/` function or policy tree.
- [x] Kept migration generation and application as a reviewed step; applied
  migrations are never rewritten.
- [x] Exercised the existing history's additive, rename, type, function,
  trigger, view, grant, and policy transitions through a clean replay and
  rejected pg-delta's redundant default-privilege noise.
- [x] Preserved the deployment contract after the 2026-09-01 move to
  self-hosted Supabase on `mdr`: only new migrations deploy; declarative files
  remain review and drift inputs.
- [x] Added contributor guidance and a CI drift, reset, lint, and pgTAP gate.

References: [Supabase declarative database schemas](https://supabase.com/docs/guides/local-development/declarative-database-schemas) and [pg-delta public-alpha announcement](https://github.com/orgs/supabase/discussions/44938).
