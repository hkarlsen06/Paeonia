import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query, type MutationCtx } from "./_generated/server";
import { findCurrentCouple, findRelationshipPairId, getOrCreateRelationshipPair, hasActiveRelationshipBlock } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { hmacSha256Hex } from "./lib/crypto";
import { getByUuid, orNull, type ReaderCtx, withUpdatedAt } from "./lib/db";
import { fail, uniqueViolation } from "./lib/errors";
import { newUuid, optionalDateArg, optionalTimestampArg, optionalUuidArg, timestampArg, uuidArg } from "./lib/ids";
import { materializeFirstDayDrafts } from "./lib/firstDay";
import { enqueueNotificationForUser } from "./lib/notifications";
import { findActiveReviewAccessCode, redeemReviewAccess } from "./lib/reviewAccess";
import { userHasDirectEntitlement } from "./lib/entitlements";
import { createRelationshipSyncEvent } from "./lib/syncEvents";
import { consumeRateLimit, rateLimiter } from "./lib/rateLimits";
import { addDaysToInstant, nowIso } from "./lib/time";
import { signMediaUrl } from "./media";

const CODE_PATTERN = /^[0-9ABCDEFGHJKMNPQRSTVWXYZ]{6}$/;

/**
 * Port of `internal.hash_pairing_invite_code`: HMAC-SHA256 of the six-character
 * code with the `INVITE_CODE_PEPPER` environment variable, as lowercase hex.
 */
export async function hashPairingInviteCode(code: string | null | undefined): Promise<string> {
  if (code === null || code === undefined || !CODE_PATTERN.test(code)) {
    return fail("23514", "invalid invite code");
  }
  const pepper = process.env.INVITE_CODE_PEPPER;
  if (!pepper) {
    return fail("22023", "invite code pepper is not configured");
  }
  return await hmacSha256Hex(pepper, code);
}

/**
 * Port of `internal.assert_pairing_invite_attempt_allowed`. The SQL counted
 * logged attempts in a ten-minute window. The rate limiter keeps the same budget:
 * `recordAttempt` takes from it where the SQL logged a row.
 */
async function assertPairingInviteAttemptAllowed(ctx: MutationCtx, userId: string, codeHashPrefix: string): Promise<void> {
  if (!(await rateLimiter.check(ctx, "pairingInviteAttempt", { key: userId })).ok) {
    fail("53300", "too many invite attempts");
  }
  if (!(await rateLimiter.check(ctx, "pairingInviteCodeFailure", { key: codeFailureKey(userId, codeHashPrefix) })).ok) {
    fail("53300", "too many invite attempts for this code");
  }
}

/** Only failed attempts count toward the limit for one code. */
async function recordAttempt(ctx: MutationCtx, userId: string, codeHashPrefix: string, success: boolean): Promise<void> {
  await rateLimiter.limit(ctx, "pairingInviteAttempt", { key: userId });
  if (!success) {
    await rateLimiter.limit(ctx, "pairingInviteCodeFailure", { key: codeFailureKey(userId, codeHashPrefix) });
  }
}

function codeFailureKey(userId: string, codeHashPrefix: string): string {
  return `${userId}:${codeHashPrefix}`;
}

async function findInviteByCodeHash(ctx: ReaderCtx, codeHash: string): Promise<Doc<"pairing_invites"> | null> {
  const secret = await ctx.db
    .query("pairing_invite_secrets")
    .withIndex("by_code_hash", (q) => q.eq("code_hash", codeHash))
    .unique();
  return secret ? await getByUuid(ctx, "pairing_invites", secret.invite_id) : null;
}

async function hasActiveCouple(ctx: ReaderCtx, userId: string): Promise<boolean> {
  return (await findCurrentCouple(ctx, userId)) !== null;
}

function checkExpiry(expiresAt: string): void {
  const now = nowIso();
  if (expiresAt <= now || expiresAt > addDaysToInstant(now, 30)) {
    fail("23514", "invite expiration is out of range");
  }
}

async function insertInvite(
  ctx: MutationCtx,
  userId: string,
  codeHash: string,
  expiresAt: string,
): Promise<string> {
  const id = newUuid();
  const now = nowIso();
  const taken = await ctx.db
    .query("pairing_invite_secrets")
    .withIndex("by_code_hash", (q) => q.eq("code_hash", codeHash))
    .first();
  if (taken) {
    uniqueViolation("pairing_invite_secrets_code_hash_unique");
  }
  await ctx.db.insert("pairing_invites", {
    id,
    created_by_user_id: userId,
    status: "pending",
    expires_at: expiresAt,
    created_at: now,
    updated_at: now,
  });
  await ctx.db.insert("pairing_invite_secrets", { invite_id: id, code_hash: codeHash, created_at: now });
  return id;
}

