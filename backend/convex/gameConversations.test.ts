import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import { gameChatResultId, gameChatSubjectId, type GameChatSource } from "./lib/gameChatSubjects";
import { getByUuid } from "./lib/db";
import { purgeCoupleContent } from "./lib/relationshipCleanup";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op } from "./media.testing";
import { addDevice, createCouple, newTest, type TestConvex, type TestCouple } from "./test.setup";

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
      chat_result_available: true,
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
    const piccanteId = newUuid();
    const state = { game_number: 1, starter_user_id: a, partner_user_id: b, phase: "finished" as const,
      size: 3, chilis: [{ tile: 0, user_id: a, note: "Tea?" }, { tile: 8, user_id: b }], sniffs: [],
      bites: [{ tile: 0, user_id: b }], winner_user_id: a, loser_user_id: b, started_at: now, finished_at: now };
    await ctx.db.insert("piccante_games", { id: piccanteId, couple_id: couple.coupleId, version: 4, state,
      wins_by_user: { [a]: 1 }, games_finished: 1, turn_started_at: now, created_at: now, updated_at: now });
    await ctx.db.insert("piccante_results", { id: newUuid(), game_id: piccanteId, couple_id: couple.coupleId,
      game_number: 1, state, seen_by_user_ids: [], finished_at: now });
    sources.push({ kind: "piccante", couple_id: couple.coupleId, game_number: 1 });
    return sources;
  });
}

test("every finished game supports one shared conversation and refuses another couple", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const other = await createCouple(t);
  const sources = await seedGames(t, couple);
  for (const source of sources) {
    const args = { p_couple_id: couple.coupleId, p_game_kind: source.kind };
    expect((await failure(other.first.as.query(api.gameConversations.get_game_conversation, { p_couple_id: couple.coupleId, p_source: source }))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.threads.create_game_thread_with_message, { ...args, ...op(), p_body: "no" }))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.threads.create_game_thread_with_message, {
      ...args, p_couple_id: other.coupleId, p_reply_to_game_result_source: source, ...op(), p_body: "no",
    }))).code).toBe("23514");
    const operation = { ...args, ...op(), p_body: "What was that?" };
    const [first] = await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation);
    expect(await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation)).toEqual([first]);
    const [reply] = await couple.second.as.mutation(api.threads.create_game_thread_with_message, { ...args, ...op(), p_body: "I have no idea" });
    expect(reply.thread_id).toBe(first.thread_id);
    const context = await couple.second.as.query(api.gameConversations.get_game_conversation, { p_couple_id: couple.coupleId, p_source: source });
    expect(context?.kind).toBe(source.kind);
    const messages = await couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: first.thread_id, p_limit: 50 });
    expect(messages.messages.map(message => message.body).sort()).toEqual(["I have no idea", "What was that?"]);
  }
  expect(await t.run(ctx => ctx.db.query("game_threads").collect())).toHaveLength(11);
  const summaries = await couple.first.as.query(api.threads.get_conversation_threads, {});
  expect(summaries.filter(row => row.kind === "game")).toHaveLength(11);
  expect(summaries.every(row => sources.some(source => source.kind === row.game_kind))).toBe(true);
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

test("unfinished results stay private while their chat opens, and revoked access refuses replay", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const source = (await seedGames(t, couple))[0];
  const args = { p_couple_id: couple.coupleId, p_game_kind: source.kind, ...op(), p_body: "hi" };
  if (source.kind !== "mind_meld") throw new Error("expected Mind Meld");
  await t.run(async ctx => {
    const game = await getByUuid(ctx, "mind_meld_games", source.id);
    if (!game) throw new Error("missing game");
    await ctx.db.patch(game._id, { state: "playing" });
  });
  expect((await failure(couple.first.as.query(api.gameConversations.get_game_conversation, {
    p_couple_id: couple.coupleId, p_source: source,
  }))).code).toBe("42501");
  expect((await failure(couple.first.as.mutation(api.threads.create_game_thread_with_message, { ...args, p_reply_to_game_result_source: source }))).code).toBe("23514");
  await couple.first.as.mutation(api.threads.create_game_thread_with_message, args);
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
    ...op(), p_couple_id: unpaid.coupleId, p_game_kind: unpaidSource.kind, p_body: "no",
  }))).code).toBe("42501");
});

