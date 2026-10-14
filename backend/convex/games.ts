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
  GAME_PRESENCE_TIMEOUT_MS,
  getGameSettings,
  INVITE_INTERVAL_MS,
  requirePartnerId,
  settingsJson,
} from "./lib/games";
import { signLiveTicket } from "./lib/liveTicket";
import { gameRoom, onlineUserIds, setPresent } from "./lib/presence";
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
 * clock: the presence component marks a closed screen offline, and the app judges the invite time.
 *
 * Result: `{ user_id, partner_user_id, couple_id, settings, presence }`. `partner_user_id` is null
 * without an active partner, and `settings` is null until the couple sets them. `presence` has one
 * entry per game kind (in `GAME_KINDS` order) that either partner has open or the caller sent an
 * invite for, and leaves the other kinds out. An entry is `{ kind, my_present, partner_present,
 * last_invite_at }`. `last_invite_at` is the caller's own last invite for that kind, or null.
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

    const presence = [];
    for (const kind of GAME_KINDS) {
      const online = await onlineUserIds(ctx, gameRoom(coupleId, kind));
      const invite = invites.find((row) => row.kind === kind && row.sender_user_id === userId);
      const myPresent = online.includes(userId);
      const partnerPresent = partnerId !== null && online.includes(partnerId);
      if (!myPresent && !partnerPresent && !invite) continue;
      presence.push({ kind, my_present: myPresent, partner_present: partnerPresent, last_invite_at: orNull(invite?.sent_at) });
    }

    return {
      user_id: userId,
      partner_user_id: partnerId,
      couple_id: coupleId,
      settings: settings ? settingsJson(settings) : null,
      presence,
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
 * after, and `false` when it closes. The presence component marks the screen closed 60
 * seconds after the last `true`, such as when the app was killed.
 */
export const set_game_presence = mutation({
  args: { p_kind: gameKind, p_present: v.boolean() },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    await assertNoPendingAccountDeletion(ctx, userId);
    const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
    await setPresent(ctx, gameRoom(coupleId, args.p_kind), userId, args.p_present, GAME_PRESENCE_TIMEOUT_MS);
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

/** The single reminder for each turn that waited 72 hours, for every game with turns. Returns the pushes queued. */
export const send_due_game_turn_reminders = internalMutation({
  args: {},
  handler: async (ctx) => await sendDueGameTurnReminders(ctx, nowIso()),
});
