import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import type { FavoriteKind } from "./favorites";

/** The `favorites` rows: lookups, paging, and the deletes the cleanup paths use. The kinds are in `lib/favorites.ts`. */

/** The caller's favorite row for a target, if any. */
export async function getFavorite(
  ctx: ReaderCtx,
  userId: string,
  kind: FavoriteKind,
  targetId: string,
): Promise<Doc<"favorites"> | null> {
  return await ctx.db
    .query("favorites")
    .withIndex("by_user_id_kind_target_id", (q) => q.eq("user_id", userId).eq("kind", kind).eq("target_id", targetId))
    .unique();
}

/**
 * The caller's favorites of a game kind, newest item first, strictly before `before`. The games page
 * their "starred only" history through this.
 */
export function favoritesByOrdinalDesc(ctx: ReaderCtx, userId: string, kind: FavoriteKind, before: number) {
  return ctx.db
    .query("favorites")
    .withIndex("by_user_id_kind_ordinal", (q) => q.eq("user_id", userId).eq("kind", kind).lt("ordinal", before))
    .order("desc");
}

/** Deletes every favorite in the couple, whoever saved it. For the couple cleanup and purge. Returns the row count. */
export async function deleteCoupleFavorites(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = await ctx.db.query("favorites").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect();
  for (const row of rows) await ctx.db.delete(row._id);
  return rows.length;
}

/** The rows of one person's favorites, for account deletion. */
export async function listUserFavoriteRows(ctx: ReaderCtx, userId: string): Promise<Doc<"favorites">[]> {
  return await ctx.db.query("favorites").withIndex("by_user_id_created_at", (q) => q.eq("user_id", userId)).collect();
}

/**
 * Deletes everyone's favorites of one target in the couple, for a path that deletes the target
 * itself. The couple matters for a question, which many couples share.
 */
export async function deleteFavoritesOfTarget(
  ctx: WriterCtx,
  coupleId: string,
  kind: FavoriteKind,
  targetId: string,
): Promise<void> {
  for (const row of await ctx.db
    .query("favorites")
    .withIndex("by_kind_target_id", (q) => q.eq("kind", kind).eq("target_id", targetId))
    .collect()) {
    if (row.couple_id === coupleId) await ctx.db.delete(row._id);
  }
}
