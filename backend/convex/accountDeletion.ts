import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalAction, internalMutation, internalQuery, type ActionCtx, type MutationCtx } from "./_generated/server";
import { findCurrentCouple } from "./lib/access";
import { authProviderFromIdentity } from "./lib/auth";
import { getByUuid, withTouch, withUpdatedAt, type ReaderCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { newUuid, optionalTimestampArg, optionalUuidArg, uuidArg } from "./lib/ids";
import { queueOldMediaAssetIfOrphaned } from "./lib/mediaOrphans";
import {
  deleteClerkUser,
  fetchAppleSubjects,
  revokeAppleAuthorization,
  stableAuthDeleteErrorCode,
} from "./lib/accountDeletionProviders";
import { findProfile, updateProfile } from "./lib/profiles";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { tombstoneReportTargets } from "./lib/reports";
import { addMs, nowIso } from "./lib/time";
import { authProvider as authProviderValidator } from "./lib/validators";

type AuthProvider = "apple" | "google" | "unknown";

const MAX_AUTH_ATTEMPTS = 10;
const RESERVATION_MS = 30_000;
const ACTIVE_DELETION_STATUSES = ["submitted", "verifying", "processing"] as const;

type DeletionStartRow = {
  id: string;
  status: string;
  requested_at: string;
  deletion_job_id: string;
  auth_provider: string;
  provider_revocation_status: string;
  auth_delete_status: string;
};

async function addPrivacyRequestEvent(
  ctx: MutationCtx,
  requestId: string,
  actorUserId: string | null,
  eventKind: string,
  metadata: Record<string, unknown>,
): Promise<void> {
  await ctx.db.insert("privacy_request_events", {
    id: newUuid(),
    request_id: requestId,
    actor_user_id: actorUserId ?? undefined,
    event_kind: eventKind,
    metadata,
    created_at: nowIso(),
  });
}

function startRow(request: Doc<"privacy_requests">, job: Doc<"account_deletion_jobs">): DeletionStartRow {
  return {
    id: request.id,
    status: request.status,
    requested_at: request.requested_at,
    deletion_job_id: job.id,
    auth_provider: job.auth_provider,
    provider_revocation_status: job.provider_revocation_status,
    auth_delete_status: job.status,
  };
}

function scheduleDrain(ctx: MutationCtx, delayMs: number) {
  return ctx.scheduler.runAfter(Math.max(0, delayMs), internal.accountDeletion.request_account_deletion_drain, {
    p_source: "convex.account_deletion_jobs",
  });
}

async function findActiveDeletionRequest(ctx: ReaderCtx, userId: string): Promise<Doc<"privacy_requests"> | null> {
  const found: Doc<"privacy_requests">[] = [];
  for (const status of ACTIVE_DELETION_STATUSES) {
    found.push(
      ...(await ctx.db
        .query("privacy_requests")
        .withIndex("by_user_id_request_kind_status", (q) =>
          q.eq("user_id", userId).eq("request_kind", "deletion").eq("status", status),
        )
        .collect()),
    );
  }
  found.sort((a, b) => (a.requested_at === b.requested_at ? (a.id < b.id ? -1 : 1) : a.requested_at < b.requested_at ? 1 : -1));
  return found[0] ?? null;
}

/**
 * Port of `internal.request_account_deletion`: the first stage of account
 * deletion. Removes the user's data paths in one transaction and records a job
 * for the final identity deletion. A retry returns the stored tombstone.
 * `providerHint` is the provider named by the caller's session claims.
 */
export async function requestAccountDeletion(
  ctx: MutationCtx,
  userId: string,
  providerHint: AuthProvider,
): Promise<DeletionStartRow[]> {
  const existingJob = await ctx.db
    .query("account_deletion_jobs")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .first();
  if (existingJob) {
    const request = await getByUuid(ctx, "privacy_requests", existingJob.request_id);
    if (!request) {
      return fail("P0001", "account deletion request tombstone is missing");
    }
    return [startRow(request, existingJob)];
  }

  const user = await getByUuid(ctx, "users", userId);
  // Apple wins when both are linked: its grant has a separate revocation duty.
  const providers = [user?.auth_provider, providerHint];
  const resolvedProvider: AuthProvider = providers.includes("apple")
    ? "apple"
    : providers.includes("google")
      ? "google"
      : "unknown";

  const now = nowIso();
  let request = await findActiveDeletionRequest(ctx, userId);
  let createdRequest = false;
  if (!request) {
    const id = newUuid();
    await ctx.db.insert("privacy_requests", {
      id,
      user_id: userId,
      request_kind: "deletion",
      status: "processing",
      requested_at: now,
      verified_at: now,
      visible_status_message: "Your account deletion is in progress.",
      revision: 1,
      created_at: now,
      updated_at: now,
    });
    request = (await getByUuid(ctx, "privacy_requests", id))!;
    createdRequest = true;
  } else {
    await ctx.db.patch(
      request._id,
      withTouch(request, {
        status: "processing" as const,
        verified_at: request.verified_at ?? now,
        visible_status_message: "Your account deletion is in progress.",
      }),
    );
    request = (await getByUuid(ctx, "privacy_requests", request.id))!;
  }

  if (createdRequest) {
    await addPrivacyRequestEvent(ctx, request.id, userId, "deletion_requested", { source: "ios_app" });
  }

  // Reuse the leave transition so the partner gets the same ended notice and cleanup window.
  const activeCouple = await findCurrentCouple(ctx, userId);
  const relationshipEnded = activeCouple
    ? await endRelationshipForPair(ctx, activeCouple.pair_id, userId, "account_deletion")
    : false;

  // An unaccepted invite must not let a deleted identity create a relationship later.
  const invites = await ctx.db
    .query("pairing_invites")
    .withIndex("by_created_by_user_id_status_expires_at", (q) =>
      q.eq("created_by_user_id", userId).eq("status", "pending"),
    )
    .collect();
  for (const invite of invites) {
    await ctx.db.patch(invite._id, withUpdatedAt({ status: "revoked" as const, revoked_at: invite.revoked_at ?? now }));
  }

  // Remove every delivery and location path before the identity job runs.
  const widgetDevices = await ctx.db
    .query("widget_push_devices")
    .withIndex("by_user_id_disabled_at", (q) => q.eq("user_id", userId))
    .collect();
  const userDevices = await ctx.db
    .query("user_devices")
    .withIndex("by_user_id_disabled_at", (q) => q.eq("user_id", userId))
    .collect();
  for (const row of await ctx.db
    .query("widget_push_outbox")
    .withIndex("by_recipient_user_id", (q) => q.eq("recipient_user_id", userId))
    .collect()) {
    await ctx.db.delete(row._id);
  }
  const outboxRows = await ctx.db
    .query("notification_outbox")
    .withIndex("by_recipient_user_id_created_at", (q) => q.eq("recipient_user_id", userId))
    .collect();
  for (const device of userDevices) {
    outboxRows.push(
      ...(await ctx.db
        .query("notification_outbox")
        .withIndex("by_target_device_id", (q) => q.eq("target_device_id", device.id))
        .collect()),
    );
  }
  const deletedOutbox = new Set<string>();
  for (const row of outboxRows) {
    if (!deletedOutbox.has(row._id)) {
      deletedOutbox.add(row._id);
      await ctx.db.delete(row._id);
    }
  }
  for (const device of widgetDevices) await ctx.db.delete(device._id);
  for (const device of userDevices) await ctx.db.delete(device._id);
  for (const row of await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .collect()) {
    await ctx.db.delete(row._id);
  }
  for (const row of await ctx.db
    .query("latest_partner_locations")
    .withIndex("by_user_id_updated_at", (q) => q.eq("user_id", userId))
    .collect()) {
    await ctx.db.delete(row._id);
  }
  for (const row of await ctx.db
    .query("location_sharing_preferences")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .collect()) {
    await ctx.db.delete(row._id);
  }

  // Review and test access must not outlive the account. Purchase ledgers stay as audit records.
  for (const grant of await ctx.db
    .query("entitlement_grants")
    .withIndex("by_user_id_status_expires_at", (q) => q.eq("user_id", userId).eq("status", "active"))
    .collect()) {
    await ctx.db.patch(
      grant._id,
      withUpdatedAt({
        status: "revoked" as const,
        revoked_at: grant.revoked_at ?? now,
        revoked_reason: grant.revoked_reason ?? "account_deleted",
      }),
    );
  }
  for (const session of await ctx.db
    .query("review_access_sessions")
    .withIndex("by_user_id_redeemed_at", (q) => q.eq("user_id", userId))
    .collect()) {
    await ctx.db.patch(session._id, { completed_at: session.completed_at ?? now });
  }

  const profile = await findProfile(ctx, userId);
  if (profile) {
    await updateProfile(ctx, profile, {
      display_name: undefined,
      profile_photo_asset_id: undefined,
      time_zone_id: undefined,
      time_zone_updated_at: undefined,
      onboarding_completed_at: undefined,
      moderation_status: "hidden",
      deleted_at: profile.deleted_at ?? now,
    });
  }

  // Queue abandoned uploads and every profile photo this user owns for storage deletion.
  const assets = await ctx.db
    .query("media_assets")
    .withIndex("by_owner_user_id_created_at", (q) => q.eq("owner_user_id", userId))
    .collect();
  for (const asset of assets) {
    if (
      asset.storage_delete_status !== "deleted" &&
      asset.upload_purpose !== "report_snapshot" &&
      (asset.upload_purpose === "profile_photo" || asset.upload_status !== "finalized")
    ) {
      await ctx.db.patch(
        asset._id,
        withUpdatedAt({
          deleted_at: asset.deleted_at ?? now,
          storage_delete_status: "pending" as const,
          storage_deleted_at: undefined,
          last_storage_delete_error: undefined,
        }),
      );
    }
  }

  const jobId = newUuid();
  await ctx.db.insert("account_deletion_jobs", {
    id: jobId,
    request_id: request.id,
    user_id: userId,
    auth_provider: resolvedProvider,
    status: "ready_for_auth_delete",
    provider_revocation_status: resolvedProvider === "apple" ? "manual_required" : "not_required",
    auth_delete_attempts: 0,
    // A short reservation lets the delete_account action claim the job first.
    next_attempt_at: addMs(now, RESERVATION_MS),
    created_at: now,
    updated_at: now,
  });
  const job = (await getByUuid(ctx, "account_deletion_jobs", jobId))!;

  const hasRemovedEvent = (
    await ctx.db
      .query("privacy_request_events")
      .withIndex("by_request_id_created_at", (q) => q.eq("request_id", request.id))
      .collect()
  ).some((event) => event.event_kind === "account_data_removed");
  if (!hasRemovedEvent) {
    await addPrivacyRequestEvent(ctx, request.id, userId, "account_data_removed", {
      relationship_ended: relationshipEnded,
      auth_provider: resolvedProvider,
      provider_revocation_status: job.provider_revocation_status,
    });
  }

  await scheduleDrain(ctx, RESERVATION_MS);
  return [startRow(request, job)];
}

/** Starts deletion for the Clerk session of the `delete_account` action. */
export const begin_account_deletion = internalMutation({
  args: { clerk_user_id: v.string(), provider_hint: v.optional(authProviderValidator) },
  handler: async (ctx, args): Promise<DeletionStartRow[]> => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_user_id", (q) => q.eq("clerk_user_id", args.clerk_user_id))
      .unique();
    if (!user) {
      return fail("42501", "authenticated user required");
    }
    return await requestAccountDeletion(ctx, user.id, args.provider_hint ?? "unknown");
  },
});

