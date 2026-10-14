import { cronJobs } from "convex/server";
import { internal } from "./_generated/api";

// Every scheduled job lives here. Feature agents append entries; keep one
// comment per job naming the pg_cron job or SQL function it replaces.
const crons = cronJobs();

// Game presence and chat typing have no cleanup cron: the presence component marks a user
// offline when heartbeats stop. See lib/presence.ts.

// New in Convex: the single reminder for a game turn that waited 72 hours. See games.ts.
crons.interval("send-due-game-turn-reminders", { minutes: 15 }, internal.games.send_due_game_turn_reminders, {});

// pg_cron 'paeonia-push-notification-drain' has no entry: each outbox row is a pushWorkpool
// work item that runs at its scheduled_for and retries itself. See lib/notifications.ts.

// Report snapshot copies have no cron. Each copy is a backgroundWorkpool job that retries
// itself. See lib/reportTargets.ts.

// New in Convex: replaces operator runs of claim_report_snapshot_storage_deletes
// and purge_deleted_report_snapshots. Snapshots expire 180 days after the first moderation action.
crons.interval("cleanup-report-snapshots", { hours: 1 }, internal.moderation.cleanup_report_snapshots, {});

// internal.enqueue_due_streak_reminders. pg_cron ran it inside the 30 second push job; reminders are
// queued up to one hour before a streak deadline and deduped per streak day, so five minutes is enough.
crons.interval("enqueue-due-streak-reminders", { minutes: 5 }, internal.streaks.enqueue_due_streak_reminders, {});
// Evening reminders go out within the hour after 19:00 in each partner's zone, deduped per streak day.
crons.interval("enqueue-evening-streak-reminders", { minutes: 5 }, internal.streaks.enqueue_evening_streak_reminders, {});

// New in Convex: the opt-in "question time" reminder. The window after the chosen time is 15 minutes,
// so five-minute runs cover a late run. Deduped per user and local date. See questionTime.ts.
crons.interval("enqueue-question-time-reminders", { minutes: 5 }, internal.questionTime.enqueue_question_time_reminders, {});

// pg_cron 'queue-subscription-trial-reminders' (internal.queue_subscription_trial_reminders), minute 15 of every hour.
crons.cron("queue-subscription-trial-reminders", "15 * * * *", internal.storekit.queue_subscription_trial_reminders, {});

// pg_cron 'paeonia-account-deletion-drain' has no entry. requestAccountDeletion queues the
// Clerk delete as a backgroundWorkpool job that retries itself. See accountDeletion.ts.

// New in Convex: these three SQL cleanup functions had no pg_cron job (operators ran them by hand).
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
