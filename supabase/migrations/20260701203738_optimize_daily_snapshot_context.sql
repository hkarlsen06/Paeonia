-- Reduce CPU in the launch-time Daily Challenge snapshot by resolving the
-- authenticated couple entitlement once and passing that trusted context through
-- the private read helpers. Public RPC signatures stay unchanged.

create or replace function internal.get_current_entitled_couple_id()
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  select couple.id
  into resolved_couple_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = current_user_id
    and member.status = 'active'
    and couple.status = 'active'
    and exists (
      select 1
      from public.couple_members entitled_member
      join internal.resolve_user_entitlement(entitled_member.user_id) entitlement
        on entitlement.is_entitled
      where entitled_member.couple_id = couple.id
        and entitled_member.status = 'active'
    )
  order by couple.created_at desc
  limit 1;

  if resolved_couple_id is null then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  return resolved_couple_id;
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
  from (select p_couple_id as couple_id) resolved
  left join public.streak_states streak
    on streak.couple_id = resolved.couple_id;
end;
$$;

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

  return query
  select
    streak.current_count,
    streak.longest_count,
    streak.last_qualified_date,
    streak.restore_available,
    streak.restorable_count,
    streak.restore_deadline
  from internal.get_couple_streak_for_couple(resolved_couple_id) streak;
end;
$$;

create or replace function internal.get_today_daily_questions_for_context(
  p_current_user_id uuid,
  p_couple_id uuid
)
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  instance_status text,
  question_id uuid,
  question_version_id uuid,
  question_key text,
  prompt_en text,
  short_prompt_en text,
  prompt_nb text,
  short_prompt_nb text,
  answer_kinds text[],
  own_answer_id uuid,
  own_answered_at timestamptz,
  partner_answer_id uuid,
  partner_answered_at timestamptz,
  can_view_partner_answer boolean,
  is_current_day boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  with current_context as (
    select
      p_current_user_id as current_user_id,
      p_couple_id as couple_id
  ),
  anchor as (
    select resolved.anchor_time_zone_id as time_zone_id
    from current_context
    cross join lateral internal.resolve_couple_day_anchor(current_context.couple_id) resolved
  ),
  current_day as (
    select couple_day.id, couple_day.starts_at
    from public.couple_days couple_day
    join current_context context
      on context.couple_id = couple_day.couple_id
    where now() >= couple_day.starts_at
      and now() < couple_day.ends_at
    order by couple_day.starts_at desc
    limit 1
  ),
  selected_instances as (
    select instance.id, true as is_current_day
    from current_day
    join public.daily_question_instances instance
      on instance.couple_day_id = current_day.id
    where instance.status in ('active', 'answered')

    union

    select instance.id, false as is_current_day
    from current_context context
    cross join anchor
    join public.couple_days couple_day
      on couple_day.couple_id = context.couple_id
    join public.daily_question_instances instance
      on instance.couple_day_id = couple_day.id
    left join public.daily_question_answers viewer_answer
      on viewer_answer.instance_id = instance.id
      and viewer_answer.user_id = context.current_user_id
      and viewer_answer.deleted_at is null
      and viewer_answer.moderation_status = 'visible'
    left join public.daily_question_answers seeded_answer
      on seeded_answer.instance_id = instance.id
      and seeded_answer.user_id = instance.seeded_for_user_id
      and seeded_answer.deleted_at is null
      and seeded_answer.moderation_status = 'visible'
    left join public.daily_question_answers other_answer
      on other_answer.instance_id = instance.id
      and other_answer.user_id <> context.current_user_id
      and other_answer.deleted_at is null
      and other_answer.moderation_status = 'visible'
    where instance.status in ('active', 'answered')
      and not exists (
        select 1
        from current_day
        where current_day.id = couple_day.id
      )
      and couple_day.starts_at < coalesce((select current_day.starts_at from current_day), now())
      and (
        (
          instance.seeded_for_user_id <> context.current_user_id
          and seeded_answer.id is not null
          and viewer_answer.id is null
        )
        or (
          instance.seeded_for_user_id = context.current_user_id
          and viewer_answer.id is not null
          and other_answer.id is null
        )
        or (
          greatest(viewer_answer.created_at, other_answer.created_at) is not null
          and (greatest(viewer_answer.created_at, other_answer.created_at) at time zone anchor.time_zone_id)::date
            = (now() at time zone anchor.time_zone_id)::date
        )
      )
  )
  select
    couple_day.id,
    couple_day.couple_id,
    couple_day.local_date,
    couple_day.starts_at,
    couple_day.ends_at,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.status,
    question.id,
    version.id,
    question.key,
    en_localization.prompt,
    en_localization.short_prompt,
    nb_localization.prompt,
    nb_localization.short_prompt,
    (
      select array_agg(answer_kind.answer_kind order by answer_kind.answer_kind)
      from public.question_answer_kinds answer_kind
      where answer_kind.question_version_id = version.id
    ),
    own_answer.id,
    own_answer.created_at,
    partner_answer.id,
    partner_answer.created_at,
    partner_answer.id is not null and own_answer.id is not null,
    selected_instances.is_current_day
  from selected_instances
  join public.daily_question_instances instance
    on instance.id = selected_instances.id
  join public.couple_days couple_day
    on couple_day.id = instance.couple_day_id
  join current_context context
    on context.couple_id = couple_day.couple_id
  join public.question_versions version
    on version.id = instance.question_version_id
  join public.questions question
    on question.id = version.question_id
  join public.question_version_localizations en_localization
    on en_localization.question_version_id = version.id
    and en_localization.locale = 'en'
  join public.question_version_localizations nb_localization
    on nb_localization.question_version_id = version.id
    and nb_localization.locale = 'nb'
  left join public.daily_question_answers own_answer
    on own_answer.instance_id = instance.id
    and own_answer.user_id = context.current_user_id
    and own_answer.deleted_at is null
    and own_answer.moderation_status = 'visible'
  left join public.daily_question_answers partner_answer
    on partner_answer.instance_id = instance.id
    and partner_answer.user_id <> context.current_user_id
    and partner_answer.deleted_at is null
    and partner_answer.moderation_status = 'visible'
  where selected_instances.is_current_day = false
    or instance.seeded_for_user_id = context.current_user_id
    or partner_answer.id is not null
  order by
    selected_instances.is_current_day desc,
    couple_day.starts_at desc,
    instance.seeded_for_user_id = context.current_user_id desc,
    instance.seeded_for_user_id,
    instance.slot_number,
    instance.created_at;
