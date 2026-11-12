import { v } from "convex/values";
import { internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import { internalMutation, mutation } from "./_generated/server";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { sha256Hex } from "./lib/crypto";
import { getByUuid, type WriterCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { newUuid, uuidArg } from "./lib/ids";
import { activityTokens, checkGameActivity, moveGameActivity, queueActivityPush, queueLiveActivityPush } from "./lib/liveActivities";
import { consumeRateLimit } from "./lib/rateLimits";
import { btrimToNull, charLength } from "./lib/text";
import { gameKind, literals } from "./lib/validators";
import { nowIso } from "./lib/time";

// The Live Activity that shows the partner's game session (lib/liveActivities.ts). The app
// registers the tokens ActivityKit gives it here, says when it ended an activity on its own, and
// ends its install when the sign-in ends.

/** One account keeps at most this many push-to-start tokens, so a start reaches at most this many phones. */
export const MAX_START_TOKENS = 5;

/**
 * Saves an ActivityKit token of this phone. `p_install_id` is the app's id for this sign-in on
 * the phone. `p_kind` `start` is the push-to-start token, and a new one replaces the install's old
 * one. `update` is the token of the running activity `p_activity_id`. A new update token gets the
 * activity's current state at once, so a game switch or a turn that came before the token still
 * reaches the phone. A token belongs to one install at a time, so a phone that signed in again, to
 * this account or another, never holds it twice.
 *
 * Returns `saved` for a start token, `playing` for an update token of the caller's running
 * activity, `ended` for any other activity, which the phone then ends and whose token the server
 * keeps nowhere, and `install_taken` when the install holds another account's tokens, so the phone
 * starts a new one. Nothing is saved for `ended` or `install_taken`.
 */
export const register_live_activity_token = mutation({
  args: {
    p_install_id: v.string(),
    p_kind: v.union(v.literal("start"), v.literal("update")),
    p_token: v.string(),
    p_apns_environment: v.string(),
    p_activity_id: v.optional(v.union(v.null(), v.string())),
    p_locale: v.optional(v.union(v.null(), v.string())),
  },
  handler: async (ctx, args): Promise<"saved" | "playing" | "ended" | "install_taken"> => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const installId = uuidArg(args.p_install_id);
    const tokenLength = charLength(args.p_token);
    if (tokenLength < 20 || tokenLength > 4096) fail("23514", "invalid live activity token");
    if (args.p_apns_environment !== "sandbox" && args.p_apns_environment !== "production") {
      fail("23514", "unsupported APNs environment");
    }
    const environment = args.p_apns_environment;
    const locale = btrimToNull(args.p_locale) ?? undefined;
    if (locale !== undefined && charLength(locale) > 64) fail("23514", "invalid locale");
    const activityId = args.p_kind === "update" ? uuidArg(args.p_activity_id) : undefined;
    await consumeRateLimit(ctx, "liveActivity", userId);

    const installRows = await ctx.db
      .query("live_activity_tokens")
      .withIndex("by_install_id_kind_activity_id", (q) => q.eq("install_id", installId))
      .collect();
    if (installRows.some((row) => row.user_id !== userId)) return "install_taken";
    const activity = activityId === undefined ? null : await getByUuid(ctx, "game_live_activities", activityId);
    if (activityId !== undefined && activity?.viewer_user_id !== userId) return "ended";

    const existing = installRows.find((row) => row.kind === args.p_kind && row.activity_id === activityId);
    const tokenHash = await sha256Hex(args.p_token);
    for (const row of await ctx.db
      .query("live_activity_tokens")
      .withIndex("by_token_hash", (q) => q.eq("token_hash", tokenHash))
      .collect()) {
      if (row._id !== existing?._id) await ctx.db.delete(row._id);
    }

    const now = nowIso();
    const fields: Pick<Doc<"live_activity_tokens">, "token" | "token_hash" | "apns_environment" | "locale" | "updated_at"> = {
      token: args.p_token,
      token_hash: tokenHash,
      apns_environment: environment,
      locale,
      updated_at: now,
    };
    let tokenId = existing?._id;
    if (existing) {
      await ctx.db.patch(existing._id, fields);
      if (existing.token_hash === tokenHash) return activity ? "playing" : "saved";
    } else {
      tokenId = await ctx.db.insert("live_activity_tokens", {
        id: newUuid(),
        user_id: userId,
        install_id: installId,
        kind: args.p_kind,
        ...(activityId === undefined ? {} : { activity_id: activityId }),
        ...fields,
        created_at: now,
      });
    }
    if (!activity) {
      await keepNewestStartTokens(ctx, userId);
      return "saved";
    }
    const token = (await ctx.db.get(tokenId!))!;
    await queueLiveActivityPush(ctx, token, { event: "update", quiet: false, activity_id: activity.id, game_kind: activity.game_kind });
    return "playing";
  },
});

/** Drops the start tokens an account registered least recently beyond `MAX_START_TOKENS`. */
async function keepNewestStartTokens(ctx: WriterCtx, userId: string): Promise<void> {
  const tokens = await ctx.db
    .query("live_activity_tokens")
    .withIndex("by_user_id_kind", (q) => q.eq("user_id", userId).eq("kind", "start"))
    .collect();
  tokens.sort((a, b) => b.updated_at.localeCompare(a.updated_at) || b._creationTime - a._creationTime);
  for (const token of tokens.slice(MAX_START_TOKENS)) await ctx.db.delete(token._id);
}

/**
 * The phone with install `p_install_id` ended activity `p_activity_id` on its own, because it went
 * stale. Nothing more goes to that phone's activity. Another phone of the caller that holds the
 * activity keeps it, with no new alert. When none does, the activity ends and the partner's next
 * heartbeat may start a new one. Does nothing for an activity of another viewer or one that no
 * longer runs. Returns null.
 */
export const end_game_live_activity = mutation({
  args: { p_activity_id: v.string(), p_install_id: v.string() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const activityId = uuidArg(args.p_activity_id);
    const installId = uuidArg(args.p_install_id);
    await consumeRateLimit(ctx, "liveActivity", userId);
    const row = await getByUuid(ctx, "game_live_activities", activityId);
    if (row?.viewer_user_id !== userId) return null;
    const tokens = (await activityTokens(ctx, activityId)).filter((token) => token.user_id === userId);
    for (const token of tokens) {
      if (token.install_id === installId) await ctx.db.delete(token._id);
    }
    if (!tokens.some((token) => token.install_id !== installId)) {
      await moveGameActivity(ctx, row, { kind: "viewer_ended", activity_id: activityId });
    }
    return null;
  },
});

/**
 * The sign-in `p_install_id` ended on the phone, so the install's tokens go. Needs no sign-in,
 * because the session may already be gone when the phone sends it. The id is random and only that
 * phone knows it. An id with no tokens writes nothing, so a flood of made-up ids costs one empty
 * read each. The phone sends it again two minutes later, which removes a registration that was on
 * its way during the sign-out. Returns null.
 */
export const end_live_activity_install = mutation({
  args: { p_install_id: v.string() },
  handler: async (ctx, args) => {
    const installId = uuidArg(args.p_install_id);
    for (const row of await ctx.db
      .query("live_activity_tokens")
      .withIndex("by_install_id_kind_activity_id", (q) => q.eq("install_id", installId))
      .collect()) {
      await ctx.db.delete(row._id);
    }
    return null;
  },
});

/** Rows the `check-game-activities` cron reads in one run. */
const CHECK_PAGE = 50;

/**
 * The cron that looks at every activity, every `GAME_ACTIVITY_CHECK_MS`. It reads the turn again,
 * ends an activity whose partner left every game, keeps one from going stale, and pages through
 * the rows with `cursor`.
 */
export const check_game_activities = internalMutation({
  args: { cursor: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const at = nowIso();
    const page = await ctx.db.query("game_live_activities").paginate({ cursor: args.cursor ?? null, numItems: CHECK_PAGE });
    for (const row of page.page) await checkGameActivity(ctx, row, at);
    if (!page.isDone) {
      await ctx.scheduler.runAfter(0, internal.liveActivities.check_game_activities, { cursor: page.continueCursor });
    }
    return null;
  },
});

/**
 * Queues one start, update or end to each of the viewer's phones that can get it. A start or an
 * update runs only while its activity still runs. One scheduled before the activity ended would
 * carry a later time than the end, and iOS keeps the push with the latest time.
 */
export const queue_game_activity_push = internalMutation({
  args: {
    viewer_user_id: v.string(),
    activity_id: v.string(),
    game_kind: gameKind,
    event: literals("start", "update", "end"),
    quiet: v.boolean(),
  },
  handler: async (ctx, { viewer_user_id, ...push }) => {
    if (push.event !== "end" && !(await getByUuid(ctx, "game_live_activities", push.activity_id))) return null;
    await queueActivityPush(ctx, viewer_user_id, push);
    return null;
  },
});

