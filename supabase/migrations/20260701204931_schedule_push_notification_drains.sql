-- Scheduled notification work:
-- 1) Enqueue check-in reminders near the streak deadline.
-- 2) Wake the unified APNs drain for retryable notification rows whose claim
--    lease has elapsed, even if no new outbox row is inserted afterward.

create extension if not exists pg_cron;

create or replace function internal.has_due_push_notification_work(
  p_now timestamptz default now()
)
returns boolean
language sql
stable
security definer
set search_path = pg_catalog
as $$
  select exists (
    select 1
    from internal.notification_outbox outbox
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= p_now
      and outbox.attempt_count < 5
  )
  or exists (
    select 1
    from internal.widget_push_outbox outbox
    join public.widget_push_devices device
      on device.id = outbox.target_widget_device_id
    where outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.scheduled_for <= p_now
      and outbox.attempt_count < 5
      and device.disabled_at is null
  );
$$;

create or replace function internal.request_push_notification_drain(
  p_source text default 'manual'
)
returns boolean
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  drain_secret text;
begin
  if current_setting('paeonia.push_notification_drain_queued', true) = '1' then
    return true;
  end if;

  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name in ('push_notification_drain_secret', 'widget_drain_secret')
  order by case name
    when 'push_notification_drain_secret' then 0
    else 1
  end
  limit 1;

  if coalesce(drain_secret, '') = '' then
    return false;
  end if;

  perform set_config('paeonia.push_notification_drain_queued', '1', true);

  perform net.http_post(
    url := 'https://api.paeonia.no/functions/v1/send-push-notifications',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-drain-secret', drain_secret
    ),
    body := jsonb_build_object(
      'source', coalesce(nullif(btrim(p_source), ''), 'manual'),
      'triggered_at', now()
    )
  );

  return true;
end;
$$;

create or replace function internal.invoke_push_notification_drain()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
begin
  perform internal.request_push_notification_drain(
    tg_table_schema || '.' || tg_table_name
  );
  return null;
end;
$$;

create or replace function internal.run_scheduled_push_notification_jobs(
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_streak_reminders integer;
  due_work boolean;
  drain_requested boolean := false;
begin
  queued_streak_reminders = internal.enqueue_due_streak_reminders(p_now);
  due_work = internal.has_due_push_notification_work(p_now);

  if due_work then
    drain_requested = internal.request_push_notification_drain(
      'cron.push_notification_drain'
    );
  end if;

  return jsonb_build_object(
    'queued_streak_reminders', queued_streak_reminders,
    'due_work', due_work,
    'drain_requested', drain_requested
  );
end;
$$;

select cron.schedule(
  'paeonia-push-notification-drain',
  '30 seconds',
  $$select internal.run_scheduled_push_notification_jobs();$$
);

revoke all on function internal.has_due_push_notification_work(timestamptz) from public, anon, authenticated;
grant execute on function internal.has_due_push_notification_work(timestamptz) to service_role;

revoke all on function internal.request_push_notification_drain(text) from public, anon, authenticated;
grant execute on function internal.request_push_notification_drain(text) to service_role;

revoke all on function internal.invoke_push_notification_drain() from public, anon, authenticated;
grant execute on function internal.invoke_push_notification_drain() to service_role;

revoke all on function internal.run_scheduled_push_notification_jobs(timestamptz) from public, anon, authenticated;
grant execute on function internal.run_scheduled_push_notification_jobs(timestamptz) to service_role;
