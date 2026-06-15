create table public.subscription_products (
  id uuid primary key default extensions.gen_random_uuid(),
  apple_product_id text not null,
  kind text not null,
  billing_period text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint subscription_products_apple_product_id_check
    check (char_length(btrim(apple_product_id)) between 1 and 255),
  constraint subscription_products_kind_check
    check (kind in ('couple_subscription')),
  constraint subscription_products_billing_period_check
    check (billing_period in ('monthly', 'yearly')),
  constraint subscription_products_apple_product_id_unique
    unique (apple_product_id)
);

create trigger set_subscription_products_updated_at
before update on public.subscription_products
for each row
execute function internal.set_updated_at();

create table internal.storekit_payloads (
  id uuid primary key default extensions.gen_random_uuid(),
  payload_kind text not null,
  environment text not null,
  original_transaction_id text,
  transaction_id text,
  notification_uuid uuid,
  signed_payload text,
  payload_json jsonb,
  sha256 bytea,
  received_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  constraint storekit_payloads_payload_kind_check
    check (payload_kind in ('transaction', 'renewal_info', 'server_notification', 'server_api_response')),
  constraint storekit_payloads_environment_check
    check (environment in ('xcode', 'sandbox', 'production')),
  constraint storekit_payloads_original_transaction_id_check
    check (original_transaction_id is null or char_length(btrim(original_transaction_id)) between 1 and 255),
  constraint storekit_payloads_transaction_id_check
    check (transaction_id is null or char_length(btrim(transaction_id)) between 1 and 255),
  constraint storekit_payloads_signed_payload_check
    check (signed_payload is null or char_length(signed_payload) <= 262144),
  constraint storekit_payloads_payload_json_check
    check (payload_json is null or jsonb_typeof(payload_json) = 'object'),
  constraint storekit_payloads_sha256_check
    check (sha256 is null or octet_length(sha256) = 32)
);

create table internal.storekit_transactions (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null,
  product_id uuid not null references public.subscription_products (id) on delete restrict,
  environment text not null,
  app_account_token uuid,
  original_transaction_id text not null,
  transaction_id text not null,
  web_order_line_item_id text,
  status text not null,
  purchased_at timestamptz,
  expires_at timestamptz,
  revoked_at timestamptz,
  revocation_reason text,
  raw_payload_id uuid references internal.storekit_payloads (id) on delete restrict,
  last_reconciled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint storekit_transactions_environment_check
    check (environment in ('xcode', 'sandbox', 'production')),
  constraint storekit_transactions_original_transaction_id_check
    check (char_length(btrim(original_transaction_id)) between 1 and 255),
  constraint storekit_transactions_transaction_id_check
    check (char_length(btrim(transaction_id)) between 1 and 255),
  constraint storekit_transactions_web_order_line_item_id_check
    check (web_order_line_item_id is null or char_length(btrim(web_order_line_item_id)) between 1 and 255),
  constraint storekit_transactions_status_check
    check (status in ('active', 'grace', 'billing_retry', 'expired', 'revoked', 'refunded')),
  constraint storekit_transactions_revoked_state_check
    check (
      (status in ('revoked', 'refunded') and revoked_at is not null)
      or (status not in ('revoked', 'refunded') and revoked_at is null)
    ),
  constraint storekit_transactions_access_expiry_check
    check (
      status not in ('active', 'grace')
      or expires_at is not null
    ),
  constraint storekit_transactions_revocation_reason_check
    check (revocation_reason is null or char_length(revocation_reason) <= 512),
  constraint storekit_transactions_environment_transaction_unique
    unique (environment, transaction_id)
);

create trigger set_storekit_transactions_updated_at
before update on internal.storekit_transactions
for each row
execute function internal.set_updated_at();

create table internal.storekit_notification_events (
  id uuid primary key default extensions.gen_random_uuid(),
  notification_uuid uuid not null,
  notification_type text not null,
  subtype text,
  environment text not null,
  original_transaction_id text,
  raw_payload_id uuid references internal.storekit_payloads (id) on delete restrict,
  signed_payload text,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_error text,
  created_at timestamptz not null default now(),

  constraint storekit_notification_events_notification_uuid_unique
    unique (notification_uuid),
  constraint storekit_notification_events_notification_type_check
    check (char_length(btrim(notification_type)) between 1 and 120),
  constraint storekit_notification_events_subtype_check
    check (subtype is null or char_length(btrim(subtype)) between 1 and 120),
  constraint storekit_notification_events_environment_check
    check (environment in ('xcode', 'sandbox', 'production')),
  constraint storekit_notification_events_original_transaction_id_check
    check (original_transaction_id is null or char_length(btrim(original_transaction_id)) between 1 and 255),
  constraint storekit_notification_events_signed_payload_check
    check (signed_payload is null or char_length(signed_payload) <= 262144),
  constraint storekit_notification_events_processing_error_check
    check (processing_error is null or char_length(processing_error) <= 4000)
);

