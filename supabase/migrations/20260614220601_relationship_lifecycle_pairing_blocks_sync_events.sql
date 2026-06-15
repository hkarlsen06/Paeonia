create table public.relationship_pairs (
  id uuid primary key default extensions.gen_random_uuid(),
  user_low_id uuid not null,
  user_high_id uuid not null,
  created_at timestamptz not null default now(),

  constraint relationship_pairs_order_check
    check (user_low_id < user_high_id),
  constraint relationship_pairs_distinct_users_check
    check (user_low_id <> user_high_id),
  constraint relationship_pairs_user_pair_unique
    unique (user_low_id, user_high_id)
);

create table public.couples (
  id uuid primary key default extensions.gen_random_uuid(),
  pair_id uuid not null references public.relationship_pairs (id) on delete restrict,
  status text not null default 'active',
  started_on date not null,
  created_by_user_id uuid not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  ended_at timestamptz,
  delete_after timestamptz,

  constraint couples_status_check
    check (status in ('active', 'ended', 'deleted')),
  constraint couples_ended_state_check
    check (
      (status = 'active' and ended_at is null and delete_after is null)
      or (status in ('ended', 'deleted') and ended_at is not null and delete_after is not null)
    )
);

create trigger set_couples_updated_at
before update on public.couples
for each row
execute function internal.set_updated_at();

create table public.couple_members (
  couple_id uuid not null references public.couples (id) on delete restrict,
  user_id uuid not null,
  role text not null default 'partner',
  status text not null default 'active',
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  ended_notice_seen_at timestamptz,
  updated_at timestamptz not null default now(),

  constraint couple_members_primary_key
    primary key (couple_id, user_id),
  constraint couple_members_role_check
    check (role in ('creator', 'partner')),
  constraint couple_members_status_check
    check (status in ('active', 'left', 'ended_notice_pending', 'ended_notice_seen')),
  constraint couple_members_left_at_check
    check (left_at is null or status = 'left'),
  constraint couple_members_notice_seen_check
    check (ended_notice_seen_at is null or status = 'ended_notice_seen')
);

create trigger set_couple_members_updated_at
before update on public.couple_members
for each row
execute function internal.set_updated_at();