$$;

create or replace function internal.get_today_daily_questions()
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  starts_at timestamptz,
  ends_at timestamptz,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  instance_status text,
  question_id uuid,
  question_version_id uuid,
  question_key text,
  prompt_en text,
  short_prompt_en text,
  prompt_nb text,
  short_prompt_nb text,
  answer_kinds text[],
  own_answer_id uuid,
  own_answered_at timestamptz,
  partner_answer_id uuid,
  partner_answered_at timestamptz,
  can_view_partner_answer boolean,
  is_current_day boolean
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
  select questions.*
  from current_context context
  cross join lateral internal.get_today_daily_questions_for_context(
    context.current_user_id,
    context.couple_id
  ) questions;
$$;

create or replace function internal.get_daily_answer_details_for_context(
  p_couple_day_ids uuid[],
  p_current_user_id uuid,
  p_couple_id uuid
)
returns table (
  couple_day_id uuid,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  answer_user_id uuid,
  answer_id uuid,
  answered_at timestamptz,
  is_own_answer boolean,
  can_view_answer boolean,
  text_body text,
  selected_user_id uuid,
  media_asset_ids uuid[]
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = p_current_user_id,
    visibility.can_view_answer,
    case
      when visibility.can_view_answer then answer_text.body
      else null
    end,
    case
      when visibility.can_view_answer then partner_choice.selected_user_id
      else null
    end,
    case
      when visibility.can_view_answer then coalesce(media.media_asset_ids, array[]::uuid[])
      else array[]::uuid[]
    end
  from public.couple_days couple_day
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.daily_question_answers answer
    on answer.instance_id = instance.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
  left join public.daily_question_answers viewer_answer
    on viewer_answer.instance_id = answer.instance_id
    and viewer_answer.user_id = p_current_user_id
    and viewer_answer.deleted_at is null
    and viewer_answer.moderation_status = 'visible'
  cross join lateral (
    select answer.user_id = p_current_user_id or viewer_answer.id is not null as can_view_answer
  ) visibility
  left join public.daily_answer_text answer_text
    on answer_text.answer_id = answer.id
  left join public.daily_answer_partner_choice partner_choice
    on partner_choice.answer_id = answer.id
  left join lateral (
    select array_agg(answer_media.media_asset_id order by answer_media.sort_order) as media_asset_ids
    from public.daily_answer_media answer_media
    join public.media_assets asset
      on asset.id = answer_media.media_asset_id
    where answer_media.answer_id = answer.id
      and asset.upload_status = 'finalized'
      and asset.storage_delete_status = 'none'
      and asset.moderation_status = 'visible'
      and asset.deleted_at is null
  ) media
    on true
  where couple_day.id = any(coalesce(p_couple_day_ids, array[]::uuid[]))
    and couple_day.couple_id = p_couple_id
  order by couple_day.starts_at desc, instance.slot_number, answer.created_at, answer.id;
$$;

create or replace function internal.get_daily_answer_details_for_couple_days(
  p_couple_day_ids uuid[]
)
returns table (
  couple_day_id uuid,
  instance_id uuid,
  seeded_for_user_id uuid,
  slot_number smallint,
  answer_user_id uuid,
  answer_id uuid,
  answered_at timestamptz,
  is_own_answer boolean,
  can_view_answer boolean,
  text_body text,
  selected_user_id uuid,
  media_asset_ids uuid[]
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
  select details.*
  from current_context context
  cross join lateral internal.get_daily_answer_details_for_context(
    p_couple_day_ids,
    context.current_user_id,
    context.couple_id
  ) details;
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
      select to_jsonb(streak_rows)
      from streak_rows
      limit 1
    ),
    now();
$$;

revoke all on function internal.get_couple_streak_for_couple(uuid) from public, anon, authenticated;
grant execute on function internal.get_couple_streak_for_couple(uuid) to service_role;

revoke all on function internal.get_today_daily_questions_for_context(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.get_today_daily_questions_for_context(uuid, uuid) to service_role;

revoke all on function internal.get_daily_answer_details_for_context(uuid[], uuid, uuid) from public, anon, authenticated;
grant execute on function internal.get_daily_answer_details_for_context(uuid[], uuid, uuid) to service_role;

revoke all on function internal.get_couple_streak() from public, anon, authenticated;
grant execute on function internal.get_couple_streak() to service_role;

revoke all on function internal.get_today_daily_questions() from public, anon, authenticated;
grant execute on function internal.get_today_daily_questions() to service_role;

revoke all on function internal.get_daily_answer_details_for_couple_days(uuid[]) from public, anon, authenticated;
grant execute on function internal.get_daily_answer_details_for_couple_days(uuid[]) to service_role;

revoke all on function internal.get_today_daily_challenge_snapshot() from public, anon, authenticated;
grant execute on function internal.get_today_daily_challenge_snapshot() to service_role;

notify pgrst, 'reload schema';
