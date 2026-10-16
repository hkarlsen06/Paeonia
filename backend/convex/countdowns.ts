import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { isSupersededClientOperation, runClientOperation } from "./lib/clientOperations";
import { getByUuid, withUpdatedAt, type ReaderCtx, type WriterCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { dateArg, uuidArg } from "./lib/ids";
import { enqueueLockScreenRefreshForPartner, LOCK_SCREEN_REFRESH_DELAY_SECONDS } from "./lib/notifications";
import { addDaysToDate, nowIso } from "./lib/time";

// The couple's own dates on the milestones timeline: countdowns either partner adds
// ("Trip to Bergen") and both partners' birthdays. The relationship milestones are derived
// on the phone from couples.started_on and are not stored here.

/** The app caps titles at 40 characters. Code points are counted here, so an emoji never trips it. */
const MAX_TITLE_CODE_POINTS = 80;
const MAX_COUNTDOWNS_PER_COUPLE = 50;

/** The partner's Lock Screen widget lists the next countdowns, so any change to them refreshes it. */
const refreshPartnerLockScreen = (ctx: WriterCtx, coupleId: string, userId: string) =>
  enqueueLockScreenRefreshForPartner(ctx, {
    couple_id: coupleId,
    actor_user_id: userId,
    delay_seconds: LOCK_SCREEN_REFRESH_DELAY_SECONDS,
  });

function countdownRow(row: Doc<"countdowns">) {
  return {
    id: row.id,
    title: row.title,
    target_date: row.target_date,
    created_by_user_id: row.created_by_user_id,
    updated_at: row.updated_at,
  };
}

async function liveCountdowns(ctx: ReaderCtx, coupleId: string) {
  return await ctx.db
    .query("countdowns")
    .withIndex("by_couple_id_deleted_at", (q) => q.eq("couple_id", coupleId).eq("deleted_at", undefined))
    .collect();
}

/**
 * The caller's couple's countdowns, soonest first, and the birthdays set for its active
 * members. The app subscribes to this. Fails with `42501` without an entitled couple.
 */
export const get_countdowns = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const countdowns = (await liveCountdowns(ctx, coupleId))
      .sort((a, b) => (a.target_date < b.target_date ? -1 : a.target_date > b.target_date ? 1 : a.id < b.id ? -1 : 1))
      .map(countdownRow);
    const birthdays = (await listActiveMembers(ctx, coupleId))
      .filter((member) => member.birthday !== undefined)
      .map((member) => ({ user_id: member.user_id, birthday: member.birthday! }));
    return { couple_id: coupleId, countdowns, birthdays };
  },
});

/** The countdown as stored now, or null when it is missing, deleted, or another couple's. */
async function currentCountdown(ctx: ReaderCtx, countdownId: string, coupleId: string) {
  const row = await getByUuid(ctx, "countdowns", countdownId);
  return row && row.couple_id === coupleId && row.deleted_at === undefined ? countdownRow(row) : null;
}

/**
 * Creates or edits the countdown `p_countdown_id`. The phone picks the id, so a create and
 * its retries are the same write. A deleted countdown stays deleted, and a retry that a
 * newer write from the same phone already replaced changes nothing. That includes a create
 * whose first send failed while the delete after it went through. Returns the countdown as
 * stored now, also on a replay, or null when it was deleted.
 */
