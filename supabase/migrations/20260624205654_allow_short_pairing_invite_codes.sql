create table if not exists internal.app_runtime_secrets (
  secret_name text primary key,
  secret_value text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint app_runtime_secrets_name_check
    check (secret_name ~ '^[a-z0-9_]+$'),
  constraint app_runtime_secrets_value_check
    check (char_length(secret_value) between 32 and 1024)
);

alter table internal.app_runtime_secrets enable row level security;
revoke all on table internal.app_runtime_secrets from public, anon, authenticated;

create or replace function internal.hash_pairing_invite_code(p_invite_code text)
returns bytea
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  invite_code_pepper text;
begin
  if p_invite_code is null or p_invite_code !~ '^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6}$' then
    raise exception 'invalid invite code'
      using errcode = '23514';
  end if;

  invite_code_pepper = nullif(current_setting('app.invite_code_pepper', true), '');

  if invite_code_pepper is null then
    select nullif(secret.secret_value, '')
    into invite_code_pepper
    from internal.app_runtime_secrets secret
    where secret.secret_name = 'invite_code_pepper';
  end if;

  if invite_code_pepper is null then
    raise exception 'invite code pepper is not configured'
      using errcode = '22023';
  end if;

  return extensions.hmac(p_invite_code, invite_code_pepper, 'sha256');
end;
$$;

revoke all on function internal.hash_pairing_invite_code(text) from public, anon, authenticated;
grant execute on function internal.hash_pairing_invite_code(text) to service_role;
