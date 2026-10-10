import type { Doc } from "../_generated/dataModel";
import { getOrCreateRelationshipPair, hasActiveRelationshipBlock } from "./access";
import { assertNoPendingAccountDeletion } from "./accountDeletion";
import { sha256Hex } from "./crypto";
import { getByUuid, type ReaderCtx, type WriterCtx } from "./db";
import { fail, uniqueViolation } from "./errors";
import { newUuid } from "./ids";
import { cleanupCoupleContent, purgeCoupleContent } from "./relationshipCleanup";
import { updateProfile } from "./profiles";
import { createRelationshipSyncEvent } from "./syncEvents";
import { deleteStorekitTransaction } from "./storekit";
import { addDaysToDate, addDaysToInstant, nowIso } from "./time";

const DEMO_START_DAYS_AGO = 180;
const DEMO_RESTORABLE_COUNT = 12;
const DEMO_PARTNER_TIME_ZONE = "Europe/Oslo";

/** Port of `internal.hash_review_access_code`. The SQL returned bytea; this is its lowercase hex. */
export function hashReviewAccessCode(code: string): Promise<string> {
  return sha256Hex(code);
}

/** Port of `internal.find_active_review_access_code`. Null when the code is unknown, revoked, or expired. */
export async function findActiveReviewAccessCode(
  ctx: ReaderCtx,
  code: string,
): Promise<Doc<"review_access_codes"> | null> {
  const hash = await hashReviewAccessCode(code);
  const match = await ctx.db
    .query("review_access_codes")
    .withIndex("by_code_hash", (q) => q.eq("code_hash", hash))
    .first();
  if (!match || match.status !== "active" || (match.expires_at !== undefined && match.expires_at <= nowIso())) {
    return null;
  }
  return match;
}

/** Port of `internal.ensure_review_partner`: makes the demo partner's profile complete and visible. */
export async function ensureReviewPartner(ctx: WriterCtx, userId: string, displayName: string): Promise<void> {
  const user = await getByUuid(ctx, "users", userId);
  if (!user) {
    return fail("23503", 'insert or update on table "profiles" violates foreign key constraint "profiles_user_id_fkey"');
  }
  const trimmed = displayName.trim();
  if (trimmed.length < 1 || trimmed.length > 80) {
    return fail("23514", 'new row for relation "profiles" violates check constraint "profiles_display_name_check"');
  }
  const now = nowIso();
  const profile = await ctx.db
    .query("profiles")
    .withIndex("by_user_id", (q) => q.eq("user_id", userId))
    .unique();
  if (!profile) {
    await ctx.db.insert("profiles", {
      user_id: userId,
      display_name: displayName,
      time_zone_id: DEMO_PARTNER_TIME_ZONE,
      time_zone_updated_at: now,
      onboarding_completed_at: now,
      revision: 1,
      moderation_status: "visible",
      created_at: now,
      updated_at: now,
    });
    return;
  }
  await updateProfile(ctx, profile, {
    display_name: displayName,
    time_zone_id: profile.time_zone_id ?? DEMO_PARTNER_TIME_ZONE,
    time_zone_updated_at: profile.time_zone_updated_at ?? now,
    onboarding_completed_at: profile.onboarding_completed_at ?? now,
    moderation_status: "visible",
    deleted_at: undefined,
  });
}

async function hasActiveMembership(ctx: ReaderCtx, userId: string): Promise<boolean> {
  const rows = await ctx.db
    .query("couple_members")
    .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", userId).eq("status", "active"))
    .first();
  return rows !== null;
}

/**
 * Port of `internal.redeem_review_access`. Pairs the reviewer with the seeded
 * demo partner in a fresh couple that has a map pin, a broken streak with a
 * restore window, and an expired partner subscription. Replays return the
 * reviewer's existing couple without consuming a redemption.
 */