export const claim_account_deletion_jobs = internalMutation({
  args: {
    p_now: v.optional(v.union(v.null(), v.string())),
    p_limit: v.optional(v.number()),
    p_retry_after_seconds: v.optional(v.number()),
    p_max_attempts: v.optional(v.number()),
    p_job_id: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args) => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const limit = args.p_limit ?? 10;
    const retryAfterSeconds = args.p_retry_after_seconds ?? 300;
    const maxAttempts = args.p_max_attempts ?? MAX_AUTH_ATTEMPTS;
    const jobId = optionalUuidArg(args.p_job_id);
    if (!(limit >= 1 && limit <= 100)) fail("23514", "invalid account deletion claim limit");
    if (!(retryAfterSeconds >= 30 && retryAfterSeconds <= 86_400)) {
      fail("23514", "invalid account deletion retry interval");
    }
    if (!(maxAttempts >= 1 && maxAttempts <= 100)) fail("23514", "invalid account deletion max attempts");

    const staleBefore = addMs(now, -retryAfterSeconds * 1000);
    let candidates: Doc<"account_deletion_jobs">[];
    if (jobId) {
      const job = await getByUuid(ctx, "account_deletion_jobs", jobId);
      candidates = job ? [job] : [];
    } else {
      const ready = await ctx.db
        .query("account_deletion_jobs")
        .withIndex("by_status_next_attempt_at", (q) =>
          q.eq("status", "ready_for_auth_delete").lte("next_attempt_at", now),
        )
        .collect();
      const processing = await ctx.db
        .query("account_deletion_jobs")
        .withIndex("by_status_next_attempt_at", (q) => q.eq("status", "processing_auth_delete"))
        .collect();
      candidates = [...ready, ...processing];
    }
    const claimable = candidates
      .filter((job) => {
        if (job.auth_delete_attempts >= maxAttempts) return false;
        if (job.status === "ready_for_auth_delete") {
          return jobId !== undefined || (job.next_attempt_at !== undefined && job.next_attempt_at <= now);
        }
        return job.status === "processing_auth_delete" && job.claimed_at !== undefined && job.claimed_at <= staleBefore;
      })
      .sort((a, b) => {
        const left = a.next_attempt_at ?? "";
        const right = b.next_attempt_at ?? "";
        return left === right ? (a.id < b.id ? -1 : 1) : left < right ? -1 : 1;
      })
      .slice(0, limit);

    const claimed = [];
    for (const job of claimable) {
      await ctx.db.patch(
        job._id,
        withUpdatedAt({
          status: "processing_auth_delete" as const,
          claimed_at: now,
          auth_delete_attempts: job.auth_delete_attempts + 1,
          last_auth_delete_error_code: undefined,
        }),
      );
      const user = await getByUuid(ctx, "users", job.user_id);
      claimed.push({
        job_id: job.id,
        request_id: job.request_id,
        user_id: job.user_id,
        auth_provider: job.auth_provider,
        provider_revocation_status: job.provider_revocation_status,
        auth_delete_attempts: job.auth_delete_attempts + 1,
        // Not in the SQL result. The drain needs it to delete the Clerk user.
        clerk_user_id: user?.clerk_user_id ?? null,
      });
    }
    return claimed;
  },
});

