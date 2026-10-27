import type { RegisteredQuery } from "convex/server";
import { v } from "convex/values";
import { api, internal } from "./_generated/api";
import { query } from "./_generated/server";
import { canAccessCoupleContent } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { getByUuid } from "./lib/db";
import { fail } from "./lib/errors";
import { finishedGameForChat, gameChatSource, normalizeGameChatSource } from "./lib/gameChatSubjects";
import { uuidArg } from "./lib/ids";

type Returned<Query> = Query extends RegisteredQuery<infer Visibility, infer Args, infer Value> ? Awaited<Value> : never;

type Result =
  | { kind: "mind_meld"; result: Returned<typeof import("./mindMeld").get_mind_meld_history>["games"][number] }
  | { kind: "draw_and_guess"; result: NonNullable<Returned<typeof import("./drawAndGuess").get_draw_and_guess_history_round>>; guesses: string[] }
  | { kind: "consensio"; result: Returned<typeof import("./consensio").get_consensio_history>["rounds"][number] }
  | { kind: "guess_my_spot"; result: Returned<typeof import("./guessMySpot").get_guess_my_spot_history>["rounds"][number] }
  | { kind: "story_chain"; result: NonNullable<Returned<typeof import("./storyChain").get_story_chain_story>> }
  | { kind: "exquisite_corpse"; result: NonNullable<Returned<typeof import("./exquisiteCorpse").get_exquisite_corpse_figure>> }
  | { kind: "connect_four" | "dots_and_boxes" | "ultimate_tic_tac_toe" | "ludo"; result: Returned<typeof import("./boardGames").get_board_game_history>["games"][number] };

/** Full finished results load only while their conversation is open. */
export const get_game_conversation = query({
  args: { p_couple_id: v.string(), p_source: gameChatSource },
  handler: async (ctx, args): Promise<Result | null> => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) return fail("42501", "active entitled couple access is required");
    const source = normalizeGameChatSource(args.p_source);
    const game = await finishedGameForChat(ctx, coupleId, source);
    if (!game) {
      if (source.kind === "guess_my_spot") {
        const round = await getByUuid(ctx, "guess_my_spot_rounds", source.id);
        if (round?.couple_id === coupleId && round.deleted_at !== undefined) return null;
      }
      return fail("42501", "finished game is not available");
    }
    switch (game.kind) {
      case "mind_meld": {
        const page = await ctx.runQuery(api.mindMeld.get_mind_meld_history, { p_before_game_number: game.row.game_number + 1, p_limit: 1 });
        const result = page.games[0];
        if (!result || result.id !== game.row.id) return fail("42501", "finished game is not available");
        return { kind: game.kind, result };
      }
      case "draw_and_guess": {
        const result = await ctx.runQuery(api.drawAndGuess.get_draw_and_guess_history_round, { p_round_id: game.row.id });
        if (!result) return fail("42501", "finished drawing is not available");
        return { kind: game.kind, result, guesses: result.guesses };
      }
      case "consensio": {
        const page = await ctx.runQuery(api.consensio.get_consensio_history, { p_before_round_number: game.row.round_number + 1, p_limit: 1 });
        const result = page.rounds[0];
        if (!result || result.id !== game.row.id) return fail("42501", "finished round is not available");
        return { kind: game.kind, result };
      }
      case "guess_my_spot": {
        const result = await ctx.runQuery(internal.guessMySpot.get_finished_round_for_conversation, { p_round_id: game.row.id });
        if (!result) return null;
        return { kind: game.kind, result };
      }
      case "story_chain": {
        const result = await ctx.runQuery(api.storyChain.get_story_chain_story, { p_story_id: game.row.id });
        if (!result) return fail("42501", "finished story is not available");
        return { kind: game.kind, result };
      }
      case "exquisite_corpse": {
        const result = await ctx.runQuery(api.exquisiteCorpse.get_exquisite_corpse_figure, { p_figure_id: game.row.id });
        if (!result) return fail("42501", "finished creature is not available");
        return { kind: game.kind, result };
      }
      case "board": {
        const page = await ctx.runQuery(api.boardGames.get_board_game_history, { p_kind: game.row.kind, p_before_game_number: game.row.game_number + 1, p_limit: 1 });
        const result = page.games[0];
        if (!result || result.game_number !== game.row.game_number) return fail("42501", "finished game is not available");
        return { kind: game.row.kind, result };
      }
    }
  },
});
