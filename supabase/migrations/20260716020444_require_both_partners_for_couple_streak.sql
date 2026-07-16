-- A couple streak represents both people showing up. An activity event remains
-- individually attributed for audit and notification targeting, but a couple
-- day qualifies only after every active member has contributed at least once.

create or replace function internal.get_couple_day_streak_qualified_at(
  p_couple_id uuid,
  p_couple_day_id uuid
)
returns timestamptz
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with active_members as materialized (
    select member.user_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.status = 'active'
      and couple.status = 'active'
  ),
  first_contributions as materialized (
    select
      member.user_id,
      min(event.occurred_at) as first_occurred_at
    from active_members member
    left join public.couple_activity_events event
      on event.couple_id = p_couple_id
      and event.couple_day_id = p_couple_day_id
      and event.user_id = member.user_id
    group by member.user_id
  )
  select case
    when count(*) >= 2
      and count(first_contributions.first_occurred_at) = count(*)
      then max(first_contributions.first_occurred_at)
    else null
  end
  from first_contributions;
$$;

create or replace function internal.get_couple_streak_participation_for_user(
  p_couple_id uuid,
  p_current_user_id uuid,
  p_observed_at timestamptz default now()
)
returns table (
  current_user_contributed_today boolean,
  partner_contributed_today boolean
)
language sql
stable
security definer
set search_path = pg_catalog
as $$
  with current_day as materialized (
    select couple_day.id
    from public.couple_days couple_day
    where couple_day.couple_id = p_couple_id
      and p_observed_at >= couple_day.starts_at
      and p_observed_at < couple_day.ends_at
    order by couple_day.starts_at desc
    limit 1
  )
  select
    exists (
      select 1
      from current_day
      join public.couple_activity_events event
        on event.couple_day_id = current_day.id
      where event.couple_id = p_couple_id
        and event.user_id = p_current_user_id
    ),
    exists (
      select 1
      from current_day
      join public.couple_activity_events event
        on event.couple_day_id = current_day.id
      join public.couple_members member
        on member.couple_id = event.couple_id
        and member.user_id = event.user_id
      where event.couple_id = p_couple_id
        and event.user_id <> p_current_user_id
        and member.status = 'active'
    );
$$;

create or replace function internal.refresh_streak_deadline(p_couple_id uuid)
returns timestamptz
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  state public.streak_states%rowtype;
  qualified_at timestamptz;
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

  qualified_at = internal.get_couple_day_streak_qualified_at(
    p_couple_id,
    state.last_qualified_couple_day_id
  );

  -- Rows created before this migration may have counted a one-person day. Use
  -- the same latest-event anchor those rows used before this migration, rather
  -- than shortening their shipped deadline to the couple-day start.
  if qualified_at is null then
    select max(event.occurred_at)
    into qualified_at
    from public.couple_activity_events event
    where event.couple_id = p_couple_id
      and event.couple_day_id = state.last_qualified_couple_day_id;
  end if;

  if qualified_at is null then
    return state.next_activity_deadline_at;
  end if;

  resolved_deadline = internal.resolve_next_activity_deadline_at(
    p_couple_id,
    qualified_at
  );

  update public.streak_states
  set next_activity_deadline_at = resolved_deadline
  where couple_id = p_couple_id
    and next_activity_deadline_at is distinct from resolved_deadline;

  return resolved_deadline;
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
  qualified_at timestamptz;
  previous_qualified_at timestamptz;
  previous_observed_at timestamptz;
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

  -- Serialize both partners' events on the couple row. Without this lock, two
  -- simultaneous first contributions could each miss the other's uncommitted
  -- event and leave an otherwise-qualified day uncounted.
  perform 1
  from public.couples couple
  where couple.id = p_couple_id
  for update;

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

  qualified_at = internal.get_couple_day_streak_qualified_at(
    p_couple_id,
    p_couple_day_id
  );

  -- One person can contribute more than once, but no streak state changes until
  -- the other active member has also shown up during this couple day.
  if qualified_at is null then
    return inserted_event_id;
  end if;

  select *
  into existing_state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  resolved_deadline = internal.resolve_next_activity_deadline_at(
    p_couple_id,
    qualified_at
  );

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

  previous_qualified_at = internal.get_couple_day_streak_qualified_at(
    p_couple_id,
    existing_state.last_qualified_couple_day_id
  );

  previous_observed_at = previous_qualified_at;
  if previous_observed_at is null then
    -- A legacy streak may point at a day that only one partner completed. Its
    -- latest event still provides a stable ordering/deadline anchor so a late
    -- older two-person day cannot move the ledger backwards.
    select max(event.occurred_at)
    into previous_observed_at
    from public.couple_activity_events event
    where event.couple_id = p_couple_id
      and event.couple_day_id = existing_state.last_qualified_couple_day_id;
  end if;

  if previous_observed_at is not null then
    previous_deadline = internal.resolve_next_activity_deadline_at(
      p_couple_id,
      previous_observed_at
    );
  else
    previous_deadline = existing_state.next_activity_deadline_at;
  end if;

  if couple_day_row.id = existing_state.last_qualified_couple_day_id then
    update public.streak_states
    set next_activity_deadline_at = resolved_deadline
    where couple_id = p_couple_id;

    return inserted_event_id;
  end if;

  -- Keep a late-arriving historical day in the audit trail without allowing it
  -- to reorder the current streak ledger.
  if previous_observed_at is not null and qualified_at <= previous_observed_at then
    return inserted_event_id;
  end if;

  if previous_deadline is not null and qualified_at < previous_deadline then
    next_current_count = existing_state.current_count + 1;
    next_restorable_count = 0;
    next_restorable_through_date = null;
    next_restore_deadline = null;
  else
    next_current_count = 1;
    next_restorable_count = greatest(
      existing_state.restorable_count,
      existing_state.current_count
    );
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

