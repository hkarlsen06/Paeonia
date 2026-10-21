import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, components, internal } from "./_generated/api";
import { newUuid } from "./lib/ids";
import { gameRoom } from "./lib/presence";
import { endCouple, failure, op, setMediaEnv, uploadAsset } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import { photo } from "./media.testing";
import {
  addDevice,
  createCouple,
  createSignedInUser,
  grantLifetime,
  newTest,
  type TestConvex,
  type TestCouple,
  type TestUser,
} from "./test.setup";

const START = Date.parse("2026-10-10T12:00:00.000Z");

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(() => {
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

type Setup = { t: TestConvex; couple: TestCouple; a: TestUser; b: TestUser; gameId: string };

/** A couple with devices, settings, and a game. `a` draws first. */
async function startGame(options: { playStyle?: "together" | "against"; language?: "en" | "nb" } = {}): Promise<Setup> {
  const t = newTest();
  const couple = await createCouple(t);
  const { first: a, second: b } = couple;
  await addDevice(t, a.userId);
  await addDevice(t, b.userId);
  await a.as.mutation(api.games.set_game_settings, {
    p_play_style: options.playStyle ?? "together",
    p_language: options.language ?? "en",
  });
  const { game_id } = await a.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});
  return { t, couple, a, b, gameId: game_id };
}

const view = (user: TestUser) => user.as.query(api.drawAndGuess.get_draw_and_guess, {});

async function pick(user: TestUser, gameId: string, choice: "easy" | "medium" | "hard" | "custom", custom?: string, roundId = newUuid()) {
  const offered = choice === "custom" ? null : (await view(user)).choices?.find((item: { difficulty: string }) => item.difficulty === choice);
  const result = await user.as.mutation(api.drawAndGuess.pick_draw_word, {
    ...op(),
    p_game_id: gameId,
    p_round_id: roundId,
    p_choice: choice,
    p_custom_word: custom ?? null,
    p_word_id: offered?.word_id ?? null,
  });
  return result;
}

async function uploadDrawing(s: Setup, user: TestUser, roundId: string) {
  return await uploadAsset(s.t, user, {
    kind: "game_move",
    purpose: "game_drawing_payload",
    mediaType: "drawing_payload",
    extension: "pkdrawing",
    mime: "application/octet-stream",
    parentId: roundId,
    coupleId: s.couple.coupleId,
    gameId: s.gameId,
  });
}

async function sendDrawing(s: Setup, user: TestUser, roundId: string) {
  const up = await uploadDrawing(s, user, roundId);
  return await user.as.mutation(api.drawAndGuess.submit_drawing, { ...op(), p_round_id: roundId, p_media_asset_id: up.assetId });
}

const guess = (user: TestUser, roundId: string, text: string) =>
  user.as.mutation(api.drawAndGuess.submit_guess, { ...op(), p_round_id: roundId, p_guess: text });

const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

/** Plays a whole round: `drawer` picks and sends a drawing, `guesser` marks it seen and guesses after `afterSeconds`. */
async function playRound(
  s: Setup,
  drawer: TestUser,
  guesser: TestUser,
  choice: "easy" | "medium" | "hard",
  afterSeconds: number | null,
) {
  const picked = await pick(drawer, s.gameId, choice);
  await sendDrawing(s, drawer, picked.round_id);
  if (afterSeconds !== null) {
    await guesser.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id });
    tick(afterSeconds);
  }
  return { picked, result: await guess(guesser, picked.round_id, picked.word) };
}

const favoriteRound = (user: TestUser, roundId: string, favorited = true) =>
  user.as.mutation(api.favorites.set_favorite, { p_kind: "game_round", p_target_id: roundId, p_favorited: favorited });

describe("access", () => {
  test("a user without a couple cannot use the games", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect((await failure(loner.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {}))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" }))).code).toBe("42501");
    expect((await failure(loner.as.query(api.drawAndGuess.get_draw_and_guess, {}))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" }))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true }))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.create_game_live_ticket, { p_kind: "draw_and_guess" }))).code).toBe("42501");
  });

  test("a couple without a subscription cannot use the games", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(couple.first.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {}))).code).toBe("42501");
    expect((await failure(couple.first.as.query(api.games.get_games_overview, {}))).code).toBe("42501");
  });

  test("a subscription that ends blocks the existing game", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    await s.t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    expect((await failure(s.a.as.mutation(api.drawAndGuess.pick_draw_word, { ...op(), p_game_id: s.gameId, p_round_id: newUuid(), p_choice: "easy", p_custom_word: null }))).code).toBe("42501");
    expect((await failure(s.b.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id }))).code).toBe("42501");
  });

  test("another couple cannot touch a round", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const other = await createCouple(s.t);
    expect((await failure(guess(other.first, picked.round_id, "cat"))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id }))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.drawAndGuess.mark_round_result_seen, { p_round_id: picked.round_id }))).code).toBe("42501");
    expect((await failure(favoriteRound(other.first, picked.round_id))).code).toBe("23514");
    expect(await view(other.first)).toMatchObject({ game: null, current_round: null });
  });

  test("a partner who left cannot play after the relationship ends", async () => {
    const s = await startGame();
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect((await failure(s.b.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true }))).code).toBe("42501");
  });

  test("a pending account deletion blocks writes", async () => {
    const s = await startGame();
    await s.t.run(async (ctx) => {
      await ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: s.a.userId,
        auth_provider: "apple",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
    });
    expect((await failure(s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true }))).message).toMatch(/account deletion/);
    expect((await failure(s.a.as.mutation(api.drawAndGuess.pick_draw_word, { ...op(), p_game_id: s.gameId, p_round_id: newUuid(), p_choice: "easy", p_custom_word: null }))).message).toMatch(/account deletion/);
  });
});

describe("settings", () => {
  test("a new language replaces the words offered for the open turn", async () => {
    const s = await startGame({ language: "en" });
    const en = (await view(s.a)).choices!.map((choice) => choice.word_id);
    await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    const nb = (await view(s.a)).choices!;
    expect(nb).toHaveLength(3);
    const catalog = await import("../games/words/nb.json");
    for (const choice of nb) {
      expect(catalog.words.find((word) => word.id === choice.word_id)?.text).toBe(choice.word);
    }
    expect(nb.map((choice) => choice.word_id)).not.toEqual(en);
  });

  test("the game needs settings first", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await failure(couple.first.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {}))).message).toMatch(/settings are required/);
  });
});

describe("ensure_draw_and_guess_game", () => {
  test("creates one game with the caller drawing first, and returns it again", async () => {
    const s = await startGame();
    const again = await s.b.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});
    expect(again).toEqual({ game_id: s.gameId, created: false });
    const data = await view(s.a);
    expect(data.game).toMatchObject({
      id: s.gameId,
      state: "choosing_word",
      turn_user_id: s.a.userId,
      turn_number: 1,
      shared_points: 0,
      my_points: 0,
      partner_points: 0,
      current_round_id: null,
    });
    expect(data.current_round).toBeNull();
    expect(data.recent_rounds).toEqual([]);
    expect(data.partner_user_id).toBe(s.b.userId);
    expect(data.settings).toMatchObject({ play_style: "together", language: "en" });
    expect(await s.t.run((ctx) => ctx.db.query("games").collect())).toHaveLength(1);
  });

  test("two partners opening at the same time still get one game", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    const [x, y] = await Promise.all([
      couple.first.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {}),
      couple.second.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {}),
    ]);
    expect(x.game_id).toBe(y.game_id);
    expect([x.created, y.created].sort()).toEqual([false, true]);
  });
});