export async function redeemReviewAccess(
  ctx: WriterCtx,
  codeId: string,
  reviewerUserId: string | null | undefined,
): Promise<string> {
  if (!reviewerUserId) {
    return fail("42501", "authenticated user required");
  }
  const code = await getByUuid(ctx, "review_access_codes", codeId);

  // A revoked, expired, or unknown code is never redeemable, not even as a replay.
  // The redemption ceiling is checked after the replay lookup so a reviewer who
  // already redeemed can return to their couple once the code is consumed.
  if (!code || code.status !== "active" || (code.expires_at !== undefined && code.expires_at <= nowIso())) {
    return fail("22023", "review access code is not available");
  }
  const partnerId = code.seeded_partner_user_id;
  if (!partnerId) {
    return fail("23514", "review access code has no seeded partner");
  }
  if (partnerId === reviewerUserId) {
    return fail("23514", "reviewer cannot be the seeded partner");
  }

  const sessions = await ctx.db
    .query("review_access_sessions")
    .withIndex("by_code_id_redeemed_at", (q) => q.eq("code_id", code.id))
    .order("desc")
    .collect();
  for (const session of sessions) {
    if (session.user_id !== reviewerUserId || session.couple_id === undefined) continue;
    const couple = await getByUuid(ctx, "couples", session.couple_id);
    if (couple?.status !== "active") continue;
    const member = await ctx.db
      .query("couple_members")
      .withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id).eq("user_id", reviewerUserId))
      .unique();
    if (member?.status === "active") {
      return couple.id;
    }
  }

  if (code.redemption_count >= code.max_redemptions) {
    return fail("22023", "review access code is not available");
  }
  if (await hasActiveMembership(ctx, reviewerUserId)) {
    return fail("23505", "reviewer already has an active couple");
  }
  if (await hasActiveMembership(ctx, partnerId)) {
    return fail("23505", "seeded partner still has an active couple; run reset before minting");
  }

  const pairId = await getOrCreateRelationshipPair(ctx, partnerId, reviewerUserId);
  if (await hasActiveRelationshipBlock(ctx, pairId)) {
    return fail("42501", "review pair is blocked");
  }

  const now = nowIso();
  const today = now.slice(0, 10);
  const coupleId = newUuid();
  // The partner "invited" the reviewer, so the partner is the creator.
  await ctx.db.insert("couples", {
    id: coupleId,
    pair_id: pairId,
    status: "active",
    started_on: addDaysToDate(today, -DEMO_START_DAYS_AGO),
    created_by_user_id: partnerId,
    created_at: now,
    updated_at: now,
  });
  await ctx.db.insert("couple_members", {
    couple_id: coupleId,
    user_id: partnerId,
    role: "creator",
    status: "active",
    joined_at: now,
    updated_at: now,
  });
  await ctx.db.insert("couple_members", {
    couple_id: coupleId,
    user_id: reviewerUserId,
    role: "partner",
    status: "active",
    joined_at: now,
    updated_at: now,
  });

  // A partner pin in central Oslo so the map has something to show.
  await assertNoPendingAccountDeletion(ctx, partnerId);
  await ctx.db.insert("latest_partner_locations", {
    couple_id: coupleId,
    user_id: partnerId,
    latitude: 59.9139,
    longitude: 10.7523,
    accuracy_m: 25,
    captured_at: now,
    received_at: now,
    updated_at: now,
    source: "settings_toggle",
    client_operation_id: newUuid(),
    client_id: newUuid(),
    client_sequence: 1,
  });
  await ctx.db.insert("location_sharing_preferences", {
    couple_id: coupleId,
    user_id: partnerId,
    is_enabled: true,
    enabled_at: now,
    consent_version: "1",
    source: "settings_toggle",
    created_at: now,
    updated_at: now,
  });

  // A broken streak with a 30 day restore window, so streak restore is reachable during review.
  await ctx.db.insert("streak_states", {
    couple_id: coupleId,
    current_count: 0,
    longest_count: DEMO_RESTORABLE_COUNT,
    restore_available: true,
    restorable_count: DEMO_RESTORABLE_COUNT,
    restorable_through_date: addDaysToDate(today, -2),
    restore_deadline: addDaysToInstant(now, 30),
    updated_at: now,
  });

  // An expired partner subscription, so the paywall reads like a lapsed subscriber. Skipped when no product is configured.
  const products = await ctx.db
    .query("subscription_products")
    .withIndex("by_is_active_kind", (q) => q.eq("is_active", true).eq("kind", "couple_subscription"))
    .collect();
  products.sort((a, b) => (a.created_at < b.created_at ? -1 : a.created_at > b.created_at ? 1 : 0));
  const product = products[0];
  if (product) {
    const demoTransactionId = `review-demo-${coupleId}`;
    await ctx.db.insert("storekit_transactions", {
      id: newUuid(),
      user_id: partnerId,
      product_id: product.id,
      environment: "sandbox",
      original_transaction_id: demoTransactionId,
      transaction_id: demoTransactionId,
      status: "expired",
      purchased_at: addDaysToInstant(now, -60),
      expires_at: addDaysToInstant(now, -30),
      reconciliation_attempts: 0,
      created_at: now,
      updated_at: now,
    });
  }

  // Mirror real pairing so local-first clients refresh into the paired state.
  for (const userId of [partnerId, reviewerUserId]) {
    await createRelationshipSyncEvent(ctx, {
      user_id: userId,
      couple_id: coupleId,
      initiated_by_user_id: reviewerUserId,
      event_kind: "relationship_started",
      reason: "review_access_redeemed",
      relationship_status: "active",
      member_status: "active",
      local_purge_scope: { relationship: "refresh", entitlement: "refresh" },
    });
  }

  await ctx.db.insert("review_access_sessions", {
    id: newUuid(),
    code_id: code.id,
    user_id: reviewerUserId,
    seeded_partner_user_id: partnerId,
    couple_id: coupleId,
    scenario: code.scenario,
    auth_verified_at: now,
    redeemed_at: now,
  });
  await ctx.db.insert("review_access_attempts", {
    id: newUuid(),
    user_id: reviewerUserId,
    code_hash_prefix: code.code_hash.slice(0, 12),
    matched_code_id: code.id,
    success: true,
    attempted_at: now,
  });
  await ctx.db.patch(code._id, { redemption_count: code.redemption_count + 1 });
  return coupleId;
}