create table public.pairing_invites (
  id uuid primary key default extensions.gen_random_uuid(),
  created_by_user_id uuid not null,
  status text not null default 'pending',
  expires_at timestamptz not null,
  accepted_by_user_id uuid,
  accepted_at timestamptz,
  revoked_at timestamptz,
  couple_id uuid references public.couples (id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint pairing_invites_status_check
    check (status in ('pending', 'accepted', 'revoked', 'expired')),
  constraint pairing_invites_expiry_check
    check (expires_at > created_at),
  constraint pairing_invites_not_self_accepted_check
    check (accepted_by_user_id is null or accepted_by_user_id <> created_by_user_id),
  constraint pairing_invites_accepted_state_check
    check (
      (status = 'accepted' and accepted_by_user_id is not null and accepted_at is not null and couple_id is not null)
      or (status <> 'accepted' and accepted_by_user_id is null and accepted_at is null and couple_id is null)
    ),
  constraint pairing_invites_revoked_state_check
    check (
      (status = 'revoked' and revoked_at is not null)
      or (status <> 'revoked' and revoked_at is null)
    )
);

create trigger set_pairing_invites_updated_at
before update on public.pairing_invites
for each row
execute function internal.set_updated_at();

create table internal.pairing_invite_secrets (
  invite_id uuid primary key references public.pairing_invites (id) on delete cascade,
  code_hash bytea not null,
  created_at timestamptz not null default now(),

  constraint pairing_invite_secrets_code_hash_check
    check (octet_length(code_hash) = 32),
  constraint pairing_invite_secrets_code_hash_unique
    unique (code_hash)
);

create table internal.pairing_invite_attempts (
  id uuid primary key default extensions.gen_random_uuid(),
  code_hash_prefix text not null,
  matched_invite_id uuid references public.pairing_invites (id) on delete set null,
  user_id uuid,
  success boolean not null default false,
  failure_reason text,
  ip_hash bytea,
  device_hash bytea,
  app_version text,
  attempted_at timestamptz not null default now(),

  constraint pairing_invite_attempts_code_hash_prefix_check
    check (char_length(code_hash_prefix) between 1 and 32),
  constraint pairing_invite_attempts_failure_reason_check
    check (failure_reason is null or char_length(failure_reason) between 1 and 120),
  constraint pairing_invite_attempts_ip_hash_check
    check (ip_hash is null or octet_length(ip_hash) = 32),
  constraint pairing_invite_attempts_device_hash_check
    check (device_hash is null or octet_length(device_hash) = 32),
  constraint pairing_invite_attempts_app_version_check
    check (app_version is null or char_length(btrim(app_version)) between 1 and 64),
  constraint pairing_invite_attempts_success_failure_check
    check ((success and failure_reason is null) or (not success and failure_reason is not null))
);

create table public.relationship_blocks (
  id uuid primary key default extensions.gen_random_uuid(),
  pair_id uuid not null references public.relationship_pairs (id) on delete restrict,
  blocked_by_user_id uuid not null,
  blocked_user_id uuid not null,
  source_report_id uuid,
  created_at timestamptz not null default now(),
  revoked_at timestamptz,
  revoked_by_user_id uuid,
  revoke_reason text,

  constraint relationship_blocks_distinct_users_check
    check (blocked_by_user_id <> blocked_user_id),
  constraint relationship_blocks_revoke_reason_check
    check (revoke_reason is null or revoke_reason in ('user_unblocked', 'moderation_unblocked', 'admin_correction')),
  constraint relationship_blocks_revoked_state_check
    check (
      (revoked_at is null and revoked_by_user_id is null and revoke_reason is null)
      or (revoked_at is not null and revoked_by_user_id is not null and revoke_reason is not null)
    )
);

create table public.relationship_sync_events (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null,
  couple_id uuid not null references public.couples (id) on delete restrict,
  initiated_by_user_id uuid,
  event_kind text not null,
  reason text,
  occurred_at timestamptz not null default now(),
  relationship_status text not null,
  member_status text not null,
  ended_at timestamptz,
  delete_after timestamptz,
  local_purge_scope jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint relationship_sync_events_event_kind_check
    check (
      event_kind in (
        'relationship_started',
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
    ),
  constraint relationship_sync_events_reason_check
    check (reason is null or char_length(reason) between 1 and 160),
  constraint relationship_sync_events_relationship_status_check
    check (relationship_status in ('active', 'ended', 'deleted')),
  constraint relationship_sync_events_member_status_check
    check (member_status in ('active', 'left', 'ended_notice_pending', 'ended_notice_seen')),
  constraint relationship_sync_events_local_purge_scope_check
    check (
      jsonb_typeof(local_purge_scope) = 'object'
      and octet_length(local_purge_scope::text) <= 4096
    )
);

create trigger set_relationship_sync_events_updated_at
before update on public.relationship_sync_events
for each row
execute function internal.set_updated_at();

create table internal.pair_safety_warning_flags (
  id uuid primary key default extensions.gen_random_uuid(),
  pair_id uuid not null references public.relationship_pairs (id) on delete restrict,
  source_report_id uuid,
  created_at timestamptz not null default now()
);

create or replace function internal.current_user_id()
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select auth.uid();
$$;

create or replace function internal.find_relationship_pair_id(
  p_first_user_id uuid,
  p_second_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  low_user_id uuid;
  high_user_id uuid;
  existing_pair_id uuid;
begin
  if p_first_user_id is null or p_second_user_id is null or p_first_user_id = p_second_user_id then
    return null;
  end if;

  if p_first_user_id < p_second_user_id then
    low_user_id = p_first_user_id;
    high_user_id = p_second_user_id;
  else
    low_user_id = p_second_user_id;
    high_user_id = p_first_user_id;
  end if;

  select id
  into existing_pair_id
  from public.relationship_pairs
  where user_low_id = low_user_id
    and user_high_id = high_user_id;

  return existing_pair_id;
end;
$$;

create or replace function internal.get_or_create_relationship_pair(
  p_first_user_id uuid,
  p_second_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  low_user_id uuid;
  high_user_id uuid;
  existing_pair_id uuid;
begin
  if p_first_user_id is null or p_second_user_id is null or p_first_user_id = p_second_user_id then
    raise exception 'relationship pair requires two distinct users'
      using errcode = '23514';
  end if;

  if p_first_user_id < p_second_user_id then
    low_user_id = p_first_user_id;
    high_user_id = p_second_user_id;
  else
    low_user_id = p_second_user_id;
    high_user_id = p_first_user_id;
  end if;

  insert into public.relationship_pairs (user_low_id, user_high_id)
  values (low_user_id, high_user_id)
  on conflict (user_low_id, user_high_id) do nothing
  returning id into existing_pair_id;

  if existing_pair_id is null then
    select id
    into existing_pair_id
    from public.relationship_pairs
    where user_low_id = low_user_id
      and user_high_id = high_user_id;
  end if;

  return existing_pair_id;
end;
$$;

create or replace function internal.assert_relationship_block_pair_members()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  pair_low_user_id uuid;
  pair_high_user_id uuid;
begin
  select user_low_id, user_high_id
  into pair_low_user_id, pair_high_user_id
  from public.relationship_pairs
  where id = new.pair_id;

  if not found then
    raise exception 'relationship pair not found'
      using errcode = '23503';
  end if;

  if not (
    new.blocked_by_user_id in (pair_low_user_id, pair_high_user_id)
    and new.blocked_user_id in (pair_low_user_id, pair_high_user_id)
    and new.blocked_by_user_id <> new.blocked_user_id
  ) then
    raise exception 'relationship block users must match the pair'
      using errcode = '23514';
  end if;

  return new;
end;
$$;

create trigger assert_relationship_block_pair_members
before insert or update on public.relationship_blocks
for each row
execute function internal.assert_relationship_block_pair_members();

create or replace function internal.is_active_couple_member(p_couple_id uuid)
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
  );
$$;

create or replace function internal.is_couple_pair_member(p_pair_id uuid)
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
    where couple.pair_id = p_pair_id
      and member.user_id = (select auth.uid())
      and member.status in ('active', 'ended_notice_pending', 'ended_notice_seen', 'left')
  );
$$;

create or replace function internal.can_access_couple_content(p_couple_id uuid)
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
  );
$$;

create or replace function internal.has_active_relationship_block(p_pair_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from public.relationship_blocks block
    where block.pair_id = p_pair_id
      and block.revoked_at is null
  );
$$;

create or replace function internal.create_relationship_sync_event(
  p_user_id uuid,
  p_couple_id uuid,
  p_initiated_by_user_id uuid,
  p_event_kind text,
  p_reason text,
  p_relationship_status text,
  p_member_status text,
  p_ended_at timestamptz,
  p_delete_after timestamptz,
  p_local_purge_scope jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  event_id uuid;
begin
  insert into public.relationship_sync_events (
    user_id,
    couple_id,
    initiated_by_user_id,
    event_kind,
    reason,
    relationship_status,
    member_status,
    ended_at,
    delete_after,
    local_purge_scope
  ) values (
    p_user_id,
    p_couple_id,
    p_initiated_by_user_id,
    p_event_kind,
    p_reason,
    p_relationship_status,
    p_member_status,
    p_ended_at,
    p_delete_after,
    coalesce(p_local_purge_scope, '{}'::jsonb)
  )
  returning id into event_id;

  return event_id;
end;
$$;

create or replace function internal.hash_pairing_invite_code(p_invite_code text)
returns bytea
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  invite_code_pepper text;
begin
  if p_invite_code is null or char_length(p_invite_code) not between 32 and 512 then
    raise exception 'invalid invite code'
      using errcode = '23514';
  end if;

  invite_code_pepper = nullif(current_setting('app.invite_code_pepper', true), '');

  if invite_code_pepper is null then
    raise exception 'invite code pepper is not configured'
      using errcode = '22023';
  end if;

  return extensions.hmac(p_invite_code, invite_code_pepper, 'sha256');
end;
$$;

create or replace function internal.assert_pairing_invite_attempt_allowed(
  p_user_id uuid,
  p_code_hash_prefix text
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if exists (
    select 1
    from internal.pairing_invite_attempts attempt
    where attempt.user_id = p_user_id
      and attempt.attempted_at > now() - interval '10 minutes'
    group by attempt.user_id
    having count(*) >= 30
  ) then
    raise exception 'too many invite attempts'
      using errcode = '53300';
  end if;

  if exists (
    select 1
    from internal.pairing_invite_attempts attempt
    where attempt.user_id = p_user_id
      and attempt.code_hash_prefix = p_code_hash_prefix
      and attempt.success = false
      and attempt.attempted_at > now() - interval '10 minutes'
    group by attempt.user_id, attempt.code_hash_prefix
    having count(*) >= 10
  ) then
    raise exception 'too many invite attempts for this code'
      using errcode = '53300';
  end if;
end;
$$;

create or replace function internal.begin_client_operation(
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_operation_kind text,
  p_idempotency_scope text,
  p_request_hash bytea
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  operation_row internal.client_operations%rowtype;
  inserted_rows integer;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_client_operation_id is null or p_client_id is null then
    raise exception 'client operation identifiers are required'
      using errcode = '23514';
  end if;

  insert into internal.client_operations (
    user_id,
    client_operation_id,
    client_id,
    client_sequence,
    local_created_at,
    operation_kind,
    idempotency_scope,
    request_hash
  ) values (
    current_user_id,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_operation_kind,
    p_idempotency_scope,
    p_request_hash
  )
  on conflict (user_id, client_operation_id) do nothing;

  get diagnostics inserted_rows = row_count;

  select *
  into operation_row
  from internal.client_operations
  where user_id = current_user_id
    and client_operation_id = p_client_operation_id
  for update;

  if operation_row.request_hash <> p_request_hash then
    raise exception 'client operation replay hash mismatch'
      using errcode = '23505';
  end if;

  if operation_row.status = 'succeeded' then
    return operation_row.stored_response;
  end if;

  if inserted_rows = 0 then
    raise exception 'client operation is already in progress'
      using errcode = '55P03';
  end if;

  if operation_row.status <> 'started' then
    raise exception 'client operation cannot be replayed'
      using errcode = '23505';
  end if;

  return null;
end;
$$;

create or replace function internal.complete_client_operation(
  p_client_operation_id uuid,
  p_stored_response jsonb
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  update internal.client_operations
  set
    status = 'succeeded',
    completed_at = now(),
    stored_response = p_stored_response,
    response_hash = extensions.digest(coalesce(p_stored_response, '{}'::jsonb)::text, 'sha256')
  where user_id = current_user_id
    and client_operation_id = p_client_operation_id
    and status = 'started';
end;
$$;

create or replace function internal.user_has_direct_entitlement(p_user_id uuid)
returns boolean
language sql
security definer
set search_path = pg_catalog
as $$
  select false;
$$;

create or replace function internal.create_pairing_invite(
  p_invite_code text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_expires_at timestamptz default now() + interval '7 days'
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  invite_code_hash bytea;
  request_hash bytea;
  invite_id uuid;
  replayed_response jsonb;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);
  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'create_pairing_invite',
      pg_catalog.encode(invite_code_hash, 'hex'),
      p_expires_at::text
    ),
    'sha256'
  );

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'create_pairing_invite',
    'pairing_invites',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'invite_id')::uuid;
  end if;

  if p_expires_at <= now() or p_expires_at > now() + interval '30 days' then
    raise exception 'invite expiration is out of range'
      using errcode = '23514';
  end if;

  if not (select internal.user_has_direct_entitlement(current_user_id)) then
    raise exception 'direct entitlement is required to create an invite'
      using errcode = '42501';
  end if;

  if exists (
    select 1
    from public.couple_members member
    join public.couples couple
      on couple.id = member.couple_id
    where member.user_id = current_user_id
      and member.status = 'active'
      and couple.status = 'active'
  ) then
    raise exception 'user already has an active couple'
      using errcode = '23505';
  end if;

  insert into public.pairing_invites (created_by_user_id, expires_at)
  values (current_user_id, p_expires_at)
  returning id into invite_id;

  insert into internal.pairing_invite_secrets (invite_id, code_hash)
  values (invite_id, invite_code_hash);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('invite_id', invite_id)
  );

  return invite_id;
end;
$$;

create or replace function internal.preview_pairing_invite(p_invite_code text)
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
  current_user_id uuid;
  found_invite record;
  resolved_pair_id uuid;
  invite_code_hash bytea;
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

  select invite.id,
    invite.created_by_user_id,
    invite.expires_at,
    profile.display_name,
    profile.moderation_status
  into found_invite
  from internal.pairing_invite_secrets secret
  join public.pairing_invites invite
    on invite.id = secret.invite_id
  left join public.profiles profile
    on profile.user_id = invite.created_by_user_id
  where secret.code_hash = invite_code_hash
    and invite.status = 'pending'
    and invite.expires_at > now();

  if not found then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      current_user_id,
      false,
      'not_found'
    );

    return;
  end if;

  resolved_pair_id = internal.find_relationship_pair_id(current_user_id, found_invite.created_by_user_id);

  if resolved_pair_id is not null and (select internal.has_active_relationship_block(resolved_pair_id)) then
    insert into internal.pairing_invite_attempts (
      code_hash_prefix,
      matched_invite_id,
      user_id,
      success,
      failure_reason
    ) values (
      code_prefix,
      found_invite.id,
      current_user_id,
      false,
      'active_block'
    );

    return;
  end if;

  insert into internal.pairing_invite_attempts (
    code_hash_prefix,
    matched_invite_id,
    user_id,
    success
  ) values (
    code_prefix,
    found_invite.id,
    current_user_id,
    true
  );

  return query
  select
    found_invite.id,
    found_invite.created_by_user_id,
    case
      when found_invite.moderation_status = 'visible' then found_invite.display_name
      else null
    end,
    found_invite.expires_at,
    exists (
      select 1
      from internal.pair_safety_warning_flags warning
      where warning.pair_id = resolved_pair_id
    );
