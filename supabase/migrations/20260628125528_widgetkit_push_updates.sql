-- Real WidgetKit push updates:
-- * WidgetKit push tokens are separate from normal app APNs device tokens.
-- * APNs uses topic `<bundle id>.push-type.widgets`, push type `widgets`,
--   and payload `{"aps":{"content-changed":true}}`.
-- * The existing app silent push remains as a fallback for syncing data into
--   the App Group before WidgetKit asks the extension for a new timeline.

create table public.widget_push_devices (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete restrict,
  widget_kind text not null,
  widget_push_token text not null,
  widget_push_token_hash bytea not null,
  apns_environment text not null,
  locale text,
  time_zone_id text,
  app_version text,
  last_seen_at timestamptz not null default now(),
  revision integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  disabled_at timestamptz,

  constraint widget_push_devices_widget_kind_check
    check (char_length(btrim(widget_kind)) between 1 and 128),
  constraint widget_push_devices_token_check
    check (char_length(widget_push_token) between 20 and 4096),
  constraint widget_push_devices_token_hash_check
    check (octet_length(widget_push_token_hash) = 32),
  constraint widget_push_devices_apns_environment_check
    check (apns_environment in ('sandbox', 'production')),
  constraint widget_push_devices_locale_check
    check (locale is null or char_length(btrim(locale)) between 2 and 64),
  constraint widget_push_devices_time_zone_id_check
    check (time_zone_id is null or char_length(btrim(time_zone_id)) between 1 and 128),
  constraint widget_push_devices_app_version_check
    check (app_version is null or char_length(btrim(app_version)) between 1 and 64),
  constraint widget_push_devices_revision_check
    check (revision > 0)
);

create trigger touch_widget_push_devices_updated_at_and_revision
before update on public.widget_push_devices
for each row
execute function internal.touch_updated_at_and_revision();

create unique index widget_push_devices_active_token_environment_kind_idx
on public.widget_push_devices (widget_push_token_hash, apns_environment, widget_kind)
where disabled_at is null;

create index widget_push_devices_user_id_idx
on public.widget_push_devices (user_id)
where disabled_at is null;

alter table public.widget_push_devices enable row level security;

create policy "Users can read their own widget push devices"
on public.widget_push_devices
for select
to authenticated
using ((select auth.uid()) = user_id);

revoke all on public.widget_push_devices from public, anon, authenticated;
grant all privileges on public.widget_push_devices to service_role;
grant select (
  id,
  user_id,
  widget_kind,
  apns_environment,
  locale,
  time_zone_id,
  app_version,
  last_seen_at,
  revision,
  created_at,
  updated_at,
  disabled_at
) on public.widget_push_devices to authenticated;

create or replace function internal.register_widget_push_device(
  p_widget_kind text,
  p_widget_push_token text,
  p_apns_environment text,
  p_locale text default null,
  p_time_zone_id text default null,
  p_app_version text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  token_hash bytea;
  registered_device_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_widget_kind is null or char_length(btrim(p_widget_kind)) not between 1 and 128 then
    raise exception 'invalid widget kind'
      using errcode = '23514';
  end if;

  if p_widget_push_token is null or char_length(p_widget_push_token) not between 20 and 4096 then
    raise exception 'invalid widget push token'
      using errcode = '23514';
  end if;

  if p_apns_environment is null or p_apns_environment not in ('sandbox', 'production') then
    raise exception 'unsupported APNs environment'
      using errcode = '23514';
  end if;

  token_hash = extensions.digest(p_widget_push_token, 'sha256');

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      pg_catalog.encode(token_hash, 'hex') || ':' || p_apns_environment || ':' || p_widget_kind,
      0
    )
  );

  update public.widget_push_devices
  set disabled_at = now()
  where widget_push_token_hash = token_hash
    and apns_environment = p_apns_environment
    and widget_kind = p_widget_kind
    and user_id <> current_user_id
    and disabled_at is null;

  select id
  into registered_device_id
  from public.widget_push_devices
  where user_id = current_user_id
    and widget_push_token_hash = token_hash
    and apns_environment = p_apns_environment
    and widget_kind = p_widget_kind
  order by updated_at desc, id
  limit 1
  for update;

  if registered_device_id is null then
    insert into public.widget_push_devices (
      user_id,
      widget_kind,
      widget_push_token,
      widget_push_token_hash,
      apns_environment,
      locale,
      time_zone_id,
      app_version
    )
    values (
      current_user_id,
      btrim(p_widget_kind),
      p_widget_push_token,
      token_hash,
      p_apns_environment,
      nullif(btrim(p_locale), ''),
      nullif(btrim(p_time_zone_id), ''),
      nullif(btrim(p_app_version), '')
    )
    returning id into registered_device_id;
  else
    update public.widget_push_devices
    set
      widget_push_token = p_widget_push_token,
      locale = nullif(btrim(p_locale), ''),
      time_zone_id = nullif(btrim(p_time_zone_id), ''),
      app_version = nullif(btrim(p_app_version), ''),
      last_seen_at = now(),
      disabled_at = null
    where id = registered_device_id;
  end if;

  return registered_device_id;
