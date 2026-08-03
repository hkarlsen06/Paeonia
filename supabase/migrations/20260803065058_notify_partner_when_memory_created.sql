-- Notify the other active partner exactly once when a memory row is first
-- created. Later title, note, date, and photo changes do not fire this insert-
-- only trigger. Copy deliberately excludes the memory's user-authored content.

alter table public.notification_preferences
  add column memories_enabled boolean not null default true;

grant select (memories_enabled), update (memories_enabled)
  on public.notification_preferences to authenticated;

alter table internal.notification_outbox
  drop constraint notification_outbox_kind_check;

alter table internal.notification_outbox
  add constraint notification_outbox_kind_check
  check (kind in (
    'streak_reminder',
    'daily_challenge_completed',
    'partner_answered',
    'widget_updated',
    'location_updated',
    'relationship_ended',
    'entitlement_changed',
    'subscription_trial_reminder',
    'memory_created'
  ));

create or replace function internal.notification_alert_title(
  p_kind text,
  p_payload jsonb,
  p_locale text
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  language_code text := internal.notification_locale_language(p_locale);
  actor_name text := coalesce(internal.notification_actor_display_name(p_payload), 'Paeonia');
begin
  return case p_kind
    when 'widget_updated' then actor_name
    when 'partner_answered' then case language_code
      when 'nb' then actor_name || ' svarte på samme spørsmål!'
      else actor_name || ' answered the same question!'
    end
    when 'daily_challenge_completed' then case language_code
      when 'nb' then actor_name || ' fullførte dagens spørsmål'
      else actor_name || ' finished today''s questions'
    end
    when 'memory_created' then case language_code
      when 'nb' then actor_name || ' la til et nytt minne'
      else actor_name || ' added a new memory'
    end
    when 'streak_reminder' then case language_code
      when 'nb' then 'Sjekk inn før tiden går ut'
      else 'Check in before time runs out'
    end
    when 'subscription_trial_reminder' then case language_code
      when 'nb' then 'Prøveperioden avsluttes snart'
      else 'Your free trial ends soon'
    end
    else 'Paeonia'
  end;
end;
$$;

create or replace function internal.notification_alert_body(
  p_kind text,
  p_payload jsonb,
  p_locale text
)
returns text
language plpgsql
stable
set search_path = pg_catalog
as $$
declare
  language_code text := internal.notification_locale_language(p_locale);
  days_left integer := greatest(
    case
      when p_payload ->> 'days_left' ~ '^[0-9]+$'
        then (p_payload ->> 'days_left')::integer
      else 2
    end,
    1
  );
begin
  return case p_kind
    when 'widget_updated' then case language_code
      when 'nb' then 'La til en ny tegning'
      else 'Added a new drawing'
    end
    when 'partner_answered' then case language_code
      when 'nb' then 'Åpne Paeonia for å se hva partneren din skrev.'
      else 'Open Paeonia to reveal what they wrote.'
    end
    when 'daily_challenge_completed' then case language_code
      when 'nb' then 'Åpne Paeonia for å svare og se hva partneren din skrev.'
      else 'Open Paeonia to answer and reveal what they wrote.'
    end
    when 'memory_created' then case language_code
      when 'nb' then 'Åpne Paeonia for å se det.'
      else 'Open Paeonia to see it.'
    end
    when 'streak_reminder' then case language_code
      when 'nb' then 'Gjør én liten ting i dag. Rekken fortsetter når dere begge har sjekket inn.'
      else 'Do one small thing today. Your streak continues once both of you have checked in.'
    end
    when 'subscription_trial_reminder' then case language_code
      when 'nb' then
        days_left::text || case when days_left = 1 then ' dag igjen. ' else ' dager igjen. ' end ||
        'Se over abonnementet ditt i App Store.'
      else
        days_left::text || case when days_left = 1 then ' day left. ' else ' days left. ' end ||
        'Review your subscription in the App Store.'
    end
    else null
  end;
end;
$$;

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

  if p_kind not in (
    'streak_reminder',
    'daily_challenge_completed',
    'partner_answered',
    'widget_updated',
    'location_updated',
    'relationship_ended',
    'entitlement_changed',
    'subscription_trial_reminder',
    'memory_created'
  ) then
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
    title,
    body,
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
    case
      when p_apns_push_type = 'alert' then
        internal.notification_alert_title(p_kind, p_payload, device.locale)
      else null
    end,
    case
      when p_apns_push_type = 'alert' then
        internal.notification_alert_body(p_kind, p_payload, device.locale)
      else null
    end,
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
        when 'widget_updated' then
          (p_apns_push_type <> 'alert' or preference.widget_updates_enabled)
        when 'location_updated' then preference.location_updates_enabled
        when 'memory_created' then preference.memories_enabled
        else true
      end
    )
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;

