import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { isSupersededClientOperation, runClientOperation } from "./lib/clientOperations";
import { getByUuid, withUpdatedAt, type ReaderCtx, type WriterCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { dateArg, uuidArg } from "./lib/ids";
import { enqueueLockScreenRefreshForPartner, LOCK_SCREEN_REFRESH_DELAY_SECONDS } from "./lib/notifications";
import { normalizePlace, placeArg } from "./lib/places";
import { nowIso } from "./lib/time";
import {
  liveTogetherItems,
  liveVisits,
  MAX_TOGETHER_ITEMS_PER_COUPLE,
  MAX_VISITS_PER_COUPLE,
} from "./lib/visits";

// The couple's visits, the times they meet in person, and their one shared list of things to do
// together. Either partner plans, edits or deletes a visit, and adds, ticks or deletes an item.

/** The app caps item titles at 40 characters. Code points are counted here, so an emoji never trips it. */
const MAX_ITEM_TITLE_CODE_POINTS = 80;

/** The partner's Lock Screen widget counts down to the next visit, so a visit change refreshes it. */
const refreshPartnerLockScreen = (ctx: WriterCtx, coupleId: string, userId: string) =>
  enqueueLockScreenRefreshForPartner(ctx, {
    couple_id: coupleId,
    actor_user_id: userId,
    delay_seconds: LOCK_SCREEN_REFRESH_DELAY_SECONDS,
  });

function visitRow(row: Doc<"visits">) {
  return {
    id: row.id,
    start_date: row.start_date,
    end_date: row.end_date,
    place: row.place ?? null,
    created_by_user_id: row.created_by_user_id,
    updated_at: row.updated_at,
  };
}

function itemRow(row: Doc<"together_list_items">) {
  return {
    id: row.id,
    title: row.title,
    added_by_user_id: row.added_by_user_id,
    done_at: row.done_at ?? null,
    done_by_user_id: row.done_by_user_id ?? null,
    created_at: row.created_at,
  };
}

const byStartDate = (a: Doc<"visits">, b: Doc<"visits">) =>
  a.start_date !== b.start_date ? (a.start_date < b.start_date ? -1 : 1) : a.id < b.id ? -1 : 1;

const byCreatedAt = (a: Doc<"together_list_items">, b: Doc<"together_list_items">) =>
  a.created_at !== b.created_at ? (a.created_at < b.created_at ? -1 : 1) : a.id < b.id ? -1 : 1;

/**
 * The caller's couple's visits, earliest first, and the list, oldest item first. The phone works out
 * which visit is next on its own day. The app subscribes to this. Fails with `42501` without an
 * entitled couple.
 */
export const get_visits = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const visits = (await liveVisits(ctx, coupleId)).sort(byStartDate).map(visitRow);
    const items = (await liveTogetherItems(ctx, coupleId)).sort(byCreatedAt).map(itemRow);
    return { couple_id: coupleId, visits, items };
  },
});

async function currentVisit(ctx: ReaderCtx, visitId: string, coupleId: string) {
  const row = await getByUuid(ctx, "visits", visitId);
  return row && row.couple_id === coupleId && row.deleted_at === undefined ? visitRow(row) : null;
}

async function currentItem(ctx: ReaderCtx, itemId: string, coupleId: string) {
  const row = await getByUuid(ctx, "together_list_items", itemId);
  return row && row.couple_id === coupleId && row.deleted_at === undefined ? itemRow(row) : null;
}

/**
 * Plans or edits the visit `p_visit_id`. The phone picks the id, so a create and its retries are the
 * same write. The last day may equal the first and may not be before it. A visit in the past is
 * fine. A deleted visit stays deleted, and a retry that a newer write from the same phone already
 * replaced changes nothing. Returns the visit as stored now, also on a replay, or null when it was
 * deleted.
 */
export const save_visit = mutation({
  args: {
    p_visit_id: v.string(),
    p_start_date: v.string(),
    p_end_date: v.string(),
    p_place: placeArg,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const visitId = uuidArg(args.p_visit_id);
    const startDate = dateArg(args.p_start_date);
    const endDate = dateArg(args.p_end_date);
    if (endDate < startDate) {
      fail("23514", "visit end date must not be before its start date");
    }
    const place = normalizePlace(args.p_place, "visit");
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "save_visit",
      scope: `visit:${visitId}`,
      request: { kind: "save_visit", couple_id: coupleId, id: visitId, start_date: startDate, end_date: endDate, place },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "visits", visitId);
      if (existing && existing.couple_id !== coupleId) {
        return fail("42501", "visit belongs to another couple");
      }
      if (existing?.deleted_at !== undefined || (await isSupersededClientOperation(ctx, userId, input))) {
        return null;
      }

      const fields = { start_date: startDate, end_date: endDate, place: place ?? undefined, last_edited_by_user_id: userId };
      if (existing) {
        await ctx.db.patch(existing._id, withUpdatedAt(fields));
      } else {
        if ((await liveVisits(ctx, coupleId)).length >= MAX_VISITS_PER_COUPLE) {
          return fail("23514", `a couple can have at most ${MAX_VISITS_PER_COUPLE} visits`);
        }
        const now = nowIso();
        await ctx.db.insert("visits", {
          id: visitId,
          couple_id: coupleId,
          ...fields,
          created_by_user_id: userId,
          created_at: now,
          updated_at: now,
        });
      }
      await refreshPartnerLockScreen(ctx, coupleId, userId);
      return null;
    });
    // Read after the operation, so a replay returns today's row and not the answer it stored back
    // then, which a partner's edit may have replaced.
    return await currentVisit(ctx, visitId, coupleId);
  },
});

