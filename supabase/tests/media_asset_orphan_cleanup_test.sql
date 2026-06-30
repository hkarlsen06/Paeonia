-- Regression tests for automatic orphaned media cleanup queueing.

BEGIN;
SELECT plan(11);

INSERT INTO auth.users (id, email)
VALUES
  ('10000000-0000-0000-0000-0000000000a1', 'media-owner@test.local'),
  ('10000000-0000-0000-0000-0000000000a2', 'media-partner@test.local');

INSERT INTO public.relationship_pairs (id, user_low_id, user_high_id)
VALUES (
  '10000000-0000-0000-0000-0000000000b1',
  '10000000-0000-0000-0000-0000000000a1',
  '10000000-0000-0000-0000-0000000000a2'
);

INSERT INTO public.couples (id, pair_id, started_on, created_by_user_id, status)
VALUES (
  '10000000-0000-0000-0000-0000000000c1',
  '10000000-0000-0000-0000-0000000000b1',
  current_date,
  '10000000-0000-0000-0000-0000000000a1',
  'active'
);

INSERT INTO public.couple_members (couple_id, user_id, status)
VALUES
  ('10000000-0000-0000-0000-0000000000c1', '10000000-0000-0000-0000-0000000000a1', 'active'),
  ('10000000-0000-0000-0000-0000000000c1', '10000000-0000-0000-0000-0000000000a2', 'active');

INSERT INTO public.memories (
  id,
  couple_id,
  title,
  memory_date,
  created_by_user_id,
  last_edited_by_user_id
)
VALUES
  (
    '10000000-0000-0000-0000-0000000000d1',
    '10000000-0000-0000-0000-0000000000c1',
    'Soft deleted memory',
    current_date,
    '10000000-0000-0000-0000-0000000000a1',
    '10000000-0000-0000-0000-0000000000a1'
  ),
  (
    '10000000-0000-0000-0000-0000000000d2',
    '10000000-0000-0000-0000-0000000000c1',
    'Direct media removal',
    current_date,
    '10000000-0000-0000-0000-0000000000a1',
    '10000000-0000-0000-0000-0000000000a1'
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
    '10000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-0000000000a1',
    null,
    'profile_photo',
    '10000000-0000-0000-0000-0000000000a1',
    '10000000-0000-0000-0000-000000000101',
    'profile-photos',
    '10000000-0000-0000-0000-0000000000a1/old.jpg',
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
    '10000000-0000-0000-0000-000000000002',
    '10000000-0000-0000-0000-0000000000a1',
    null,
    'profile_photo',
    '10000000-0000-0000-0000-0000000000a1',
    '10000000-0000-0000-0000-000000000102',
    'profile-photos',
    '10000000-0000-0000-0000-0000000000a1/current.jpg',
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
    '10000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-0000000000a1',
    '10000000-0000-0000-0000-0000000000c1',
    'memory_media',
    '10000000-0000-0000-0000-0000000000e1',
    '10000000-0000-0000-0000-000000000103',
    'couple-media',
    '10000000-0000-0000-0000-0000000000c1/image/soft.jpg',
    'image',
    'memory_photo',
    'image',
    'couple-media',
    'image/jpeg',
    100,
    decode(repeat('3', 64), 'hex'),
    'finalized',
    now() + interval '1 day',
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-0000000000a1',
    '10000000-0000-0000-0000-0000000000c1',
    'memory_media',
    '10000000-0000-0000-0000-0000000000e2',
    '10000000-0000-0000-0000-000000000104',
    'couple-media',
    '10000000-0000-0000-0000-0000000000c1/image/direct.jpg',
    'image',
    'memory_photo',
    'image',
    'couple-media',
    'image/jpeg',
    100,
    decode(repeat('4', 64), 'hex'),
    'finalized',
    now() + interval '1 day',
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000005',
    '10000000-0000-0000-0000-0000000000a1',
    '10000000-0000-0000-0000-0000000000c1',
    'memory_media',
    '10000000-0000-0000-0000-0000000000d2',
    '10000000-0000-0000-0000-000000000105',
    'couple-media',
    '10000000-0000-0000-0000-0000000000c1/image/loose.jpg',
    'image',
    'memory_photo',
    'image',
    'couple-media',
    'image/jpeg',
    100,
    decode(repeat('5', 64), 'hex'),
    'finalized',
    now() + interval '1 day',
    now()
  ),
  (
    '10000000-0000-0000-0000-000000000006',
    '10000000-0000-0000-0000-0000000000a1',
    null,
    'report_snapshot',
    '10000000-0000-0000-0000-0000000000f1',
    '10000000-0000-0000-0000-000000000106',
    'report-snapshots',
    '10000000-0000-0000-0000-0000000000f1/snapshot.json',
    'report_snapshot',
    'report_snapshot',
    'report_snapshot',
    'report-snapshots',
    'application/json',
    100,
    decode(repeat('6', 64), 'hex'),
    'finalized',
    now() + interval '1 day',
    now()
  );

