// Operator functions for App Store review access. Run them with
// `npx convex run review:<name> '<json args>'`. None are callable by the app.
import { v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";
import { fail, uniqueViolation } from "./lib/errors";
import { optionalTimestampArg, uuidArg } from "./lib/ids";
import {
  ensureReviewPartner,
  expireStaleReviewCodes,
  findActiveReviewAccessCode,
  hashReviewAccessCode,
  issueReviewAccessCode,
  redeemReviewAccess,
  resetReviewDemo,
} from "./lib/reviewAccess";
import { addDaysToInstant, nowIso } from "./lib/time";
import { reviewScenario } from "./lib/validators";

/** Port of `internal.issue_review_access_code`. Returns the new code id. */
export const issue_review_access_code = internalMutation({
  args: {
    p_code: v.string(),
    p_seeded_partner_user_id: v.optional(v.union(v.null(), v.string())),
    p_scenario: v.optional(reviewScenario),
    p_expires_at: v.optional(v.union(v.null(), v.string())),
    p_max_redemptions: v.optional(v.number()),
  },
  handler: async (ctx, args) =>
    await issueReviewAccessCode(ctx, {
      code: args.p_code,
      seededPartnerUserId: args.p_seeded_partner_user_id ? uuidArg(args.p_seeded_partner_user_id) : undefined,
      scenario: args.p_scenario ?? "pre_paired_paywalled",
      // Omitted means 30 days. An explicit null means the code never expires.
      expiresAt:
        args.p_expires_at === undefined ? addDaysToInstant(nowIso(), 30) : optionalTimestampArg(args.p_expires_at),
      maxRedemptions: args.p_max_redemptions ?? 1,
    }),
});

/** Port of `internal.revoke_review_access_codes`. Returns the number of codes revoked. */
export const revoke_review_access_codes = internalMutation({
  args: {},
  handler: async (ctx) => {
    const codes = await ctx.db
      .query("review_access_codes")
      .withIndex("by_status_expires_at", (q) => q.eq("status", "active"))
      .collect();
    const now = nowIso();
    for (const code of codes) {
      await ctx.db.patch(code._id, { status: "revoked", revoked_at: now });
    }
    return codes.length;
  },
});

/** Port of `internal.hash_review_access_code`. Returns the SHA-256 as lowercase hex. */
export const hash_review_access_code = internalQuery({
  args: { p_code: v.string() },
  handler: async (_ctx, args) => await hashReviewAccessCode(args.p_code),
});

/** Port of `internal.find_active_review_access_code`. Returns the code row or null. */
export const find_active_review_access_code = internalQuery({
  args: { p_code: v.string() },
  handler: async (ctx, args) => await findActiveReviewAccessCode(ctx, args.p_code),
});

/** Port of `internal.redeem_review_access`. Returns the couple id. */
export const redeem_review_access = internalMutation({
  args: { p_code_id: v.string(), p_reviewer_user_id: v.string() },
  handler: async (ctx, args) =>
    await redeemReviewAccess(ctx, uuidArg(args.p_code_id), uuidArg(args.p_reviewer_user_id)),
});

/** Port of `internal.ensure_review_partner`. */
export const ensure_review_partner = internalMutation({
  args: { p_user_id: v.string(), p_display_name: v.string() },
  handler: async (ctx, args) => {
    await ensureReviewPartner(ctx, uuidArg(args.p_user_id), args.p_display_name);
    return null;
  },
});

/** Port of `internal.register_review_demo_partner`. The user must already have signed in once. */
export const register_review_demo_partner = internalMutation({
  args: { p_slot: v.number(), p_user_id: v.string(), p_display_name: v.string() },
  handler: async (ctx, args) => {
    const userId = uuidArg(args.p_user_id);
    const displayName = args.p_display_name.trim();
    if (!Number.isInteger(args.p_slot) || args.p_slot < 1 || args.p_slot > 9) {
      return fail("23514", 'new row for relation "review_demo_partners" violates check constraint "review_demo_partners_slot_check"');
    }
    if (displayName.length < 1 || displayName.length > 80) {
      return fail(
        "23514",
        'new row for relation "review_demo_partners" violates check constraint "review_demo_partners_display_name_check"',
      );
    }
    const user = await ctx.db
      .query("users")
      .withIndex("by_uuid", (q) => q.eq("id", userId))
      .unique();
    if (!user) {
      return fail(
        "23503",
        'insert or update on table "review_demo_partners" violates foreign key constraint "review_demo_partners_user_id_fkey"',
      );
    }
    const takenBy = await ctx.db
      .query("review_demo_partners")
      .withIndex("by_user_id", (q) => q.eq("user_id", userId))
      .unique();
    if (takenBy && takenBy.slot !== args.p_slot) {
      return uniqueViolation("review_demo_partners_user_unique");
    }
    const now = nowIso();
    const existing = await ctx.db
      .query("review_demo_partners")
      .withIndex("by_slot", (q) => q.eq("slot", args.p_slot))
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, { user_id: userId, display_name: args.p_display_name, updated_at: now });
    } else {
      await ctx.db.insert("review_demo_partners", {
        slot: args.p_slot,
        user_id: userId,
        display_name: args.p_display_name,
        created_at: now,
        updated_at: now,
      });
    }
    await ensureReviewPartner(ctx, userId, args.p_display_name);
    return null;
  },
});

/** Port of `internal.list_review_demo_partners`. */
export const list_review_demo_partners = internalQuery({
  args: {},
  handler: async (ctx) => {
    const partners = await ctx.db.query("review_demo_partners").collect();
    return partners
      .sort((a, b) => a.slot - b.slot)
      .map((partner) => ({ slot: partner.slot, user_id: partner.user_id, display_name: partner.display_name }));
  },
});

/** Port of `internal.reset_review_demo`. Returns the number of demo couples deleted. */
export const reset_review_demo = internalMutation({
  args: {},
  handler: async (ctx) => await resetReviewDemo(ctx),
});

/**
 * Review-code half of `internal.expire_stale_invites_and_review_codes`. The
 * pairing module owns the invite half. Returns `review_codes_expired`.
 */
export const expire_stale_review_codes = internalMutation({
  args: { p_now: v.optional(v.union(v.null(), v.string())), p_limit: v.optional(v.union(v.null(), v.number())) },
  handler: async (ctx, args) => {
    const now = args.p_now === undefined ? nowIso() : optionalTimestampArg(args.p_now);
    if (now === undefined) {
      return fail("23514", "expiry timestamp is required");
    }
    const limit = args.p_limit === undefined ? 500 : args.p_limit;
    if (limit === null || limit < 1 || limit > 5000) {
      return fail("23514", "expiry limit is out of range");
    }
    return await expireStaleReviewCodes(ctx, now, limit);
  },
});