create table internal.review_access_codes (
  id uuid primary key default extensions.gen_random_uuid(),
  code_hash bytea not null,
  seeded_partner_user_id uuid,
  scenario text not null,
  status text not null default 'active',
  expires_at timestamptz,
  max_redemptions integer not null default 1,
  redemption_count integer not null default 0,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,

  constraint review_access_codes_code_hash_check
    check (octet_length(code_hash) = 32),
  constraint review_access_codes_code_hash_unique
    unique (code_hash),
  constraint review_access_codes_scenario_check
    check (scenario in ('pre_paired_entitled', 'purchase_flow_unentitled')),
  constraint review_access_codes_status_check
    check (status in ('active', 'revoked', 'expired')),
  constraint review_access_codes_redemption_count_check
    check (redemption_count >= 0 and max_redemptions > 0 and redemption_count <= max_redemptions),
  constraint review_access_codes_revoked_state_check
    check ((status = 'revoked' and revoked_at is not null) or status <> 'revoked'),
  constraint review_access_codes_prepaired_partner_check
    check (scenario <> 'pre_paired_entitled' or seeded_partner_user_id is not null)
);

create table internal.review_access_attempts (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null,
  code_hash_prefix text not null,
  matched_code_id uuid references internal.review_access_codes (id) on delete set null,
  success boolean not null default false,
  failure_reason text,
  ip_hash bytea,
  device_hash bytea,
  app_version text,
  attempted_at timestamptz not null default now(),

  constraint review_access_attempts_code_hash_prefix_check
    check (char_length(code_hash_prefix) between 1 and 32),
  constraint review_access_attempts_failure_reason_check
    check (failure_reason is null or char_length(failure_reason) between 1 and 120),
  constraint review_access_attempts_ip_hash_check
    check (ip_hash is null or octet_length(ip_hash) = 32),
  constraint review_access_attempts_device_hash_check
    check (device_hash is null or octet_length(device_hash) = 32),
  constraint review_access_attempts_app_version_check
    check (app_version is null or char_length(btrim(app_version)) between 1 and 64),
  constraint review_access_attempts_success_failure_check
    check ((success and failure_reason is null) or (not success and failure_reason is not null))
);

create table internal.review_access_sessions (
  id uuid primary key default extensions.gen_random_uuid(),
  code_id uuid not null references internal.review_access_codes (id) on delete restrict,
  user_id uuid not null,
  seeded_partner_user_id uuid,
  couple_id uuid references public.couples (id) on delete restrict,
  entitlement_grant_id uuid,
  scenario text not null,
  auth_verified_at timestamptz not null,
  completed_at timestamptz,
  redeemed_at timestamptz not null default now(),
  user_agent text,
  app_version text,
  device_info jsonb,

  constraint review_access_sessions_scenario_check
    check (scenario in ('pre_paired_entitled', 'purchase_flow_unentitled')),
  constraint review_access_sessions_user_agent_check
    check (user_agent is null or char_length(user_agent) <= 512),
  constraint review_access_sessions_app_version_check
    check (app_version is null or char_length(btrim(app_version)) between 1 and 64),
  constraint review_access_sessions_device_info_check
    check (device_info is null or jsonb_typeof(device_info) = 'object'),
  constraint review_access_sessions_prepaired_partner_check
    check (scenario <> 'pre_paired_entitled' or seeded_partner_user_id is not null)
);

create table internal.entitlement_grants (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null,
  product_id uuid references public.subscription_products (id) on delete restrict,
  grant_kind text not null,
  status text not null default 'active',
  scope text not null default 'user',
  environment text,
  source_review_session_id uuid references internal.review_access_sessions (id) on delete restrict deferrable initially deferred,
  reason text,
  granted_by text,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint entitlement_grants_grant_kind_check
    check (grant_kind in ('lifetime', 'review', 'test', 'beta')),
  constraint entitlement_grants_status_check
    check (status in ('active', 'expired', 'revoked')),
  constraint entitlement_grants_scope_check
    check (scope in ('user', 'review')),
  constraint entitlement_grants_environment_check
    check (environment is null or environment in ('xcode', 'sandbox', 'production')),
  constraint entitlement_grants_review_session_check
    check (grant_kind <> 'review' or source_review_session_id is not null),
  constraint entitlement_grants_review_test_expiry_check
    check (grant_kind not in ('review', 'test') or expires_at is not null),
  constraint entitlement_grants_revoked_state_check
    check ((status = 'revoked' and revoked_at is not null) or (status <> 'revoked' and revoked_at is null)),
  constraint entitlement_grants_reason_check
    check (reason is null or char_length(reason) <= 1000),
  constraint entitlement_grants_granted_by_check
    check (granted_by is null or char_length(granted_by) <= 255),
  constraint entitlement_grants_revoked_reason_check
    check (revoked_reason is null or char_length(revoked_reason) <= 1000)
);