create or replace function internal.enqueue_due_streak_reminders(
  p_now timestamptz default now()
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_rows integer := 0;
  streak_row record;
  missing_member record;
  current_couple_day_id uuid;
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

  for streak_row in
    select
      streak.couple_id,
      streak.current_count,
      streak.last_qualified_date,
      streak.next_activity_deadline_at
    from public.streak_states streak
    join public.couples couple
      on couple.id = streak.couple_id
    where couple.status = 'active'
      and streak.restorable_count = 0
      and streak.next_activity_deadline_at > p_now
      and streak.next_activity_deadline_at <= p_now + interval '1 hour'
  loop
    current_couple_day_id = internal.get_or_create_couple_day_at(
      streak_row.couple_id,
      p_now
    );

    for missing_member in
      select member.user_id
      from public.couple_members member
      where member.couple_id = streak_row.couple_id
        and member.status = 'active'
        and not exists (
          select 1
          from public.couple_activity_events event
          where event.couple_id = streak_row.couple_id
            and event.couple_day_id = current_couple_day_id
            and event.user_id = member.user_id
        )
    loop
      queued_rows = queued_rows + internal.enqueue_notification_for_user(
        missing_member.user_id,
        'streak_reminder',
        jsonb_build_object(
          'type', 'streak_reminder',
          'couple_id', streak_row.couple_id::text,
          'current_count', streak_row.current_count,
          'last_qualified_date', streak_row.last_qualified_date,
          'next_activity_deadline_at', streak_row.next_activity_deadline_at,
          'contribution_needed', true,
          'route', 'streak',
          'deeplink', 'paeonia://streak'
        ),
        'streak_reminder:' || streak_row.couple_id::text || ':'
          || streak_row.last_qualified_date::text || ':'
          || missing_member.user_id::text,
        'private',
        'alert',
        'streak:' || streak_row.couple_id::text,
        p_now
      );
    end loop;
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
  today_qualified_at timestamptz;
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

  today_qualified_at = internal.get_couple_day_streak_qualified_at(
    p_couple_id,
    today_couple_day_id
  );

  -- A restore adds today only when both partners have contributed. One person's
  -- pending contribution stays in the audit trail and can qualify the day when
  -- the other partner later joins them.
  if today_qualified_at is not null then
    resolved_count = state.restorable_count + 1;
    resolved_last_date = today_couple_day.local_date;
    resolved_last_couple_day_id = today_couple_day_id;
    resolved_deadline = internal.resolve_next_activity_deadline_at(
      p_couple_id,
      today_qualified_at
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

-- Expose per-person participation in the existing streak JSON/read RPC so the
-- local-first completion screen never claims one person's contribution advanced
-- a shared streak. Older cached app snapshots safely default these fields false.
drop function if exists public.get_couple_streak();

create function public.get_couple_streak()
returns table (
  current_count integer,
  longest_count integer,
  last_qualified_date date,
  restore_available boolean,
  restorable_count integer,
  restore_deadline timestamptz,
  current_user_contributed_today boolean,
  partner_contributed_today boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  with current_context as materialized (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  )
  select
    streak.current_count,
    streak.longest_count,
    streak.last_qualified_date,
    streak.restore_available,
    streak.restorable_count,
    streak.restore_deadline,
    participation.current_user_contributed_today,
    participation.partner_contributed_today
  from current_context context
  cross join lateral internal.get_couple_streak_for_couple(context.couple_id) streak
  cross join lateral internal.get_couple_streak_participation_for_user(
    context.couple_id,
    context.current_user_id,
    now()
  ) participation;
$$;

create or replace function internal.get_today_daily_challenge_snapshot()
returns table (
  questions jsonb,
  answer_details jsonb,
  streak jsonb,
  generated_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  with current_context as materialized (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  ),
  question_rows as materialized (
    select questions.*
    from current_context context
    cross join lateral internal.get_today_daily_questions_for_context(
      context.current_user_id,
      context.couple_id
    ) questions
  ),
  answer_detail_rows as materialized (
    select details.*
    from current_context context
    cross join lateral internal.get_daily_answer_details_for_context(
      coalesce(
        (select array_agg(distinct question_rows.couple_day_id) from question_rows),
        array[]::uuid[]
      ),
      context.current_user_id,
      context.couple_id
    ) details
  ),
  streak_rows as materialized (
    select streak.*
    from current_context context
    cross join lateral internal.get_couple_streak_for_couple(context.couple_id) streak
  ),
  participation_rows as materialized (
    select participation.*
    from current_context context
    cross join lateral internal.get_couple_streak_participation_for_user(
      context.couple_id,
      context.current_user_id,
      now()
    ) participation
  )
  select
    coalesce(
      (
        select jsonb_agg(to_jsonb(question_rows) order by
          question_rows.is_current_day desc nulls last,
          question_rows.starts_at desc,
          question_rows.seeded_for_user_id,
          question_rows.slot_number,
          question_rows.instance_id
        )
        from question_rows
      ),
      '[]'::jsonb
    ),
    coalesce(
      (
        select jsonb_agg(to_jsonb(answer_detail_rows) order by
          answer_detail_rows.couple_day_id,
          answer_detail_rows.slot_number,
          answer_detail_rows.answered_at,
          answer_detail_rows.answer_id
        )
        from answer_detail_rows
      ),
      '[]'::jsonb
    ),
    (
      select to_jsonb(streak_rows) || to_jsonb(participation_rows)
      from streak_rows
      cross join participation_rows
      limit 1
    ),
    now();
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

comment on function internal.get_couple_day_streak_qualified_at(uuid, uuid) is
  'Returns when every active partner first had a qualifying event in the couple day; null until both contribute.';

revoke all on function internal.get_couple_day_streak_qualified_at(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.get_couple_day_streak_qualified_at(uuid, uuid) to service_role;

revoke all on function internal.get_couple_streak_participation_for_user(uuid, uuid, timestamptz) from public, anon, authenticated;
grant execute on function internal.get_couple_streak_participation_for_user(uuid, uuid, timestamptz) to service_role;

revoke all on function internal.refresh_streak_deadline(uuid) from public, anon, authenticated;
grant execute on function internal.refresh_streak_deadline(uuid) to service_role;

revoke all on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) from public, anon, authenticated;
grant execute on function internal.apply_couple_activity(uuid, uuid, uuid, text, timestamptz, text, jsonb) to service_role;

revoke all on function internal.enqueue_due_streak_reminders(timestamptz) from public, anon, authenticated;
grant execute on function internal.enqueue_due_streak_reminders(timestamptz) to service_role;

revoke all on function internal.apply_streak_restore(uuid, uuid, uuid, text, text, text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function internal.apply_streak_restore(uuid, uuid, uuid, text, text, text, timestamptz, uuid) to service_role;

revoke all on function internal.get_today_daily_challenge_snapshot() from public, anon, authenticated;
grant execute on function internal.get_today_daily_challenge_snapshot() to service_role;

revoke all on function internal.notification_alert_title(text, jsonb, text) from public, anon, authenticated;
grant execute on function internal.notification_alert_title(text, jsonb, text) to service_role;

revoke all on function internal.notification_alert_body(text, jsonb, text) from public, anon, authenticated;
grant execute on function internal.notification_alert_body(text, jsonb, text) to service_role;

revoke all on function public.get_couple_streak() from public, anon;
grant execute on function public.get_couple_streak() to authenticated, service_role;

notify pgrst, 'reload schema';
