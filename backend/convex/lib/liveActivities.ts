import type { Infer } from "convex/values";
import { internal } from "../_generated/api";
import type { Doc } from "../_generated/dataModel";
import type { ReaderCtx, WriterCtx } from "./db";
import type { GameKind } from "./games";
import { newUuid } from "./ids";
import { enqueuePush } from "./notifications";
import { isGamePresent, openGameKinds } from "./presence";
import { addMs, nowIso } from "./time";
import { isCoupleTogetherAt } from "./together";
import type { liveActivityDelivery } from "./validators";

// The Live Activity that shows a viewer their partner's game session. A row exists only while an
// activity runs, one per viewer and couple. It starts on the partner's game screen heartbeat,
// follows the partner to another game, shows whose turn it is in that game, and ends a while after
// the partner left every game. It names the partner and the game, never a move. None starts while
// the couple is together that day. lib/games.ts imports this file, so it must not import lib/games.ts.

/** How often the `check-game-activities` cron looks for the partner of each activity. */
export const GAME_ACTIVITY_CHECK_MS = 30_000;
/**
 * How long an activity stays once the partner closed its game, or the cron found them in no game.
 * With no turn it says the partner is playing, which is no longer true, so it goes after a minute.
 * A turn stays true, so the viewer sees it for ten minutes. The cron ends it at the next check after that.
 */
export const GAME_ACTIVITY_END_DELAY_MS: Record<GameTurn, number> = { none: 60_000, yours: 10 * 60_000, theirs: 10 * 60_000 };
/**
 * While the activity runs, a quiet update this often moves its stale date
 * (`LIVE_ACTIVITY_STALE_SECONDS` in lib/apns.ts) forward.
 */
export const GAME_ACTIVITY_REFRESH_MS = 10 * 60_000;

/**
 * Whose turn it is in the game the activity shows, from the viewer's side: `yours` when something
 * in it waits for the viewer, else `theirs` when something waits for the partner, else `none`.
 */
export type GameTurn = "yours" | "theirs" | "none";

/** The fields of a `game_live_activities` row that `nextGameActivity` moves. */
export type GameActivityState = {
  id: string;
  game_kind: GameKind;
  turn: GameTurn;
  /** The activity ends at this time unless the partner's game screen shows up again. */
  ends_at?: string;
  /** The last push that moved the activity's stale date. */
  pushed_at: string;
};

export type GameActivityEvent =
  /** No activity runs, the partner's game screen is open, and the viewer may get an activity (`mayStart`). */
  | { kind: "start"; id: string; game_kind: GameKind; turn: GameTurn; at: string }
  /** The partner's game screen is open. `viewer_present`: the viewer has that game open too. */
  | { kind: "heartbeat"; game_kind: GameKind; turn: GameTurn; viewer_present: boolean; at: string }
  /** The turn in the activity's game was read again, without word from the partner's screen. */
  | { kind: "turn"; turn: GameTurn; viewer_present: boolean; at: string }
  /** The partner closed a game screen. */
  | { kind: "left"; game_kind: GameKind; at: string }
  /** The cron looked for the partner in every game. */
  | { kind: "check"; partner_present: boolean; at: string }
  /** No phone of the viewer holds activity `activity_id` anymore. */
  | { kind: "viewer_ended"; activity_id: string }
  /** The viewer turned game pushes off. */
  | { kind: "stop" };

/**
 * How a push reaches the phone. `alert` lights the screen and opens the Dynamic Island. `now`
 * changes the activity with no sign. `quiet` goes at APNs priority 5, which iOS may hold back and
 * does not count against the app.
 */
export type LiveActivityDelivery = Infer<typeof liveActivityDelivery>;

/**
 * One push to the viewer's phones. A start goes to every push-to-start token of the viewer, an
 * update or an end to every token of activity `activity_id`.
 */
export type LiveActivityPush = {
  event: "start" | "update" | "end";
  delivery: LiveActivityDelivery;
  activity_id: string;
  game_kind: GameKind;
};

/** `row` null deletes the row, which ends the activity. */
export type GameActivityStep = { row: GameActivityState | null; push: LiveActivityPush | null };

