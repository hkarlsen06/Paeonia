-- The app-account-token RPC was added after the internal RPC hardening
-- migration, so align it with the existing public wrappers that call internal
-- implementation functions while keeping the internal schema private.
alter function public.get_or_create_app_account_token(uuid)
security definer;

alter function public.get_or_create_app_account_token(uuid)
set search_path = pg_catalog;
