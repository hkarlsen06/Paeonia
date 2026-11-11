import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { isSupersededClientOperation, runClientOperation } from "./lib/clientOperations";
import { daysBetweenDates } from "./lib/coupleDates";
import { getByUuid, withUpdatedAt, type ReaderCtx, type WriterCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { dateArg, uuidArg } from "./lib/ids";
import { enqueueLockScreenRefreshForPartner, LOCK_SCREEN_REFRESH_DELAY_SECONDS } from "./lib/notifications";
import { normalizePlace, placeArg } from "./lib/places";
import { detectStreakBreak } from "./lib/streaks";
import { requireTitle } from "./lib/text";
import { nowIso } from "./lib/time";
import { coupleDateAt, keepVisitDays } from "./lib/together";
import {
  earliestLocalDate,
  FIRST_VISIT_DATE,
  LAST_VISIT_DATE,
  liveTogetherItems,
  MAX_OPEN_VISITS_PER_COUPLE,
  MAX_TOGETHER_ITEM_TITLE_CODE_POINTS,
  MAX_TOGETHER_ITEMS_PER_COUPLE,
  MAX_VISIT_DAYS,
  openVisits,
  recentVisits,
} from "./lib/visits";

// The couple's visits, the times they meet in person, and their one shared list of things to do
// together. Either partner plans, edits or deletes a visit, and adds, ticks or deletes an item.
//
// The phone queues writes and may send them in any order, since a failed send waits while later
// ones go. All writes on one visit, or on one list item, share an idempotency scope, so a write
// that arrives after a newer one from the same phone changes nothing. A tick carries the item's
// title and adds the item when its add has not arrived yet. An item's title never changes.

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
    updated_at: row.updated_at,
  };
}

const byStartDate = (a: Doc<"visits">, b: Doc<"visits">) =>
  a.start_date !== b.start_date ? (a.start_date < b.start_date ? -1 : 1) : a.id < b.id ? -1 : 1;

const byCreatedAt = (a: Doc<"together_list_items">, b: Doc<"together_list_items">) =>
  a.created_at !== b.created_at ? (a.created_at < b.created_at ? -1 : 1) : a.id < b.id ? -1 : 1;

/**
 * The caller's couple's visits that are not over and the ones that ended last (`recentVisits`),
 * earliest first, and the list, oldest item first. The phone works out which visit is next on its
 * own day. The app subscribes to this. Fails with `42501` without an entitled couple.
 */
export const get_visits = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const visits = (await recentVisits(ctx, coupleId)).sort(byStartDate).map(visitRow);
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

/** Fails with `23514` unless the last day is not before the first, both are dates a visit can have, and the visit is not too long. */
function checkVisitDates(startDate: string, endDate: string) {
  if (endDate < startDate) {
    fail("23514", "visit end date must not be before its start date");
  }
  const tooLong = daysBetweenDates(startDate, endDate) >= MAX_VISIT_DAYS;
  if (startDate < FIRST_VISIT_DATE || endDate > LAST_VISIT_DATE || tooLong) {
    fail("23514", `a visit lies from ${FIRST_VISIT_DATE} to ${LAST_VISIT_DATE}, ${MAX_VISIT_DAYS} days at most`);
  }
}

/**
 * Plans or edits the visit `p_visit_id`. The phone picks the id, so a create and its retries are the
 * same write. A create sends every field. An edit sends only the fields the person changed, and the
 * visit keeps the others, so partners who edit different fields at once both keep their change.
 * `p_place: null` removes the place. The last day may equal the first and may not be before it,
 * both fall from `FIRST_VISIT_DATE` to `LAST_VISIT_DATE`, and a visit spans at most `MAX_VISIT_DAYS`
 * days, or this fails with `23514`. A visit in the past is fine, and it rests the streak only from today on. At most
 * `MAX_OPEN_VISITS_PER_COUPLE` visits end on or after `earliestLocalDate`, so a save that adds one
 * fails with `23514` when that many do. A deleted visit stays deleted, and a write that a newer one
 * from the same phone already replaced changes nothing. Returns the visit as stored now, also on a
 * replay, or null when it is deleted or was never saved.
 */
