insert into public.subscription_products (apple_product_id, kind, billing_period, is_active)
values
  ('no.paeonia.couple', 'couple_subscription', 'monthly', true),
  ('no.paeonia.couple.year', 'couple_subscription', 'yearly', true)
on conflict (apple_product_id) do update
set
  kind = excluded.kind,
  billing_period = excluded.billing_period,
  is_active = excluded.is_active;