describe("word choices", () => {
  test("the drawer sees three choices, one per difficulty, and the guesser sees none", async () => {
    const s = await startGame();
    const mine = (await view(s.a)).choices!;
    expect(mine.map((choice) => [choice.difficulty, choice.points])).toEqual([
      ["easy", 1],
      ["medium", 2],
      ["hard", 3],
    ]);
    expect((await view(s.b)).choices).toBeNull();
    // The choices stay fixed when the game is reopened.
    expect((await view(s.a)).choices).toEqual(mine);
  });

  test("choices are stored on the row only while a turn waits for a word", async () => {
    const s = await startGame();
    await pick(s.a, s.gameId, "easy");
    expect((await view(s.a)).choices).toBeNull();
    const row = await s.t.run((ctx) => ctx.db.query("games").first());
    expect(row?.word_choices).toBeUndefined();
  });

  test("the guesser's phone gets no choices after a round ends either, but the new drawer does", async () => {
    const s = await startGame();
    await playRound(s, s.a, s.b, "easy", null);
    expect((await view(s.a)).choices).toBeNull();
    expect((await view(s.b)).choices).toHaveLength(3);
  });

  test("a couple does not see the same word twice until the list runs out", async () => {
    const s = await startGame();
    const seen = new Map<string, number>();
    const record = (choices: { word_id: string }[]) => choices.forEach((choice) => seen.set(choice.word_id, (seen.get(choice.word_id) ?? 0) + 1));
    record((await view(s.a)).choices!);
    let drawer = s.a;
    let guesser = s.b;
    for (let turn = 0; turn < 10; turn += 1) {
      await playRound(s, drawer, guesser, "easy", null);
      [drawer, guesser] = [guesser, drawer];
      record((await view(drawer)).choices!);
    }
    expect([...seen.values()].every((count) => count === 1)).toBe(true);
    expect(seen.size).toBe(33);
  });

  test("a difficulty starts over after all its words were shown", async () => {
    const s = await startGame();
    const catalog = await import("../games/words/en.json");
    const hard = catalog.words.filter((word) => word.difficulty === "hard");
    await s.t.run(async (ctx) => {
      const used = await ctx.db.query("game_used_words").collect();
      for (const row of used) await ctx.db.delete(row._id);
      for (const word of hard) {
        await ctx.db.insert("game_used_words", {
          game_id: s.gameId,
          couple_id: s.couple.coupleId,
          language: "en",
          difficulty: "hard",
          word_id: word.id,
          created_at: new Date().toISOString(),
        });
      }
    });
    await playRound(s, s.a, s.b, "easy", null);
    const usedHard = await s.t.run(async (ctx) =>
      (await ctx.db.query("game_used_words").collect()).filter((row) => row.difficulty === "hard"),
    );
    // The used set was reset, so only the new hard choice is marked.
    expect(usedHard).toHaveLength(1);
  });
});

describe("pick_draw_word", () => {
  test("starts the round in drawing and the guesser sees the word", async () => {
    const s = await startGame();
    const choice = (await view(s.a)).choices![1];
    const picked = await pick(s.a, s.gameId, "medium");
    expect(picked).toMatchObject({ round_number: 1, difficulty: "medium", word: choice.word, points: 2 });
    const data = await view(s.b);
    expect(data.game).toMatchObject({ state: "drawing", turn_user_id: s.a.userId, current_round_id: picked.round_id });
    expect(data.current_round).toMatchObject({
      id: picked.round_id,
      state: "drawing",
      drawer_user_id: s.a.userId,
      guesser_user_id: s.b.userId,
      word: choice.word,
      drawing_media_asset_id: null,
      attempts: [],
    });
  });

  test("a retry with the same operation returns the same round", async () => {
    const s = await startGame();
    const offered = (await view(s.a)).choices!.find((item: { difficulty: string }) => item.difficulty === "easy")!;
    const args = { ...op(), p_game_id: s.gameId, p_round_id: newUuid(), p_choice: "easy" as const, p_custom_word: null, p_word_id: offered.word_id };
    const first = await s.a.as.mutation(api.drawAndGuess.pick_draw_word, args);
    expect(await s.a.as.mutation(api.drawAndGuess.pick_draw_word, args)).toEqual(first);
    expect(await s.t.run((ctx) => ctx.db.query("game_moves").collect())).toHaveLength(1);
  });

  test("only the drawer whose turn it is can pick, and only once", async () => {
    const s = await startGame();
    expect(await failure(pick(s.b, s.gameId, "easy"))).toMatchObject({ code: "42501", message: "it is not your turn" });
    await pick(s.a, s.gameId, "easy");
    expect((await failure(pick(s.a, s.gameId, "easy"))).message).toMatch(/already chosen/);
  });

  test("a custom word scores like a medium word", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "custom", "  Dog At   Mom ");
    expect(picked).toMatchObject({ difficulty: "custom", word: "dog at mom", points: 2 });
    expect((await view(s.b)).current_round).toMatchObject({ difficulty: "custom", word: "dog at mom", points: 2 });
  });

  test.each(["", "a", "x".repeat(21), "one two three four", "cat5", "no!", "tæ.st"])("rejects the custom word %j", async (word) => {
    const s = await startGame();
    expect((await failure(pick(s.a, s.gameId, "custom", word))).code).toBe("23514");
    expect((await view(s.a)).game?.state).toBe("choosing_word");
  });

  test.each(["ab", "Brunost", "Æ Ø Å", "x".repeat(20), "a b c"])("accepts the custom word %j", async (word) => {
    const s = await startGame();
    expect((await pick(s.a, s.gameId, "custom", word)).word).toBe(word.toLowerCase());
  });
});

describe("submit_drawing", () => {
  test("moves the round to guessing, gives the partner the turn, and counts for the streak", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const sent = await sendDrawing(s, s.a, picked.round_id);
    expect(sent).toMatchObject({ round_id: picked.round_id, round_state: "guessing" });

    const data = await view(s.b);
    expect(data.game).toMatchObject({ state: "guessing", turn_user_id: s.b.userId });
    expect(data.current_round).toMatchObject({ state: "guessing" });
    expect(data.current_round?.drawing_media_asset_id).toBeTruthy();

    const events = await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({
      activity_kind: "game_turn_completed",
      user_id: s.a.userId,
      dedupe_key: `game_turn_completed:${picked.round_id}`,
    });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("both partners sending a drawing on one day qualify the streak", async () => {
    const s = await startGame();
    await playRound(s, s.a, s.b, "easy", null);
    const second = await pick(s.b, s.gameId, "easy");
    await sendDrawing(s, s.b, second.round_id);
    const streak = await s.t.run((ctx) => ctx.db.query("streak_states").first());
    expect(streak?.current_count).toBe(1);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("only the drawer sends, once, and only the round's own asset", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const mine = await uploadDrawing(s, s.a, picked.round_id);
    const submit = (user: TestUser, assetId: string, roundId = picked.round_id) =>
      user.as.mutation(api.drawAndGuess.submit_drawing, { ...op(), p_round_id: roundId, p_media_asset_id: assetId });
    expect((await failure(submit(s.b, mine.assetId))).code).toBe("42501");
    // Nobody can reserve a drawing upload for a round they don't draw, or for a round that doesn't exist.
    expect((await failure(uploadDrawing(s, s.b, picked.round_id))).code).toBe("42501");
    expect((await failure(uploadDrawing(s, s.a, newUuid()))).code).toBe("42501");
    // An image from the memory bucket is not a drawing.
    const image = await uploadAsset(s.t, s.a, photo(s.couple.coupleId));
    expect((await failure(submit(s.a, image.assetId))).message).toMatch(/not usable/);

    await submit(s.a, mine.assetId);
    expect((await failure(submit(s.a, mine.assetId))).code).toBe("23505");
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a retried send returns the first answer and queues one push", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const up = await uploadDrawing(s, s.a, picked.round_id);
    const args = { ...op(), p_round_id: picked.round_id, p_media_asset_id: up.assetId };
    const first = await s.a.as.mutation(api.drawAndGuess.submit_drawing, args);
    expect(await s.a.as.mutation(api.drawAndGuess.submit_drawing, args)).toEqual(first);
    expect((await outbox(s.t)).filter((row) => row.kind === "game_turn_ready")).toHaveLength(1);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the partner can download the drawing and an outsider cannot", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const up = await uploadDrawing(s, s.a, picked.round_id);
    // A drawing nobody attached yet is not readable by the partner.
    expect((await failure(s.b.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId, p_expires_in_seconds: 300 }))).code).toBe("42501");
    await s.a.as.mutation(api.drawAndGuess.submit_drawing, { ...op(), p_round_id: picked.round_id, p_media_asset_id: up.assetId });

    for (const user of [s.a, s.b]) {
      const [row] = await user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId, p_expires_in_seconds: 300 });
      expect(row.bucket).toBe("game-drawings");
      expect(row.storage_path).toBe(`${s.couple.coupleId}/${s.gameId}/rounds/${picked.round_id}/${up.assetId}.pkdrawing`);
      expect(row.signed_url).toContain(`asset=${up.assetId}`);
    }
    const stranger = await createCouple(s.t);
    expect((await failure(stranger.first.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId, p_expires_in_seconds: 300 }))).code).toBe("42501");
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a drawing upload needs a game of the same couple", async () => {
    const s = await startGame();
    const stranger = await createCouple(s.t);
    const reserve = (user: TestUser, coupleId: string, gameId?: string) =>
      user.as.mutation(api.media.create_pending_media_upload, {
        ...op(),
        p_reserved_parent_kind: "game_move",
        p_reserved_parent_id: newUuid(),
        p_upload_purpose: "game_drawing_payload",
        p_media_type: "drawing_payload",
        p_file_extension: "pkdrawing",
        p_couple_id: coupleId,
        ...(gameId ? { p_path_context: { game_id: gameId } } : {}),
      });
    expect((await failure(reserve(s.a, s.couple.coupleId))).message).toMatch(/require a game id/);
    expect((await failure(reserve(stranger.first, stranger.coupleId, s.gameId))).code).toBe("42501");
    expect((await failure(reserve(s.a, stranger.coupleId, s.gameId))).code).toBe("42501");
    expect((await failure(reserve(s.a, s.couple.coupleId, newUuid()))).code).toBe("42501");
  });
});

