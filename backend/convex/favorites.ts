import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId, getEntitledCoupleIdForUser } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { fail } from "./lib/errors";
import { getFavorite } from "./lib/favoriteRows";
import { loadFavoriteTarget } from "./lib/favorites";
import { uuidArg } from "./lib/ids";
import { nowIso } from "./lib/time";
import { favoriteKind } from "./lib/validators";

/** Newest favorites `list_favorites` returns. Far above what a couple saves, and a bound on the live query. */
const MAX_LISTED_FAVORITES = 2000;
/** Most favorites one `get_favorite_summaries` call resolves. The Saved list reads one page at a time. */
const MAX_SUMMARY_ITEMS = 40;

/**
 * Saves or unsaves one item for the caller. Favorites are private: the partner is never told and
 * cannot read them. The server sets the given value, so sending the same write twice changes
 * nothing. Taking a favorite back always works. Saving needs an item that is alive in the caller's
 * couple and, for a game item, finished, or it fails with 23514, which a retry cannot fix. A caller
 * without an entitled couple fails with 42501.
 * Result: `{ kind, target_id, favorited }`.
 */
export const set_favorite = mutation({
  args: { p_kind: favoriteKind, p_target_id: v.string(), p_favorited: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const targetId = uuidArg(args.p_target_id);
    const existing = await getFavorite(ctx, userId, args.p_kind, targetId);
    const result = { kind: args.p_kind, target_id: targetId, favorited: args.p_favorited };
    if (!args.p_favorited) {
      if (existing) await ctx.db.delete(existing._id);
      return result;
    }
    if (existing) return result;
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const target = await loadFavoriteTarget(ctx, userId, coupleId, args.p_kind, targetId);
    if (!target) return fail("23514", "this item cannot be saved");
    await ctx.db.insert("favorites", {
      couple_id: coupleId,
      user_id: userId,
      kind: args.p_kind,
      target_id: targetId,
      ordinal: target.ordinal,
      created_at: nowIso(),
    });
    return result;
  },
});

/**
 * The caller's favorites in their couple, newest first, as ids only. The app keeps this list to show
 * which stars are filled, and pages the Saved list over it. An item that was deleted since it was
 * saved can still be in it until the cleanup that removes the item runs. `get_favorite_summaries` drops
 * those. Result: `[{ kind, target_id, created_at }]`.
 */
export const list_favorites = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getEntitledCoupleIdForUser(ctx, userId);
    if (!coupleId) return [];
    const rows = await ctx.db
      .query("favorites")
      .withIndex("by_user_id_created_at", (q) => q.eq("user_id", userId))
      .order("desc")
      .take(MAX_LISTED_FAVORITES);
    return rows
      .filter((row) => row.couple_id === coupleId)
      .map((row) => ({ kind: row.kind, target_id: row.target_id, created_at: row.created_at }));
  },
});

/**
 * What the Saved list shows for some of the caller's favorites. Only items the caller saved are
 * resolved, and an item that is gone, hidden or no longer readable is left out. The order of
 * `p_items` is kept. Result: `[{ kind, target_id, created_at, summary }]`, see `FavoriteSummary`.
 */
export const get_favorite_summaries = query({
  args: { p_items: v.array(v.object({ kind: favoriteKind, target_id: v.string() })) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    if (args.p_items.length > MAX_SUMMARY_ITEMS) fail("23514", "too many favorites in one read");
    const coupleId = await getEntitledCoupleIdForUser(ctx, userId);
    if (!coupleId) return [];
    const rows = [];
    for (const item of args.p_items) {
      const targetId = uuidArg(item.target_id);
      const favorite = await getFavorite(ctx, userId, item.kind, targetId);
      if (!favorite || favorite.couple_id !== coupleId) continue;
      const target = await loadFavoriteTarget(ctx, userId, coupleId, item.kind, targetId);
      if (!target) continue;
      rows.push({ kind: item.kind, target_id: targetId, created_at: favorite.created_at, summary: target.summary });
    }
    return rows;
  },
});
