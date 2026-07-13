-- Keep the paywall's "we'll remind you" promise using the same server-side
-- pattern as Tidex: identify the initial Apple introductory period, enqueue one
-- localized push per registered device, and let the existing outbox drain send
-- it two days before the trial expires.

alter table internal.notification_outbox
  drop constraint notification_outbox_kind_check;

alter table internal.notification_outbox
  add constraint notification_outbox_kind_check
  check (
    kind in (
      'streak_reminder',
      'daily_challenge_completed',
      'partner_answered',
      'widget_updated',
      'location_updated',
      'relationship_ended',
      'entitlement_changed',
      'subscription_trial_reminder'
    )
  );

create or replace function internal.notification_alert_title(
  p_kind text,
  p_payload jsonb,
  p_locale text
)
returns text
language plpgsql
stable
security definer
set search_path = pg_catalog
as $$
declare
  language_code text := internal.notification_locale_language(p_locale);
  actor_name text := coalesce(internal.notification_actor_display_name(p_payload), 'Paeonia');
begin
  return case p_kind
    when 'widget_updated' then actor_name
    when 'partner_answered' then case language_code
      when 'nb' then actor_name || ' svarte på samme spørsmål!'
      else actor_name || ' answered the same question!'
    end
    when 'daily_challenge_completed' then case language_code
      when 'nb' then actor_name || ' fullførte dagens spørsmål'
      else actor_name || ' finished today''s questions'
    end
    when 'streak_reminder' then case language_code
      when 'nb' then 'Innsjekken deres utløper snart'
      else 'Your check-in expires soon'
    end
    when 'subscription_trial_reminder' then case language_code
      when 'nb' then 'Prøveperioden avsluttes snart'
      else 'Your free trial ends soon'
    end
    else 'Paeonia'
  end;
end;
$$;

create or replace function internal.notification_alert_body(
  p_kind text,
  p_payload jsonb,
  p_locale text
)
returns text
language plpgsql
stable
set search_path = pg_catalog
as $$
declare
  language_code text := internal.notification_locale_language(p_locale);
  days_left integer := greatest(
    case
      when p_payload ->> 'days_left' ~ '^[0-9]+$'
        then (p_payload ->> 'days_left')::integer
      else 2
    end,
    1
  );
begin
  return case p_kind
    when 'widget_updated' then case language_code
      when 'nb' then 'La til en ny tegning'
      else 'Added a new drawing'
    end
    when 'partner_answered' then case language_code
      when 'nb' then 'Åpne Paeonia for å se hva partneren din skrev.'
      else 'Open Paeonia to reveal what they wrote.'
    end
    when 'daily_challenge_completed' then case language_code
      when 'nb' then 'Åpne Paeonia for å svare og se hva partneren din skrev.'
      else 'Open Paeonia to answer and reveal what they wrote.'
    end
    when 'streak_reminder' then case language_code
      when 'nb' then 'Svar på dagens spørsmål eller legg til en tegning for å holde den i gang.'
      else 'Answer today''s questions or add a drawing to keep it going.'
    end
    when 'subscription_trial_reminder' then case language_code
      when 'nb' then
        days_left::text || case when days_left = 1 then ' dag igjen. ' else ' dager igjen. ' end ||
        'Se over abonnementet ditt i App Store.'
      else
        days_left::text || case when days_left = 1 then ' day left. ' else ' days left. ' end ||
        'Review your subscription in the App Store.'
    end
    else null
  end;
end;
$$;

