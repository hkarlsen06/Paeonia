-- Raise the per-person daily skip (shuffle) cap from 5 to 30. Five swaps across
-- three slots felt punitive; 30 is effectively unlimited for everyday use while
-- keeping a ceiling against runaway churn through the question catalog.
--
-- This restates `internal.shuffle_daily_question` verbatim from
-- 20260614234610_daily_challenges_answers_reveal.sql with the single threshold
-- change, because `create or replace function` needs the whole body.

create or replace function internal.shuffle_daily_question(
  p_slot_number smallint,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_couple_id uuid;
  resolved_couple_day_id uuid;
  active_instance_row public.daily_question_instances%rowtype;
  skipped_question_id uuid;
  picked_question_version_id uuid;
  replacement_instance_id uuid;
  shuffle_count integer;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_slot_number not between 1 and 3 then
    raise exception 'slot number is out of range'
      using errcode = '23514';
  end if;

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  resolved_couple_id = internal.get_current_entitled_couple_id();

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'shuffle_daily_question',
      resolved_couple_id::text,
      current_user_id::text,
      p_slot_number::text,
      p_local_created_at::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'shuffle_daily_question',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'replacement_instance_id')::uuid;
  end if;

  resolved_couple_day_id = internal.get_or_create_couple_day_at(
    resolved_couple_id,
    p_local_created_at
  );
  perform internal.ensure_daily_challenge_slots(resolved_couple_day_id);

  perform 1
  from public.daily_challenges challenge
  where challenge.couple_day_id = resolved_couple_day_id
    and challenge.user_id = current_user_id
  for update;

  select count(*)
  into shuffle_count
  from public.daily_question_shuffles shuffle
  where shuffle.couple_day_id = resolved_couple_day_id
    and shuffle.user_id = current_user_id;

  if shuffle_count >= 30 then
    raise exception 'daily shuffle limit reached'
      using errcode = '23514';
  end if;

  select *
  into active_instance_row
  from public.daily_question_instances instance
  where instance.couple_day_id = resolved_couple_day_id
    and instance.seeded_for_user_id = current_user_id
    and instance.slot_number = p_slot_number
    and instance.status = 'active'
  for update;

  if not found then
    raise exception 'active daily question slot was not found'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.daily_question_answers answer
    where answer.instance_id = active_instance_row.id
      and answer.user_id = current_user_id
      and answer.deleted_at is null
  ) then
    raise exception 'answered daily questions cannot be shuffled'
      using errcode = '23514';
  end if;

  select version.question_id
  into skipped_question_id
  from public.question_versions version
  where version.id = active_instance_row.question_version_id;

  picked_question_version_id = internal.pick_daily_question_version(
    resolved_couple_day_id,
    current_user_id,
    skipped_question_id
  );

  update public.daily_question_instances
  set
    status = 'shuffled',
    replaced_at = now()
  where id = active_instance_row.id;

  insert into public.daily_question_instances (
    couple_day_id,
    question_version_id,
    seeded_for_user_id,
    slot_number
  ) values (
    resolved_couple_day_id,
    picked_question_version_id,
    current_user_id,
    p_slot_number
  )
  returning id into replacement_instance_id;

  update public.daily_question_instances
  set replaced_by_instance_id = replacement_instance_id
  where id = active_instance_row.id;

  insert into public.daily_question_shuffles (
    couple_id,
    couple_day_id,
    user_id,
    question_id,
    skipped_instance_id,
    replacement_instance_id,
    slot_number,
    exclude_until
  ) values (
    resolved_couple_id,
    resolved_couple_day_id,
    current_user_id,
    skipped_question_id,
    active_instance_row.id,
    replacement_instance_id,
    p_slot_number,
    now() + interval '14 days'
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('replacement_instance_id', replacement_instance_id)
  );

  return replacement_instance_id;
end;
$$;
