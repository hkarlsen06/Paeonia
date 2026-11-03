import { v, type Infer } from "convex/values";
import type { ReaderCtx } from "./db";
import { fail } from "./errors";
import type { GameChatKind, GameChatSource } from "./gameChatSubjects";
import { timestampArg, uuidArg } from "./ids";
import { literals } from "./validators";

export const gameChatCursor = v.object({ at: v.string(), item_kind: literals("message", "result"), key: v.string() });
export type GameChatCursor = Infer<typeof gameChatCursor>;
export type GameChatResultReference = { source: GameChatSource; finished_at: string; key: string };

export function normalizeGameChatCursor(cursor: GameChatCursor | undefined, kind: GameChatKind): GameChatCursor | undefined {
  if (!cursor) return undefined;
  const board = ["connect_four", "dots_and_boxes", "ultimate_tic_tac_toe", "ludo", "piccante"].includes(kind);
  if (cursor.item_kind === "result" && board) {
    if (!/^\d{16}$/.test(cursor.key) || !Number.isSafeInteger(Number(cursor.key)) || Number(cursor.key) < 1) fail("23514", "invalid game timeline cursor");
    return { ...cursor, at: timestampArg(cursor.at) };
  }
  return { ...cursor, at: timestampArg(cursor.at), key: uuidArg(cursor.key) };
}

export function compareGameChatItems(a: GameChatCursor, b: GameChatCursor): number {
  if (a.at !== b.at) return a.at < b.at ? -1 : 1;
  if (a.item_kind !== b.item_kind) return a.item_kind < b.item_kind ? -1 : 1;
  return a.key === b.key ? 0 : a.key < b.key ? -1 : 1;
}

