-- Trial-ending reminders adapt Tidex's server-side queue pattern. The queue
-- must prove Apple's payment mode is FREE_TRIAL, localize per device, advance
-- through bounded batches, run two days before expiry, and invalidate stale rows.

begin;
select plan(19);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000a101', 'trial-one@test.local'),
  ('00000000-0000-0000-0000-00000000a102', 'paid-intro@test.local'),
  ('00000000-0000-0000-0000-00000000a103', 'trial-two@test.local'),
  ('00000000-0000-0000-0000-00000000a104', 'noninitial-trial@test.local'),
  ('00000000-0000-0000-0000-00000000a105', 'future-trial@test.local'),
  ('00000000-0000-0000-0000-00000000a106', 'no-device-trial@test.local');

insert into public.user_devices (
  id,
  user_id,
  platform,
  push_token,
  push_token_hash,
  apns_environment,
  locale
) values
  ('00000000-0000-0000-0000-00000000d101', '00000000-0000-0000-0000-00000000a101', 'ios', repeat('a', 64), decode(repeat('a', 64), 'hex'), 'sandbox', 'en'),
  ('00000000-0000-0000-0000-00000000d102', '00000000-0000-0000-0000-00000000a101', 'ios', repeat('b', 64), decode(repeat('b', 64), 'hex'), 'sandbox', 'nb-NO'),
  ('00000000-0000-0000-0000-00000000d103', '00000000-0000-0000-0000-00000000a102', 'ios', repeat('c', 64), decode(repeat('c', 64), 'hex'), 'sandbox', 'en'),
  ('00000000-0000-0000-0000-00000000d104', '00000000-0000-0000-0000-00000000a103', 'ios', repeat('d', 64), decode(repeat('d', 64), 'hex'), 'sandbox', 'en'),
  ('00000000-0000-0000-0000-00000000d105', '00000000-0000-0000-0000-00000000a104', 'ios', repeat('e', 64), decode(repeat('e', 64), 'hex'), 'sandbox', 'en'),
  ('00000000-0000-0000-0000-00000000d106', '00000000-0000-0000-0000-00000000a105', 'ios', repeat('f', 64), decode(repeat('f', 64), 'hex'), 'sandbox', 'en');

insert into internal.storekit_payloads (
  id,
  payload_kind,
  environment,
  original_transaction_id,
  transaction_id,
  payload_json
) values
  (
    '00000000-0000-0000-0000-00000000e101',
    'transaction',
    'sandbox',
    'trial-one',
    'trial-one',
    '{"transactionInfo":{"offerType":1,"offerDiscountType":"FREE_TRIAL"}}'::jsonb
  ),
  (
    '00000000-0000-0000-0000-00000000e102',
    'transaction',
    'sandbox',
    'paid-intro',
    'paid-intro',
    '{"transactionInfo":{"offerType":1,"offerDiscountType":"PAY_AS_YOU_GO"}}'::jsonb
  ),
  (
    '00000000-0000-0000-0000-00000000e103',
    'transaction',
    'sandbox',
    'trial-two',
    'trial-two',
    '{"transactionInfo":{"offerType":1,"offerDiscountType":"FREE_TRIAL"}}'::jsonb
  ),
  (
    '00000000-0000-0000-0000-00000000e104',
    'transaction',
    'sandbox',
    'noninitial-original',
    'noninitial-second',
    '{"transactionInfo":{"offerType":1,"offerDiscountType":"FREE_TRIAL"}}'::jsonb
  ),
  (
    '00000000-0000-0000-0000-00000000e105',
    'transaction',
    'sandbox',
    'future-trial',
    'future-trial',
    '{"transactionInfo":{"offerType":1,"offerDiscountType":"FREE_TRIAL"}}'::jsonb
  ),
  (
    '00000000-0000-0000-0000-00000000e106',
    'transaction',
    'sandbox',
    'no-device-trial',
    'no-device-trial',
    '{"transactionInfo":{"offerType":1,"offerDiscountType":"FREE_TRIAL"}}'::jsonb
  );

insert into internal.storekit_transactions (
  id,
  user_id,
  product_id,
  environment,
  original_transaction_id,
  transaction_id,
  status,
  purchased_at,
  expires_at,
  raw_payload_id
) values
  (
    '00000000-0000-0000-0000-00000000f101',
    '00000000-0000-0000-0000-00000000a101',
    (select id from public.subscription_products where apple_product_id = 'no.paeonia.couple.year'),
    'sandbox', 'trial-one', 'trial-one', 'active',
    now() - interval '12 days', now() + interval '2 days 30 minutes',
    '00000000-0000-0000-0000-00000000e101'
  ),
  (
    '00000000-0000-0000-0000-00000000f102',
    '00000000-0000-0000-0000-00000000a102',
    (select id from public.subscription_products where apple_product_id = 'no.paeonia.couple.year'),
    'sandbox', 'paid-intro', 'paid-intro', 'active',
    now() - interval '12 days', now() + interval '2 days 35 minutes',
    '00000000-0000-0000-0000-00000000e102'
  ),
  (
    '00000000-0000-0000-0000-00000000f103',
    '00000000-0000-0000-0000-00000000a103',
    (select id from public.subscription_products where apple_product_id = 'no.paeonia.couple.year'),
    'sandbox', 'trial-two', 'trial-two', 'active',
    now() - interval '12 days', now() + interval '2 days 40 minutes',
    '00000000-0000-0000-0000-00000000e103'
  ),
  (
    '00000000-0000-0000-0000-00000000f104',
    '00000000-0000-0000-0000-00000000a104',
    (select id from public.subscription_products where apple_product_id = 'no.paeonia.couple.year'),
    'sandbox', 'noninitial-original', 'noninitial-second', 'active',
    now() - interval '12 days', now() + interval '2 days 20 minutes',
    '00000000-0000-0000-0000-00000000e104'
  ),
  (
    '00000000-0000-0000-0000-00000000f105',
    '00000000-0000-0000-0000-00000000a105',
    (select id from public.subscription_products where apple_product_id = 'no.paeonia.couple.year'),
    'sandbox', 'future-trial', 'future-trial', 'active',
    now() - interval '10 days', now() + interval '4 days',
    '00000000-0000-0000-0000-00000000e105'
  ),
  (
    '00000000-0000-0000-0000-00000000f106',
    '00000000-0000-0000-0000-00000000a106',
    (select id from public.subscription_products where apple_product_id = 'no.paeonia.couple.year'),
    'sandbox', 'no-device-trial', 'no-device-trial', 'active',
    now() - interval '12 days', now() + interval '2 days 10 minutes',
    '00000000-0000-0000-0000-00000000e106'
  );

