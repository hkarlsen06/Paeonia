-- Place a daily question on the day of its *latest* answer, not the day its instance
-- was seeded. If a partner answered late yesterday and you reply early today, the
-- exchange belongs to today.
--
-- Two effects, both keyed on "the couple-local date of the most recent answer"
-- (couple days are midnight-aligned in the couple's anchor timezone, so
-- `(answered_at at time zone tz)::date` is exactly that couple day):
--
--  1. `get_today_daily_questions` keeps a carried-over instance visible *today* while
--     its latest answer falls on the current couple-local date. Without this, the
--     moment you answer a partner's carried question it satisfies neither carry-forward
--     branch and drops out of the Questions tab entirely — the partner's just-revealed
--     reply vanishes until you dig through history under the previous day.
--
--  2. `get_daily_questions_history` returns an `effective_local_date` = the latest
--     answer's couple-local date, so the history overview buckets the exchange under
--     the day it was actually completed.

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
  with current_context as (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
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
          -- Resolved/last answered today (couple timezone): keep the just-completed
          -- exchange in the Questions tab for the rest of the day instead of dropping
          -- it straight into history under a previous day.
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
    coalesce(internal.can_view_daily_answer(partner_answer.id), false),
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

-- History gains `effective_local_date`: the couple-local date of the latest answer.
-- Return type changes, so drop before recreating (create-or-replace can't add a
-- column to a SQL set-returning function).
drop function if exists public.get_daily_questions_history();
drop function if exists internal.get_daily_questions_history();

create or replace function internal.get_daily_questions_history()
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  effective_local_date date,
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
  can_view_partner_answer boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  with context as (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  ),
  anchor as (
    select resolved.anchor_time_zone_id as time_zone_id
    from context
    cross join lateral internal.resolve_couple_day_anchor(context.couple_id) resolved
  )
  select
    couple_day.id,
    couple_day.couple_id,
    couple_day.local_date,
    -- The latest answer's couple-local date. own_answer always exists here (inner
    -- join below); greatest() ignores a null partner answer. Aliased so ORDER BY can
    -- reference it.
    (greatest(own_answer.created_at, partner_answer.created_at) at time zone anchor.time_zone_id)::date
      as effective_local_date,
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
    coalesce(internal.can_view_daily_answer(partner_answer.id), false)
  from context
  cross join anchor
  join public.couple_days couple_day
    on couple_day.couple_id = context.couple_id
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
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
  -- Inner join: only questions the viewer has actually answered surface in history,
  -- so every row has the viewer's own answer to show.
  join public.daily_question_answers own_answer
    on own_answer.instance_id = instance.id
    and own_answer.user_id = context.current_user_id
    and own_answer.deleted_at is null
    and own_answer.moderation_status = 'visible'
  left join public.daily_question_answers partner_answer
    on partner_answer.instance_id = instance.id
    and partner_answer.user_id <> context.current_user_id
    and partner_answer.deleted_at is null
    and partner_answer.moderation_status = 'visible'
  where instance.status in ('active', 'answered')
    and internal.can_access_couple_content(couple_day.couple_id)
  order by effective_local_date desc, instance.slot_number, instance.created_at;
$$;

create or replace function public.get_daily_questions_history()
returns table (
  couple_day_id uuid,
  couple_id uuid,
  local_date date,
  effective_local_date date,
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
  can_view_partner_answer boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.get_daily_questions_history();
$$;

revoke all on function internal.get_daily_questions_history() from public, anon, authenticated;
grant execute on function internal.get_daily_questions_history() to authenticated, service_role;

revoke all on function public.get_daily_questions_history() from public, anon;
grant execute on function public.get_daily_questions_history() to authenticated, service_role;
