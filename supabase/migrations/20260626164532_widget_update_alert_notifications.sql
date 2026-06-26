-- Non-silent (alert) push when a partner updates the widget, alongside the
-- existing silent refresh.
--
-- Decisions:
-- * Silent refresh is not user-toggleable; it must always run. The background
--   widget push therefore bypasses the notification_preferences gate.
-- * The alert push has a user toggle, backed by the existing
--   notification_preferences.widget_updates_enabled (repurposed to gate only the
--   alert). Default stays true, so alerts arrive once OS permission is granted.
-- * Push copy is localized server-side (Tidex pattern), keyed on the recipient
--   device's locale, with the final title/body stored on the outbox row.
--   Title = partner's display name; body = localized "Added a new drawing".

-- 1) Outbox carries the localized alert copy ----------------------------------

alter table internal.notification_outbox
  add column if not exists title text,
  add column if not exists body text;

alter table internal.notification_outbox
  add constraint notification_outbox_title_check
    check (title is null or char_length(btrim(title)) between 1 and 200),
  add constraint notification_outbox_body_check
    check (body is null or char_length(btrim(body)) between 1 and 1000);

-- 2) Server-side localized body (en + nb) -------------------------------------
-- Mirrors Tidex's notification-body functions: normalize the locale, map
-- Norwegian variants to nb, fall back to English. Kept in SQL because the server
-- composes the push; the app's String Catalog cannot localize it.

create or replace function internal.widget_updated_notification_body(p_locale text)
returns text
language plpgsql
stable
set search_path = pg_catalog
as $$
declare
  v_normalized text := lower(replace(coalesce(p_locale, 'en'), '_', '-'));
  v_language text;
begin
  v_language := case
    when split_part(v_normalized, '-', 1) in ('no', 'nb', 'nn') then 'nb'
    else split_part(v_normalized, '-', 1)
  end;

  return case v_language
    when 'nb' then 'La til en ny tegning'
    else 'Added a new drawing'
  end;
end;
$$;

-- 3) Silent widget refresh bypasses the preference gate -----------------------
-- Recreated verbatim from 20260615012605 except the widget_updated branch: a
-- background (silent) widget push always passes; only an alert respects the
-- user's widget_updates_enabled toggle.

create or replace function internal.enqueue_notification_for_user(
  p_recipient_user_id uuid,
  p_kind text,
  p_payload jsonb,
  p_dedupe_key text default null,
  p_redaction_level text default 'private',
  p_apns_push_type text default 'alert',
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
    raise exception 'notification recipient is required'
      using errcode = '23514';
  end if;

  if p_kind not in ('streak_reminder', 'daily_challenge_completed', 'partner_answered', 'widget_updated', 'location_updated', 'relationship_ended', 'entitlement_changed') then
    raise exception 'notification kind is not supported'
      using errcode = '23514';
  end if;

  if p_redaction_level <> 'private' then
    raise exception 'only private notification payloads are supported for MVP'
      using errcode = '23514';
  end if;

  if not internal.notification_payload_is_safe(p_payload) then
    raise exception 'notification payload contains sensitive or unsupported fields'
      using errcode = '23514';
  end if;

  insert into internal.notification_outbox (
    recipient_user_id,
    target_device_id,
    push_token_hash,
    apns_environment,
    kind,
    redaction_level,
    payload,
    dedupe_key,
    apns_push_type,
    apns_collapse_id,
    scheduled_for
  )
  select
    device.user_id,
    device.id,
    device.push_token_hash,
    device.apns_environment,
    p_kind,
    p_redaction_level,
    p_payload,
    case
      when nullif(btrim(coalesce(p_dedupe_key, '')), '') is null then null
      else btrim(p_dedupe_key) || ':' || device.id::text
    end,
    p_apns_push_type,
    nullif(btrim(coalesce(p_apns_collapse_id, '')), ''),
    coalesce(p_scheduled_for, now())
  from public.user_devices device
  join public.notification_preferences preference
    on preference.user_id = device.user_id
  where device.user_id = p_recipient_user_id
    and device.disabled_at is null
    and (
      case p_kind
        when 'streak_reminder' then preference.streak_reminders_enabled
        when 'daily_challenge_completed' then preference.daily_challenge_enabled
        when 'partner_answered' then preference.partner_answered_enabled
        -- Silent refresh is always allowed; only the alert respects the toggle.
        when 'widget_updated' then (p_apns_push_type <> 'alert' or preference.widget_updates_enabled)
        when 'location_updated' then preference.location_updates_enabled
        else true
      end
    )
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;

-- 4) Enqueue the localized alert per recipient device -------------------------
-- One alert row per recipient device, body localized to that device's locale.
-- Distinct dedupe-key prefix and collapse id from the silent row so the two
-- coexist. Gated on widget_updates_enabled (the alert toggle).

