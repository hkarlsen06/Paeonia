import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import { type GameKind, isGamePresent, isRealTimeGameKind, type RealTimeGameKind } from "./games";
import { newUuid } from "./ids";
import { enqueuePush } from "./notifications";
import { nowIso } from "./time";
import { isCoupleTogetherAt } from "./together";

// The Live Activity that shows a viewer that their partner is in a real-time game. One row per
// viewer and couple: an activity starts on the partner's first heartbeat, follows the partner to
// another game, and ends a minute or two after the partner left every game. It names the partner
// and the game, never a move. None starts while the couple is together that day.

/** How often the `check-game-activities` cron looks for the partner of each running or held row. */
export const GAME_ACTIVITY_CHECK_MS = 30_000;
/**
 * After the partner closes a game screen, the row goes idle this long after the close unless the
 * partner opens a real-time game again. The cron then ends it 60 to 90 seconds after the close.
 */
export const GAME_ACTIVITY_CLOSE_GRACE_MS = 60_000;
/**
 * A partner whose app was killed or lost its connection sends no close. Presence marks them gone
 * `GAME_PRESENCE_TIMEOUT_MS` after their last heartbeat, and the first check that sees it sets the
 * end this much later. That is less than one check interval, so the next check ends the activity
 * even when the cron runs a little early. The end comes 90 to 120 seconds after that heartbeat,
 * and a partner who is back before the next check keeps the same activity.
 */
export const GAME_ACTIVITY_AWAY_GRACE_MS = 20_000;
/**
 * While the partner keeps playing, a quiet update this often moves the activity's stale date
 * (`LIVE_ACTIVITY_STALE_SECONDS` in lib/apns.ts) forward.
 */
export const GAME_ACTIVITY_REFRESH_MS = 10 * 60_000;

/**
 * `idle`: nothing shows on the viewer's phones, and the partner's next real-time heartbeat checks
 * whether an activity may start. `playing`: activity `id` shows the partner in `game_kind`.
 * `held`: nothing shows and nothing starts while the partner stays in `game_kind`. Either the
 * viewer opened that game too and every phone of the viewer got an end, or the couple was together
 * that day when the partner opened it. `off`: the viewer turned game pushes off.
 */
export type GameActivityPhase = "idle" | "playing" | "held" | "off";

/** The fields of a `game_live_activities` row that `nextGameActivity` moves. */
export type GameActivityState = {
  id: string;
  game_kind: RealTimeGameKind;
  phase: GameActivityPhase;
  /** `playing` and `held`: the row goes idle at this time unless the partner shows up again. */
  ends_at?: string;
  started_at: string;
  /** The last push that moved the activity's stale date. */
  pushed_at: string;
};

/** Whether a heartbeat may start an activity for the viewer, and why not (`startCheck`). */
export type StartCheck = "start" | "no_token" | "pushes_off" | "viewer_present" | "together";

export type GameActivityEvent =
  /** The partner's game screen is open, and `needsStartCheck` said no check is needed. */
  | { kind: "heartbeat"; game_kind: RealTimeGameKind; at: string }
  /** The partner's game screen is open, with the answer of `startCheck`. */
  | { kind: "start_checked"; game_kind: RealTimeGameKind; at: string; new_id: string; start: StartCheck }
  /** The partner closed a real-time game screen. */
  | { kind: "left"; game_kind: RealTimeGameKind; at: string }
  /** The viewer's own game screen is open. */
  | { kind: "viewer_heartbeat"; game_kind: RealTimeGameKind }
  /** A phone of the viewer ended activity `activity_id` on its own, so the server should stop counting on it. */
  | { kind: "viewer_ended"; activity_id: string }
  /** The cron looked for the partner in the real-time games. */
  | { kind: "check"; partner_present: boolean; at: string }
  /** The viewer turned game pushes off or on. */
  | { kind: "pushes_off" }
  | { kind: "pushes_on" };

/**
 * One push to the viewer's phones. A start goes to every push-to-start token of the viewer, an
 * update or an end to every token of activity `activity_id`. `quiet` goes at APNs priority 5.
 */
export type LiveActivityPush = {
  event: "start" | "update" | "end";
  quiet: boolean;
  activity_id: string;
  game_kind: RealTimeGameKind;
};

export type GameActivityStep = { row: GameActivityState; push: LiveActivityPush | null };

