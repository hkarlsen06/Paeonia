create unique index privacy_requests_active_deletion_user_idx
on public.privacy_requests (user_id)
where request_kind = 'deletion'
  and status in ('submitted', 'verifying', 'processing');

create or replace function internal.request_account_deletion()
returns table (
  id uuid,
  status text,
  requested_at timestamptz
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  current_user_id uuid;
  request_row public.privacy_requests%rowtype;
  created_request boolean := false;
begin
  current_user_id = auth.uid();

  if current_user_id is null then
    raise exception 'authenticated user required'
      using errcode = '42501';
  end if;

  select request.*
  into request_row
  from public.privacy_requests request
  where request.user_id = current_user_id
    and request.request_kind = 'deletion'
    and request.status in ('submitted', 'verifying', 'processing')
  order by request.requested_at desc, request.id
  limit 1
  for update;

  if request_row.id is null then
    insert into public.privacy_requests (
      user_id,
      request_kind
    ) values (
      current_user_id,
      'deletion'
    )
    on conflict (user_id)
      where request_kind = 'deletion'
        and status in ('submitted', 'verifying', 'processing')
    do nothing
    returning *
    into request_row;

    created_request = request_row.id is not null;
  end if;

  if request_row.id is null then
    select request.*
    into request_row
    from public.privacy_requests request
    where request.user_id = current_user_id
      and request.request_kind = 'deletion'
      and request.status in ('submitted', 'verifying', 'processing')
    order by request.requested_at desc, request.id
    limit 1;
  end if;

  if created_request then
    insert into internal.privacy_request_events (
      request_id,
      actor_user_id,
      event_kind,
      metadata
    ) values (
      request_row.id,
      current_user_id,
      'deletion_requested',
      '{"source":"ios_app"}'::jsonb
    );
  end if;

  return query
  select
    request_row.id,
    request_row.status,
    request_row.requested_at;
end;
$$;

create or replace function public.request_account_deletion()
returns table (
  id uuid,
  status text,
  requested_at timestamptz
)
language sql
security definer
set search_path = pg_catalog
as $$
  select *
  from internal.request_account_deletion();
$$;

revoke all on function internal.request_account_deletion() from public, anon, authenticated;
grant execute on function internal.request_account_deletion() to service_role;

revoke all on function public.request_account_deletion() from public, anon;
grant execute on function public.request_account_deletion() to authenticated, service_role;
