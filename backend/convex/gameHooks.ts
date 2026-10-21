import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import { gameLanguageChanged, sendDueGameTurnReminders } from "./lib/gameRegistry";
import { nowIso } from "./lib/time";
import { gameLanguage } from "./lib/validators";

// The two jobs that need every game's backend (lib/gameRegistry.ts). They live in their own module
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
