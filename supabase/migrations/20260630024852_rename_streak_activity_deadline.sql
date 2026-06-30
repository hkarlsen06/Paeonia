-- Rename the streak deadline field away from `expires_at`. The value is the next
-- couple-local deadline for qualifying activity, not the moment the streak is
-- considered broken.

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'streak_states'
      and column_name = 'expires_at'
  ) and not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'streak_states'
      and column_name = 'next_activity_deadline_at'
  ) then
    alter table public.streak_states
      rename column expires_at to next_activity_deadline_at;
  end if;
end;
$$;

comment on column public.streak_states.next_activity_deadline_at is
  'Next couple-local deadline by which qualifying activity must happen to continue the streak naturally.';

create or replace function internal.resolve_next_activity_deadline_at(
  p_couple_id uuid,
  p_observed_at timestamptz
)
returns timestamptz
language sql
security definer
set search_path = pg_catalog
as $$
  select max(
    (((p_observed_at at time zone coalesce(timezone_name.name, 'UTC'))::date + 1)::timestamp)
      at time zone coalesce(timezone_name.name, 'UTC')
  )
  from public.couple_members member
  left join public.profiles profile
    on profile.user_id = member.user_id
  left join pg_timezone_names timezone_name
    on timezone_name.name = profile.time_zone_id
  where member.couple_id = p_couple_id
    and member.status = 'active';
$$;

create or replace function internal.detect_streak_break(p_couple_id uuid)
returns void
language sql
security definer
set search_path = pg_catalog
as $$
  update public.streak_states
  set
    restorable_count = current_count,
    restorable_through_date = last_qualified_date,
    restore_deadline = next_activity_deadline_at + interval '1 day' + interval '48 hours'
  where couple_id = p_couple_id
    and current_count > 0
    and restorable_count = 0
    and next_activity_deadline_at is not null
    and now() >= next_activity_deadline_at + interval '1 day';
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
  next_current_count integer;
  next_longest_count integer;
  next_restore_available boolean;
  resolved_next_activity_deadline_at timestamptz;
  next_restorable_count integer;
  next_restorable_through_date date;
  next_restore_deadline timestamptz;
begin
  if p_activity_kind not in ('daily_challenge_completed', 'widget_drawing_saved', 'memory_created', 'memory_updated', 'thread_message_sent') then
    raise exception 'couple activity kind is not supported'
      using errcode = '23514';
  end if;

  if p_occurred_at is null then
    p_occurred_at = now();
  end if;

  if p_dedupe_key is null or char_length(btrim(p_dedupe_key)) not between 1 and 240 then
    raise exception 'couple activity dedupe key is required'
      using errcode = '23514';
  end if;

  if p_metadata is null then
    p_metadata = '{}'::jsonb;
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = p_couple_day_id;

  if not found
    or couple_day_row.couple_id <> p_couple_id then
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
    couple_id,
    user_id,
    couple_day_id,
    activity_kind,
    occurred_at,
    dedupe_key,
    metadata
  ) values (
    p_couple_id,
    p_user_id,
    p_couple_day_id,
    p_activity_kind,
    p_occurred_at,
    btrim(p_dedupe_key),
    p_metadata
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

  resolved_next_activity_deadline_at = internal.resolve_next_activity_deadline_at(p_couple_id, p_occurred_at);

  select *
  into existing_state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

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
      resolved_next_activity_deadline_at
    );
  elsif existing_state.last_qualified_date is null
    or couple_day_row.local_date > existing_state.last_qualified_date then
    if existing_state.last_qualified_date is null then
      next_current_count = 1;
      next_restore_available = false;
      next_restorable_count = existing_state.restorable_count;
      next_restorable_through_date = existing_state.restorable_through_date;
      next_restore_deadline = existing_state.restore_deadline;
    elsif couple_day_row.local_date = existing_state.last_qualified_date + 1 then
      next_current_count = existing_state.current_count + 1;
      next_restore_available = existing_state.restore_available;
      -- A consecutive day means the streak is healthy; drop any stale offer.
      next_restorable_count = 0;
      next_restorable_through_date = null;
      next_restore_deadline = null;
    else
      -- Gap > 1 day: the streak broke. Preserve the lost count and a restore
      -- window, then reset the live count to 1.
      next_current_count = 1;
      next_restore_available = true;
      next_restorable_count = greatest(existing_state.restorable_count, existing_state.current_count);
      next_restorable_through_date = coalesce(existing_state.restorable_through_date, existing_state.last_qualified_date);
      next_restore_deadline = coalesce(
        existing_state.restore_deadline,
        existing_state.next_activity_deadline_at + interval '1 day' + interval '48 hours'
      );
    end if;

    next_longest_count = greatest(existing_state.longest_count, next_current_count);

    update public.streak_states
    set
      current_count = next_current_count,
      longest_count = next_longest_count,
      last_qualified_date = couple_day_row.local_date,
      last_qualified_couple_day_id = couple_day_row.id,
      restore_available = next_restore_available,
      next_activity_deadline_at = resolved_next_activity_deadline_at,
      restorable_count = next_restorable_count,
      restorable_through_date = next_restorable_through_date,
      restore_deadline = next_restore_deadline
    where couple_id = p_couple_id;
  elsif couple_day_row.local_date = existing_state.last_qualified_date then
    update public.streak_states
    set
      last_qualified_couple_day_id = couple_day_row.id,
      next_activity_deadline_at = greatest(
        existing_state.next_activity_deadline_at,
        resolved_next_activity_deadline_at
      )
    where couple_id = p_couple_id;
  end if;

  return inserted_event_id;
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
        'couple_id', reminder_row.couple_id,
        'current_count', reminder_row.current_count,
        'last_qualified_date', reminder_row.last_qualified_date,
        'next_activity_deadline_at', reminder_row.next_activity_deadline_at,
        'route', 'streak'
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
  today_completed boolean;
  resolved_count integer;
  resolved_last_date date;
  resolved_last_couple_day_id uuid;
  resolved_next_activity_deadline_at timestamptz;
