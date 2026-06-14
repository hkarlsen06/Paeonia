create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create schema if not exists internal;

revoke all on schema internal from public, anon, authenticated;
grant usage on schema internal to service_role;

alter default privileges revoke execute on functions from public, anon, authenticated;
alter default privileges in schema internal revoke all on tables from public, anon, authenticated;
alter default privileges in schema internal revoke all on sequences from public, anon, authenticated;
alter default privileges in schema internal revoke all on functions from public, anon, authenticated;
alter default privileges in schema internal revoke execute on functions from public, anon, authenticated;
alter default privileges in schema internal grant all on tables to service_role;
alter default privileges in schema internal grant all on sequences to service_role;
alter default privileges in schema internal grant execute on functions to service_role;

create or replace function internal.set_updated_at()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create or replace function internal.bump_revision()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  new.revision = old.revision + 1;
  return new;
end;
$$;

create or replace function internal.touch_updated_at_and_revision()
returns trigger
language plpgsql
security invoker
set search_path = pg_catalog
as $$
begin
  new.updated_at = now();
  new.revision = old.revision + 1;
  return new;
end;
$$;

create table internal.client_operations (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  client_operation_id uuid not null,
  client_id uuid not null,
  client_sequence bigint not null,
  local_created_at timestamptz not null,
  operation_kind text not null,
  idempotency_scope text not null,
  request_hash bytea not null,
  response_hash bytea,
  stored_response jsonb,
  status text not null default 'started',
  locked_until timestamptz,
  attempt_count integer not null default 1,
  last_attempt_at timestamptz not null default now(),
  completed_at timestamptz,
  failed_at timestamptz,
  failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint client_operations_user_operation_unique
    unique (user_id, client_operation_id),
  constraint client_operations_client_sequence_check
    check (client_sequence > 0),
  constraint client_operations_operation_kind_check
    check (length(operation_kind) between 1 and 120),
  constraint client_operations_idempotency_scope_check
    check (length(idempotency_scope) between 1 and 160),
  constraint client_operations_request_hash_check
    check (octet_length(request_hash) = 32),
  constraint client_operations_response_hash_check
    check (response_hash is null or octet_length(response_hash) = 32),
  constraint client_operations_status_check
    check (status in ('started', 'succeeded', 'failed_retryable', 'failed_terminal')),
  constraint client_operations_attempt_count_check
    check (attempt_count > 0),
  constraint client_operations_success_response_check
    check (
      status <> 'succeeded'
      or (completed_at is not null and stored_response is not null and response_hash is not null)
    ),
  constraint client_operations_failure_timestamp_check
    check (
      status not in ('failed_retryable', 'failed_terminal')
      or (failed_at is not null and failure_code is not null)
    ),
  constraint client_operations_completed_status_check
    check (completed_at is null or status = 'succeeded'),
  constraint client_operations_failed_status_check
    check (failed_at is null or status in ('failed_retryable', 'failed_terminal')),
  constraint client_operations_locked_status_check
    check (locked_until is null or status = 'started')
);

create trigger set_client_operations_updated_at
before update on internal.client_operations
for each row
execute function internal.set_updated_at();

alter table internal.client_operations enable row level security;

create index client_operations_user_scope_created_at_idx
on internal.client_operations (user_id, idempotency_scope, created_at desc);

create index client_operations_user_created_at_idx
on internal.client_operations (user_id, created_at desc);

create index client_operations_started_locked_until_idx
on internal.client_operations (status, locked_until)
where status = 'started' and locked_until is not null;

create index client_operations_stale_cleanup_idx
on internal.client_operations (status, created_at)
where status in ('started', 'failed_retryable');

revoke all on all tables in schema internal from public, anon, authenticated;
revoke all on all sequences in schema internal from public, anon, authenticated;
revoke all on all functions in schema internal from public, anon, authenticated;
grant all privileges on all tables in schema internal to service_role;
grant all privileges on all sequences in schema internal to service_role;
grant execute on all functions in schema internal to service_role;
