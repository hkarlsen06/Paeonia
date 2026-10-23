import { v } from "convex/values";
import { internal } from "./_generated/api";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId, listActiveMembers } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { orNull, type WriterCtx } from "./lib/db";
import { fail } from "./lib/errors";
import {
  answerGameInvite,
  enqueueGamePush,
  GAME_PRESENCE_TIMEOUT_MS,
  type GameKind,
  getGameSettings,
  INVITE_INTERVAL_MS,
  PLAYED_AT_INTERVAL_MS,
  requireGameSettings,
  requirePartnerId,
  settingsJson,
} from "./lib/games";
import { signLiveTicket } from "./lib/liveTicket";
import { gameRoom, openGameKinds, setPresent } from "./lib/presence";
import { addMs, nowIso } from "./lib/time";
import { GAME_KINDS, gameKind, gameLanguage, gamePlayStyle } from "./lib/validators";

// Functions every game shares: settings, the overview, invites, presence, the relay ticket, and
// the crons. Each game's own functions are in its module (drawAndGuess.ts). What a game plugs
// into this file is in lib/gameRegistry.ts. This file must not import the registry, because that loads every
// game on each call. The jobs that need it are in gameHooks.ts.

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
        seen_by_user_ids: withSeen(existing.seen_by_user_ids, userId),
        updated_at: now,
      });
      if (existing.language !== args.p_language) {
        await ctx.runMutation(internal.gameHooks.language_changed, { couple_id: coupleId, language: args.p_language });
      }
    } else {
      await ctx.db.insert("game_settings", {
        couple_id: coupleId,
        play_style: args.p_play_style,
        language: args.p_language,
        updated_by_user_id: userId,
        seen_by_user_ids: [userId],
        created_at: now,
        updated_at: now,
      });
    }
    return settingsJson((await getGameSettings(ctx, coupleId))!);
  },
});

/**
 * The caller has seen what their partner picked, so the app stops showing it on any phone. Safe to
 * repeat. Returns the settings.
 */
export const mark_game_settings_seen = mutation({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const settings = await requireGameSettings(ctx, coupleId);
    await ctx.db.patch(settings._id, { seen_by_user_ids: withSeen(settings.seen_by_user_ids, userId) });
    return settingsJson((await getGameSettings(ctx, coupleId))!);
  },
});

function withSeen(userIds: string[], userId: string): string[] {
  return userIds.includes(userId) ? userIds : [...userIds, userId];
}

/**
 * What the Games tab and every game share, for the caller. Subscribe to it. The presence component
 * marks a closed screen offline, and the app judges the invite time. The one clock read is in
 * `hidden_kinds`, which counts a partner's invite as a wait for 15 minutes. A subscriber may keep a
 * kind visible after that until the next write, which is harmless.
 *
 * Result: `{ user_id, partner_user_id, couple_id, settings, presence, hidden_kinds }`. `partner_user_id` is null
 * without an active partner, and `settings` is null until the couple sets them. `presence` has one
 * entry per game kind (in `GAME_KINDS` order) that either partner has open or has ever opened, or
 * the caller sent an invite for, and leaves the other kinds out. An entry is `{ kind, my_present,
 * partner_present, last_invite_at, last_played_at }`. `last_invite_at` is the caller's own last
 * invite for that kind, or null. `last_played_at` is when either partner last had the game open, or
 * null when neither ever opened it. `hidden_kinds` lists the kinds the caller put aside with "Not now"
 * (`hide_waiting_game`) whose waits have not changed since, in `GAME_KINDS` order.
 */
export const get_games_overview = query({
  args: {},
  handler: async (ctx) => {
    const userId = await requireUserId(ctx);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    const settings = await getGameSettings(ctx, coupleId);
    const partnerId = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId)?.user_id ?? null;
    const invites = await ctx.db
      .query("game_invites")
      .withIndex("by_couple_id_kind_sender_user_id", (q) => q.eq("couple_id", coupleId))
      .collect();

    const plays = await ctx.db
      .query("game_plays")
      .withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId))
      .collect();

    const myOpen = await openGameKinds(ctx, coupleId, userId);
    const partnerOpen = partnerId === null ? new Set<string>() : await openGameKinds(ctx, coupleId, partnerId);
    const presence = [];
    for (const kind of GAME_KINDS) {
      const invite = invites.find((row) => row.kind === kind && row.sender_user_id === userId);
      const myPresent = myOpen.has(kind);
      const partnerPresent = partnerOpen.has(kind);
      const play = plays.find((row) => row.kind === kind);
      if (!myPresent && !partnerPresent && !invite && !play) continue;
      presence.push({
        kind,
        my_present: myPresent,
        partner_present: partnerPresent,
        last_invite_at: orNull(invite?.sent_at),
        last_played_at: orNull(play?.last_played_at),
      });
    }

    const hiddenKinds: GameKind[] = await ctx.runQuery(internal.gameHooks.hidden_game_kinds, { couple_id: coupleId, user_id: userId });

    return {
      user_id: userId,
      partner_user_id: partnerId,
      couple_id: coupleId,
      settings: settings ? settingsJson(settings) : null,
      presence,
      hidden_kinds: hiddenKinds,
    };
  },
});

/**
 * "Not now" on a game that waits for the caller. What waits for them in that game stops counting
 * toward the badges, stops putting the game under "Right now" (`hidden_kinds` in the overview), and
 * gets no turn reminder. It comes back by itself with the partner's next move, a new result or a
 * new invite. Safe to repeat. Returns null.
 */
export const hide_waiting_game = mutation({
  args: { p_kind: gameKind },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    await ctx.runMutation(internal.gameHooks.hide_waiting_game, { couple_id: coupleId, user_id: userId, kind: args.p_kind });
    return null;
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
      await ctx.db.patch(previous._id, { sent_at: now, answered_at: undefined });
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
 * after, and `false` when it closes. The presence component marks the screen closed 60
 * seconds after the last `true`, such as when the app was killed. Each call also moves the
 * game's last played time forward (`recordPlayed`), and a `true` answers the partner's invite to the game.
 */
export const set_game_presence = mutation({
  args: { p_kind: gameKind, p_present: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    await setPresent(ctx, gameRoom(coupleId, args.p_kind), userId, args.p_present, GAME_PRESENCE_TIMEOUT_MS);
    await recordPlayed(ctx, coupleId, args.p_kind, args.p_present);
    if (args.p_present) await answerGameInvite(ctx, coupleId, args.p_kind, userId);
    return null;
  },
});

/**
 * Sets when the couple last played a game to now. A heartbeat writes at most every
 * `PLAYED_AT_INTERVAL_MS`, so an open screen does not rerun every overview subscription every 30
 * seconds. Closing the screen always writes.
 */
async function recordPlayed(ctx: WriterCtx, coupleId: string, kind: GameKind, present: boolean): Promise<void> {
  const now = nowIso();
  const row = await ctx.db
    .query("game_plays")
    .withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId).eq("kind", kind))
    .unique();
  if (!row) {
    await ctx.db.insert("game_plays", { couple_id: coupleId, kind, last_played_at: now });
  } else if (!present || row.last_played_at <= addMs(now, -PLAYED_AT_INTERVAL_MS)) {
    await ctx.db.patch(row._id, { last_played_at: now });
  }
}

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
