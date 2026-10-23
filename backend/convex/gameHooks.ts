import { v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";
import { queueBadgeUpdate } from "./lib/badges";
import { gameLanguageChanged, hiddenGameKinds, hideGameWaits, sendDueGameTurnReminders } from "./lib/gameRegistry";
import { nowIso } from "./lib/time";
import { gameKind, gameLanguage } from "./lib/validators";

// The jobs that need every game's backend (lib/gameRegistry.ts). They live in their own module
// so games.ts, whose queries run on every app launch, does not load all game code on each call.
// Convex evaluates a function's whole import graph on every call, and there is no lazy import.

/** The couple changed the game language. Redoes content that every game already offered. `games.set_game_settings` calls it. */
export const language_changed = internalMutation({
  args: { couple_id: v.string(), language: gameLanguage },
  handler: async (ctx, args): Promise<null> => {
    await gameLanguageChanged(ctx, args.couple_id, args.language);
    return null;
  },
});

/** The single reminder for each turn that waited 72 hours, for every game with turns. Returns the pushes queued. */
export const send_due_game_turn_reminders = internalMutation({
  args: {},
  handler: async (ctx): Promise<number> => await sendDueGameTurnReminders(ctx, nowIso()),
});

/**
 * The kinds the user put aside with "Not now", for `games.get_games_overview`. Reads every game's
 * waits, so the overview re-runs when one changes. The caller checks couple access.
 */
export const hidden_game_kinds = internalQuery({
  args: { couple_id: v.string(), user_id: v.string() },
  handler: async (ctx, args) => await hiddenGameKinds(ctx, args.couple_id, args.user_id),
});

/** "Not now" on a game, run by `games.hide_waiting_game` after its access check. Updates the icon badge on the user's other phones. */
export const hide_waiting_game = internalMutation({
  args: { couple_id: v.string(), user_id: v.string(), kind: gameKind },
  handler: async (ctx, args): Promise<null> => {
    await hideGameWaits(ctx, args.couple_id, args.user_id, args.kind);
    await queueBadgeUpdate(ctx, args.user_id);
    return null;
  },
});