const expiresAtArg = v.optional(v.union(v.null(), v.string()));

function expiresAtOrDefault(value: string | null | undefined): string {
  return value === null || value === undefined ? addDaysToInstant(nowIso(), 7) : timestampArg(value);
}

export const create_pairing_invite = mutation({
  args: { p_invite_code: v.string(), ...clientOperationArgs, p_expires_at: expiresAtArg },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const codeHash = await hashPairingInviteCode(args.p_invite_code);
    const expiresAt = expiresAtOrDefault(args.p_expires_at);
    const input = toClientOperation(args, {
      kind: "create_pairing_invite",
      scope: "pairing_invites",
      // A missing expiry defaults to now + 7 days, which differs per call. Hash a marker so a retry matches.
      request: { kind: "create_pairing_invite", code_hash: codeHash, expires_at: args.p_expires_at ?? "default" },
    });
    const outcome = await runClientOperation(ctx, userId, input, async () => {
      await consumeRateLimit(ctx, "pairingInviteCreate", userId);
      checkExpiry(expiresAt);
      if (!(await userHasDirectEntitlement(ctx, userId))) {
        fail("42501", "direct entitlement is required to create an invite");
      }
      if (await hasActiveCouple(ctx, userId)) {
        fail("23505", "user already has an active couple");
      }
      return { invite_id: await insertInvite(ctx, userId, codeHash, expiresAt) };
    });
    return outcome.invite_id;
  },
});

export const rotate_pairing_invite = mutation({
  args: {
    p_current_invite_id: v.union(v.null(), v.string()),
    p_invite_code: v.string(),
    ...clientOperationArgs,
    p_expires_at: expiresAtArg,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (args.p_current_invite_id === null) {
      fail("23514", "current invite id is required");
    }
    const currentInviteId = uuidArg(args.p_current_invite_id);
    const codeHash = await hashPairingInviteCode(args.p_invite_code);
    const expiresAt = expiresAtOrDefault(args.p_expires_at);
    const input = toClientOperation(args, {
      kind: "rotate_pairing_invite",
      scope: "pairing_invites",
      request: {
        kind: "rotate_pairing_invite",
        current_invite_id: currentInviteId,
        code_hash: codeHash,
        expires_at: args.p_expires_at ?? "default",
      },
    });
    const outcome = await runClientOperation(ctx, userId, input, async () => {
      await consumeRateLimit(ctx, "pairingInviteCreate", userId);
      checkExpiry(expiresAt);
      if (!(await userHasDirectEntitlement(ctx, userId))) {
        fail("42501", "direct entitlement is required to create an invite");
      }
      const current = await getByUuid(ctx, "pairing_invites", currentInviteId);
      if (!current || current.created_by_user_id !== userId) {
        fail("22023", "current invite is not available");
      }
      if (await hasActiveCouple(ctx, userId)) {
        fail("23505", "user already has an active couple");
      }
      const newInviteId = await insertInvite(ctx, userId, codeHash, expiresAt);
      if (current.status === "pending") {
        await ctx.db.patch(current._id, withUpdatedAt({ status: "revoked" as const, revoked_at: current.revoked_at ?? nowIso() }));
      }
      return { invite_id: newInviteId };
    });
    return outcome.invite_id;
  },
});

export const revoke_pairing_invite = mutation({
  args: { p_invite_id: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const inviteId = optionalUuidArg(args.p_invite_id);
    const invite = await getByUuid(ctx, "pairing_invites", inviteId);
    if (!invite || invite.created_by_user_id !== userId || invite.status !== "pending") {
      return false;
    }
    await ctx.db.patch(invite._id, withUpdatedAt({ status: "revoked" as const, revoked_at: nowIso() }));
    return true;
  },
});

