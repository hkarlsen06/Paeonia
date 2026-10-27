import { v, type Infer } from "convex/values";
import { sha256Hex } from "./crypto";
import type { ReaderCtx } from "./db";
import { getByUuid } from "./db";
import { fail } from "./errors";
import { uuidArg } from "./ids";
import { literals } from "./validators";

export const boardChatKind = literals("connect_four", "dots_and_boxes", "ultimate_tic_tac_toe", "ludo");
export const gameChatSource = v.union(
  v.object({ kind: literals("draw_and_guess", "mind_meld", "consensio", "guess_my_spot", "story_chain", "exquisite_corpse"), id: v.string() }),
  v.object({ kind: boardChatKind, couple_id: v.string(), game_number: v.number() }),
);
export type GameChatSource = Infer<typeof gameChatSource>;

export function normalizeGameChatSource(source: GameChatSource): GameChatSource {
  if ("id" in source) return { ...source, id: uuidArg(source.id) };
  if (!Number.isSafeInteger(source.game_number) || source.game_number < 1) fail("23514", "invalid game number");
  return { ...source, couple_id: uuidArg(source.couple_id) };
}

/** A board's history uses a couple, kind and number instead of a UUID. Both clients use this key. */
export async function gameChatSubjectId(source: GameChatSource): Promise<string> {
  if ("id" in source) return source.id;
  const hex = await sha256Hex(`game-chat:${source.couple_id}:${source.kind}:${source.game_number}`);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

/** Only finished, still available content in the named couple can start or keep a chat. */
export async function finishedGameForChat(ctx: ReaderCtx, coupleId: string, source: GameChatSource) {
  switch (source.kind) {
    case "draw_and_guess": {
      const row = await getByUuid(ctx, "game_moves", source.id);
      return row?.couple_id === coupleId && (row.state === "solved" || row.state === "missed") && row.drawing_media_asset_id !== undefined ? { kind: source.kind, row } : null;
    }
    case "mind_meld": {
      const row = await getByUuid(ctx, "mind_meld_games", source.id);
      return row?.couple_id === coupleId && row.state !== "playing" ? { kind: source.kind, row } : null;
    }
    case "consensio": {
      const row = await getByUuid(ctx, "consensio_rounds", source.id);
      return row?.couple_id === coupleId && row.guess !== undefined ? { kind: source.kind, row } : null;
    }
    case "guess_my_spot": {
      const row = await getByUuid(ctx, "guess_my_spot_rounds", source.id);
      return row?.couple_id === coupleId && row.guessed_at !== undefined && row.deleted_at === undefined ? { kind: source.kind, row } : null;
    }
    case "story_chain": {
      const row = await getByUuid(ctx, "story_chain_stories", source.id);
      return row?.couple_id === coupleId && row.state === "finished" ? { kind: source.kind, row } : null;
    }
    case "exquisite_corpse": {
      const row = await getByUuid(ctx, "exquisite_corpse_figures", source.id);
      return row?.couple_id === coupleId && row.finished_at !== undefined ? { kind: source.kind, row } : null;
    }
    case "connect_four": case "dots_and_boxes": case "ultimate_tic_tac_toe": case "ludo":
      if (source.couple_id !== coupleId) return null;
      const row = await ctx.db.query("board_game_history")
        .withIndex("by_couple_id_kind_game_number", q => q.eq("couple_id", coupleId).eq("kind", source.kind).eq("game_number", source.game_number))
        .unique();
      return row ? { kind: "board" as const, row } : null;
  }
}