test("deleting a photo round removes only its result and keeps the chat messages", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const source = (await seedGames(t, couple))[3];
  if (!("id" in source)) throw new Error("expected round");
  const operation = {
    ...op(), p_couple_id: couple.coupleId, p_game_kind: source.kind, p_body: "hi",
    p_reply_to_game_result_source: source,
  };
  const [thread] = await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation);
  await couple.first.as.mutation(api.guessMySpot.delete_guess_my_spot_round, { ...op(), p_round_id: source.id });
  expect(await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation)).toEqual([thread]);
  expect(await couple.second.as.query(api.threads.get_conversation_threads, {})).toHaveLength(1);
  const page = await couple.second.as.query(api.threads.get_thread_messages, { p_thread_id: thread.thread_id, p_limit: 50 });
  expect(page.messages.map(message => message.body)).toEqual(["hi"]);
  expect(await couple.second.as.query(api.gameConversations.get_game_chat_timeline, { p_couple_id: couple.coupleId, p_game_kind: source.kind })).toMatchObject({ thread_id: thread.thread_id, results: [] });
  expect(await couple.second.as.query(api.gameConversations.get_game_conversation, { p_couple_id: couple.coupleId, p_source: source })).toBeNull();
  expect((await failure(couple.second.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: thread.thread_id, p_body: "reply", p_reply_to_game_result_source: source }))).code).toBe("23514");
  await couple.second.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: thread.thread_id, p_body: "still here" });
});

test("a relationship purge removes the game conversation links and messages", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const source = (await seedGames(t, couple))[0];
  await couple.first.as.mutation(api.threads.create_game_thread_with_message, {
    ...op(), p_couple_id: couple.coupleId, p_game_kind: source.kind, p_body: "Private conversation",
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
  expect(await gameChatResultId({ kind: "ludo", couple_id: "11111111-1111-1111-1111-111111111111", game_number: 7 }))
    .toBe("0a5acf9e-861c-3e27-12da-85c9e7b1ec89");
});

test("a kind-scoped chat opens before any games and shares the client UUID recipe", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const args = { p_couple_id: couple.coupleId, p_game_kind: "connect_four" as const };
  expect(await couple.first.as.query(api.gameConversations.get_game_chat_timeline, args)).toEqual({ thread_id: null, messages: [], results: [], has_more: false, next_before: null });
  const operation = { ...args, ...op(), p_body: "Ready?" };
  const sent = await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation);
  expect(await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation)).toEqual(sent);
  expect(await couple.first.as.query(api.gameConversations.get_game_chat_timeline, args)).toMatchObject({ thread_id: sent[0].thread_id, messages: [{ body: "Ready?" }], results: [], has_more: false });
  const link = await t.run(ctx => ctx.db.query("game_threads").unique());
  expect(link?.subject_id).toBe(await gameChatSubjectId(couple.coupleId, "connect_four"));
  expect(await gameChatSubjectId("00000000-0000-0000-0000-000000000001", "connect_four")).toBe("5117096c-484e-52e5-c36f-bb03b8cfaad8");
});

test("timeline refuses outsiders and unpaid members for all kinds, before and after a thread exists", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const outsider = await createCouple(t);
  const unpaid = await createCouple(t, { entitled: false });
  const sources = await seedGames(t, couple);
  await seedGames(t, unpaid);
  for (const source of sources) {
    const args = { p_couple_id: couple.coupleId, p_game_kind: source.kind };
    expect((await failure(outsider.first.as.query(api.gameConversations.get_game_chat_timeline, args))).code).toBe("42501");
    expect((await failure(unpaid.first.as.query(api.gameConversations.get_game_chat_timeline, { ...args, p_couple_id: unpaid.coupleId }))).code).toBe("42501");
    expect((await failure(unpaid.first.as.query(api.gameConversations.get_game_conversation, { p_couple_id: unpaid.coupleId, p_source: source }))).code).toBe("42501");
    const page = await couple.first.as.query(api.gameConversations.get_game_chat_timeline, args);
    expect(page.thread_id).toBeNull();
    expect(page.results).toEqual([{ source, finished_at: now, key: "id" in source ? source.id : "0000000000000001" }]);
    const [sent] = await couple.first.as.mutation(api.threads.create_game_thread_with_message, { ...args, ...op(), p_body: "hello" });
    expect((await failure(outsider.first.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: sent.thread_id, p_body: "no" }))).code).toBe("42501");
    expect((await failure(unpaid.first.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: sent.thread_id, p_body: "no" }))).code).toBe("42501");
  }
});