/** Deletes the visit `p_visit_id` for both partners. The list stays. A missing or already deleted one is fine. */
export const delete_visit = mutation({
  args: { p_visit_id: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const visitId = uuidArg(args.p_visit_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "delete_visit",
      scope: `visit:${visitId}`,
      request: { kind: "delete_visit", couple_id: coupleId, id: visitId },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "visits", visitId);
      if (!existing || existing.deleted_at !== undefined) return null;
      if (existing.couple_id !== coupleId) {
        return fail("42501", "visit belongs to another couple");
      }
      await ctx.db.patch(existing._id, withUpdatedAt({ deleted_at: nowIso(), last_edited_by_user_id: userId }));
      await refreshPartnerLockScreen(ctx, coupleId, userId);
      return null;
    });
    return null;
  },
});

/**
 * Adds the list item `p_item_id`, or renames it. Like `save_visit`, a deleted item stays deleted and
 * a superseded retry changes nothing. Returns the item as stored now, or null when it was deleted.
 */
export const save_together_item = mutation({
  args: { p_item_id: v.string(), p_title: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const itemId = uuidArg(args.p_item_id);
    const title = args.p_title.trim();
    if (title.length === 0 || Array.from(title).length > MAX_ITEM_TITLE_CODE_POINTS) {
      fail("23514", "list item title must be 1 to 40 characters");
    }
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "save_together_item",
      scope: `together_item:${itemId}`,
      request: { kind: "save_together_item", couple_id: coupleId, id: itemId, title },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "together_list_items", itemId);
      if (existing && existing.couple_id !== coupleId) {
        return fail("42501", "list item belongs to another couple");
      }
      if (existing?.deleted_at !== undefined || (await isSupersededClientOperation(ctx, userId, input))) {
        return null;
      }
      if (existing) {
        await ctx.db.patch(existing._id, withUpdatedAt({ title, last_edited_by_user_id: userId }));
        return null;
      }
      if ((await liveTogetherItems(ctx, coupleId)).length >= MAX_TOGETHER_ITEMS_PER_COUPLE) {
        return fail("23514", `a couple can have at most ${MAX_TOGETHER_ITEMS_PER_COUPLE} list items`);
      }
      const now = nowIso();
      await ctx.db.insert("together_list_items", {
        id: itemId,
        couple_id: coupleId,
        title,
        added_by_user_id: userId,
        last_edited_by_user_id: userId,
        created_at: now,
        updated_at: now,
      });
      return null;
    });
    return await currentItem(ctx, itemId, coupleId);
  },
});

/**
 * Ticks (`p_done: true`) or unticks the list item `p_item_id`. Ticking a ticked item keeps who ticked
 * it first. Returns the item as stored now, or null when it is missing or deleted.
 */
export const set_together_item_done = mutation({
  args: { p_item_id: v.string(), p_done: v.boolean(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const itemId = uuidArg(args.p_item_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "set_together_item_done",
      scope: `together_item:${itemId}:done`,
      request: { kind: "set_together_item_done", couple_id: coupleId, id: itemId, done: args.p_done },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "together_list_items", itemId);
      if (!existing || existing.deleted_at !== undefined) return null;
      if (existing.couple_id !== coupleId) {
        return fail("42501", "list item belongs to another couple");
      }
      if (await isSupersededClientOperation(ctx, userId, input)) return null;
      if (args.p_done === (existing.done_at !== undefined)) return null;
      await ctx.db.patch(
        existing._id,
        withUpdatedAt(
          args.p_done
            ? { done_at: nowIso(), done_by_user_id: userId, last_edited_by_user_id: userId }
            : { done_at: undefined, done_by_user_id: undefined, last_edited_by_user_id: userId },
        ),
      );
      return null;
    });
    return await currentItem(ctx, itemId, coupleId);
  },
});

/** Deletes the list item `p_item_id` for both partners. A missing or already deleted one is fine. */
export const delete_together_item = mutation({
  args: { p_item_id: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const itemId = uuidArg(args.p_item_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "delete_together_item",
      scope: `together_item:${itemId}`,
      request: { kind: "delete_together_item", couple_id: coupleId, id: itemId },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "together_list_items", itemId);
      if (!existing || existing.deleted_at !== undefined) return null;
      if (existing.couple_id !== coupleId) {
        return fail("42501", "list item belongs to another couple");
      }
      await ctx.db.patch(existing._id, withUpdatedAt({ deleted_at: nowIso(), last_edited_by_user_id: userId }));
      return null;
    });
    return null;
  },
});