/** The only way a `game_live_activities` row moves. Returns null when the event changes nothing. */
export function nextGameActivity(row: GameActivityState | null, event: GameActivityEvent): GameActivityStep | null {
  if (event.kind === "start") {
    if (row) return null;
    return {
      row: { id: event.id, game_kind: event.game_kind, turn: event.turn, pushed_at: event.at },
      push: { event: "start", delivery: "alert", activity_id: event.id, game_kind: event.game_kind },
    };
  }
  if (!row) return null;
  switch (event.kind) {
    case "heartbeat": {
      const kept = withoutEnd(row);
      return showing(kept, event.game_kind, event.turn, event.viewer_present, event.at) ?? (row.ends_at === undefined ? null : { row: kept, push: null });
    }
    case "turn": {
      // While the activity ends, a new turn can bring the end closer but never later.
      const kept = row.ends_at === undefined ? row : { ...row, ends_at: earlier(row.ends_at, endsAfter(event.at, event.turn)) };
      return showing(kept, row.game_kind, event.turn, event.viewer_present, event.at);
    }
    case "left": {
      if (row.game_kind !== event.game_kind) return null;
      const endsAt = earlier(row.ends_at, endsAfter(event.at, row.turn));
      return endsAt === row.ends_at ? null : { row: { ...row, ends_at: endsAt }, push: null };
    }
    case "check":
      return afterCheck(row, event);
    case "viewer_ended":
      return row.id === event.activity_id ? { row: null, push: endOf(row) } : null;
    case "stop":
      return { row: null, push: endOf(row) };
  }
}

/**
 * One update when the game or the turn changed. It alerts when the partner went to another game or
 * the turn became the viewer's. The viewer cannot see the activity while they have the game open,
 * so it goes quiet then.
 */
function showing(row: GameActivityState, gameKind: GameKind, turn: GameTurn, viewerPresent: boolean, at: string): GameActivityStep | null {
  if (row.game_kind === gameKind && row.turn === turn) return null;
  const news = row.game_kind !== gameKind || turn === "yours";
  return {
    row: { ...row, game_kind: gameKind, turn, pushed_at: at },
    push: { event: "update", delivery: viewerPresent ? "quiet" : news ? "alert" : "now", activity_id: row.id, game_kind: gameKind },
  };
}

function afterCheck(row: GameActivityState, event: Extract<GameActivityEvent, { kind: "check" }>): GameActivityStep | null {
  if (!event.partner_present && row.ends_at !== undefined && event.at >= row.ends_at) return { row: null, push: endOf(row) };
  const kept = event.partner_present ? withoutEnd(row) : { ...row, ends_at: row.ends_at ?? endsAfter(event.at, row.turn) };
  // The refresh runs while the activity ends too, so it never shows its stale look first.
  const refresh = msBetween(row.pushed_at, event.at) >= GAME_ACTIVITY_REFRESH_MS;
  if (!refresh && kept.ends_at === row.ends_at) return null;
  return {
    row: refresh ? { ...kept, pushed_at: event.at } : kept,
    push: refresh ? { event: "update", delivery: "quiet", activity_id: row.id, game_kind: row.game_kind } : null,
  };
}

function withoutEnd(row: GameActivityState): GameActivityState {
  const { ends_at: _, ...rest } = row;
  return rest;
}

const endOf = (row: GameActivityState): LiveActivityPush => ({ event: "end", delivery: "now", activity_id: row.id, game_kind: row.game_kind });
const endsAfter = (at: string, turn: GameTurn) => addMs(at, GAME_ACTIVITY_END_DELAY_MS[turn]);
const msBetween = (from: string, to: string) => Date.parse(to) - Date.parse(from);
const earlier = (a: string | undefined, b: string) => (a !== undefined && a < b ? a : b);

type GameActivityRow = Doc<"game_live_activities">;
type ActivityPeople = Pick<GameActivityRow, "couple_id" | "viewer_user_id" | "partner_user_id">;

function gameActivityState(row: GameActivityRow): GameActivityState {
  const { id, game_kind, turn, ends_at, pushed_at } = row;
  return { id, game_kind, turn, ...(ends_at === undefined ? {} : { ends_at }), pushed_at };
}

