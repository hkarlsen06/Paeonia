import { v } from "convex/values";
import { internalMutation, mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { orNull } from "./lib/db";
import { fail } from "./lib/errors";
import { gameLanguageChanged, sendDueGameTurnReminders } from "./lib/gameRegistry";
import {
  enqueueGamePush,
  getGameSettings,
  getPresence,
  INVITE_INTERVAL_MS,
  PRESENCE_DELETE_AFTER_MS,
  requirePartnerId,
  settingsJson,
} from "./lib/games";
import { signLiveTicket } from "./lib/liveTicket";
import { addMs, nowIso } from "./lib/time";
import { GAME_KINDS, gameKind, gameLanguage, gamePlayStyle } from "./lib/validators";

// Functions every game shares: settings, the overview, invites, presence, the relay ticket, and
// the crons. Each game's own functions are in its module (drawAndGuess.ts). What a game plugs
// into this file is in lib/gameRegistry.ts.

// --- Settings ---------------------------------------------------------------

/** Sets the couple's play style and game language. Either partner may call it, and the last write wins. */
export const set_game_settings = mutation({
  args: { p_play_style: gamePlayStyle, p_language: gameLanguage },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const now = nowIso();
    const existing = await getGameSettings(ctx, coupleId);
    if (existing) {
      await ctx.db.patch(existing._id, {
        play_style: args.p_play_style,
        language: args.p_language,
        updated_by_user_id: userId,
        updated_at: now,
      });
      if (existing.language !== args.p_language) await gameLanguageChanged(ctx, coupleId, args.p_language);
    } else {
      await ctx.db.insert("game_settings", {
        couple_id: coupleId,
        play_style: args.p_play_style,
        language: args.p_language,
        updated_by_user_id: userId,
        created_at: now,
        updated_at: now,
      });
    }
    return settingsJson((await getGameSettings(ctx, coupleId))!);
  },
});

/**
 * What the Games tab and every game share, for the caller. Subscribe to it. It does not read the
 * clock: the app decides what counts as recent.
 *
 * Result: `{ user_id, partner_user_id, couple_id, settings, presence }`. `partner_user_id` is null
 * without an active partner, and `settings` is null until the couple sets them. `presence` has one
 * entry per game kind (in `GAME_KINDS` order) that has a presence row for either partner or an
 * invite from the caller, and leaves the other kinds out. An entry is `{ kind, my_last_seen_at,
 * partner_last_seen_at, last_invite_at }`, with null for a missing time. `last_invite_at` is the
 * caller's own last invite for that kind.
 */
export const get_games_overview = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const settings = await getGameSettings(ctx, coupleId);
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;
    const presence = await ctx.db
      .query("game_presence")
      .withIndex("by_couple_id_kind_user_id", (q) => q.eq("couple_id", coupleId))
      .collect();
    const invites = await ctx.db
      .query("game_invites")
      .withIndex("by_couple_id_kind_sender_user_id", (q) => q.eq("couple_id", coupleId))
      .collect();

    return {
      user_id: userId,
      partner_user_id: partnerId,
      couple_id: coupleId,
      settings: settings ? settingsJson(settings) : null,
      presence: GAME_KINDS.flatMap((kind) => {
        const mine = presence.find((row) => row.kind === kind && row.user_id === userId);
        const theirs = presence.find((row) => row.kind === kind && row.user_id === partnerId);
        const invite = invites.find((row) => row.kind === kind && row.sender_user_id === userId);
        if (!mine && !theirs && !invite) return [];
        return [
          {
            kind,
            my_last_seen_at: orNull(mine?.last_seen_at),
            partner_last_seen_at: orNull(theirs?.last_seen_at),
            last_invite_at: orNull(invite?.sent_at),
          },
        ];
      }),
    };
  },
});

// --- Play together ----------------------------------------------------------

/** "Tell [Name] you want to play". One invite per sender per game every 15 minutes. */
export const send_game_invite = mutation({
  args: { p_kind: gameKind },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const partnerId = await requirePartnerId(ctx, coupleId, userId);
    const now = nowIso();
    const previous = await ctx.db
      .query("game_invites")
      .withIndex("by_couple_id_kind_sender_user_id", (q) =>
        q.eq("couple_id", coupleId).eq("kind", args.p_kind).eq("sender_user_id", userId),
      )
      .unique();
    if (previous && previous.sent_at > addMs(now, -INVITE_INTERVAL_MS)) {
      fail("53300", "you can send one invite every 15 minutes");
    }
    if (previous) {
      await ctx.db.patch(previous._id, { sent_at: now });
    } else {
      await ctx.db.insert("game_invites", { couple_id: coupleId, kind: args.p_kind, sender_user_id: userId, sent_at: now });
    }
    await enqueueGamePush(ctx, {
      kind: "game_invite",
      game_kind: args.p_kind,
      couple_id: coupleId,
      actor_user_id: userId,
      recipient_user_id: partnerId,
      dedupe_key: `game_invite:${coupleId}:${args.p_kind}:${userId}:${now}`,
    });
    return { sent_at: now };
  },
});

/**
 * The open game screen. The app sends `true` when the screen opens and every 30 seconds
 * after, and `false` when it closes. A row older than 60 seconds counts as gone.
 */
export const set_game_presence = mutation({
  args: { p_kind: gameKind, p_present: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const existing = await getPresence(ctx, coupleId, args.p_kind, userId);
    if (!args.p_present) {
      if (existing) await ctx.db.delete(existing._id);
      return null;
    }
    const now = nowIso();
    if (existing) {
      await ctx.db.patch(existing._id, { last_seen_at: now });
    } else {
      await ctx.db.insert("game_presence", { couple_id: coupleId, kind: args.p_kind, user_id: userId, last_seen_at: now });
    }
    return null;
  },
});

/**
 * A 60-second ticket for the game's own relay room (`<couple>:<kind>`), so game sockets do not
 * share the widget canvas room. The relay channel is the game kind. Returns null while the relay
 * is not configured.
 */
export const create_game_live_ticket = mutation({
  args: { p_kind: gameKind },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    return await signLiveTicket({ coupleId, userId, channel: args.p_kind });
  },
});

// --- Cron jobs --------------------------------------------------------------

/** Deletes presence rows the app stopped refreshing, such as a phone that lost power. */
export const cleanup_stale_game_presence = internalMutation({
  args: {},
  handler: async (ctx) => {
    const cutoff = addMs(nowIso(), -PRESENCE_DELETE_AFTER_MS);
    const stale = await ctx.db
      .query("game_presence")
      .withIndex("by_last_seen_at", (q) => q.lt("last_seen_at", cutoff))
      .take(200);
    for (const row of stale) await ctx.db.delete(row._id);
    return stale.length;
  },
});

/** The single reminder for each turn that waited 72 hours, for every game with turns. Returns the pushes queued. */
export const send_due_game_turn_reminders = internalMutation({
  args: {},
  handler: async (ctx) => await sendDueGameTurnReminders(ctx, nowIso()),
});
