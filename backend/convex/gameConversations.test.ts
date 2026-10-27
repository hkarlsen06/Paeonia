import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { gameChatSubjectId, type GameChatSource } from "./lib/gameChatSubjects";
import { getByUuid } from "./lib/db";
import { purgeCoupleContent } from "./lib/relationshipCleanup";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op } from "./media.testing";
import { createCouple, newTest, type TestConvex, type TestCouple } from "./test.setup";

const now = "2026-10-27T12:00:00.000Z";
let scheduled: TestConvex | undefined;
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(now));
});
afterEach(async () => {
  await scheduled?.finishAllScheduledFunctions(vi.runAllTimers);
  scheduled = undefined;
  vi.useRealTimers();
});

/** Finished history records, including a restarted Mind Meld's unrevealed word. */
async function seedGames(t: TestConvex, couple: TestCouple): Promise<GameChatSource[]> {
  return await t.run(async ctx => {
    const a = couple.first.userId;
    const b = couple.second.userId;
    const common = { couple_id: couple.coupleId, created_at: now, updated_at: now };
    const sources: GameChatSource[] = [];
    const mind = newUuid();
    await ctx.db.insert("mind_meld_games", {
      ...common, id: mind, game_number: 1, state: "ended", end_reason: "restart", ended_at: now,
      end_seen_by_user: {}, version: 1, created_by_user_id: a,
    });
    for (const [index, pair] of [["Ocean", "Sushi"], ["Fish", "Fish"], ["Secret", ""]].entries()) {
      const id = newUuid();
      await ctx.db.insert("mind_meld_rounds", {
        ...common, id, game_id: mind, round_number: index + 1, state: index === 2 ? "open" : "revealed", outcome: index === 2 ? undefined : "miss",
      });
      for (const [offset, word] of pair.entries()) {
        if (!word) continue;
        await ctx.db.insert("mind_meld_words", {
          couple_id: couple.coupleId, round_id: id, game_id: mind, user_id: offset === 0 ? a : b,
          word, match_key: word.toLowerCase(), locked_at: now,
        });
      }
    }
    sources.push({ kind: "mind_meld", id: mind });
    const draw = newUuid();
    await ctx.db.insert("game_moves", {
      ...common, id: draw, game_id: newUuid(), round_number: 1, drawer_user_id: a, guesser_user_id: b,
      state: "solved", difficulty: "easy", word: "umbrella", points: 2,
      drawing_media_asset_id: newUuid(), started_at: now, ended_at: now, speed_bonus: 0,
    });
    for (const [index, text] of ["cat", "hat", "umbrella"].entries()) {
      await ctx.db.insert("game_guesses", {
        id: newUuid(), move_id: draw, couple_id: couple.coupleId, user_id: b, text, correct: index === 2,
        created_at: new Date(Date.parse(now) + index).toISOString(),
      });
    }
    sources.push({ kind: "draw_and_guess", id: draw });
    const consensioGame = newUuid();
    await ctx.db.insert("consensio_games", {
      ...common, id: consensioGame, turn_user_id: a, turn_started_at: now, choices: [],
      shared_points: 4, round_count: 1, version: 1, created_by_user_id: a,
    });
    const consensio = newUuid();
    await ctx.db.insert("consensio_rounds", {
      ...common, id: consensio, game_id: consensioGame, round_number: 1, placer_user_id: a, guesser_user_id: b,
      subject: "Weather", left_end: "Cold", right_end: "Hot", spot: 70, guess: 65, distance: 5,
      points: 4, placed_at: now, guessed_at: now,
    });
    sources.push({ kind: "consensio", id: consensio });
    const spotGame = newUuid();
    await ctx.db.insert("guess_my_spot_games", {
      ...common, id: spotGame, turn_user_id: a, turn_started_at: now, shared_points: 100,
      points_by_user: {}, round_count: 1, version: 1, created_by_user_id: a,
    });
    const spot = newUuid();
    await ctx.db.insert("guess_my_spot_rounds", {
      ...common, id: spot, game_id: spotGame, round_number: 1, sender_user_id: a, guesser_user_id: b,
      photo_media_asset_id: newUuid(), spot_latitude: 60, spot_longitude: 10, sent_at: now,
      guess_latitude: 59, guess_longitude: 10, distance_m: 111_000, points: 100, guessed_at: now,
      sender_reveal_seen_at: now, guesser_reveal_seen_at: now,
    });
    sources.push({ kind: "guess_my_spot", id: spot });
    const story = newUuid();
    await ctx.db.insert("story_chain_stories", {
      ...common, id: story, game_id: newUuid(), story_number: 1, starter_user_id: a,
      opening_text: "It was a quiet night.", state: "finished", title: "Our story", seen_by: [], finished_at: now,
      lines: [{ id: newUuid(), number: 1, author_user_id: b, text: "Then a duck knocked.", created_at: now }],
    });
    sources.push({ kind: "story_chain", id: story });
    const figure = newUuid();
    await ctx.db.insert("exquisite_corpse_figures", {
      ...common, id: figure, game_id: newUuid(), number: 1, starter_user_id: a, finished_at: now,
    });
    for (let part = 0; part < 3; part++) {
      await ctx.db.insert("exquisite_corpse_parts", {
        couple_id: couple.coupleId, created_at: now, id: newUuid(), figure_id: figure, game_id: newUuid(), figure_number: 1,
        part_index: part, drawer_user_id: part === 1 ? b : a, drawing_media_asset_id: newUuid(),
      });
    }
    sources.push({ kind: "exquisite_corpse", id: figure });
    for (const kind of ["connect_four", "dots_and_boxes", "ultimate_tic_tac_toe", "ludo"] as const) {
      await ctx.db.insert("board_game_history", {
        couple_id: couple.coupleId, kind, game_number: 1, first_user_id: a, moves: [0, 1],
        winner_user_id: a, win_line: [], stake: "You pick dinner", started_at: now, finished_at: now,
      });
      sources.push({ kind, couple_id: couple.coupleId, game_number: 1 });
    }
    return sources;
  });
}

