-- Localized MVP notification copy and app deep-link payloads.
--
-- Alert title/body are built when rows are queued, one row per target device,
-- following Tidex's outbox pattern. The Edge Function only delivers the stored
-- copy and payload.

create or replace function internal.notification_locale_language(p_locale text)
returns text
language sql
immutable
set search_path = pg_catalog
as $$
  select case
    when split_part(lower(replace(nullif(btrim(coalesce(p_locale, '')), ''), '_', '-')), '-', 1)
      in ('no', 'nb', 'nn') then 'nb'
    else 'en'
  end;
$$;

create or replace function internal.notification_actor_display_name(p_payload jsonb)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  actor_id_text text;
  actor_id uuid;
  actor_name text;
begin
  actor_id_text = coalesce(
    nullif(btrim(coalesce(p_payload ->> 'actor_user_id', '')), ''),
    nullif(btrim(coalesce(p_payload ->> 'sender_user_id', '')), '')
  );

  if actor_id_text is null then
    return null;
  end if;

  begin
    actor_id = actor_id_text::uuid;
  exception
    when invalid_text_representation then
      return null;
  end;

  select nullif(btrim(profile.display_name), '')
  into actor_name
  from public.profiles profile
  where profile.user_id = actor_id;

  return actor_name;
end;
$$;

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
    when 'streak_reminder' then case language_code
      when 'nb' then 'Innsjekken deres utløper snart'
      else 'Your check-in expires soon'
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
    when 'streak_reminder' then case language_code
      when 'nb' then 'Svar på dagens spørsmål eller legg til en tegning for å holde den i gang.'
      else 'Answer today''s questions or add a drawing to keep it going.'
    end
    else null
  end;
end;
$$;

create or replace function internal.widget_updated_notification_body(p_locale text)
returns text
language plpgsql
stable
set search_path = pg_catalog
as $$
begin
  return internal.notification_alert_body('widget_updated', '{}'::jsonb, p_locale);
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
      when p_apns_push_type = 'alert' then internal.notification_alert_title(p_kind, p_payload, device.locale)
      else null
    end,
    case
      when p_apns_push_type = 'alert' then internal.notification_alert_body(p_kind, p_payload, device.locale)
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
        -- Silent widget refresh is required for cache freshness; only visible
        -- widget alerts respect the user-facing toggle.
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
      'couple_id', p_couple_id::text,
      'canvas_id', p_canvas_id::text,
      'revision_id', p_revision_id::text,
      'actor_user_id', p_author_user_id::text,
      'sender_user_id', p_author_user_id::text,
      'route', 'widget',
      'deeplink', 'paeonia://widget/drawing'
    ),
    'widget_updated_alert:' || p_revision_id::text || ':' || device.id::text,
    'alert',
    'widget-alert:' || p_couple_id::text,
    coalesce(author_name, 'Paeonia'),
    internal.notification_alert_body('widget_updated', '{}'::jsonb, device.locale),
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
          'route', 'widget',
          'deeplink', 'paeonia://widget/drawing'
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
      'route', 'widget',
      'deeplink', 'paeonia://widget/drawing'
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

create or replace function internal.enqueue_partner_answered_notification()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  recipient_user_id uuid;
  visible_answer_count integer;
begin
  if new.deleted_at is not null or new.moderation_status <> 'visible' then
    return new;
  end if;

  select *
  into instance_row
  from public.daily_question_instances
  where id = new.instance_id;

  if not found then
    return new;
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if not found then
    return new;
  end if;

  select count(*)
  into visible_answer_count
  from public.daily_question_answers answer
  where answer.instance_id = new.instance_id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible';

  if visible_answer_count <> 2 then
    return new;
  end if;

  select answer.user_id
  into recipient_user_id
  from public.daily_question_answers answer
  where answer.instance_id = new.instance_id
    and answer.user_id <> new.user_id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  limit 1;

  if recipient_user_id is null then
    return new;
  end if;

  perform internal.enqueue_notification_for_user(
    recipient_user_id,
    'partner_answered',
    jsonb_build_object(
      'type', 'partner_answered',
      'couple_id', couple_day_row.couple_id::text,
      'couple_day_id', instance_row.couple_day_id::text,
      'instance_id', new.instance_id::text,
      'actor_user_id', new.user_id::text,
      'route', 'daily',
      'deeplink', 'paeonia://daily/reveal?instanceId=' || new.instance_id::text || '&coupleDayId=' || instance_row.couple_day_id::text
    ),
    'partner_answered:' || new.instance_id::text || ':' || new.user_id::text || ':' || recipient_user_id::text,
    'private',
    'alert',
    'daily:' || couple_day_row.couple_id::text,
    now()
  );

  return new;
end;
$$;

drop trigger if exists enqueue_partner_answered_notification on public.daily_question_answers;
create trigger enqueue_partner_answered_notification
after insert on public.daily_question_answers
for each row
execute function internal.enqueue_partner_answered_notification();