create or replace function internal.enqueue_notification_for_user(
  p_recipient_user_id uuid,
  p_kind text,
  p_payload jsonb,
  p_dedupe_key text default null,
  p_redaction_level text default 'private',
  p_apns_push_type text default 'alert',
  p_apns_collapse_id text default null,
  p_scheduled_for timestamptz default null
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  queued_rows integer;
begin
  if p_recipient_user_id is null then
    raise exception 'notification recipient is required'
      using errcode = '23514';
  end if;

  if p_kind not in (
    'streak_reminder',
    'daily_challenge_completed',
    'partner_answered',
    'widget_updated',
    'location_updated',
    'relationship_ended',
    'entitlement_changed',
    'subscription_trial_reminder'
  ) then
    raise exception 'notification kind is not supported'
      using errcode = '23514';
  end if;

  if p_redaction_level <> 'private' then
    raise exception 'only private notification payloads are supported for MVP'
      using errcode = '23514';
  end if;

  if not internal.notification_payload_is_safe(p_payload) then
    raise exception 'notification payload contains sensitive or unsupported fields'
      using errcode = '23514';
  end if;

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
    p_kind,
    p_redaction_level,
    p_payload,
    case
      when nullif(btrim(coalesce(p_dedupe_key, '')), '') is null then null
      else btrim(p_dedupe_key) || ':' || device.id::text
    end,
    p_apns_push_type,
    nullif(btrim(coalesce(p_apns_collapse_id, '')), ''),
    case
      when p_apns_push_type = 'alert' then
        internal.notification_alert_title(p_kind, p_payload, device.locale)
      else null
    end,
    case
      when p_apns_push_type = 'alert' then
        internal.notification_alert_body(p_kind, p_payload, device.locale)
      else null
    end,
    coalesce(p_scheduled_for, now())
  from public.user_devices device
  join public.notification_preferences preference
    on preference.user_id = device.user_id
  where device.user_id = p_recipient_user_id
    and device.disabled_at is null
    and (
      case p_kind
        when 'streak_reminder' then preference.streak_reminders_enabled
        when 'daily_challenge_completed' then preference.daily_challenge_enabled
        when 'partner_answered' then preference.partner_answered_enabled
        when 'widget_updated' then
          (p_apns_push_type <> 'alert' or preference.widget_updates_enabled)
        when 'location_updated' then preference.location_updates_enabled
        else true
      end
    )
  on conflict do nothing;

  get diagnostics queued_rows = row_count;
  return queued_rows;
end;
$$;

create or replace function internal.queue_subscription_trial_reminders(
  p_batch_size integer default 500
)
returns integer
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  reminder_days_before_end constant integer := 2;
  reminder_interval interval;
  trial_row record;
  inserted_count integer := 0;
begin
  reminder_interval := reminder_days_before_end * interval '1 day';

  for trial_row in
    select
      tx.id as subscription_id,
      tx.user_id,
      tx.expires_at
    from internal.storekit_transactions tx
    join public.subscription_products product
      on product.id = tx.product_id
    join internal.storekit_payloads payload
      on payload.id = tx.raw_payload_id
    where tx.status in ('active', 'grace')
      and tx.expires_at is not null
      and tx.expires_at > now()
      and product.kind = 'couple_subscription'
      and product.is_active
      and payload.payload_json #>> '{transactionInfo,offerType}' = '1'
      and upper(payload.payload_json #>> '{transactionInfo,offerDiscountType}') = 'FREE_TRIAL'
      and tx.transaction_id = tx.original_transaction_id
      -- Queue only shortly before delivery. This keeps a future reminder from
      -- lingering for days after Apple revokes or changes the trial period.
      and tx.expires_at - reminder_interval <= now() + interval '1 hour'
      and exists (
        select 1
        from public.user_devices device
        join public.notification_preferences preference
          on preference.user_id = device.user_id
        where device.user_id = tx.user_id
          and device.disabled_at is null
          and not exists (
            select 1
            from internal.notification_outbox outbox
            where outbox.dedupe_key =
              'subscription_trial_reminder:' || tx.id::text || ':' ||
              device.id::text
          )
      )
    order by tx.expires_at
    limit greatest(coalesce(p_batch_size, 500), 1)
    for update of tx skip locked
  loop
    inserted_count := inserted_count + internal.enqueue_notification_for_user(
      trial_row.user_id,
      'subscription_trial_reminder',
      jsonb_build_object(
        'type', 'subscription_trial_reminder',
        'route', 'subscription',
        'deeplink', 'paeonia://settings/subscription',
        'subscription_id', trial_row.subscription_id,
        'trial_ends_at', trial_row.expires_at,
        'days_left', reminder_days_before_end
      ),
      'subscription_trial_reminder:' || trial_row.subscription_id::text,
      'private',
      'alert',
      'subscription-trial',
      greatest(now(), trial_row.expires_at - reminder_interval)
    );
  end loop;

  return inserted_count;
end;
$$;

create or replace function internal.invalidate_subscription_trial_reminder()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  subscription_id uuid;
begin
  if tg_op = 'DELETE' then
    subscription_id := old.id;
  else
    subscription_id := new.id;
  end if;

  if tg_op = 'DELETE' then
    delete from internal.notification_outbox outbox
    where outbox.kind = 'subscription_trial_reminder'
      and outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.payload ->> 'subscription_id' = subscription_id::text;

    return old;
  end if;

  if old.status is distinct from new.status
    or old.expires_at is distinct from new.expires_at then
    delete from internal.notification_outbox outbox
    where outbox.kind = 'subscription_trial_reminder'
      and outbox.sent_at is null
      and outbox.failed_at is null
      and outbox.payload ->> 'subscription_id' = subscription_id::text;
  end if;

  return new;
end;
$$;

create trigger invalidate_trial_reminder_after_storekit_update
after update of status, expires_at on internal.storekit_transactions
for each row
execute function internal.invalidate_subscription_trial_reminder();

create trigger invalidate_trial_reminder_after_storekit_delete
after delete on internal.storekit_transactions
for each row
execute function internal.invalidate_subscription_trial_reminder();

revoke all on function internal.queue_subscription_trial_reminders(integer)
  from public, anon, authenticated;
grant execute on function internal.queue_subscription_trial_reminders(integer)
  to service_role, postgres;

revoke all on function internal.invalidate_subscription_trial_reminder()
  from public, anon, authenticated;
grant execute on function internal.invalidate_subscription_trial_reminder()
  to service_role, postgres;

select cron.unschedule('queue-subscription-trial-reminders')
where exists (
  select 1
  from cron.job
  where jobname = 'queue-subscription-trial-reminders'
);

select cron.schedule(
  'queue-subscription-trial-reminders',
  '15 * * * *',
  $$select internal.queue_subscription_trial_reminders();$$
);