describe("guessing", () => {
  test("a wrong guess is stored with its time and the round stays open", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, picked.round_id);
    const wrong = await guess(s.b, picked.round_id, "definitely not it");
    expect(wrong).toMatchObject({ correct: false, round_state: "guessing", points: 0, speed_bonus: 0 });
    tick(5);
    await guess(s.b, picked.round_id, "  Nope ");
    const data = await view(s.a);
    expect(data.current_round?.state).toBe("guessing");
    expect(data.current_round?.attempts.map((attempt) => [attempt.text, attempt.correct, attempt.user_id])).toEqual([
      ["definitely not it", false, s.b.userId],
      ["nope", false, s.b.userId],
    ]);
    expect(data.current_round!.attempts[1].created_at > data.current_round!.attempts[0].created_at).toBe(true);
    expect(data.game).toMatchObject({ state: "guessing", shared_points: 0 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a correct guess ignores case and extra spaces, solves the round, and the guesser draws next", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "custom", "hot dog");
    await sendDrawing(s, s.a, picked.round_id);
    const result = await guess(s.b, picked.round_id, "  HOT    Dog ");
    expect(result).toMatchObject({ correct: true, round_state: "solved", points: 2 });

    const asDrawer = await view(s.a);
    expect(asDrawer.current_round).toMatchObject({ state: "solved", word: "hot dog" });
    expect(asDrawer.current_round?.attempts).toHaveLength(1);
    expect(asDrawer.game).toMatchObject({ state: "choosing_word", turn_user_id: s.b.userId, turn_number: 2, shared_points: 2 });
    expect(asDrawer.choices).toBeNull();
    expect((await view(s.b)).choices).toHaveLength(3);

    // The next round is the guesser's turn to draw.
    const next = await pick(s.b, s.gameId, "easy");
    expect(next.round_number).toBe(2);
    const data = await view(s.a);
    expect(data.current_round).toMatchObject({ id: next.round_id, drawer_user_id: s.b.userId, guesser_user_id: s.a.userId });
    expect(data.recent_rounds.map((round) => round.id)).toEqual([picked.round_id]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("only the guesser guesses, and a finished round takes no more guesses", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    expect((await failure(guess(s.a, picked.round_id, "cat"))).message).toBe("only the guesser can guess");
    await sendDrawing(s, s.a, picked.round_id);
    await guess(s.b, picked.round_id, picked.word);
    expect((await failure(guess(s.b, picked.round_id, "cat"))).message).toBe("this round is already finished");
    expect((await failure(guess(s.b, picked.round_id, "   "))).code).toBe("23514");
    expect((await failure(guess(s.b, picked.round_id, "x".repeat(41)))).code).toBe("23514");
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the guesser can guess while the drawer is still drawing, and the drawing is sent afterwards", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "medium");
    await s.b.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id });
    tick(8);
    const solved = await guess(s.b, picked.round_id, picked.word);
    expect(solved).toMatchObject({ correct: true, round_state: "solved", speed_bonus: 2, solve_ms: 8000 });

    // The round is over before any drawing exists, and the guesser already draws next.
    let data = await view(s.a);
    expect(data.current_round).toMatchObject({ state: "solved", drawing_media_asset_id: null });
    expect(data.game).toMatchObject({ state: "choosing_word", turn_user_id: s.b.userId });
    expect(await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect())).toHaveLength(0);

    // The drawer's phone sends the drawing as it was at that moment.
    const sent = await sendDrawing(s, s.a, picked.round_id);
    expect(sent.round_state).toBe("solved");
    data = await view(s.b);
    expect(data.current_round).toMatchObject({ state: "solved" });
    expect(data.current_round?.drawing_media_asset_id).toBeTruthy();
    // The turn did not move back, and no turn push went out for it.
    expect(data.game).toMatchObject({ state: "choosing_word", turn_user_id: s.b.userId, turn_number: 2 });
    expect((await outbox(s.t)).filter((row) => row.kind === "game_turn_ready")).toHaveLength(0);
    const events = await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events).toMatchObject([{ activity_kind: "game_turn_completed", user_id: s.a.userId, dedupe_key: `game_turn_completed:${picked.round_id}` }]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a retried guess is stored once", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const args = { ...op(), p_round_id: picked.round_id, p_guess: "nope" };
    const first = await s.b.as.mutation(api.drawAndGuess.submit_guess, args);
    expect(await s.b.as.mutation(api.drawAndGuess.submit_guess, args)).toEqual(first);
    expect(await s.t.run((ctx) => ctx.db.query("game_guesses").collect())).toHaveLength(1);
  });
});

