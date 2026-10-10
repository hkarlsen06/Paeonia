import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

// Every scheduled job lives here. Feature agents append entries; keep one
// comment per job naming the pg_cron job or SQL function it replaces.
const crons = cronJobs();

// pg_cron 'paeonia-push-notification-drain' (internal.run_scheduled_push_notification_jobs).
crons.interval(
  "paeonia-push-notification-drain",
  { seconds: 30 },
  internal.push.run_scheduled_push_notification_jobs,
);

// New in Convex: report snapshot copies had no schedule in SQL (operators ran the claim by hand).
// The copy also runs right after a report is submitted. This cron retries failures after 15 minutes.
crons.interval("copy-report-snapshot-assets", { minutes: 5 }, internal.moderation.copy_report_snapshot_assets, {});

// New in Convex: replaces operator runs of claim_report_snapshot_storage_deletes
// and purge_deleted_report_snapshots. Snapshots expire 180 days after the first moderation action.
crons.interval("cleanup-report-snapshots", { hours: 1 }, internal.moderation.cleanup_report_snapshots, {});

// internal.enqueue_due_streak_reminders. pg_cron ran it inside the 30 second push job; reminders are
// queued up to one hour before a streak deadline and deduped per streak day, so five minutes is enough.
crons.interval("enqueue-due-streak-reminders", { minutes: 5 }, internal.streaks.enqueue_due_streak_reminders, {});

// pg_cron 'queue-subscription-trial-reminders' (internal.queue_subscription_trial_reminders), minute 15 of every hour.
crons.cron("queue-subscription-trial-reminders", "15 * * * *", internal.storekit.queue_subscription_trial_reminders, {});

// pg_cron 'paeonia-account-deletion-drain' (internal.request_account_deletion_drain), every minute.
// Inserting a job also schedules a drain after its 30 second reservation window.
crons.interval(
  "paeonia-account-deletion-drain",
  { minutes: 1 },
  internal.accountDeletion.request_account_deletion_drain,
  { p_source: "cron.account_deletion" },
);

// New in Convex: these four SQL cleanup functions had no pg_cron job (operators ran them by hand).
// Each runs one mutation per batch, so the batch sizes stay small. See lib/relationshipCleanup.ts.
crons.interval(
  "paeonia-cleanup-expired-relationship-content",
  { hours: 1 },
  internal.relationship.cleanup_expired_relationship_content,
  { p_limit: 5 },
);
crons.interval(
  "paeonia-purge-deleted-relationship-content",
  { hours: 1 },
  internal.relationship.purge_deleted_relationship_content,
  { p_limit: 5 },
);
crons.interval("paeonia-expire-stale-pairing-invites", { hours: 1 }, internal.pairing.expire_stale_pairing_invites, {});
crons.cron("paeonia-cleanup-attempt-logs", "30 3 * * *", internal.pairing.cleanup_attempt_logs, {});

// Replaces the cleanup-media-storage Edge Function, claim_media_storage_deletes, and
// claim_expired_pending_uploads. The SQL drain ran after each queueing write; the other two had no schedule.
crons.interval("cleanup-media-storage", { minutes: 5 }, internal.media.cleanup_media_storage, {});
// New in Convex: replaces operator runs of queue_orphaned_media_assets_for_delete and
// removes uploaded blobs that no media asset references. See media.ts.
crons.interval("sweep-orphan-media-storage", { hours: 6 }, internal.media.sweep_orphan_storage, {});

// New in Convex: internal.expire_stale_entitlements had no pg_cron job. Entitlement checks compare
// expires_at to the clock, but queries cannot write, so this persists the expired status and sends
// the entitlement_lost sync events. Covers StoreKit transactions and entitlement grants, 500 rows per run.
crons.interval("expire-stale-entitlements", { minutes: 5 }, internal.storekit.expire_stale_entitlements, {});

export default crons;
