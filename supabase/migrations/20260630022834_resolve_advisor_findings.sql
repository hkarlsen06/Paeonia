-- Resolve actionable Supabase advisor findings from 2026-06-30.
--
-- Most remaining RLS/no-policy and public SECURITY DEFINER advisor rows are
-- intentional RPC-only design. These changes address the findings that are
-- either real defense-in-depth gaps or deterministic performance wins.

alter table if exists internal.widget_push_outbox enable row level security;

revoke all on internal.widget_push_outbox from public, anon, authenticated;
grant all privileges on internal.widget_push_outbox to service_role;

create index if not exists streak_restorations_product_id_fk_idx
  on internal.streak_restorations (product_id);

create index if not exists streak_restorations_raw_payload_id_fk_idx
  on internal.streak_restorations (raw_payload_id);

create index if not exists widget_push_outbox_recipient_user_id_fk_idx
  on internal.widget_push_outbox (recipient_user_id);

do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    revoke all on function public.rls_auto_enable() from public, anon, authenticated;
    grant execute on function public.rls_auto_enable() to service_role;
  end if;
end;
$$;