end;
$$;

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
security invoker
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

create table internal.widget_push_outbox (
  id uuid primary key default extensions.gen_random_uuid(),
  recipient_user_id uuid not null references auth.users (id) on delete restrict,
  target_widget_device_id uuid not null references public.widget_push_devices (id) on delete restrict,
  widget_push_token_hash bytea not null,
  apns_environment text not null,
  kind text not null default 'widget_updated',
  payload jsonb not null default '{}'::jsonb,
  dedupe_key text,
  apns_collapse_id text,
  provider_message_id text,
  attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  last_error text,
  scheduled_for timestamptz not null default now(),
  sent_at timestamptz,
  failed_at timestamptz,
  created_at timestamptz not null default now(),

  constraint widget_push_outbox_token_hash_check
    check (octet_length(widget_push_token_hash) = 32),
  constraint widget_push_outbox_apns_environment_check
    check (apns_environment in ('sandbox', 'production')),
  constraint widget_push_outbox_kind_check
    check (kind in ('widget_updated')),
  constraint widget_push_outbox_payload_check
    check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 2048),
  constraint widget_push_outbox_dedupe_key_check
    check (dedupe_key is null or char_length(btrim(dedupe_key)) between 1 and 256),
  constraint widget_push_outbox_collapse_id_check
    check (apns_collapse_id is null or char_length(btrim(apns_collapse_id)) between 1 and 64),
  constraint widget_push_outbox_attempt_count_check
    check (attempt_count >= 0)
);

create unique index widget_push_outbox_pending_dedupe_idx
on internal.widget_push_outbox (target_widget_device_id, dedupe_key)
where sent_at is null
  and failed_at is null
  and dedupe_key is not null;

create index widget_push_outbox_due_idx
on internal.widget_push_outbox (scheduled_for, id)
where sent_at is null
  and failed_at is null;

