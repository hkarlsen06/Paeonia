-- Fix: the question-history public wrappers were created `security invoker` in
-- 20260628234249, but `authenticated` has no USAGE on the private `internal` schema,
-- so calling them raised "permission denied for schema internal" (SQLSTATE 42501)
-- the moment they tried to reach `internal.get_daily_*_history*()`.
--
-- Re-declare both wrappers as `security definer` with a fixed search_path, matching
-- every other app-callable daily wrapper (see 20260627190239). Auth is still enforced
-- inside the `internal.*` functions via auth.uid()/get_current_entitled_couple_id().
-- The bodies are unchanged; re-running this is a no-op.

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
security definer
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
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.get_daily_answer_history_details();
$$;

revoke all on function public.get_daily_questions_history() from public, anon;
grant execute on function public.get_daily_questions_history() to authenticated, service_role;

revoke all on function public.get_daily_answer_history_details() from public, anon;
grant execute on function public.get_daily_answer_history_details() to authenticated, service_role;
