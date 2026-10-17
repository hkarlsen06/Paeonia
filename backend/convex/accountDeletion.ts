import { vOnCompleteArgs } from "@convex-dev/workpool";
import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalAction, internalMutation, internalQuery, type ActionCtx, type MutationCtx } from "./_generated/server";
import { findCurrentCouple } from "./lib/access";
import { authProviderFromIdentity } from "./lib/auth";
import { backgroundWorkpool } from "./lib/backgroundWorkpool";
import { getByUuid, withTouch, withUpdatedAt, type ReaderCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { newUuid, uuidArg } from "./lib/ids";
import { deleteFirstDayDraft } from "./lib/firstDay";
import { queueOldMediaAssetIfOrphaned } from "./lib/mediaOrphans";
import {
  deleteAnalyticsPerson,
  deleteClerkUser,
  fetchAppleSubjects,
  revokeAppleAuthorization,
  stableAuthDeleteErrorCode,
} from "./lib/accountDeletionProviders";
import { removePresenceRooms } from "./lib/presence";
import { findProfile, updateProfile } from "./lib/profiles";
import { endRelationshipForPair } from "./lib/relationshipEnd";
import { tombstoneReportTargets } from "./lib/reports";
import { nowIso } from "./lib/time";
import { authProvider as authProviderValidator } from "./lib/validators";

type AuthProvider = "apple" | "google" | "unknown";

// `delete_account` deletes the Clerk user itself right after the Apple step,
// which can take 30 seconds. The queued job starts later, so it rarely runs
// alongside. A run alongside is harmless, because both steps are idempotent.
const QUEUED_AUTH_DELETE_DELAY_MS = 60_000;
// 10 tries over about 8.5 hours, then the job needs an operator.
const AUTH_DELETE_RETRY = { maxAttempts: 10, initialBackoffMs: 60_000, base: 2 };
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

/** Queues the Clerk delete on `backgroundWorkpool`. `auth_delete_finished` records a job that ran out of tries. */
function enqueueAuthDelete(ctx: MutationCtx, jobId: string, runAfter: number) {
  return backgroundWorkpool.enqueueAction(
    ctx,
    internal.accountDeletion.delete_auth_user,
    { p_job_id: jobId },
    {
      runAfter,
      retry: AUTH_DELETE_RETRY,
      onComplete: internal.accountDeletion.auth_delete_finished,
      context: { job_id: jobId },
    },
  );
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
  await deleteFirstDayDraft(ctx, userId);

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

  await enqueueAuthDelete(ctx, jobId, QUEUED_AUTH_DELETE_DELAY_MS);
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

/** The Clerk user and Paeonia user a job still has to delete. Null once the job completed. */
export const get_auth_delete_target = internalQuery({
  args: { p_job_id: v.string() },
  handler: async (ctx, args): Promise<{ clerk_user_id: string | null; user_id: string } | null> => {
    const job = await getByUuid(ctx, "account_deletion_jobs", uuidArg(args.p_job_id));
    if (!job || job.status === "completed") return null;
    const user = await getByUuid(ctx, "users", job.user_id);
    return { clerk_user_id: user?.clerk_user_id ?? null, user_id: job.user_id };
  },
});

/** Records one failed Clerk delete. The job keeps its status while tries remain. */
export const mark_account_deletion_auth_failed = internalMutation({
  args: { p_job_id: v.string(), p_error_code: v.string() },
  handler: async (ctx, args): Promise<boolean> => {
    if (Array.from(args.p_error_code).length < 1 || Array.from(args.p_error_code).length > 120) {
      fail("23514", "invalid Auth deletion error code");
    }
    const job = await getByUuid(ctx, "account_deletion_jobs", uuidArg(args.p_job_id));
    if (!job || job.status === "completed") return false;
    await ctx.db.patch(job._id, withUpdatedAt({ last_auth_delete_error_code: args.p_error_code }));
    await addPrivacyRequestEvent(ctx, job.request_id, null, "auth_delete_failed", {
      error_code: args.p_error_code,
      requires_attention: false,
    });
    return true;
  },
});

/**
 * The pool calls this when a Clerk delete job ends. A job that failed every try, or whose pool
 * job was canceled, becomes `attention_required`, so an operator sees it and can retry it.
 */
export const auth_delete_finished = internalMutation({
  args: vOnCompleteArgs(v.object({ job_id: v.string() })),
  handler: async (ctx, { context, result }) => {
    if (result.kind === "success") return;
    const job = await getByUuid(ctx, "account_deletion_jobs", context.job_id);
    if (!job || job.status !== "ready_for_auth_delete") return;
    const errorCode =
      result.kind === "canceled" ? "auth_delete_canceled" : (job.last_auth_delete_error_code ?? "auth_delete_unexpected");
    await ctx.db.patch(
      job._id,
      withUpdatedAt({ status: "attention_required" as const, last_auth_delete_error_code: errorCode }),
    );
    await addPrivacyRequestEvent(ctx, job.request_id, null, "auth_delete_failed", {
      error_code: errorCode,
      requires_attention: true,
    });
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
      .query("daily_question_shuffles")
      .withIndex("by_user_id_question_id_exclude_until", (q) => q.eq("user_id", userId))
      .collect()),
    ...(await ctx.db.query("review_demo_partners").withIndex("by_user_id", (q) => q.eq("user_id", userId)).collect()),
    ...(await ctx.db.query("thread_read_states").withIndex("by_user_id", (q) => q.eq("user_id", userId)).collect()),
    ...(await ctx.db
      .query("daily_answer_seen_states")
      .withIndex("by_user_id", (q) => q.eq("user_id", userId))
      .collect()),
  ];
  for (const row of rows) await ctx.db.delete(row._id);
  await ctx.scheduler.runAfter(0, internal.retention.delete_user_client_operations, { p_user_id: userId });
  // Ending the relationship already removed the couple's presence rooms. This clears any left.
  await removePresenceRooms(ctx, [userId], "");
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
    return true;
  },
});

