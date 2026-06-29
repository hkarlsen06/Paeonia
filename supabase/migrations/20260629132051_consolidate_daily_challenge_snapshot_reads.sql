-- Consolidate the launch-time Daily Challenge read path into one RPC while keeping
-- write/upload/sync boundaries separate. The snapshot reuses the existing question,
-- answer-detail, and streak read models so reveal rules and streak repair stay in
-- one place.

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
  select
    couple_day.id,
    instance.id,
    instance.seeded_for_user_id,
    instance.slot_number,
    answer.user_id,
    answer.id,
    answer.created_at,
    answer.user_id = (select auth.uid()),
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
  from public.couple_days couple_day
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
  where couple_day.id = any(coalesce(p_couple_day_ids, array[]::uuid[]))
    and internal.can_access_couple_content(couple_day.couple_id)
  order by couple_day.starts_at desc, instance.slot_number, answer.created_at, answer.id;
$$;

create or replace function public.get_daily_answer_details_for_couple_days(
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
  select *
  from internal.get_daily_answer_details_for_couple_days(p_couple_day_ids);
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
  with question_rows as materialized (
    select *
    from internal.get_today_daily_questions()
  ),
  answer_detail_rows as materialized (
    select *
    from internal.get_daily_answer_details_for_couple_days(
      coalesce(
        (select array_agg(distinct question_rows.couple_day_id) from question_rows),
        array[]::uuid[]
      )
    )
  ),
  streak_rows as materialized (
    select *
    from internal.get_couple_streak()
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

create or replace function public.get_today_daily_challenge_snapshot()
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
  select *
  from internal.get_today_daily_challenge_snapshot();
$$;

create or replace function public.start_daily_challenge_snapshot(
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  questions jsonb,
  answer_details jsonb,
  streak jsonb,
  generated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.start_daily_challenge(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_today_daily_challenge_snapshot();
end;
$$;

create or replace function public.shuffle_daily_question_snapshot(
  p_slot_number smallint,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns table (
  questions jsonb,
  answer_details jsonb,
  streak jsonb,
  generated_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.shuffle_daily_question(
    p_slot_number,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  return query
  select *
  from internal.get_today_daily_challenge_snapshot();
end;
$$;

-- Keep the older single-day wrapper callable for existing clients while aligning it
-- with the repository rule for public wrappers over private internal functions.
alter function public.get_daily_answer_details(uuid)
  security definer;
alter function public.get_daily_answer_details(uuid)
  set search_path = pg_catalog;

-- These media RPCs stay separate for idempotent upload/retry boundaries, but they
-- are also public wrappers over internal helpers and should use the same wrapper
-- security model.
alter function public.create_pending_media_upload(
  uuid,
  uuid,
  bigint,
  timestamptz,
  text,
  uuid,
  text,
  text,
  text,
  uuid,
  timestamptz,
  jsonb
) security definer;
alter function public.create_pending_media_upload(
  uuid,
  uuid,
  bigint,
  timestamptz,
  text,
  uuid,
  text,
  text,
  text,
  uuid,
  timestamptz,
  jsonb
) set search_path = pg_catalog;

alter function public.finalize_media_upload(
  uuid,
  uuid,
  uuid,
  uuid,
  bigint,
  timestamptz,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  bigint,
  text,
  integer,
  integer,
  integer
) security definer;
alter function public.finalize_media_upload(
  uuid,
  uuid,
  uuid,
  uuid,
  bigint,
  timestamptz,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  bigint,
  text,
  integer,
  integer,
  integer
) set search_path = pg_catalog;

alter function public.get_media_signed_url(uuid, integer)
  security definer;
alter function public.get_media_signed_url(uuid, integer)
  set search_path = pg_catalog;

revoke all on function internal.get_daily_answer_details_for_couple_days(uuid[]) from public, anon, authenticated;
grant execute on function internal.get_daily_answer_details_for_couple_days(uuid[]) to service_role;

revoke all on function internal.get_today_daily_challenge_snapshot() from public, anon, authenticated;
grant execute on function internal.get_today_daily_challenge_snapshot() to service_role;

revoke all on function public.get_daily_answer_details_for_couple_days(uuid[]) from public, anon;
grant execute on function public.get_daily_answer_details_for_couple_days(uuid[]) to authenticated, service_role;

revoke all on function public.get_today_daily_challenge_snapshot() from public, anon;
grant execute on function public.get_today_daily_challenge_snapshot() to authenticated, service_role;

revoke all on function public.start_daily_challenge_snapshot(uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.start_daily_challenge_snapshot(uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.shuffle_daily_question_snapshot(smallint, uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.shuffle_daily_question_snapshot(smallint, uuid, uuid, bigint, timestamptz) to authenticated, service_role;