create trigger set_entitlement_grants_updated_at
before update on internal.entitlement_grants
for each row
execute function internal.set_updated_at();

alter table internal.review_access_sessions
add constraint review_access_sessions_entitlement_grant_id_fkey
foreign key (entitlement_grant_id)
references internal.entitlement_grants (id)
on delete restrict
deferrable initially deferred;

create or replace view public.user_entitlements
with (security_invoker = true)
as
select
  tx.user_id,
  'storekit'::text as source,
  tx.status,
  tx.product_id,
  tx.expires_at as current_period_end,
  coalesce(tx.last_reconciled_at, tx.updated_at, tx.created_at) as updated_at
from internal.storekit_transactions tx
union all
select
  grant_row.user_id,
  case grant_row.grant_kind
    when 'lifetime' then 'lifetime_grant'
    when 'review' then 'review_grant'
    else 'test_grant'
  end as source,
  case
    when grant_row.status = 'revoked' then 'revoked'
    when grant_row.status = 'expired' then 'expired'
    when grant_row.expires_at is not null and grant_row.expires_at <= now() then 'expired'
    when grant_row.grant_kind = 'lifetime' then 'lifetime'
    else 'active'
  end as status,
  grant_row.product_id,
  grant_row.expires_at as current_period_end,
  grant_row.updated_at
from internal.entitlement_grants grant_row;

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
  )
  select
    p_user_id,
    coalesce(bool_or(grants_access), false) as is_entitled,
    (
      select ranked.source
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
    ) as source,
    (
      select ranked.status
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
    ) as status,
    (
      select ranked.product_id
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
    ) as product_id,
    (
      select ranked.current_period_end
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
    ) as current_period_end,
    (
      select ranked.updated_at
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
    ) as updated_at
  from ranked_entitlements;
$$;