test("result replies are typed, validated before the first send and included in idempotency", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const other = await createCouple(t);
  const [mind, draw] = await seedGames(t, couple);
  const foreign = (await seedGames(t, other))[0];
  const args = { p_couple_id: couple.coupleId, p_game_kind: mind.kind, p_body: "That was close" };
  for (const source of [draw, foreign]) {
    expect((await failure(couple.first.as.mutation(api.threads.create_game_thread_with_message, { ...args, ...op(), p_reply_to_game_result_source: source }))).code).toBe("23514");
  }
  expect(await t.run(ctx => ctx.db.query("game_threads").collect())).toEqual([]);
  const operation = { ...args, ...op(), p_reply_to_game_result_source: mind };
  const first = await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation);
  expect(await couple.first.as.mutation(api.threads.create_game_thread_with_message, operation)).toEqual(first);
  if ("id" in mind) {
    expect(await couple.first.as.mutation(api.threads.create_game_thread_with_message, {
      ...operation, p_reply_to_game_result_source: { id: mind.id, kind: mind.kind },
    })).toEqual(first);
  }
  expect((await failure(couple.first.as.mutation(api.threads.create_game_thread_with_message, { ...operation, p_reply_to_game_result_source: undefined }))).code).toBe("23505");
  const threadId = first[0].thread_id;
  const send = { ...op(), p_thread_id: threadId, p_body: "Agreed", p_reply_to_game_result_source: mind };
  const second = await couple.second.as.mutation(api.threads.send_thread_message, send);
  expect(await couple.second.as.mutation(api.threads.send_thread_message, send)).toEqual(second);
  expect((await failure(couple.second.as.mutation(api.threads.send_thread_message, { ...send, p_reply_to_game_result_source: undefined }))).code).toBe("23505");
  for (const source of [draw, foreign]) {
    expect((await failure(couple.second.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: threadId, p_body: "no", p_reply_to_game_result_source: source }))).code).toBe("23514");
  }
  expect((await failure(couple.second.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: threadId, p_body: "no", p_reply_to_game_result_source: mind, p_reply_to_message_id: first[0].message_id }))).code).toBe("23514");
  const page = await couple.first.as.query(api.gameConversations.get_game_chat_timeline, { p_couple_id: couple.coupleId, p_game_kind: mind.kind });
  expect(page.messages).toHaveLength(2);
  expect(page.messages.every(message => JSON.stringify(message.reply_to_game_result_source) === JSON.stringify(mind))).toBe(true);
  if (!("id" in mind)) throw new Error("expected Mind Meld");
  await t.run(async ctx => {
    const row = await getByUuid(ctx, "mind_meld_games", mind.id);
    if (!row) throw new Error("missing game");
    await ctx.db.patch(row._id, { state: "playing" });
  });
  expect((await failure(couple.second.as.mutation(api.threads.send_thread_message, { ...op(), p_thread_id: threadId, p_body: "no", p_reply_to_game_result_source: mind }))).code).toBe("23514");
  expect((await couple.first.as.query(api.gameConversations.get_game_chat_timeline, { p_couple_id: couple.coupleId, p_game_kind: mind.kind })).results).toEqual([]);
  await endCouple(t, couple.coupleId, couple.first.userId);
  expect((await failure(couple.second.as.mutation(api.threads.send_thread_message, send))).code).toBe("42501");
});