test("every finished game supports one shared conversation and refuses another couple", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const other = await createCouple(t);
  const sources = await seedGames(t, couple);
  for (const source of sources) {
    const args = { p_couple_id: couple.coupleId, p_source: source };
    expect((await failure(other.first.as.query(api.gameConversations.get_game_conversation, args))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.threads.create_game_thread_with_message, { ...args, ...op(), p_body: "no" }))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.threads.create_game_thread_with_message, {
      ...args, p_couple_id: other.coupleId, ...op(), p_body: "no",
    }))).code).toBe("42501");
    const operation = { ...args, ...op(), p_body: "What was that?" };
    const [first] = await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation);
    expect(await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation)).toEqual([first]);
    const [reply] = await couple.second.as.mutation(api.threads.create_game_thread_with_message, { ...args, ...op(), p_body: "I have no idea" });
    expect(reply.thread_id).toBe(first.thread_id);
    const context = await couple.second.as.query(api.gameConversations.get_game_conversation, args);
    expect(context?.kind).toBe(source.kind);
    const messages = await couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: first.thread_id, p_limit: 50 });
    expect(messages.messages.map(message => message.body).sort()).toEqual(["I have no idea", "What was that?"]);
  }
  expect(await t.run(ctx => ctx.db.query("game_threads").collect())).toHaveLength(10);
  const summaries = await couple.first.as.query(api.threads.get_conversation_threads, {});
  expect(summaries.filter(row => row.kind === "game")).toHaveLength(10);
  expect(summaries.every(row => sources.some(source => JSON.stringify(source) === JSON.stringify(row.game_source)))).toBe(true);
});

test("the full trail is relative to the reader and never includes unrevealed words", async () => {
  const t = newTest();
  const couple = await createCouple(t);
  const sources = await seedGames(t, couple);
  const args = { p_couple_id: couple.coupleId, p_source: sources[0] };
  const first = await couple.first.as.query(api.gameConversations.get_game_conversation, args);
  const second = await couple.second.as.query(api.gameConversations.get_game_conversation, args);
  expect(first?.kind).toBe("mind_meld"); expect(second?.kind).toBe("mind_meld");
  if (first?.kind !== "mind_meld" || second?.kind !== "mind_meld") throw new Error("wrong game");
  expect(first.result.rounds.map(round => [round.my_word, round.partner_word])).toEqual([["Ocean", "Sushi"], ["Fish", "Fish"]]);
  expect(second.result.rounds.map(round => [round.my_word, round.partner_word])).toEqual([["Sushi", "Ocean"], ["Fish", "Fish"]]);
  expect(JSON.stringify(first)).not.toContain("Secret");
  const drawing = await couple.first.as.query(api.gameConversations.get_game_conversation, { ...args, p_source: sources[1] });
  expect(drawing).toMatchObject({ guesses: ["cat", "hat", "umbrella"] });
});

