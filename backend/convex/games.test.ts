import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { hmacSha256Hex } from "./lib/crypto";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op, setMediaEnv, uploadAsset } from "./media.testing";
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
  const { game_id } = await a.as.mutation(api.games.ensure_draw_and_guess_game, {});
  return { t, couple, a, b, gameId: game_id };
}

const view = (user: TestUser) => user.as.query(api.games.get_draw_and_guess, {});

async function pick(user: TestUser, gameId: string, choice: "easy" | "medium" | "hard" | "custom", custom?: string, roundId = newUuid()) {
  const offered = choice === "custom" ? null : (await view(user)).choices?.find((item: { difficulty: string }) => item.difficulty === choice);
  const result = await user.as.mutation(api.games.pick_draw_word, {
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
  return await user.as.mutation(api.games.submit_drawing, { ...op(), p_round_id: roundId, p_media_asset_id: up.assetId });
}

const guess = (user: TestUser, roundId: string, text: string) =>
  user.as.mutation(api.games.submit_guess, { ...op(), p_round_id: roundId, p_guess: text });

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
    await guesser.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id });
    tick(afterSeconds);
  }
  return { picked, result: await guess(guesser, picked.round_id, picked.word) };
}

describe("access", () => {
  test("a user without a couple cannot use the games", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect((await failure(loner.as.mutation(api.games.ensure_draw_and_guess_game, {}))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" }))).code).toBe("42501");
    expect((await failure(loner.as.query(api.games.get_draw_and_guess, {}))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" }))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true }))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.games.create_game_live_ticket, { p_kind: "draw_and_guess" }))).code).toBe("42501");
  });

  test("a couple without a subscription cannot use the games", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(couple.first.as.mutation(api.games.ensure_draw_and_guess_game, {}))).code).toBe("42501");
    expect((await failure(couple.first.as.query(api.games.get_game_settings, {}))).code).toBe("42501");
  });

  test("a subscription that ends blocks the existing game", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    await s.t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    expect((await failure(s.a.as.mutation(api.games.pick_draw_word, { ...op(), p_game_id: s.gameId, p_round_id: newUuid(), p_choice: "easy", p_custom_word: null }))).code).toBe("42501");
    expect((await failure(s.b.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id }))).code).toBe("42501");
  });

  test("another couple cannot touch a round", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const other = await createCouple(s.t);
    expect((await failure(guess(other.first, picked.round_id, "cat"))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id }))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.games.respond_save_prompt, { p_round_id: picked.round_id }))).code).toBe("42501");
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
        auth_delete_attempts: 0,
        next_attempt_at: new Date().toISOString(),
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      });
    });
    expect((await failure(s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true }))).message).toMatch(/account deletion/);
    expect((await failure(s.a.as.mutation(api.games.pick_draw_word, { ...op(), p_game_id: s.gameId, p_round_id: newUuid(), p_choice: "easy", p_custom_word: null }))).message).toMatch(/account deletion/);
  });
});

describe("settings", () => {
  test("either partner writes them and the last write wins", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await couple.first.as.query(api.games.get_game_settings, {})).toBeNull();
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    const changed = await couple.second.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "nb" });
    expect(changed).toMatchObject({ play_style: "against", language: "nb", updated_by_user_id: couple.second.userId, couple_id: couple.coupleId });
    expect(await couple.first.as.query(api.games.get_game_settings, {})).toMatchObject({ play_style: "against", language: "nb" });
    expect(await t.run((ctx) => ctx.db.query("game_settings").collect())).toHaveLength(1);
  });

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
    expect((await failure(couple.first.as.mutation(api.games.ensure_draw_and_guess_game, {}))).message).toMatch(/settings are required/);
  });
});