export const save_countdown = mutation({
  args: { p_countdown_id: v.string(), p_title: v.string(), p_target_date: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const countdownId = uuidArg(args.p_countdown_id);
    const title = args.p_title.trim();
    if (title.length === 0 || Array.from(title).length > MAX_TITLE_CODE_POINTS) {
      fail("23514", "countdown title must be 1 to 40 characters");
    }
    const targetDate = dateArg(args.p_target_date);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "save_countdown",
      scope: `countdown:${countdownId}`,
      request: { kind: "save_countdown", couple_id: coupleId, id: countdownId, title, target_date: targetDate },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "countdowns", countdownId);
      if (existing && existing.couple_id !== coupleId) {
        return fail("42501", "countdown belongs to another couple");
      }
      if (existing?.deleted_at !== undefined || (await isSupersededClientOperation(ctx, userId, input))) {
        return null;
      }

      if (existing) {
        await ctx.db.patch(existing._id, withUpdatedAt({ title, target_date: targetDate, last_edited_by_user_id: userId }));
        await refreshPartnerLockScreen(ctx, coupleId, userId);
        return null;
      }
      if ((await liveCountdowns(ctx, coupleId)).length >= MAX_COUNTDOWNS_PER_COUPLE) {
        return fail("23514", `a couple can have at most ${MAX_COUNTDOWNS_PER_COUPLE} countdowns`);
      }
      const now = nowIso();
      await ctx.db.insert("countdowns", {
        id: countdownId,
        couple_id: coupleId,
        title,
        target_date: targetDate,
        created_by_user_id: userId,
        last_edited_by_user_id: userId,
        created_at: now,
        updated_at: now,
      });
      await refreshPartnerLockScreen(ctx, coupleId, userId);
      return null;
    });
    // Read after the operation, so a replay returns today's row and not the answer it stored
    // back then, which a partner's edit may have replaced.
    return await currentCountdown(ctx, countdownId, coupleId);
  },
});

/** Deletes the countdown `p_countdown_id` for both partners. A missing or already deleted one is fine. */
export const delete_countdown = mutation({
  args: { p_countdown_id: v.string(), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const countdownId = uuidArg(args.p_countdown_id);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);

    const input = toClientOperation(args, {
      kind: "delete_countdown",
      scope: `countdown:${countdownId}`,
      request: { kind: "delete_countdown", couple_id: coupleId, id: countdownId },
    });
    await runClientOperation(ctx, userId, input, async () => {
      const existing = await getByUuid(ctx, "countdowns", countdownId);
      if (!existing || existing.deleted_at !== undefined) return null;
      if (existing.couple_id !== coupleId) {
        return fail("42501", "countdown belongs to another couple");
      }
      await ctx.db.patch(existing._id, withUpdatedAt({ deleted_at: nowIso(), last_edited_by_user_id: userId }));
      await refreshPartnerLockScreen(ctx, coupleId, userId);
      return null;
    });
    return null;
  },
});

/**
 * Sets or removes (`p_birthday: null`) the birthday of `p_user_id`, who is the caller or
 * the partner. A birthday later than tomorrow in UTC fails with `23514`. Returns the
 * birthday as stored now, also on a replay.
 */
export const set_birthday = mutation({
  args: { p_user_id: v.string(), p_birthday: v.union(v.null(), v.string()), ...clientOperationArgs },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const targetUserId = uuidArg(args.p_user_id);
    const birthday = args.p_birthday === null ? null : dateArg(args.p_birthday);
    // Tomorrow in UTC is today or later in every time zone, so no phone's today is refused.
    if (birthday !== null && birthday > addDaysToDate(nowIso().slice(0, 10), 1)) {
      fail("23514", "birthday must be today or earlier");
    }
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const member = (await listActiveMembers(ctx, coupleId)).find((row) => row.user_id === targetUserId);
    if (!member) {
      return fail("42501", "birthday owner is not in this relationship");
    }

    const input = toClientOperation(args, {
      kind: "set_birthday",
      scope: `couple:${coupleId}:birthday:${targetUserId}`,
      request: { kind: "set_birthday", couple_id: coupleId, user_id: targetUserId, birthday },
    });
    await runClientOperation(ctx, userId, input, async () => {
      if (!(await isSupersededClientOperation(ctx, userId, input))) {
        await ctx.db.patch(member._id, withUpdatedAt({ birthday: birthday ?? undefined }));
      }
      return null;
    });
    const current = (await ctx.db.get(member._id))!;
    return { user_id: targetUserId, birthday: current.birthday ?? null };
  },
});
