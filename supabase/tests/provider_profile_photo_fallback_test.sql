BEGIN;
SELECT plan(15);

INSERT INTO auth.users (id, email)
VALUES
  ('81000000-0000-0000-0000-000000000001', 'avatar-owner@test.local'),
  ('81000000-0000-0000-0000-000000000002', 'avatar-partner@test.local'),
  ('81000000-0000-0000-0000-000000000003', 'avatar-outsider@test.local');

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id)
VALUES (
  '82000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000002'
);

INSERT INTO public.couples (id, pair_id, started_on, created_by_user_id, status)
VALUES (
  '83000000-0000-0000-0000-000000000001',
  '82000000-0000-0000-0000-000000000001',
  null,
  '81000000-0000-0000-0000-000000000001',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status)
VALUES
  (
    '83000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001',
    'active'
  ),
  (
    '83000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000002',
    'active'
  );

INSERT INTO internal.entitlement_grants (
  id,
  user_id,
  grant_kind,
  status,
  scope,
  granted_by
)
VALUES (
  '83500000-0000-0000-0000-000000000001',
  '81000000-0000-0000-0000-000000000001',
  'lifetime',
  'active',
  'user',
  'provider-profile-photo-test'
);

INSERT INTO public.media_assets (
  id,
  owner_user_id,
  couple_id,
  reserved_parent_kind,
  reserved_parent_id,
  reserved_by_client_operation_id,
  bucket,
  storage_path,
  media_type,
  upload_purpose,
  expected_media_type,
  expected_bucket,
  mime_type,
  byte_size,
  sha256,
  upload_status,
  upload_expires_at,
  upload_finalized_at
)
VALUES
  (
    '84000000-0000-0000-0000-000000000001',
    '81000000-0000-0000-0000-000000000001',
    null,
    'profile_photo',
    '81000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000001',
    'profile-photos',
    '81000000-0000-0000-0000-000000000001/custom.jpg',
    'image',
    'profile_photo',
    'image',
    'profile-photos',
    'image/jpeg',
    100,
    decode(repeat('1', 64), 'hex'),
    'finalized',
    now() + interval '1 day',
    now()
  ),
  (
    '84000000-0000-0000-0000-000000000002',
    '81000000-0000-0000-0000-000000000001',
    null,
    'profile_photo',
    '81000000-0000-0000-0000-000000000001',
    '85000000-0000-0000-0000-000000000002',
    'profile-photos',
    '81000000-0000-0000-0000-000000000001/provider.jpg',
    'image',
    'profile_photo',
    'image',
    'profile-photos',
    'image/jpeg',
    100,
    decode(repeat('2', 64), 'hex'),
    'finalized',
    now() + interval '1 day',
    now()
  ),
  (
    '84000000-0000-0000-0000-000000000003',
    '81000000-0000-0000-0000-000000000003',
    null,
    'profile_photo',
    '81000000-0000-0000-0000-000000000003',
    '85000000-0000-0000-0000-000000000003',
    'profile-photos',
    '81000000-0000-0000-0000-000000000003/other.jpg',
    'image',
    'profile_photo',
    'image',
    'profile-photos',
    'image/jpeg',
    100,
    decode(repeat('3', 64), 'hex'),
    'finalized',
    now() + interval '1 day',
    now()
  );

UPDATE public.profiles
SET
  display_name = 'Owner',
  profile_photo_asset_id = '84000000-0000-0000-0000-000000000001',
  provider_profile_photo_asset_id = '84000000-0000-0000-0000-000000000002',
  provider_profile_photo_source = 'google'
WHERE user_id = '81000000-0000-0000-0000-000000000001';

SELECT ok(
  (
    SELECT proc.prosecdef
      AND coalesce(proc.proconfig @> ARRAY['search_path=pg_catalog'], false)
    FROM pg_proc proc
    JOIN pg_namespace namespace ON namespace.oid = proc.pronamespace
    WHERE namespace.nspname = 'public'
      AND proc.proname = 'update_own_profile'
  ),
  'profile update RPC is security definer with a fixed search path'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.update_own_profile(text,uuid)',
    'execute'
  ),
  'authenticated users can execute the scoped profile update RPC'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.update_own_profile(text,uuid)', 'execute'),
  'anonymous users cannot execute the profile update RPC'
);

