-- Keep privileged implementation details out of the client-visible API surface.
--
-- Earlier foundation migrations granted authenticated users USAGE on `internal`
-- plus EXECUTE on selected internal functions so `public` invoker wrappers and
-- Storage policies could reach the implementation functions. The intended
-- final shape is stricter: clients call only public RPC wrappers and Storage
-- policies call Storage-local helpers. The `internal` schema remains private
-- and is not included in the Supabase Data API schemas.

do $$
declare
  fn record;
begin
  for fn in
    select
      p.oid,
      n.nspname,
      p.proname,
      pg_get_function_identity_arguments(p.oid) as arguments
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prokind = 'f'
      and pg_get_functiondef(p.oid) like '%internal.%'
  loop
    execute format(
      'alter function %I.%I(%s) security definer',
      fn.nspname,
      fn.proname,
      fn.arguments
    );

    execute format(
      'alter function %I.%I(%s) set search_path = pg_catalog',
      fn.nspname,
      fn.proname,
      fn.arguments
    );
  end loop;
end $$;

create schema if not exists storage_private;
revoke all on schema storage_private from public, anon, authenticated;
grant usage on schema storage_private to authenticated, service_role;

create or replace function storage_private.paeonia_can_upload_reserved_media_object(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.can_upload_reserved_media_object(p_bucket_id, p_name);
$$;

create or replace function storage_private.paeonia_can_read_media_object(
  p_bucket_id text,
  p_name text
)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.can_read_media_object(p_bucket_id, p_name);
$$;

drop policy if exists paeonia_media_pending_upload_insert on storage.objects;
drop policy if exists paeonia_media_visible_select on storage.objects;

create policy paeonia_media_pending_upload_insert
on storage.objects
for insert
to authenticated
with check (storage_private.paeonia_can_upload_reserved_media_object(bucket_id, name));

create policy paeonia_media_visible_select
on storage.objects
for select
to authenticated
using (storage_private.paeonia_can_read_media_object(bucket_id, name));

revoke usage on schema internal from public, anon, authenticated;
revoke execute on all functions in schema internal from public, anon, authenticated;

revoke all on function storage_private.paeonia_can_upload_reserved_media_object(text, text) from public, anon, authenticated;
revoke all on function storage_private.paeonia_can_read_media_object(text, text) from public, anon, authenticated;
grant execute on function storage_private.paeonia_can_upload_reserved_media_object(text, text) to authenticated, service_role;
grant execute on function storage_private.paeonia_can_read_media_object(text, text) to authenticated, service_role;

revoke execute on all functions in schema public from public, anon;
grant execute on all functions in schema public to authenticated, service_role;
grant execute on all functions in schema internal to service_role;

alter default privileges in schema internal revoke all on functions from public, anon, authenticated;
alter default privileges in schema internal grant execute on functions to service_role;
