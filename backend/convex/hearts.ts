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

async function receivedRow(ctx: QueryCtx, coupleId: string, userId: string) {
  const members = await listActiveMembers(ctx, coupleId);
  const partner = members.find((member) => member.user_id !== userId);
  if (!partner) return null;
  return await ctx.db
    .query("couple_hearts")
    .withIndex("by_couple_id_sender_user_id", (q) => q.eq("couple_id", coupleId).eq("sender_user_id", partner.user_id))
    .unique();
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
        const existing = await ctx.db
          .query("couple_hearts")
          .withIndex("by_couple_id_sender_user_id", (q) => q.eq("couple_id", coupleId).eq("sender_user_id", userId))
          .unique();
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
 * so a retry and a heart that arrived mid-animation are both safe. Returns the caller's
 * received totals after the mark.
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
    const row = await receivedRow(ctx, coupleId, userId);
    if (!row) return { couple_id: coupleId, received_total: 0, received_seen_total: 0 };
    const seenTotal = seenTotalAfterMark(row.seen_total, shown, row.sent_total);
    if (seenTotal !== row.seen_total) {
      await ctx.db.patch(row._id, { seen_total: seenTotal, updated_at: nowIso() });
    }
    return { couple_id: coupleId, received_total: row.sent_total, received_seen_total: seenTotal };
  },
});

/**
 * What the partner sent the caller: `received_total` hearts so far, `received_seen_total` of
 * them already shown. The app subscribes to this and plays the difference. It reads only the
 * partner's row, so the caller's own sends never re-run it.
 */
export const get_hearts = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const row = await receivedRow(ctx, coupleId, userId);
    return {
      couple_id: coupleId,
      received_total: row?.sent_total ?? 0,
      received_seen_total: row?.seen_total ?? 0,
    };
  },
});