/**
 * Stores `step.row` as the whole row, or deletes the row, and queues its push. The push fans out
 * to the tokens in a mutation of its own, so a heartbeat reads no tokens and pays no push queue cost.
 */
async function applyGameActivityStep(ctx: WriterCtx, existing: GameActivityRow | null, people: ActivityPeople, step: GameActivityStep) {
  if (step.row === null) {
    if (existing) await ctx.db.delete(existing._id);
  } else {
    const row = { couple_id: people.couple_id, viewer_user_id: people.viewer_user_id, partner_user_id: people.partner_user_id, ...step.row };
    if (existing) {
      await ctx.db.replace(existing._id, row);
    } else {
      await ctx.db.insert("game_live_activities", row);
    }
  }
  if (step.push) {
    await ctx.scheduler.runAfter(0, internal.liveActivities.queue_game_activity_push, {
      viewer_user_id: people.viewer_user_id,
      ...step.push,
    });
  }
}

export async function moveGameActivity(ctx: WriterCtx, row: GameActivityRow, event: GameActivityEvent): Promise<void> {
  const step = nextGameActivity(gameActivityState(row), event);
  if (step) await applyGameActivityStep(ctx, row, row, step);
}

/** The couple's activities, which are at most two: one for each partner as the viewer. */
function coupleActivities(ctx: ReaderCtx, coupleId: string) {
  return ctx.db
    .query("game_live_activities")
    .withIndex("by_couple_id_partner_user_id", (q) => q.eq("couple_id", coupleId))
    .collect();
}

/**
 * Whose turn it is in `kind` for the viewer. Every game's backend is needed for it, which only
 * gameHooks.ts may load, so a module with queries can import this file.
 */
function readTurn(ctx: WriterCtx, people: ActivityPeople, kind: GameKind): Promise<GameTurn> {
  return ctx.runQuery(internal.gameHooks.game_turn, {
    couple_id: people.couple_id,
    viewer_user_id: people.viewer_user_id,
    partner_user_id: people.partner_user_id,
    kind,
  });
}

async function rereadTurn(ctx: WriterCtx, row: GameActivityRow, viewerPresent: boolean, at: string): Promise<void> {
  await moveGameActivity(ctx, row, { kind: "turn", turn: await readTurn(ctx, row, row.game_kind), viewer_present: viewerPresent, at });
}

/**
 * A heartbeat from `userId`'s game screen. It starts the partner's activity that shows `userId`,
 * or moves it to this game and its turn.
 *
 * Reads the couple's rows. Only a heartbeat with no activity to move reads whether one may start,
 * and it reads the turn only once that passed.
 */
export async function recordGameHeartbeat(ctx: WriterCtx, coupleId: string, userId: string, kind: GameKind): Promise<void> {
  const rows = await coupleActivities(ctx, coupleId);
  const mine = rows.find((row) => row.partner_user_id === userId);
  const theirs = rows.find((row) => row.viewer_user_id === userId);
  const at = nowIso();
  if (mine) {
    const turn = await readTurn(ctx, mine, kind);
    const viewerPresent = await isGamePresent(ctx, coupleId, kind, mine.viewer_user_id);
    await moveGameActivity(ctx, mine, { kind: "heartbeat", game_kind: kind, turn, viewer_present: viewerPresent, at });
    return;
  }
  // The caller checked that the couple is active, so only its members need reading.
  const viewerUserId =
    theirs?.partner_user_id ??
    (
      await ctx.db
        .query("couple_members")
        .withIndex("by_couple_id_status", (q) => q.eq("couple_id", coupleId).eq("status", "active"))
        .collect()
    ).find((member) => member.user_id !== userId)?.user_id;
  if (!viewerUserId || !(await mayStart(ctx, coupleId, viewerUserId, kind, at))) return;
  const people = { couple_id: coupleId, viewer_user_id: viewerUserId, partner_user_id: userId };
  const step = nextGameActivity(null, { kind: "start", id: newUuid(), game_kind: kind, turn: await readTurn(ctx, people, kind), at });
  if (step) await applyGameActivityStep(ctx, null, people, step);
}