export const mark_account_deletion_auth_failed = internalMutation({
  args: { p_job_id: v.string(), p_error_code: v.string(), p_max_attempts: v.optional(v.number()) },
  handler: async (ctx, args): Promise<boolean> => {
    const jobId = uuidArg(args.p_job_id);
    const maxAttempts = args.p_max_attempts ?? MAX_AUTH_ATTEMPTS;
    if (Array.from(args.p_error_code).length < 1 || Array.from(args.p_error_code).length > 120) {
      fail("23514", "invalid Auth deletion error code");
    }
    const job = await getByUuid(ctx, "account_deletion_jobs", jobId);
    if (!job || job.status !== "processing_auth_delete") {
      return false;
    }
    const exhausted = job.auth_delete_attempts >= maxAttempts;
    const backoffMs = Math.min(6 * 3_600_000, 30_000 * 2 ** Math.min(job.auth_delete_attempts, 10));
    const nextAttemptAt = exhausted ? undefined : addMs(nowIso(), backoffMs);
    await ctx.db.patch(
      job._id,
      withUpdatedAt({
        status: exhausted ? ("attention_required" as const) : ("ready_for_auth_delete" as const),
        next_attempt_at: nextAttemptAt,
        claimed_at: undefined,
        last_auth_delete_error_code: args.p_error_code,
      }),
    );
    await addPrivacyRequestEvent(ctx, job.request_id, null, "auth_delete_failed", {
      error_code: args.p_error_code,
      attempt: job.auth_delete_attempts,
      requires_attention: exhausted,
    });
    if (nextAttemptAt) await scheduleDrain(ctx, backoffMs);
    return true;
  },
});

