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
- Use service-role flows only for privileged work: cron, cleanup, admin deletion, notification fanout, and internals.
- Use the Supabase CLI to create migration files when implementation starts.
- Start with the migration order listed in `docs/phase-3-migration-checklist.md`.
- Do not deploy or apply remote migrations until the project is intentionally linked.

Content tracking:

- `questions/` holds source-controlled structure for database-authored question content, versions, and locales. Question catalog rows are content; migrations are only for schema and database behavior changes.

PostgREST implementation notes:

- iOS table writes must always include an explicit row filter. RLS still enforces ownership, but production rejects unfiltered `UPDATE`/`DELETE` statements before RLS can scope them.
- User-scoped RPC writes should only be sent when the Supabase client has an active auth session; otherwise local-first pending sync should retry later.
- Public RPC wrappers that call private `internal.*` functions must be thin `security definer` wrappers with a fixed `search_path`; private implementations must perform `auth.uid()` authorization checks.

## Agent Quick Reference

Previous agents repeatedly looked up the same Supabase context. Use this as the backend starting point before broad searching:

- Product/data decisions: `docs/phase-3-data-contract.md`.
- SQL implementation order and RLS helper checklist: `docs/phase-3-migration-checklist.md`.
- Question content source tree: `supabase/questions/README.md` and `supabase/questions/system/*`.
- Edge Functions: `supabase/functions/`; deploy with Supabase CLI.
- Local config: `supabase/config.toml`.

Common local checks agents have needed:

```bash
supabase --version
DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 supabase db lint --local --schema public,internal --fail-on error
DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 supabase db reset --local --no-seed
```

Use Orbstack's Docker socket on this machine when Supabase CLI needs Docker. Do not push remote migrations from the CLI; commit migration files and let the configured Supabase GitHub integration apply them after the branch is pushed intentionally.