/**
 * `userId` closed a game screen. The activity that shows them to their partner gets its end, and
 * the turn of the activity that shows them their partner is read again when it is in that game.
 */
export async function recordGameLeave(ctx: WriterCtx, coupleId: string, userId: string, kind: GameKind): Promise<void> {
  const rows = await coupleActivities(ctx, coupleId);
  const at = nowIso();
  const mine = rows.find((row) => row.partner_user_id === userId);
  const theirs = rows.find((row) => row.viewer_user_id === userId);
  if (mine) await moveGameActivity(ctx, mine, { kind: "left", game_kind: kind, at });
  if (theirs?.game_kind === kind) await rereadTurn(ctx, theirs, false, at);
}

/** A move or a result in `kind` may have changed whose turn it is, so the couple's activities in that game read it again. */
export async function refreshGameActivityTurns(ctx: WriterCtx, coupleId: string, kind: GameKind): Promise<void> {
  const at = nowIso();
  for (const row of await coupleActivities(ctx, coupleId)) {
    if (row.game_kind === kind) await rereadTurn(ctx, row, await isGamePresent(ctx, coupleId, kind, row.viewer_user_id), at);
  }
}

/**
 * The cron's look at one activity. It reads the turn again, because a write that queues no push,
 * such as a result someone saw, can change it. Then it looks for the partner in every game.
 */
export async function checkGameActivity(ctx: WriterCtx, row: GameActivityRow, at: string): Promise<void> {
  await rereadTurn(ctx, row, await isGamePresent(ctx, row.couple_id, row.game_kind, row.viewer_user_id), at);
  const current = await ctx.db.get(row._id);
  if (!current) return;
  const open = await openGameKinds(ctx, row.couple_id, row.partner_user_id);
  await moveGameActivity(ctx, current, { kind: "check", partner_present: open.size > 0, at });
}

/** `viewerUserId` turned game pushes off, which ends every activity on their phones. */
export async function stopGameActivities(ctx: WriterCtx, viewerUserId: string): Promise<void> {
  const rows = await ctx.db
    .query("game_live_activities")
    .withIndex("by_viewer_user_id", (q) => q.eq("viewer_user_id", viewerUserId))
    .collect();
  for (const row of rows) await moveGameActivity(ctx, row, { kind: "stop" });
}

/**
 * Whether an activity may start for a viewer at `at`: they have a phone that can show it, allow
 * game pushes, do not have that game open already, and the couple is not together that day by a
 * visit or by location (`isCoupleTogetherAt`). Reads the cheapest answer first. Nothing is stored
 * when it fails, so the partner's next heartbeat asks again.
 */
async function mayStart(ctx: WriterCtx, coupleId: string, viewerUserId: string, kind: GameKind, at: string): Promise<boolean> {
  const startToken = await ctx.db
    .query("live_activity_tokens")
    .withIndex("by_user_id_kind", (q) => q.eq("user_id", viewerUserId).eq("kind", "start"))
    .first();
  if (!startToken) return false;
  const preference = await ctx.db
    .query("notification_preferences")
    .withIndex("by_user_id", (q) => q.eq("user_id", viewerUserId))
    .unique();
  if (!(preference?.games_enabled ?? false)) return false;
  if (await isGamePresent(ctx, coupleId, kind, viewerUserId)) return false;
  return !(await isCoupleTogetherAt(ctx, coupleId, at));
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
    delivery: push.delivery,
    scheduled_for: now,
    created_at: now,
  });
  await enqueuePush(ctx, "liveactivity", id, now);
}

/**
 * The couple ended. Every activity gets its end on each phone that shows it, and the
 * couple's rows go. The relationship end calls it, and the cleanup and purge call it again in
 * case a row came after. Returns how many rows it deleted.
 */
export async function endCoupleGameActivities(ctx: WriterCtx, coupleId: string): Promise<number> {
  const rows = await coupleActivities(ctx, coupleId);
  for (const row of rows) {
    await queueActivityPush(ctx, row.viewer_user_id, endOf(row));
    await ctx.db.delete(row._id);
  }
  return rows.length;
}