INSERT INTO public.memory_media (
  id,
  memory_id,
  media_asset_id,
  owner_user_id,
  sort_order
)
VALUES
  (
    '10000000-0000-0000-0000-0000000000e1',
    '10000000-0000-0000-0000-0000000000d1',
    '10000000-0000-0000-0000-000000000003',
    '10000000-0000-0000-0000-0000000000a1',
    1
  ),
  (
    '10000000-0000-0000-0000-0000000000e2',
    '10000000-0000-0000-0000-0000000000d2',
    '10000000-0000-0000-0000-000000000004',
    '10000000-0000-0000-0000-0000000000a1',
    1
  );

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_trigger
    WHERE tgname LIKE 'queue_orphaned%'
      AND tgdeferrable
      AND tginitdeferred
  ),
  15,
  'orphaned media queue triggers are deferrable'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc proc
    JOIN pg_namespace schema_row
      ON schema_row.oid = proc.pronamespace
    WHERE schema_row.nspname = 'public'
      AND proc.proname IN (
        'claim_media_storage_deletes',
        'mark_media_storage_deleted',
        'mark_media_storage_delete_failed',
        'claim_report_snapshot_storage_deletes',
        'mark_report_snapshot_storage_deleted',
        'mark_report_snapshot_storage_delete_failed'
      )
      AND proc.prosecdef
      AND coalesce(proc.proconfig @> ARRAY['search_path=pg_catalog'], false)
  ),
  6,
  'storage cleanup public wrappers are security definer with fixed search path'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc proc
    JOIN pg_namespace schema_row
      ON schema_row.oid = proc.pronamespace
    WHERE schema_row.nspname = 'public'
      AND proc.proname IN (
        'claim_media_storage_deletes',
        'mark_media_storage_deleted',
        'mark_media_storage_delete_failed',
        'claim_report_snapshot_storage_deletes',
        'mark_report_snapshot_storage_deleted',
        'mark_report_snapshot_storage_delete_failed'
      )
      AND has_function_privilege('service_role', proc.oid, 'execute')
  ),
  6,
  'service role can execute storage cleanup wrappers'
);

SELECT is(
  (
    SELECT count(*)::integer
    FROM pg_proc proc
    JOIN pg_namespace schema_row
      ON schema_row.oid = proc.pronamespace
    WHERE schema_row.nspname = 'public'
      AND proc.proname IN (
        'claim_media_storage_deletes',
        'mark_media_storage_deleted',
        'mark_media_storage_delete_failed',
        'claim_report_snapshot_storage_deletes',
        'mark_report_snapshot_storage_deleted',
        'mark_report_snapshot_storage_delete_failed'
      )
      AND (
        has_function_privilege('anon', proc.oid, 'execute')
        OR has_function_privilege('authenticated', proc.oid, 'execute')
      )
  ),
  0,
  'ordinary client roles cannot execute storage cleanup wrappers'
);

UPDATE public.profiles
SET profile_photo_asset_id = '10000000-0000-0000-0000-000000000001'
WHERE user_id = '10000000-0000-0000-0000-0000000000a1';

UPDATE public.profiles
SET profile_photo_asset_id = '10000000-0000-0000-0000-000000000002'
WHERE user_id = '10000000-0000-0000-0000-0000000000a1';

SET CONSTRAINTS ALL IMMEDIATE;

SELECT is(
  (
    SELECT storage_delete_status
    FROM public.media_assets
    WHERE id = '10000000-0000-0000-0000-000000000001'
  ),
  'pending',
  'replacing a profile photo queues the old asset'
);

SELECT is(
  (
    SELECT storage_delete_status
    FROM public.media_assets
    WHERE id = '10000000-0000-0000-0000-000000000002'
  ),
  'none',
  'the current profile photo stays usable'
);

SELECT ok(
  NOT internal.queue_orphaned_media_asset_for_delete('10000000-0000-0000-0000-000000000002'),
  'a live profile reference prevents deletion queueing'
);

UPDATE public.memories
SET deleted_at = now()
WHERE id = '10000000-0000-0000-0000-0000000000d1';

SELECT is(
  (
    SELECT storage_delete_status
    FROM public.media_assets
    WHERE id = '10000000-0000-0000-0000-000000000003'
  ),
  'pending',
  'soft-deleting a memory queues its media asset'
);

DELETE FROM public.memory_media
WHERE id = '10000000-0000-0000-0000-0000000000e2';

SELECT is(
  (
    SELECT storage_delete_status
    FROM public.media_assets
    WHERE id = '10000000-0000-0000-0000-000000000004'
  ),
  'pending',
  'deleting a media join row queues its orphaned asset'
);

SELECT is(
  internal.queue_orphaned_media_assets_for_delete(100),
  1,
  'the sweep queues the remaining finalized ordinary orphan'
);

SELECT ok(
  (
    SELECT loose.storage_delete_status = 'pending'
      AND snapshot.storage_delete_status = 'none'
    FROM public.media_assets loose
    CROSS JOIN public.media_assets snapshot
    WHERE loose.id = '10000000-0000-0000-0000-000000000005'
      AND snapshot.id = '10000000-0000-0000-0000-000000000006'
  ),
  'the sweep skips report snapshots'
);

SELECT * FROM finish();
ROLLBACK;