describe("ensure_draw_and_guess_game", () => {
  test("creates one game with the caller drawing first, and returns it again", async () => {
    const s = await startGame();
    const again = await s.b.as.mutation(api.games.ensure_draw_and_guess_game, {});
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
      couple.first.as.mutation(api.games.ensure_draw_and_guess_game, {}),
      couple.second.as.mutation(api.games.ensure_draw_and_guess_game, {}),
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
    const first = await s.a.as.mutation(api.games.pick_draw_word, args);
    expect(await s.a.as.mutation(api.games.pick_draw_word, args)).toEqual(first);
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
      user.as.mutation(api.games.submit_drawing, { ...op(), p_round_id: roundId, p_media_asset_id: assetId });
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
    const first = await s.a.as.mutation(api.games.submit_drawing, args);
    expect(await s.a.as.mutation(api.games.submit_drawing, args)).toEqual(first);
    expect((await outbox(s.t)).filter((row) => row.kind === "game_turn_ready")).toHaveLength(1);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the partner can download the drawing and an outsider cannot", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const up = await uploadDrawing(s, s.a, picked.round_id);
    // A drawing nobody attached yet is not readable by the partner.
    expect((await failure(s.b.as.mutation(api.media.get_media_signed_url, { p_media_asset_id: up.assetId, p_expires_in_seconds: 300 }))).code).toBe("42501");
    await s.a.as.mutation(api.games.submit_drawing, { ...op(), p_round_id: picked.round_id, p_media_asset_id: up.assetId });

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
    await s.b.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id });
    tick(8);
    const solved = await guess(s.b, picked.round_id, picked.word);
    expect(solved).toMatchObject({ correct: true, round_state: "solved", speed_bonus: 1, solve_ms: 8000 });

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
    const first = await s.b.as.mutation(api.games.submit_guess, args);
    expect(await s.b.as.mutation(api.games.submit_guess, args)).toEqual(first);
    expect(await s.t.run((ctx) => ctx.db.query("game_guesses").collect())).toHaveLength(1);
  });
});