/** Whether the partner's heartbeat in `gameKind` needs `startCheck` before `nextGameActivity` can move `row`. */
export function needsStartCheck(row: GameActivityState | null, gameKind: RealTimeGameKind): boolean {
  if (row === null || row.phase === "idle") return true;
  if (row.phase === "off") return false;
  return row.game_kind !== gameKind;
}

/** The only way a `game_live_activities` row moves. Returns null when the event changes nothing. */
export function nextGameActivity(row: GameActivityState | null, event: GameActivityEvent): GameActivityStep | null {
  switch (event.kind) {
    case "heartbeat":
      if (!isWatched(row) || row.game_kind !== event.game_kind || row.ends_at === undefined) return null;
      return { row: withoutEnd(row), push: null };
    case "start_checked":
      return afterStartCheck(row, event);
    case "left": {
      if (!isWatched(row) || row.game_kind !== event.game_kind) return null;
      const endsAt = earlier(row.ends_at, addMs(event.at, GAME_ACTIVITY_CLOSE_GRACE_MS));
      return endsAt === row.ends_at ? null : { row: { ...row, ends_at: endsAt }, push: null };
    }
    case "viewer_heartbeat":
      if (row?.phase !== "playing" || row.game_kind !== event.game_kind) return null;
      return { row: { ...row, phase: "held" }, push: endOf(row) };
    case "viewer_ended":
      if (row?.phase !== "playing" || row.id !== event.activity_id) return null;
      return { row: { ...withoutEnd(row), phase: "idle" }, push: endOf(row) };
    case "check":
      return afterCheck(row, event);
    case "pushes_off":
      if (!row || row.phase === "off") return null;
      return { row: { ...withoutEnd(row), phase: "off" }, push: row.phase === "playing" ? endOf(row) : null };
    case "pushes_on":
      return row?.phase === "off" ? { row: { ...row, phase: "idle" }, push: null } : null;
  }
}

function afterStartCheck(
  row: GameActivityState | null,
  event: Extract<GameActivityEvent, { kind: "start_checked" }>,
): GameActivityStep | null {
  const kept = row ? withoutEnd(row) : { id: event.new_id, game_kind: event.game_kind, started_at: event.at, pushed_at: event.at };
  if (row?.phase === "playing") {
    // The partner moved to another game. The same activity follows unless the viewer is in that game
    // or the couple is together now.
    switch (event.start) {
      case "start":
        return {
          row: { ...kept, phase: "playing", game_kind: event.game_kind, pushed_at: event.at },
          push: { event: "update", quiet: false, activity_id: row.id, game_kind: event.game_kind },
        };
      case "viewer_present":
      case "together":
        return { row: { ...kept, phase: "held", game_kind: event.game_kind }, push: endOf(row) };
      case "pushes_off":
        return { row: { ...kept, phase: "off" }, push: endOf(row) };
      case "no_token":
        return { row: { ...kept, phase: "idle" }, push: endOf(row) };
    }
  }
  switch (event.start) {
    case "start":
      return {
        row: { id: event.new_id, game_kind: event.game_kind, phase: "playing", started_at: event.at, pushed_at: event.at },
        push: { event: "start", quiet: false, activity_id: event.new_id, game_kind: event.game_kind },
      };
    case "viewer_present":
    case "together":
      return { row: { ...kept, phase: "held", game_kind: event.game_kind }, push: null };
    case "pushes_off":
      return { row: { ...kept, phase: "off" }, push: null };
    case "no_token":
      // A row keeps who the viewer is, so later heartbeats read no members.
      return row?.phase === "idle" ? null : { row: { ...kept, phase: "idle" }, push: null };
  }
}

function afterCheck(row: GameActivityState | null, event: Extract<GameActivityEvent, { kind: "check" }>): GameActivityStep | null {
  if (!isWatched(row)) return null;
  if (event.partner_present) {
    const refresh = row.phase === "playing" && msBetween(row.pushed_at, event.at) >= GAME_ACTIVITY_REFRESH_MS;
    if (!refresh && row.ends_at === undefined) return null;
    return {
      row: { ...withoutEnd(row), ...(refresh ? { pushed_at: event.at } : {}) },
      push: refresh ? { event: "update", quiet: true, activity_id: row.id, game_kind: row.game_kind } : null,
    };
  }
  if (row.ends_at === undefined) return { row: { ...row, ends_at: addMs(event.at, GAME_ACTIVITY_AWAY_GRACE_MS) }, push: null };
  if (event.at < row.ends_at) return null;
  return { row: { ...withoutEnd(row), phase: "idle" }, push: row.phase === "playing" ? endOf(row) : null };
}