export const validate_my_pairing_invite = query({
  args: { p_invite_id: v.union(v.null(), v.string()), p_invite_code: v.union(v.null(), v.string()) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const notFound = [{ invite_id: null, status: "not_found", expires_at: null }];
    if (args.p_invite_id === null || args.p_invite_code === null || args.p_invite_code.replace(/^ +| +$/g, "") === "") {
      return notFound;
    }
    const inviteId = uuidArg(args.p_invite_id);
    const codeHash = await hashPairingInviteCode(args.p_invite_code);
    const invite = await getByUuid(ctx, "pairing_invites", inviteId);
    const secret = invite
      ? await ctx.db
          .query("pairing_invite_secrets")
          .withIndex("by_invite_id", (q) => q.eq("invite_id", inviteId))
          .collect()
      : [];
    if (!invite || invite.created_by_user_id !== userId || !secret.some((row) => row.code_hash === codeHash)) {
      return notFound;
    }
    // Read-only: the hourly expire_stale_pairing_invites cron persists the status.
    const status = invite.status === "pending" && invite.expires_at <= nowIso() ? "expired" : invite.status;
    return [{ invite_id: invite.id, status, expires_at: invite.expires_at }];
  },
});

/** A 15 minute link to the visible profile photo the app shows for this person, or null. */
async function profilePhotoUrl(ctx: ReaderCtx, profile: Doc<"profiles"> | null): Promise<string | null> {
  if (!profile || profile.moderation_status !== "visible" || profile.deleted_at !== undefined) return null;
  const asset = await getByUuid(ctx, "media_assets", profile.profile_photo_asset_id ?? profile.provider_profile_photo_asset_id);
  if (
    !asset ||
    asset.upload_status !== "finalized" ||
    asset.storage_delete_status !== "none" ||
    asset.moderation_status !== "visible" ||
    asset.deleted_at !== undefined
  ) {
    return null;
  }
  return await signMediaUrl(asset.id, Math.floor(Date.now() / 1000) + 900);
}

export const preview_pairing_invite = mutation({
  args: { p_invite_code: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const now = nowIso();

    // App Review demo codes bypass invites.
    const reviewCode = await findActiveReviewAccessCode(ctx, args.p_invite_code);
    if (reviewCode) {
      const partner = reviewCode.seeded_partner_user_id
        ? await ctx.db
            .query("profiles")
            .withIndex("by_user_id", (q) => q.eq("user_id", reviewCode.seeded_partner_user_id!))
            .unique()
        : null;
      return [
        {
          invite_id: reviewCode.id,
          inviter_user_id: orNull(reviewCode.seeded_partner_user_id),
          inviter_display_name: partner?.moderation_status === "visible" ? orNull(partner.display_name) : null,
          inviter_photo_url: await profilePhotoUrl(ctx, partner),
          expires_at: reviewCode.expires_at ?? addDaysToInstant(now, 1),
          has_safety_warning: false,
        },
      ];
    }

    const codeHash = await hashPairingInviteCode(args.p_invite_code);
    const prefix = codeHash.slice(0, 12);
    await assertPairingInviteAttemptAllowed(ctx, userId, prefix);

    const invite = await findInviteByCodeHash(ctx, codeHash);
    if (!invite || invite.status !== "pending" || invite.expires_at <= now) {
      await recordAttempt(ctx, userId, prefix, false);
      return [];
    }

    const pairId = await findRelationshipPairId(ctx, userId, invite.created_by_user_id);
    if (pairId && (await hasActiveRelationshipBlock(ctx, pairId))) {
      await recordAttempt(ctx, userId, prefix, false);
      return [];
    }
    await recordAttempt(ctx, userId, prefix, true);

    const inviter = await ctx.db
      .query("profiles")
      .withIndex("by_user_id", (q) => q.eq("user_id", invite.created_by_user_id))
      .unique();
    const flagged = pairId
      ? (await ctx.db
          .query("pair_safety_warning_flags")
          .withIndex("by_pair_id_created_at", (q) => q.eq("pair_id", pairId))
          .first()) !== null
      : false;
    return [
      {
        invite_id: invite.id,
        inviter_user_id: invite.created_by_user_id,
        inviter_display_name: inviter?.moderation_status === "visible" ? orNull(inviter.display_name) : null,
        inviter_photo_url: await profilePhotoUrl(ctx, inviter),
        expires_at: invite.expires_at,
        has_safety_warning: flagged,
      },
    ];
  },
});

