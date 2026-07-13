-- Make the streak deadline the actual break instant. A qualifying action keeps
-- the streak alive through the couple's next complete local calendar day. The
-- deadline is the later of the two partners' relevant local midnights, using
-- their current device time zones (profile fallback). Re-resolving from the
-- immutable activity timestamp makes travel affect the live deadline without
-- rewriting history.

create or replace function internal.resolve_streak_deadline_at(
  p_couple_id uuid,
  p_observed_at timestamptz,
  p_local_days_after integer
)
returns timestamptz
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_deadline timestamptz;
begin
  if p_couple_id is null or p_observed_at is null then
    raise exception 'couple and observed timestamp are required'
      using errcode = '23514';
  end if;

  if p_local_days_after not between 1 and 2 then
    raise exception 'local deadline offset must be one or two days'
      using errcode = '23514';
  end if;

  select max(
    (
      (
        (
          p_observed_at at time zone coalesce(
            latest_device_time_zone.name,
            profile_time_zone.name,
            'UTC'
          )
        )::date
        + p_local_days_after
      )::timestamp
      at time zone coalesce(
        latest_device_time_zone.name,
        profile_time_zone.name,
        'UTC'
      )
    )
  )
  into resolved_deadline
  from public.couple_members member
  left join public.profiles profile
    on profile.user_id = member.user_id
  left join pg_timezone_names profile_time_zone
    on profile_time_zone.name = profile.time_zone_id
  left join lateral (
    select timezone_name.name
    from public.user_devices device
    join pg_timezone_names timezone_name
      on timezone_name.name = device.time_zone_id
    where device.user_id = member.user_id
      and device.disabled_at is null
    order by device.last_seen_at desc, device.updated_at desc, device.id
    limit 1
  ) latest_device_time_zone on true
  where member.couple_id = p_couple_id
    and member.status = 'active';

  if resolved_deadline is null then
    raise exception 'active couple members are required'
      using errcode = '23514';
  end if;

  return resolved_deadline;
end;
$$;

create or replace function internal.resolve_next_activity_deadline_at(
  p_couple_id uuid,
  p_observed_at timestamptz
)
returns timestamptz
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.resolve_streak_deadline_at(p_couple_id, p_observed_at, 2);
$$;

comment on column public.streak_states.next_activity_deadline_at is
  'Actual instant when the live streak breaks unless qualifying activity occurs first; recalculated from the latest activity and current partner time zones.';