create or replace function internal.enqueue_widget_push_for_user(
  p_recipient_user_id uuid,
  p_kind text,
  p_payload jsonb default '{}'::jsonb,
  p_dedupe_key text default null,
  p_apns_collapse_id text default null,
  p_scheduled_for timestamptz default null
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_rows integer;
begin
  if p_recipient_user_id is null then
    raise exception 'widget push recipient required'
      using errcode = '23514';
  end if;

  if p_kind <> 'widget_updated' then
    raise exception 'unsupported widget push kind'
      using errcode = '23514';
  end if;

  if jsonb_typeof(coalesce(p_payload, '{}'::jsonb)) <> 'object' then
    raise exception 'widget push payload must be an object'
      using errcode = '23514';
  end if;

  insert into internal.widget_push_outbox (
    recipient_user_id,
    target_widget_device_id,
    widget_push_token_hash,
    apns_environment,
    kind,
    payload,
    dedupe_key,
    apns_collapse_id,
    scheduled_for
  )
  select
    device.user_id,
    device.id,
    device.widget_push_token_hash,
    device.apns_environment,
    p_kind,
    coalesce(p_payload, '{}'::jsonb),
    p_dedupe_key,
    p_apns_collapse_id,
    coalesce(p_scheduled_for, now())
  from public.widget_push_devices device
  where device.user_id = p_recipient_user_id
    and device.widget_kind = 'PaeoniaWidget'
    and device.disabled_at is null
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;

create or replace function internal.fail_exhausted_widget_push_claims()
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  update internal.widget_push_outbox
  set
    failed_at = now(),
    last_error = coalesce(last_error, 'attempts exhausted')
  where sent_at is null
    and failed_at is null
    and attempt_count >= 5;
end;
$$;

create or replace function internal.claim_widget_push_batch(p_limit integer default 50)
returns table (
  outbox_id uuid,
  target_widget_device_id uuid,
  widget_push_token text,
  apns_environment text,
  apns_collapse_id text,
  payload jsonb
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.fail_exhausted_widget_push_claims();

  return query
  with claimed as (
    select outbox.id, outbox.target_widget_device_id
    from internal.widget_push_outbox outbox
    join public.widget_push_devices device
      on device.id = outbox.target_widget_device_id
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= now()
      and outbox.attempt_count < 5
      and device.disabled_at is null
    order by outbox.scheduled_for, outbox.id
    for update of outbox skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  )
  update internal.widget_push_outbox outbox
  set
    attempt_count = outbox.attempt_count + 1,
    last_attempt_at = now()
  from claimed
  join public.widget_push_devices device
    on device.id = claimed.target_widget_device_id
  where outbox.id = claimed.id
  returning
    outbox.id,
    device.id,
    device.widget_push_token,
    outbox.apns_environment,
    outbox.apns_collapse_id,
    outbox.payload;
end;
$$;

create or replace function internal.mark_widget_push_result(
  p_outbox_id uuid,
  p_success boolean,
  p_provider_message_id text default null,
  p_error text default null,
  p_invalid_token boolean default false
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  update internal.widget_push_outbox
  set
    sent_at = case when p_success then now() else sent_at end,
    provider_message_id = case when p_success then p_provider_message_id else provider_message_id end,
    failed_at = case
      when p_success then failed_at
      when p_invalid_token or attempt_count >= 5 then now()
      else failed_at
    end,
    last_error = case when p_success then null else p_error end
  where id = p_outbox_id;
end;
$$;

create or replace function public.claim_widget_push_batch(p_limit integer default 50)
returns table (
  outbox_id uuid,
  target_widget_device_id uuid,
  widget_push_token text,
  apns_environment text,
  apns_collapse_id text,
  payload jsonb
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select * from internal.claim_widget_push_batch(p_limit);
$$;

create or replace function public.mark_widget_push_result(
  p_outbox_id uuid,
  p_success boolean,
  p_provider_message_id text default null,
  p_error text default null,
  p_invalid_token boolean default false
)
returns void
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.mark_widget_push_result(
    p_outbox_id,
    p_success,
    p_provider_message_id,
    p_error,
    p_invalid_token
  );
$$;

create or replace function internal.handle_widget_drawing_revision_created()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  canvas_row public.widget_canvases%rowtype;
  couple_day_id uuid;
  recipient_user_id uuid;
begin
  select *
  into canvas_row
  from public.widget_canvases
  where id = new.canvas_id;

  if not found then
    return new;
  end if;

  couple_day_id = internal.get_or_create_couple_day_at(canvas_row.couple_id, new.created_at);

  perform internal.apply_couple_activity(
    canvas_row.couple_id,
    new.author_user_id,
    couple_day_id,
    'widget_drawing_saved',
    new.created_at,
    'widget_drawing_saved:' || new.id::text,
    jsonb_build_object('canvas_id', new.canvas_id)
  );

  select member.user_id
  into recipient_user_id
  from public.couple_members member
  where member.couple_id = canvas_row.couple_id
    and member.user_id <> new.author_user_id
    and member.status = 'active'
  limit 1;

  if recipient_user_id is not null then
    -- WidgetKit push delivery must never make saving a drawing fail.
    begin
      perform internal.enqueue_widget_push_for_user(
        recipient_user_id,
        'widget_updated',
        jsonb_build_object(
          'type', 'widget_updated',
          'couple_id', canvas_row.couple_id,
          'canvas_id', new.canvas_id,
          'revision_id', new.id,
          'actor_user_id', new.author_user_id,
          'route', 'widget'
        ),
        'widgetkit:' || new.id::text,
        'widget:' || canvas_row.couple_id::text,
        null
      );
    exception when others then
      null;
    end;
  end if;

  -- Silent refresh: wakes partner's app to pull the new drawing.
  perform internal.enqueue_partner_notification(
    canvas_row.couple_id,
    new.author_user_id,
    'widget_updated',
    jsonb_build_object(
      'type', 'widget_updated',
      'couple_id', canvas_row.couple_id,
      'canvas_id', new.canvas_id,
      'revision_id', new.id,
      'actor_user_id', new.author_user_id,
      'route', 'widget'
    ),
    'widget_updated:' || new.id::text,
    'private',
    'background',
    'widget:' || canvas_row.couple_id::text,
    now()
  );

  -- Alert: lock-screen banner, gated on the partner's alert toggle.
  perform internal.enqueue_widget_update_alert(
    canvas_row.couple_id,
    new.author_user_id,
    new.canvas_id,
    new.id
  );

  return new;
end;
$$;

drop trigger if exists invoke_widget_push_drain_on_widget_push_outbox
on internal.widget_push_outbox;

create trigger invoke_widget_push_drain_on_widget_push_outbox
after insert on internal.widget_push_outbox
for each statement
execute function internal.invoke_widget_push_drain();

grant all privileges on internal.widget_push_outbox to service_role;

revoke all on function internal.register_widget_push_device(text, text, text, text, text, text) from public, anon, authenticated;
grant execute on function internal.register_widget_push_device(text, text, text, text, text, text) to service_role;

revoke all on function public.register_widget_push_device(text, text, text, text, text, text) from public, anon;
grant execute on function public.register_widget_push_device(text, text, text, text, text, text) to authenticated, service_role;

revoke all on function internal.enqueue_widget_push_for_user(uuid, text, jsonb, text, text, timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_widget_push_for_user(uuid, text, jsonb, text, text, timestamptz) to service_role;

revoke all on function internal.fail_exhausted_widget_push_claims() from public, anon, authenticated;
grant execute on function internal.fail_exhausted_widget_push_claims() to service_role;

revoke all on function internal.claim_widget_push_batch(integer) from public, anon, authenticated;
grant execute on function internal.claim_widget_push_batch(integer) to service_role;

revoke all on function internal.mark_widget_push_result(uuid, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function internal.mark_widget_push_result(uuid, boolean, text, text, boolean) to service_role;

revoke all on function public.claim_widget_push_batch(integer) from public, anon, authenticated;
grant execute on function public.claim_widget_push_batch(integer) to service_role;

revoke all on function public.mark_widget_push_result(uuid, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.mark_widget_push_result(uuid, boolean, text, text, boolean) to service_role;
