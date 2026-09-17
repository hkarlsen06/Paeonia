# Supabase agent guidance

Paths and commands below are relative to the repository root. These rules also apply when changing iOS auth, RPC, or backend client integrations.

## Supabase Guidelines

Production Supabase API domain: `api.paeonia.no`.
Production Supabase is self-hosted on the `mdr` server.

When configuring OAuth providers, include the Supabase Auth callback on the custom domain:

```text
https://api.paeonia.no/auth/v1/callback
```

For Google OAuth client setup, use `https://paeonia.no` as the web origin and `https://api.paeonia.no/auth/v1/callback` as the authorized redirect URI.

### Production Access

Agents may access production directly with `ssh mdr`. The Paeonia stack is at
`/srv/paeonia/paeonia-sb`; use `docker compose` there to inspect logs and
services or make task-authorized service changes, and use
`docker compose exec -T db psql -U postgres -d postgres` for direct database
inspection or task-authorized data mutations. Direct SSH is the normal
production access path, so do not block on Supabase MCP or the hosted dashboard.

Use migrations rather than ad hoc SQL for schema changes. Use
`./scripts/supabase-db.sh` when migration tracking or another Supabase CLI
database operation is required. Do not use bare remote CLI commands or
`--linked`; they target the retired hosted project unless explicitly
reconfigured and verified.

### PostgREST Client Calls

- Client-side Supabase table writes must include an explicit row filter such as `.eq("user_id", value: session.user.id.uuidString)`. Do not rely on RLS alone to scope `update` or `delete` calls; production rejects unfiltered writes before RLS policies are applied.
- Before user-scoped RPC writes from the iOS app, make sure the Supabase client has an active `client.auth.session`. If no session exists, fail locally and let local-first pending sync retry after auth is restored instead of sending anonymous PostgREST requests.
- Keep public RPC wrappers for app-callable functions as thin wrappers around private `internal.*` implementations.

#### App-callable public RPC wrappers that call `internal.*` MUST be `security definer` (this keeps recurring)

This is the single most common backend regression in this repo. A `public.*` RPC wrapper callable by `authenticated` whose body calls any `internal.*` function **must** be declared `security definer` with a fixed `search_path`. `authenticated` has **no USAGE on the `internal` schema**, so a `security invoker` wrapper that reaches into `internal.*` fails for every signed-in user.

- Symptom: PostgREST returns `permission denied for schema internal` with SQLSTATE `42501`; the Postgres log `context` reads `SQL function "<your_wrapper>" during startup`. The feature works for nobody and there is no client-side clue.
- Default to copy for any new app-callable wrapper:

  ```sql
  create or replace function public.my_rpc(...)
  returns ...
  language sql
  security definer            -- REQUIRED: authenticated has no USAGE on `internal`
  set search_path = pg_catalog -- REQUIRED with security definer
  as $$
    select * from internal.my_rpc(...);
  $$;

  revoke all on function public.my_rpc(...) from public, anon;
  grant execute on function public.my_rpc(...) to authenticated, service_role;
  ```

- `security definer` does **not** weaken auth here: `auth.uid()` reads the request JWT regardless of the executing role, so authorization stays enforced inside the `internal.*` implementation (via `auth.uid()` / `internal.get_current_entitled_couple_id()`). The wrapper is definer only so it can *reach* the private schema.
- `security invoker` is correct for public wrappers whose body touches `public.*` / RLS-protected tables and never `internal.*`.
- `security invoker` is also acceptable for service-role-only maintenance/drain wrappers that call `internal.*`, but only when all of these are true: `anon` and `authenticated` have no `execute`, `service_role` has `execute`, and `search_path` is pinned to `pg_catalog`. This keeps the wrapper unusable if someone accidentally grants it to app users later.
- Before committing a new app-callable wrapper, grep the migration: if the body contains `internal.` and the function is callable by `authenticated` but is not `security definer`, it is wrong. Prior offenders and the fix pattern: `20260627190239_reconcile_daily_rpc_security_definer.sql`, `20260625093000_harden_public_rpc_wrappers_after_relationship_state.sql`, `20260629000405_fix_daily_history_rpc_security_definer.sql`.
- An already-applied migration cannot be edited into production. Fix a deployed wrapper with a new migration that `create or replace`s it as `security definer`; leave the original migration as the historical record.

