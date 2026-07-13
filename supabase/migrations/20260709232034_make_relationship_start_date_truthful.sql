-- A couple's real anniversary is not known at pairing time. Keep it absent until
-- either partner sets it from the milestone card instead of inventing the day the
-- invite was accepted.
alter table public.couples
alter column started_on drop not null;

-- Relationship metadata changes are delivered through the existing per-user
-- relationship sync stream. This event carries no private date value; clients
-- refresh the access snapshot they are already allowed to read.
alter table public.relationship_sync_events
drop constraint if exists relationship_sync_events_event_kind_check;

alter table public.relationship_sync_events
add constraint relationship_sync_events_event_kind_check
check (
  event_kind in (
    'relationship_started',
    'relationship_updated',
    'relationship_ended',
    'relationship_deleted',
    'entitlement_lost',
    'entitlement_restored',
    'content_hidden',
    'content_cleanup_scheduled',
    'content_purged',
    'account_deletion_started',
    'account_deleted'
  )
);

-- Preserve the normal invite flow while allowing the relationship date to be
-- omitted. The public dispatch wrapper below still preserves App Review demo-code
-- redemption before reaching this implementation.
create or replace function internal.accept_pairing_invite(
  p_invite_code text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_started_on date default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  invite_row public.pairing_invites%rowtype;
  resolved_pair_id uuid;
  created_couple_id uuid;
  invite_code_hash bytea;
  request_hash bytea;
  replayed_response jsonb;
  code_prefix text;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);
  code_prefix = left(pg_catalog.encode(invite_code_hash, 'hex'), 12);

  perform internal.assert_pairing_invite_attempt_allowed(current_user_id, code_prefix);

  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'accept_pairing_invite',
      pg_catalog.encode(invite_code_hash, 'hex'),
      coalesce(p_started_on::text, 'unset')
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'accept_pairing_invite',
    'pairing_invites',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'couple_id')::uuid;
  end if;

  select invite.*
  into invite_row
  from internal.pairing_invite_secrets secret
  join public.pairing_invites invite
    on invite.id = secret.invite_id
  where secret.code_hash = invite_code_hash
  for update of invite;

  if not found then
    insert into internal.pairing_invite_attempts (code_hash_prefix, user_id, success, failure_reason)
    values (code_prefix, current_user_id, false, 'not_found');

    raise exception 'pairing invite is not available'
      using errcode = '22023';
  end if;

  if invite_row.created_by_user_id = current_user_id then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'self_accept'
    );

    raise exception 'users cannot accept their own invite'
      using errcode = '23514';
  end if;

  if invite_row.status <> 'pending' then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'not_pending'
    );

    raise exception 'pairing invite is not pending'
      using errcode = '22023';
  end if;

  if invite_row.expires_at <= now() then
    update public.pairing_invites
    set status = 'expired'
    where id = invite_row.id;

    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'expired'
    );

    raise exception 'pairing invite is expired'
      using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id in (current_user_id, invite_row.created_by_user_id)
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'active_couple'
    );

    raise exception 'one of the users already has an active couple'
      using errcode = '23505';
  end if;

  resolved_pair_id = internal.get_or_create_relationship_pair(
    invite_row.created_by_user_id,
    current_user_id
  );

  if (select internal.has_active_relationship_block(resolved_pair_id)) then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      invite_row.id,
      current_user_id,
      false,
      'active_block'
    );

    raise exception 'pairing is blocked for this pair'
      using errcode = '42501';
  end if;

  insert into public.couples (pair_id, started_on, created_by_user_id)
  values (resolved_pair_id, p_started_on, invite_row.created_by_user_id)
  returning id into created_couple_id;

  insert into public.couple_members (couple_id, user_id, role)
  values
    (created_couple_id, invite_row.created_by_user_id, 'creator'),
    (created_couple_id, current_user_id, 'partner');

  update public.pairing_invites
  set
    status = 'accepted',
    accepted_by_user_id = current_user_id,
    accepted_at = now(),
    couple_id = created_couple_id
  where id = invite_row.id;

  perform internal.create_relationship_sync_event(
    invite_row.created_by_user_id,
    created_couple_id,
    current_user_id,
    'relationship_started',
    'pairing_invite_accepted',
    'active',
    'active',
    null,
    null,
    '{"relationship":"refresh","entitlement":"refresh"}'::jsonb
  );

  perform internal.create_relationship_sync_event(
    current_user_id,
    created_couple_id,
    current_user_id,
    'relationship_started',
    'pairing_invite_accepted',
    'active',
    'active',
    null,
    null,
    '{"relationship":"refresh","entitlement":"refresh"}'::jsonb
  );

  insert into internal.pairing_invite_attempts (
    code_hash_prefix,
    matched_invite_id,
    user_id,
    success
  ) values (
    code_prefix,
    invite_row.id,
    current_user_id,
    true
  );

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('couple_id', created_couple_id)
  );

  return created_couple_id;
