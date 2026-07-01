-- Rename the APNs drain surface now that it handles app notifications and
-- WidgetKit pushes, not only widget alerts.

create or replace function internal.invoke_push_notification_drain()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  drain_secret text;
begin
  if current_setting('paeonia.push_notification_drain_queued', true) = '1' then
    return null;
  end if;
  perform set_config('paeonia.push_notification_drain_queued', '1', true);

  select decrypted_secret
  into drain_secret
  from vault.decrypted_secrets
  where name in ('push_notification_drain_secret', 'widget_drain_secret')
  order by case name
    when 'push_notification_drain_secret' then 0
    else 1
  end
  limit 1;

  if drain_secret is null then
    return null;
  end if;

  perform net.http_post(
    url := 'https://api.paeonia.no/functions/v1/send-push-notifications',
    headers := jsonb_build_object(
      'content-type', 'application/json',
      'x-drain-secret', drain_secret
    ),
    body := jsonb_build_object(
      'source', tg_table_schema || '.' || tg_table_name,
      'triggered_at', now()
    )
  );

  return null;
end;
$$;

drop trigger if exists invoke_widget_push_drain on internal.notification_outbox;
drop trigger if exists invoke_push_notification_drain_on_notification_outbox on internal.notification_outbox;
create trigger invoke_push_notification_drain_on_notification_outbox
after insert on internal.notification_outbox
for each statement
execute function internal.invoke_push_notification_drain();

drop trigger if exists invoke_widget_push_drain_on_widget_push_outbox on internal.widget_push_outbox;
drop trigger if exists invoke_push_notification_drain_on_widget_push_outbox on internal.widget_push_outbox;
create trigger invoke_push_notification_drain_on_widget_push_outbox
after insert on internal.widget_push_outbox
for each statement
execute function internal.invoke_push_notification_drain();

drop function if exists internal.invoke_widget_push_drain();

revoke all on function internal.invoke_push_notification_drain() from public, anon, authenticated;
grant execute on function internal.invoke_push_notification_drain() to service_role;