/** The phases the cron looks after. */
function isWatched(row: GameActivityState | null): row is GameActivityState & { phase: "playing" | "held" } {
  return row?.phase === "playing" || row?.phase === "held";
}

function withoutEnd(row: GameActivityState): GameActivityState {
  const { ends_at: _, ...rest } = row;
  return rest;
}

const endOf = (row: GameActivityState): LiveActivityPush => ({ event: "end", quiet: false, activity_id: row.id, game_kind: row.game_kind });
const msBetween = (from: string, to: string) => Date.parse(to) - Date.parse(from);
const addMs = (at: string, ms: number) => new Date(Date.parse(at) + ms).toISOString();
const earlier = (a: string | undefined, b: string) => (a !== undefined && a < b ? a : b);

type GameActivityRow = Doc<"game_live_activities">;
type ActivityPeople = Pick<GameActivityRow, "couple_id" | "viewer_user_id" | "partner_user_id">;

function gameActivityState(row: GameActivityRow): GameActivityState {
  const { id, game_kind, phase, ends_at, started_at, pushed_at } = row;
  return { id, game_kind, phase, ...(ends_at === undefined ? {} : { ends_at }), started_at, pushed_at };
}

/**
 * Stores `step.row` as the whole row and queues its push. The push fans out to the tokens in a
 * mutation of its own, so a heartbeat reads no tokens and pays no push queue cost.
 */
async function applyGameActivityStep(ctx: WriterCtx, existing: GameActivityRow | null, people: ActivityPeople, step: GameActivityStep) {
  const row = { couple_id: people.couple_id, viewer_user_id: people.viewer_user_id, partner_user_id: people.partner_user_id, ...step.row };
  if (existing) {
    await ctx.db.replace(existing._id, row);
  } else {
    await ctx.db.insert("game_live_activities", row);
  }
  if (step.push) {
    await ctx.scheduler.runAfter(0, internal.liveActivities.queue_game_activity_push, {
      viewer_user_id: people.viewer_user_id,
      ...step.push,
    });
  }
}

/** Moves an existing row by an event that needs no start check. */
export async function moveGameActivity(ctx: WriterCtx, row: GameActivityRow, event: GameActivityEvent): Promise<void> {
  const step = nextGameActivity(gameActivityState(row), event);
  if (step) await applyGameActivityStep(ctx, row, row, step);
}

/**
 * A heartbeat from `userId`'s game screen. In a real-time game it starts the other partner's
 * activity at once or moves it to this game, and when `userId` opened the game of an activity
 * that shows them their partner, that activity is held.
 *
 * Reads the couple's two rows. Only a heartbeat that may start or move an activity reads more:
 * the viewer's start token, their game push setting, whether they have the game open and whether
 * the couple is together today.
 */
