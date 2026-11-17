import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation, query, type MutationCtx } from "./_generated/server";
import { findCurrentCouple, findRelationshipPairId, getOrCreateRelationshipPair, hasActiveRelationshipBlock } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { hmacSha256Hex } from "./lib/crypto";
import { getByUuid, type ReaderCtx, withUpdatedAt } from "./lib/db";
import { fail, uniqueViolation } from "./lib/errors";
import { newUuid, optionalDateArg, optionalTimestampArg, timestampArg, uuidArg } from "./lib/ids";
import { materializeFirstDayDrafts } from "./lib/firstDay";
import { enqueueNotificationForUser } from "./lib/notifications";
import { findActiveReviewAccessCode, redeemReviewAccess } from "./lib/reviewAccess";
import { userHasDirectEntitlement } from "./lib/entitlements";
import { createRelationshipSyncEvent } from "./lib/syncEvents";
import { consumeRateLimit, rateLimiter } from "./lib/rateLimits";
import { addDaysToInstant, nowIso } from "./lib/time";
import { signMediaUrl } from "./media";
import { isUsableMediaAsset } from "./lib/mediaAssetState";
import { findRestorableCouple, reopenCouple, standingRestoreRequest } from "./lib/relationshipRestore";

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

/** How long an invite lasts. The app asks for this, and it is the default when the app names no expiry. */
const INVITE_DAYS = 30;
/**
 * The latest expiry the server accepts. The extra day leaves room for a phone clock that runs ahead
 * and for a daylight saving change inside the app's 30 calendar days.
 */
const MAX_INVITE_DAYS = INVITE_DAYS + 1;

function checkExpiry(expiresAt: string): void {
  const now = nowIso();
  if (expiresAt <= now || expiresAt > addDaysToInstant(now, MAX_INVITE_DAYS)) {
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
  return value === null || value === undefined ? addDaysToInstant(nowIso(), INVITE_DAYS) : timestampArg(value);
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
      // A missing expiry defaults to now + 30 days, which differs per call. Hash a marker so a retry matches.
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
    !isUsableMediaAsset(asset)
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
          inviter_user_id: reviewCode.seeded_partner_user_id ?? null,
          inviter_display_name: partner?.moderation_status === "visible" ? partner.display_name ?? null : null,
          inviter_photo_url: await profilePhotoUrl(ctx, partner),
          expires_at: reviewCode.expires_at ?? addDaysToInstant(now, 1),
          has_safety_warning: false,
          can_restore: false,
          restore_requested: false,
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
    if ((pairId && (await hasActiveRelationshipBlock(ctx, pairId))) || (await reservedForSomeoneElse(ctx, invite, userId))) {
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
    // Only the two people of the ended couple ever learn that it can come back.
    const canRestore = pairId !== null && (await findRestorableCouple(ctx, pairId, now)) !== null;
    return [
      {
        invite_id: invite.id,
        inviter_user_id: invite.created_by_user_id,
        inviter_display_name: inviter?.moderation_status === "visible" ? inviter.display_name ?? null : null,
        inviter_photo_url: await profilePhotoUrl(ctx, inviter),
        expires_at: invite.expires_at,
        has_safety_warning: flagged,
        can_restore: canRestore,
        // This person already asked, so the app shows that they are waiting for the answer.
        restore_requested: canRestore && invite.restore_requested_by_user_id === userId,
      },
    ];
  },
});

/**
 * Pairs the invite's creator with `joinerUserId` in a new couple and uses up the invite. The
 * caller has checked the invite and that neither person has a couple.
 */
async function pairAsNewCouple(
  ctx: MutationCtx,
  invite: Doc<"pairing_invites">,
  pairId: string,
  joinerUserId: string,
  startedOn: string | undefined,
): Promise<string> {
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
    [joinerUserId, "partner"],
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
  await markInviteAccepted(ctx, invite, joinerUserId, coupleId);
  await materializeFirstDayDrafts(ctx, { coupleId, creatorUserId: invite.created_by_user_id, partnerUserId: joinerUserId });
  for (const memberId of [invite.created_by_user_id, joinerUserId]) {
    await createRelationshipSyncEvent(ctx, {
      user_id: memberId,
      couple_id: coupleId,
      initiated_by_user_id: joinerUserId,
      event_kind: "relationship_started",
      reason: "pairing_invite_accepted",
      relationship_status: "active",
      member_status: "active",
      local_purge_scope: { relationship: "refresh", entitlement: "refresh" },
    });
  }
  return coupleId;
}

