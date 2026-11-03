import type { RegisteredQuery } from "convex/server";
import { v } from "convex/values";
import { api, internal } from "./_generated/api";
import { query } from "./_generated/server";
import { canAccessCoupleContent } from "./lib/access";
import { requireUserId } from "./lib/auth";
import { getByUuid } from "./lib/db";
import { fail } from "./lib/errors";
import { finishedGameForChat, gameChatSource, gameChatSubjectId, normalizeGameChatSource } from "./lib/gameChatSubjects";
import { compareGameChatItems, gameChatCursor, gameChatResults, normalizeGameChatCursor, type GameChatCursor } from "./lib/gameChatTimeline";
import { projectThreadMessages } from "./lib/threadMessageProjection";
import { gameKind } from "./lib/validators";
import { uuidArg } from "./lib/ids";

type Returned<Query> = Query extends RegisteredQuery<infer Visibility, infer Args, infer Value> ? Awaited<Value> : never;

type Result =
  | { kind: "piccante"; result: NonNullable<Returned<typeof import("./piccante").get_piccante_result>> }
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
      case "piccante": {
        const result = await ctx.runQuery(api.piccante.get_piccante_result, { p_game_number: game.row.game_number });
        if (!result) return fail("42501", "finished game is not available");
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

/** One common page boundary over messages and finished result references. */
export const get_game_chat_timeline = query({
  args: { p_couple_id: v.string(), p_game_kind: gameKind, p_limit: v.optional(v.number()), p_before: v.optional(gameChatCursor) },
  handler: async (ctx, args) => {
    const userId = await requireUserId(ctx);
    const coupleId = uuidArg(args.p_couple_id);
    if (!(await canAccessCoupleContent(ctx, userId, coupleId))) return fail("42501", "active entitled couple access is required");
    const requestedLimit = args.p_limit ?? 50;
    if (!Number.isFinite(requestedLimit) || requestedLimit < 1) return fail("23514", "limit must be 1 or more");
    const limit = Math.min(Math.floor(requestedLimit), 100);
    const before = normalizeGameChatCursor(args.p_before, args.p_game_kind);
    const subjectId = await gameChatSubjectId(coupleId, args.p_game_kind);
    const link = await ctx.db.query("game_threads").withIndex("by_subject_id", q => q.eq("subject_id", subjectId)).unique();
    const thread = link?.couple_id === coupleId ? await getByUuid(ctx, "conversation_threads", link.thread_id) : null;
    const availableThread = thread?.couple_id === coupleId && thread.deleted_at === undefined && thread.moderation_status === "visible" ? thread : null;
    const messages = [];
    if (availableThread) {
      const older = await ctx.db.query("thread_messages")
        .withIndex("by_thread_id_created_at_id", q => before ? q.eq("thread_id", availableThread.id).lt("created_at", before.at) : q.eq("thread_id", availableThread.id))
        .order("desc").take(limit + 1);
      const tied = before ? await ctx.db.query("thread_messages")
        .withIndex("by_thread_id_created_at_id", q => before.item_kind === "message"
          ? q.eq("thread_id", availableThread.id).eq("created_at", before.at).lt("id", before.key)
          : q.eq("thread_id", availableThread.id).eq("created_at", before.at))
        .order("desc").take(limit + 1) : [];
      messages.push(...tied, ...older);
    }
    const results = await gameChatResults(ctx, coupleId, args.p_game_kind, limit + 1, before);
    const items = [
      ...messages.map(message => ({ cursor: { at: message.created_at, item_kind: "message", key: message.id } satisfies GameChatCursor, message })),
      ...results.map(result => ({ cursor: { at: result.finished_at, item_kind: "result", key: result.key } satisfies GameChatCursor, result })),
    ].sort((a, b) => compareGameChatItems(b.cursor, a.cursor));
    const page = items.slice(0, limit).reverse();
    const pageMessages = page.flatMap(item => "message" in item ? [item.message] : []);
    return {
      thread_id: availableThread?.id ?? null,
      messages: availableThread ? await projectThreadMessages(ctx, availableThread, pageMessages) : [],
      results: page.flatMap(item => "result" in item ? [item.result] : []),
      has_more: items.length > limit,
      next_before: items.length > limit ? page[0].cursor : null,
    };
  },
});