/**
 * What `ON DELETE CASCADE` from `auth.users` removed once the identity was
 * hard-deleted. The `users` row stays as a tombstone, so an unexpired token
 * cannot provision a fresh account for the same Clerk user. Its email is cleared.
 */
async function removeDeletedUserRows(ctx: MutationCtx, userId: string): Promise<void> {
  const profile = await findProfile(ctx, userId);
  if (profile) {
    await tombstoneReportTargets(ctx, "profile", userId);
    await ctx.db.delete(profile._id);
    await queueOldMediaAssetIfOrphaned(ctx, profile.profile_photo_asset_id, profile.provider_profile_photo_asset_id);
  }
  const rows = [
    ...(await ctx.db.query("app_account_tokens").withIndex("by_user_id", (q) => q.eq("user_id", userId)).collect()),
    ...(await ctx.db
      .query("client_operations")
      .withIndex("by_user_id_created_at", (q) => q.eq("user_id", userId))
      .collect()),
    ...(await ctx.db
      .query("daily_question_shuffles")
      .withIndex("by_user_id_question_id_exclude_until", (q) => q.eq("user_id", userId))
      .collect()),
    ...(await ctx.db.query("review_demo_partners").withIndex("by_user_id", (q) => q.eq("user_id", userId)).collect()),
    ...(await ctx.db.query("thread_read_states").withIndex("by_user_id", (q) => q.eq("user_id", userId)).collect()),
    ...(await ctx.db.query("daily_chat_typing").withIndex("by_user_id", (q) => q.eq("user_id", userId)).collect()),
  ];
  for (const row of rows) await ctx.db.delete(row._id);
  const user = await getByUuid(ctx, "users", userId);
  if (user) {
    await ctx.db.patch(user._id, { email: undefined, claim_display_name: undefined });
  }
}

