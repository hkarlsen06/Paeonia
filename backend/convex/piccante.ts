import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import { getCurrentEntitledCoupleId } from "./lib/access";
import { assertNoPendingAccountDeletion } from "./lib/accountDeletion";
import { requireUserId } from "./lib/auth";
import { clientOperationArgs, toClientOperation } from "./lib/clientOperationArgs";
import { runClientOperation } from "./lib/clientOperations";
import { getOrCreateCoupleDayAt } from "./lib/coupleDays";
import type { ReaderCtx, WriterCtx } from "./lib/db";
import { fail } from "./lib/errors";
import { dataEpoch, enqueueGamePush, requireGameSettings, requirePartnerId } from "./lib/games";
import { newUuid, uuidArg } from "./lib/ids";
import { applyPiccanteAction, getPiccanteGame, latestUnseenPiccanteResult, newPiccanteState, piccanteTurnToken, piccanteView, type PiccanteAction } from "./lib/piccante";
import { applyCoupleActivity } from "./lib/streaks";
import { nowIso } from "./lib/time";

async function envelope(ctx: ReaderCtx, coupleId: string, userId: string) {
  const game = await getPiccanteGame(ctx, coupleId);
  const result = await latestUnseenPiccanteResult(ctx, coupleId, userId);
  const partnerId = game ? userId === game.state.starter_user_id ? game.state.partner_user_id : game.state.starter_user_id : await requirePartnerId(ctx, coupleId, userId);
  return { user_id: userId, couple_id: coupleId, partner_user_id: partnerId, data_epoch: dataEpoch(),
    game: game ? piccanteView(game.state, game, userId) : null,
    unseen_result: result && game ? piccanteView(result.state, game, userId) : null };
}
export const get_piccante = query({ args: {}, handler: async ctx => {
  const userId = await requireUserId(ctx);
  return envelope(ctx, await getCurrentEntitledCoupleId(ctx, userId), userId);
} });
export const ensure_piccante_game = mutation({ args: {}, handler: async ctx => {
  const userId = await requireUserId(ctx);
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  await assertNoPendingAccountDeletion(ctx, userId);
  if (!await getPiccanteGame(ctx, coupleId)) {
    const partnerId = await requirePartnerId(ctx, coupleId, userId);
    await requireGameSettings(ctx, coupleId);
    const now = nowIso();
    await ctx.db.insert("piccante_games", { id: newUuid(), couple_id: coupleId, version: 1,
      state: newPiccanteState(userId, partnerId, 1, now), wins_by_user: {}, games_finished: 0,
      turn_started_at: now, created_at: now, updated_at: now });
  }
  return envelope(ctx, coupleId, userId);
} });
const moveArgs = { p_game_id: v.string(), p_expected_version: v.number(), ...clientOperationArgs };
type MoveArgs = { p_game_id: string; p_expected_version: number; p_client_operation_id: string; p_client_id: string; p_client_sequence: number; p_local_created_at: string };
async function move(ctx: WriterCtx, args: MoveArgs, action: PiccanteAction) {
  const userId = await requireUserId(ctx);
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const gameId = uuidArg(args.p_game_id);
  const existing = await getPiccanteGame(ctx, coupleId);
  if (!existing || existing.id !== gameId) return fail("42501", "active entitled game access is required");
  return runClientOperation(ctx, userId, toClientOperation(args, { kind: `piccante_${action.kind}`, scope: "games", request: [gameId, args.p_expected_version, action] }), async () => {
    const game = await getPiccanteGame(ctx, coupleId);
    if (!game || game.version !== args.p_expected_version) return fail("40001", "the game has changed");
    const now = nowIso();
    const state = applyPiccanteAction(game.state, userId, action, now);
    if (action.kind === "rematch") {
      const result = await ctx.db.query("piccante_results").withIndex("by_couple_id_game_number", q => q.eq("couple_id", coupleId).eq("game_number", game.state.game_number)).unique();
      if (result && !result.seen_by_user_ids.includes(userId)) await ctx.db.patch(result._id, { seen_by_user_ids: [...result.seen_by_user_ids, userId] });
    }
    const finished = state.phase === "finished";
    const wins = { ...game.wins_by_user };
    if (finished && state.winner_user_id) wins[state.winner_user_id] = (wins[state.winner_user_id] ?? 0) + 1;
    // Sniffing does not restart the turn's 72-hour reminder or its hidden-wait key.
    await ctx.db.patch(game._id, { state, wins_by_user: wins, games_finished: game.games_finished + (finished ? 1 : 0),
      version: game.version + 1, updated_at: now,
      ...(action.kind !== "sniff" ? { turn_started_at: now, turn_reminder_sent_at: undefined } : {}) });
    if (finished) await ctx.db.insert("piccante_results", { id: newUuid(), game_id: game.id, couple_id: coupleId,
      game_number: state.game_number, state, finished_at: now, seen_by_user_ids: [] });
    const recipient = finished ? state.winner_user_id : state.turn_user_id;
    if (recipient && recipient !== userId && action.kind !== "sniff") {
      const token = finished ? String(state.game_number) : piccanteTurnToken({ ...game, state });
      await enqueueGamePush(ctx, { kind: finished ? "game_result" : "game_turn_ready", game_kind: "piccante", couple_id: coupleId,
        game_id: gameId, round_id: token, actor_user_id: userId, recipient_user_id: recipient,
        dedupe_key: `piccante:${gameId}:${token}`, skipIfPresent: true });
    }
    if (action.kind === "hide" || action.kind === "bite") await applyCoupleActivity(ctx, {
      couple_id: coupleId, user_id: userId, couple_day_id: await getOrCreateCoupleDayAt(ctx, coupleId, now),
      activity_kind: "game_turn_completed", occurred_at: now, dedupe_key: `piccante:${gameId}:${state.game_number}:${action.kind}:${state.bites.length}:${userId}`,
      metadata: { game_id: gameId } });
    return envelope(ctx, coupleId, userId);
  });
}
export const choose_piccante_size = mutation({ args: { ...moveArgs, p_size: v.number() }, handler: (ctx, args) => move(ctx, args, { kind: "size", size: args.p_size }) });
export const hide_piccante_chili = mutation({ args: { ...moveArgs, p_tile: v.number(), p_note: v.optional(v.union(v.string(), v.null())) }, handler: (ctx, args) => move(ctx, args, { kind: "hide", tile: args.p_tile, ...(args.p_note ? { note: args.p_note } : {}) }) });
export const bite_piccante_chocolate = mutation({ args: { ...moveArgs, p_tile: v.number() }, handler: (ctx, args) => move(ctx, args, { kind: "bite", tile: args.p_tile }) });
export const sniff_piccante_chocolate = mutation({ args: { ...moveArgs, p_tile: v.number() }, handler: (ctx, args) => move(ctx, args, { kind: "sniff", tile: args.p_tile }) });
export const start_piccante_rematch = mutation({ args: moveArgs, handler: (ctx, args) => move(ctx, args, { kind: "rematch" }) });
export const mark_piccante_result_seen = mutation({ args: { p_game_id: v.string(), p_game_number: v.number(), ...clientOperationArgs }, handler: async (ctx, args) => {
  const userId = await requireUserId(ctx);
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const game = await getPiccanteGame(ctx, coupleId);
  if (!game || game.id !== uuidArg(args.p_game_id)) return fail("42501", "active entitled game access is required");
  return runClientOperation(ctx, userId, toClientOperation(args, { kind: "piccante_seen", scope: "games", request: [game.id, args.p_game_number] }), async () => {
    const result = await ctx.db.query("piccante_results").withIndex("by_couple_id_game_number", q => q.eq("couple_id", coupleId).eq("game_number", args.p_game_number)).unique();
    if (!result) return fail("23514", "the game has not finished");
    if (!result.seen_by_user_ids.includes(userId)) {
      await ctx.db.patch(result._id, { seen_by_user_ids: [...result.seen_by_user_ids, userId] });
    }
    return envelope(ctx, coupleId, userId);
  });
} });
export const get_piccante_result = query({ args: { p_game_number: v.number() }, handler: async (ctx, args) => {
  const userId = await requireUserId(ctx);
  const coupleId = await getCurrentEntitledCoupleId(ctx, userId);
  const game = await getPiccanteGame(ctx, coupleId);
  const result = await ctx.db.query("piccante_results").withIndex("by_couple_id_game_number", q => q.eq("couple_id", coupleId).eq("game_number", args.p_game_number)).unique();
  return result && game ? piccanteView(result.state, game, userId) : null;
} });
