-- Silent push for widget drawings:
--   1) When a revision is saved, enqueue a background ('content-available') push
--      to the *other* couple member so their app wakes and syncs the widget.
--   2) Service-role drain RPCs the edge function uses to claim pending
--      notifications (with the raw device token) and record the send result.
--      The outbox lives in `internal`, which PostgREST does not expose, so the
--      drainer goes through these `public` security-definer wrappers.

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
    -- A save must never fail because of a notification problem.
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

-- Atomically claims a batch of sendable notifications (skipping rows another
-- worker already holds) and returns the raw push token for each.
create or replace function public.claim_notification_batch(p_limit integer default 50)
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
  return query
  with claimed as (
    select outbox.id, outbox.target_device_id
    from internal.notification_outbox outbox
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= now()
      and outbox.attempt_count < 5
      -- This drainer only delivers silent pushes; alert kinds need their own path.
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

-- Records the outcome of a send attempt. Failures only become terminal once the
-- attempt budget is exhausted, so transient errors are retried by later drains.
create or replace function public.mark_notification_result(
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
    set last_error = left(coalesce(p_error, ''), 2000),
        failed_at = case when attempt_count >= 5 then now() else null end
    where id = p_outbox_id
      and sent_at is null
      and failed_at is null;
  end if;
end;
$$;

-- 3) Automatic delivery: drain the outbox to APNs as soon as it's enqueued -----
-- pg_net queues the HTTP call and sends it after this transaction commits, so the
-- edge function always sees the committed row. The drain secret is read from
-- Vault (create it with: select vault.create_secret('<value>', 'widget_drain_secret'));
-- until it exists the call is skipped, so no unauthenticated POST is made.
-- Missed/failed sends still reconcile via on-open sync and the next save's drain.

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
      url := 'https://pbquwluigzrkpjufayst.supabase.co/functions/v1/send-widget-push',
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

revoke all on function internal.invoke_widget_push_drain() from public, anon, authenticated;
grant execute on function internal.invoke_widget_push_drain() to service_role;

revoke all on function public.claim_notification_batch(integer) from public, anon, authenticated;
grant execute on function public.claim_notification_batch(integer) to service_role;

revoke all on function public.mark_notification_result(uuid, boolean, text, text) from public, anon, authenticated;
grant execute on function public.mark_notification_result(uuid, boolean, text, text) to service_role;
