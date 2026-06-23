create table internal.app_account_tokens (
  user_id uuid primary key references auth.users (id) on delete cascade,
  token uuid not null default extensions.gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint app_account_tokens_token_unique
    unique (token)
);

create trigger set_app_account_tokens_updated_at
before update on internal.app_account_tokens
for each row
execute function internal.set_updated_at();

create or replace function internal.get_or_create_app_account_token(p_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  resolved_token uuid;
begin
  current_user_id = auth.uid();

  if current_user_id is null or p_user_id is distinct from current_user_id then
    raise exception 'not authorized'
      using errcode = '42501';
  end if;

  select app_token.token
  into resolved_token
  from internal.app_account_tokens app_token
  where app_token.user_id = p_user_id;

  if resolved_token is null then
    insert into internal.app_account_tokens (user_id)
    values (p_user_id)
    on conflict (user_id) do update
      set updated_at = now()
    returning token into resolved_token;
  end if;

  return resolved_token;
end;
$$;

create or replace function internal.get_user_id_by_app_account_token(p_token uuid)
returns uuid
language sql
security definer
set search_path = pg_catalog
as $$
  select app_token.user_id
  from internal.app_account_tokens app_token
  where app_token.token = p_token;
$$;

create or replace function public.get_or_create_app_account_token(p_user_id uuid)
returns uuid
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.get_or_create_app_account_token(p_user_id);
$$;

alter table internal.app_account_tokens enable row level security;

revoke all on internal.app_account_tokens from public, anon, authenticated;
grant all privileges on internal.app_account_tokens to service_role;

revoke all on function internal.get_or_create_app_account_token(uuid) from public, anon, authenticated;
grant execute on function internal.get_or_create_app_account_token(uuid) to authenticated, service_role;

revoke all on function internal.get_user_id_by_app_account_token(uuid) from public, anon, authenticated;
grant execute on function internal.get_user_id_by_app_account_token(uuid) to service_role;

revoke all on function public.get_or_create_app_account_token(uuid) from public, anon, service_role;
grant execute on function public.get_or_create_app_account_token(uuid) to authenticated;