/** Read only bounded pages from each kind's own completion index. */
export async function gameChatResults(ctx: ReaderCtx, coupleId: string, kind: GameChatKind, limit: number, before?: GameChatCursor): Promise<GameChatResultReference[]> {
  const references: GameChatResultReference[] = [];
  switch (kind) {
    case "draw_and_guess": {
      const older = await ctx.db.query("game_moves")
        .withIndex("by_couple_id_chat_result_available_ended_at_id", q => before ? q.eq("couple_id", coupleId).eq("chat_result_available", true).gte("ended_at", "").lt("ended_at", before.at) : q.eq("couple_id", coupleId).eq("chat_result_available", true).gte("ended_at", ""))
        .order("desc").take(limit);
      const tied = before?.item_kind === "result" ? await ctx.db.query("game_moves")
        .withIndex("by_couple_id_chat_result_available_ended_at_id", q => q.eq("couple_id", coupleId).eq("chat_result_available", true).eq("ended_at", before.at).lt("id", before.key))
        .order("desc").take(limit) : [];
      for (const row of [...tied, ...older]) {
        if (row.ended_at === undefined) continue;
        references.push({ source: { kind, id: row.id }, finished_at: row.ended_at, key: row.id });
      }
      break;
    }
    case "mind_meld": {
      for (const state of ["melded", "ended"] as const) {
        const older = await ctx.db.query("mind_meld_games")
          .withIndex("by_couple_id_state_ended_at_id", q => before ? q.eq("couple_id", coupleId).eq("state", state).gte("ended_at", "").lt("ended_at", before.at) : q.eq("couple_id", coupleId).eq("state", state).gte("ended_at", ""))
          .order("desc").take(limit);
        const tied = before?.item_kind === "result" ? await ctx.db.query("mind_meld_games")
          .withIndex("by_couple_id_state_ended_at_id", q => q.eq("couple_id", coupleId).eq("state", state).eq("ended_at", before.at).lt("id", before.key))
          .order("desc").take(limit) : [];
        for (const row of [...tied, ...older]) {
          if (row.ended_at === undefined) continue;
          references.push({ source: { kind, id: row.id }, finished_at: row.ended_at, key: row.id });
        }
      }
      break;
    }
    case "consensio": {
      const older = await ctx.db.query("consensio_rounds")
        .withIndex("by_couple_id_guessed_at_id", q => before ? q.eq("couple_id", coupleId).gte("guessed_at", "").lt("guessed_at", before.at) : q.eq("couple_id", coupleId).gte("guessed_at", ""))
        .order("desc").take(limit);
      const tied = before?.item_kind === "result" ? await ctx.db.query("consensio_rounds")
        .withIndex("by_couple_id_guessed_at_id", q => q.eq("couple_id", coupleId).eq("guessed_at", before.at).lt("id", before.key))
        .order("desc").take(limit) : [];
      for (const row of [...tied, ...older]) {
        if (row.guessed_at === undefined) continue;
        references.push({ source: { kind, id: row.id }, finished_at: row.guessed_at, key: row.id });
      }
      break;
    }
    case "guess_my_spot": {
      const older = await ctx.db.query("guess_my_spot_rounds")
        .withIndex("by_couple_id_deleted_at_guessed_at_id", q => before ? q.eq("couple_id", coupleId).eq("deleted_at", undefined).gte("guessed_at", "").lt("guessed_at", before.at) : q.eq("couple_id", coupleId).eq("deleted_at", undefined).gte("guessed_at", ""))
        .order("desc").take(limit);
      const tied = before?.item_kind === "result" ? await ctx.db.query("guess_my_spot_rounds")
        .withIndex("by_couple_id_deleted_at_guessed_at_id", q => q.eq("couple_id", coupleId).eq("deleted_at", undefined).eq("guessed_at", before.at).lt("id", before.key))
        .order("desc").take(limit) : [];
      for (const row of [...tied, ...older]) {
        if (row.guessed_at === undefined) continue;
        references.push({ source: { kind, id: row.id }, finished_at: row.guessed_at, key: row.id });
      }
      break;
    }
    case "story_chain": {
      const older = await ctx.db.query("story_chain_stories")
        .withIndex("by_couple_id_state_finished_at_id", q => before ? q.eq("couple_id", coupleId).eq("state", "finished").gte("finished_at", "").lt("finished_at", before.at) : q.eq("couple_id", coupleId).eq("state", "finished").gte("finished_at", ""))
        .order("desc").take(limit);
      const tied = before?.item_kind === "result" ? await ctx.db.query("story_chain_stories")
        .withIndex("by_couple_id_state_finished_at_id", q => q.eq("couple_id", coupleId).eq("state", "finished").eq("finished_at", before.at).lt("id", before.key))
        .order("desc").take(limit) : [];
      for (const row of [...tied, ...older]) {
        if (row.finished_at === undefined) continue;
        references.push({ source: { kind, id: row.id }, finished_at: row.finished_at, key: row.id });
      }
      break;
    }
    case "exquisite_corpse": {
      const older = await ctx.db.query("exquisite_corpse_figures")
        .withIndex("by_couple_id_finished_at_id", q => before ? q.eq("couple_id", coupleId).gte("finished_at", "").lt("finished_at", before.at) : q.eq("couple_id", coupleId).gte("finished_at", ""))
        .order("desc").take(limit);
      const tied = before?.item_kind === "result" ? await ctx.db.query("exquisite_corpse_figures")
        .withIndex("by_couple_id_finished_at_id", q => q.eq("couple_id", coupleId).eq("finished_at", before.at).lt("id", before.key))
        .order("desc").take(limit) : [];
      for (const row of [...tied, ...older]) {
        if (row.finished_at === undefined) continue;
        references.push({ source: { kind, id: row.id }, finished_at: row.finished_at, key: row.id });
      }
      break;
    }
    case "piccante": {
      const older = await ctx.db.query("piccante_results")
        .withIndex("by_couple_id_finished_at_game_number", q => before ? q.eq("couple_id", coupleId).lt("finished_at", before.at) : q.eq("couple_id", coupleId))
        .order("desc").take(limit);
      const tied = before?.item_kind === "result" ? await ctx.db.query("piccante_results")
        .withIndex("by_couple_id_finished_at_game_number", q => q.eq("couple_id", coupleId).eq("finished_at", before.at).lt("game_number", Number(before.key)))
        .order("desc").take(limit) : [];
      for (const row of [...tied, ...older]) references.push({ source: { kind, couple_id: coupleId, game_number: row.game_number }, finished_at: row.finished_at, key: String(row.game_number).padStart(16, "0") });
      break;
    }
    case "connect_four": case "dots_and_boxes": case "ultimate_tic_tac_toe": case "ludo": {
      const older = await ctx.db.query("board_game_history")
        .withIndex("by_couple_id_kind_finished_at_game_number", q => before ? q.eq("couple_id", coupleId).eq("kind", kind).gte("finished_at", "").lt("finished_at", before.at) : q.eq("couple_id", coupleId).eq("kind", kind).gte("finished_at", ""))
        .order("desc").take(limit);
      const tied = before?.item_kind === "result" ? await ctx.db.query("board_game_history")
        .withIndex("by_couple_id_kind_finished_at_game_number", q => q.eq("couple_id", coupleId).eq("kind", kind).eq("finished_at", before.at).lt("game_number", Number(before.key)))
        .order("desc").take(limit) : [];
      for (const row of [...tied, ...older]) {
        if (row.finished_at === undefined) continue;
        references.push({ source: { kind, couple_id: coupleId, game_number: row.game_number }, finished_at: row.finished_at, key: String(row.game_number).padStart(16, "0") });
      }
      break;
    }
  }
  return references.sort((a, b) => compareGameChatItems({ at: b.finished_at, item_kind: "result", key: b.key }, { at: a.finished_at, item_kind: "result", key: a.key })).slice(0, limit);
}