describe("give_up_round", () => {
  test("counts as missed, scores nothing, and the guesser draws next", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "hard");
    await sendDrawing(s, s.a, picked.round_id);
    expect((await failure(s.a.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: picked.round_id }))).code).toBe("42501");
    const result = await s.b.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: picked.round_id });
    expect(result).toEqual({ round_id: picked.round_id, round_state: "missed" });
    const data = await view(s.a);
    expect(data.current_round).toMatchObject({ state: "missed", word: picked.word });
    expect(data.game).toMatchObject({ state: "choosing_word", turn_user_id: s.b.userId, shared_points: 0, my_points: 0, partner_points: 0 });
    expect((await failure(s.b.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: picked.round_id }))).message).toMatch(/already finished/);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("scoring", () => {
  test("every solve adds the word points to the shared total and to each personal total, in either play style", async () => {
    for (const playStyle of ["together", "against"] as const) {
      const s = await startGame({ playStyle });
      // a draws an easy word, b guesses 10 seconds after seeing it on the first try: b gets 1 + 2 + 1, a gets 1.
      await playRound(s, s.a, s.b, "easy", 10);
      let data = await view(s.a);
      expect(data.game).toMatchObject({ shared_points: 1, my_points: 1, partner_points: 4 });
      // b draws a hard word, a guesses 40 seconds after seeing it on the first try: a gets 3 + 0 + 1, b gets 3.
      await playRound(s, s.b, s.a, "hard", 40);
      data = await view(s.a);
      expect(data.game).toMatchObject({ shared_points: 4, my_points: 5, partner_points: 7 });
      data = await view(s.b);
      expect(data.game).toMatchObject({ shared_points: 4, my_points: 7, partner_points: 5 });
      expect(data.settings?.play_style).toBe(playStyle);
      // A missed round changes nothing.
      const third = await pick(s.a, s.gameId, "hard");
      await sendDrawing(s, s.a, third.round_id);
      await s.b.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: third.round_id });
      expect((await view(s.a)).game).toMatchObject({ shared_points: 4, my_points: 5, partner_points: 7 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    }
  });

  test("a live watcher's speed bonus window starts when they first see the drawing, not when it is sent", async () => {
    const s = await startGame({ playStyle: "against" });
    const picked = await pick(s.a, s.gameId, "easy");
    await s.b.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id });
    tick(60);
    await sendDrawing(s, s.a, picked.round_id);
    tick(10);
    const solved = await guess(s.b, picked.round_id, picked.word);
    expect(solved).toMatchObject({ correct: true, speed_bonus: 0, solve_ms: 70_000 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the speed bonus is 2 within 15 seconds, 1 within 30, and 0 after that", async () => {
    const s = await startGame({ playStyle: "against" });
    const bonus = async (seconds: number | null) => {
      const { result } = await playRound(s, s.a, s.b, "easy", seconds);
      // The roles swap after each solve, so give the turn back to a with a quick missed round of b.
      const back = await pick(s.b, s.gameId, "easy");
      await sendDrawing(s, s.b, back.round_id);
      await s.a.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: back.round_id });
      return result;
    };
    expect(await bonus(15)).toMatchObject({ points: 1, speed_bonus: 2, first_try_bonus: 1, solve_ms: 15_000 });
    expect(await bonus(16)).toMatchObject({ points: 1, speed_bonus: 1, first_try_bonus: 1, solve_ms: 16_000 });
    expect(await bonus(30)).toMatchObject({ points: 1, speed_bonus: 1, solve_ms: 30_000 });
    expect(await bonus(31)).toMatchObject({ points: 1, speed_bonus: 0, solve_ms: 31_000 });
    expect(await bonus(null)).toMatchObject({ points: 1, speed_bonus: 0, solve_ms: null });
    const data = await view(s.b);
    // b scored 4, 3, 3, 2, 2 (word, speed, first try). a scored 1 for each of the five, as the drawer.
    expect(data.game).toMatchObject({ shared_points: 5, my_points: 14, partner_points: 5 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  describe("the phone's speed bonus claim", () => {
    const claimed = (user: TestUser, roundId: string, text: string, claim: { p_speed_bonus?: number | null; p_solve_ms?: number | null }) =>
      user.as.mutation(api.drawAndGuess.submit_guess, { ...op(), p_round_id: roundId, p_guess: text, ...claim });

    test("a claim gives the bonus tier on screen even when the server clock alone says no", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await sendDrawing(s, s.a, picked.round_id);
      // The guess waited in the offline queue, and mark_round_seen never arrived.
      tick(300);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: 2, p_solve_ms: 12_000 });
      expect(solved).toMatchObject({ correct: true, points: 1, speed_bonus: 2, solve_ms: 12_000 });
      expect((await view(s.b)).game).toMatchObject({ shared_points: 1, my_points: 4, partner_points: 1 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("a claim of 0 gives no bonus even when the server clock alone says yes", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await s.b.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id });
      tick(5);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: 0, p_solve_ms: 45_000 });
      expect(solved).toMatchObject({ correct: true, speed_bonus: 0, solve_ms: 45_000 });
      expect((await view(s.b)).game).toMatchObject({ my_points: 2 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("without a claim the server decides, and null counts as absent", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await s.b.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id });
      tick(8);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: null, p_solve_ms: null });
      expect(solved).toMatchObject({ speed_bonus: 2, solve_ms: 8000 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("a claim of the solve time alone keeps the server's bonus", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await sendDrawing(s, s.a, picked.round_id);
      tick(300);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_solve_ms: 9_000 });
      expect(solved).toMatchObject({ speed_bonus: 0, solve_ms: 9_000 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("a claim that is not a time is refused", async () => {
      const s = await startGame();
      const picked = await pick(s.a, s.gameId, "easy");
      for (const p_solve_ms of [-1, Number.NaN, Number.POSITIVE_INFINITY]) {
        expect((await failure(claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: 1, p_solve_ms }))).code).toBe("23514");
      }
    });

    test("a speed bonus claim outside 0, 1 and 2 is refused", async () => {
      const s = await startGame();
      const picked = await pick(s.a, s.gameId, "easy");
      for (const p_speed_bonus of [3, -1, 1.5, Number.NaN]) {
        expect((await failure(claimed(s.b, picked.round_id, picked.word, { p_speed_bonus }))).code).toBe("23514");
      }
      expect(await s.t.run((ctx) => ctx.db.query("game_guesses").collect())).toHaveLength(0);
    });

    test("a guess after more than 30 days still solves the round, with the solve time capped", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await sendDrawing(s, s.a, picked.round_id);
      await s.b.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id });
      tick(31 * 24 * 3600);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: 0, p_solve_ms: 31 * 24 * 3600 * 1000 });
      expect(solved).toMatchObject({ correct: true, round_state: "solved", speed_bonus: 0, solve_ms: 30 * 24 * 3600 * 1000 });
      expect((await view(s.b)).game).toMatchObject({ state: "choosing_word", turn_user_id: s.b.userId, shared_points: 1 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("a replay with the same claim returns the stored result and a different claim is a hash mismatch", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await sendDrawing(s, s.a, picked.round_id);
      const args = { ...op(), p_round_id: picked.round_id, p_guess: picked.word, p_speed_bonus: 2, p_solve_ms: 4000 };
      const first = await s.b.as.mutation(api.drawAndGuess.submit_guess, args);
      expect(await s.b.as.mutation(api.drawAndGuess.submit_guess, args)).toEqual(first);
      const changed = { ...args, p_speed_bonus: 1 };
      expect((await failure(s.b.as.mutation(api.drawAndGuess.submit_guess, changed))).message).toContain("replay hash mismatch");
      const slower = { ...args, p_solve_ms: 5000 };
      expect((await failure(s.b.as.mutation(api.drawAndGuess.submit_guess, slower))).message).toContain("replay hash mismatch");
      const hinted = { ...args, p_hints_used: 1 };
      expect((await failure(s.b.as.mutation(api.drawAndGuess.submit_guess, hinted))).message).toContain("replay hash mismatch");
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });
  });

  test("mark_round_seen keeps the first time and only works for the guesser", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    expect((await failure(s.a.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id }))).code).toBe("42501");
    const first = await s.b.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id });
    tick(20);
    expect(await s.b.as.mutation(api.drawAndGuess.mark_round_seen, { p_round_id: picked.round_id })).toEqual(first);
    expect((await view(s.a)).current_round?.guesser_first_seen_at).toBe(first.guesser_first_seen_at);
  });
});

