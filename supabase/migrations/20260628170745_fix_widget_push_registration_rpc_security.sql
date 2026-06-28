-- `authenticated` does not have USAGE on the private `internal` schema.
-- The public RPC is intentionally only a narrow wrapper, but it must run as
-- the function owner so app clients can register WidgetKit push tokens without
-- exposing the internal schema.
create or replace function public.register_widget_push_device(
  p_widget_kind text,
  p_widget_push_token text,
  p_apns_environment text,
  p_locale text default null,
  p_time_zone_id text default null,
  p_app_version text default null
)
returns uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.register_widget_push_device(
    p_widget_kind,
    p_widget_push_token,
    p_apns_environment,
    p_locale,
    p_time_zone_id,
    p_app_version
  );
$$;

revoke all on function public.register_widget_push_device(text, text, text, text, text, text) from public, anon;
grant execute on function public.register_widget_push_device(text, text, text, text, text, text) to authenticated, service_role;