create or replace function internal.user_has_direct_entitlement(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select coalesce((
    select resolved.is_entitled
    from internal.resolve_user_entitlement(p_user_id) resolved
  ), false);
$$;

create or replace function internal.is_active_entitled_couple_member(p_couple_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.couple_id = p_couple_id
      and member.user_id = (select auth.uid())
      and member.status = 'active'
      and couple.status = 'active'
      and exists (
        select 1
        from public.couple_members any_member
        join internal.resolve_user_entitlement(any_member.user_id) entitlement
          on entitlement.is_entitled
        where any_member.couple_id = p_couple_id
          and any_member.status = 'active'
      )
  );
$$;

create or replace function internal.can_access_couple_content(p_couple_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.is_active_entitled_couple_member(p_couple_id);
$$;

create or replace function public.get_my_entitlement()
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
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.resolve_user_entitlement((select auth.uid()));
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
  )
  select
    current_couple.couple_id,
    coalesce(bool_or(member_entitlements.is_entitled), false) as is_entitled,
    (
      select candidate.user_id
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
    ) as covering_user_id,
    (
      select candidate.source
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
    ) as source,
    (
      select candidate.status
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
    ) as status,
    (
      select candidate.product_id
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
    ) as product_id,
    (
      select candidate.current_period_end
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
    ) as current_period_end,
    (
      select candidate.updated_at
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
    ) as updated_at
  from current_couple
  left join member_entitlements
    on member_entitlements.couple_id = current_couple.couple_id
  group by current_couple.couple_id;
$$;

create or replace function public.get_my_couple_entitlement()
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
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.resolve_current_couple_entitlement();
$$;

create or replace function internal.complete_review_access_session(p_review_session_id uuid)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  changed_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update internal.review_access_sessions
  set completed_at = coalesce(completed_at, now())
  where id = p_review_session_id
    and user_id = current_user_id;

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function public.complete_review_access_session(p_review_session_id uuid)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.complete_review_access_session(p_review_session_id);
$$;

alter table public.subscription_products enable row level security;
alter table internal.storekit_payloads enable row level security;
alter table internal.storekit_transactions enable row level security;
alter table internal.storekit_notification_events enable row level security;
alter table internal.entitlement_grants enable row level security;
alter table internal.review_access_codes enable row level security;
alter table internal.review_access_attempts enable row level security;
alter table internal.review_access_sessions enable row level security;

create policy subscription_products_select_active
on public.subscription_products
for select
to authenticated
using (is_active);

create unique index storekit_payloads_environment_sha256_unique_idx
on internal.storekit_payloads (environment, sha256)
where sha256 is not null;

create index storekit_transactions_user_status_expires_at_idx
on internal.storekit_transactions (user_id, status, expires_at);

create index storekit_transactions_environment_original_transaction_idx
on internal.storekit_transactions (environment, original_transaction_id);

create index storekit_transactions_product_user_idx
on internal.storekit_transactions (product_id, user_id);

create index entitlement_grants_user_status_expires_at_idx
on internal.entitlement_grants (user_id, status, expires_at);

create unique index entitlement_grants_active_user_kind_product_idx
on internal.entitlement_grants (
  user_id,
  grant_kind,
  coalesce(product_id, '00000000-0000-0000-0000-000000000000'::uuid)
)
where status = 'active' and revoked_at is null;

create index entitlement_grants_review_session_idx
on internal.entitlement_grants (source_review_session_id)
where source_review_session_id is not null;

create index review_access_attempts_user_attempted_at_idx
on internal.review_access_attempts (user_id, attempted_at desc);

create index review_access_attempts_code_prefix_attempted_at_idx
on internal.review_access_attempts (code_hash_prefix, attempted_at desc);

create index review_access_sessions_user_redeemed_at_idx
on internal.review_access_sessions (user_id, redeemed_at desc);

create index review_access_sessions_code_redeemed_at_idx
on internal.review_access_sessions (code_id, redeemed_at desc);

create index subscription_products_is_active_kind_idx
on public.subscription_products (is_active, kind);

revoke all on public.subscription_products from public, anon, authenticated;
revoke all on public.user_entitlements from public, anon, authenticated;
revoke all on internal.storekit_payloads from public, anon, authenticated;
revoke all on internal.storekit_transactions from public, anon, authenticated;
revoke all on internal.storekit_notification_events from public, anon, authenticated;
revoke all on internal.entitlement_grants from public, anon, authenticated;
revoke all on internal.review_access_codes from public, anon, authenticated;
revoke all on internal.review_access_attempts from public, anon, authenticated;
revoke all on internal.review_access_sessions from public, anon, authenticated;

grant select (
  id,
  apple_product_id,
  kind,
  billing_period,
  is_active,
  created_at,
  updated_at
) on public.subscription_products to authenticated;

grant all privileges on public.subscription_products to service_role;
grant select on public.user_entitlements to service_role;
grant all privileges on internal.storekit_payloads to service_role;
grant all privileges on internal.storekit_transactions to service_role;
grant all privileges on internal.storekit_notification_events to service_role;
grant all privileges on internal.entitlement_grants to service_role;
grant all privileges on internal.review_access_codes to service_role;
grant all privileges on internal.review_access_attempts to service_role;
grant all privileges on internal.review_access_sessions to service_role;

grant usage on schema internal to authenticated;

revoke all on function internal.resolve_user_entitlement(uuid) from public, anon, authenticated;
grant execute on function internal.resolve_user_entitlement(uuid) to authenticated, service_role;

revoke all on function internal.user_has_direct_entitlement(uuid) from public, anon, authenticated;
grant execute on function internal.user_has_direct_entitlement(uuid) to authenticated, service_role;

revoke all on function internal.is_active_entitled_couple_member(uuid) from public, anon, authenticated;
grant execute on function internal.is_active_entitled_couple_member(uuid) to authenticated, service_role;

revoke all on function internal.can_access_couple_content(uuid) from public, anon, authenticated;
grant execute on function internal.can_access_couple_content(uuid) to authenticated, service_role;

revoke all on function public.get_my_entitlement() from public, anon;
grant execute on function public.get_my_entitlement() to authenticated, service_role;

revoke all on function internal.resolve_current_couple_entitlement() from public, anon, authenticated;
grant execute on function internal.resolve_current_couple_entitlement() to authenticated, service_role;

revoke all on function public.get_my_couple_entitlement() from public, anon;
grant execute on function public.get_my_couple_entitlement() to authenticated, service_role;

revoke all on function internal.complete_review_access_session(uuid) from public, anon, authenticated;
grant execute on function internal.complete_review_access_session(uuid) to authenticated, service_role;

revoke all on function public.complete_review_access_session(uuid) from public, anon;
grant execute on function public.complete_review_access_session(uuid) to authenticated, service_role;
