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
import { openGameInvitesFor, type GameKind, type GamePushKind, type GameWait } from "./games";
import { nowIso } from "./time";
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
  /** Deletes the couple's rows in this game's own tables and returns how many. Shared rows (settings, presence, invites, play times, hidden waits) are deleted for it. */
  deleteCoupleRows(ctx: WriterCtx, coupleId: string): Promise<number>;
  /** Sends the single reminder for each turn that waited TURN_REMINDER_AFTER_MS. Returns the pushes queued. Leave out for a game without turns. */
  sendDueTurnReminders?(ctx: WriterCtx, now: string): Promise<number>;
  /** The couple changed the game language. Redo content already offered in the old language. */
  onLanguageChanged?(ctx: WriterCtx, coupleId: string, language: GameLanguage): Promise<void>;
  /**
   * The couple's games of this backend that wait for `userId`, one wait per game: it is their turn,
   * or they have not seen the newest result. A game gives one wait even when both are true, with the
   * turn's key, and none for what waits for the partner. A key must change with every new turn and
   * every newer result, because a wait hidden with "Not now" comes back when its key changes. Leave
   * out for a game that only plays while both are online.
   */
  waitingFor?(ctx: ReaderCtx, coupleId: string, userId: string): Promise<GameWait[]>;
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
  let wanted = backend ? await backend.pushStillWanted(ctx, push, payload, recipientUserId) : false;
  // The recipient said "Not now" to the turn the reminder is about.
  if (wanted && kind && push === "game_turn_reminder") wanted = !(await hiddenGameKinds(ctx, coupleId, recipientUserId)).includes(kind);
  return wanted ? { wanted: true } : { wanted: false, reason: "out_of_date" };
}

/**
 * Everything that waits for `userId` in the couple: each backend's `waitingFor`, plus the partner's
 * invites that are still open. The board games share one backend, which gives the waits of all of
 * them, so each backend runs once. The caller checks couple access.
 */
async function gameWaits(ctx: ReaderCtx, coupleId: string, userId: string): Promise<GameWait[]> {
  const waits = await openGameInvitesFor(ctx, coupleId, userId);
  for (const backend of new Set(registered())) waits.push(...((await backend.waitingFor?.(ctx, coupleId, userId)) ?? []));
  return waits;
}

/** The wait keys `userId` hid with "Not now", by kind. */
async function hiddenWaitKeys(ctx: ReaderCtx, coupleId: string, userId: string): Promise<Map<GameKind, Set<string>>> {
  const rows = await ctx.db
    .query("game_hidden_waits")
    .withIndex("by_couple_id_user_id_kind", (q) => q.eq("couple_id", coupleId).eq("user_id", userId))
    .collect();
  return new Map(rows.map((row) => [row.kind, new Set(row.wait_keys)]));
}

/**
 * How many games wait for `userId` in the couple, for the app icon badge and the Games tab badge.
 * A wait the person hid with "Not now" does not count. The caller checks couple access.
 */
export async function gamesWaitingFor(ctx: ReaderCtx, coupleId: string, userId: string): Promise<number> {
  const hidden = await hiddenWaitKeys(ctx, coupleId, userId);
  return (await gameWaits(ctx, coupleId, userId)).filter((wait) => !hidden.get(wait.kind)?.has(wait.key)).length;
}

/**
 * The kinds `userId` put aside with "Not now": every wait of the kind was there when they hid it.
 * A new turn, result or invite has a new key, so the kind is no longer hidden. The caller checks
 * couple access.
 */
export async function hiddenGameKinds(ctx: ReaderCtx, coupleId: string, userId: string): Promise<GameKind[]> {
  const hidden = await hiddenWaitKeys(ctx, coupleId, userId);
  if (hidden.size === 0) return [];
  const waits = await gameWaits(ctx, coupleId, userId);
  return GAME_KINDS.filter((kind) => {
    const keys = hidden.get(kind);
    return keys !== undefined && waits.every((wait) => wait.kind !== kind || keys.has(wait.key));
  });
}

/** "Not now": keeps what waits for `userId` in `kind` today from counting or showing until it changes. Safe to repeat. */
export async function hideGameWaits(ctx: WriterCtx, coupleId: string, userId: string, kind: GameKind): Promise<void> {
  const keys = (await gameWaits(ctx, coupleId, userId)).filter((wait) => wait.kind === kind).map((wait) => wait.key);
  const row = await ctx.db
    .query("game_hidden_waits")
    .withIndex("by_couple_id_user_id_kind", (q) => q.eq("couple_id", coupleId).eq("user_id", userId).eq("kind", kind))
    .unique();
  if (!row) {
    await ctx.db.insert("game_hidden_waits", { couple_id: coupleId, user_id: userId, kind, wait_keys: keys, hidden_at: nowIso() });
  } else if (row.wait_keys.join("\n") !== keys.join("\n")) {
    await ctx.db.patch(row._id, { wait_keys: keys, hidden_at: nowIso() });
  }
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
 * Deletes every game row of a couple: the shared settings, invites, play times and hidden waits, then each game's own rows.
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
    ...(await ctx.db.query("game_hidden_waits").withIndex("by_couple_id_user_id_kind", (q) => q.eq("couple_id", coupleId)).collect()),
  ];
  for (const row of shared) {
    await ctx.db.delete(row._id);
    deleted += 1;
  }
  for (const backend of registered()) deleted += await backend.deleteCoupleRows(ctx, coupleId);
  return deleted;
}
