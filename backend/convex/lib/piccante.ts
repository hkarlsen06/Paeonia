import { defineTable } from "convex/server";
import { v, type Infer } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { canAccessCoupleContent } from "./access";
import type { ReaderCtx, WriterCtx } from "./db";
import { fail } from "./errors";
import type { GameBackend } from "./gameRegistry";
import { enqueueGamePush, TURN_REMINDER_AFTER_MS, type GameWait } from "./games";
import { addMs } from "./time";

export const piccanteState = v.object({
  game_number: v.number(), starter_user_id: v.string(), partner_user_id: v.string(),
  turn_user_id: v.optional(v.string()), phase: v.union(v.literal("choosing"), v.literal("hiding"), v.literal("biting"), v.literal("finished")),
  size: v.optional(v.number()),
  chilis: v.array(v.object({ tile: v.number(), user_id: v.string(), note: v.optional(v.string()) })),
  sniffs: v.array(v.object({ tile: v.number(), user_id: v.string(), has_chili: v.boolean() })),
  bites: v.array(v.object({ tile: v.number(), user_id: v.string() })),
  winner_user_id: v.optional(v.string()), loser_user_id: v.optional(v.string()),
  started_at: v.string(), finished_at: v.optional(v.string()),
});
export const piccanteTables = {
  piccante_games: defineTable({ id: v.string(), couple_id: v.string(), version: v.number(), state: piccanteState,
    wins_by_user: v.record(v.string(), v.number()), games_finished: v.number(), turn_started_at: v.string(),
    turn_reminder_sent_at: v.optional(v.string()), created_at: v.string(), updated_at: v.string(),
  }).index("by_uuid", ["id"]).index("by_couple_id", ["couple_id"])
    .index("by_turn_reminder_sent_at_turn_started_at", ["turn_reminder_sent_at", "turn_started_at"]),
  piccante_results: defineTable({ id: v.string(), game_id: v.string(), couple_id: v.string(), game_number: v.number(), state: piccanteState,
    seen_by_user_ids: v.array(v.string()), finished_at: v.string(),
  }).index("by_uuid", ["id"]).index("by_couple_id", ["couple_id"])
    .index("by_couple_id_game_number", ["couple_id", "game_number"])
    .index("by_couple_id_finished_at_game_number", ["couple_id", "finished_at", "game_number"]),
};
export type PiccanteState = Infer<typeof piccanteState>;
export type PiccanteGame = Doc<"piccante_games">;
export type PiccanteAction = { kind: "size"; size: number } | { kind: "hide"; tile: number; note?: string } |
  { kind: "bite"; tile: number } | { kind: "sniff"; tile: number } | { kind: "rematch" };

export function newPiccanteState(starter: string, partner: string, number: number, now: string): PiccanteState {
  return { game_number: number, starter_user_id: starter, partner_user_id: partner,
    phase: "choosing", chilis: [], sniffs: [], bites: [], started_at: now };
}

/** Applies one legal action without mutating the previous state. Hidden information stays here. */
export function applyPiccanteAction(state: PiccanteState, userId: string, action: PiccanteAction, now: string): PiccanteState {
  if (userId !== state.starter_user_id && userId !== state.partner_user_id) return fail("42501", "active entitled game access is required");
  if (action.kind === "rematch") {
    if (state.phase !== "finished") return fail("23514", "that move is not allowed");
    return newPiccanteState(state.partner_user_id, state.starter_user_id, state.game_number + 1, now);
  }
  if (action.kind === "size") {
    if (state.phase !== "choosing" || ![3, 4, 5].includes(action.size)) return fail("23514", "that move is not allowed");
    const partner = userId === state.starter_user_id ? state.partner_user_id : state.starter_user_id;
    return { ...state, starter_user_id: userId, partner_user_id: partner,
      turn_user_id: userId, size: action.size, phase: "hiding" };
  }
  if (state.turn_user_id !== userId) return fail("42501", "it is not your turn");
  const tile = action.tile;
  if (!state.size || !Number.isInteger(tile) || tile < 0 || tile >= state.size * state.size || state.bites.some(b => b.tile === tile)) return fail("23514", "that move is not allowed");
  const other = userId === state.starter_user_id ? state.partner_user_id : state.starter_user_id;
  if (action.kind === "hide") {
    if (state.phase !== "hiding" || state.chilis.some(c => c.user_id === userId)) return fail("23514", "that move is not allowed");
    const note = action.note?.trim() || undefined;
    if (note && ([...note].length > 60 || /[\p{Cc}\p{Zl}\p{Zp}]/u.test(note))) return fail("23514", "note must be one line of 1 to 60 characters");
    const chilis = [...state.chilis, { tile, user_id: userId, ...(note ? { note } : {}) }];
    return { ...state, chilis, phase: chilis.length === 2 ? "biting" : "hiding", turn_user_id: chilis.length === 2 ? userId : other };
  }
  if (state.phase !== "biting") return fail("23514", "that move is not allowed");
  if (action.kind === "sniff") {
    if (state.sniffs.some(s => s.user_id === userId) || state.chilis.some(c => c.user_id === userId && c.tile === tile)) return fail("23514", "that move is not allowed");
    return { ...state, sniffs: [...state.sniffs, { tile, user_id: userId, has_chili: state.chilis.some(c => c.tile === tile) }] };
  }
  const bites = [...state.bites, { tile, user_id: userId }];
  if (state.chilis.some(c => c.tile === tile)) return { ...state, bites, phase: "finished", turn_user_id: undefined, winner_user_id: other, loser_user_id: userId, finished_at: now };
  return { ...state, bites, turn_user_id: other };
}