async function markInviteAccepted(
  ctx: MutationCtx,
  invite: Doc<"pairing_invites">,
  joinerUserId: string,
  coupleId: string,
): Promise<void> {
  await ctx.db.patch(
    invite._id,
    withUpdatedAt({
      status: "accepted" as const,
      accepted_by_user_id: joinerUserId,
      accepted_at: nowIso(),
      couple_id: coupleId,
    }),
  );
}

/**
 * The couple an accepted invite made for `joinerUserId`, while it is still active. A retry of a
 * join that already went through, or a "start fresh" that lost the race to the creator's answer,
 * gets it instead of an error.
 */
async function coupleJoinedThrough(
  ctx: ReaderCtx,
  invite: Doc<"pairing_invites">,
  joinerUserId: string,
): Promise<Doc<"couples"> | null> {
  if (invite.status !== "accepted" || invite.accepted_by_user_id !== joinerUserId) return null;
  const couple = await getByUuid(ctx, "couples", invite.couple_id);
  return couple?.status === "active" ? couple : null;
}

/**
 * Joins the partner's invite. With `p_restore`, the joiner asks to bring back the ended
 * relationship of the two (see `lib/relationshipRestore.ts`). When that can happen, the invite
 * stays pending, its creator is asked, and this returns null. When it can't, the two pair as new,
 * the same as without `p_restore`, and nobody is told why.
 */