### Edge Functions

- Edit Edge Functions locally in `supabase/functions/`.
- Deploy by syncing `supabase/functions/` to `/srv/paeonia/paeonia-sb/volumes/functions/` on `mdr` and restarting the `functions` service.
- For direct user-called functions, do not enable Supabase's "Verify JWT with legacy secret" / platform `verify_jwt` gate when the app uses modern publishable keys. Set `verify_jwt = false` in `supabase/config.toml` and perform auth inside the function with the request `Authorization` header and `auth.getUser()`.
- Edge Functions that need user auth should read modern `SUPABASE_PUBLISHABLE_KEYS` / `SUPABASE_SECRET_KEYS` when available, with legacy key env vars only as local compatibility fallbacks.

### SQL And Migrations

- `supabase/schemas/*.sql` is the readable current-state source for DDL that pg-delta can reproduce. Files run in lexical order: keep ordinary declarations before `98_managed_schema_integrations.sql`, and keep `99_acl_normalization.sql` last.
- `supabase/migrations/` remains the immutable deployment and transition history. Always create new migration files with `supabase migration new <migration_name>`, then edit the generated file. Never rewrite an already-applied migration.
- For representable DDL, edit the declarative schema first, generate a migration with `supabase db diff --use-pg-delta -f <name>`, review every statement, and apply it locally with `supabase migration up --local`. Commit the schema files and reviewed migration together.
- Do not introduce `supabase/sql/` as another canonical function or policy tree. Paeonia has one readable current-state source in `supabase/schemas/`.
- Keep these changes in explicit hand-written migrations even when the final representable state is also updated declaratively:
  - DML, backfills, seed/content changes, and other data-dependent transitions
  - extension lifecycle or schema moves
  - `storage.buckets` rows and configuration
  - cron schedules and unschedule/reschedule operations
  - publication membership
  - grants, revokes, ownership, default privileges, and column privileges
  - renames, destructive changes, type changes that depend on existing data, policy renames, and view ownership or column-order transitions
- Treat generated migrations as proposals, not trusted output. Reject unexpected drops, table rewrites, locks, privilege changes, or RLS changes and replace them with a safe hand-written transition.
- Preserve and explicitly round-trip the Paeonia-owned objects attached to managed schemas: both triggers on `auth.users` and both policies on `storage.objects`. Do not dump or declare Supabase-owned Auth or Storage internals wholesale.
- Preserve `security_invoker` view options, RLS state, function `security definer`/`search_path` settings, comments, triggers, and ACLs. The existing rule for authenticated public wrappers that call `internal.*` remains mandatory.
- Run `./scripts/check-supabase-schema-drift.sh` after schema or migration changes. A non-empty pg-delta result means the declarative state and migration history disagree and must be reconciled before commit.
- Production Supabase is self-hosted on the `mdr` server (since 2026-09-01), so nothing applies migrations automatically on git push. Apply them with `./scripts/supabase-db.sh push` (add `--dry-run` first to preview). The script tunnels to the mdr database over SSH and passes `--db-url`; do not use `--linked`, the hosted project is gone.
- The CLI applies only migrations missing from the remote history and records each under its file version.
- New migrations should be rerunnable where the operation allows it: prefer `create or replace` / `drop ... if exists`. To change a function's return type (which `create or replace` cannot do), `drop function if exists` and recreate it in the same reviewed migration.
- Use `./scripts/supabase-db.sh pull` only when intentionally baselining or reconciling remote-first schema changes.
- For local Supabase verification, inspect the active Docker context (`docker context show` / `docker context inspect`) and any existing `DOCKER_HOST` override, then verify connectivity with `docker info`. Use the configured local engine; do not hardcode a home-directory socket or change global Docker settings. If the selected local engine is stopped, start it and retry. Never substitute a production Docker endpoint for a local test environment.