SELECT ok(
  (
    SELECT proc.prosecdef
      AND coalesce(proc.proconfig @> ARRAY['search_path=pg_catalog'], false)
    FROM pg_proc proc
    JOIN pg_namespace namespace ON namespace.oid = proc.pronamespace
    WHERE namespace.nspname = 'public'
      AND proc.proname = 'set_own_provider_profile_photo'
  ),
  'provider import RPC is security definer with a fixed search path'
);

SELECT ok(
  has_function_privilege(
    'authenticated',
    'public.set_own_provider_profile_photo(uuid,text)',
    'execute'
  )
  AND NOT has_function_privilege(
    'anon',
    'public.set_own_provider_profile_photo(uuid,text)',
    'execute'
  ),
  'only authenticated app users can call the provider import RPC'
);

SELECT throws_ok(
  $$
    UPDATE public.profiles
    SET
      provider_profile_photo_asset_id = '84000000-0000-0000-0000-000000000003',
      provider_profile_photo_source = 'google'
    WHERE user_id = '81000000-0000-0000-0000-000000000001'
  $$,
  '23514',
  'profile photo asset is not usable',
  'a provider fallback must belong to the profile owner'
);

DO $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    '81000000-0000-0000-0000-000000000002',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated"}',
    true
  );
end;
$$;

SELECT is(
  (
    SELECT partner_profile_photo_asset_id
    FROM public.get_current_relationship_state()
  ),
  '84000000-0000-0000-0000-000000000001'::uuid,
  'the partner relationship projection prefers the custom override'
);

SELECT ok(
  internal.can_read_media_object(
    'profile-photos',
    '81000000-0000-0000-0000-000000000001/provider.jpg'
  ),
  'an active partner can read the private provider fallback'
);

DO $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    '81000000-0000-0000-0000-000000000001',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"81000000-0000-0000-0000-000000000001","role":"authenticated"}',
    true
  );
end;
$$;

SELECT lives_ok(
  $$
    SELECT *
    FROM public.set_own_provider_profile_photo(
      '84000000-0000-0000-0000-000000000002',
      'google'
    )
  $$,
  'the owner can link their validated private provider fallback through the RPC'
);

SELECT lives_ok(
  $$ SELECT * FROM public.update_own_profile('Renamed', null) $$,
  'the owner can atomically update their name and remove the custom override'
);

SET CONSTRAINTS ALL IMMEDIATE;

SELECT is(
  (
    SELECT profile_photo_asset_id
    FROM public.profiles
    WHERE user_id = '81000000-0000-0000-0000-000000000001'
  ),
  null::uuid,
  'removing a custom photo leaves the custom override empty'
);

SELECT is(
  (
    SELECT provider_profile_photo_asset_id
    FROM public.profiles
    WHERE user_id = '81000000-0000-0000-0000-000000000001'
  ),
  '84000000-0000-0000-0000-000000000002'::uuid,
  'removing a custom photo preserves the provider fallback'
);

SELECT is(
  (
    SELECT storage_delete_status
    FROM public.media_assets
    WHERE id = '84000000-0000-0000-0000-000000000001'
  ),
  'pending',
  'removing the custom override queues only that old asset'
);

DO $$
begin
  perform set_config(
    'request.jwt.claim.sub',
    '81000000-0000-0000-0000-000000000002',
    true
  );
  perform set_config(
    'request.jwt.claims',
    '{"sub":"81000000-0000-0000-0000-000000000002","role":"authenticated"}',
    true
  );
end;
$$;

SELECT is(
  (
    SELECT partner_profile_photo_asset_id
    FROM public.get_current_relationship_state()
  ),
  '84000000-0000-0000-0000-000000000002'::uuid,
  'the partner relationship projection reveals the provider fallback'
);

SELECT ok(
  NOT internal.queue_orphaned_media_asset_for_delete(
    '84000000-0000-0000-0000-000000000002'
  ),
  'the provider fallback remains protected from orphan cleanup'
);

SELECT * FROM finish();
ROLLBACK;
