-- Expose the couple's daily-challenge streak to the app.
--
-- `public.streak_states` is maintained automatically by the
-- `handle_daily_challenge_completed` trigger (see
-- 20260615012605_location_streaks_notifications.sql) and is locked to
-- service_role. The app has no way to read it. This adds a thin, read-only RPC
-- so the daily-challenge completion celebration (and, later, the Us-tab streak
-- label) can show the real count.
--
-- Follows the project's RPC convention: a public `security definer` wrapper over
-- a private `internal.*` implementation that resolves the caller from auth.uid()
-- via `internal.get_current_entitled_couple_id()`.

create or replace function internal.get_couple_streak()
returns table (
  current_count integer,
  longest_count integer,
  last_qualified_date date,
  restore_available boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_couple_id uuid;
begin
  -- Raises if the caller is not an authenticated, entitled couple member, the
  -- same gate the other daily-challenge RPCs use.
  resolved_couple_id = internal.get_current_entitled_couple_id();

  -- Always returns exactly one row: the stored streak, or zeros for a couple
  -- that has never completed a challenge yet.
  return query
  select
    coalesce(streak.current_count, 0),
    coalesce(streak.longest_count, 0),
    streak.last_qualified_date,
    coalesce(streak.restore_available, false)
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
  restore_available boolean
)
language sql
security definer
set search_path = pg_catalog
as $$
  select * from internal.get_couple_streak();
$$;

revoke all on function internal.get_couple_streak() from public, anon, authenticated;
grant execute on function internal.get_couple_streak() to service_role;

revoke all on function public.get_couple_streak() from public, anon;
grant execute on function public.get_couple_streak() to authenticated, service_role;
