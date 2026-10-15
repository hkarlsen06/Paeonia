import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import type { QueryCtx } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { fail } from "./lib/errors";
import { MAX_HEARTS_PER_SEND, seenTotalAfterMark } from "./lib/hearts";
import { consumeRateLimit } from "./lib/rateLimits";
import { nowIso } from "./lib/time";

// Hearts sent from the Home map. The sender's phone batches taps and sends one count.
// The recipient's phone subscribes to `get_hearts`, plays the unseen ones, and marks them seen.
// Nothing here pushes a notification, touches a streak, or feeds a widget.

/** The couple's heart row of one user. `sent_total` is what that user sent, `seen_total` what they were shown from the partner. */
async function heartsRow(ctx: QueryCtx, coupleId: string, userId: string) {
  return await ctx.db
    .query("couple_hearts")
    .withIndex("by_couple_id_sender_user_id", (q) => q.eq("couple_id", coupleId).eq("sender_user_id", userId))
    .unique();
}

async function partnerOf(ctx: QueryCtx, coupleId: string, userId: string) {
  const members = await listActiveMembers(ctx, coupleId);
  return members.find((member) => member.user_id !== userId) ?? null;
}

/**
 * Adds `p_count` (1 to 100) hearts to the caller's total for the couple. Fails with
 * `42501` without an entitled couple and an active partner, and with `53300` when the
 * caller sends too often. A replay of the same operation changes nothing.
 * Returns `{ sent_total }`.
 */
export const send_hearts = mutation({
  args: { p_count: v.number(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const count = args.p_count;
    if (!Number.isInteger(count) || count < 1 || count > MAX_HEARTS_PER_SEND) {
      fail("23514", `hearts count must be between 1 and ${MAX_HEARTS_PER_SEND}`);
    }
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const members = await listActiveMembers(ctx, coupleId);
    if (!members.some((member) => member.user_id !== userId)) {
      fail("42501", "an active partner is required to send hearts");
    }

    return await runClientOperation(
      ctx,
      userId,
      toClientOperation(args, {
        kind: "send_hearts",
        scope: "hearts",
        request: { kind: "send_hearts", couple_id: coupleId, user_id: userId, count },
      }),
      async () => {
        await consumeRateLimit(ctx, "heartsSend", userId);
        const now = nowIso();
        const existing = await heartsRow(ctx, coupleId, userId);
        if (existing) {
          const sentTotal = existing.sent_total + count;
          await ctx.db.patch(existing._id, { sent_total: sentTotal, last_sent_at: now, updated_at: now });
          return { sent_total: sentTotal };
        }
        await ctx.db.insert("couple_hearts", {
          couple_id: coupleId,
          sender_user_id: userId,
          sent_total: count,
          seen_total: 0,
          last_sent_at: now,
          created_at: now,
          updated_at: now,
        });
        return { sent_total: count };
      },
    );
  },
});

/**
 * Tells the server the caller showed the partner's hearts up to `p_seen_total`. A total
 * above what the partner sent counts as the sent total, and a lower one changes nothing,
 * so a retry and a heart that arrived mid-animation are both safe. Each partner keeps their
 * own seen total on their own row, so a mark never writes the row the partner sends to.
 * Returns the caller's received totals after the mark.
 */
export const mark_hearts_seen = mutation({
  args: { p_seen_total: v.number() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const shown = args.p_seen_total;
    if (!Number.isInteger(shown) || shown < 0) {
      fail("23514", "seen hearts total must be a whole number of at least 0");
    }
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partner = await partnerOf(ctx, coupleId, userId);
    const sent = partner ? await heartsRow(ctx, coupleId, partner.user_id) : null;
    if (!sent) return { couple_id: coupleId, received_total: 0, received_seen_total: 0 };
    const own = await heartsRow(ctx, coupleId, userId);
    const seenTotal = seenTotalAfterMark(own?.seen_total ?? 0, shown, sent.sent_total);
    if (own && seenTotal !== own.seen_total) {
      await ctx.db.patch(own._id, { seen_total: seenTotal, updated_at: nowIso() });
    } else if (!own && seenTotal > 0) {
      const now = nowIso();
      await ctx.db.insert("couple_hearts", {
        couple_id: coupleId,
        sender_user_id: userId,
        sent_total: 0,
        seen_total: seenTotal,
        created_at: now,
        updated_at: now,
      });
    }
    return { couple_id: coupleId, received_total: sent.sent_total, received_seen_total: seenTotal };
  },
});

/**
 * What the partner sent the caller: `received_total` hearts so far, `received_seen_total` of
 * them already shown. The app subscribes to this and plays the difference. The totals come
 * from two rows: the partner's sent total and the caller's own seen total.
 */
export const get_hearts = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partner = await partnerOf(ctx, coupleId, userId);
    const sent = partner ? await heartsRow(ctx, coupleId, partner.user_id) : null;
    const own = await heartsRow(ctx, coupleId, userId);
    return {
      couple_id: coupleId,
      received_total: sent?.sent_total ?? 0,
      received_seen_total: own?.seen_total ?? 0,
    };
  },
});