end;
$$;

create or replace function internal.accept_pairing_invite(
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

  if p_started_on is null then
    raise exception 'relationship start date is required'
      using errcode = '23514';
  end if;

  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'accept_pairing_invite',
      pg_catalog.encode(invite_code_hash, 'hex'),
      p_started_on::text
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
    insert into internal.pairing_invite_attempts (code_hash_prefix, matched_invite_id, user_id, success, failure_reason)
    values (code_prefix, invite_row.id, current_user_id, false, 'self_accept');

    raise exception 'users cannot accept their own invite'
      using errcode = '23514';
  end if;

  if invite_row.status <> 'pending' then
    insert into internal.pairing_invite_attempts (code_hash_prefix, matched_invite_id, user_id, success, failure_reason)
    values (code_prefix, invite_row.id, current_user_id, false, 'not_pending');

    raise exception 'pairing invite is not pending'
      using errcode = '22023';
  end if;

  if invite_row.expires_at <= now() then
    update public.pairing_invites
    set status = 'expired'
    where id = invite_row.id;

    insert into internal.pairing_invite_attempts (code_hash_prefix, matched_invite_id, user_id, success, failure_reason)
    values (code_prefix, invite_row.id, current_user_id, false, 'expired');

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
    insert into internal.pairing_invite_attempts (code_hash_prefix, matched_invite_id, user_id, success, failure_reason)
    values (code_prefix, invite_row.id, current_user_id, false, 'active_couple');

    raise exception 'one of the users already has an active couple'
      using errcode = '23505';
  end if;

  resolved_pair_id = internal.get_or_create_relationship_pair(invite_row.created_by_user_id, current_user_id);

  if (select internal.has_active_relationship_block(resolved_pair_id)) then
    insert into internal.pairing_invite_attempts (code_hash_prefix, matched_invite_id, user_id, success, failure_reason)
    values (code_prefix, invite_row.id, current_user_id, false, 'active_block');

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

  insert into internal.pairing_invite_attempts (code_hash_prefix, matched_invite_id, user_id, success)
  values (code_prefix, invite_row.id, current_user_id, true);

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('couple_id', created_couple_id)
  );

  return created_couple_id;