export const accept_pairing_invite = mutation({
  args: { p_invite_code: v.string(), ...clientOperationArgs, p_started_on: v.optional(v.union(v.null(), v.string())) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);

    const reviewCode = await findActiveReviewAccessCode(ctx, args.p_invite_code);
    if (reviewCode) {
      return await redeemReviewAccess(ctx, reviewCode.id, userId);
    }

    const codeHash = await hashPairingInviteCode(args.p_invite_code);
    const prefix = codeHash.slice(0, 12);
    await assertPairingInviteAttemptAllowed(ctx, userId, prefix);
    const startedOn = optionalDateArg(args.p_started_on);

    const input = toClientOperation(args, {
      kind: "accept_pairing_invite",
      scope: "pairing_invites",
      request: { kind: "accept_pairing_invite", code_hash: codeHash, started_on: startedOn ?? "unset" },
    });
    // The SQL logged each rejected attempt and then raised, which rolled the log back.
    // The throws below roll back the rate limiter the same way, so only accepted attempts count.
    const outcome = await runClientOperation(ctx, userId, input, async () => {
      const invite = await findInviteByCodeHash(ctx, codeHash);
      if (!invite) fail("22023", "pairing invite is not available");
      if (invite.created_by_user_id === userId) fail("23514", "users cannot accept their own invite");
      if (invite.status !== "pending") fail("22023", "pairing invite is not pending");
      if (invite.expires_at <= nowIso()) fail("22023", "pairing invite is expired");
      if ((await hasActiveCouple(ctx, userId)) || (await hasActiveCouple(ctx, invite.created_by_user_id))) {
        fail("23505", "one of the users already has an active couple");
      }

      const pairId = await getOrCreateRelationshipPair(ctx, invite.created_by_user_id, userId);
      if (await hasActiveRelationshipBlock(ctx, pairId)) {
        fail("42501", "pairing is blocked for this pair");
      }

      const now = nowIso();
      const coupleId = newUuid();
      await ctx.db.insert("couples", {
        id: coupleId,
        pair_id: pairId,
        status: "active",
        started_on: startedOn,
        created_by_user_id: invite.created_by_user_id,
        created_at: now,
        updated_at: now,
      });
      for (const [memberId, role] of [
        [invite.created_by_user_id, "creator"],
        [userId, "partner"],
      ] as const) {
        await ctx.db.insert("couple_members", {
          couple_id: coupleId,
          user_id: memberId,
          role,
          status: "active",
          joined_at: now,
          updated_at: now,
        });
      }
      await ctx.db.patch(
        invite._id,
        withUpdatedAt({
          status: "accepted" as const,
          accepted_by_user_id: userId,
          accepted_at: now,
          couple_id: coupleId,
        }),
      );
      await materializeFirstDayDrafts(ctx, { coupleId, creatorUserId: invite.created_by_user_id, partnerUserId: userId });
      for (const memberId of [invite.created_by_user_id, userId]) {
        await createRelationshipSyncEvent(ctx, {
          user_id: memberId,
          couple_id: coupleId,
          initiated_by_user_id: userId,
          event_kind: "relationship_started",
          reason: "pairing_invite_accepted",
          relationship_status: "active",
          member_status: "active",
          local_purge_scope: { relationship: "refresh", entitlement: "refresh" },
        });
      }
      await enqueueNotificationForUser(ctx, {
        recipient_user_id: invite.created_by_user_id,
        kind: "partner_joined",
        payload: {
          type: "partner_joined",
          couple_id: coupleId,
          actor_user_id: userId,
          route: "home",
          deeplink: "paeonia://home",
        },
        dedupe_key: `partner_joined:${coupleId}`,
        redaction_level: "private",
        apns_push_type: "alert",
        apns_collapse_id: `partner_joined:${coupleId}`,
      });
      await recordAttempt(ctx, userId, prefix, true);
      return { couple_id: coupleId };
    });
    return outcome.couple_id;
  },
});

// ---- cleanup (operator and cron) ----

/** Pairing half of `internal.expire_stale_invites_and_review_codes`. The review code half lives in the access module. */
export const expire_stale_pairing_invites = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())), p_limit: v.optional(v.number()) },
  handler: async (ctx, args): Promise<number> => {
    const now = optionalTimestampArg(args.p_now) ?? nowIso();
    const limit = args.p_limit ?? 500;
    if (!Number.isInteger(limit) || limit < 1 || limit > 5000) {
      return fail("23514", "expiry limit is out of range");
    }
    const stale = await ctx.db
      .query("pairing_invites")
      .withIndex("by_status_expires_at", (q) => q.eq("status", "pending").lte("expires_at", now))
      .take(limit);
    for (const invite of stale) {
      await ctx.db.patch(invite._id, withUpdatedAt({ status: "expired" as const }));
    }
    return stale.length;
  },
});
