-- Allow a user to edit the text of their own daily answer, but only while it is
-- still private. Once the partner has answered the same question instance the
-- content is (or is about to be) revealed, so editing is locked from then on.

create or replace function internal.update_daily_answer_text(
  p_instance_id uuid,
  p_text text,
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
  instance_row public.daily_question_instances%rowtype;
  couple_day_row public.couple_days%rowtype;
  answer_row public.daily_question_answers%rowtype;
  allowed_kinds text[];
  text_body text;
  request_hash bytea;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_local_created_at is null then
    raise exception 'daily operation timestamp is required'
      using errcode = '23514';
  end if;

  text_body = nullif(btrim(coalesce(p_text, '')), '');

  if text_body is null then
    raise exception 'answer text is required'
      using errcode = '23514';
  end if;

  if char_length(text_body) > 2000 then
    raise exception 'answer text is too long'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    concat_ws(
      '|',
      'update_daily_answer_text',
      p_instance_id::text,
      text_body
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'update_daily_answer_text',
    'daily_challenges',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'answer_id')::uuid;
  end if;

  -- Lock the instance so a partner answering concurrently cannot slip past the
  -- "still private" check below.
  select *
  into instance_row
  from public.daily_question_instances
  where id = p_instance_id
  for update;

  if not found then
    raise exception 'daily question instance was not found'
      using errcode = '22023';
  end if;

  if instance_row.status = 'shuffled' then
    raise exception 'shuffled daily questions cannot be edited'
      using errcode = '23514';
  end if;

  select *
  into couple_day_row
  from public.couple_days
  where id = instance_row.couple_day_id;

  if p_local_created_at < couple_day_row.starts_at
    or p_local_created_at >= couple_day_row.ends_at then
    raise exception 'daily answer timestamp is outside the question day'
      using errcode = '23514';
  end if;

  if not internal.can_access_couple_content(couple_day_row.couple_id) then
    raise exception 'active entitled couple access is required'
      using errcode = '42501';
  end if;

  -- The answer being edited must already exist and belong to the current user.
  select *
  into answer_row
  from public.daily_question_answers
  where instance_id = instance_row.id
    and user_id = current_user_id
    and deleted_at is null
  for update;

  if not found then
    raise exception 'there is no answer to edit'
      using errcode = '22023';
  end if;

  -- Once the partner has answered the same instance the answer is revealed, so it
  -- can no longer be changed.
  if exists (
    select 1
    from public.daily_question_answers other_answer
    where other_answer.instance_id = instance_row.id
      and other_answer.user_id <> current_user_id
      and other_answer.deleted_at is null
      and other_answer.moderation_status = 'visible'
  ) then
    raise exception 'answers cannot be edited after your partner has answered'
      using errcode = '23514';
  end if;

  select array_agg(answer_kind.answer_kind)
  into allowed_kinds
  from public.question_answer_kinds answer_kind
  where answer_kind.question_version_id = instance_row.question_version_id;

  if not ('text' = any(coalesce(allowed_kinds, array[]::text[]))) then
    raise exception 'answer kind is not allowed for this question'
      using errcode = '23514';
  end if;

  insert into public.daily_answer_text (answer_id, body)
  values (answer_row.id, text_body)
  on conflict (answer_id) do update
    set body = excluded.body;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('answer_id', answer_row.id)
  );

  return answer_row.id;
end;
$$;

create or replace function public.update_daily_answer_text(
  p_instance_id uuid,
  p_text text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language sql
-- Runs as the function owner so it can reach the private `internal` schema, which
-- `authenticated` has no USAGE on. Matches the other public daily-challenge RPCs.
-- Auth is still enforced inside `internal.update_daily_answer_text` via auth.uid().
security definer
set search_path = pg_catalog
as $$
  select internal.update_daily_answer_text(
    p_instance_id,
    p_text,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

revoke all on function internal.update_daily_answer_text(uuid, text, uuid, uuid, bigint, timestamptz)
  from public, anon, authenticated;
grant execute on function internal.update_daily_answer_text(uuid, text, uuid, uuid, bigint, timestamptz)
  to authenticated, service_role;

revoke all on function public.update_daily_answer_text(uuid, text, uuid, uuid, bigint, timestamptz)
  from public, anon;
grant execute on function public.update_daily_answer_text(uuid, text, uuid, uuid, bigint, timestamptz)
  to authenticated, service_role;