export const accept_pairing_invite = mutation({
  args: {
    p_invite_code: v.string(),
    ...clientOperationArgs,
    p_started_on: v.optional(v.union(v.null(), v.string())),
    p_restore: v.optional(v.boolean()),
  },
  handler: async (ctx, args): Promise<string | null> => {
    const userId = await requireUserId(ctx);

    const reviewCode = await findActiveReviewAccessCode(ctx, args.p_invite_code);
    if (reviewCode) {
      return await redeemReviewAccess(ctx, reviewCode.id, userId);
    }

    const codeHash = await hashPairingInviteCode(args.p_invite_code);
    const prefix = codeHash.slice(0, 12);
    await assertPairingInviteAttemptAllowed(ctx, userId, prefix);
    const startedOn = optionalDateArg(args.p_started_on);
    const restore = args.p_restore === true;

    const input = toClientOperation(args, {
      kind: "accept_pairing_invite",
      scope: "pairing_invites",
      request: { kind: "accept_pairing_invite", code_hash: codeHash, started_on: startedOn ?? "unset", restore },
    });
    // The SQL logged each rejected attempt and then raised, which rolled the log back.
    // The throws below roll back the rate limiter the same way, so only accepted attempts count.
    const outcome = await runClientOperation(ctx, userId, input, async () => {
      const invite = await findInviteByCodeHash(ctx, codeHash);
      if (!invite) fail("22023", "pairing invite is not available");
      if (invite.created_by_user_id === userId) fail("23514", "users cannot accept their own invite");
      const joined = await coupleJoinedThrough(ctx, invite, userId);
      if (joined) return { couple_id: joined.id };
      if (invite.status !== "pending") fail("22023", "pairing invite is not pending");
      if (invite.expires_at <= nowIso()) fail("22023", "pairing invite is expired");
      if (await reservedForSomeoneElse(ctx, invite, userId)) fail("22023", "pairing invite is not available");
      if ((await hasActiveCouple(ctx, userId)) || (await hasActiveCouple(ctx, invite.created_by_user_id))) {
        fail("23505", "one of the users already has an active couple");
      }

      const pairId = await getOrCreateRelationshipPair(ctx, invite.created_by_user_id, userId);
      if (await hasActiveRelationshipBlock(ctx, pairId)) {
        fail("42501", "pairing is blocked for this pair");
      }

      if (restore && (await findRestorableCouple(ctx, pairId, nowIso()))) {
        await askToRestore(ctx, invite, userId);
        await recordAttempt(ctx, userId, prefix, true);
        return { couple_id: null };
      }

      const coupleId = await pairAsNewCouple(ctx, invite, pairId, userId, startedOn);
      await enqueueNotificationForUser(ctx, {
        recipient_user_id: invite.created_by_user_id,
        kind: "partner_joined",
        payload: {
          type: "partner_joined",
          couple_id: coupleId,
          actor_user_id: userId,
          route: "us",
          deeplink: "paeonia://us",
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

/**
 * True while someone other than `userId` asked to bring their relationship back through this invite
 * and the request still stands. The creator may already be looking at that person's request, so
 * nobody else may use the invite until the creator answers or the request lapses.
 */
async function reservedForSomeoneElse(ctx: ReaderCtx, invite: Doc<"pairing_invites">, userId: string): Promise<boolean> {
  if (invite.restore_requested_by_user_id === undefined || invite.restore_requested_by_user_id === userId) return false;
  return (await standingRestoreRequest(ctx, invite)) !== null;
}

/** Marks the invite with the joiner's request and asks its creator once. Asking again changes nothing. */
async function askToRestore(ctx: MutationCtx, invite: Doc<"pairing_invites">, joinerUserId: string): Promise<void> {
  if (invite.restore_requested_by_user_id === joinerUserId) return;
  await ctx.db.patch(
    invite._id,
    withUpdatedAt({ restore_requested_by_user_id: joinerUserId, restore_requested_at: nowIso() }),
  );
  await enqueueRestorePush(ctx, invite, invite.created_by_user_id, joinerUserId, "requested");
}

async function enqueueRestorePush(
  ctx: MutationCtx,
  invite: Doc<"pairing_invites">,
  recipientUserId: string,
  actorUserId: string,
  step: "requested" | "restored" | "fresh",
  coupleId?: string,
): Promise<void> {
  await enqueueNotificationForUser(ctx, {
    recipient_user_id: recipientUserId,
    kind: "relationship_restore",
    payload: {
      type: "relationship_restore",
      step,
      invite_id: invite.id,
      actor_user_id: actorUserId,
      ...(coupleId ? { couple_id: coupleId } : {}),
      // Without a couple the root shows the answer screen, and with one Home, so `us` fits both.
      route: "us",
      deeplink: "paeonia://us",
    },
    dedupe_key: `relationship_restore:${invite.id}:${recipientUserId}:${step}`,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `relationship-restore:${invite.id}`,
  });
}

/**
 * The invite creator's answer to `p_requester_user_id`'s request to bring back their ended
 * relationship. The app sends the requester its access snapshot showed, so the answer never pairs
 * the creator with someone they were not asked about. With `p_restore` and while it still can,
 * the old couple opens again. Otherwise, after a "start fresh" or when it got too late, the two
 * pair as a new couple. Returns the couple and whether it is the old one. `couple_id` is null when
 * the request no longer stands, such as when the joiner was reported, blocked, deleted their
 * account or paired with someone else, and the invite then waits as before.
 */
export const answer_relationship_restore = mutation({
  args: { p_invite_id: v.string(), p_requester_user_id: v.string(), p_restore: v.boolean(), ...clientOperationArgs },
  handler: async (ctx, args): Promise<{ couple_id: string | null; restored: boolean }> => {
    const userId = await requireUserId(ctx);
    const inviteId = uuidArg(args.p_invite_id);
    const requesterId = uuidArg(args.p_requester_user_id);
    const input = toClientOperation(args, {
      kind: "answer_relationship_restore",
      scope: "pairing_invites",
      request: { kind: "answer_relationship_restore", invite_id: inviteId, requester_user_id: requesterId, restore: args.p_restore },
    });
    return await runClientOperation(ctx, userId, input, async () => {
      const invite = await getByUuid(ctx, "pairing_invites", inviteId);
      if (!invite || invite.created_by_user_id !== userId) {
        return fail("22023", "restore request is not available");
      }
      const joined = await coupleJoinedThrough(ctx, invite, requesterId);
      if (joined) {
        // A restored couple is older than the invite that brought it back.
        return { couple_id: joined.id, restored: joined.created_at < invite.created_at };
      }
      // Someone else's request, or none, is not the one the creator answers.
      if (invite.restore_requested_by_user_id !== requesterId) return { couple_id: null, restored: false };
      const now = nowIso();
      const request = await standingRestoreRequest(ctx, invite);
      if (!request || invite.expires_at <= now) {
        await ctx.db.patch(
          invite._id,
          withUpdatedAt({ restore_requested_by_user_id: undefined, restore_requested_at: undefined }),
        );
        return { couple_id: null, restored: false };
      }

      const couple = args.p_restore ? await findRestorableCouple(ctx, request.pairId, now) : null;
      if (couple) {
        await reopenCouple(ctx, couple, userId);
        await markInviteAccepted(ctx, invite, requesterId, couple.id);
        // What the creator made while waiting for their partner joins the couple's content.
        await materializeFirstDayDrafts(ctx, { coupleId: couple.id, creatorUserId: userId, partnerUserId: requesterId });
        await enqueueRestorePush(ctx, invite, requesterId, userId, "restored", couple.id);
        return { couple_id: couple.id, restored: true };
      }
      const coupleId = await pairAsNewCouple(ctx, invite, request.pairId, requesterId, undefined);
      await enqueueRestorePush(ctx, invite, requesterId, userId, "fresh", coupleId);
      return { couple_id: coupleId, restored: false };
    });
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
