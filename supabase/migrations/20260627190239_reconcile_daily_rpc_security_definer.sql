-- Reconcile committed source with production.
--
-- `public.submit_daily_answer` and `public.shuffle_daily_question` were declared
-- `security invoker` in their original migration (20260614234610), but production
-- runs them as `security definer`. That difference is load-bearing: `authenticated`
-- has no USAGE on the private `internal` schema, so an invoker wrapper raises
-- "permission denied for schema internal" when it tries to call `internal.*`. The
-- live functions were changed to definer directly on the database, which left the
-- migrations out of sync — a fresh deploy from source would recreate them as
-- invoker and break both RPCs.
--
-- These re-declarations restore the wrappers as `security definer` (matching prod)
-- so the committed migrations are the source of truth again. The bodies are
-- unchanged; auth is still enforced inside the `internal.*` functions via
-- auth.uid(). Re-running this against production is a no-op.

create or replace function public.submit_daily_answer(
  p_instance_id uuid,
  p_payload jsonb,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.submit_daily_answer(
    p_instance_id,
    p_payload,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.shuffle_daily_question(
  p_slot_number smallint,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
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
  can_view_partner_answer boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_day_id uuid;
  replacement_instance_id uuid;
begin
  replacement_instance_id = internal.shuffle_daily_question(
    p_slot_number,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );

  select instance.couple_day_id
  into resolved_couple_day_id
  from public.daily_question_instances instance
  where instance.id = replacement_instance_id;

  return query
  select *
  from internal.get_daily_questions_for_couple_day(resolved_couple_day_id);
end;
$$;

revoke all on function public.submit_daily_answer(uuid, jsonb, uuid, uuid, bigint, timestamptz)
  from public, anon;
grant execute on function public.submit_daily_answer(uuid, jsonb, uuid, uuid, bigint, timestamptz)
  to authenticated, service_role;

revoke all on function public.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz)
  from public, anon;
grant execute on function public.shuffle_daily_question(smallint, uuid, uuid, bigint, timestamptz)
  to authenticated, service_role;
