-- Review-access demo redemption.
--
-- Lets App Review reach the full couple experience from a single device using a
-- short review code typed into the normal partner-invite field. The public
-- pairing wrappers recognize a review code (by sha256 hash) and, instead of the
-- normal invite flow, seed a complete demo relationship around the reviewer:
-- a pre-provisioned partner, an active couple, a partner location, an expired
-- partner subscription (so the reviewer lands on the paywall), and a broken
-- streak with a long restore window (so streak-restore is reachable once the
-- reviewer subscribes). The client never distinguishes review codes from real
-- invite codes; all detection lives server-side here.
--
-- Depends on:
--   20260614224602_entitlements_storekit_review_access.sql   (review_access_* tables)
--   20260614220601_relationship_lifecycle_pairing_blocks_sync_events.sql (pairing)
--   20260624232506_cascade_couple_deletion.sql               (couple delete cascade -> teardown)
--   20260630024852_rename_streak_activity_deadline.sql        (streak columns)
--
-- Every public function below is `security definer` with a pinned search_path so
-- it can reach the `internal` schema (authenticated has no USAGE there) and to
-- satisfy the security-surface test. Ops wrappers are granted to service_role
-- only; the mint/revoke scripts call them with the service key.

-- 1. Allow the pre-paired-but-paywalled review scenario on codes and sessions.
alter table internal.review_access_codes
  drop constraint if exists review_access_codes_scenario_check;
alter table internal.review_access_codes
  add constraint review_access_codes_scenario_check
  check (scenario in ('pre_paired_entitled', 'purchase_flow_unentitled', 'pre_paired_paywalled'));

alter table internal.review_access_codes
  drop constraint if exists review_access_codes_prepaired_partner_check;
alter table internal.review_access_codes
  add constraint review_access_codes_prepaired_partner_check
  check (
    scenario not in ('pre_paired_entitled', 'pre_paired_paywalled')
    or seeded_partner_user_id is not null
  );

alter table internal.review_access_sessions
  drop constraint if exists review_access_sessions_scenario_check;
alter table internal.review_access_sessions
  add constraint review_access_sessions_scenario_check
  check (scenario in ('pre_paired_entitled', 'purchase_flow_unentitled', 'pre_paired_paywalled'));

alter table internal.review_access_sessions
  drop constraint if exists review_access_sessions_prepaired_partner_check;
alter table internal.review_access_sessions
  add constraint review_access_sessions_prepaired_partner_check
  check (
    scenario not in ('pre_paired_entitled', 'pre_paired_paywalled')
    or seeded_partner_user_id is not null
  );

-- 2. Registry of the reusable demo partner accounts. The mint script keeps three
--    slots pointing at pre-provisioned auth users; this is the canonical, tightly
--    scoped list that reset iterates so teardown can never touch a real couple.
create table if not exists internal.review_demo_partners (
  slot smallint primary key,
  user_id uuid not null references auth.users (id) on delete restrict,
  display_name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint review_demo_partners_slot_check
    check (slot between 1 and 9),
  constraint review_demo_partners_user_unique
    unique (user_id),
  constraint review_demo_partners_display_name_check
    check (char_length(btrim(display_name)) between 1 and 80)
);

alter table internal.review_demo_partners enable row level security;
revoke all on internal.review_demo_partners from public, anon, authenticated;
grant all privileges on internal.review_demo_partners to service_role;

