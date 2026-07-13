-- Keep the durable streak ledger intact for restore and future activity math,
-- but never expose its historical count as the couple's live streak after the
-- activity grace day has fully elapsed. Previously an expired restore offer
-- made the iOS client treat the preserved count as healthy again because the
-- read model returned current_count unchanged while restore_available became
-- false.
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
    case
      when streak.next_activity_deadline_at is not null
        and now() >= streak.next_activity_deadline_at + interval '1 day'
        then 0
      else coalesce(streak.current_count, 0)
    end,
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

revoke all on function internal.get_couple_streak_for_couple(uuid) from public, anon, authenticated;
grant execute on function internal.get_couple_streak_for_couple(uuid) to service_role;