begin
  -- Replay: a finished-but-unconfirmed purchase returns the prior outcome.
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

  today_completed = exists (
    select 1
    from public.couple_activity_events
    where couple_id = p_couple_id
      and couple_day_id = today_couple_day_id
      and activity_kind = 'daily_challenge_completed'
  );

  if today_completed then
    -- The reset-to-1 came from a completion today; restore puts today on top.
    resolved_count = state.restorable_count + 1;
    resolved_last_date = today_couple_day.local_date;
    resolved_last_couple_day_id = today_couple_day_id;
  else
    -- Nothing today yet: anchor to yesterday so today's completion extends it.
    resolved_count = state.restorable_count;
    yesterday_couple_day_id = internal.get_or_create_couple_day_at(p_couple_id, now() - interval '1 day');
    resolved_last_couple_day_id = yesterday_couple_day_id;
    select local_date
    into resolved_last_date
    from public.couple_days
    where id = yesterday_couple_day_id;
  end if;

  resolved_next_activity_deadline_at = internal.resolve_next_activity_deadline_at(p_couple_id, now());

  update public.streak_states
  set
    current_count = resolved_count,
    longest_count = greatest(longest_count, resolved_count),
    last_qualified_date = resolved_last_date,
    last_qualified_couple_day_id = resolved_last_couple_day_id,
    next_activity_deadline_at = resolved_next_activity_deadline_at,
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

revoke all on function internal.resolve_next_activity_deadline_at(uuid, timestamptz) from public, anon, authenticated;
grant execute on function internal.resolve_next_activity_deadline_at(uuid, timestamptz) to service_role;

revoke all on function internal.detect_streak_break(uuid) from public, anon, authenticated;
grant execute on function internal.detect_streak_break(uuid) to service_role;

revoke all on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) from public, anon, authenticated;
grant execute on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) to service_role;

revoke all on function internal.enqueue_due_streak_reminders(timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_due_streak_reminders(timestamptz) to service_role;

revoke all on function internal.apply_streak_restore(uuid, uuid, uuid, text, text, text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function internal.apply_streak_restore(uuid, uuid, uuid, text, text, text, timestamptz, uuid) to service_role;

drop function if exists internal.resolve_streak_expires_at(uuid, timestamptz);
