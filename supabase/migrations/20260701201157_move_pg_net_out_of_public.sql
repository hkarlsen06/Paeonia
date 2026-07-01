-- Move pg_net out of the public schema (Supabase linter 0014_extension_in_public,
-- WARN: "Extension `pg_net` is installed in the public schema. Move it to another
-- schema.").
--
-- pg_net 0.20.3 is non-relocatable (pg_extension.extrelocatable = false), so
-- ALTER EXTENSION pg_net SET SCHEMA extensions is rejected. Re-anchoring the
-- extension therefore requires DROP + CREATE. pg_net always creates its callable
-- objects in the dedicated `net` schema regardless of the extension's anchor
-- schema, so the fully-qualified callers keep resolving after the move:
--   - public.invoke_media_storage_cleanup  -> net.http_post(...)
--   - public.invoke_widget_push_drain      -> net.http_post(...)
-- Both are SECURITY DEFINER owned by postgres, and net.http_post keeps its
-- default (PUBLIC EXECUTE) function grant on recreate, so callability is
-- unchanged; only pg_extension.extnamespace flips public -> extensions.
--
-- Safe to DROP without CASCADE: no object holds a hard dependency on the
-- extension (the PL/pgSQL callers reference net.http_post at runtime only, which
-- does not record a catalog dependency). Dropping clears any transient rows in
-- net.http_request_queue / net._http_response, which is acceptable for an async
-- fire-and-forget HTTP queue.
--
-- Guarded so the migration is a no-op once pg_net is already anchored outside
-- public, and so a fresh `supabase db reset` (where an earlier migration first
-- installs pg_net into public) still lands it in extensions.

do $$
declare
  v_schema text;
begin
  select n.nspname
    into v_schema
  from pg_extension e
  join pg_namespace n on n.oid = e.extnamespace
  where e.extname = 'pg_net';

  if v_schema = 'public' then
    execute 'drop extension pg_net';
    execute 'create extension pg_net with schema extensions';
  elsif v_schema is null then
    execute 'create extension pg_net with schema extensions';
  end if;
  -- Already outside public: nothing to do.
end
$$;
