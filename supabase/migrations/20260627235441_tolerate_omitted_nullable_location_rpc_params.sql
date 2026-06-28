-- Swift Encodable omits nil optional fields by default. Keep the original
-- full RPC signatures, but add public overloads for nullable arguments that
-- can be absent in already-built clients.

create or replace function public.update_location_sharing_preference(
  p_couple_id uuid,
  p_is_enabled boolean,
  p_source text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  couple_id uuid,
  user_id uuid,
  is_enabled boolean,
  enabled_at timestamptz,
  disabled_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.update_location_sharing_preference(
    p_couple_id,
    p_is_enabled,
    null::text,
    p_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

revoke all on function public.update_location_sharing_preference(
  uuid,
  boolean,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
) from public, anon;
grant execute on function public.update_location_sharing_preference(
  uuid,
  boolean,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
) to authenticated, service_role;

create or replace function public.update_latest_partner_location(
  p_couple_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_captured_at timestamptz,
  p_source text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  couple_id uuid,
  user_id uuid,
  latitude numeric,
  longitude numeric,
  accuracy_m numeric,
  captured_at timestamptz,
  received_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.update_latest_partner_location(
    p_couple_id,
    p_latitude,
    p_longitude,
    null::numeric,
    p_captured_at,
    p_source,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

revoke all on function public.update_latest_partner_location(
  uuid,
  numeric,
  numeric,
  timestamptz,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
) from public, anon;
grant execute on function public.update_latest_partner_location(
  uuid,
  numeric,
  numeric,
  timestamptz,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
) to authenticated, service_role;

notify pgrst, 'reload schema';
