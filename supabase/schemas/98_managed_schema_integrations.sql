-- User-owned objects attached to Supabase-managed schemas.
--
-- Keep this file narrow: auth and storage themselves remain platform-managed.
-- These triggers and policies are Paeonia-owned and must survive every
-- declarative-schema round trip.

create trigger create_paeonia_profile_on_auth_user_created
after insert on auth.users
for each row
execute function internal.create_profile_for_new_user();

create trigger sync_profile_display_name_from_auth_metadata
after update of raw_user_meta_data on auth.users
for each row
execute function internal.sync_profile_display_name_from_auth_metadata();

create policy paeonia_media_pending_upload_insert
on storage.objects
for insert
to authenticated
with check (storage_private.paeonia_can_upload_reserved_media_object(bucket_id, name));

create policy paeonia_media_visible_select
on storage.objects
for select
to authenticated
using (storage_private.paeonia_can_read_media_object(bucket_id, name));
