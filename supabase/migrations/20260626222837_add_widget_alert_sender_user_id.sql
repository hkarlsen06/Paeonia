-- Add `sender_user_id` to the widget-update alert payload so the recipient's
-- notification service extension can upgrade it into a communication
-- notification (partner avatar + name, styled like a Messages alert).
--
-- The original definition shipped in 20260626164532, which is already applied,
-- so this redefines the function rather than editing that migration in place.
create or replace function internal.enqueue_widget_update_alert(
  p_couple_id uuid,
  p_author_user_id uuid,
  p_canvas_id uuid,
  p_revision_id uuid
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  recipient_user_id uuid;
  author_name text;
  queued_rows integer;
begin
  select member.user_id
  into recipient_user_id
  from public.couple_members member
  join public.couples couple
    on couple.id = member.couple_id
  where member.couple_id = p_couple_id
    and member.user_id <> p_author_user_id
    and member.status = 'active'
    and couple.status = 'active'
  limit 1;

  if recipient_user_id is null then
    return 0;
  end if;

  select nullif(btrim(profile.display_name), '')
  into author_name
  from public.profiles profile
  where profile.user_id = p_author_user_id;

  insert into internal.notification_outbox (
    recipient_user_id,
    target_device_id,
    push_token_hash,
    apns_environment,
    kind,
    redaction_level,
    payload,
    dedupe_key,
    apns_push_type,
    apns_collapse_id,
    title,
    body,
    scheduled_for
  )
  select
    device.user_id,
    device.id,
    device.push_token_hash,
    device.apns_environment,
    'widget_updated',
    'private',
    jsonb_build_object(
      'type', 'widget_updated',
      'canvas_id', p_canvas_id::text,
      'route', 'widget',
      -- Identifies the partner for the communication notification (avatar +
      -- name shown like a Messages alert); the recipient renders it.
      'sender_user_id', p_author_user_id::text
    ),
    'widget_updated_alert:' || p_revision_id::text || ':' || device.id::text,
    'alert',
    'widget-alert:' || p_couple_id::text,
    coalesce(author_name, 'Paeonia'),
    internal.widget_updated_notification_body(device.locale),
    now()
  from public.user_devices device
  join public.notification_preferences preference
    on preference.user_id = device.user_id
  where device.user_id = recipient_user_id
    and device.disabled_at is null
    and preference.widget_updates_enabled
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;
