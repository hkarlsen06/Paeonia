-- Silent push for widget drawings:
-- 1) When a revision is saved, enqueue a background ('content-available') push
--    to the other couple member so the app wakes and syncs the widget.
-- 2) A service-role Edge Function drains the internal notification outbox,
--    claims pending notifications with raw device tokens, and records results.
--
-- Internal security-definer functions hold elevated outbox access. Public RPC
-- wrappers stay security-invoker so PostgREST can expose them to service_role
-- without putting security-definer functions in the exposed schema.

-- 1) Enqueue on revision insert ------------------------------------------------

create or replace function internal.notify_partner_of_widget_revision()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  recipient_user_id uuid;
begin
  select member.user_id
  into recipient_user_id
  from public.widget_canvases canvas
  join public.couple_members member
    on member.couple_id = canvas.couple_id
  where canvas.id = new.canvas_id
    and member.user_id <> new.author_user_id
    and member.status = 'active'
  limit 1;

  if recipient_user_id is not null then
    -- A notification problem must never make saving a drawing fail.
    begin
      perform internal.enqueue_notification_for_user(
        recipient_user_id,
        'widget_updated',
        jsonb_build_object('type', 'widget_updated', 'canvas_id', new.canvas_id::text),
        null,
        'private',
        'background',
        'widget',
        null
      );
    exception when others then
      null;
    end;
  end if;

  return new;
end;
$$;

create trigger notify_partner_of_widget_revision
after insert on public.widget_drawing_revisions
for each row
execute function internal.notify_partner_of_widget_revision();

-- 2) Service-role drain RPCs ---------------------------------------------------

create or replace function internal.fail_exhausted_notification_claims()
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  update internal.notification_outbox
  set failed_at = now(),
      last_error = coalesce(
        nullif(last_error, ''),
        'delivery attempt budget exhausted before a result was recorded'
      )
  where sent_at is null
    and failed_at is null
    and attempt_count >= 5;
end;
$$;

-- Atomically claims a batch of sendable notifications, skipping rows another
-- worker already holds, and returns each raw push token.
create or replace function internal.claim_notification_batch(p_limit integer default 50)
returns table (
  outbox_id uuid,
  push_token text,
  apns_environment text,
  apns_push_type text,
  apns_collapse_id text,
  payload jsonb
)
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.fail_exhausted_notification_claims();

  return query
  with claimed as (
    select outbox.id, outbox.target_device_id
    from internal.notification_outbox outbox
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= now()
      and outbox.attempt_count < 5
      -- This drainer only delivers silent pushes; alert kinds need own path.
      and outbox.apns_push_type = 'background'
    order by outbox.scheduled_for
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 50), 200))
  )
  update internal.notification_outbox outbox
  set attempt_count = outbox.attempt_count + 1,
      last_attempt_at = now()
  from claimed
  join public.user_devices device
    on device.id = claimed.target_device_id
  where outbox.id = claimed.id
  returning
    outbox.id,
    device.push_token,
    outbox.apns_environment,
    outbox.apns_push_type,
    outbox.apns_collapse_id,
    outbox.payload;
end;
$$;

-- Records the result of one send attempt. Failures become terminal once the
-- attempt budget is exhausted; transient errors stay retryable.
create or replace function internal.mark_notification_result(
  p_outbox_id uuid,
  p_success boolean,
  p_provider_message_id text default null,
  p_error text default null
)
returns void
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  if p_success then
    update internal.notification_outbox
    set sent_at = now(),
        provider_message_id = nullif(btrim(coalesce(p_provider_message_id, '')), ''),
        last_error = null
    where id = p_outbox_id
      and sent_at is null
      and failed_at is null;
  else
    update internal.notification_outbox
    set last_error = left(coalesce(nullif(btrim(p_error), ''), 'delivery failed'), 2000),
        failed_at = case when attempt_count >= 5 then now() else null end
    where id = p_outbox_id
      and sent_at is null
      and failed_at is null;
  end if;
end;
$$;

create or replace function public.claim_notification_batch(p_limit integer default 50)
returns table (
  outbox_id uuid,
  push_token text,
  apns_environment text,
  apns_push_type text,
  apns_collapse_id text,
  payload jsonb
)
language sql
security invoker
set search_path = pg_catalog
as $$
  select *
  from internal.claim_notification_batch(p_limit);
$$;

create or replace function public.mark_notification_result(
  p_outbox_id uuid,
  p_success boolean,
  p_provider_message_id text default null,
  p_error text default null
)
returns void
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.mark_notification_result(
    p_outbox_id,
    p_success,
    p_provider_message_id,
    p_error
  );
$$;

-- 3) Automatic delivery: drain outbox to APNs as soon as it's enqueued ---------

-- pg_net queues the HTTP call and sends it after the transaction commits, so the
-- Edge Function always sees committed rows. The drain secret is read from Vault
-- (create it with: select vault.create_secret('<value>', 'widget_drain_secret'));
-- until it exists, the call is skipped and no unauthenticated POST is made.
-- Missed/failed sends still reconcile through on-open sync and scheduled drains.

create extension if not exists pg_net;

create or replace function internal.invoke_widget_push_drain()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  drain_secret text;
begin
  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name = 'widget_drain_secret'
  limit 1;

  if coalesce(drain_secret, '') <> '' then
    perform net.http_post(
      url := 'https://api.paeonia.no/functions/v1/send-widget-push',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-drain-secret', drain_secret
      ),
      body := '{}'::jsonb
    );
  end if;
  return null;
end;
$$;

create trigger invoke_widget_push_drain
after insert on internal.notification_outbox
for each statement
execute function internal.invoke_widget_push_drain();

revoke all on function internal.notify_partner_of_widget_revision() from public, anon, authenticated;
grant execute on function internal.notify_partner_of_widget_revision() to service_role;

revoke all on function internal.fail_exhausted_notification_claims() from public, anon, authenticated;
grant execute on function internal.fail_exhausted_notification_claims() to service_role;

revoke all on function internal.claim_notification_batch(integer) from public, anon, authenticated;
grant execute on function internal.claim_notification_batch(integer) to service_role;

revoke all on function internal.mark_notification_result(uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function internal.mark_notification_result(uuid, boolean, text, text) to service_role;

revoke all on function internal.invoke_widget_push_drain() from public, anon, authenticated;
grant execute on function internal.invoke_widget_push_drain() to service_role;

revoke all on function public.claim_notification_batch(integer) from public, anon, authenticated;
grant execute on function public.claim_notification_batch(integer) to service_role;

revoke all on function public.mark_notification_result(uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function public.mark_notification_result(uuid, boolean, text, text) to service_role;
