# Paeonia Supabase

Supabase backend planning surface.

Do not create schema migrations until the implementation slice is checked against:

- `docs/phase-3-data-contract.md`
- `docs/phase-3-migration-checklist.md`

Current backend decisions:

- Use Supabase.
- Use Supabase Auth with Sign in with Apple and Google Sign-In for MVP.
- Do not support a separate sign-up page, passkey flow, email/password, or email magic-link auth for MVP.
- Enable RLS by default.
- Use the database as the source of truth for couple membership and shared subscription entitlement.
- Use service-role flows only for privileged work such as cron cleanup, admin deletion, and notification fanout internals.
- Use the Supabase CLI to create migration files when implementation starts.
- Start with the migration order listed in `docs/phase-3-migration-checklist.md`.
- Do not deploy or apply remote migrations until a project is intentionally linked.

Content tracking:

- `questions/` holds source-controlled structure for database-authored question
  content, versions, and locales. Question catalog rows are content; migrations
  are only for schema or database behavior changes.

PostgREST implementation notes:

- iOS table writes must always include an explicit row filter. RLS still enforces ownership, but production rejects unfiltered `UPDATE`/`DELETE` statements before RLS can scope them.
- User-scoped RPC writes should only be sent when the Supabase client has an active auth session; otherwise local-first pending sync should retry later.
- Public RPC wrappers that call private `internal.*` functions must be thin `security definer` wrappers with a fixed `search_path`; the private implementation must perform the `auth.uid()` authorization checks.
