-- Streak restore: the consumable product, a purchase ledger, and the RPCs that
-- verify a purchase and actually restore the couple's streak.
--
-- Depends on 20260628115131_capture_streak_break_for_restore.sql, which adds the
-- restorable snapshot columns to public.streak_states and
-- internal.get_entitled_couple_id_for_user.

-- 1. Register the consumable in the product table. It is consumable / one-time,
--    so widen the kind and billing-period checks (the table is otherwise
--    subscription-shaped). The existing select policy + grant already expose
--    active products to the app.
alter table public.subscription_products
  drop constraint subscription_products_kind_check;
alter table public.subscription_products
  add constraint subscription_products_kind_check
  check (kind in ('couple_subscription', 'streak_restore'));

alter table public.subscription_products
  drop constraint subscription_products_billing_period_check;
alter table public.subscription_products
  add constraint subscription_products_billing_period_check
  check (billing_period in ('monthly', 'yearly', 'one_time'));

insert into public.subscription_products (apple_product_id, kind, billing_period, is_active)
values ('no.paeonia.streak.restore', 'streak_restore', 'one_time', true)
on conflict (apple_product_id) do update
set
  kind = excluded.kind,
  billing_period = excluded.billing_period,
  is_active = excluded.is_active;

-- 2. Purchase ledger: one row per verified restore purchase. The unique
--    (environment, transaction_id) makes the restore idempotent (a replayed
--    StoreKit finish cannot restore twice) and gives refunds a place to land.
create table internal.streak_restorations (
  id uuid primary key default extensions.gen_random_uuid(),
  couple_id uuid not null references public.couples (id) on delete restrict,
  purchaser_user_id uuid not null references auth.users (id) on delete restrict,
  product_id uuid not null references public.subscription_products (id) on delete restrict,
  environment text not null,
  transaction_id text not null,
  original_transaction_id text,
  restored_count integer not null,
  restorable_through_date date,
  purchased_at timestamptz,
  restored_at timestamptz not null default now(),
  raw_payload_id uuid references internal.storekit_payloads (id) on delete restrict,
  status text not null default 'applied',
  refunded_at timestamptz,
  created_at timestamptz not null default now(),

  constraint streak_restorations_environment_check
    check (environment in ('xcode', 'sandbox', 'production')),
  constraint streak_restorations_transaction_id_check
    check (char_length(btrim(transaction_id)) between 1 and 255),
  constraint streak_restorations_original_transaction_id_check
    check (original_transaction_id is null or char_length(btrim(original_transaction_id)) between 1 and 255),
  constraint streak_restorations_restored_count_check
    check (restored_count > 0),
  constraint streak_restorations_status_check
    check (status in ('applied', 'refunded')),
  constraint streak_restorations_refunded_state_check
    check ((status = 'refunded' and refunded_at is not null) or (status <> 'refunded' and refunded_at is null)),
  constraint streak_restorations_environment_transaction_unique
    unique (environment, transaction_id)
);

create index streak_restorations_couple_restored_at_idx
  on internal.streak_restorations (couple_id, restored_at desc);

create index streak_restorations_purchaser_idx
  on internal.streak_restorations (purchaser_user_id, restored_at desc);