create or replace function internal.enqueue_widget_update_alert(
  p_couple_id uuid,
  p_author_user_id uuid,
  p_canvas_id uuid,
  p_revision_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  recipient_user_id uuid;
  author_name text;
  queued_rows integer;
begin
  select member.user_id
  into recipient_user_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.couple_id = p_couple_id
    and member.user_id <> p_author_user_id
    and member.status = 'active'
    and couple.status = 'active'
  limit 1;

  if recipient_user_id is null then
    return 0;
  end if;

  select nullif(btrim(profile.display_name), '')
  into author_name
  from public.profiles profile
  where profile.user_id = p_author_user_id;

  insert into internal.notification_outbox (
    recipient_user_id,
    target_device_id,
    push_token_hash,
    apns_environment,
    kind,
    redaction_level,
    payload,
    dedupe_key,
    apns_push_type,
    apns_collapse_id,
    title,
    body,
    scheduled_for
  )
  select
    device.user_id,
    device.id,
    device.push_token_hash,
    device.apns_environment,
    'widget_updated',
    'private',
    jsonb_build_object(
      'type', 'widget_updated',
      'canvas_id', p_canvas_id::text,
      'route', 'widget'
    ),
    'widget_updated_alert:' || p_revision_id::text || ':' || device.id::text,
    'alert',
    'widget-alert:' || p_couple_id::text,
    coalesce(author_name, 'Paeonia'),
    internal.widget_updated_notification_body(device.locale),
    now()
  from public.user_devices device
  join public.notification_preferences preference
    on preference.user_id = device.user_id
  where device.user_id = recipient_user_id
    and device.disabled_at is null
    and preference.widget_updates_enabled
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;

-- 5) Fire both silent + alert on save -----------------------------------------
-- Recreated from 20260615012605 with the alert enqueue appended. The silent
-- enqueue is unchanged (now ungated by the gate change above).

create or replace function internal.handle_widget_drawing_revision_created()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  canvas_row public.widget_canvases%rowtype;
  couple_day_id uuid;
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

  -- Silent refresh: wakes the partner's app to pull the new drawing.
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

-- 6) Drain claims widget alert + silent rows, returns the alert copy ----------
-- The drainer is widget-scoped (kind = 'widget_updated'); other kinds get their
-- own path. On claim it leases the row forward 30s so an overlapping drain
-- cannot re-claim and double-send it before the result is recorded.

drop function if exists public.claim_notification_batch(integer);
drop function if exists internal.claim_notification_batch(integer);

