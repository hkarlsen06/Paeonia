-- Capture a broken streak so it can be bought back ("streak restore").
--
-- The streak break is lazy: nothing zeroes a streak on a timer. A couple's
-- streak counts while completions land on consecutive couple-local days
-- (see internal.apply_couple_activity). When a day is skipped, the streak is
-- only actually reset to 1 by the *next* non-consecutive completion — at which
-- point the old count is discarded.
--
-- To offer a paid restore we must preserve the lost count plus a deadline.
-- There are two broken states:
--   (A) Broken, not yet reset: the grace day after `last_qualified_date` has
--       fully elapsed (now() >= expires_at + 1 day) but no later completion has
--       reset the row. `current_count` still holds the old value.
--   (B) Reset: a later completion already set current_count = 1. We capture the
--       old count *before* resetting, inside apply_couple_activity.
--
-- `expires_at` is the start of the day after `last_qualified_date` (the grace
-- day). The streak is broken once that grace day has passed, i.e.
-- now() >= expires_at + interval '1 day'. The restore offer then stays open for
-- 48 hours past the break.

alter table public.streak_states
  add column restorable_count integer not null default 0,
  add column restorable_through_date date,
  add column restore_deadline timestamptz,
  add column restored_at timestamptz,
  add column last_restore_transaction_id text;

alter table public.streak_states
  add constraint streak_states_restorable_check
  check (
    (restorable_count = 0 and restorable_through_date is null and restore_deadline is null)
    or (restorable_count > 0 and restorable_through_date is not null and restore_deadline is not null)
  );

-- Lazily stamp the restorable snapshot for case (A): the grace day has passed
-- and no later completion has reset the row yet. Idempotent — only the first
-- detection (restorable_count = 0) writes anything, and a no-op otherwise.
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
    restore_deadline = expires_at + interval '1 day' + interval '48 hours'
  where couple_id = p_couple_id
    and current_count > 0
    and restorable_count = 0
    and expires_at is not null
    and now() >= expires_at + interval '1 day';
$$;

-- A parameterized twin of internal.get_current_entitled_couple_id() that works
-- under service_role (auth.uid() is null there). Returns the user's active,
-- entitled couple, or null. Used by the streak-restore edge function.
create or replace function internal.get_entitled_couple_id_for_user(p_user_id uuid)
returns uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select couple.id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = p_user_id
    and member.status = 'active'
    and couple.status = 'active'
    and exists (
      select 1
      from public.couple_members any_member
      join internal.resolve_user_entitlement(any_member.user_id) entitlement
        on entitlement.is_entitled
      where any_member.couple_id = couple.id
        and any_member.status = 'active'
    )
  order by couple.created_at desc
  limit 1;
$$;

-- Re-create apply_couple_activity with the gap (reset) branch preserving the
-- lost count for restore, and the consecutive branch clearing any stale offer.
-- Everything else is unchanged from
-- 20260615012605_location_streaks_notifications.sql.
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
  next_expires_at timestamptz;
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

  next_expires_at = internal.resolve_streak_expires_at(p_couple_id, p_occurred_at);

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
      expires_at
    ) values (
      p_couple_id,
      1,
      1,
      couple_day_row.local_date,
      couple_day_row.id,
      false,
      next_expires_at
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
      -- Gap > 1 day: the streak broke. Preserve the lost count (and a 48h
      -- window from the break) so it can be bought back, then reset to 1.
      next_current_count = 1;
      next_restore_available = true;
      next_restorable_count = greatest(existing_state.restorable_count, existing_state.current_count);
      next_restorable_through_date = coalesce(existing_state.restorable_through_date, existing_state.last_qualified_date);
      next_restore_deadline = coalesce(
        existing_state.restore_deadline,
        existing_state.expires_at + interval '1 day' + interval '48 hours'
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
      expires_at = next_expires_at,
      restorable_count = next_restorable_count,
      restorable_through_date = next_restorable_through_date,
      restore_deadline = next_restore_deadline
    where couple_id = p_couple_id;
  elsif couple_day_row.local_date = existing_state.last_qualified_date then
    update public.streak_states
    set
      last_qualified_couple_day_id = couple_day_row.id,
      expires_at = greatest(existing_state.expires_at, next_expires_at)
    where couple_id = p_couple_id;
  end if;

  return inserted_event_id;
end;
$$;

-- Expand the read RPC: detect a lazy break first, then return the restorable
-- snapshot alongside the streak. `restore_available` is recomputed from the
-- snapshot + deadline so the app can show the "get it back" offer.
--
-- The return signature gains columns, which `create or replace` cannot do, so
-- drop the previous (4-column) versions from 20260627231420 first.
drop function if exists public.get_couple_streak();
drop function if exists internal.get_couple_streak();

create or replace function internal.get_couple_streak()
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
declare
  resolved_couple_id uuid;
begin
  resolved_couple_id = internal.get_current_entitled_couple_id();

  perform internal.detect_streak_break(resolved_couple_id);

  return query
  select
    coalesce(streak.current_count, 0),
    coalesce(streak.longest_count, 0),
    streak.last_qualified_date,
    (
      coalesce(streak.restorable_count, 0) > 0
      and streak.restore_deadline is not null
      and streak.restore_deadline > now()
    ),
    coalesce(streak.restorable_count, 0),
    streak.restore_deadline
  from (select resolved_couple_id as couple_id) resolved
  left join public.streak_states streak
    on streak.couple_id = resolved.couple_id;
end;
$$;

create or replace function public.get_couple_streak()
returns table (
  current_count integer,
  longest_count integer,
  last_qualified_date date,
  restore_available boolean,
  restorable_count integer,
  restore_deadline timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  select * from internal.get_couple_streak();
$$;

revoke all on function internal.detect_streak_break(uuid) from public, anon, authenticated;
grant execute on function internal.detect_streak_break(uuid) to service_role;

revoke all on function internal.get_entitled_couple_id_for_user(uuid) from public, anon, authenticated;
grant execute on function internal.get_entitled_couple_id_for_user(uuid) to service_role;

revoke all on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) from public, anon, authenticated;
grant execute on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) to service_role;

revoke all on function internal.get_couple_streak() from public, anon, authenticated;
grant execute on function internal.get_couple_streak() to service_role;

revoke all on function public.get_couple_streak() from public, anon;
grant execute on function public.get_couple_streak() to authenticated, service_role;