end;
$$;

create or replace function internal.user_local_date(
  p_user_id uuid,
  p_observed_at timestamptz
)
returns date
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select (
    p_observed_at at time zone coalesce(
      (
        select timezone_name.name
        from public.profiles profile
        join pg_catalog.pg_timezone_names timezone_name
          on timezone_name.name = profile.time_zone_id
        where profile.user_id = p_user_id
      ),
      'UTC'
    )
  )::date;
$$;

-- Either active member of an entitled couple may set or correct the date. The
-- client-operation envelope makes queued retries idempotent.
create or replace function internal.set_couple_started_on(
  p_started_on date,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns date
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  resolved_couple_id uuid;
  replayed_response jsonb;
  request_hash bytea;
  member_row record;
  operation_scope text;
  current_started_on date;
begin
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_started_on is null
    or p_started_on > internal.user_local_date(current_user_id, now()) then
    raise exception 'relationship start date must be today or earlier'
      using errcode = '23514';
  end if;

  resolved_couple_id = internal.get_current_entitled_couple_id();
  operation_scope = 'couple:' || resolved_couple_id::text || ':started_on';
  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'set_couple_started_on',
      resolved_couple_id::text,
      p_started_on::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'set_couple_started_on',
    operation_scope,
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'started_on')::date;
  end if;

  -- A delayed retry from this client must not overwrite a newer edit that the
  -- same client already completed. Cross-device/partner edits intentionally keep
  -- ordinary server-arrival ordering because device clocks are not authoritative.
  if exists (
    select 1
    from internal.client_operations later_operation
    where later_operation.user_id = current_user_id
      and later_operation.client_id = p_client_id
      and later_operation.client_sequence > p_client_sequence
      and later_operation.operation_kind = 'set_couple_started_on'
      and later_operation.idempotency_scope = operation_scope
      and later_operation.status = 'succeeded'
  ) then
    select couple.started_on
    into current_started_on
    from public.couples couple
    where couple.id = resolved_couple_id;

    perform internal.complete_client_operation(
      p_client_operation_id,
      jsonb_build_object(
        'couple_id', resolved_couple_id,
        'started_on', current_started_on,
        'superseded', true
      )
    );

    return current_started_on;
  end if;

  update public.couples
  set started_on = p_started_on
  where id = resolved_couple_id
    and status = 'active';

  if not found then
    raise exception 'active relationship not found'
      using errcode = 'P0002';
  end if;

  for member_row in
    select member.user_id, member.status
    from public.couple_members member
    where member.couple_id = resolved_couple_id
      and member.status = 'active'
  loop
    perform internal.create_relationship_sync_event(
      member_row.user_id,
      resolved_couple_id,
      current_user_id,
      'relationship_updated',
      'relationship_start_date_changed',
      'active',
      member_row.status,
      null,
      null,
      '{"relationship":"refresh"}'::jsonb
    );
  end loop;

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object(
      'couple_id', resolved_couple_id,
      'started_on', p_started_on
    )
  );

  return p_started_on;
end;
$$;

-- Keep the review-code dispatch introduced by
-- 20260701120000_review_access_demo_redemption.sql. Review redemption continues
-- to seed its deliberate demonstration date; ordinary invites leave the date
-- unset until the couple chooses it.
create or replace function public.accept_pairing_invite(
  p_invite_code text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_started_on date default null
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
    raise exception 'authenticated user required'
      using errcode = '42501';
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

create or replace function public.set_couple_started_on(
  p_started_on date,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns date
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.set_couple_started_on(
    p_started_on,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

revoke all on function internal.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date)
from public, anon, authenticated;
grant execute on function internal.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date)
to service_role;

revoke all on function internal.set_couple_started_on(date, uuid, uuid, bigint, timestamptz)
from public, anon, authenticated;
grant execute on function internal.set_couple_started_on(date, uuid, uuid, bigint, timestamptz)
to service_role;

revoke all on function internal.user_local_date(uuid, timestamptz)
from public, anon, authenticated;
grant execute on function internal.user_local_date(uuid, timestamptz)
to service_role;

revoke all on function public.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date)
from public, anon;
grant execute on function public.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date)
to authenticated, service_role;

revoke all on function public.set_couple_started_on(date, uuid, uuid, bigint, timestamptz)
from public, anon;
grant execute on function public.set_couple_started_on(date, uuid, uuid, bigint, timestamptz)
to authenticated, service_role;

notify pgrst, 'reload schema';