export const mark_account_deletion_completed = internalMutation({
  args: { p_job_id: v.string() },
  handler: async (ctx, args): Promise<boolean> => {
    const job = await getByUuid(ctx, "account_deletion_jobs", uuidArg(args.p_job_id));
    if (!job) return false;
    if (job.status === "completed") return true;

    const now = nowIso();
    await ctx.db.patch(
      job._id,
      withUpdatedAt({
        status: "completed" as const,
        next_attempt_at: undefined,
        claimed_at: undefined,
        last_auth_delete_error_code: undefined,
        completed_at: now,
      }),
    );
    const request = await getByUuid(ctx, "privacy_requests", job.request_id);
    if (request) {
      await ctx.db.patch(
        request._id,
        withTouch(request, {
          status: "completed" as const,
          completed_at: now,
          cancelled_at: undefined,
          visible_status_message: "Your Paeonia account has been deleted.",
        }),
      );
    }
    await addPrivacyRequestEvent(ctx, job.request_id, null, "auth_user_deleted", {
      attempts: job.auth_delete_attempts,
      provider_revocation_status: job.provider_revocation_status,
    });
    await removeDeletedUserRows(ctx, job.user_id);
    return true;
  },
});

export const mark_account_deletion_provider_result = internalMutation({
  args: { p_job_id: v.string(), p_status: v.string(), p_error_code: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args): Promise<boolean> => {
    const status = args.p_status;
    if (status !== "succeeded" && status !== "manual_required" && status !== "not_required") {
      return fail("23514", "invalid provider revocation status");
    }
    const errorCode = args.p_error_code ?? undefined;
    if (errorCode !== undefined && (Array.from(errorCode).length < 1 || Array.from(errorCode).length > 120)) {
      fail("23514", "invalid provider revocation error code");
    }
    const job = await getByUuid(ctx, "account_deletion_jobs", uuidArg(args.p_job_id));
    if (!job) return false;

    const now = nowIso();
    await ctx.db.patch(
      job._id,
      withUpdatedAt({
        provider_revocation_status: status,
        provider_revocation_attempted_at: now,
        provider_revocation_error_code: errorCode,
        status:
          job.status === "completed"
            ? ("completed" as const)
            : job.status === "processing_auth_delete"
              ? ("processing_auth_delete" as const)
              : ("ready_for_auth_delete" as const),
        next_attempt_at: job.status === "completed" ? undefined : now,
        claimed_at: job.status === "processing_auth_delete" ? job.claimed_at : undefined,
      }),
    );
    const eventKind =
      status === "succeeded"
        ? "provider_revocation_succeeded"
        : status === "not_required"
          ? "provider_revocation_not_required"
          : "provider_revocation_manual_required";
    await addPrivacyRequestEvent(ctx, job.request_id, null, eventKind, {
      provider: job.auth_provider,
      ...(errorCode ? { error_code: errorCode } : {}),
    });
    if (job.status !== "completed") await scheduleDrain(ctx, 0);
    return true;
  },
});

