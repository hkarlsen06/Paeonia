-- Keep local invite caches honest and rotate visible invite codes atomically.
-- The app should never have to revoke a still-visible invite before it knows a
-- replacement exists.

create or replace function internal.validate_my_pairing_invite(
  p_invite_id uuid,
  p_invite_code text
)
returns table (
  invite_id uuid,
  status text,
  expires_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid := auth.uid();
  invite_row public.pairing_invites%rowtype;
  invite_code_hash bytea;
begin
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_invite_id is null or p_invite_code is null or btrim(p_invite_code) = '' then
    return query
    select
      null::uuid,
      'not_found'::text,
      null::timestamptz;
    return;
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);

  select invite.*
  into invite_row
  from public.pairing_invites invite
  join internal.pairing_invite_secrets secret
    on secret.invite_id = invite.id
  where invite.id = p_invite_id
    and invite.created_by_user_id = current_user_id
    and secret.code_hash = invite_code_hash
  for update of invite;

  if not found then
    return query
    select
      null::uuid,
      'not_found'::text,
      null::timestamptz;
    return;
  end if;

  if invite_row.status = 'pending' and invite_row.expires_at <= now() then
    update public.pairing_invites invite
    set
      status = 'expired',
      updated_at = now()
    where invite.id = invite_row.id
    returning invite.* into invite_row;
  end if;

  return query
  select
    invite_row.id,
    invite_row.status,
    invite_row.expires_at;
end;
$$;

create or replace function internal.rotate_pairing_invite(
  p_current_invite_id uuid,
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
  current_user_id uuid := auth.uid();
  current_invite_row public.pairing_invites%rowtype;
  invite_code_hash bytea;
  new_invite_id uuid;
  request_hash bytea;
  replayed_response jsonb;
begin
  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  if p_current_invite_id is null then
    raise exception 'current invite id is required'
      using errcode = '23514';
  end if;

  invite_code_hash = internal.hash_pairing_invite_code(p_invite_code);
  request_hash = extensions.digest(
    pg_catalog.concat_ws(
      '|',
      'rotate_pairing_invite',
      p_current_invite_id::text,
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
    'rotate_pairing_invite',
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

  select invite.*
  into current_invite_row
  from public.pairing_invites invite
  where invite.id = p_current_invite_id
    and invite.created_by_user_id = current_user_id
  for update of invite;

  if not found then
    raise exception 'current invite is not available'
      using errcode = '22023';
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
  returning id into new_invite_id;

  insert into internal.pairing_invite_secrets (invite_id, code_hash)
  values (new_invite_id, invite_code_hash);

  update public.pairing_invites invite
  set
    status = 'revoked',
    revoked_at = coalesce(invite.revoked_at, now()),
    updated_at = now()
  where invite.id = current_invite_row.id
    and invite.status = 'pending';

  perform internal.complete_client_operation(
    p_client_operation_id,
    jsonb_build_object('invite_id', new_invite_id)
  );

  return new_invite_id;
end;
$$;

create or replace function public.validate_my_pairing_invite(
  p_invite_id uuid,
  p_invite_code text
)
returns table (
  invite_id uuid,
  status text,
  expires_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.validate_my_pairing_invite(p_invite_id, p_invite_code);
$$;

create or replace function public.rotate_pairing_invite(
  p_current_invite_id uuid,
  p_invite_code text,
  p_client_operation_id uuid,
  p_client_id uuid,
  p_client_sequence bigint,
  p_local_created_at timestamptz,
  p_expires_at timestamptz default now() + interval '7 days'
)
returns uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select internal.rotate_pairing_invite(
    p_current_invite_id,
    p_invite_code,
    p_client_operation_id,
    p_client_id,
    p_client_sequence,
    p_local_created_at,
    p_expires_at
  );
$$;

revoke all on function internal.validate_my_pairing_invite(uuid, text) from public, anon, authenticated;
grant execute on function internal.validate_my_pairing_invite(uuid, text) to service_role;

revoke all on function internal.rotate_pairing_invite(uuid, text, uuid, uuid, bigint, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function internal.rotate_pairing_invite(uuid, text, uuid, uuid, bigint, timestamptz, timestamptz) to service_role;

revoke all on function public.validate_my_pairing_invite(uuid, text) from public, anon;
grant execute on function public.validate_my_pairing_invite(uuid, text) to authenticated, service_role;

revoke all on function public.rotate_pairing_invite(uuid, text, uuid, uuid, bigint, timestamptz, timestamptz) from public, anon;
grant execute on function public.rotate_pairing_invite(uuid, text, uuid, uuid, bigint, timestamptz, timestamptz) to authenticated, service_role;