create or replace function internal.refresh_streak_deadline(p_couple_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  state public.streak_states%rowtype;
  observed_at timestamptz;
  resolved_deadline timestamptz;
begin
  select *
  into state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  if not found
    or state.current_count <= 0
    or coalesce(state.restorable_count, 0) > 0 then
    return state.next_activity_deadline_at;
  end if;

  select max(event.occurred_at)
  into observed_at
  from public.couple_activity_events event
  where event.couple_id = p_couple_id
    and event.couple_day_id = state.last_qualified_couple_day_id;

  if observed_at is null then
    select couple_day.starts_at
    into observed_at
    from public.couple_days couple_day
    where couple_day.id = state.last_qualified_couple_day_id;
  end if;

  if observed_at is null then
    return state.next_activity_deadline_at;
  end if;

  resolved_deadline = internal.resolve_next_activity_deadline_at(p_couple_id, observed_at);

  update public.streak_states
  set next_activity_deadline_at = resolved_deadline
  where couple_id = p_couple_id
    and next_activity_deadline_at is distinct from resolved_deadline;

  return resolved_deadline;
end;
$$;

create or replace function internal.detect_streak_break(p_couple_id uuid)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_deadline timestamptz;
begin
  resolved_deadline = internal.refresh_streak_deadline(p_couple_id);

  update public.streak_states
  set
    restorable_count = current_count,
    restorable_through_date = last_qualified_date,
    restore_deadline = resolved_deadline + interval '24 hours',
    restore_available = resolved_deadline + interval '24 hours' > now()
  where couple_id = p_couple_id
    and current_count > 0
    and restorable_count = 0
    and resolved_deadline is not null
    and now() >= resolved_deadline;
end;
$$;

create or replace function internal.apply_couple_activity(
  p_couple_id uuid,
  p_user_id uuid,
  p_couple_day_id uuid,
  p_activity_kind text,
  p_occurred_at timestamptz,
  p_dedupe_key text,
  p_metadata jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_day_row public.couple_days%rowtype;
  inserted_event_id uuid;
  existing_state public.streak_states%rowtype;
  last_activity_at timestamptz;
  previous_deadline timestamptz;
  resolved_deadline timestamptz;
  next_current_count integer;
  next_restorable_count integer;
  next_restorable_through_date date;
  next_restore_deadline timestamptz;
begin
  if p_activity_kind not in ('daily_challenge_completed', 'widget_drawing_saved', 'memory_created', 'memory_updated', 'thread_message_sent') then
    raise exception 'couple activity kind is not supported'
      using errcode = '23514';
  end if;

  p_occurred_at = coalesce(p_occurred_at, now());

  if p_dedupe_key is null or char_length(btrim(p_dedupe_key)) not between 1 and 240 then
    raise exception 'couple activity dedupe key is required'
      using errcode = '23514';
  end if;

  p_metadata = coalesce(p_metadata, '{}'::jsonb);

  select *
  into couple_day_row
  from public.couple_days
  where id = p_couple_day_id;

  if not found or couple_day_row.couple_id <> p_couple_id then
    raise exception 'couple activity day is invalid'
      using errcode = '23514';
  end if;

  if not exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id = p_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'couple activity user must be an active couple member'
      using errcode = '23514';
  end if;

  insert into public.couple_activity_events (
    couple_id, user_id, couple_day_id, activity_kind, occurred_at, dedupe_key, metadata
  ) values (
    p_couple_id, p_user_id, p_couple_day_id, p_activity_kind, p_occurred_at,
    btrim(p_dedupe_key), p_metadata
  )
  on conflict (dedupe_key) do nothing
  returning id into inserted_event_id;

  if inserted_event_id is null then
    select event.id
    into inserted_event_id
    from public.couple_activity_events event
    where event.dedupe_key = btrim(p_dedupe_key);

    return inserted_event_id;
  end if;

  select *
  into existing_state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  resolved_deadline = internal.resolve_next_activity_deadline_at(p_couple_id, p_occurred_at);

  if not found then
    insert into public.streak_states (
      couple_id,
      current_count,
      longest_count,
      last_qualified_date,
      last_qualified_couple_day_id,
      restore_available,
      next_activity_deadline_at
    ) values (
      p_couple_id,
      1,
      1,
      couple_day_row.local_date,
      couple_day_row.id,
      false,
      resolved_deadline
    );

    return inserted_event_id;
  end if;

  select max(event.occurred_at)
  into last_activity_at
  from public.couple_activity_events event
  where event.couple_id = p_couple_id
    and event.couple_day_id = existing_state.last_qualified_couple_day_id
    and event.id <> inserted_event_id;

  if last_activity_at is not null then
    previous_deadline = internal.resolve_next_activity_deadline_at(p_couple_id, last_activity_at);
  else
    previous_deadline = existing_state.next_activity_deadline_at;
  end if;

  if couple_day_row.id = existing_state.last_qualified_couple_day_id then
    select internal.resolve_next_activity_deadline_at(p_couple_id, max(event.occurred_at))
    into resolved_deadline
    from public.couple_activity_events event
    where event.couple_id = p_couple_id
      and event.couple_day_id = couple_day_row.id;

    update public.streak_states
    set next_activity_deadline_at = resolved_deadline
    where couple_id = p_couple_id;

    return inserted_event_id;
  end if;

  -- Ignore a late-arriving activity from before the most recently qualified
  -- event. It remains in the audit trail but cannot reorder the streak ledger.
  if last_activity_at is not null and p_occurred_at <= last_activity_at then
    return inserted_event_id;
  end if;

  if previous_deadline is not null and p_occurred_at < previous_deadline then
    next_current_count = existing_state.current_count + 1;
    next_restorable_count = 0;
    next_restorable_through_date = null;
    next_restore_deadline = null;
  else
    next_current_count = 1;
    next_restorable_count = greatest(existing_state.restorable_count, existing_state.current_count);
    next_restorable_through_date = coalesce(
      existing_state.restorable_through_date,
      existing_state.last_qualified_date
    );
    next_restore_deadline = coalesce(
      existing_state.restore_deadline,
      previous_deadline + interval '24 hours'
    );
  end if;

  update public.streak_states
  set
    current_count = next_current_count,
    longest_count = greatest(longest_count, next_current_count),
    last_qualified_date = couple_day_row.local_date,
    last_qualified_couple_day_id = couple_day_row.id,
    restore_available = next_restorable_count > 0 and next_restore_deadline > now(),
    next_activity_deadline_at = resolved_deadline,
    restorable_count = next_restorable_count,
    restorable_through_date = next_restorable_through_date,
    restore_deadline = next_restore_deadline
  where couple_id = p_couple_id;

  return inserted_event_id;
end;
$$;

create or replace function internal.get_couple_streak_for_couple(p_couple_id uuid)
returns table (
  current_count integer,
  longest_count integer,
  last_qualified_date date,
  restore_available boolean,
  restorable_count integer,
  restore_deadline timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_couple_id is null then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  perform internal.detect_streak_break(p_couple_id);

  return query
  select
    case
      when streak.next_activity_deadline_at is not null
        and now() >= streak.next_activity_deadline_at
        then 0
      else coalesce(streak.current_count, 0)
    end,
    coalesce(streak.longest_count, 0),
    streak.last_qualified_date,
    (
      coalesce(streak.restorable_count, 0) > 0
      and streak.restore_deadline is not null
      and streak.restore_deadline > now()
    ),
    coalesce(streak.restorable_count, 0),
    streak.restore_deadline
  from (select p_couple_id as couple_id) resolved
  left join public.streak_states streak
    on streak.couple_id = resolved.couple_id;
end;
$$;

create or replace function internal.enqueue_due_streak_reminders(p_now timestamptz default now())
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_rows integer := 0;
  streak_row record;
  reminder_row record;
begin
  for streak_row in
    select streak.couple_id
    from public.streak_states streak
    join public.couples couple
      on couple.id = streak.couple_id
    where couple.status = 'active'
      and streak.current_count > 0
      and streak.restorable_count = 0
  loop
    perform internal.refresh_streak_deadline(streak_row.couple_id);
  end loop;

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
      and streak.restorable_count = 0
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

create or replace function internal.apply_streak_restore(
  p_couple_id uuid,
  p_purchaser_user_id uuid,
  p_product_id uuid,
  p_environment text,
  p_transaction_id text,
  p_original_transaction_id text,
  p_purchased_at timestamptz,
  p_raw_payload_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  existing_restoration internal.streak_restorations%rowtype;
  state public.streak_states%rowtype;
  today_couple_day_id uuid;
  today_couple_day public.couple_days%rowtype;
  yesterday_couple_day_id uuid;
  yesterday_couple_day public.couple_days%rowtype;
  today_activity_at timestamptz;
  resolved_count integer;
  resolved_last_date date;
  resolved_last_couple_day_id uuid;
  resolved_deadline timestamptz;
begin
  select *
  into existing_restoration
  from internal.streak_restorations
  where environment = p_environment
    and transaction_id = p_transaction_id;

  if found then
    return jsonb_build_object(
      'ok', true,
      'restoredCount', existing_restoration.restored_count,
      'replayed', true
    );
  end if;

  select *
  into state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  if not found
    or coalesce(state.restorable_count, 0) <= 0
    or state.restore_deadline is null
    or state.restore_deadline <= now() then
    return jsonb_build_object(
      'ok', false,
      'error', 'No streak is available to restore',
      'status', 409
    );
  end if;

  today_couple_day_id = internal.get_or_create_couple_day_at(p_couple_id, now());

  select *
  into today_couple_day
  from public.couple_days
  where id = today_couple_day_id;

  -- Any qualifying action can restart the streak before a restore. Previously
  -- this only recognized a completed three-question challenge, so a drawing
  -- could extend the streak but was lost when the couple restored it.
  select max(event.occurred_at)
  into today_activity_at
  from public.couple_activity_events event
  where event.couple_id = p_couple_id
    and event.couple_day_id = today_couple_day_id;

  if today_activity_at is not null then
    resolved_count = state.restorable_count + 1;
    resolved_last_date = today_couple_day.local_date;
    resolved_last_couple_day_id = today_couple_day_id;
    resolved_deadline = internal.resolve_next_activity_deadline_at(
      p_couple_id,
      today_activity_at
    );
  else
    resolved_count = state.restorable_count;
    yesterday_couple_day_id = internal.get_or_create_couple_day_at(
      p_couple_id,
      now() - interval '1 day'
    );

    select *
    into yesterday_couple_day
    from public.couple_days
    where id = yesterday_couple_day_id;

    resolved_last_date = yesterday_couple_day.local_date;
    resolved_last_couple_day_id = yesterday_couple_day_id;
    resolved_deadline = internal.resolve_next_activity_deadline_at(
      p_couple_id,
      yesterday_couple_day.starts_at
    );
  end if;

  update public.streak_states
  set
    current_count = resolved_count,
    longest_count = greatest(longest_count, resolved_count),
    last_qualified_date = resolved_last_date,
    last_qualified_couple_day_id = resolved_last_couple_day_id,
    next_activity_deadline_at = resolved_deadline,
    restore_available = false,
    restorable_count = 0,
    restorable_through_date = null,
    restore_deadline = null,
    restored_at = now(),
    last_restore_transaction_id = p_transaction_id
  where couple_id = p_couple_id;

  insert into internal.streak_restorations (
    couple_id,
    purchaser_user_id,
    product_id,
    environment,
    transaction_id,
    original_transaction_id,
    restored_count,
    restorable_through_date,
    purchased_at,
    raw_payload_id,
    status
  ) values (
    p_couple_id,
    p_purchaser_user_id,
    p_product_id,
    p_environment,
    p_transaction_id,
    p_original_transaction_id,
    resolved_count,
    state.restorable_through_date,
    p_purchased_at,
    p_raw_payload_id,
    'applied'
  );

  return jsonb_build_object(
    'ok', true,
    'restoredCount', resolved_count,
    'replayed', false
  );
end;
$$;

create or replace function internal.refresh_streak_after_profile_time_zone_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_row record;
begin
  if new.time_zone_id is not distinct from old.time_zone_id then
    return new;
  end if;

  for couple_row in
    select member.couple_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  loop
    perform internal.detect_streak_break(couple_row.couple_id);
  end loop;

  return new;
end;
$$;

create or replace function internal.refresh_streak_after_device_time_zone_change()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_row record;
begin
  if tg_op = 'UPDATE'
    and new.time_zone_id is not distinct from old.time_zone_id
    and new.last_seen_at is not distinct from old.last_seen_at
    and new.disabled_at is not distinct from old.disabled_at then
    return new;
  end if;

  for couple_row in
    select member.couple_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = new.user_id
      and member.status = 'active'
      and couple.status = 'active'
  loop
    perform internal.detect_streak_break(couple_row.couple_id);
  end loop;

  return new;
end;
$$;

drop trigger if exists refresh_streak_after_profile_time_zone_change on public.profiles;
create trigger refresh_streak_after_profile_time_zone_change
after update of time_zone_id on public.profiles
for each row
execute function internal.refresh_streak_after_profile_time_zone_change();

drop trigger if exists refresh_streak_after_device_time_zone_change on public.user_devices;
create trigger refresh_streak_after_device_time_zone_change
after insert or update of time_zone_id, last_seen_at, disabled_at on public.user_devices
for each row
execute function internal.refresh_streak_after_device_time_zone_change();

-- Convert existing rows from the legacy "start of grace day" meaning to the new
-- actual break instant. Already-broken rows have a stable break point encoded by
-- their 24-hour restore deadline. Live rows are recalculated from the latest
-- activity and current partner time zones; seeded rows without an event fall
-- back to their couple-day start instead of relying on a fixed 24-hour offset.
update public.streak_states
set next_activity_deadline_at = restore_deadline - interval '24 hours'
where current_count > 0
  and restorable_count > 0
  and next_activity_deadline_at is not null
  and restore_deadline is not null;

update public.streak_states
set restore_available = restorable_count > 0
  and restore_deadline is not null
  and restore_deadline > now();

do $$
declare
  streak_row record;
begin
  for streak_row in
    select couple_id
    from public.streak_states
    where current_count > 0
      and restorable_count = 0
  loop
    perform internal.refresh_streak_deadline(streak_row.couple_id);
  end loop;
end;
$$;

revoke all on function internal.resolve_streak_deadline_at(uuid, timestamptz, integer) from public, anon, authenticated;
grant execute on function internal.resolve_streak_deadline_at(uuid, timestamptz, integer) to service_role;

revoke all on function internal.resolve_next_activity_deadline_at(uuid, timestamptz) from public, anon, authenticated;
grant execute on function internal.resolve_next_activity_deadline_at(uuid, timestamptz) to service_role;

revoke all on function internal.refresh_streak_deadline(uuid) from public, anon, authenticated;
grant execute on function internal.refresh_streak_deadline(uuid) to service_role;

revoke all on function internal.detect_streak_break(uuid) from public, anon, authenticated;
grant execute on function internal.detect_streak_break(uuid) to service_role;

revoke all on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) from public, anon, authenticated;
grant execute on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) to service_role;

revoke all on function internal.get_couple_streak_for_couple(uuid) from public, anon, authenticated;
grant execute on function internal.get_couple_streak_for_couple(uuid) to service_role;

revoke all on function internal.enqueue_due_streak_reminders(timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_due_streak_reminders(timestamptz) to service_role;

revoke all on function internal.apply_streak_restore(uuid, uuid, uuid, text, text, text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function internal.apply_streak_restore(uuid, uuid, uuid, text, text, text, timestamptz, uuid) to service_role;

revoke all on function internal.refresh_streak_after_profile_time_zone_change() from public, anon, authenticated;
grant execute on function internal.refresh_streak_after_profile_time_zone_change() to service_role;

revoke all on function internal.refresh_streak_after_device_time_zone_change() from public, anon, authenticated;
grant execute on function internal.refresh_streak_after_device_time_zone_change() to service_role;