export async function recordGameHeartbeat(ctx: WriterCtx, coupleId: string, userId: string, kind: GameKind): Promise<void> {
  if (!isRealTimeGameKind(kind)) return;
  const rows = await ctx.db
    .query("game_live_activities")
    .withIndex("by_couple_id_partner_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  const mine = rows.find((row) => row.partner_user_id === userId) ?? null;
  const theirs = rows.find((row) => row.viewer_user_id === userId) ?? null;
  if (theirs) await moveGameActivity(ctx, theirs, { kind: "viewer_heartbeat", game_kind: kind });

  const at = nowIso();
  const state = mine && gameActivityState(mine);
  if (mine && !needsStartCheck(state, kind)) {
    await moveGameActivity(ctx, mine, { kind: "heartbeat", game_kind: kind, at });
    return;
  }
  // The caller checked that the couple is active, so only its members need reading.
  const viewerUserId =
    mine?.viewer_user_id ??
    theirs?.partner_user_id ??
    (
      await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
        .collect()
    ).find((member) => member.user_id !== userId)?.user_id;
  if (!viewerUserId) return;
  const start = await startCheck(ctx, coupleId, viewerUserId, kind, at);
  const step = nextGameActivity(state, { kind: "start_checked", game_kind: kind, at, new_id: newUuid(), start });
  if (step) await applyGameActivityStep(ctx, mine, { couple_id: coupleId, viewer_user_id: viewerUserId, partner_user_id: userId }, step);
}

/** `userId` closed a game screen. The activity that shows them to their partner ends a minute later unless they come back. */
export async function recordGameLeave(ctx: WriterCtx, coupleId: string, userId: string, kind: GameKind): Promise<void> {
  if (!isRealTimeGameKind(kind)) return;
  const mine = await ctx.db
    .query("game_live_activities")
    .withIndex("by_couple_id_partner_user_id", (q) => q.eq("couple_id", coupleId).eq("partner_user_id", userId))
    .unique();
  if (mine) await moveGameActivity(ctx, mine, { kind: "left", game_kind: kind, at: nowIso() });
}

/** `viewerUserId` turned game pushes on or off. Off ends every activity that shows on their phones. */
export async function setGameActivitiesAllowed(ctx: WriterCtx, viewerUserId: string, allowed: boolean): Promise<void> {
  const rows = await ctx.db
    .query("game_live_activities")
    .withIndex("by_viewer_user_id", (q) => q.eq("viewer_user_id", viewerUserId))
    .collect();
  for (const row of rows) await moveGameActivity(ctx, row, { kind: allowed ? "pushes_on" : "pushes_off" });
}

/**
 * Whether an activity may start for a viewer at `at`: they have a phone that can show it, allow
 * game pushes, do not have that game open already, and the couple is not together that day by a
 * visit or by location (`isCoupleTogetherAt`). Reads the cheapest answer first.
 */
async function startCheck(
  ctx: WriterCtx,
  coupleId: string,
  viewerUserId: string,
  kind: RealTimeGameKind,
  at: string,
): Promise<StartCheck> {
  const startToken = await ctx.db
    .query("live_activity_tokens")
    .withIndex("by_user_id_kind", (q) => q.eq("user_id", viewerUserId).eq("kind", "start"))
    .first();
  if (!startToken) return "no_token";
  const preference = await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_id", (q) => q.eq("user_id", viewerUserId))
    .unique();
  if (!(preference?.games_enabled ?? false)) return "pushes_off";
  if (await isGamePresent(ctx, coupleId, kind, viewerUserId)) return "viewer_present";
  return (await isCoupleTogetherAt(ctx, coupleId, at)) ? "together" : "start";
}

/** Queues `push` to each of the viewer's phones that can get it. */
export async function queueActivityPush(ctx: WriterCtx, viewerUserId: string, push: LiveActivityPush): Promise<void> {
  const tokens =
    push.event === "start"
      ? await ctx.db
          .query("live_activity_tokens")
          .withIndex("by_user_id_kind", (q) => q.eq("user_id", viewerUserId).eq("kind", "start"))
          .collect()
      : await activityTokens(ctx, push.activity_id);
  for (const token of tokens) await queueLiveActivityPush(ctx, token, push);
}

export function activityTokens(ctx: ReaderCtx, activityId: string) {
  return ctx.db
    .query("live_activity_tokens")
    .withIndex("by_activity_id", (q) => q.eq("activity_id", activityId))
    .collect();
}

export async function queueLiveActivityPush(ctx: WriterCtx, token: Doc<"live_activity_tokens">, push: LiveActivityPush): Promise<void> {
  const id = newUuid();
  const now = nowIso();
  await ctx.db.insert("live_activity_push_outbox", {
    id,
    recipient_user_id: token.user_id,
    target_token_id: token.id,
    activity_id: push.activity_id,
    event: push.event,
    game_kind: push.game_kind,
    ...(push.quiet ? { quiet: true } : {}),
    scheduled_for: now,
    created_at: now,
  });
  await enqueuePush(ctx, "liveactivity", id, now);
}

/**
 * The couple ended. Every running activity gets its end on each phone that shows it, and the
 * couple's rows go. The relationship end calls it, and the cleanup and purge call it again in
 * case a row came after. Returns how many rows it deleted.
 */
export async function endCoupleGameActivities(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = await ctx.db
    .query("game_live_activities")
    .withIndex("by_couple_id_partner_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
  for (const row of rows) {
    if (row.phase === "playing") await queueActivityPush(ctx, row.viewer_user_id, endOf(row));
    await ctx.db.delete(row._id);
  }
  return rows.length;
}