end;
$$;

create or replace function internal.revoke_pairing_invite(p_invite_id uuid)
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

  update public.pairing_invites
  set
    status = 'revoked',
    revoked_at = now()
  where id = p_invite_id
    and created_by_user_id = current_user_id
    and status = 'pending';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.end_relationship_for_pair(
  p_pair_id uuid,
  p_initiated_by_user_id uuid,
  p_reason text
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  couple_row public.couples%rowtype;
  member_row record;
  changed_rows integer;
  cleanup_deadline timestamptz;
begin
  select *
  into couple_row
  from public.couples
  where pair_id = p_pair_id
    and status = 'active'
  order by created_at desc
  limit 1
  for update;

  if not found then
    return false;
  end if;

  cleanup_deadline = now() + interval '30 days';

  update public.couples
  set
    status = 'ended',
    ended_at = now(),
    delete_after = cleanup_deadline
  where id = couple_row.id;

  update public.couple_members
  set
    status = 'left',
    left_at = now()
  where couple_id = couple_row.id
    and user_id = p_initiated_by_user_id
    and status = 'active';

  get diagnostics changed_rows = row_count;

  if changed_rows <> 1 then
    raise exception 'initiating user is not an active member of the relationship'
      using errcode = '42501';
  end if;

  update public.couple_members
  set status = 'ended_notice_pending'
  where couple_id = couple_row.id
    and user_id <> p_initiated_by_user_id
    and status = 'active';

  for member_row in
    select user_id, status
    from public.couple_members
    where couple_id = couple_row.id
  loop
    perform internal.create_relationship_sync_event(
      member_row.user_id,
      couple_row.id,
      p_initiated_by_user_id,
      'relationship_ended',
      p_reason,
      'ended',
      member_row.status,
      now(),
      cleanup_deadline,
      '{"relationship_content":"hide","location":"purge","widget_cache":"purge","pending_uploads":"review"}'::jsonb
    );
  end loop;

  return true;
end;
$$;

create or replace function internal.leave_relationship(
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  active_pair_id uuid;
  request_hash bytea;
  replayed_response jsonb;
  left_relationship boolean;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  request_hash = extensions.digest('leave_relationship', 'sha256');

  replayed_response = internal.begin_client_operation(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    'leave_relationship',
    'relationship_lifecycle',
    request_hash
  );

  if replayed_response is not null then
    return (replayed_response ->> 'left')::boolean;
  end if;

  select couple.pair_id
  into active_pair_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.user_id = current_user_id
    and member.status = 'active'
    and couple.status = 'active'
  order by couple.created_at desc
  limit 1;

  if active_pair_id is null then
    perform internal.complete_client_operation(
      p_client_operation_id,
      jsonb_build_object('left', false)
    );

    return false;
  end if;

  left_relationship = internal.end_relationship_for_pair(active_pair_id, current_user_id, 'user_left');

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('left', left_relationship)
  );

  return left_relationship;
end;
$$;

create or replace function internal.block_relationship(
  p_blocked_user_id uuid,
  p_source_report_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_pair_id uuid;
  relationship_block_id uuid;
  valid_source_report_id uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_blocked_user_id is null or p_blocked_user_id = current_user_id then
    raise exception 'blocked user must be a different user'
      using errcode = '23514';
  end if;

  select couple.pair_id
  into resolved_pair_id
  from public.couple_members self_member
  join public.couple_members blocked_member
    on blocked_member.couple_id = self_member.couple_id
    and blocked_member.user_id = p_blocked_user_id
  join public.couples couple
    on couple.id = self_member.couple_id
  where self_member.user_id = current_user_id
    and (
      couple.status = 'active'
      or (couple.status = 'ended' and couple.delete_after > now())
    )
  order by
    case when couple.status = 'active' then 0 else 1 end,
    couple.created_at desc
  limit 1;

  if resolved_pair_id is null then
    raise exception 'blocked user must be a current or recently ended partner'
      using errcode = '42501';
  end if;

  if p_source_report_id is not null then
    select report.id
    into valid_source_report_id
    from public.content_reports report
    where report.id = p_source_report_id
      and report.reporter_user_id = current_user_id
      and report.reported_user_id = p_blocked_user_id
      and report.pair_id = resolved_pair_id;

    if valid_source_report_id is null then
      raise exception 'source report does not belong to this block'
        using errcode = '42501';
    end if;
  end if;

  insert into public.relationship_blocks (
    pair_id,
    blocked_by_user_id,
    blocked_user_id,
    source_report_id
  ) values (
    resolved_pair_id,
    current_user_id,
    p_blocked_user_id,
    p_source_report_id
  )
  on conflict (pair_id, blocked_by_user_id, blocked_user_id)
    where revoked_at is null
  do update set source_report_id = coalesce(public.relationship_blocks.source_report_id, excluded.source_report_id)
  returning id into relationship_block_id;

  if p_source_report_id is not null then
    insert into internal.pair_safety_warning_flags (pair_id, source_report_id)
    values (resolved_pair_id, p_source_report_id)
    on conflict (pair_id, source_report_id)
      where source_report_id is not null
    do nothing;
  end if;

  perform internal.end_relationship_for_pair(resolved_pair_id, current_user_id, 'blocked');

  return relationship_block_id;
end;
$$;

create or replace function internal.unblock_pair(p_pair_id uuid)
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

  update public.relationship_blocks
  set
    revoked_at = now(),
    revoked_by_user_id = current_user_id,
    revoke_reason = 'user_unblocked'
  where pair_id = p_pair_id
    and blocked_by_user_id = current_user_id
    and revoked_at is null;

  get diagnostics changed_rows = row_count;
  return changed_rows > 0;
end;
$$;

create or replace function internal.mark_relationship_ended_notice_seen(p_couple_id uuid)
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

  update public.couple_members
  set
    status = 'ended_notice_seen',
    ended_notice_seen_at = now()
  where couple_id = p_couple_id
    and user_id = current_user_id
    and status = 'ended_notice_pending';

  get diagnostics changed_rows = row_count;
  return changed_rows = 1;
end;
$$;

create or replace function internal.get_current_relationship_state()
returns table (
  couple_id uuid,
  pair_id uuid,
  relationship_status text,
  member_status text,
  partner_user_id uuid,
  partner_display_name text,
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

create or replace function public.create_pairing_invite(
  p_invite_code text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_expires_at timestamptz default now() + interval '7 days'
)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.create_pairing_invite(
    p_invite_code,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_expires_at
  );
$$;

create or replace function public.preview_pairing_invite(p_invite_code text)
returns table (
  invite_id uuid,
  inviter_user_id uuid,
  inviter_display_name text,
  expires_at timestamptz,
  has_safety_warning boolean
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.preview_pairing_invite(p_invite_code);
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
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.accept_pairing_invite(
    p_invite_code,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_started_on
  );
$$;

create or replace function public.revoke_pairing_invite(p_invite_id uuid)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.revoke_pairing_invite(p_invite_id);
$$;

create or replace function public.leave_relationship(
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz
)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.leave_relationship(
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at
  );
$$;

create or replace function public.block_relationship(
  p_blocked_user_id uuid
)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.block_relationship(p_blocked_user_id, null);
$$;

create or replace function public.unblock_pair(p_pair_id uuid)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.unblock_pair(p_pair_id);
$$;

create or replace function public.mark_relationship_ended_notice_seen(p_couple_id uuid)
returns boolean
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.mark_relationship_ended_notice_seen(p_couple_id);
$$;

create or replace function public.get_current_relationship_state()
returns table (
  couple_id uuid,
  pair_id uuid,
  relationship_status text,
  member_status text,
  partner_user_id uuid,
  partner_display_name text,
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

alter table public.relationship_pairs enable row level security;
alter table public.couples enable row level security;
alter table public.couple_members enable row level security;
alter table public.pairing_invites enable row level security;
alter table internal.pairing_invite_secrets enable row level security;
alter table internal.pairing_invite_attempts enable row level security;
alter table public.relationship_blocks enable row level security;
alter table public.relationship_sync_events enable row level security;
alter table internal.pair_safety_warning_flags enable row level security;

create policy pairing_invites_select_created
on public.pairing_invites
for select
to authenticated
using (created_by_user_id = (select auth.uid()));

create policy relationship_sync_events_select_own
on public.relationship_sync_events
for select
to authenticated
using (user_id = (select auth.uid()));

create index couples_pair_status_idx
on public.couples (pair_id, status);

create index couples_status_delete_after_idx
on public.couples (status, delete_after);

create index couples_id_status_idx
on public.couples (id, status);

create index couple_members_user_status_couple_idx
on public.couple_members (user_id, status, couple_id);

create unique index couple_members_one_active_couple_per_user_idx
on public.couple_members (user_id)
where status = 'active';

create index couple_members_couple_user_status_idx
on public.couple_members (couple_id, user_id, status);

create index pairing_invites_created_by_status_expires_at_idx
on public.pairing_invites (created_by_user_id, status, expires_at);

create index pairing_invite_attempts_code_prefix_attempted_at_idx
on internal.pairing_invite_attempts (code_hash_prefix, attempted_at desc);

create index pairing_invite_attempts_user_attempted_at_idx
on internal.pairing_invite_attempts (user_id, attempted_at desc);

create index relationship_blocks_pair_revoked_at_idx
on public.relationship_blocks (pair_id, revoked_at);

create unique index relationship_blocks_active_pair_direction_idx
on public.relationship_blocks (pair_id, blocked_by_user_id, blocked_user_id)
where revoked_at is null;

create index relationship_sync_events_couple_created_at_id_idx
on public.relationship_sync_events (couple_id, created_at, id);

create index relationship_sync_events_user_created_at_id_idx
on public.relationship_sync_events (user_id, created_at, id);

create index pair_safety_warning_flags_pair_created_at_idx
on internal.pair_safety_warning_flags (pair_id, created_at desc);

create unique index pair_safety_warning_flags_pair_report_unique_idx
on internal.pair_safety_warning_flags (pair_id, source_report_id)
where source_report_id is not null;

revoke all on public.relationship_pairs from public, anon, authenticated;
revoke all on public.couples from public, anon, authenticated;
revoke all on public.couple_members from public, anon, authenticated;
revoke all on public.pairing_invites from public, anon, authenticated;
revoke all on public.relationship_blocks from public, anon, authenticated;
revoke all on public.relationship_sync_events from public, anon, authenticated;
revoke all on internal.pairing_invite_secrets from public, anon, authenticated;
revoke all on internal.pairing_invite_attempts from public, anon, authenticated;
revoke all on internal.pair_safety_warning_flags from public, anon, authenticated;

grant select (
  id,
  created_by_user_id,
  status,
  expires_at,
  accepted_by_user_id,
  accepted_at,
  revoked_at,
  couple_id,
  created_at,
  updated_at
) on public.pairing_invites to authenticated;

grant select (
  id,
  user_id,
  couple_id,
  initiated_by_user_id,
  event_kind,
  reason,
  occurred_at,
  relationship_status,
  member_status,
  ended_at,
  delete_after,
  local_purge_scope,
  created_at,
  updated_at
) on public.relationship_sync_events to authenticated;

grant all privileges on public.relationship_pairs to service_role;
grant all privileges on public.couples to service_role;
grant all privileges on public.couple_members to service_role;
grant all privileges on public.pairing_invites to service_role;
grant all privileges on public.relationship_blocks to service_role;
grant all privileges on public.relationship_sync_events to service_role;
grant all privileges on internal.pairing_invite_secrets to service_role;
grant all privileges on internal.pairing_invite_attempts to service_role;
grant all privileges on internal.pair_safety_warning_flags to service_role;

grant usage on schema internal to authenticated;

revoke all on function internal.current_user_id() from public, anon, authenticated;
grant execute on function internal.current_user_id() to authenticated, service_role;

revoke all on function internal.find_relationship_pair_id(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.find_relationship_pair_id(uuid, uuid) to service_role;

revoke all on function internal.get_or_create_relationship_pair(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.get_or_create_relationship_pair(uuid, uuid) to service_role;

revoke all on function internal.assert_relationship_block_pair_members() from public, anon, authenticated;
grant execute on function internal.assert_relationship_block_pair_members() to service_role;

revoke all on function internal.is_active_couple_member(uuid) from public, anon, authenticated;
grant execute on function internal.is_active_couple_member(uuid) to authenticated, service_role;

revoke all on function internal.is_couple_pair_member(uuid) from public, anon, authenticated;
grant execute on function internal.is_couple_pair_member(uuid) to authenticated, service_role;

revoke all on function internal.can_access_couple_content(uuid) from public, anon, authenticated;
grant execute on function internal.can_access_couple_content(uuid) to authenticated, service_role;

revoke all on function internal.has_active_relationship_block(uuid) from public, anon, authenticated;
grant execute on function internal.has_active_relationship_block(uuid) to service_role;

revoke all on function internal.create_relationship_sync_event(uuid, uuid, uuid, text, text, text, text, timestamptz, timestamptz, jsonb) from public, anon, authenticated;
grant execute on function internal.create_relationship_sync_event(uuid, uuid, uuid, text, text, text, text, timestamptz, timestamptz, jsonb) to service_role;

revoke all on function internal.hash_pairing_invite_code(text) from public, anon, authenticated;
grant execute on function internal.hash_pairing_invite_code(text) to authenticated, service_role;

revoke all on function internal.assert_pairing_invite_attempt_allowed(uuid, text) from public, anon, authenticated;
grant execute on function internal.assert_pairing_invite_attempt_allowed(uuid, text) to authenticated, service_role;

revoke all on function internal.begin_client_operation(uuid, uuid, bigint, timestamptz, text, text, bytea) from public, anon, authenticated;
grant execute on function internal.begin_client_operation(uuid, uuid, bigint, timestamptz, text, text, bytea) to authenticated, service_role;

revoke all on function internal.complete_client_operation(uuid, jsonb) from public, anon, authenticated;
grant execute on function internal.complete_client_operation(uuid, jsonb) to authenticated, service_role;

revoke all on function internal.user_has_direct_entitlement(uuid) from public, anon, authenticated;
grant execute on function internal.user_has_direct_entitlement(uuid) to authenticated, service_role;

revoke all on function internal.create_pairing_invite(text, uuid, uuid, bigint, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function internal.create_pairing_invite(text, uuid, uuid, bigint, timestamptz, timestamptz) to authenticated, service_role;

revoke all on function internal.preview_pairing_invite(text) from public, anon, authenticated;
grant execute on function internal.preview_pairing_invite(text) to authenticated, service_role;

revoke all on function internal.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date) from public, anon, authenticated;
grant execute on function internal.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date) to authenticated, service_role;

revoke all on function internal.revoke_pairing_invite(uuid) from public, anon, authenticated;
grant execute on function internal.revoke_pairing_invite(uuid) to authenticated, service_role;

revoke all on function internal.end_relationship_for_pair(uuid, uuid, text) from public, anon, authenticated;
grant execute on function internal.end_relationship_for_pair(uuid, uuid, text) to service_role;

revoke all on function internal.leave_relationship(uuid, uuid, bigint, timestamptz) from public, anon, authenticated;
grant execute on function internal.leave_relationship(uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function internal.block_relationship(uuid, uuid) from public, anon, authenticated;
grant execute on function internal.block_relationship(uuid, uuid) to authenticated, service_role;

revoke all on function internal.unblock_pair(uuid) from public, anon, authenticated;
grant execute on function internal.unblock_pair(uuid) to authenticated, service_role;

revoke all on function internal.mark_relationship_ended_notice_seen(uuid) from public, anon, authenticated;
grant execute on function internal.mark_relationship_ended_notice_seen(uuid) to authenticated, service_role;

revoke all on function internal.get_current_relationship_state() from public, anon, authenticated;
grant execute on function internal.get_current_relationship_state() to authenticated, service_role;

revoke all on function public.create_pairing_invite(text, uuid, uuid, bigint, timestamptz, timestamptz) from public, anon;
grant execute on function public.create_pairing_invite(text, uuid, uuid, bigint, timestamptz, timestamptz) to authenticated, service_role;

revoke all on function public.preview_pairing_invite(text) from public, anon;
grant execute on function public.preview_pairing_invite(text) to authenticated, service_role;

revoke all on function public.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date) from public, anon;
grant execute on function public.accept_pairing_invite(text, uuid, uuid, bigint, timestamptz, date) to authenticated, service_role;

revoke all on function public.revoke_pairing_invite(uuid) from public, anon;
grant execute on function public.revoke_pairing_invite(uuid) to authenticated, service_role;

revoke all on function public.leave_relationship(uuid, uuid, bigint, timestamptz) from public, anon;
grant execute on function public.leave_relationship(uuid, uuid, bigint, timestamptz) to authenticated, service_role;

revoke all on function public.block_relationship(uuid) from public, anon;
grant execute on function public.block_relationship(uuid) to authenticated, service_role;

revoke all on function public.unblock_pair(uuid) from public, anon;
grant execute on function public.unblock_pair(uuid) to authenticated, service_role;

revoke all on function public.mark_relationship_ended_notice_seen(uuid) from public, anon;
grant execute on function public.mark_relationship_ended_notice_seen(uuid) to authenticated, service_role;

revoke all on function public.get_current_relationship_state() from public, anon;
grant execute on function public.get_current_relationship_state() to authenticated, service_role;