describe("give_up_round", () => {
  test("counts as missed, scores nothing, and the guesser draws next", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "hard");
    await sendDrawing(s, s.a, picked.round_id);
    expect((await failure(s.a.as.mutation(api.games.give_up_round, { ...op(), p_round_id: picked.round_id }))).code).toBe("42501");
    const result = await s.b.as.mutation(api.games.give_up_round, { ...op(), p_round_id: picked.round_id });
    expect(result).toEqual({ round_id: picked.round_id, round_state: "missed" });
    const data = await view(s.a);
    expect(data.current_round).toMatchObject({ state: "missed", word: picked.word });
    expect(data.game).toMatchObject({ state: "choosing_word", turn_user_id: s.b.userId, shared_points: 0, my_points: 0, partner_points: 0 });
    expect((await failure(s.b.as.mutation(api.games.give_up_round, { ...op(), p_round_id: picked.round_id }))).message).toMatch(/already finished/);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("scoring", () => {
  test("every solve adds the word points to the shared total and to each personal total, in either play style", async () => {
    for (const playStyle of ["together", "against"] as const) {
      const s = await startGame({ playStyle });
      // a draws an easy word, b guesses 10 seconds after seeing it: b gets 1 + the speed bonus, a gets 1.
      await playRound(s, s.a, s.b, "easy", 10);
      let data = await view(s.a);
      expect(data.game).toMatchObject({ shared_points: 1, my_points: 1, partner_points: 2 });
      // b draws a hard word, a guesses 40 seconds after seeing it: a gets 3, b gets 3.
      await playRound(s, s.b, s.a, "hard", 40);
      data = await view(s.a);
      expect(data.game).toMatchObject({ shared_points: 4, my_points: 4, partner_points: 5 });
      data = await view(s.b);
      expect(data.game).toMatchObject({ shared_points: 4, my_points: 5, partner_points: 4 });
      expect(data.settings?.play_style).toBe(playStyle);
      // A missed round changes nothing.
      const third = await pick(s.a, s.gameId, "hard");
      await sendDrawing(s, s.a, third.round_id);
      await s.b.as.mutation(api.games.give_up_round, { ...op(), p_round_id: third.round_id });
      expect((await view(s.a)).game).toMatchObject({ shared_points: 4, my_points: 4, partner_points: 5 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    }
  });

  test("a live watcher gets the speed bonus window from when the drawing was sent", async () => {
    const s = await startGame({ playStyle: "against" });
    const picked = await pick(s.a, s.gameId, "easy");
    await s.b.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id });
    tick(60);
    await sendDrawing(s, s.a, picked.round_id);
    tick(10);
    const solved = await guess(s.b, picked.round_id, picked.word);
    expect(solved).toMatchObject({ correct: true, speed_bonus: 1, solve_ms: 70_000 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the speed bonus needs a guess within 30 seconds of first seeing the drawing", async () => {
    const s = await startGame({ playStyle: "against" });
    const bonus = async (seconds: number | null) => {
      const { result } = await playRound(s, s.a, s.b, "easy", seconds);
      // The roles swap after each solve, so give the turn back to a with a quick missed round of b.
      const back = await pick(s.b, s.gameId, "easy");
      await sendDrawing(s, s.b, back.round_id);
      await s.a.as.mutation(api.games.give_up_round, { ...op(), p_round_id: back.round_id });
      return result;
    };
    expect(await bonus(30)).toMatchObject({ points: 1, speed_bonus: 1, solve_ms: 30_000 });
    expect(await bonus(31)).toMatchObject({ points: 1, speed_bonus: 0, solve_ms: 31_000 });
    expect(await bonus(null)).toMatchObject({ points: 1, speed_bonus: 0, solve_ms: null });
    const data = await view(s.b);
    // b scored 1 + 1, 1, 1. a scored 1 for each of the three, as the drawer.
    expect(data.game).toMatchObject({ shared_points: 3, my_points: 4, partner_points: 3 });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  describe("the phone's speed bonus claim", () => {
    const claimed = (user: TestUser, roundId: string, text: string, claim: { p_speed_bonus?: boolean | null; p_solve_ms?: number | null }) =>
      user.as.mutation(api.games.submit_guess, { ...op(), p_round_id: roundId, p_guess: text, ...claim });

    test("a true claim gives the bonus even when the server clock alone says no", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await sendDrawing(s, s.a, picked.round_id);
      // The guess waited in the offline queue, and mark_round_seen never arrived.
      tick(300);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: true, p_solve_ms: 12_000 });
      expect(solved).toMatchObject({ correct: true, points: 1, speed_bonus: 1, solve_ms: 12_000 });
      expect((await view(s.b)).game).toMatchObject({ shared_points: 1, my_points: 2, partner_points: 1 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("a false claim gives no bonus even when the server clock alone says yes", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await s.b.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id });
      tick(5);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: false, p_solve_ms: 45_000 });
      expect(solved).toMatchObject({ correct: true, speed_bonus: 0, solve_ms: 45_000 });
      expect((await view(s.b)).game).toMatchObject({ my_points: 1 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("without a claim the server decides, and null counts as absent", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await s.b.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id });
      tick(8);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: null, p_solve_ms: null });
      expect(solved).toMatchObject({ speed_bonus: 1, solve_ms: 8000 });
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
        expect((await failure(claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: true, p_solve_ms }))).code).toBe("23514");
      }
    });

    test("a guess after more than 30 days still solves the round, with the solve time capped", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await sendDrawing(s, s.a, picked.round_id);
      await s.b.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id });
      tick(31 * 24 * 3600);
      const solved = await claimed(s.b, picked.round_id, picked.word, { p_speed_bonus: false, p_solve_ms: 31 * 24 * 3600 * 1000 });
      expect(solved).toMatchObject({ correct: true, round_state: "solved", speed_bonus: 0, solve_ms: 30 * 24 * 3600 * 1000 });
      expect((await view(s.b)).game).toMatchObject({ state: "choosing_word", turn_user_id: s.b.userId, shared_points: 1 });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("a replay with the same claim returns the stored result and a different claim is a hash mismatch", async () => {
      const s = await startGame({ playStyle: "against" });
      const picked = await pick(s.a, s.gameId, "easy");
      await sendDrawing(s, s.a, picked.round_id);
      const args = { ...op(), p_round_id: picked.round_id, p_guess: picked.word, p_speed_bonus: true, p_solve_ms: 4000 };
      const first = await s.b.as.mutation(api.games.submit_guess, args);
      expect(await s.b.as.mutation(api.games.submit_guess, args)).toEqual(first);
      const changed = { ...args, p_speed_bonus: false };
      expect((await failure(s.b.as.mutation(api.games.submit_guess, changed))).message).toContain("replay hash mismatch");
      const slower = { ...args, p_solve_ms: 5000 };
      expect((await failure(s.b.as.mutation(api.games.submit_guess, slower))).message).toContain("replay hash mismatch");
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });
  });

  test("mark_round_seen keeps the first time and only works for the guesser", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    expect((await failure(s.a.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id }))).code).toBe("42501");
    const first = await s.b.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id });
    tick(20);
    expect(await s.b.as.mutation(api.games.mark_round_seen, { p_round_id: picked.round_id })).toEqual(first);
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
      body: "Open Paeonia to guess it.",
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
    const rows = (await outbox(s.t)).filter((row) => row.kind === "game_guessed");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.a.userId,
      title: "Second Partner guessed your drawing",
      payload: { type: "game_guessed", round_id: picked.round_id, deeplink: "paeonia://games/draw-and-guess" },
    });
    expect(JSON.stringify(rows[0])).not.toContain(picked.word);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("pushes are in the recipient's language", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    await addDevice(t, couple.second.userId, { locale: "nb-NO" });
    await couple.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    const { game_id } = await couple.first.as.mutation(api.games.ensure_draw_and_guess_game, {});
    const s: Setup = { t, couple, a: couple.first, b: couple.second, gameId: game_id };
    const picked = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, picked.round_id);
    const [row] = await outbox(t);
    expect(row).toMatchObject({ title: "Din tur i Tegn og gjett", body: "Åpne Paeonia for å gjette." });
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

  test("presence older than 60 seconds does not suppress the push, and closing the screen removes it", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    tick(61);
    const picked = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, picked.round_id);
    expect((await outbox(s.t)).filter((row) => row.kind === "game_turn_ready")).toHaveLength(1);

    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: false });
    await guess(s.b, picked.round_id, picked.word);
    expect((await outbox(s.t)).filter((row) => row.kind === "game_guessed")).toHaveLength(1);
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
  const claim = (s: Setup) => s.t.mutation(internal.pushQueue.claim_notification_batch, {});
  const kinds = (rows: { payload: unknown }[]) => rows.map((row) => (row.payload as { type: string }).type).sort();
  const errorsOf = async (s: Setup, kind: string) =>
    (await outbox(s.t)).filter((row) => row.kind === kind).map((row) => row.last_error ?? null);

  test("drops a turn push or reminder once the turn moved on, and keeps current ones", async () => {
    const s = await startGame();
    // b gives up before the drain runs, so the turn push for that round is out of date.
    const first = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, first.round_id);
    await s.b.as.mutation(api.games.give_up_round, { ...op(), p_round_id: first.round_id });
    expect(await claim(s)).toEqual([]);
    expect(await errorsOf(s, "game_turn_ready")).toEqual(["notification is out of date"]);

    // A turn push that still waits for its guesser goes out.
    const second = await pick(s.b, s.gameId, "easy");
    await sendDrawing(s, s.b, second.round_id);
    expect(kinds(await claim(s))).toEqual(["game_turn_ready"]);

    // The reminder is out of date once a guesses, and the guessed push still goes to b.
    tick(73 * 3600);
    expect(await s.t.mutation(internal.games.send_due_game_turn_reminders, {})).toBe(1);
    await guess(s.a, second.round_id, second.word);
    expect(kinds(await claim(s))).toEqual(["game_guessed"]);
    expect(await errorsOf(s, "game_turn_reminder")).toEqual(["notification is out of date"]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("drops every couple push queued before the relationship ended", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "custom", "flying cat");
    await sendDrawing(s, s.a, picked.round_id);
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" });
    await guess(s.b, picked.round_id, "flying cat");
    const image = await uploadAsset(s.t, s.b, photo(s.couple.coupleId));
    await s.b.as.mutation(api.games.save_round_to_memories, {
      p_round_id: picked.round_id,
      p_memory_id: newUuid(),
      p_media_asset_id: image.assetId,
      p_memory_date: "2026-10-10",
    });
    expect(kinds((await outbox(s.t)).filter((row) => row.last_attempt_at === undefined))).toEqual(
      ["game_guessed", "game_invite", "game_turn_ready", "memory_created"],
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
      payload: { type: "game_invite", game_id: s.gameId, deeplink: "paeonia://games/draw-and-guess" },
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
  test("the query returns each partner's last seen time and the cron removes old rows", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    const seen = new Date().toISOString();
    expect((await view(s.a)).partner_last_seen_at).toBe(seen);
    expect((await view(s.a)).my_last_seen_at).toBeNull();
    tick(30);
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    expect((await view(s.a)).partner_last_seen_at).toBe(new Date().toISOString());
    expect(await s.t.run((ctx) => ctx.db.query("game_presence").collect())).toHaveLength(1);

    tick(119);
    expect(await s.t.mutation(internal.games.cleanup_stale_game_presence, {})).toBe(0);
    tick(2);
    expect(await s.t.mutation(internal.games.cleanup_stale_game_presence, {})).toBe(1);
    expect((await view(s.a)).partner_last_seen_at).toBeNull();
  });
});

