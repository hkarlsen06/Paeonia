import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent, listActiveMembers } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { fail } from "./errors";
import { enqueueNotificationForUser } from "./notifications";
import { gameRoom, onlineUserIds } from "./presence";
import { addMs, nowIso } from "./time";
import type { GAME_KINDS } from "./validators";

// Helpers every game shares: settings, presence, invites, and pushes. Draw & Guess has its own
// in drawAndGuess.ts. This file must not import the registry (gameRegistry.ts) or any game.

export type GameKind = (typeof GAME_KINDS)[number];
export type GameSettings = Doc<"game_settings">;

/** The game screen counts as closed this long after its last heartbeat. The app sends one every 30 seconds. */
export const GAME_PRESENCE_TIMEOUT_MS = 60_000;
export const INVITE_INTERVAL_MS = 15 * 60_000;
export const TURN_REMINDER_AFTER_MS = 72 * 3_600_000;

/**
 * Names the current copy of the game data, from `PAEONIA_DATA_EPOCH`. Every game state read returns it.
 * A phone keeps its own newer copy of a game over an older answer, so after a backup restore or a hand
 * edit that removes or rolls back game rows, set a new value. A phone that sees another value takes the
 * server's games as they are.
 */
export function dataEpoch(): string {
  return process.env.PAEONIA_DATA_EPOCH ?? "";
}

// --- Lookups ----------------------------------------------------------------

export async function getGameSettings(ctx: ReaderCtx, coupleId: string): Promise<GameSettings | null> {
  return await ctx.db
    .query("game_settings")
    .withIndex("by_couple_id", (q) => q.eq("couple_id", coupleId))
    .unique();
}

export async function requireGameSettings(ctx: ReaderCtx, coupleId: string): Promise<GameSettings> {
  const settings = await getGameSettings(ctx, coupleId);
  if (!settings) return fail("23514", "game settings are required");
  return settings;
}

/** Fails with 42501 unless `userId` is an active, entitled member of the couple. */
export async function requireCoupleAccess(ctx: ReaderCtx, userId: string, coupleId: string): Promise<void> {
  if (!(await canAccessCoupleContent(ctx, userId, coupleId))) {
    fail("42501", "active entitled couple access is required");
  }
}

/** The active partner of `userId`. Fails with 23514 when there is none. */
export async function requirePartnerId(ctx: ReaderCtx, coupleId: string, userId: string): Promise<string> {
  const partner = (await listActiveMembers(ctx, coupleId)).find((member) => member.user_id !== userId);
  if (!partner) return fail("23514", "a game needs two active partners");
  return partner.user_id;
}

// --- Presence ---------------------------------------------------------------

/** True while the user has the game screen open, per the presence component. */
export async function isGamePresent(ctx: ReaderCtx, coupleId: string, kind: GameKind, userId: string): Promise<boolean> {
  return (await onlineUserIds(ctx, gameRoom(coupleId, kind))).includes(userId);
}

// --- Notifications ----------------------------------------------------------

/**
 * `game_turn_ready`: the partner's move is done and it is your turn. `game_result`: the partner
 * finished something you were waiting to see. `game_invite`: "want to play?". `game_turn_reminder`:
 * your turn waited `TURN_REMINDER_AFTER_MS`.
 */
export type GamePushKind = "game_turn_ready" | "game_result" | "game_invite" | "game_turn_reminder";

/** The link a game push opens: `paeonia://games/draw-and-guess`, `paeonia://games/mind-meld`, and so on. */
export function gameDeepLink(kind: GameKind): string {
  return `paeonia://games/${kind.replaceAll("_", "-")}`;
}

/**
 * Queues one lock-screen-safe push. The payload names the game and the people, never the
 * move, a word, or a drawing. `skipIfPresent` drops the push when the recipient has the game open.
 * Returns the number of rows queued.
 */
export async function enqueueGamePush(
  ctx: WriterCtx,
  args: {
    kind: GamePushKind;
    game_kind: GameKind;
    couple_id: string;
    game_id?: string;
    round_id?: string;
    actor_user_id: string;
    recipient_user_id: string;
    dedupe_key: string;
    skipIfPresent?: boolean;
    /** A fixed token the game picks, such as `last_line`, never content. It picks the copy in `GamePushCopy.steps`. */
    step?: string;
    /** Sends the push this long from now instead of at once. The drain checks it again when it is due. */
    delay_ms?: number;
  },
): Promise<number> {
  if (args.skipIfPresent && (await isGamePresent(ctx, args.couple_id, args.game_kind, args.recipient_user_id))) {
    return 0;
  }
  return await enqueueNotificationForUser(ctx, {
    recipient_user_id: args.recipient_user_id,
    kind: args.kind,
    payload: {
      type: args.kind,
      game_kind: args.game_kind,
      couple_id: args.couple_id,
      ...(args.game_id ? { game_id: args.game_id } : {}),
      ...(args.round_id ? { round_id: args.round_id } : {}),
      ...(args.step ? { step: args.step } : {}),
      actor_user_id: args.actor_user_id,
      route: "games",
      deeplink: gameDeepLink(args.game_kind),
    },
    dedupe_key: args.dedupe_key,
    redaction_level: "private",
    apns_push_type: "alert",
    apns_collapse_id: `${args.kind}:${args.couple_id}`,
    scheduled_for: args.delay_ms ? addMs(nowIso(), args.delay_ms) : nowIso(),
  });
}

// --- Reads ------------------------------------------------------------------

export function settingsJson(settings: GameSettings) {
  return {
    couple_id: settings.couple_id,
    play_style: settings.play_style,
    language: settings.language,
    updated_by_user_id: settings.updated_by_user_id,
    created_at: settings.created_at,
    updated_at: settings.updated_at,
  };
}
