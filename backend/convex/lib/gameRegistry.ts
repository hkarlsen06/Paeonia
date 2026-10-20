import { canAccessCoupleContent } from "./access";
import { boardGameBackend } from "./boardGameBackend";
import { consensioBackend } from "./consensio";
import type { ReaderCtx, WriterCtx } from "./db";
import { drawAndGuessBackend } from "./drawAndGuess";
import { exquisiteCorpseBackend } from "./exquisiteCorpse";
import { guessMySpotBackend } from "./guessMySpot";
import { mindMeldBackend } from "./mindMeld";
import { storyChainBackend } from "./storyChain";
import type { GameLanguage } from "./gameWords";
import { openGameInvitesFor, type GameKind, type GamePushKind } from "./games";
import { GAME_KINDS } from "./validators";

// The one place a game registers its backend hooks. The shared games code (games.ts, pushQueue.ts,
// relationship cleanup) calls the dispatchers below and never names a game. A new game adds its
// entry to GAME_BACKENDS. The push copy has its own table in notificationCopy.ts.

/** What the shared games code needs from one game. Each built game adds its entry to GAME_BACKENDS. */
export type GameBackend = {
  /** Whether a queued push of this game still has a reason to go out. Couple access is already checked, and invites never reach this. */
  pushStillWanted(
    ctx: ReaderCtx,
    push: GamePushKind,
    payload: Record<string, unknown>,
    recipientUserId: string,
  ): Promise<boolean>;
  /** Deletes the couple's rows in this game's own tables and returns how many. Shared rows (settings, presence, invites, play times) are deleted for it. */
  deleteCoupleRows(ctx: WriterCtx, coupleId: string): Promise<number>;
  /** Sends the single reminder for each turn that waited TURN_REMINDER_AFTER_MS. Returns the pushes queued. Leave out for a game without turns. */
  sendDueTurnReminders?(ctx: WriterCtx, now: string): Promise<number>;
  /** The couple changed the game language. Redo content already offered in the old language. */
  onLanguageChanged?(ctx: WriterCtx, coupleId: string, language: GameLanguage): Promise<void>;
  /**
   * How many of the couple's games of this backend wait for `userId`: it is their turn, or they have
   * not seen the newest result. A game counts once even when both are true, and never for what waits
   * for the partner. Leave out for a game that only plays while both are online.
   */
  waitingFor?(ctx: ReaderCtx, coupleId: string, userId: string): Promise<number>;
};

/** A kind without an entry has no backend yet. */
export const GAME_BACKENDS: Record<GameKind, GameBackend | null> = {
  draw_and_guess: drawAndGuessBackend,
  mind_meld: mindMeldBackend,
  exquisite_corpse: exquisiteCorpseBackend,
  story_chain: storyChainBackend,
  // The board games share one backend, which works on the couple's rows of every board game.
  connect_four: boardGameBackend,
  dots_and_boxes: boardGameBackend,
  ultimate_tic_tac_toe: boardGameBackend,
  ludo: boardGameBackend,
  consensio: consensioBackend,
  guess_my_spot: guessMySpotBackend,
};

const registered = (): GameBackend[] => GAME_KINDS.flatMap((kind) => GAME_BACKENDS[kind] ?? []);

/**
 * Whether a queued game push still has a reason to go out to `recipientUserId`, checked when the
 * push drain claims it. The recipient must still have couple access. An invite is wanted after that.
 * Any other push belongs to the game named in `payload.game_kind`, which decides. A kind without an
 * entry in `GAME_BACKENDS` has nothing to wait for, so its pushes are out of date.
 */
export async function gamePushStillWanted(
  ctx: ReaderCtx,
  push: GamePushKind,
  payload: Record<string, unknown>,
  recipientUserId: string,
): Promise<{ wanted: true } | { wanted: false; reason: "ineligible" | "out_of_date" }> {
  const coupleId = typeof payload.couple_id === "string" ? payload.couple_id : null;
  if (!coupleId || !(await canAccessCoupleContent(ctx, recipientUserId, coupleId))) return { wanted: false, reason: "ineligible" };
  if (push === "game_invite") return { wanted: true };
  const kind = GAME_KINDS.find((item) => item === payload.game_kind);
  const backend = kind ? GAME_BACKENDS[kind] : null;
  const wanted = backend ? await backend.pushStillWanted(ctx, push, payload, recipientUserId) : false;
  return wanted ? { wanted: true } : { wanted: false, reason: "out_of_date" };
}

/**
 * How many games wait for `userId` in the couple, for the app icon badge: each backend's
 * `waitingFor`, plus the partner's invites that are still open. The board games share one backend,
 * which counts all of them, so each backend counts once. The caller checks couple access.
 */
export async function gamesWaitingFor(ctx: ReaderCtx, coupleId: string, userId: string): Promise<number> {
  let waiting = await openGameInvitesFor(ctx, coupleId, userId);
  for (const backend of new Set(registered())) waiting += (await backend.waitingFor?.(ctx, coupleId, userId)) ?? 0;
  return waiting;
}

/** Tells every game that the couple changed the game language. */
export async function gameLanguageChanged(ctx: WriterCtx, coupleId: string, language: GameLanguage): Promise<void> {
  for (const backend of registered()) await backend.onLanguageChanged?.(ctx, coupleId, language);
}

/** Sends the due turn reminders of every game with turns. Returns the pushes queued. */
export async function sendDueGameTurnReminders(ctx: WriterCtx, now: string): Promise<number> {
  let sent = 0;
  for (const backend of registered()) sent += (await backend.sendDueTurnReminders?.(ctx, now)) ?? 0;
  return sent;
}

/**
 * Deletes every game row of a couple: the shared settings, invites, and play times, then each game's own rows.
 * Returns the number of rows deleted. Presence went when the relationship ended
 * (`endRelationshipForPair`). Drawing media is queued for deletion by the couple media sweep in
 * `cleanupCoupleContent`.
 */
export async function deleteCoupleGameRows(ctx: WriterCtx, coupleId: string): Promise<number> {
  let deleted = 0;
  const shared = [
    ...(await ctx.db.query("game_settings").withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId)).collect()),
    ...(await ctx.db.query("game_invites").withIndex("by_couple_id_kind_sender_user_id", (q) => q.eq("couple_id", coupleId)).collect()),
    ...(await ctx.db.query("game_plays").withIndex("by_couple_id_kind", (q) => q.eq("couple_id", coupleId)).collect()),
  ];
  for (const row of shared) {
    await ctx.db.delete(row._id);
    deleted += 1;
  }
  for (const backend of registered()) deleted += await backend.deleteCoupleRows(ctx, coupleId);
  return deleted;
}