test("unfinished games and revoked access cannot start or reopen a conversation, including a replay", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const source = (await seedGames(t, couple))[0];
  const args = { p_couple_id: couple.coupleId, p_source: source, ...op(), p_body: "hi" };
  if (source.kind !== "mind_meld") throw new Error("expected Mind Meld");
  await t.run(async ctx => {
    const game = await getByUuid(ctx, "mind_meld_games", source.id);
    if (!game) throw new Error("missing game");
    await ctx.db.patch(game._id, { state: "playing" });
  });
  expect((await failure(couple.first.as.query(api.gameConversations.get_game_conversation, {
    p_couple_id: couple.coupleId, p_source: source,
  }))).code).toBe("42501");
  expect((await failure(couple.first.as.mutation(api.threads.create_game_thread_with_message, args))).code).toBe("42501");
  await t.run(async ctx => {
    const game = await getByUuid(ctx, "mind_meld_games", source.id);
    if (!game) throw new Error("missing game");
    await ctx.db.patch(game._id, { state: "ended" });
  });
  await couple.first.as.mutation(api.threads.create_game_thread_with_message, args);
  await endCouple(t, couple.coupleId, couple.first.userId);
  expect((await failure(couple.first.as.mutation(api.threads.create_game_thread_with_message, args))).code).toBe("42501");
  expect((await failure(couple.first.as.query(api.gameConversations.get_game_conversation, { p_couple_id: couple.coupleId, p_source: source }))).code).toBe("42501");
  const unpaid = await createCouple(t, { entitled: false });
  const unpaidSource = (await seedGames(t, unpaid))[0];
  expect((await failure(unpaid.first.as.mutation(api.threads.create_game_thread_with_message, {
    ...op(), p_couple_id: unpaid.coupleId, p_source: unpaidSource, p_body: "no",
  }))).code).toBe("42501");
});

test("deleting a photo round removes its conversation and hides its messages", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const source = (await seedGames(t, couple))[3];
  if (!("id" in source)) throw new Error("expected round");
  const [thread] = await couple.first.as.mutation(api.threads.create_game_thread_with_message, {
    ...op(), p_couple_id: couple.coupleId, p_source: source, p_body: "hi",
  });
  await couple.first.as.mutation(api.guessMySpot.delete_guess_my_spot_round, { ...op(), p_round_id: source.id });
  expect(await couple.second.as.query(api.threads.get_conversation_threads, {})).toEqual([]);
  const page = await couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: thread.thread_id, p_limit: 50 });
  expect(page.messages.every(message => message.body === null)).toBe(true);
});

test("a relationship purge removes the game conversation links and messages", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const source = (await seedGames(t, couple))[0];
  await couple.first.as.mutation(api.threads.create_game_thread_with_message, {
    ...op(), p_couple_id: couple.coupleId, p_source: source, p_body: "Private conversation",
  });
  await endCouple(t, couple.coupleId, couple.first.userId);
  await t.run(async ctx => {
    const row = await getByUuid(ctx, "couples", couple.coupleId);
    if (!row) throw new Error("missing couple");
    await purgeCoupleContent(ctx, row);
  });
  expect(await t.run(ctx => ctx.db.query("game_threads").collect())).toEqual([]);
  expect(await t.run(ctx => ctx.db.query("thread_messages").collect())).toEqual([]);
});

test("board subjects have a stable UUID shared with the iOS decoder", async () => {
  expect(await gameChatSubjectId({ kind: "ludo", couple_id: "11111111-1111-1111-1111-111111111111", game_number: 7 }))
    .toBe("0a5acf9e-861c-3e27-12da-85c9e7b1ec89");
});
