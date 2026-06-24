create or replace function internal.record_verified_storekit_transaction(
  p_user_id uuid,
  p_app_account_token uuid,
  p_apple_product_id text,
  p_environment text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_web_order_line_item_id text,
  p_status text,
  p_purchased_at timestamptz,
  p_expires_at timestamptz,
  p_revoked_at timestamptz,
  p_revocation_reason text,
  p_signed_payload text,
  p_payload_json jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog
as $$
declare
  resolved_user_id uuid;
  resolved_product_id uuid;
  existing_user_id uuid;
  payload_id uuid;
  storekit_transaction_id uuid;
begin
  if p_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Invalid user',
      'status', 401
    );
  end if;

  if p_app_account_token is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple transaction is missing appAccountToken',
      'status', 403
    );
  end if;

  select app_token.user_id
  into resolved_user_id
  from internal.app_account_tokens app_token
  where app_token.token = p_app_account_token;

  if resolved_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple appAccountToken is not registered',
      'status', 403
    );
  end if;

  if resolved_user_id is distinct from p_user_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple transaction belongs to a different user',
      'status', 403
    );
  end if;

  select product.id
  into resolved_product_id
  from public.subscription_products product
  where product.apple_product_id = p_apple_product_id
    and product.is_active
  limit 1;

  if resolved_product_id is null then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple product is not active in Paeonia',
      'status', 400
    );
  end if;

  select tx.user_id
  into existing_user_id
  from internal.storekit_transactions tx
  where tx.environment = p_environment
    and tx.transaction_id = p_transaction_id;

  if existing_user_id is not null and existing_user_id is distinct from p_user_id then
    return jsonb_build_object(
      'ok', false,
      'error', 'Apple transaction belongs to a different user',
      'status', 403
    );
  end if;

  insert into internal.storekit_payloads (
    payload_kind,
    environment,
    original_transaction_id,
    transaction_id,
    signed_payload,
    payload_json
  )
  values (
    'transaction',
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_signed_payload,
    p_payload_json
  )
  returning id into payload_id;

  insert into internal.storekit_transactions (
    user_id,
    product_id,
    environment,
    app_account_token,
    original_transaction_id,
    transaction_id,
    web_order_line_item_id,
    status,
    purchased_at,
    expires_at,
    revoked_at,
    revocation_reason,
    raw_payload_id,
    last_reconciled_at,
    reconciliation_claimed_at,
    reconciliation_attempts,
    last_reconciliation_error
  )
  values (
    p_user_id,
    resolved_product_id,
    p_environment,
    p_app_account_token,
    p_original_transaction_id,
    p_transaction_id,
    p_web_order_line_item_id,
    p_status,
    p_purchased_at,
    p_expires_at,
    p_revoked_at,
    p_revocation_reason,
    payload_id,
    now(),
    null,
    0,
    null
  )
  on conflict (environment, transaction_id)
  do update set
    user_id = excluded.user_id,
    product_id = excluded.product_id,
    app_account_token = excluded.app_account_token,
    original_transaction_id = excluded.original_transaction_id,
    web_order_line_item_id = excluded.web_order_line_item_id,
    status = excluded.status,
    purchased_at = excluded.purchased_at,
    expires_at = excluded.expires_at,
    revoked_at = excluded.revoked_at,
    revocation_reason = excluded.revocation_reason,
    raw_payload_id = excluded.raw_payload_id,
    last_reconciled_at = excluded.last_reconciled_at,
    reconciliation_claimed_at = excluded.reconciliation_claimed_at,
    reconciliation_attempts = excluded.reconciliation_attempts,
    last_reconciliation_error = excluded.last_reconciliation_error
  returning id into storekit_transaction_id;

  return jsonb_build_object(
    'ok', true,
    'productId', resolved_product_id,
    'payloadId', payload_id,
    'transactionId', storekit_transaction_id
  );
end;
$$;

create or replace function public.record_verified_storekit_transaction(
  p_user_id uuid,
  p_app_account_token uuid,
  p_apple_product_id text,
  p_environment text,
  p_original_transaction_id text,
  p_transaction_id text,
  p_web_order_line_item_id text,
  p_status text,
  p_purchased_at timestamptz,
  p_expires_at timestamptz,
  p_revoked_at timestamptz,
  p_revocation_reason text,
  p_signed_payload text,
  p_payload_json jsonb
)
returns jsonb
language sql
security invoker
set search_path = pg_catalog
as $$
  select internal.record_verified_storekit_transaction(
    p_user_id,
    p_app_account_token,
    p_apple_product_id,
    p_environment,
    p_original_transaction_id,
    p_transaction_id,
    p_web_order_line_item_id,
    p_status,
    p_purchased_at,
    p_expires_at,
    p_revoked_at,
    p_revocation_reason,
    p_signed_payload,
    p_payload_json
  );
$$;

revoke all on function internal.record_verified_storekit_transaction(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  jsonb
) from public, anon, authenticated;
grant execute on function internal.record_verified_storekit_transaction(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  jsonb
) to service_role;

revoke all on function public.record_verified_storekit_transaction(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  jsonb
) from public, anon, authenticated;
grant execute on function public.record_verified_storekit_transaction(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  jsonb
) to service_role;
