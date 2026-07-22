## Evaluate Supabase declarative schemas with pg-delta

Research and, if the current Supabase workflow proves safe for Paeonia, adopt declarative schema files as the readable source of truth while retaining versioned migrations as the deployment and transition history.

- [ ] Verify the currently supported Supabase CLI version, commands, configuration, and directory convention from the official documentation; do not rely on the original public-alpha `db schema declarative sync` interface if it has been superseded.
- [ ] Inventory the existing `supabase/migrations/` schema surface: tables, types, constraints, indexes, RLS policies, functions, triggers, views, grants, extensions, cron jobs, publications, Storage configuration, and any schema-adjacent data.
- [ ] Document which objects pg-delta cannot safely or completely represent. Keep DML/data transforms, extension-managed state, and unsupported objects in explicit hand-written migrations.
- [ ] Generate an initial `supabase/schemas/` baseline from the migration-reconstructed local database, then compare it with the linked Paeonia project and explain every difference before accepting it.
- [ ] If `supabase/sql/` source files are introduced or already exist, define how they map into the declarative structure so functions and policies do not acquire two competing sources of truth.
- [ ] Trial the edit -> `supabase db diff -f <name>` -> review -> `supabase migration up` workflow on a disposable branch/local database. Never rewrite already-applied migrations.
- [ ] Test additive, rename, type-change, function, trigger, view, grant, and RLS-policy changes. Confirm generated migrations preserve data and do not introduce unexpected drops, locks, privilege changes, or RLS regressions.
- [ ] Prove reproducibility with a clean local reset and representative seed data, then run Supabase security and performance advisors against the result.
- [ ] Confirm the generated migrations remain compatible with Paeonia's Supabase GitHub integration deployment flow.
- [ ] If adopted, update `AGENTS.md` and contributor commands, add a CI drift/diff check where practical, and require declarative files plus reviewed generated migrations in the same change.

References: [Supabase declarative database schemas](https://supabase.com/docs/guides/local-development/declarative-database-schemas) and [pg-delta public-alpha announcement](https://github.com/orgs/supabase/discussions/44938).