describe("turn reminder", () => {
  test("goes out once after 72 hours to the partner whose turn it is, and again only for a new move", async () => {
    const s = await startGame();
    const run = () => s.t.mutation(internal.games.send_due_game_turn_reminders, {});
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
    expect(await s.t.mutation(internal.games.send_due_game_turn_reminders, {})).toBe(0);
    expect(await outbox(s.t)).toHaveLength(0);

    const other = await startGame();
    await endCouple(other.t, other.couple.coupleId, other.a.userId);
    expect(await other.t.mutation(internal.games.send_due_game_turn_reminders, {})).toBe(0);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("save to Memories", () => {
  async function finishedRound(s: Setup) {
    const picked = await pick(s.a, s.gameId, "custom", "flying cat");
    await sendDrawing(s, s.a, picked.round_id);
    await guess(s.b, picked.round_id, "flying cat");
    return picked;
  }

  const uploadImage = (s: Setup, user: TestUser) => uploadAsset(s.t, user, photo(s.couple.coupleId));
  const save = (user: TestUser, roundId: string, image: { assetId: string; parentId: string }, memoryId = newUuid()) =>
    user.as.mutation(api.games.save_round_to_memories, {
      p_round_id: roundId,
      p_memory_id: memoryId,
      p_media_asset_id: image.assetId,
      p_memory_date: "2026-10-10",
    });

  test("creates a memory titled with the word, created by the caller", async () => {
    const s = await startGame();
    const picked = await finishedRound(s);
    const image = await uploadImage(s, s.b);
    const memoryId = newUuid();
    expect(await save(s.b, picked.round_id, image, memoryId)).toEqual({ memory_id: memoryId, created: true });

    const memories = await s.t.run((ctx) => ctx.db.query("memories").collect());
    expect(memories).toHaveLength(1);
    expect(memories[0]).toMatchObject({ id: memoryId, title: "Flying cat", created_by_user_id: s.b.userId, couple_id: s.couple.coupleId });
    const links = await s.t.run((ctx) => ctx.db.query("memory_media").collect());
    expect(links).toMatchObject([{ memory_id: memoryId, media_asset_id: image.assetId, owner_user_id: s.b.userId }]);
    const data = await view(s.a);
    expect(data.current_round).toMatchObject({ memory_id: memoryId, saved_by_user_id: s.b.userId });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("two partners saying yes at once get one memory, and the extra image is queued for deletion", async () => {
    const s = await startGame();
    const picked = await finishedRound(s);
    const imageA = await uploadImage(s, s.a);
    const imageB = await uploadImage(s, s.b);
    const memoryA = newUuid();
    const memoryB = newUuid();
    const results = await Promise.all([save(s.a, picked.round_id, imageA, memoryA), save(s.b, picked.round_id, imageB, memoryB)]);

    expect(results.filter((result) => result.created)).toHaveLength(1);
    const winner = results.find((result) => result.created)!;
    expect(results.every((result) => result.memory_id === winner.memory_id)).toBe(true);
    expect(await s.t.run((ctx) => ctx.db.query("memories").collect())).toHaveLength(1);
    expect(await s.t.run((ctx) => ctx.db.query("memory_media").collect())).toHaveLength(1);

    const loserImage = winner.memory_id === memoryA ? imageB : imageA;
    const winnerImage = winner.memory_id === memoryA ? imageA : imageB;
    const assets = await s.t.run((ctx) => ctx.db.query("media_assets").collect());
    expect(assets.find((asset) => asset.id === loserImage.assetId)).toMatchObject({ storage_delete_status: "pending" });
    expect(assets.find((asset) => asset.id === winnerImage.assetId)).toMatchObject({ storage_delete_status: "none" });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a second save one after the other returns the existing memory", async () => {
    const s = await startGame();
    const picked = await finishedRound(s);
    const first = await save(s.a, picked.round_id, await uploadImage(s, s.a));
    const second = await save(s.b, picked.round_id, await uploadImage(s, s.b));
    expect(second).toEqual({ memory_id: first.memory_id, created: false });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an unfinished round cannot be saved, and a stranger's round neither", async () => {
    const s = await startGame();
    const picked = await pick(s.a, s.gameId, "easy");
    const image = await uploadImage(s, s.a);
    expect((await failure(save(s.a, picked.round_id, image))).message).toMatch(/not finished/);
    const stranger = await createCouple(s.t);
    expect((await failure(save(stranger.first, picked.round_id, image))).code).toBe("42501");
  });

  test("Not now closes the prompt for one partner only", async () => {
    const s = await startGame();
    const picked = await finishedRound(s);
    expect((await failure(s.a.as.mutation(api.games.respond_save_prompt, { p_round_id: newUuid() }))).code).toBe("42501");
    await s.b.as.mutation(api.games.respond_save_prompt, { p_round_id: picked.round_id });
    await s.b.as.mutation(api.games.respond_save_prompt, { p_round_id: picked.round_id });
    expect((await view(s.b)).current_round).toMatchObject({ my_save_response: "not_now", partner_save_response: null });
    expect((await view(s.a)).current_round).toMatchObject({ my_save_response: null, partner_save_response: "not_now" });
    expect(await s.t.run((ctx) => ctx.db.query("game_save_responses").collect())).toHaveLength(1);
    // The other partner can still say yes.
    expect((await save(s.a, picked.round_id, await uploadImage(s, s.a))).created).toBe(true);

    const open = await pick(s.b, s.gameId, "easy");
    expect((await failure(s.b.as.mutation(api.games.respond_save_prompt, { p_round_id: open.round_id }))).message).toMatch(/not finished/);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("recent rounds", () => {
  test("lists earlier rounds newest first with their attempts, at most 20", async () => {
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

    const byId = (user: TestUser, roundId: string) => user.as.query(api.games.get_draw_and_guess_round, { p_round_id: roundId });
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

describe("live ticket", () => {
  const decode = (ticket: string) => JSON.parse(atob(ticket.split(".")[0].replace(/-/g, "+").replace(/_/g, "/")));

  test("carries the game channel and is signed for the relay", async () => {
    process.env.PAEONIA_LIVE_RELAY_URL = "wss://relay.example.test/canvas";
    process.env.PAEONIA_LIVE_RELAY_SECRET = "relay-secret";
    try {
      const s = await startGame();
      const ticket = await s.a.as.mutation(api.games.create_game_live_ticket, { p_kind: "draw_and_guess" });
      expect(ticket!.url).toBe("wss://relay.example.test/canvas");
      expect(decode(ticket!.ticket)).toMatchObject({ c: s.couple.coupleId, u: s.a.userId, ch: "draw_and_guess" });
      const [payload, signature] = ticket!.ticket.split(".");
      expect(signature).toBe(await hmacSha256Hex("relay-secret", payload));
      expect(Date.parse(ticket!.expires_at)).toBe(Date.now() + 60_000);

      // The widget canvas ticket keeps working without a channel.
      const widget = await s.a.as.mutation(api.widget.create_widget_live_ticket, {});
      expect(decode(widget!.ticket)).not.toHaveProperty("ch");
    } finally {
      delete process.env.PAEONIA_LIVE_RELAY_URL;
      delete process.env.PAEONIA_LIVE_RELAY_SECRET;
    }
  });

  test("is null while the relay is not configured", async () => {
    const s = await startGame();
    expect(await s.a.as.mutation(api.games.create_game_live_ticket, { p_kind: "draw_and_guess" })).toBeNull();
  });
});

describe("relationship end", () => {
  test("presence goes right away, and cleanup deletes every game row and queues the drawings", async () => {
    const s = await startGame();
    const first = await pick(s.a, s.gameId, "easy");
    await sendDrawing(s, s.a, first.round_id);
    await guess(s.b, first.round_id, first.word);
    await s.b.as.mutation(api.games.respond_save_prompt, { p_round_id: first.round_id });
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "draw_and_guess" });
    const memoryImage = await uploadAsset(s.t, s.a, photo(s.couple.coupleId));
    await s.a.as.mutation(api.games.save_round_to_memories, {
      p_round_id: first.round_id,
      p_memory_id: newUuid(),
      p_media_asset_id: memoryImage.assetId,
      p_memory_date: "2026-10-10",
    });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });
    // A second couple's game must survive.
    const keep = await startGame();
    await keep.a.as.mutation(api.games.set_game_presence, { p_kind: "draw_and_guess", p_present: true });

    const tables = [
      "game_settings",
      "games",
      "game_moves",
      "game_guesses",
      "game_save_responses",
      "game_used_words",
      "game_presence",
      "game_invites",
    ] as const;
    const count = (t: TestConvex, coupleId: string) =>
      t.run(async (ctx) => {
        const result: Record<string, number> = {};
        for (const table of tables) {
          result[table] = (await ctx.db.query(table).collect()).filter((row) => row.couple_id === coupleId).length;
        }
        return result;
      });
    expect(Object.values(await count(s.t, s.couple.coupleId)).every((rows) => rows > 0)).toBe(true);

    await s.a.as.mutation(api.relationship.leave_relationship, op());
    expect((await count(s.t, s.couple.coupleId)).game_presence).toBe(0);
    expect((await count(s.t, s.couple.coupleId)).game_moves).toBe(1);

    await s.t.mutation(internal.relationship.cleanup_expired_relationship_content, { p_now: "2027-01-01T00:00:00.000Z" });
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
  expect((await failure(s.b.as.query(api.games.get_draw_and_guess, {}))).code).toBe("42501");
  await grantLifetime(s.t, s.b.userId);
  expect((await view(s.b)).game?.id).toBe(s.gameId);
});

describe("review fixes", () => {
  test("a word choice the drawer never saw is refused after a language change", async () => {
    const s = await startGame();
    const seen = (await view(s.a)).choices!.find((item: { difficulty: string }) => item.difficulty === "easy")!;
    await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    const stale = await failure(
      s.a.as.mutation(api.games.pick_draw_word, {
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
    await s.a.as.mutation(api.games.submit_drawing, { ...op(), p_round_id: picked.round_id, p_media_asset_id: second.assetId });
    expect((await view(s.b)).current_round?.drawing_media_asset_id).toBe(second.assetId);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});