create or replace function internal.enqueue_due_streak_reminders(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_rows integer := 0;
  reminder_row record;
begin
  for reminder_row in
    select
      streak.couple_id,
      streak.current_count,
      streak.last_qualified_date,
      streak.next_activity_deadline_at,
      member.user_id
    from public.streak_states streak
    join public.couple_members member
      on member.couple_id = streak.couple_id
    join public.couples couple
      on couple.id = streak.couple_id
    where couple.status = 'active'
      and member.status = 'active'
      and streak.next_activity_deadline_at > p_now
      and streak.next_activity_deadline_at <= p_now + interval '1 hour'
  loop
    queued_rows = queued_rows + internal.enqueue_notification_for_user(
      reminder_row.user_id,
      'streak_reminder',
      jsonb_build_object(
        'type', 'streak_reminder',
        'couple_id', reminder_row.couple_id::text,
        'current_count', reminder_row.current_count,
        'last_qualified_date', reminder_row.last_qualified_date,
        'next_activity_deadline_at', reminder_row.next_activity_deadline_at,
        'route', 'streak',
        'deeplink', 'paeonia://streak'
      ),
      'streak_reminder:' || reminder_row.couple_id::text || ':' || reminder_row.last_qualified_date::text,
      'private',
      'alert',
      'streak:' || reminder_row.couple_id::text,
      p_now
    );
  end loop;

  return queued_rows;
end;
$$;

create or replace function internal.handle_daily_challenge_completed()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_day_row public.couple_days%rowtype;
begin
  if new.completed_at is null
    or old.completed_at is not null then
    return new;
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = new.couple_day_id;

  if found then
    perform internal.apply_couple_activity(
      couple_day_row.couple_id,
      new.user_id,
      new.couple_day_id,
      'daily_challenge_completed',
      new.completed_at,
      'daily_challenge_completed:' || new.couple_day_id::text || ':' || new.user_id::text,
      jsonb_build_object('source', 'daily_challenge')
    );

    perform internal.enqueue_partner_notification(
      couple_day_row.couple_id,
      new.user_id,
      'daily_challenge_completed',
      jsonb_build_object(
        'type', 'daily_challenge_completed',
        'couple_id', couple_day_row.couple_id::text,
        'couple_day_id', new.couple_day_id::text,
        'actor_user_id', new.user_id::text,
        'route', 'daily',
        'deeplink', 'paeonia://daily/today?coupleDayId=' || new.couple_day_id::text
      ),
      'daily_challenge_completed:' || new.couple_day_id::text || ':' || new.user_id::text,
      'private',
      'alert',
      'daily:' || couple_day_row.couple_id::text,
      now()
    );

    new.partner_notified_at = coalesce(new.partner_notified_at, now());
  end if;

  return new;
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

create or replace function public.claim_notification_batch(p_limit integer default 50)
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

revoke all on function internal.notification_locale_language(text) from public, anon, authenticated;
grant execute on function internal.notification_locale_language(text) to service_role;

revoke all on function internal.notification_actor_display_name(jsonb) from public, anon, authenticated;
grant execute on function internal.notification_actor_display_name(jsonb) to service_role;

revoke all on function internal.notification_alert_title(text, jsonb, text) from public, anon, authenticated;
grant execute on function internal.notification_alert_title(text, jsonb, text) to service_role;

revoke all on function internal.notification_alert_body(text, jsonb, text) from public, anon, authenticated;
grant execute on function internal.notification_alert_body(text, jsonb, text) to service_role;

revoke all on function internal.widget_updated_notification_body(text) from public, anon, authenticated;
grant execute on function internal.widget_updated_notification_body(text) to service_role;

revoke all on function internal.enqueue_notification_for_user(uuid, text, jsonb, text, text, text, text, timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_notification_for_user(uuid, text, jsonb, text, text, text, text, timestamptz) to service_role;

revoke all on function internal.enqueue_widget_update_alert(uuid, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function internal.enqueue_widget_update_alert(uuid, uuid, uuid, uuid) to service_role;

revoke all on function internal.handle_widget_drawing_revision_created() from public, anon, authenticated;
grant execute on function internal.handle_widget_drawing_revision_created() to service_role;

revoke all on function internal.enqueue_partner_answered_notification() from public, anon, authenticated;
grant execute on function internal.enqueue_partner_answered_notification() to service_role;

revoke all on function internal.enqueue_due_streak_reminders(timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_due_streak_reminders(timestamptz) to service_role;

revoke all on function internal.handle_daily_challenge_completed() from public, anon, authenticated;
grant execute on function internal.handle_daily_challenge_completed() to service_role;

revoke all on function internal.claim_notification_batch(integer) from public, anon, authenticated;
grant execute on function internal.claim_notification_batch(integer) to service_role;

revoke all on function public.claim_notification_batch(integer) from public, anon, authenticated;
grant execute on function public.claim_notification_batch(integer) to service_role;