create or replace function internal.register_review_demo_partner(
  p_slot smallint,
  p_user_id uuid,
  p_display_name text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into internal.review_demo_partners (slot, user_id, display_name)
  values (p_slot, p_user_id, p_display_name)
  on conflict (slot) do update
  set user_id = excluded.user_id,
      display_name = excluded.display_name,
      updated_at = now();

  perform internal.ensure_review_partner(p_user_id, p_display_name);
end;
$$;

create or replace function internal.list_review_demo_partners()
returns table (slot smallint, user_id uuid, display_name text)
language sql
security definer
set search_path = pg_catalog
as $$
  select slot, user_id, display_name
  from internal.review_demo_partners
  order by slot;
$$;

-- 3. Hashing + lookup. Review codes are the same 6-char canonical strings the app
--    normalizes before sending, hashed with plain sha256 (they are high-entropy,
--    single-cycle, and revoked after review). Kept in one helper so mint and
--    dispatch hash identically.
create or replace function internal.hash_review_access_code(p_code text)
returns bytea
language sql
security definer
set search_path = pg_catalog
as $$
  select extensions.digest(p_code, 'sha256');
$$;

create or replace function internal.find_active_review_access_code(p_code text)
returns internal.review_access_codes
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.review_access_codes
  where code_hash = internal.hash_review_access_code(p_code)
    and status = 'active'
    and (expires_at is null or expires_at > now())
  limit 1;
$$;
-- Note: a code that has reached its redemption ceiling still matches here so the
-- pairing wrappers keep dispatching it to internal.redeem_review_access, which
-- honors a prior reviewer's idempotent replay and rejects only genuinely new
-- redemptions. Filtering exhausted codes out here would misroute a replay to the
-- normal invite path (where a 6-char code fails as an unknown invite).

-- 4. Seed the demo relationship around the reviewer. Idempotent per (code,
--    reviewer): re-entering the same code returns the existing couple instead of
--    duplicating. Runs as the definer owner so it can write couple-scoped tables.
create or replace function internal.redeem_review_access(
  p_code_id uuid,
  p_reviewer_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  code_row internal.review_access_codes%rowtype;
  partner_id uuid;
  existing_couple_id uuid;
  resolved_pair_id uuid;
  created_couple_id uuid;
  couple_subscription_product_id uuid;
  demo_started_on date := current_date - 180;
  demo_restorable_count integer := 12;
  code_prefix text;
begin
  if p_reviewer_user_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;

  select *
  into code_row
  from internal.review_access_codes
  where id = p_code_id
  for update;

  -- A revoked, expired, or unknown code is never redeemable -- not even as a
  -- replay. The redemption ceiling is deliberately NOT checked here; it is
  -- enforced further down, after the idempotent-replay lookup, so a reviewer who
  -- already redeemed can still be returned to their couple once the code is fully
  -- consumed (replay does not consume a redemption).
  if not found
    or code_row.status <> 'active'
    or (code_row.expires_at is not null and code_row.expires_at <= now()) then
    raise exception 'review access code is not available' using errcode = '22023';
  end if;

  partner_id := code_row.seeded_partner_user_id;

  if partner_id is null then
    raise exception 'review access code has no seeded partner' using errcode = '23514';
  end if;

  if partner_id = p_reviewer_user_id then
    raise exception 'reviewer cannot be the seeded partner' using errcode = '23514';
  end if;

  -- Replay: reuse this reviewer's still-active couple from a prior redemption.
  -- Runs before the redemption-ceiling check below so an already-paired reviewer
  -- can always get back into their couple, even after the code is exhausted.
  select session.couple_id
  into existing_couple_id
  from internal.review_access_sessions session
  join public.couples couple
    on couple.id = session.couple_id and couple.status = 'active'
  join public.couple_members member
    on member.couple_id = couple.id
    and member.user_id = p_reviewer_user_id
    and member.status = 'active'
  where session.code_id = p_code_id
    and session.user_id = p_reviewer_user_id
  order by session.redeemed_at desc
  limit 1;

  if existing_couple_id is not null then
    return existing_couple_id;
  end if;

  -- Only a genuinely new redemption consumes capacity, so enforce the ceiling
  -- here rather than up front. A reviewer's replay (handled above) is never
  -- blocked by an exhausted code.
  if code_row.redemption_count >= code_row.max_redemptions then
    raise exception 'review access code is not available' using errcode = '22023';
  end if;

  -- Neither party may already hold an active couple (unique index enforces this;
  -- mint's reset clears the partner). Fail clearly rather than hit the index.
  if exists (
    select 1 from public.couple_members
    where user_id = p_reviewer_user_id and status = 'active'
  ) then
    raise exception 'reviewer already has an active couple' using errcode = '23505';
  end if;

  if exists (
    select 1 from public.couple_members
    where user_id = partner_id and status = 'active'
  ) then
    raise exception 'seeded partner still has an active couple; run reset before minting'
      using errcode = '23505';
  end if;

  resolved_pair_id := internal.get_or_create_relationship_pair(partner_id, p_reviewer_user_id);

  if internal.has_active_relationship_block(resolved_pair_id) then
    raise exception 'review pair is blocked' using errcode = '42501';
  end if;

  -- The couple. created_by = partner mirrors "the partner invited the reviewer".
  insert into public.couples (pair_id, status, started_on, created_by_user_id)
  values (resolved_pair_id, 'active', demo_started_on, partner_id)
  returning id into created_couple_id;

  insert into public.couple_members (couple_id, user_id, role, status)
  values
    (created_couple_id, partner_id, 'creator', 'active'),
    (created_couple_id, p_reviewer_user_id, 'partner', 'active');

  -- Partner location so the map shows a pin (central Oslo).
  insert into public.latest_partner_locations (
    couple_id, user_id, latitude, longitude, accuracy_m, captured_at,
    source, client_operation_id, client_id, client_sequence
  ) values (
    created_couple_id, partner_id, 59.913900, 10.752300, 25, now(),
    'settings_toggle', extensions.gen_random_uuid(), extensions.gen_random_uuid(), 1
  );

  insert into public.location_sharing_preferences (
    couple_id, user_id, is_enabled, enabled_at, disabled_at, consent_version, source
  ) values (
    created_couple_id, partner_id, true, now(), null, '1', 'settings_toggle'
  );

  -- Broken streak with a long restore window so streak-restore is reachable
  -- during review (well past the normal 24h). current_count = 0 keeps the
  -- last_qualified/next-deadline columns null per streak_states constraints.
  insert into public.streak_states (
    couple_id, current_count, longest_count,
    last_qualified_date, last_qualified_couple_day_id,
    restore_available, next_activity_deadline_at,
    restorable_count, restorable_through_date, restore_deadline
  ) values (
    created_couple_id, 0, demo_restorable_count,
    null, null,
    true, null,
    demo_restorable_count, current_date - 2, now() + interval '30 days'
  );

  -- Optional realism: an expired partner subscription so the paywall reads like a
  -- lapsed subscriber. The paywall itself triggers from the couple having no
  -- active entitlement, so this is skipped safely if no product is configured.
  select id
  into couple_subscription_product_id
  from public.subscription_products
  where kind = 'couple_subscription' and is_active
  order by created_at
  limit 1;

  if couple_subscription_product_id is not null then
    insert into internal.storekit_transactions (
      user_id, product_id, environment,
      original_transaction_id, transaction_id, status,
      purchased_at, expires_at
    ) values (
      partner_id, couple_subscription_product_id, 'sandbox',
      'review-demo-' || created_couple_id::text,
      'review-demo-' || created_couple_id::text,
      'expired',
      now() - interval '60 days', now() - interval '30 days'
    )
    on conflict (environment, transaction_id) do nothing;
  end if;

  -- Mirror real pairing so local-first clients refresh into the paired state.
  perform internal.create_relationship_sync_event(
    partner_id, created_couple_id, p_reviewer_user_id,
    'relationship_started', 'review_access_redeemed',
    'active', 'active', null, null,
    '{"relationship":"refresh","entitlement":"refresh"}'::jsonb
  );
  perform internal.create_relationship_sync_event(
    p_reviewer_user_id, created_couple_id, p_reviewer_user_id,
    'relationship_started', 'review_access_redeemed',
    'active', 'active', null, null,
    '{"relationship":"refresh","entitlement":"refresh"}'::jsonb
  );

  -- Record the session + a success attempt, and consume one redemption.
  code_prefix := left(encode(code_row.code_hash, 'hex'), 12);

  insert into internal.review_access_sessions (
    code_id, user_id, seeded_partner_user_id, couple_id, scenario, auth_verified_at
  ) values (
    p_code_id, p_reviewer_user_id, partner_id, created_couple_id, code_row.scenario, now()
  );

  insert into internal.review_access_attempts (
    user_id, code_hash_prefix, matched_code_id, success
  ) values (
    p_reviewer_user_id, code_prefix, p_code_id, true
  );

  update internal.review_access_codes
  set redemption_count = redemption_count + 1
  where id = p_code_id;

  return created_couple_id;
end;
$$;

-- 5. Teardown for reuse across submissions. Deletes every couple a registered
--    demo partner belongs to; the couple-delete cascade (20260624232506) clears
--    all couple-owned data, including review_access_sessions, streak, and
--    location. Scoped strictly to seeded partners, so it can never touch a real
--    couple. Returns the number of couples removed.
create or replace function internal.reset_review_demo()
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  partner_id uuid;
  removed integer;
  deleted_couples integer := 0;
begin
  for partner_id in
    select user_id
    from internal.review_demo_partners
  loop
    with removed_couples as (
      delete from public.couples
      where id in (
        select couple_id
        from public.couple_members
        where user_id = partner_id
      )
      returning 1
    )
    select count(*) into removed from removed_couples;
    deleted_couples := deleted_couples + removed;

    -- The expired demo subscription is keyed by user, not couple, so it does not
    -- cascade with the couple. Clear it explicitly.
    delete from internal.storekit_transactions where user_id = partner_id;
  end loop;

  return deleted_couples;
end;
$$;

-- 6. Ops helpers used by the mint/revoke scripts (service_role only).
create or replace function internal.ensure_review_partner(
  p_user_id uuid,
  p_display_name text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  insert into public.profiles (
    user_id, display_name, time_zone_id, time_zone_updated_at, onboarding_completed_at
  )
  values (p_user_id, p_display_name, 'Europe/Oslo', now(), now())
  on conflict (user_id) do update
  set
    display_name = excluded.display_name,
    time_zone_id = coalesce(public.profiles.time_zone_id, excluded.time_zone_id),
    time_zone_updated_at = coalesce(public.profiles.time_zone_updated_at, excluded.time_zone_updated_at),
    onboarding_completed_at = coalesce(public.profiles.onboarding_completed_at, excluded.onboarding_completed_at),
    moderation_status = 'visible',
    deleted_at = null;
end;
$$;

create or replace function internal.issue_review_access_code(
  p_code text,
  p_seeded_partner_user_id uuid,
  p_scenario text default 'pre_paired_paywalled',
  p_expires_at timestamptz default now() + interval '30 days',
  -- One reviewer per code: a seeded demo partner can only belong to one active
  -- couple at a time, so a second reviewer must use a different code. Minting
  -- issues one code per demo partner for exactly this reason.
  p_max_redemptions integer default 1
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  new_id uuid;
begin
  insert into internal.review_access_codes (
    code_hash, seeded_partner_user_id, scenario, status, expires_at, max_redemptions
  ) values (
    internal.hash_review_access_code(p_code),
    p_seeded_partner_user_id,
    p_scenario,
    'active',
    p_expires_at,
    p_max_redemptions
  )
  returning id into new_id;

  return new_id;
end;
$$;

create or replace function internal.revoke_review_access_codes()
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  changed_rows integer;
begin
  update internal.review_access_codes
  set status = 'revoked', revoked_at = now()
  where status = 'active';

  get diagnostics changed_rows = row_count;
  return changed_rows;
end;
$$;

-- 7. Dispatch: teach the public pairing wrappers to recognize review codes. The
--    normal invite path (internal.preview/accept) is left untouched and only
--    reached when the code is not a review code.
create or replace function public.preview_pairing_invite(p_invite_code text)
returns table (
  invite_id uuid,
  inviter_user_id uuid,
  inviter_display_name text,
  expires_at timestamptz,
  has_safety_warning boolean
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  review_code internal.review_access_codes%rowtype;
  partner_profile public.profiles%rowtype;
begin
  review_code := internal.find_active_review_access_code(p_invite_code);

  if review_code.id is not null then
    select *
    into partner_profile
    from public.profiles
    where user_id = review_code.seeded_partner_user_id;

    return query
    select
      review_code.id,
      review_code.seeded_partner_user_id,
      case
        when partner_profile.moderation_status = 'visible' then partner_profile.display_name
        else null
      end,
      coalesce(review_code.expires_at, now() + interval '1 day'),
      false;
    return;
  end if;

  return query
  select * from internal.preview_pairing_invite(p_invite_code);
end;
$$;

create or replace function public.accept_pairing_invite(
  p_invite_code text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_started_on date default current_date
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  review_code internal.review_access_codes%rowtype;
begin
  if current_user_id is null then
    raise exception 'authenticated user required' using errcode = '42501';
  end if;

  review_code := internal.find_active_review_access_code(p_invite_code);

  if review_code.id is not null then
    return internal.redeem_review_access(review_code.id, current_user_id);
  end if;

  return internal.accept_pairing_invite(
    p_invite_code,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_started_on
  );
end;
$$;

-- 8. Ops public wrappers (service_role only).
create or replace function public.reset_review_demo()
returns integer
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.reset_review_demo();
$$;

create or replace function public.issue_review_access_code(
  p_code text,
  p_seeded_partner_user_id uuid,
  p_scenario text default 'pre_paired_paywalled',
  p_expires_at timestamptz default now() + interval '30 days',
  -- One reviewer per code: a seeded demo partner can only belong to one active
  -- couple at a time, so a second reviewer must use a different code. Minting
  -- issues one code per demo partner for exactly this reason.
  p_max_redemptions integer default 1
)
returns uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.issue_review_access_code(
    p_code,
    p_seeded_partner_user_id,
    p_scenario,
    p_expires_at,
    p_max_redemptions
  );
$$;

create or replace function public.revoke_review_access_codes()
returns integer
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.revoke_review_access_codes();
$$;

create or replace function public.ensure_review_partner(
  p_user_id uuid,
  p_display_name text
)
returns void
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.ensure_review_partner(p_user_id, p_display_name);
$$;

create or replace function public.register_review_demo_partner(
  p_slot smallint,
  p_user_id uuid,
  p_display_name text
)
returns void
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.register_review_demo_partner(p_slot, p_user_id, p_display_name);
$$;

create or replace function public.list_review_demo_partners()
returns table (slot smallint, user_id uuid, display_name text)
language sql
security definer
set search_path = pg_catalog
as $$
  select * from internal.list_review_demo_partners();
$$;

-- 9. Grants. New internal functions stay service_role-only (authenticated/anon
--    must not gain internal execute -- see security_surface_test). The pairing
--    wrappers keep their existing authenticated grant; the ops wrappers are
--    service_role-only.
revoke all on function internal.hash_review_access_code(text) from public, anon, authenticated;
grant execute on function internal.hash_review_access_code(text) to service_role;

revoke all on function internal.find_active_review_access_code(text) from public, anon, authenticated;
grant execute on function internal.find_active_review_access_code(text) to service_role;

revoke all on function internal.redeem_review_access(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.redeem_review_access(uuid, uuid) to service_role;

revoke all on function internal.reset_review_demo() from public, anon, authenticated;
grant execute on function internal.reset_review_demo() to service_role;

revoke all on function internal.ensure_review_partner(uuid, text) from public, anon, authenticated;
grant execute on function internal.ensure_review_partner(uuid, text) to service_role;

revoke all on function internal.issue_review_access_code(text, uuid, text, timestamptz, integer) from public, anon, authenticated;
grant execute on function internal.issue_review_access_code(text, uuid, text, timestamptz, integer) to service_role;

revoke all on function internal.revoke_review_access_codes() from public, anon, authenticated;
grant execute on function internal.revoke_review_access_codes() to service_role;

revoke all on function internal.register_review_demo_partner(smallint, uuid, text) from public, anon, authenticated;
grant execute on function internal.register_review_demo_partner(smallint, uuid, text) to service_role;

revoke all on function internal.list_review_demo_partners() from public, anon, authenticated;
grant execute on function internal.list_review_demo_partners() to service_role;

revoke all on function public.preview_pairing_invite(text) from public, anon;
grant execute on function public.preview_pairing_invite(text) to authenticated, service_role;

revoke all on function public.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date) from public, anon;
grant execute on function public.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date) to authenticated, service_role;

revoke all on function public.reset_review_demo() from public, anon, authenticated;
grant execute on function public.reset_review_demo() to service_role;

revoke all on function public.issue_review_access_code(text, uuid, text, timestamptz, integer) from public, anon, authenticated;
grant execute on function public.issue_review_access_code(text, uuid, text, timestamptz, integer) to service_role;

revoke all on function public.revoke_review_access_codes() from public, anon, authenticated;
grant execute on function public.revoke_review_access_codes() to service_role;

revoke all on function public.ensure_review_partner(uuid, text) from public, anon, authenticated;
grant execute on function public.ensure_review_partner(uuid, text) to service_role;

revoke all on function public.register_review_demo_partner(smallint, uuid, text) from public, anon, authenticated;
grant execute on function public.register_review_demo_partner(smallint, uuid, text) to service_role;

revoke all on function public.list_review_demo_partners() from public, anon, authenticated;
grant execute on function public.list_review_demo_partners() to service_role;

notify pgrst, 'reload schema';