create or replace function internal.claim_due_notifications(p_limit integer default 100)
returns table (
  outbox_id uuid,
  recipient_user_id uuid,
  target_device_id uuid,
  push_token text,
  push_token_hash bytea,
  apns_environment text,
  kind text,
  payload_version integer,
  redaction_level text,
  payload jsonb,
  apns_push_type text,
  apns_collapse_id text,
  attempt_count integer
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_limit is null or p_limit < 1 or p_limit > 500 then
    raise exception 'notification claim limit is out of range'
      using errcode = '23514';
  end if;

  update internal.notification_outbox outbox
  set
    failed_at = now(),
    last_attempt_at = now(),
    last_error = 'notification target is no longer eligible'
  from public.user_devices device
  left join public.notification_preferences preference
    on preference.user_id = device.user_id
  where outbox.target_device_id = device.id
    and outbox.scheduled_for <= now()
    and outbox.sent_at is null
    and outbox.failed_at is null
    and (
      device.disabled_at is not null
      or not coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then preference.widget_updates_enabled
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          else true
        end,
        false
      )
    );

  return query
  with picked as (
    select outbox.id
    from internal.notification_outbox outbox
    join public.user_devices device
      on device.id = outbox.target_device_id
    left join public.notification_preferences preference
      on preference.user_id = device.user_id
    where outbox.scheduled_for <= now()
      and outbox.sent_at is null
      and outbox.failed_at is null
      and device.disabled_at is null
      and coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then preference.widget_updates_enabled
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          else true
        end,
        false
      )
    order by outbox.scheduled_for, outbox.created_at, outbox.id
    for update of outbox skip locked
    limit p_limit
  ),
  claimed as (
    update internal.notification_outbox outbox
    set
      attempt_count = outbox.attempt_count + 1,
      last_attempt_at = now(),
      last_error = null
    from picked
    where outbox.id = picked.id
    returning outbox.*
  )
  select
    claimed.id,
    claimed.recipient_user_id,
    claimed.target_device_id,
    device.push_token,
    claimed.push_token_hash,
    claimed.apns_environment,
    claimed.kind,
    claimed.payload_version,
    claimed.redaction_level,
    claimed.payload,
    claimed.apns_push_type,
    claimed.apns_collapse_id,
    claimed.attempt_count
  from claimed
  join public.user_devices device
    on device.id = claimed.target_device_id
  where device.disabled_at is null;
end;
$$;

create or replace function internal.claim_notification_batch(p_limit integer default 50)
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

  update internal.notification_outbox outbox
  set
    failed_at = now(),
    last_attempt_at = now(),
    last_error = 'notification target is no longer eligible'
  from public.user_devices device
  left join public.notification_preferences preference
    on preference.user_id = device.user_id
  where outbox.target_device_id = device.id
    and outbox.scheduled_for <= now()
    and outbox.sent_at is null
    and outbox.failed_at is null
    and (
      device.disabled_at is not null
      or not coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then
            (outbox.apns_push_type <> 'alert' or preference.widget_updates_enabled)
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          else true
        end,
        false
      )
    );

  return query
  with claimed as (
    select outbox.id, outbox.target_device_id
    from internal.notification_outbox outbox
    join public.user_devices device
      on device.id = outbox.target_device_id
    left join public.notification_preferences preference
      on preference.user_id = device.user_id
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= now()
      and outbox.attempt_count < 5
      and device.disabled_at is null
      and coalesce(
        case outbox.kind
          when 'streak_reminder' then preference.streak_reminders_enabled
          when 'daily_challenge_completed' then preference.daily_challenge_enabled
          when 'partner_answered' then preference.partner_answered_enabled
          when 'widget_updated' then
            (outbox.apns_push_type <> 'alert' or preference.widget_updates_enabled)
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          else true
        end,
        false
      )
    order by outbox.scheduled_for, outbox.created_at, outbox.id
    for update of outbox skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  )
  update internal.notification_outbox outbox
  set
    attempt_count = outbox.attempt_count + 1,
    last_attempt_at = now(),
    last_error = null,
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

create or replace function internal.enqueue_memory_created_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if new.deleted_at is not null or new.moderation_status <> 'visible' then
    return new;
  end if;

  perform internal.enqueue_partner_notification(
    new.couple_id,
    new.created_by_user_id,
    'memory_created',
    jsonb_build_object(
      'type', 'memory_created',
      'couple_id', new.couple_id::text,
      'memory_id', new.id::text,
      'actor_user_id', new.created_by_user_id::text,
      'route', 'memories',
      'deeplink', 'paeonia://memories'
    ),
    'memory_created:' || new.id::text,
    'private',
    'alert',
    'memory:' || new.id::text,
    now()
  );

  return new;
end;
$$;

drop trigger if exists enqueue_memory_created_notification on public.memories;
create trigger enqueue_memory_created_notification
after insert on public.memories
for each row
execute function internal.enqueue_memory_created_notification();

revoke all on function internal.enqueue_memory_created_notification()
  from public, anon, authenticated;
grant execute on function internal.enqueue_memory_created_notification()
  to service_role;