select is(
  internal.notification_alert_title('subscription_trial_reminder', '{"days_left":2}'::jsonb, 'en'),
  'Your free trial ends soon',
  'English reminder title is localized'
);

select is(
  internal.notification_alert_body('subscription_trial_reminder', '{"days_left":2}'::jsonb, 'nb-NO'),
  '2 dager igjen. Se over abonnementet ditt i App Store.',
  'Norwegian reminder body is localized'
);

select is(
  internal.queue_subscription_trial_reminders(1),
  2,
  'first bounded batch queues one verified trial for both devices'
);

select is(
  (select count(*)::integer from internal.notification_outbox where kind = 'subscription_trial_reminder'),
  2,
  'first verified trial has one row per device'
);

select is(
  (select title from internal.notification_outbox where target_device_id = '00000000-0000-0000-0000-00000000d101'),
  'Your free trial ends soon',
  'English device stores English copy'
);

select is(
  (select body from internal.notification_outbox where target_device_id = '00000000-0000-0000-0000-00000000d102'),
  '2 dager igjen. Se over abonnementet ditt i App Store.',
  'Norwegian device stores Norwegian copy'
);

select ok(
  (
    select abs(extract(epoch from (
      outbox.scheduled_for - (tx.expires_at - interval '2 days')
    ))) < 1
    from internal.notification_outbox outbox
    join internal.storekit_transactions tx
      on tx.id::text = (outbox.payload ->> 'subscription_id')
    where outbox.target_device_id = '00000000-0000-0000-0000-00000000d101'
  ),
  'delivery is scheduled two days before the verified expiry'
);

select is(
  (select payload ->> 'deeplink' from internal.notification_outbox where target_device_id = '00000000-0000-0000-0000-00000000d101'),
  'paeonia://settings/subscription',
  'tap payload routes to subscription management'
);

select is(
  (select count(*)::integer from internal.notification_outbox where recipient_user_id = '00000000-0000-0000-0000-00000000a102'),
  0,
  'a paid introductory offer is not mislabeled as a free trial'
);

select is(
  (select count(*)::integer from internal.notification_outbox where recipient_user_id = '00000000-0000-0000-0000-00000000a104'),
  0,
  'a noninitial transaction is not treated as the promised introductory trial'
);

select is(
  (select count(*)::integer from internal.notification_outbox where recipient_user_id = '00000000-0000-0000-0000-00000000a105'),
  0,
  'a trial outside the one-hour queue window is not scheduled far in advance'
);

select is(
  (select count(*)::integer from internal.notification_outbox where payload ->> 'subscription_id' = '00000000-0000-0000-0000-00000000f106'),
  0,
  'an earlier trial without a registered device does not consume the batch'
);

select is(
  internal.queue_subscription_trial_reminders(1),
  1,
  'next bounded run advances past fully queued trials'
);

select is(
  (select count(*)::integer from internal.notification_outbox where recipient_user_id = '00000000-0000-0000-0000-00000000a103'),
  1,
  'second verified trial is not starved by the batch limit'
);

select is(
  internal.queue_subscription_trial_reminders(1),
  0,
  'rerunning the queue does not duplicate reminders'
);

update internal.storekit_transactions
set expires_at = expires_at + interval '1 day'
where id = '00000000-0000-0000-0000-00000000f101';

select is(
  (select count(*)::integer from internal.notification_outbox where recipient_user_id = '00000000-0000-0000-0000-00000000a101'),
  0,
  'an Apple expiry change invalidates the stale scheduled reminder'
);

update internal.storekit_transactions
set status = 'expired'
where id = '00000000-0000-0000-0000-00000000f103';

select is(
  (select count(*)::integer from internal.notification_outbox where kind = 'subscription_trial_reminder'),
  0,
  'an Apple status change invalidates the remaining unsent reminder'
);

select is(
  internal.queue_subscription_trial_reminders(),
  0,
  'ineligible transactions do not queue new rows'
);

select ok(
  exists (
    select 1
    from cron.job
    where jobname = 'queue-subscription-trial-reminders'
      and schedule = '15 * * * *'
  ),
  'hourly trial reminder queue job is installed'
);

select * from finish();
rollback;
