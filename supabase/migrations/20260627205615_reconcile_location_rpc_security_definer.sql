-- Reconcile committed source with production for location RPC wrappers.
--
-- These public functions are intentionally thin `security definer` wrappers
-- around private `internal.*` implementations. `authenticated` does not have
-- USAGE on the private `internal` schema, so `security invoker` wrappers fail
-- before the implementation can enforce auth.uid()-based checks.
--
-- The function bodies stay unchanged; authorization remains inside the
-- internal implementations. Re-running against production is a no-op.

alter function public.get_partner_location_visibility(uuid)
  security definer;

alter function public.get_partner_location_visibility(uuid)
  set search_path = pg_catalog;

alter function public.update_location_sharing_preference(
  uuid,
  boolean,
  text,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
)
  security definer;

alter function public.update_location_sharing_preference(
  uuid,
  boolean,
  text,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
)
  set search_path = pg_catalog;

alter function public.update_latest_partner_location(
  uuid,
  numeric,
  numeric,
  numeric,
  timestamptz,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
)
  security definer;

alter function public.update_latest_partner_location(
  uuid,
  numeric,
  numeric,
  numeric,
  timestamptz,
  text,
  uuid,
  uuid,
  bigint,
  timestamptz
)
  set search_path = pg_catalog;
