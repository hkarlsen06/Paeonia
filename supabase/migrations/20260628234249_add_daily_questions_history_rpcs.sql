-- Couple question history: a chronological read model of every daily question the
-- current user has answered, across all days, plus the visible answer details for
-- those exchanges. Both RPCs are thin public wrappers around security-definer
-- internal implementations that resolve the entitled couple and enforce the same
-- per-answer reveal rules the rest of the daily challenge uses. They are scoped to
-- instances the viewer has answered, so a row always has something to show and a
-- partner answer is only revealed once both have answered.

create or replace function internal.get_daily_questions_history()
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
    coalesce(internal.can_view_daily_answer(partner_answer.id), false)
  from context
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
  order by couple_day.starts_at desc, instance.slot_number, instance.created_at;
$$;

create or replace function internal.get_daily_answer_history_details()
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
  with context as (
    select
      auth.uid() as current_user_id,
      internal.get_current_entitled_couple_id() as couple_id
  )
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = context.current_user_id,
    internal.can_view_daily_answer(answer.id),
    case
      when internal.can_view_daily_answer(answer.id) then answer_text.body
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then partner_choice.selected_user_id
      else null
    end,
    case
      when internal.can_view_daily_answer(answer.id) then coalesce(media.media_asset_ids, array[]::uuid[])
      else array[]::uuid[]
    end
  from context
  join public.couple_days couple_day
    on couple_day.couple_id = context.couple_id
  join public.daily_question_instances instance
    on instance.couple_day_id = couple_day.id
  join public.daily_question_answers answer
    on answer.instance_id = instance.id
    and answer.deleted_at is null
    and answer.moderation_status = 'visible'
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
  where internal.can_access_couple_content(couple_day.couple_id)
    -- Only return details for exchanges the viewer engaged with — both their own
    -- answer and the partner's revealed reply for instances they answered.
    and exists (
      select 1
      from public.daily_question_answers viewer_answer
      where viewer_answer.instance_id = instance.id
        and viewer_answer.user_id = context.current_user_id
        and viewer_answer.deleted_at is null
        and viewer_answer.moderation_status = 'visible'
    )
  order by couple_day.starts_at desc, instance.slot_number, answer.created_at;
$$;

create or replace function public.get_daily_questions_history()
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
  can_view_partner_answer boolean
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_daily_questions_history();
$$;

create or replace function public.get_daily_answer_history_details()
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
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_daily_answer_history_details();
$$;

revoke all on function internal.get_daily_questions_history() from public, anon, authenticated;
grant execute on function internal.get_daily_questions_history() to authenticated, service_role;

revoke all on function internal.get_daily_answer_history_details() from public, anon, authenticated;
grant execute on function internal.get_daily_answer_history_details() to authenticated, service_role;

revoke all on function public.get_daily_questions_history() from public, anon;
grant execute on function public.get_daily_questions_history() to authenticated, service_role;

revoke all on function public.get_daily_answer_history_details() from public, anon;
grant execute on function public.get_daily_answer_history_details() to authenticated, service_role;