-- 3. Apply a verified restore to the shared streak. Idempotent via the ledger.
--    Validates the offer is still open, then re-anchors the streak so the
--    pre-break count is current as of today (and today's completion still
--    counts on top). Constraint-safe: streak_states_last_qualified_check needs
--    non-null day / couple-day / expiry whenever current_count > 0.
create or replace function internal.apply_streak_restore(
  p_couple_id uuid,
  p_purchaser_user_id uuid,
  p_product_id uuid,
  p_environment text,
  p_transaction_id text,
  p_original_transaction_id text,
  p_purchased_at timestamptz,
  p_raw_payload_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  existing_restoration internal.streak_restorations%rowtype;
  state public.streak_states%rowtype;
  today_couple_day_id uuid;
  today_couple_day public.couple_days%rowtype;
  yesterday_couple_day_id uuid;
  today_completed boolean;
  resolved_count integer;
  resolved_last_date date;
  resolved_last_couple_day_id uuid;
  resolved_expires_at timestamptz;
begin
  -- Replay: a finished-but-unconfirmed purchase returns the prior outcome.
  select *
  into existing_restoration
  from internal.streak_restorations
  where environment = p_environment
    and transaction_id = p_transaction_id;

  if found then
    return jsonb_build_object(
      'ok', true,
      'restoredCount', existing_restoration.restored_count,
      'replayed', true
    );
  end if;

  select *
  into state
  from public.streak_states
  where couple_id = p_couple_id
  for update;

  if not found
    or coalesce(state.restorable_count, 0) <= 0
    or state.restore_deadline is null
    or state.restore_deadline <= now() then
    return jsonb_build_object(
      'ok', false,
      'error', 'No streak is available to restore',
      'status', 409
    );
  end if;

  today_couple_day_id = internal.get_or_create_couple_day_at(p_couple_id, now());

  select *
  into today_couple_day
  from public.couple_days
  where id = today_couple_day_id;

  today_completed = exists (
    select 1
    from public.couple_activity_events
    where couple_id = p_couple_id
      and couple_day_id = today_couple_day_id
      and activity_kind = 'daily_challenge_completed'
  );

  if today_completed then
    -- The reset-to-1 came from a completion today; restore puts today on top.
    resolved_count = state.restorable_count + 1;
    resolved_last_date = today_couple_day.local_date;
    resolved_last_couple_day_id = today_couple_day_id;
  else
    -- Nothing today yet: anchor to yesterday so today's completion extends it.
    resolved_count = state.restorable_count;
    yesterday_couple_day_id = internal.get_or_create_couple_day_at(p_couple_id, now() - interval '1 day');
    resolved_last_couple_day_id = yesterday_couple_day_id;
    select local_date
    into resolved_last_date
    from public.couple_days
    where id = yesterday_couple_day_id;
  end if;

  resolved_expires_at = internal.resolve_streak_expires_at(p_couple_id, now());

  update public.streak_states
  set
    current_count = resolved_count,
    longest_count = greatest(longest_count, resolved_count),
    last_qualified_date = resolved_last_date,
    last_qualified_couple_day_id = resolved_last_couple_day_id,
    expires_at = resolved_expires_at,
    restore_available = false,
    restorable_count = 0,
    restorable_through_date = null,
    restore_deadline = null,
    restored_at = now(),
    last_restore_transaction_id = p_transaction_id
  where couple_id = p_couple_id;

  insert into internal.streak_restorations (
    couple_id,
    purchaser_user_id,
    product_id,
    environment,
    transaction_id,
    original_transaction_id,
    restored_count,
    restorable_through_date,
    purchased_at,
    raw_payload_id,
    status
  ) values (
    p_couple_id,
    p_purchaser_user_id,
    p_product_id,
    p_environment,
    p_transaction_id,
    p_original_transaction_id,
    resolved_count,
    state.restorable_through_date,
    p_purchased_at,
    p_raw_payload_id,
    'applied'
  );

  return jsonb_build_object(
    'ok', true,
    'restoredCount', resolved_count,
    'replayed', false
  );
end;
$$;

-- 4. Record an Apple-verified streak-restore purchase: validate the
--    appAccountToken belongs to the user, resolve the product and couple, store
--    the signed payload, then apply the restore. Mirrors
--    internal.record_verified_storekit_transaction. Called by the edge function
--    as service_role; there is no public wrapper (least privilege).
create or replace function internal.record_verified_streak_restore(
  p_user_id uuid,
  p_app_account_token uuid,
  p_apple_product_id text,
  p_environment text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_purchased_at timestamptz,
  p_signed_payload text,
  p_payload_json jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_user_id uuid;
  resolved_product_id uuid;
  resolved_couple_id uuid;
  payload_id uuid;
begin
  if p_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'Invalid user', 'status', 401);
  end if;

  if p_app_account_token is null then
    return jsonb_build_object('ok', false, 'error', 'Apple transaction is missing appAccountToken', 'status', 403);
  end if;

  select app_token.user_id
  into resolved_user_id
  from internal.app_account_tokens app_token
  where app_token.token = p_app_account_token;

  if resolved_user_id is null then
    return jsonb_build_object('ok', false, 'error', 'Apple appAccountToken is not registered', 'status', 403);
  end if;

  if resolved_user_id is distinct from p_user_id then
    return jsonb_build_object('ok', false, 'error', 'Apple transaction belongs to a different user', 'status', 403);
  end if;

  select product.id
  into resolved_product_id
  from public.subscription_products product
  where product.apple_product_id = p_apple_product_id
    and product.kind = 'streak_restore'
    and product.is_active
  limit 1;

  if resolved_product_id is null then
    return jsonb_build_object('ok', false, 'error', 'Apple product is not active in Paeonia', 'status', 400);
  end if;

  resolved_couple_id = internal.get_entitled_couple_id_for_user(p_user_id);

  if resolved_couple_id is null then
    return jsonb_build_object('ok', false, 'error', 'No entitled couple for this user', 'status', 403);
  end if;

  insert into internal.storekit_payloads (
    payload_kind,
    environment,
    original_transaction_id,
    transaction_id,
    signed_payload,
    payload_json
  ) values (
    'transaction',
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_signed_payload,
    p_payload_json
  )
  returning id into payload_id;

  return internal.apply_streak_restore(
    resolved_couple_id,
    p_user_id,
    resolved_product_id,
    p_environment,
    p_transaction_id,
    p_original_transaction_id,
    p_purchased_at,
    payload_id
  );
end;
$$;

-- 5. Refund handling: log it on the ledger; never re-break the streak (forgiving
--    streak rules + never silently remove user content).
create or replace function internal.mark_streak_restore_refunded(
  p_environment text,
  p_transaction_id text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.streak_restorations
  set
    status = 'refunded',
    refunded_at = now()
  where environment = p_environment
    and transaction_id = p_transaction_id
    and status <> 'refunded';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

-- 6. Public wrappers. PostgREST only routes to the public schema, so the edge
--    functions (service_role) call these thin wrappers. They are granted to
--    service_role only — authenticated/anon cannot reach them.
create or replace function public.record_verified_streak_restore(
  p_user_id uuid,
  p_app_account_token uuid,
  p_apple_product_id text,
  p_environment text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_purchased_at timestamptz,
  p_signed_payload text,
  p_payload_json jsonb
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.record_verified_streak_restore(
    p_user_id,
    p_app_account_token,
    p_apple_product_id,
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_purchased_at,
    p_signed_payload,
    p_payload_json
  );
$$;

create or replace function public.mark_streak_restore_refunded(
  p_environment text,
  p_transaction_id text
)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.mark_streak_restore_refunded(p_environment, p_transaction_id);
$$;

alter table internal.streak_restorations enable row level security;

revoke all on internal.streak_restorations from public, anon, authenticated;
grant all privileges on internal.streak_restorations to service_role;

revoke all on function internal.apply_streak_restore(uuid, uuid, uuid, text, text, text, timestamptz, uuid) from public, anon, authenticated;
grant execute on function internal.apply_streak_restore(uuid, uuid, uuid, text, text, text, timestamptz, uuid) to service_role;

revoke all on function internal.record_verified_streak_restore(uuid, uuid, text, text, text, text, timestamptz, text, jsonb) from public, anon, authenticated;
grant execute on function internal.record_verified_streak_restore(uuid, uuid, text, text, text, text, timestamptz, text, jsonb) to service_role;

revoke all on function internal.mark_streak_restore_refunded(text, text) from public, anon, authenticated;
grant execute on function internal.mark_streak_restore_refunded(text, text) to service_role;

revoke all on function public.record_verified_streak_restore(uuid, uuid, text, text, text, text, timestamptz, text, jsonb) from public, anon, authenticated;
grant execute on function public.record_verified_streak_restore(uuid, uuid, text, text, text, text, timestamptz, text, jsonb) to service_role;

revoke all on function public.mark_streak_restore_refunded(text, text) from public, anon, authenticated;
grant execute on function public.mark_streak_restore_refunded(text, text) to service_role;