export function piccanteView(state: PiccanteState, game: Pick<PiccanteGame, "id" | "version" | "wins_by_user" | "games_finished">, userId: string, revealResult = true) {
  const hiddenResult = state.phase === "finished" && !revealResult;
  const phase: PiccanteState["phase"] = hiddenResult ? "biting" : state.phase;
  const mine = hiddenResult ? undefined : state.chilis.find(c => c.user_id === userId);
  const sniff = hiddenResult ? undefined : state.sniffs.find(s => s.user_id === userId);
  const partner = state.starter_user_id === userId ? state.partner_user_id : state.starter_user_id;
  return { id: game.id, game_number: state.game_number, version: game.version, starter_user_id: state.starter_user_id,
    turn_user_id: state.phase === "choosing" ? null : state.turn_user_id ?? null, phase, size: state.size ?? null, my_chili: mine?.tile ?? null,
    my_note: mine?.note ?? null, partner_hidden: state.chilis.some(c => c.user_id !== userId),
    my_sniff: sniff ? { tile: sniff.tile, has_chili: sniff.has_chili } : null,
    partner_sniff_used: state.sniffs.some(s => s.user_id !== userId), bites: hiddenResult ? state.bites.slice(0, -1) : state.bites,
    chilis: state.phase === "finished" && revealResult ? state.chilis.map(c => ({ ...c, note: c.note ?? null })) : [],
    winner_user_id: hiddenResult ? null : state.winner_user_id ?? null, loser_user_id: hiddenResult ? null : state.loser_user_id ?? null,
    my_wins: game.wins_by_user[userId] ?? 0, partner_wins: game.wins_by_user[partner] ?? 0,
    games_finished: game.games_finished, started_at: state.started_at, finished_at: state.finished_at ?? null };
}
export const getPiccanteGame = (ctx: ReaderCtx, coupleId: string) => ctx.db.query("piccante_games").withIndex("by_couple_id", q => q.eq("couple_id", coupleId)).unique();
export async function latestUnseenPiccanteResult(ctx: ReaderCtx, coupleId: string, userId: string) {
  const latest = await ctx.db.query("piccante_results").withIndex("by_couple_id_game_number", q => q.eq("couple_id", coupleId)).order("desc").first();
  return latest && !latest.seen_by_user_ids.includes(userId) ? latest : null;
}
const turnToken = (game: PiccanteGame) => `${game.state.game_number}:${game.state.chilis.length}:${game.state.bites.length}:${game.state.phase}`;
export { turnToken as piccanteTurnToken };
export const piccanteBackend: GameBackend = {
  async waitingFor(ctx, coupleId, userId): Promise<GameWait[]> {
    const game = await getPiccanteGame(ctx, coupleId);
    if (!game) return [];
    if (game.state.phase !== "choosing" && game.state.turn_user_id === userId) return [{ kind: "piccante", key: `turn:${game.id}:${turnToken(game)}` }];
    const result = await latestUnseenPiccanteResult(ctx, coupleId, userId);
    return result ? [{ kind: "piccante", key: `result:${result.id}` }] : [];
  },
  async pushStillWanted(ctx, push, payload, recipient) {
    if (typeof payload.couple_id !== "string") return false;
    const game = await getPiccanteGame(ctx, payload.couple_id);
    if (!game) return false;
    if (push === "game_result") {
      const result = await latestUnseenPiccanteResult(ctx, game.couple_id, recipient);
      return result !== null && String(result.game_number) === payload.round_id;
    }
    return game.state.phase !== "choosing" && game.state.turn_user_id === recipient && payload.round_id === turnToken(game);
  },
  async deleteCoupleRows(ctx, coupleId) {
    const rows = [...await ctx.db.query("piccante_games").withIndex("by_couple_id", q => q.eq("couple_id", coupleId)).collect(),
      ...await ctx.db.query("piccante_results").withIndex("by_couple_id", q => q.eq("couple_id", coupleId)).collect()];
    for (const row of rows) await ctx.db.delete(row._id);
    return rows.length;
  },
  async sendDueTurnReminders(ctx: WriterCtx, now) {
    const games = await ctx.db.query("piccante_games").withIndex("by_turn_reminder_sent_at_turn_started_at", q => q.eq("turn_reminder_sent_at", undefined).lte("turn_started_at", addMs(now, -TURN_REMINDER_AFTER_MS))).take(100);
    let sent = 0;
    for (const game of games) {
      await ctx.db.patch(game._id, { turn_reminder_sent_at: now });
      const recipient = game.state.turn_user_id;
      if (game.state.phase === "choosing" || !recipient || !await canAccessCoupleContent(ctx, recipient, game.couple_id)) continue;
      const actor = recipient === game.state.starter_user_id ? game.state.partner_user_id : game.state.starter_user_id;
      sent += await enqueueGamePush(ctx, { kind: "game_turn_reminder", game_kind: "piccante", couple_id: game.couple_id, game_id: game.id,
        round_id: turnToken(game), actor_user_id: actor, recipient_user_id: recipient, dedupe_key: `piccante:reminder:${game.id}:${turnToken(game)}` });
    }
    return sent;
  },
};
