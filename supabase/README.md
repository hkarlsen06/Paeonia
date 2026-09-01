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
- Production runs self-hosted on `mdr`; apply migrations with `./scripts/supabase-db.sh push` and deploy edge functions by syncing `supabase/functions/` to `/srv/paeonia/paeonia-sb/volumes/functions/` on mdr and restarting the `functions` service.

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
DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 ./scripts/check-supabase-schema-drift.sh
DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 supabase db lint --local --schema public,internal --fail-on error
DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 supabase db reset --local --no-seed
DOCKER_HOST=unix:///Users/hjalmarkarlsen/.orbstack/run/docker.sock SUPABASE_TELEMETRY_DISABLED=1 supabase test db --local supabase/tests
```

Use Orbstack's Docker socket on this machine when Supabase CLI needs Docker. Do not push remote migrations from the CLI; commit migration files and let the configured Supabase GitHub integration apply them after the branch is pushed intentionally.

## Declarative Schema Workflow

`supabase/schemas/` is the readable current database definition. The migration
directory remains the immutable record of how production moves between those
states.

For ordinary DDL:

1. Edit the ordered schema files.
2. Run `supabase db diff --use-pg-delta -f <migration_name>`.
3. Review the generated migration for data loss, table rewrites, locks, RLS,
   ownership, and privilege changes.
4. Replace unsafe or unsupported output with a hand-written migration.
5. Run `supabase migration up --local`, the drift checker, lint, and the
   relevant pgTAP tests.
6. Commit the declarative state and migration together.

The declarative files cover Paeonia-owned tables, constraints, indexes,
functions, triggers, views, RLS policies, comments, and current ACL state.
`98_managed_schema_integrations.sql` separately declares Paeonia's two
`auth.users` triggers and two `storage.objects` policies without claiming
ownership of the managed schemas. `99_acl_normalization.sql` must remain last.

Use a hand-written migration for DML and backfills, question/content changes,
Storage bucket rows, extensions, cron, publications, privileges and ownership,
renames, destructive or data-dependent type transitions, policy renames, and
view ownership or column-order transitions. When such a migration changes
representable final DDL, update `supabase/schemas/` in the same change.

Never edit an applied migration and do not add a second canonical
`supabase/sql/` tree. The retired public-alpha
`supabase db schema declarative sync` command is not part of this workflow.

## Account Deletion Operations

`public.request_account_deletion()` is the irreversible data boundary: it ends
the current relationship, anonymizes the profile, removes device/location/
notification state, and creates `internal.account_deletion_jobs`. The
`delete-account` Edge Function owns Sign in with Apple revocation, global Auth
sign-out, and final Auth-user deletion. The queue is retried by `pg_cron` and is
safe to drain more than once.

Required Edge Function configuration:

- Supabase's platform-provided `SUPABASE_PUBLISHABLE_KEYS`,
  `SUPABASE_SECRET_KEYS`, and `SUPABASE_JWKS` environment variables, resolved by
  `@supabase/server`
- `DRAIN_SECRET`
- `APPLE_SIGN_IN_TEAM_ID`
- `APPLE_SIGN_IN_KEY_ID`
- `APPLE_SIGN_IN_PRIVATE_KEY`
- `APPLE_SIGN_IN_CLIENT_ID` (defaults to `no.paeonia.app`)

The value in `DRAIN_SECRET` must match the Vault secret named
`account_deletion_drain_secret`. The migration can fall back to the existing
`media_storage_cleanup_secret` or `widget_drain_secret`, but a dedicated secret
is preferred. Never put Apple authorization codes, access tokens, refresh
tokens, or client secrets in database rows, logs, or support notes.

If automatic Apple revocation cannot run, the job records
`manual_required`, Paeonia/Auth deletion continues immediately, and the app
directs the user to Apple Account settings. This follows Apple's documented
fallback and must be verified on a real Sign in with Apple account before
release.

For an `attention_required` job, inspect the Edge Function/Auth logs using the
job ID, fix the underlying configuration or Auth/Storage constraint, then call
`public.retry_account_deletion_job(job_id)` with a secret/service-role client.
Do not mark a job complete manually unless the Auth user is confirmed absent.

## Moderation Report Operations

MVP moderation is a trusted SQL runbook, not a client/admin role. Use a secure
SQL session with the `service_role`; never put a service-role key in the app or
copy report snapshots into tickets, chat, or ordinary logs.

1. Open the report and its single target. Treat the snapshot as private user
   content and view it only when needed to decide the case.

   ```sql
   select
     report.id,
     report.status,
     report.reason,
     report.note,
     report.block_requested,
     report.leave_requested,
     report.created_at,
     target.target_kind,
     coalesce(
       target.daily_answer_id,
       target.memory_id,
       target.memory_note_id,
       target.memory_media_id,
       target.message_id,
       target.message_media_message_id,
       target.widget_drawing_revision_id,
       target.media_asset_id,
       target.profile_user_id,
       target.conduct_user_id
     ) as target_id,
     target.message_media_asset_id as target_aux_id
   from public.content_reports report
   join public.content_report_targets target on target.report_id = report.id
   where report.id = '<report-id>'::uuid;

   select snapshot
   from internal.report_snapshots
   where report_id = '<report-id>'::uuid;
   ```

2. Apply exactly one reviewed action through the audited internal function.
   Replace the operator identifier with the human operator and case reference.

   ```sql
   begin;

   select internal.apply_report_moderation_action(
     p_report_id := '<report-id>'::uuid,
     p_action_kind := 'hide',
     p_operator_kind := 'sql_runbook',
     p_operator_identifier := 'operator@example.com / case-123',
     p_reason := 'policy reason',
     p_notes := 'concise decision notes'
   );

   commit;
   ```

   Common content actions are `hide` (reversible), `remove` (remove and queue
   linked media cleanup), and `restore` (only content changed by this same
   report). `delete_storage` is for a reviewed target with storage assets and
   fails when none exist. For conduct reports use `block_pair`, `unblock_pair`,
   or `clear_pair_warning`; report submission already creates the warning, and
   report-and-leave already ends the relationship. `unblock_pair` clears every
   active block for that pair, so inspect the pair's active blocks before using
   it. Do not update report, moderation, block, or content status columns
   directly.

3. Verify the report and audit row before leaving the session.

   ```sql
   select status, resolved_at
   from public.content_reports
   where id = '<report-id>'::uuid;

   select action_kind, status, operator_identifier, reason, created_at
   from internal.moderation_actions
   where report_id = '<report-id>'::uuid
   order by created_at desc;
   ```

The audited action sets report resolution state and starts the report snapshot
retention clock. Storage deletion stays queued for the existing cleanup worker;
do not delete Storage objects or snapshot rows by hand.