test("one merged page limit handles unequal streams, timestamp ties and removed messages without gaps", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  const [sent] = await couple.first.as.mutation(api.threads.create_game_thread_with_message, { ...op(), p_couple_id: couple.coupleId, p_game_kind: "mind_meld", p_body: "first" });
  const expected = await t.run(async ctx => {
    const message = await getByUuid(ctx, "thread_messages", sent.message_id);
    if (!message) throw new Error("missing message");
    await ctx.db.delete(message._id);
    const items = [];
    for (let number = 1; number <= 13; number++) {
      const id = `00000000-0000-0000-0000-${String(number).padStart(12, "0")}`;
      const at = new Date(Date.parse(now) + (number < 8 ? 0 : 1)).toISOString();
      if (number % 4 === 0) {
        await ctx.db.insert("mind_meld_games", { id, couple_id: couple.coupleId, game_number: number, state: "ended", ended_at: at, end_seen_by_user: {}, version: 1, created_by_user_id: couple.first.userId, created_at: at, updated_at: at });
        items.push({ at, item_kind: "result", key: id });
      } else {
        await ctx.db.insert("thread_messages", { id, couple_id: couple.coupleId, thread_id: sent.thread_id, sender_user_id: couple.first.userId, body: "hello", moderation_status: "visible", deleted_at: number === 3 ? now : undefined, created_at: at, updated_at: at });
        items.push({ at, item_kind: "message", key: id });
      }
    }
    return items.sort((a, b) => JSON.stringify(b).localeCompare(JSON.stringify(a)));
  });
  const seen = [];
  let before: { at: string; item_kind: "message" | "result"; key: string } | undefined;
  do {
    const page = await couple.first.as.query(api.gameConversations.get_game_chat_timeline, { p_couple_id: couple.coupleId, p_game_kind: "mind_meld", p_limit: 2, p_before: before });
    const items = [...page.messages.map(message => ({ at: message.created_at, item_kind: "message", key: message.message_id })), ...page.results.map(result => ({ at: result.finished_at, item_kind: "result", key: result.key }))].sort((a, b) => JSON.stringify(b).localeCompare(JSON.stringify(a)));
    expect(items.length).toBeLessThanOrEqual(2);
    seen.push(...items);
    const removed = page.messages.find(message => message.deleted_at !== null);
    if (removed) expect(removed).toMatchObject({ body: null, reply_to_game_result_source: null, media: [], reactions: [] });
    if (!page.has_more) { expect(page.next_before).toBeNull(); break; }
    expect(page.next_before).not.toBeNull();
    before = page.next_before ?? undefined;
  } while (seen.length < 30);
  expect(seen).toEqual(expected);
});

test("board results with the same finish timestamp page by their natural game number", async () => {
  const t = newTest();
  const couple = await createCouple(t);
  await t.run(async ctx => {
    for (let game_number = 1; game_number <= 12; game_number++) {
      await ctx.db.insert("board_game_history", { couple_id: couple.coupleId, kind: "ludo", game_number, first_user_id: couple.first.userId, moves: [], win_line: [], started_at: now, finished_at: now });
    }
  });
  const numbers = [];
  let before: { at: string; item_kind: "message" | "result"; key: string } | undefined;
  do {
    const page = await couple.first.as.query(api.gameConversations.get_game_chat_timeline, { p_couple_id: couple.coupleId, p_game_kind: "ludo", p_limit: 3, p_before: before });
    numbers.push(...page.results.map(result => "game_number" in result.source ? result.source.game_number : -1).reverse());
    if (!page.has_more) break;
    before = page.next_before ?? undefined;
  } while (numbers.length < 20);
  expect(numbers).toEqual([12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]);
});

test("game chat pushes carry only the stable kind destination", async () => {
  const t = newTest(); scheduled = t;
  const couple = await createCouple(t);
  await addDevice(t, couple.second.userId);
  await couple.first.as.mutation(api.threads.create_game_thread_with_message, { ...op(), p_couple_id: couple.coupleId, p_game_kind: "mind_meld", p_body: "private" });
  const notifications = await t.run(ctx => ctx.db.query("notification_outbox").collect());
  const push = notifications.find(row => row.kind === "thread_message_sent");
  expect(push?.payload).toMatchObject({ game_kind: "mind_meld", couple_id: couple.coupleId, game_chat_id: await gameChatSubjectId(couple.coupleId, "mind_meld"), deeplink: "paeonia://daily/game-chat?kind=mind_meld" });
  expect(push?.payload).not.toHaveProperty("game_source");
  expect(JSON.stringify(push?.payload)).not.toContain("private");
});