export const save_visit = mutation({
  args: {
    p_visit_id: v.string(),
    p_start_date: v.optional(v.string()),
    p_end_date: v.optional(v.string()),
    p_place: placeArg,
    ...clientOperationArgs,
  },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const visitId = uuidArg(args.p_visit_id);
    const startDate = args.p_start_date === undefined ? undefined : dateArg(args.p_start_date);
    const endDate = args.p_end_date === undefined ? undefined : dateArg(args.p_end_date);
    const place = args.p_place === undefined ? undefined : normalizePlace(args.p_place, "visit");
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

      const start = startDate ?? existing?.start_date;
      const end = endDate ?? existing?.end_date;
      if (start === undefined || end === undefined) {
        return fail("23514", "a new visit needs its first and last day");
      }
      checkVisitDates(start, end);
      const earliest = earliestLocalDate(nowIso());
      if (end >= earliest) {
        const others = (await openVisits(ctx, coupleId, earliest)).filter((row) => row.id !== visitId);
        if (others.length >= MAX_OPEN_VISITS_PER_COUPLE) {
          return fail("23514", `a couple can have at most ${MAX_OPEN_VISITS_PER_COUPLE} visits that are not over`);
        }
      }
      const fields = {
        start_date: start,
        end_date: end,
        place: place === undefined ? existing?.place : (place ?? undefined),
        last_edited_by_user_id: userId,
      };
      const now = nowIso();
      if (existing && existing.start_date === start && existing.end_date === end) {
        await ctx.db.patch(existing._id, withUpdatedAt(fields));
      } else if (existing) {
        await keepVisitDays(ctx, existing, now);
        const togetherFrom = await coupleDateAt(ctx, coupleId, now);
        await ctx.db.patch(existing._id, withUpdatedAt({ ...fields, together_from: togetherFrom }));
      } else {
        await ctx.db.insert("visits", {
          id: visitId,
          couple_id: coupleId,
          ...fields,
          together_from: await coupleDateAt(ctx, coupleId, now),
          created_by_user_id: userId,
          created_at: now,
          updated_at: now,
        });
      }
      await refreshPartnerLockScreen(ctx, coupleId, userId);
      // A visit moves the days the streak needs, so its deadline and reminders follow at once.
      await detectStreakBreak(ctx, coupleId);
      return null;
    });
    // Read after the operation, so a replay returns today's row and not the answer it stored back
    // then, which a partner's edit may have replaced.
    return await currentVisit(ctx, visitId, coupleId);
  },
});

/**
 * Deletes the visit `p_visit_id` for both partners. The list stays. A missing or already deleted one
 * is fine, and a save of it from the same phone that arrives later changes nothing.
 */
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
      const now = nowIso();
      await keepVisitDays(ctx, existing, now);
      await ctx.db.patch(existing._id, withUpdatedAt({ deleted_at: now, last_edited_by_user_id: userId }));
      await refreshPartnerLockScreen(ctx, coupleId, userId);
      await detectStreakBreak(ctx, coupleId);
      return null;
    });
    return null;
  },
});

/** Adds `itemId` with `title`, ticked by `userId` when `done`, unless the list is full. */
async function insertItem(ctx: WriterCtx, coupleId: string, userId: string, itemId: string, title: string, done: boolean) {
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
    ...(done ? { done_at: now, done_by_user_id: userId } : {}),
    created_at: now,
    updated_at: now,
  });
}

const itemTitle = (title: string) => requireTitle(title, MAX_TOGETHER_ITEM_TITLE_CODE_POINTS, "list item title");

/**
 * Adds the list item `p_item_id`. An item that exists, deleted or not, stays as it is, and so does
 * one that a later tick or delete from the same phone already wrote. Fails with `23514` for an
 * empty or long title, or when the list is full. Returns the item as stored now, or null when it is
 * deleted or was never added.
 */
export const save_together_item = mutation({
  args: { p_item_id: v.string(), p_title: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const itemId = uuidArg(args.p_item_id);
    const title = itemTitle(args.p_title);
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
      if (existing || (await isSupersededClientOperation(ctx, userId, input))) return null;
      await insertItem(ctx, coupleId, userId, itemId, title, false);
      return null;
    });
    return await currentItem(ctx, itemId, coupleId);
  },
});

/**
 * Ticks (`p_done: true`) or unticks the list item `p_item_id`. Ticking a ticked item keeps who ticked
 * it first. When the item's add has not arrived yet, this adds it with `p_title`, so it fails like
 * `save_together_item` for a bad title or a full list. Returns the item as stored now, or null when
 * it is deleted.
 */
export const set_together_item_done = mutation({
  args: { p_item_id: v.string(), p_title: v.string(), p_done: v.boolean(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const itemId = uuidArg(args.p_item_id);
    const title = itemTitle(args.p_title);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "set_together_item_done",
      scope: `together_item:${itemId}`,
      request: { kind: "set_together_item_done", couple_id: coupleId, id: itemId, title, done: args.p_done },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "together_list_items", itemId);
      if (existing && existing.couple_id !== coupleId) {
        return fail("42501", "list item belongs to another couple");
      }
      if (existing?.deleted_at !== undefined || (await isSupersededClientOperation(ctx, userId, input))) {
        return null;
      }
      if (!existing) {
        await insertItem(ctx, coupleId, userId, itemId, title, args.p_done);
        return null;
      }
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

/**
 * Deletes the list item `p_item_id` for both partners. A missing or already deleted one is fine, and
 * an add or tick of it from the same phone that arrives later changes nothing.
 */
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