/** Operator retry for a job that ran out of attempts. */
export const retry_account_deletion_job = internalMutation({
  args: { p_job_id: v.string() },
  handler: async (ctx, args): Promise<boolean> => {
    const job = await getByUuid(ctx, "account_deletion_jobs", uuidArg(args.p_job_id));
    if (!job || job.status !== "attention_required") return false;
    // Reset the claim budget so the retry is claimable. Failure events keep the history.
    await ctx.db.patch(
      job._id,
      withUpdatedAt({
        status: "ready_for_auth_delete" as const,
        auth_delete_attempts: 0,
        next_attempt_at: nowIso(),
        claimed_at: undefined,
        last_auth_delete_error_code: undefined,
      }),
    );
    await scheduleDrain(ctx, 0);
    return true;
  },
});

export const has_due_account_deletion_work = internalQuery({
  args: { p_now: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args): Promise<boolean> => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const staleBefore = addMs(now, -5 * 60_000);
    const ready = await ctx.db
      .query("account_deletion_jobs")
      .withIndex("by_status_next_attempt_at", (q) => q.eq("status", "ready_for_auth_delete").lte("next_attempt_at", now))
      .collect();
    if (ready.some((job) => job.next_attempt_at !== undefined)) return true;
    const processing = await ctx.db
      .query("account_deletion_jobs")
      .withIndex("by_status_next_attempt_at", (q) => q.eq("status", "processing_auth_delete"))
      .collect();
    return processing.some((job) => job.claimed_at !== undefined && job.claimed_at <= staleBefore);
  },
});

export type ClaimedDeletionJob = {
  job_id: string;
  user_id: string;
  clerk_user_id: string | null;
};

/** Deletes the Clerk user for a claimed job, then records the result. */
export async function deleteAuthUser(
  ctx: ActionCtx,
  job: ClaimedDeletionJob,
): Promise<{ status: "completed" | "queued"; errorCode?: string }> {
  try {
    if (!job.clerk_user_id) {
      // No Clerk identity was ever linked to this user, so there is nothing to delete.
    } else {
      await deleteClerkUser(job.clerk_user_id);
    }
    await ctx.runMutation(internal.accountDeletion.mark_account_deletion_completed, { p_job_id: job.job_id });
    return { status: "completed" };
  } catch (error) {
    const errorCode = stableAuthDeleteErrorCode(error);
    await ctx.runMutation(internal.accountDeletion.mark_account_deletion_auth_failed, {
      p_job_id: job.job_id,
      p_error_code: errorCode,
      p_max_attempts: MAX_AUTH_ATTEMPTS,
    });
    return { status: "queued", errorCode };
  }
}

async function drainAccountDeletions(ctx: ActionCtx): Promise<{ claimed: number; completed: number; queued: number }> {
  const jobs: ClaimedDeletionJob[] = await ctx.runMutation(internal.accountDeletion.claim_account_deletion_jobs, {
    p_now: nowIso(),
    p_limit: 25,
    p_retry_after_seconds: 300,
    p_max_attempts: MAX_AUTH_ATTEMPTS,
  });
  let completed = 0;
  let queued = 0;
  for (const job of jobs) {
    const result = await deleteAuthUser(ctx, job);
    if (result.status === "completed") completed += 1;
    else queued += 1;
  }
  return { claimed: jobs.length, completed, queued };
}

/** Port of `request_account_deletion_drain`: runs the drain when work is due. Called by the cron and after job writes. */
export const request_account_deletion_drain = internalAction({
  args: { p_source: v.optional(v.string()) },
  handler: async (ctx): Promise<boolean> => {
    if (!(await ctx.runQuery(internal.accountDeletion.has_due_account_deletion_work, {}))) {
      return false;
    }
    await drainAccountDeletions(ctx);
    return true;
  },
});