/** Operator retry for a job that ran out of tries. Queues a fresh set of tries. */
export const retry_account_deletion_job = internalMutation({
  args: { p_job_id: v.string() },
  handler: async (ctx, args): Promise<boolean> => {
    const job = await getByUuid(ctx, "account_deletion_jobs", uuidArg(args.p_job_id));
    if (!job || job.status !== "attention_required") return false;
    // Failure events keep the history.
    await ctx.db.patch(
      job._id,
      withUpdatedAt({ status: "ready_for_auth_delete" as const, last_auth_delete_error_code: undefined }),
    );
    await enqueueAuthDelete(ctx, job.id, 0);
    return true;
  },
});

/**
 * Deletes the Clerk user of a job that has not completed and asks PostHog to
 * delete the person's usage statistics, then marks the job completed. Records
 * a failure and throws it, so the pool can try again. Both calls are safe to
 * repeat: Clerk treats a missing user as deleted.
 */
async function deleteAuthUser(ctx: ActionCtx, jobId: string): Promise<void> {
  const target = await ctx.runQuery(internal.accountDeletion.get_auth_delete_target, { p_job_id: jobId });
  if (!target) return;
  try {
    // A user without a Clerk identity has nothing to delete there.
    if (target.clerk_user_id) {
      await deleteClerkUser(target.clerk_user_id);
    }
    // The app identifies people to PostHog by their Paeonia user id.
    await deleteAnalyticsPerson(target.user_id);
  } catch (error) {
    const errorCode = stableAuthDeleteErrorCode(error);
    await ctx.runMutation(internal.accountDeletion.mark_account_deletion_auth_failed, {
      p_job_id: jobId,
      p_error_code: errorCode,
    });
    throw new Error(errorCode);
  }
  await ctx.runMutation(internal.accountDeletion.mark_account_deletion_completed, { p_job_id: jobId });
}

/** The `backgroundWorkpool` job queued by `requestAccountDeletion` and `retry_account_deletion_job`. */
export const delete_auth_user = internalAction({
  args: { p_job_id: v.string() },
  handler: async (ctx, args): Promise<null> => {
    await deleteAuthUser(ctx, args.p_job_id);
    return null;
  },
});

/** The `delete_account` action result. */
export type DeleteAccountResponse = {
  requestId: string;
  authDeleteStatus: "completed" | "queued";
  appleRevocation: string;
  requiresManualAppleRevocation: boolean;
  revocationErrorCode?: string;
};

export async function runDeleteAccount(
  ctx: ActionCtx,
  appleAuthorizationCode: string | null | undefined,
): Promise<DeleteAccountResponse> {
  const identity = await ctx.auth.getUserIdentity();
  if (!identity) {
    return fail("not_signed_in", "Invalid session");
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
    return fail("account_deletion_failed", "Could not start account deletion");
  }
  if (!start?.deletion_job_id) {
    return fail("account_deletion_failed", "Could not start account deletion");
  }

  // A retry after the identity was already deleted only repeats the stored result.
  if (start.auth_delete_status === "completed") {
    return {
      requestId: start.id,
      authDeleteStatus: "completed",
      appleRevocation: start.auth_provider === "apple" ? start.provider_revocation_status : "not_required",
      requiresManualAppleRevocation: start.auth_provider === "apple" && start.provider_revocation_status === "manual_required",
    };
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
  try {
    await deleteAuthUser(ctx, start.deletion_job_id);
    authDeleteStatus = "completed";
  } catch {
    // The job that requestAccountDeletion queued keeps trying.
  }

  return {
    requestId: start.id,
    authDeleteStatus,
    appleRevocation: start.auth_provider === "apple" ? revocationStatus : "not_required",
    requiresManualAppleRevocation: start.auth_provider === "apple" && revocationStatus === "manual_required",
    ...(revocationErrorCode ? { revocationErrorCode } : {}),
  };
}
