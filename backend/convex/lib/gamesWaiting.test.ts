// Tests for `gamesWaitingFor` in gameRegistry.ts: the games part of the app icon badge. Each case
// drives real moves and checks that only what waits for a user counts for them.
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api } from "../_generated/api";
import { op, setMediaEnv, uploadAsset } from "../media.testing";
import { createCouple, newTest, type TestConvex, type TestCouple, type TestUser } from "../test.setup";
import { gamesWaitingFor } from "./gameRegistry";
import { newUuid } from "./ids";

const START = Date.parse("2026-10-10T12:00:00.000Z");

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (minutes: number) => vi.setSystemTime(new Date(Date.now() + minutes * 60_000));

type Setup = { t: TestConvex; couple: TestCouple; a: TestUser; b: TestUser };

async function startCouple(): Promise<Setup> {
  const t = newTest();
  const couple = await createCouple(t);
  await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
  return { t, couple, a: couple.first, b: couple.second };
}

const waiting = (s: Setup, user: TestUser) => s.t.run((ctx) => gamesWaitingFor(ctx, s.couple.coupleId, user.userId));

async function counts(s: Setup): Promise<[number, number]> {
  return [await waiting(s, s.a), await waiting(s, s.b)];
}

describe("Draw & Guess", () => {
  test("counts the turn for the player who acts and the result until the drawer dismisses it", async () => {
    const s = await startCouple();
    const { game_id: gameId } = await s.a.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});
    expect(await counts(s)).toEqual([1, 0]);

    const offered = (await s.a.as.query(api.drawAndGuess.get_draw_and_guess, {})).choices!.find(
      (choice: { difficulty: string }) => choice.difficulty === "easy",
    )!;
    const picked = await s.a.as.mutation(api.drawAndGuess.pick_draw_word, {
      ...op(),
      p_game_id: gameId,
      p_round_id: newUuid(),
      p_choice: "easy",
      p_custom_word: null,
      p_word_id: offered.word_id,
    });
    const drawing = await uploadAsset(s.t, s.a, {
      kind: "game_move",
      purpose: "game_drawing_payload",
      mediaType: "drawing_payload",
      extension: "pkdrawing",
      mime: "application/octet-stream",
      parentId: picked.round_id,
      coupleId: s.couple.coupleId,
      gameId,
    });
    await s.a.as.mutation(api.drawAndGuess.submit_drawing, { ...op(), p_round_id: picked.round_id, p_media_asset_id: drawing.assetId });
    expect(await counts(s)).toEqual([0, 1]);

    // The solve gives the turn to the guesser and leaves the drawer a result to see.
    await s.b.as.mutation(api.drawAndGuess.submit_guess, { ...op(), p_round_id: picked.round_id, p_guess: picked.word });
    expect(await counts(s)).toEqual([1, 1]);

    await s.a.as.mutation(api.drawAndGuess.mark_round_result_seen, { p_round_id: picked.round_id });
    expect(await counts(s)).toEqual([0, 1]);
  });
});

describe("board games", () => {
  test("count each game in play whose turn is the user's, and nothing once it is finished", async () => {
    const s = await startCouple();
    let game = await s.a.as.mutation(api.boardGames.ensure_board_game, { p_kind: "connect_four" });
    expect(await counts(s)).toEqual([1, 0]);

    game = await s.a.as.mutation(api.boardGames.make_move, { ...op(), p_game_id: game.id, p_expected_version: game.version, p_move: 0 });
    expect(await counts(s)).toEqual([0, 1]);

    // A second board game counts on its own.
    await s.a.as.mutation(api.boardGames.ensure_board_game, { p_kind: "dots_and_boxes" });
    expect(await counts(s)).toEqual([1, 1]);

    // Four in the first column wins for a.
    for (const [user, column] of [[s.b, 1], [s.a, 0], [s.b, 1], [s.a, 0], [s.b, 1], [s.a, 0]] as const) {
      game = await user.as.mutation(api.boardGames.make_move, { ...op(), p_game_id: game.id, p_expected_version: game.version, p_move: column });
    }
    expect(game.status).toBe("finished");
    expect(await counts(s)).toEqual([1, 0]);
  });
});

describe("Story Chain", () => {
  test("counts the turn and the finished story until its last writer has seen it", async () => {
    const s = await startCouple();
    const { game_id: gameId } = await s.a.as.mutation(api.storyChain.ensure_story_chain_game, {});
    expect(await counts(s)).toEqual([1, 0]);

    const storyId = newUuid();
    await s.a.as.mutation(api.storyChain.start_story, { ...op(), p_game_id: gameId, p_story_id: storyId, p_opening_id: null });
    const write = (user: TestUser, number: number, last = false) =>
      user.as.mutation(api.storyChain.add_story_line, {
        ...op(),
        p_story_id: storyId,
        p_line_id: newUuid(),
        p_text: `Line ${number} of the story.`,
        p_is_last: last,
        p_dare_word: null,
        p_dare_word_id: null,
      });
    await write(s.a, 1);
    expect(await counts(s)).toEqual([0, 1]);
    for (let number = 2; number < 8; number += 1) await write(number % 2 === 1 ? s.a : s.b, number);
    await write(s.b, 8, true);
    // a names the story and starts the next one, and b has the finished story to read.
    await s.a.as.mutation(api.storyChain.name_story, { ...op(), p_story_id: storyId, p_title: "The story" });
    expect(await counts(s)).toEqual([1, 1]);

    await s.b.as.mutation(api.storyChain.mark_story_seen, { p_story_id: storyId });
    expect(await counts(s)).toEqual([1, 0]);
  });
});

describe("invites", () => {
  test("an invite counts for the partner until they open the game or it is 15 minutes old", async () => {
    const s = await startCouple();
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "mind_meld" });
    expect(await counts(s)).toEqual([0, 1]);

    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: false });
    expect(await counts(s)).toEqual([0, 0]);

    // A new invite waits for an answer again.
    tick(16);
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "mind_meld" });
    expect(await counts(s)).toEqual([0, 1]);

    tick(16);
    expect(await counts(s)).toEqual([0, 0]);
  });
});
