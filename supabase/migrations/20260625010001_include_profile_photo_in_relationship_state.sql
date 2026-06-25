drop function if exists public.get_current_relationship_state();
drop function if exists internal.get_current_relationship_state();

create or replace function internal.get_current_relationship_state()
returns table (
  couple_id uuid,
  pair_id uuid,
  relationship_status text,
  member_status text,
  partner_user_id uuid,
  partner_display_name text,
  partner_profile_photo_asset_id uuid,
  started_on date,
  ended_at timestamptz,
  delete_after timestamptz,
  ended_notice_seen_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  select
    couple.id,
    couple.pair_id,
    couple.status,
    self_member.status,
    partner_member.user_id,
    case
      when partner_profile.moderation_status = 'visible' then partner_profile.display_name
      else null
    end,
    case
      when partner_profile.moderation_status = 'visible' then partner_profile.profile_photo_asset_id
      else null
    end,
    couple.started_on,
    couple.ended_at,
    couple.delete_after,
    self_member.ended_notice_seen_at
  from public.couple_members self_member
  join public.couples couple
    on couple.id = self_member.couple_id
  left join public.couple_members partner_member
    on partner_member.couple_id = self_member.couple_id
    and partner_member.user_id <> self_member.user_id
  left join public.profiles partner_profile
    on partner_profile.user_id = partner_member.user_id
  where self_member.user_id = (select auth.uid())
    and (
      (couple.status = 'active' and self_member.status = 'active')
      or (couple.status = 'ended' and self_member.status in ('ended_notice_pending', 'ended_notice_seen', 'left'))
    )
  order by
    case when couple.status = 'active' and self_member.status = 'active' then 0 else 1 end,
    couple.created_at desc
  limit 1;
$$;

create or replace function public.get_current_relationship_state()
returns table (
  couple_id uuid,
  pair_id uuid,
  relationship_status text,
  member_status text,
  partner_user_id uuid,
  partner_display_name text,
  partner_profile_photo_asset_id uuid,
  started_on date,
  ended_at timestamptz,
  delete_after timestamptz,
  ended_notice_seen_at timestamptz
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.get_current_relationship_state();
$$;

revoke all on function internal.get_current_relationship_state() from public, anon, authenticated;
grant execute on function internal.get_current_relationship_state() to authenticated, service_role;

revoke all on function public.get_current_relationship_state() from public, anon;
grant execute on function public.get_current_relationship_state() to authenticated, service_role;
