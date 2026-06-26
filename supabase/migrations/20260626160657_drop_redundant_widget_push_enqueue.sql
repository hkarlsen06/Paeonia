-- Remove the duplicate widget-revision push enqueue.
--
-- 20260625212249_widget_push_notifications added
-- internal.notify_partner_of_widget_revision, but widget revisions were already
-- enqueuing a 'widget_updated' background notification through the pre-existing
-- internal.handle_widget_drawing_revision_created (20260615012605), which also
-- carries a per-revision dedupe key and records couple activity.
--
-- Running both meant every save enqueued the notification twice. Because the
-- outbox drain trigger fires per-statement, two inserts also fired two drains,
-- which raced and re-claimed each row (attempt_count = 2) and double-sent to
-- APNs. Dropping the redundant trigger leaves one well-formed, deduped enqueue
-- and one drain per save. The drain RPCs, invoke_widget_push_drain, the Vault
-- secret, and the send-widget-push function from that migration are unaffected.

drop trigger if exists notify_partner_of_widget_revision on public.widget_drawing_revisions;
drop function if exists internal.notify_partner_of_widget_revision();