/** The `delete_account` action body. Returns the Edge Function's 202 response body. */
export type DeleteAccountResponse = {
  ok: true;
  accepted: true;
  requestId: string;
  authDeleteStatus: "completed" | "queued";
  appleRevocation: string;
  requiresManualAppleRevocation: boolean;
  revocationErrorCode?: string;
};

export async function runDeleteAccount(ctx: ActionCtx, appleAuthorizationCode: unknown): Promise<DeleteAccountResponse> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    return fail("http_401", "Invalid session");
  }

  // Clerk session tokens carry no provider claim by default, so ask Clerk which
  // accounts are linked. An Apple link means Apple's revocation duty applies.
  const appleSubjects = await fetchAppleSubjects(identity.subject);
  let start: DeletionStartRow | undefined;
  try {
    [start] = await ctx.runMutation(internal.accountDeletion.begin_account_deletion, {
      clerk_user_id: identity.subject,
      provider_hint: appleSubjects.size > 0 ? "apple" : authProviderFromIdentity(identity),
    });
  } catch {
    return fail("http_500", "Could not start account deletion");
  }
  if (!start?.deletion_job_id) {
    return fail("http_500", "Could not start account deletion");
  }

  // A retry after the identity was already deleted only repeats the stored result.
  if (start.auth_delete_status === "completed") {
    return {
      ok: true,
      accepted: true,
      requestId: start.id,
      authDeleteStatus: "completed",
      appleRevocation: start.auth_provider === "apple" ? start.provider_revocation_status : "not_required",
      requiresManualAppleRevocation: start.auth_provider === "apple" && start.provider_revocation_status === "manual_required",
    };
  }

  // Reserve the job before talking to Apple so the background drain cannot delete the identity first.
  let claimed: ClaimedDeletionJob | null = null;
  try {
    const rows: ClaimedDeletionJob[] = await ctx.runMutation(internal.accountDeletion.claim_account_deletion_jobs, {
      p_now: nowIso(),
      p_limit: 1,
      p_retry_after_seconds: 300,
      p_max_attempts: MAX_AUTH_ATTEMPTS,
      p_job_id: start.deletion_job_id,
    });
    claimed = rows[0] ?? null;
  } catch {
    claimed = null;
  }

  let revocationStatus = start.provider_revocation_status;
  let revocationErrorCode: string | null = null;
  if (start.auth_provider === "apple") {
    const code =
      typeof appleAuthorizationCode === "string" && appleAuthorizationCode.trim().length > 0 &&
      appleAuthorizationCode.trim().length <= 4096
        ? appleAuthorizationCode.trim()
        : null;
    const result = await revokeAppleAuthorization(code, appleSubjects);
    revocationStatus = result.status;
    revocationErrorCode = result.status === "manual_required" ? result.errorCode : null;
    try {
      await ctx.runMutation(internal.accountDeletion.mark_account_deletion_provider_result, {
        p_job_id: start.deletion_job_id,
        p_status: revocationStatus,
        p_error_code: revocationErrorCode,
      });
    } catch {
      revocationStatus = "manual_required";
      revocationErrorCode = "provider_result_not_recorded";
    }
  }

  // Manual Apple revocation never keeps the account alive.
  let authDeleteStatus: "completed" | "queued" = "queued";
  if (claimed) {
    authDeleteStatus = (await deleteAuthUser(ctx, claimed)).status;
  } else {
    try {
      const rows: ClaimedDeletionJob[] = await ctx.runMutation(internal.accountDeletion.claim_account_deletion_jobs, {
        p_now: nowIso(),
        p_limit: 1,
        p_retry_after_seconds: 300,
        p_max_attempts: MAX_AUTH_ATTEMPTS,
        p_job_id: start.deletion_job_id,
      });
      if (rows[0]) authDeleteStatus = (await deleteAuthUser(ctx, rows[0])).status;
    } catch {
      authDeleteStatus = "queued";
    }
  }

  return {
    ok: true,
    accepted: true,
    requestId: start.id,
    authDeleteStatus,
    appleRevocation: start.auth_provider === "apple" ? revocationStatus : "not_required",
    requiresManualAppleRevocation: start.auth_provider === "apple" && revocationStatus === "manual_required",
    ...(revocationErrorCode ? { revocationErrorCode } : {}),
  };
}