/** The review-code half of `internal.expire_stale_invites_and_review_codes`. Returns `review_codes_expired`. */
export async function expireStaleReviewCodes(ctx: WriterCtx, now: string, limit: number): Promise<number> {
  const codes = await ctx.db
    .query("review_access_codes")
    .withIndex("by_status_expires_at", (q) => q.eq("status", "active").gt("expires_at", "").lte("expires_at", now))
    .take(limit);
  for (const code of codes) {
    await ctx.db.patch(code._id, { status: "expired" });
  }
  return codes.length;
}

/** Inserts a review access code. Port of `internal.issue_review_access_code`. */
export async function issueReviewAccessCode(
  ctx: WriterCtx,
  args: {
    code: string;
    seededPartnerUserId: string | undefined;
    scenario: Doc<"review_access_codes">["scenario"];
    expiresAt: string | undefined;
    maxRedemptions: number;
  },
): Promise<string> {
  if (args.scenario !== "purchase_flow_unentitled" && args.seededPartnerUserId === undefined) {
    return fail(
      "23514",
      'new row for relation "review_access_codes" violates check constraint "review_access_codes_prepaired_partner_check"',
    );
  }
  if (args.maxRedemptions <= 0) {
    return fail(
      "23514",
      'new row for relation "review_access_codes" violates check constraint "review_access_codes_redemption_count_check"',
    );
  }
  const codeHash = await hashReviewAccessCode(args.code);
  const duplicate = await ctx.db
    .query("review_access_codes")
    .withIndex("by_code_hash", (q) => q.eq("code_hash", codeHash))
    .first();
  if (duplicate) {
    return uniqueViolation("review_access_codes_code_hash_unique");
  }
  const id = newUuid();
  await ctx.db.insert("review_access_codes", {
    id,
    code_hash: codeHash,
    seeded_partner_user_id: args.seededPartnerUserId,
    scenario: args.scenario,
    status: "active",
    expires_at: args.expiresAt,
    max_redemptions: args.maxRedemptions,
    redemption_count: 0,
    created_at: nowIso(),
  });
  return id;
}

/**
 * Port of `internal.reset_review_demo`. Deletes every couple a demo partner
 * belongs to, with the rows that depended on it, and the partner's StoreKit
 * transactions. Returns the number of couples deleted. Media bytes are queued
 * for storage deletion by the normal cleanup.
 */
export async function resetReviewDemo(ctx: WriterCtx): Promise<number> {
  const partners = await ctx.db.query("review_demo_partners").collect();
  let deletedCouples = 0;
  for (const partner of partners) {
    const memberships = await ctx.db
      .query("couple_members")
      .withIndex("by_user_id_status_couple_id", (q) => q.eq("user_id", partner.user_id))
      .collect();
    const coupleIds = [...new Set(memberships.map((member) => member.couple_id))];
    for (const coupleId of coupleIds) {
      const couple = await getByUuid(ctx, "couples", coupleId);
      if (couple) {
        await deleteCoupleAndDependents(ctx, couple);
        deletedCouples += 1;
      }
    }
    // The expired demo subscription belongs to the user, not the couple, so it does not cascade.
    const transactions = await ctx.db
      .query("storekit_transactions")
      .withIndex("by_user_id_status_expires_at", (q) => q.eq("user_id", partner.user_id))
      .collect();
    for (const transaction of transactions) {
      await deleteStorekitTransaction(ctx, transaction);
    }
  }
  return deletedCouples;
}

async function deleteCoupleAndDependents(ctx: WriterCtx, couple: Doc<"couples">): Promise<void> {
  const now = nowIso();
  await cleanupCoupleContent(ctx, couple, now);
  await purgeCoupleContent(ctx, couple);

  const children = [
    await ctx.db.query("review_access_sessions").withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id)).collect(),
    await ctx.db
      .query("streak_restorations")
      .withIndex("by_couple_id_restored_at", (q) => q.eq("couple_id", couple.id))
      .collect(),
    await ctx.db
      .query("relationship_sync_events")
      .withIndex("by_couple_id_created_at_id", (q) => q.eq("couple_id", couple.id))
      .collect(),
    await ctx.db.query("couple_members").withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id)).collect(),
    await ctx.db.query("latest_partner_locations").withIndex("by_couple_id_user_id", (q) => q.eq("couple_id", couple.id)).collect(),
  ];
  for (const rows of children) {
    for (const row of rows) {
      await ctx.db.delete(row._id);
    }
  }
  const invites = await ctx.db.query("pairing_invites").withIndex("by_couple_id", (q) => q.eq("couple_id", couple.id)).collect();
  for (const invite of invites) {
    for (const secret of await ctx.db.query("pairing_invite_secrets").withIndex("by_invite_id", (q) => q.eq("invite_id", invite.id)).collect()) {
      await ctx.db.delete(secret._id);
    }
    await ctx.db.delete(invite._id);
  }
  await ctx.db.delete(couple._id);
}
