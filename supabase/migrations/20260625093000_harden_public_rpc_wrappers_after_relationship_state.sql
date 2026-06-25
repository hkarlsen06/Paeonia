-- Keep the internal schema out of the authenticated Data API surface.
--
-- Public RPC wrappers that need internal helpers must run as security definer
-- instead of granting clients USAGE or EXECUTE on the internal schema.

revoke usage on schema internal from public, anon, authenticated;
revoke execute on all functions in schema internal from public, anon, authenticated;

alter function public.get_current_relationship_state()
  security definer;

alter function public.record_verified_storekit_transaction(
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
) security definer;

alter function public.record_storekit_server_notification(
  uuid,
  text,
  text,
  text,
  text,
  text,
  uuid,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  text,
  text,
  jsonb
) security definer;

notify pgrst, 'reload schema';
