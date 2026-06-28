create or replace function internal.resolve_user_entitlement(p_user_id uuid)
returns table (
  user_id uuid,
  is_entitled boolean,
  source text,
  status text,
  product_id uuid,
  current_period_end timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  with ranked_entitlements as (
    select
      ent.user_id,
      ent.source,
      ent.status,
      ent.product_id,
      ent.current_period_end,
      ent.updated_at,
      case
        when ent.source = 'storekit' then
          ent.status in ('active', 'grace')
          and ent.current_period_end is not null
          and ent.current_period_end > now()
        when ent.source = 'lifetime_grant' then
          ent.status = 'lifetime'
          and (ent.current_period_end is null or ent.current_period_end > now())
        else
          ent.status = 'active'
          and ent.current_period_end is not null
          and ent.current_period_end > now()
      end as grants_access
    from public.user_entitlements ent
    where ent.user_id = p_user_id
  ),
  entitlement_summary as (
    select coalesce(bool_or(grants_access), false) as is_entitled
    from ranked_entitlements
  ),
  best_entitlement as (
    select
      ranked.source,
      ranked.status,
      ranked.product_id,
      ranked.current_period_end,
      ranked.updated_at
    from ranked_entitlements ranked
    order by
      ranked.grants_access desc,
      case ranked.status
        when 'lifetime' then 0
        when 'active' then 1
        when 'grace' then 2
        else 3
      end,
      ranked.current_period_end desc nulls first,
      ranked.updated_at desc
    limit 1
  )
  select
    p_user_id,
    entitlement_summary.is_entitled,
    best_entitlement.source,
    best_entitlement.status,
    best_entitlement.product_id,
    best_entitlement.current_period_end,
    best_entitlement.updated_at
  from entitlement_summary
  left join best_entitlement on true;
$$;

create or replace function internal.resolve_current_couple_entitlement()
returns table (
  couple_id uuid,
  is_entitled boolean,
  covering_user_id uuid,
  source text,
  status text,
  product_id uuid,
  current_period_end timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  with current_couple as (
    select couple.id as couple_id
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = (select auth.uid())
      and member.status = 'active'
      and couple.status = 'active'
    order by couple.created_at desc
    limit 1
  ),
  member_entitlements as (
    select
      current_couple.couple_id,
      member.user_id,
      entitlement.is_entitled,
      entitlement.source,
      entitlement.status,
      entitlement.product_id,
      entitlement.current_period_end,
      entitlement.updated_at
    from current_couple
    join public.couple_members member
      on member.couple_id = current_couple.couple_id
      and member.status = 'active'
    join internal.resolve_user_entitlement(member.user_id) entitlement
      on true
  ),
  entitlement_summary as (
    select
      current_couple.couple_id,
      coalesce(bool_or(member_entitlements.is_entitled), false) as is_entitled
    from current_couple
    left join member_entitlements
      on member_entitlements.couple_id = current_couple.couple_id
    group by current_couple.couple_id
  ),
  best_entitlement as (
    select
      candidate.couple_id,
      candidate.user_id,
      candidate.source,
      candidate.status,
      candidate.product_id,
      candidate.current_period_end,
      candidate.updated_at
    from member_entitlements candidate
    where candidate.is_entitled
    order by
      case candidate.status
        when 'lifetime' then 0
        when 'active' then 1
        when 'grace' then 2
        else 3
      end,
      candidate.current_period_end desc nulls first,
      candidate.updated_at desc
    limit 1
  )
  select
    entitlement_summary.couple_id,
    entitlement_summary.is_entitled,
    best_entitlement.user_id,
    best_entitlement.source,
    best_entitlement.status,
    best_entitlement.product_id,
    best_entitlement.current_period_end,
    best_entitlement.updated_at
  from entitlement_summary
  left join best_entitlement
    on best_entitlement.couple_id = entitlement_summary.couple_id;
$$;

create or replace function internal.get_access_snapshot()
returns table (
  user_entitlement jsonb,
  couple_entitlement jsonb,
  relationship_state jsonb
)
language sql
security definer
set search_path = pg_catalog
as $$
  with user_entitlement_row as (
    select *
    from internal.resolve_user_entitlement((select auth.uid()))
  ),
  couple_entitlement_row as (
    select *
    from internal.resolve_current_couple_entitlement()
  ),
  relationship_state_row as (
    select *
    from internal.get_current_relationship_state()
  )
  select
    (select to_jsonb(user_entitlement_row) from user_entitlement_row) as user_entitlement,
    (select to_jsonb(couple_entitlement_row) from couple_entitlement_row) as couple_entitlement,
    (select to_jsonb(relationship_state_row) from relationship_state_row) as relationship_state;
$$;

create or replace function public.get_access_snapshot()
returns table (
  user_entitlement jsonb,
  couple_entitlement jsonb,
  relationship_state jsonb
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.get_access_snapshot();
$$;

revoke all on function public.get_access_snapshot() from public, anon;
grant execute on function public.get_access_snapshot() to authenticated, service_role;

create index if not exists couple_days_current_window_idx
on public.couple_days (couple_id, starts_at desc, ends_at)
include (id, local_date);

alter table internal.client_operations set (
  autovacuum_vacuum_scale_factor = 0.01,
  autovacuum_vacuum_threshold = 50,
  autovacuum_analyze_scale_factor = 0.02,
  autovacuum_analyze_threshold = 50
);

create index if not exists client_operations_succeeded_completed_idx
on internal.client_operations (completed_at)
where status = 'succeeded';