create function internal.claim_notification_batch(p_limit integer default 50)
returns table (
  outbox_id uuid,
  target_device_id uuid,
  push_token text,
  apns_environment text,
  apns_push_type text,
  apns_collapse_id text,
  title text,
  body text,
  payload jsonb
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.fail_exhausted_notification_claims();

  return query
  with claimed as (
    select outbox.id, outbox.target_device_id
    from internal.notification_outbox outbox
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= now()
      and outbox.attempt_count < 5
      and outbox.kind = 'widget_updated'
    order by outbox.scheduled_for
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  )
  update internal.notification_outbox outbox
  set attempt_count = outbox.attempt_count + 1,
      last_attempt_at = now(),
      -- Lease: a concurrent drain skips this row until the lease elapses, so a
      -- failed send still retries after 30s but cannot be double-sent meanwhile.
      scheduled_for = now() + interval '30 seconds'
  from claimed
  join public.user_devices device
    on device.id = claimed.target_device_id
  where outbox.id = claimed.id
  returning
    outbox.id,
    outbox.target_device_id,
    device.push_token,
    outbox.apns_environment,
    outbox.apns_push_type,
    outbox.apns_collapse_id,
    outbox.title,
    outbox.body,
    outbox.payload;
end;
$$;

create function public.claim_notification_batch(p_limit integer default 50)
returns table (
  outbox_id uuid,
  target_device_id uuid,
  push_token text,
  apns_environment text,
  apns_push_type text,
  apns_collapse_id text,
  title text,
  body text,
  payload jsonb
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.claim_notification_batch(p_limit);
$$;

-- 6b) Terminal failure for dead tokens ---------------------------------------
-- A 410 Unregistered or a BadDeviceToken on every environment means the token
-- is dead; retrying wastes attempts. `p_invalid_token` fails the row now instead
-- of waiting for the attempt budget. Recreated (not replaced) because the
-- signature gains a parameter.

drop function if exists public.mark_notification_result(uuid, boolean, text, text);
drop function if exists internal.mark_notification_result(uuid, boolean, text, text);

create function internal.mark_notification_result(
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
  if p_success then
    update internal.notification_outbox
    set sent_at = now(),
        provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
        last_error = null
    where id = p_outbox_id
      and sent_at is null
      and failed_at is null;
  else
    update internal.notification_outbox
    set last_error = left(coalesce(nullif(btrim(p_error), ''), 'delivery failed'), 2000),
        failed_at = case when p_invalid_token or attempt_count >= 5 then now() else null end
    where id = p_outbox_id
      and sent_at is null
      and failed_at is null;
  end if;
end;
$$;

create function public.mark_notification_result(
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
  select internal.mark_notification_result(
    p_outbox_id,
    p_success,
    p_provider_message_id,
    p_error,
    p_invalid_token
  );
$$;

-- 7) One drain per transaction ------------------------------------------------
-- Silent + alert are two inserts in one save transaction. A per-statement
-- trigger would post twice and the two drains would race. A transaction-local
-- flag collapses them to a single drain; pg_net still sends after commit, and
-- the single claim batch picks up every pending widget row.

create or replace function internal.invoke_widget_push_drain()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  drain_secret text;
begin
  if current_setting('paeonia.widget_drain_queued', true) = '1' then
    return null;
  end if;
  perform set_config('paeonia.widget_drain_queued', '1', true);

  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name = 'widget_drain_secret'
  limit 1;

  if coalesce(drain_secret, '') <> '' then
    perform net.http_post(
      url := 'https://api.paeonia.no/functions/v1/send-widget-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-drain-secret', drain_secret
      ),
      body := '{}'::jsonb
    );
  end if;
  return null;
end;
$$;

-- 8) Grants -------------------------------------------------------------------

revoke all on function internal.widget_updated_notification_body(text) from public, anon, authenticated;
grant execute on function internal.widget_updated_notification_body(text) to service_role;

revoke all on function internal.enqueue_widget_update_alert(uuid, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function internal.enqueue_widget_update_alert(uuid, uuid, uuid, uuid) to service_role;

revoke all on function internal.claim_notification_batch(integer) from public, anon, authenticated;
grant execute on function internal.claim_notification_batch(integer) to service_role;

revoke all on function public.claim_notification_batch(integer) from public, anon, authenticated;
grant execute on function public.claim_notification_batch(integer) to service_role;

revoke all on function internal.mark_notification_result(uuid, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function internal.mark_notification_result(uuid, boolean, text, text, boolean) to service_role;

revoke all on function public.mark_notification_result(uuid, boolean, text, text, boolean) from public, anon, authenticated;
grant execute on function public.mark_notification_result(uuid, boolean, text, text, boolean) to service_role;
