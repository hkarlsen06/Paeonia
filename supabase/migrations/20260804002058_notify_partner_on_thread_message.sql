-- A thread message counts as shared streak activity and notifies the other
-- active partner without exposing the message text on the lock screen.

alter table public.notification_preferences
  add column if not exists messages_enabled boolean not null default true;

grant select (messages_enabled), update (messages_enabled)
  on public.notification_preferences to authenticated;

alter table internal.notification_outbox
  drop constraint if exists notification_outbox_kind_check;

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
    'memory_created',
    'thread_message_sent'
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
    when 'thread_message_sent' then case
      when p_payload ->> 'lock_screen_detail_level' = 'descriptive' then
        case language_code
          when 'nb' then
            coalesce(internal.notification_actor_display_name(p_payload), 'Partneren din') ||
            ' sendte deg en melding'
          else
            coalesce(internal.notification_actor_display_name(p_payload), 'Your partner') ||
            ' sent you a message'
        end
      else 'Paeonia'
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
    when 'thread_message_sent' then case
      when p_payload ->> 'lock_screen_detail_level' = 'descriptive' then
        case language_code
          when 'nb' then 'Åpne Paeonia for å svare.'
          else 'Open Paeonia to reply.'
        end
      else case language_code
        when 'nb' then 'Åpne Paeonia for å se hva som er nytt.'
        else 'Open Paeonia to see what''s new.'
      end
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
    'memory_created',
    'thread_message_sent'
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
        internal.notification_alert_title(
          p_kind,
          p_payload || jsonb_build_object(
            'lock_screen_detail_level',
            preference.lock_screen_detail_level
          ),
          device.locale
        )
      else null
    end,
    case
      when p_apns_push_type = 'alert' then
        internal.notification_alert_body(
          p_kind,
          p_payload || jsonb_build_object(
            'lock_screen_detail_level',
            preference.lock_screen_detail_level
          ),
          device.locale
        )
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
        when 'thread_message_sent' then preference.messages_enabled
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
          when 'thread_message_sent' then preference.messages_enabled
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
          when 'thread_message_sent' then preference.messages_enabled
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
          when 'widget_updated' then (outbox.apns_push_type <> 'alert' or preference.widget_updates_enabled)
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          when 'thread_message_sent' then preference.messages_enabled
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
          when 'widget_updated' then (outbox.apns_push_type <> 'alert' or preference.widget_updates_enabled)
          when 'location_updated' then preference.location_updates_enabled
          when 'memory_created' then preference.memories_enabled
          when 'thread_message_sent' then preference.messages_enabled
          else true
        end,
        false
      )
    order by outbox.scheduled_for, outbox.created_at, outbox.id
    for update of outbox skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  )
  update internal.notification_outbox outbox
  set attempt_count = outbox.attempt_count + 1,
      last_attempt_at = now(),
      last_error = null,
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

create or replace function internal.handle_thread_message_created()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_id uuid;
  resolved_instance_id uuid;
  resolved_memory_id uuid;
  notification_payload jsonb;
begin
  if new.deleted_at is not null or new.moderation_status <> 'visible' then
    return new;
  end if;

  select
    thread.couple_id,
    daily_thread.instance_id,
    memory_thread.memory_id
  into
    resolved_couple_id,
    resolved_instance_id,
    resolved_memory_id
  from public.conversation_threads thread
  left join public.daily_question_threads daily_thread
    on daily_thread.thread_id = thread.id
  left join public.memory_threads memory_thread
    on memory_thread.thread_id = thread.id
  where thread.id = new.thread_id
    and thread.deleted_at is null
    and thread.moderation_status = 'visible';

  if resolved_couple_id is null
    or (resolved_instance_id is null and resolved_memory_id is null) then
    return new;
  end if;

  perform internal.apply_couple_activity(
    resolved_couple_id,
    new.sender_user_id,
    internal.get_or_create_couple_day_at(resolved_couple_id, new.created_at),
    'thread_message_sent',
    new.created_at,
    'thread_message_sent:' || new.id::text,
    jsonb_build_object('thread_id', new.thread_id)
  );

  notification_payload = jsonb_build_object(
    'type', 'thread_message_sent',
    'couple_id', resolved_couple_id::text,
    'thread_id', new.thread_id::text,
    'message_id', new.id::text,
    'actor_user_id', new.sender_user_id::text
  );

  if resolved_instance_id is not null then
    notification_payload = notification_payload || jsonb_build_object(
      'route', 'daily',
      'deeplink', 'paeonia://daily/chat?instanceId=' || resolved_instance_id::text,
      'instance_id', resolved_instance_id::text
    );
  else
    notification_payload = notification_payload || jsonb_build_object(
      'route', 'memories',
      'deeplink', 'paeonia://memories',
      'memory_id', resolved_memory_id::text
    );
  end if;

  -- Push delivery must never make sending a message fail.
  begin
    perform internal.enqueue_partner_notification(
      resolved_couple_id,
      new.sender_user_id,
      'thread_message_sent',
      notification_payload,
      'thread_message_sent:' || new.id::text,
      'private',
      'alert',
      'thread:' || new.thread_id::text,
      now()
    );
  exception when others then
    null;
  end;

  return new;
end;
$$;

drop trigger if exists handle_thread_message_created on public.thread_messages;
create trigger handle_thread_message_created
after insert on public.thread_messages
for each row
execute function internal.handle_thread_message_created();

revoke all on function internal.handle_thread_message_created()
  from public, anon, authenticated;
grant execute on function internal.handle_thread_message_created()
  to service_role;