describe("pushes", () => {
  test("a drawing queues a lock-screen-safe turn push with the deep link", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "custom", "secret surprise");
    await sendDrawing(s, s.a, picked.round_id);
    const rows = (await outbox(s.t)).filter((row) => row.kind === "game_turn_ready");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      apns_push_type: "alert",
      title: "Your turn in Draw & Guess",
      body: "Guess what they drew.",
      payload: {
        type: "game_turn_ready",
        game_kind: "draw_and_guess",
        couple_id: s.couple.coupleId,
        game_id: s.gameId,
        round_id: picked.round_id,
        actor_user_id: s.a.userId,
        route: "games",
        deeplink: "paeonia://games/draw-and-guess",
      },
    });
    expect(JSON.stringify(rows[0])).not.toContain("secret");
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a correct guess tells the drawer, and the push never names the word", async () => {
    const s = await startGame();
    // A custom word, because a short random word such as "key" also appears in field names.
    const picked = await pick(s.a, s.gameId, "custom", "pineapple");
    await sendDrawing(s, s.a, picked.round_id);
    await guess(s.b, picked.round_id, picked.word);
    const rows = (await outbox(s.t)).filter((row) => row.kind === "game_result");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.a.userId,
      title: "Second Partner guessed your drawing",
      payload: { type: "game_result", round_id: picked.round_id, deeplink: "paeonia://games/draw-and-guess" },
    });
    expect(JSON.stringify(rows[0])).not.toContain(picked.word);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("pushes are in the recipient's language", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "nb-NO" });
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    const { game_id } = await couple.first.as.mutation(api.drawAndGuess.ensure_draw_and_guess_game, {});
    const s: Setup = { t, couple, a: couple.first, b: couple.second, gameId: game_id };
    const picked = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, picked.round_id);
    const [row] = await outbox(t);
    expect(row).toMatchObject({ title: "Din tur i Tegn og gjett", body: "Gjett hva som er tegnet." });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an open game screen on the recipient's phone suppresses the turn and guessed pushes", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    const picked = await pick(s.a, s.gameId, "easy");
    tick(30);
    await sendDrawing(s, s.a, picked.round_id);
    expect(await outbox(s.t)).toHaveLength(0);

    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    await guess(s.b, picked.round_id, picked.word);
    expect(await outbox(s.t)).toHaveLength(0);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a screen that stopped its heartbeats does not suppress the push, and closing the screen removes it", async () => {
    const s = await startGame();
    // The presence component times sessions out with scheduled functions, so fake every timer.
    vi.useFakeTimers();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    const picked = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, picked.round_id);
    expect((await outbox(s.t)).filter((row) => row.kind === "game_turn_ready")).toHaveLength(1);

    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: false });
    await guess(s.b, picked.round_id, picked.word);
    expect((await outbox(s.t)).filter((row) => row.kind === "game_result")).toHaveLength(1);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the Games switch turns every game push off", async () => {
    const s = await startGame();
    const row = await s.b.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    expect(row.games_enabled).toBe(false);
    const picked = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, picked.round_id);
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" });
    expect(await outbox(s.t)).toHaveLength(0);
    // New accounts start with the switch on.
    expect((await s.a.as.query(api.identity.get_notification_preferences, {})).games_enabled).toBe(true);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("push drain", () => {
  const claim = (s: Setup) => deliverDuePushes(s.t);
  const kinds = (rows: { payload: unknown }[]) => rows.map((row) => (row.payload as { type: string }).type).sort();
  const errorsOf = async (s: Setup, kind: string) =>
    (await outbox(s.t)).filter((row) => row.kind === kind).map((row) => row.last_error ?? null);

  test("drops a turn push or reminder once the turn moved on, and keeps current ones", async () => {
    const s = await startGame();
    // b gives up before the drain runs, so the turn push for that round is out of date.
    const first = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, first.round_id);
    await s.b.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: first.round_id });
    expect(await claim(s)).toEqual([]);
    expect(await errorsOf(s, "game_turn_ready")).toEqual(["notification is out of date"]);

    // A turn push that still waits for its guesser goes out.
    const second = await pick(s.b, s.gameId, "easy");
    await sendDrawing(s, s.b, second.round_id);
    expect(kinds(await claim(s))).toEqual(["game_turn_ready"]);

    // The reminder is out of date once a guesses, and the guessed push still goes to b.
    tick(73 * 3600);
    expect(await s.t.mutation(internal.gameHooks.send_due_game_turn_reminders, {})).toBe(1);
    await guess(s.a, second.round_id, second.word);
    expect(kinds(await claim(s))).toEqual(["game_result"]);
    expect(await errorsOf(s, "game_turn_reminder")).toEqual(["notification is out of date"]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("drops every couple push queued before the relationship ended", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "custom", "flying cat");
    await sendDrawing(s, s.a, picked.round_id);
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" });
    await guess(s.b, picked.round_id, "flying cat");
    expect(kinds((await outbox(s.t)).filter((row) => row.sent_at === undefined))).toEqual(
      ["game_invite", "game_result", "game_turn_ready"],
    );
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect(await claim(s)).toEqual([]);
    for (const row of await outbox(s.t)) {
      expect(row).toMatchObject({ last_error: "notification target is no longer eligible" });
      expect(row.failed_at).toBeDefined();
    }
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("invites", () => {
  test("push the partner, then allow the next invite after 15 minutes", async () => {
    const s = await startGame();
    const sent = await s.a.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" });
    expect(sent.sent_at).toBe(new Date(START).toISOString());
    const rows = await outbox(s.t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      title: "First Partner wants to play Draw & Guess with you",
      payload: { type: "game_invite", deeplink: "paeonia://games/draw-and-guess" },
    });
    expect((await view(s.a)).last_invite_at).toBe(sent.sent_at);
    expect((await view(s.b)).last_invite_at).toBeNull();

    tick(14 * 60 + 59);
    expect((await failure(s.a.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" }))).code).toBe("53300");
    // The limit is per sender.
    await s.b.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" });
    tick(1);
    const again = await s.a.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" });
    expect(again.sent_at > sent.sent_at).toBe(true);
    expect((await outbox(s.t)).filter((row) => row.recipient_user_id === s.b.userId)).toHaveLength(2);
    expect(await s.t.run((ctx) => ctx.db.query("game_invites").collect())).toHaveLength(2);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("presence", () => {
  test("the query says who has the screen open, until 60 seconds after the last heartbeat", async () => {
    const s = await startGame();
    // The presence component times sessions out with scheduled functions, so fake every timer.
    vi.useFakeTimers();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    expect(await view(s.a)).toMatchObject({ my_present: false, partner_present: true });
    expect(await view(s.b)).toMatchObject({ my_present: true, partner_present: false });

    const lastHeartbeat = Date.now();
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    expect(Date.now() - lastHeartbeat).toBeGreaterThanOrEqual(60_000);
    expect(await view(s.a)).toMatchObject({ my_present: false, partner_present: false });
  });
});

describe("turn reminder", () => {
  test("goes out once after 72 hours to the partner whose turn it is, and again only for a new move", async () => {
    const s = await startGame();
    const run = () => s.t.mutation(internal.gameHooks.send_due_game_turn_reminders, {});
    const reminders = async () => (await outbox(s.t)).filter((row) => row.kind === "game_turn_reminder");

    tick(71 * 3600);
    expect(await run()).toBe(0);
    tick(3600);
    expect(await run()).toBe(1);
    expect(await run()).toBe(0);
    tick(10 * 3600);
    expect(await run()).toBe(0);
    let rows = await reminders();
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.a.userId,
      title: "Your turn in Draw & Guess",
      payload: { type: "game_turn_reminder", actor_user_id: s.b.userId, deeplink: "paeonia://games/draw-and-guess" },
    });

    // a finally draws. The turn moves to b, and b's wait starts now.
    const picked = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, picked.round_id);
    tick(73 * 3600);
    expect(await run()).toBe(1);
    expect(await run()).toBe(0);
    rows = await reminders();
    expect(rows.map((row) => row.recipient_user_id)).toEqual([s.a.userId, s.b.userId]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("respects the Games switch and a couple that is no longer active", async () => {
    const s = await startGame();
    await s.a.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    tick(80 * 3600);
    expect(await s.t.mutation(internal.gameHooks.send_due_game_turn_reminders, {})).toBe(0);
    expect(await outbox(s.t)).toHaveLength(0);

    const other = await startGame();
    await endCouple(other.t, other.couple.coupleId, other.a.userId);
    expect(await other.t.mutation(internal.gameHooks.send_due_game_turn_reminders, {})).toBe(0);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

const guessWith = (user: TestUser, roundId: string, text: string, extra: Record<string, number | null> = {}) =>
  user.as.mutation(api.drawAndGuess.submit_guess, { ...op(), p_round_id: roundId, p_guess: text, ...extra });

/** `drawer` picks a word and sends the drawing, then `guesser` solves it on the first try. */
async function finishedRound(s: Setup, drawer: TestUser, guesser: TestUser, extra: Record<string, number | null> = {}) {
  const picked = await pick(drawer, s.gameId, "easy");
  await sendDrawing(s, drawer, picked.round_id);
  const result = await guessWith(guesser, picked.round_id, picked.word, extra);
  return { picked, result };
}

describe("first-try and hint bonuses", () => {
  test("a correct first attempt earns the first-try bonus, and an earlier wrong one removes it", async () => {
    const s = await startGame({ playStyle: "against" });
    const first = await finishedRound(s, s.a, s.b);
    expect(first.result).toMatchObject({ points: 1, speed_bonus: 0, first_try_bonus: 1, hints_used: 0, personal_best: false });

    const second = await pick(s.b, s.gameId, "easy");
    await sendDrawing(s, s.b, second.round_id);
    await guess(s.a, second.round_id, "nope");
    expect(await guess(s.a, second.round_id, second.word)).toMatchObject({ first_try_bonus: 0, hints_used: 0 });

    const data = await view(s.a);
    expect(data.current_round).toMatchObject({ first_try_bonus: 0, hints_used: 0, attempt_count: 2 });
    expect(data.recent_rounds[0]).toMatchObject({ first_try_bonus: 1, hints_used: 0 });
    // a drew round 1 (1) and guessed round 2 (1). b guessed round 1 (1 + 1) and drew round 2 (1).
    expect(data.game).toMatchObject({ shared_points: 2, my_points: 2, partner_points: 3 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("any hint zeroes the speed bonus and the first-try bonus, and the count is stored", async () => {
    const s = await startGame({ playStyle: "against" });
    const picked = await pick(s.a, s.gameId, "custom", "hot dog");
    await sendDrawing(s, s.a, picked.round_id);
    const result = await guessWith(s.b, picked.round_id, "hot dog", { p_speed_bonus: 2, p_solve_ms: 5000, p_hints_used: 2 });
    expect(result).toMatchObject({ points: 2, speed_bonus: 0, first_try_bonus: 0, hints_used: 2, personal_best: false, solve_ms: 5000 });
    const data = await view(s.a);
    expect(data.current_round).toMatchObject({ speed_bonus: 0, first_try_bonus: 0, hints_used: 2 });
    expect(data.game).toMatchObject({ shared_points: 2, my_points: 2, partner_points: 2 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a wrong guess ignores the hint count", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "custom", "hot dog");
    const wrong = await guessWith(s.b, picked.round_id, "cold dog", { p_hints_used: 99 });
    expect(wrong).toMatchObject({ correct: false, hints_used: 0, first_try_bonus: 0 });
    expect(await guessWith(s.b, picked.round_id, "hot dog", { p_hints_used: 1 })).toMatchObject({ hints_used: 1 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("hints are limited to the letters of the word minus one, and spaces do not count", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "custom", "hot dog");
    for (const p_hints_used of [6, -1, 1.5, Number.NaN]) {
      expect((await failure(guessWith(s.b, picked.round_id, "hot dog", { p_hints_used }))).code).toBe("23514");
    }
    expect(await s.t.run((ctx) => ctx.db.query("game_guesses").collect())).toHaveLength(0);
    expect(await guessWith(s.b, picked.round_id, "hot dog", { p_hints_used: 5 })).toMatchObject({ correct: true, hints_used: 5 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("personal best", () => {
  test("a hint-free solve beats every earlier hint-free solve by the same guesser, and needs one earlier solve", async () => {
    const s = await startGame({ playStyle: "against" });
    // b guesses a's drawing, then draws one back that a gives up on, so b guesses again.
    const bSolves = async (solveMs: number, hints = 0) => {
      const { result } = await finishedRound(s, s.a, s.b, { p_speed_bonus: 0, p_solve_ms: solveMs, ...(hints ? { p_hints_used: hints } : {}) });
      const back = await pick(s.b, s.gameId, "easy");
      await sendDrawing(s, s.b, back.round_id);
      await s.a.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: back.round_id });
      return result;
    };
    expect((await bSolves(20_000)).personal_best).toBe(false);
    const faster = await bSolves(10_000);
    expect(faster.personal_best).toBe(true);
    expect((await bSolves(15_000)).personal_best).toBe(false);
    // A solve with a hint is never a personal best, and it does not count against later ones.
    expect((await bSolves(1_000, 1)).personal_best).toBe(false);
    expect((await bSolves(9_000)).personal_best).toBe(true);
    expect((await bSolves(9_000)).personal_best).toBe(false);

    const data = await view(s.a);
    const stored = await s.t.run((ctx) => ctx.db.query("game_moves").collect());
    expect(stored.filter((move) => move.personal_best === true)).toHaveLength(2);
    expect(data.recent_rounds.filter((round) => round.personal_best)).toHaveLength(2);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a solve without a solve time is never a personal best", async () => {
    const s = await startGame();
    const first = await finishedRound(s, s.a, s.b, { p_solve_ms: 5000 });
    expect(first.result.personal_best).toBe(false);
    const back = await pick(s.b, s.gameId, "easy");
    await s.a.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: back.round_id });
    const second = await finishedRound(s, s.a, s.b);
    expect(second.result).toMatchObject({ solve_ms: null, personal_best: false });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("result seen", () => {
  const seen = (user: TestUser, roundId: string) => user.as.mutation(api.drawAndGuess.mark_round_result_seen, { p_round_id: roundId });

  test("each partner's field is set once, keeps the first time, and the other field stays empty", async () => {
    const s = await startGame();
    const { picked } = await finishedRound(s, s.a, s.b);
    expect((await view(s.a)).current_round).toMatchObject({ drawer_result_seen_at: null, guesser_result_seen_at: null });

    const first = await seen(s.b, picked.round_id);
    expect(first.round_id).toBe(picked.round_id);
    tick(60);
    expect(await seen(s.b, picked.round_id)).toEqual(first);
    expect((await view(s.a)).current_round).toMatchObject({ drawer_result_seen_at: null, guesser_result_seen_at: first.result_seen_at });

    const drawer = await seen(s.a, picked.round_id);
    expect(drawer.result_seen_at > first.result_seen_at).toBe(true);
    expect((await view(s.b)).current_round).toMatchObject({ drawer_result_seen_at: drawer.result_seen_at, guesser_result_seen_at: first.result_seen_at });
    expect((await view(s.a)).current_round?.id).toBe(picked.round_id);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a round that is still open cannot be marked, and a missed round can", async () => {
    const s = await startGame();
    const open = await pick(s.a, s.gameId, "easy");
    expect((await failure(seen(s.a, open.round_id))).message).toMatch(/not finished/);
    expect((await failure(seen(s.b, open.round_id))).message).toMatch(/not finished/);
    await s.b.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: open.round_id });
    expect((await seen(s.b, open.round_id)).result_seen_at).toEqual(expect.any(String));
  });
});

describe("history", () => {
  const history = (user: TestUser, args: { starredOnly?: boolean; before?: number | null; limit?: number } = {}) =>
    user.as.query(api.drawAndGuess.get_draw_and_guess_history, {
      p_starred_only: args.starredOnly ?? false,
      p_before_round_number: args.before ?? null,
      p_limit: args.limit ?? 50,
    });
  const numbers = (page: { rounds: { round_number: number }[] }) => page.rounds.map((round) => round.round_number);

  /**
   * Seven rounds, alternating drawers. Round 3 is missed. Round 5 is solved live and its drawing never
   * arrives. Round 7 is still open. Returns the round ids by number.
   */
  async function playHistory(s: Setup) {
    const ids: Record<number, { id: string; word: string; drawer: TestUser }> = {};
    let drawer = s.a;
    let guesser = s.b;
    for (let number = 1; number <= 7; number += 1) {
      const picked = await pick(drawer, s.gameId, "easy");
      ids[number] = { id: picked.round_id, word: picked.word, drawer };
      if (number === 5) {
        await guess(guesser, picked.round_id, picked.word);
      } else {
        await sendDrawing(s, drawer, picked.round_id);
        if (number === 3) await guesser.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: picked.round_id });
        else if (number !== 7) await guess(guesser, picked.round_id, picked.word);
      }
      if (number !== 7) [drawer, guesser] = [guesser, drawer];
    }
    return ids;
  }

  test("lists finished rounds that hold a drawing, newest first, in pages", async () => {
    const s = await startGame();
    const ids = await playHistory(s);
    const all = await history(s.a);
    expect(numbers(all)).toEqual([6, 4, 3, 2, 1]);
    expect(all.next_before_round_number).toBeNull();
    expect(all.rounds.map((round) => round.state)).toEqual(["solved", "solved", "missed", "solved", "solved"]);

    const first = await history(s.a, { limit: 2 });
    expect(numbers(first)).toEqual([6, 4]);
    expect(first.next_before_round_number).toBe(4);
    const second = await history(s.a, { limit: 2, before: first.next_before_round_number });
    expect(numbers(second)).toEqual([3, 2]);
    expect(second.next_before_round_number).toBe(2);
    const third = await history(s.a, { limit: 2, before: second.next_before_round_number });
    expect(numbers(third)).toEqual([1]);
    expect(third.next_before_round_number).toBeNull();
    // The cursor is exclusive, and a page that ends exactly at the last round has no next page.
    expect(numbers(await history(s.a, { limit: 5 }))).toEqual([6, 4, 3, 2, 1]);
    expect((await history(s.a, { limit: 5 })).next_before_round_number).toBeNull();
    expect(numbers(await history(s.a, { before: 1 }))).toEqual([]);

    const item = all.rounds[4];
    expect(Object.keys(item).sort()).toEqual(
      [
        "id", "round_number", "drawer_user_id", "guesser_user_id", "word", "difficulty", "points", "state", "drawing_media_asset_id",
        "solve_ms", "speed_bonus", "first_try_bonus", "hints_used", "attempt_count", "personal_best",
        "started_at", "ended_at",
      ].sort(),
    );
    expect(item).toMatchObject({
      id: ids[1].id,
      drawer_user_id: s.a.userId,
      guesser_user_id: s.b.userId,
      word: ids[1].word,
      difficulty: "easy",
      points: 1,
      first_try_bonus: 1,
      hints_used: 0,
      attempt_count: 1,
      personal_best: false,
    });
    expect(item.drawing_media_asset_id).toEqual(expect.any(String));
    // The same history for both partners.
    expect(numbers(await history(s.b))).toEqual([6, 4, 3, 2, 1]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("starred only returns the caller's favorites", async () => {
    const s = await startGame();
    const ids = await playHistory(s);
    for (const number of [1, 2, 4, 5]) await favoriteRound(s.a, ids[number].id);
    await favoriteRound(s.b, ids[4].id);
    await favoriteRound(s.b, ids[3].id);

    // Round 5 has no drawing, so its star stays out of the history.
    expect(numbers(await history(s.a, { starredOnly: true }))).toEqual([4, 2, 1]);
    const page = await history(s.a, { starredOnly: true, limit: 2 });
    expect(numbers(page)).toEqual([4, 2]);
    expect(page.next_before_round_number).toBe(2);
    const rest = await history(s.a, { starredOnly: true, limit: 2, before: page.next_before_round_number });
    expect(numbers(rest)).toEqual([1]);
    expect(rest.next_before_round_number).toBeNull();
    expect(numbers(await history(s.b, { starredOnly: true }))).toEqual([4, 3]);

    await favoriteRound(s.a, ids[4].id, false);
    expect(numbers(await history(s.a, { starredOnly: true }))).toEqual([2, 1]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("shows the hints and personal best stored on the round", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "custom", "hot dog");
    await sendDrawing(s, s.a, picked.round_id);
    await guessWith(s.b, picked.round_id, "hot dog", { p_hints_used: 3, p_solve_ms: 40_000 });
    const [item] = (await history(s.a)).rounds;
    expect(item).toMatchObject({ hints_used: 3, solve_ms: 40_000, speed_bonus: 0, first_try_bonus: 0, personal_best: false });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("both partners can still download the drawing of an old round", async () => {
    const s = await startGame();
    await playHistory(s);
    const oldest = (await history(s.a)).rounds.at(-1)!;
    for (const user of [s.a, s.b]) {
      const [row] = await user.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: oldest.drawing_media_asset_id, p_expires_in_seconds: 300 });
      expect(row.bucket).toBe("game-drawings");
    }
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a page holds at most 50 rounds and the limit must be positive", async () => {
    const s = await startGame();
    await s.t.run(async (ctx) => {
      for (let number = 1; number <= 60; number += 1) {
        const now = new Date().toISOString();
        await ctx.db.insert("game_moves", {
          id: newUuid(),
          game_id: s.gameId,
          couple_id: s.couple.coupleId,
          round_number: number,
          drawer_user_id: s.a.userId,
          guesser_user_id: s.b.userId,
          state: "solved",
          difficulty: "easy",
          word: "cat",
          points: 1,
          drawing_media_asset_id: newUuid(),
          started_at: now,
          ended_at: now,
          speed_bonus: 0,
          created_at: now,
          updated_at: now,
        });
      }
    });
    const page = await history(s.a, { limit: 1000 });
    expect(page.rounds).toHaveLength(50);
    expect(page.rounds[0].round_number).toBe(60);
    expect(page.next_before_round_number).toBe(11);
    expect(numbers(await history(s.a, { limit: 1000, before: 11 }))).toHaveLength(10);
    expect((await failure(history(s.a, { limit: 0 }))).code).toBe("23514");
  });

  test("another couple sees none of it, and a user without a couple is refused", async () => {
    const s = await startGame();
    await playHistory(s);
    const other = await startGame();
    expect(await history(other.a)).toEqual({ rounds: [], next_before_round_number: null });
    expect(await history(other.a, { starredOnly: true })).toEqual({ rounds: [], next_before_round_number: null });
    const loner = await createSignedInUser(s.t, { name: "Loner" });
    expect((await failure(history(loner))).code).toBe("42501");
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("one finished round can be read by id, and nobody outside the couple can read it", async () => {
    const s = await startGame();
    const ids = await playHistory(s);
    const byId = (user: TestUser, id: string) => user.as.query(api.drawAndGuess.get_draw_and_guess_history_round, { p_round_id: id });
    const listed = (await history(s.a)).rounds.find((round) => round.id === ids[1].id);
    expect(await byId(s.a, ids[1].id)).toEqual(listed);
    expect(await byId(s.b, ids[1].id)).toEqual(listed);
    // A round that is open, never got its drawing, or does not exist is not a history round.
    expect(await byId(s.a, ids[7].id)).toBeNull();
    expect(await byId(s.a, ids[5].id)).toBeNull();
    expect(await byId(s.a, newUuid())).toBeNull();
    const other = await startGame();
    expect(await byId(other.a, ids[1].id)).toBeNull();
    const loner = await createSignedInUser(s.t, { name: "Loner" });
    expect((await failure(byId(loner, ids[1].id))).code).toBe("42501");
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("records", () => {
  test("counts solves, first tries, solve times, and solved drawings for each partner", async () => {
    const s = await startGame();
    // Round 1: a draws, b solves on the first try in 20 seconds.
    const r1 = await finishedRound(s, s.a, s.b, { p_solve_ms: 20_000 });
    // Round 2: b draws, a tries twice and solves in 30 seconds.
    const r2 = await pick(s.b, s.gameId, "easy");
    await sendDrawing(s, s.b, r2.round_id);
    await guess(s.a, r2.round_id, "nope");
    await guessWith(s.a, r2.round_id, r2.word, { p_solve_ms: 30_000 });
    // Round 3: a draws, b solves with a hint in 1 second. Hints keep it out of the times and the first tries.
    await finishedRound(s, s.a, s.b, { p_solve_ms: 1000, p_hints_used: 1 });
    // Round 4: b draws, a solves on the first try in 11 minutes. It stays out of the average only.
    await finishedRound(s, s.b, s.a, { p_solve_ms: 11 * 60_000 });
    // Round 5: a draws, b gives up.
    const r5 = await pick(s.a, s.gameId, "easy");
    await s.b.as.mutation(api.drawAndGuess.give_up_round, { ...op(), p_round_id: r5.round_id });
    // Round 6 is open.
    await pick(s.b, s.gameId, "easy");

    const records = await s.a.as.query(api.drawAndGuess.get_draw_and_guess_records, {});
    expect(records.partners.map((partner) => partner.user_id)).toEqual([s.a.userId, s.b.userId]);
    expect(records.partners[0]).toEqual({
      user_id: s.a.userId,
      solves: 2,
      first_try_solves: 1,
      average_solve_ms: 30_000,
      fastest_solve_ms: 30_000,
      fastest_solve_word: r2.word,
      drawings_solved: 2,
    });
    expect(records.partners[1]).toEqual({
      user_id: s.b.userId,
      solves: 2,
      first_try_solves: 1,
      average_solve_ms: 20_000,
      fastest_solve_ms: 20_000,
      fastest_solve_word: r1.picked.word,
      drawings_solved: 2,
    });
    expect((await s.b.as.query(api.drawAndGuess.get_draw_and_guess_records, {})).partners.map((partner) => partner.user_id)).toEqual([s.b.userId, s.a.userId]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a couple with no solved rounds has zeros and nulls, and a stranger is refused", async () => {
    const s = await startGame();
    const empty = { solves: 0, first_try_solves: 0, average_solve_ms: null, fastest_solve_ms: null, fastest_solve_word: null, drawings_solved: 0 };
    expect((await s.a.as.query(api.drawAndGuess.get_draw_and_guess_records, {})).partners).toMatchObject([empty, empty]);
    const loner = await createSignedInUser(s.t, { name: "Loner" });
    expect((await failure(loner.as.query(api.drawAndGuess.get_draw_and_guess_records, {}))).code).toBe("42501");
  });
});

describe("recent rounds", () => {
  test("lists earlier rounds newest first, at most 20, with attempts for the newest two rounds", async () => {
    const s = await startGame();
    let drawer = s.a;
    let guesser = s.b;
    for (let index = 0; index < 22; index += 1) {
      const picked = await pick(drawer, s.gameId, "easy");
      await sendDrawing(s, drawer, picked.round_id);
      await guess(guesser, picked.round_id, "wrong");
      await guess(guesser, picked.round_id, picked.word);
      [drawer, guesser] = [guesser, drawer];
    }
    const data = await view(s.a);
    expect(data.current_round?.round_number).toBe(22);
    expect(data.recent_rounds).toHaveLength(20);
    expect(data.recent_rounds[0].round_number).toBe(21);
    expect(data.recent_rounds[0].attempts.map((attempt) => attempt.text)).toEqual(["wrong", data.recent_rounds[0].word]);
    // Older rounds keep the exact count and send no attempts.
    expect(data.recent_rounds[1]).toMatchObject({ attempts: [], attempt_count: 2 });
    expect(data.recent_rounds[19]).toMatchObject({ attempts: [], attempt_count: 2 });
    expect(data.game?.turn_number).toBe(23);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("get_draw_and_guess_round finds a round past the recent list, for the couple only", async () => {
    const s = await startGame();
    const first = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, first.round_id);
    await guess(s.b, first.round_id, first.word);
    let drawer = s.b;
    let guesser = s.a;
    for (let index = 0; index < 21; index += 1) {
      const picked = await pick(drawer, s.gameId, "easy");
      await sendDrawing(s, drawer, picked.round_id);
      await guess(guesser, picked.round_id, picked.word);
      [drawer, guesser] = [guesser, drawer];
    }
    const listed = await view(s.b);
    expect([listed.current_round, ...listed.recent_rounds].map((round) => round?.id)).not.toContain(first.round_id);

    const byId = (user: TestUser, roundId: string) => user.as.query(api.drawAndGuess.get_draw_and_guess_round, { p_round_id: roundId });
    const round = await byId(s.b, first.round_id.toUpperCase());
    expect(round).toMatchObject({ id: first.round_id, state: "solved", round_number: 1 });
    expect(round?.drawing_media_asset_id).toEqual(expect.any(String));
    expect(Object.keys(round ?? {}).sort()).toEqual(Object.keys(listed.recent_rounds[0]).sort());
    expect(await byId(s.b, newUuid())).toBeNull();

    const other = await createCouple(s.t);
    expect(await byId(other.first, first.round_id)).toBeNull();
    const loner = await createSignedInUser(s.t, { name: "Loner" });
    expect((await failure(byId(loner, first.round_id))).code).toBe("42501");
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect((await failure(byId(s.b, first.round_id))).code).toBe("42501");
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

test("a round with more than 200 attempts returns the newest ones and the exact count", async () => {
  const s = await startGame();
  const picked = await pick(s.a, s.gameId, "custom", "flying cat");
  for (let index = 0; index < 205; index += 1) {
    await guess(s.b, picked.round_id, `wrong ${String.fromCharCode(97 + (index % 26))}`);
    tick(1);
  }
  await guess(s.b, picked.round_id, "flying cat");
  const round = (await view(s.a)).current_round!;
  expect(round.attempt_count).toBe(206);
  expect(round.attempts).toHaveLength(200);
  // Oldest first, and the latest tries, including the correct one, are there.
  expect(round.attempts.at(-1)).toMatchObject({ text: "flying cat", correct: true });
  expect(round.attempts[0].created_at < round.attempts.at(-1)!.created_at).toBe(true);
  await s.t.finishAllScheduledFunctions(vi.runAllTimers);
});

describe("relationship end", () => {
  test("presence goes right away, and cleanup deletes every game row and queues the drawings", async () => {
    const s = await startGame();
    const first = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, first.round_id);
    await guess(s.b, first.round_id, first.word);
    await favoriteRound(s.a, first.round_id);
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    // A second couple's game must survive.
    const keep = await startGame();
    await keep.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });

    const tables = [
      "game_settings",
      "games",
      "game_moves",
      "game_guesses",
      "favorites",
      "game_used_words",
      "game_invites",
      "game_plays",
    ] as const;
    const count = (t: TestConvex, coupleId: string) =>
      t.run(async (ctx) => {
        const result: Record<string, number> = {};
        for (const table of tables) {
          result[table] = (await ctx.db.query(table).collect()).filter((row) => row.couple_id === coupleId).length;
        }
        return result;
      });
    const online = (coupleId: string) =>
      s.t.run((ctx) => ctx.runQuery(components.presence.public.listRoom, { roomId: gameRoom(coupleId, "draw_and_guess") }));
    expect(Object.values(await count(s.t, s.couple.coupleId)).every((rows) => rows > 0)).toBe(true);
    expect(await online(s.couple.coupleId)).toHaveLength(1);

    await s.a.as.mutation(api.relationship.leave_relationship, op());
    expect(await online(s.couple.coupleId)).toEqual([]);
    expect((await count(s.t, s.couple.coupleId)).game_moves).toBe(1);

    await s.t.mutation(internal.relationshipJobs.cleanup_expired_relationship_content, { p_now: "2027-01-01T00:00:00.000Z" });
    expect(Object.values(await count(s.t, s.couple.coupleId)).every((rows) => rows === 0)).toBe(true);

    const drawings = await s.t.run(async (ctx) =>
      (await ctx.db.query("media_assets").collect()).filter((asset) => asset.bucket === "game-drawings"),
    );
    expect(drawings).toHaveLength(1);
    expect(drawings[0]).toMatchObject({ storage_delete_status: "pending" });
    // The drawing is queued for deletion, then the storage job removes the blob.
    await s.t.mutation(internal.media.cleanup_media_storage, {});
    const after = await s.t.run(async (ctx) =>
      (await ctx.db.query("media_assets").collect()).filter((asset) => asset.bucket === "game-drawings"),
    );
    expect(after[0]).toMatchObject({ storage_delete_status: "deleted" });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a purge without an earlier cleanup still removes the game rows", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    await guess(s.b, picked.round_id, "wrong");
    await s.t.run(async (ctx) => {
      const { purgeCoupleContent } = await import("./lib/relationshipCleanup");
      const couple = (await ctx.db.query("couples").first())!;
      await purgeCoupleContent(ctx, couple);
    });
    expect(await s.t.run((ctx) => ctx.db.query("games").collect())).toHaveLength(0);
    expect(await s.t.run((ctx) => ctx.db.query("game_guesses").collect())).toHaveLength(0);
  });
});

test("a new subscription holder can play after the first partner's entitlement lapses", async () => {
  const s = await startGame();
  await s.t.run(async (ctx) => {
    for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
  });
  expect((await failure(s.b.as.query(api.drawAndGuess.get_draw_and_guess, {}))).code).toBe("42501");
  await grantLifetime(s.t, s.b.userId);
  expect((await view(s.b)).game?.id).toBe(s.gameId);
});

describe("review fixes", () => {
  test("a word choice the drawer never saw is refused after a language change", async () => {
    const s = await startGame();
    const seen = (await view(s.a)).choices!.find((item: { difficulty: string }) => item.difficulty === "easy")!;
    await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    const stale = await failure(
      s.a.as.mutation(api.drawAndGuess.pick_draw_word, {
        ...op(),
        p_game_id: s.gameId,
        p_round_id: newUuid(),
        p_choice: "easy",
        p_custom_word: null,
        p_word_id: seen.word_id,
      }),
    );
    expect(stale.message).toMatch(/out of date/);
    const picked = await pick(s.a, s.gameId, "easy");
    expect(picked.word).not.toBe(seen.word);
  });

  test("only the drawer can reserve the round's drawing upload, and a retry gets its own path", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    expect((await failure(uploadDrawing(s, s.b, picked.round_id))).code).toBe("42501");
    const first = await uploadDrawing(s, s.a, picked.round_id);
    const second = await uploadDrawing(s, s.a, picked.round_id);
    expect(second.assetId).not.toBe(first.assetId);
    await s.a.as.mutation(api.drawAndGuess.submit_drawing, { ...op(), p_round_id: picked.round_id, p_media_asset_id: second.assetId });
    expect((await view(s.b)).current_round?.drawing_media_asset_id).toBe(second.assetId);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
