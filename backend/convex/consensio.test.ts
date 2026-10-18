import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { deleteCoupleGameRows } from "./lib/gameRegistry";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

const START = Date.parse("2026-10-18T12:00:00.000Z");

let scheduled: TestConvex | null = null;
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(async () => {
  if (scheduled) await scheduled.finishAllScheduledFunctions(vi.runAllTimers);
  scheduled = null;
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

type Setup = { t: TestConvex; couple: TestCouple; a: TestUser; b: TestUser; gameId: string };

/** A couple with devices, settings and a game. `a` places first. */
async function startGame(language: "en" | "nb" = "en"): Promise<Setup> {
  const t = newTest();
  scheduled = t;
  const couple = await createCouple(t);
  const { first: a, second: b } = couple;
  await addDevice(t, a.userId);
  await addDevice(t, b.userId);
  await a.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: language });
  const { game_id } = await a.as.mutation(api.consensio.ensure_consensio_game, {});
  return { t, couple, a, b, gameId: game_id };
}

const view = (user: TestUser) => user.as.query(api.consensio.get_consensio, {});
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());
const history = (user: TestUser, limit = 30, before: number | null = null) =>
  user.as.query(api.consensio.get_consensio_history, { p_before_round_number: before, p_limit: limit });

/** Places `spot` on the first offered topic. Returns the round id. */
async function place(
  user: TestUser,
  spot: number,
  roundId = newUuid(),
  args = op(),
  topic?: { topic_id: string; language: "en" | "nb" },
  roundNumber?: number,
) {
  const data = await view(user);
  const choice = topic ?? data.game!.choices[0];
  await user.as.mutation(api.consensio.place_consensio_spot, {
    ...args,
    p_round_id: roundId,
    p_topic_id: choice.topic_id,
    p_topic_language: choice.language,
    p_spot: spot,
    p_round_number: roundNumber ?? data.game!.round_count + 1,
  });
  return roundId;
}

const guess = (user: TestUser, roundId: string, value: number, args = op()) =>
  user.as.mutation(api.consensio.guess_consensio_spot, { ...args, p_round_id: roundId, p_guess: value });

describe("access", () => {
  test("a user without a couple cannot play", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect((await failure(loner.as.mutation(api.consensio.ensure_consensio_game, {}))).code).toBe("42501");
    expect((await failure(loner.as.query(api.consensio.get_consensio, {}))).code).toBe("42501");
    expect((await failure(history(loner))).code).toBe("42501");
  });

  test("a couple without a subscription cannot play", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(couple.first.as.mutation(api.consensio.ensure_consensio_game, {}))).code).toBe("42501");
  });

  test("another couple cannot guess or mark a round", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 40);
    const other = await createCouple(s.t);
    expect((await failure(guess(other.first, roundId, 40))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.consensio.mark_consensio_reveal_seen, { p_round_id: roundId }))).code).toBe("42501");
  });

  test("a partner who left cannot guess", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 40);
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect((await failure(guess(s.b, roundId, 40))).code).toBe("42501");
  });
});

describe("ensure_consensio_game", () => {
  test("makes one game with the caller placing first and three topics only the caller sees", async () => {
    const s = await startGame();
    expect(await s.b.as.mutation(api.consensio.ensure_consensio_game, {})).toEqual({ game_id: s.gameId, created: false });
    const mine = await view(s.a);
    expect(mine.game).toMatchObject({ id: s.gameId, turn_user_id: s.a.userId, shared_points: 0, round_count: 0, version: 1 });
    expect(mine.game!.choices).toHaveLength(3);
    expect(new Set(mine.game!.choices.map((choice) => choice.topic_id)).size).toBe(3);
    expect(mine.current_round).toBeNull();
    expect((await view(s.b)).game!.choices).toEqual([]);
  });

  test("needs the game settings", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect((await failure(couple.first.as.mutation(api.consensio.ensure_consensio_game, {}))).code).toBe("23514");
  });
});

describe("the round", () => {
  test("the guesser never reads the spot before guessing, and the placer always does", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 72);
    expect((await view(s.a)).current_round).toMatchObject({ id: roundId, spot: 72, guess: null, placer_user_id: s.a.userId });
    const theirs = (await view(s.b)).current_round!;
    expect(theirs).toMatchObject({ id: roundId, spot: null, guess: null, guesser_user_id: s.b.userId });
    expect(JSON.stringify(await view(s.b))).not.toMatch(/"spot":72/);
    expect((await view(s.b)).game).toMatchObject({ turn_user_id: s.b.userId, round_count: 1 });
    expect((await view(s.b)).game!.choices).toHaveLength(3);
    expect((await view(s.a)).game!.choices).toEqual([]);
  });

  test("a guess scores by distance and makes the guesser the next placer", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 70);
    const result = await guess(s.b, roundId, 64);
    expect(result).toMatchObject({ id: roundId, spot: 70, guess: 64, distance: 6, points: 4 });
    expect((await view(s.a)).game).toMatchObject({ turn_user_id: s.b.userId, shared_points: 4 });
    expect((await view(s.a)).current_round).toMatchObject({ guess: 64, points: 4 });

    const next = await place(s.b, 10);
    const data = await view(s.a);
    expect(data.current_round).toMatchObject({ id: next, round_number: 2, placer_user_id: s.b.userId, spot: null });
    expect(data.previous_round).toMatchObject({ id: roundId, spot: 70, guess: 64, my_reveal_seen_at: null });
  });

  test("points drop by one every 4 off", async () => {
    const cases: [number, number][] = [[0, 5], [3, 5], [4, 4], [7, 4], [8, 3], [12, 2], [16, 1], [19, 1], [20, 0], [100, 0]];
    for (const [distance, points] of cases) {
      const s = await startGame();
      const roundId = await place(s.a, 0);
      expect((await guess(s.b, roundId, distance)).points).toBe(points);
    }
  });

  test("the turn is enforced", async () => {
    const s = await startGame();
    const topic = { topic_id: "camping", language: "en" as const };
    expect((await failure(place(s.b, 50, newUuid(), op(), topic))).message).toMatch(/your turn/);
    const roundId = await place(s.a, 50);
    expect((await failure(place(s.a, 50, newUuid(), op(), topic))).message).toMatch(/your turn/);
    expect((await failure(guess(s.a, roundId, 50))).code).toBe("42501");
    await guess(s.b, roundId, 50);
    expect((await failure(guess(s.b, roundId, 49))).message).toMatch(/already has a guess/);
  });

  test("spots and guesses are whole numbers from 0 to 100", async () => {
    const s = await startGame();
    for (const bad of [-1, 101, 50.5, Number.NaN]) {
      expect((await failure(place(s.a, bad))).message).toMatch(/whole number/);
    }
    const roundId = await place(s.a, 100);
    expect((await failure(guess(s.b, roundId, 3.2))).message).toMatch(/whole number/);
  });

  test("a repeated operation returns the same answer", async () => {
    const s = await startGame();
    const roundId = newUuid();
    const placeArgs = op();
    const topic = (await view(s.a)).game!.choices[0];
    await place(s.a, 30, roundId, placeArgs, topic, 1);
    await place(s.a, 30, roundId, placeArgs, topic, 1);
    const guessArgs = op();
    const first = await guess(s.b, roundId, 31, guessArgs);
    expect(await guess(s.b, roundId, 31, guessArgs)).toEqual(first);
    expect((await view(s.a)).game!.shared_points).toBe(5);
  });

  test("an own topic is stored as written, and bad ones are refused", async () => {
    const s = await startGame();
    const own = (subject: string, left: string, right: string) =>
      s.a.as.mutation(api.consensio.place_consensio_spot, {
        ...op(),
        p_round_id: newUuid(),
        p_subject: subject,
        p_left_end: left,
        p_right_end: right,
        p_spot: 20,
        p_round_number: 1,
      });
    expect((await failure(own("x", "Yes", "No"))).message).toMatch(/subject/);
    expect((await failure(own("Waffles", "", "No"))).message).toMatch(/each end/);
    expect((await failure(own("Waffles", "Yes", "yes"))).message).toMatch(/different/);
    await own("  Your  mom's\nwaffles ", "Not again", "Every Sunday");
    expect((await view(s.b)).current_round).toMatchObject({ topic_id: null, language: null, subject: "Your mom's waffles", left_end: "Not again", right_end: "Every Sunday" });
  });

  test("a topic from before a language change still places", async () => {
    const s = await startGame();
    const old = (await view(s.a)).game!.choices[0];
    await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "nb" });
    expect((await view(s.a)).game!.choices.every((choice) => choice.language === "nb")).toBe(true);
    await s.a.as.mutation(api.consensio.place_consensio_spot, {
      ...op(),
      p_round_id: newUuid(),
      p_topic_id: old.topic_id,
      p_topic_language: old.language,
      p_spot: 5,
      p_round_number: 1,
    });
    expect((await view(s.b)).current_round).toMatchObject({ topic_id: old.topic_id, language: "en", subject: old.subject });
    expect((await failure(s.b.as.mutation(api.consensio.place_consensio_spot, { ...op(), p_round_id: newUuid(), p_topic_id: "nope", p_topic_language: "en", p_spot: 5, p_round_number: 2 }))).code).toBe("23514");
  });

  test("a placement queued for a turn that moved on is refused", async () => {
    const s = await startGame();
    const topic = { topic_id: "camping", language: "en" as const };
    const first = await place(s.a, 30);
    await guess(s.b, first, 31);
    const second = await place(s.b, 60);
    await guess(s.a, second, 62);
    // A second phone of a's queued round 2 when round 2 was b's.
    expect((await failure(place(s.a, 40, newUuid(), op(), topic, 2))).message).toMatch(/moved on/);
    await place(s.a, 40, newUuid(), op(), topic, 3);
  });

  test("a replay after access ended is refused", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 30);
    const args = op();
    await guess(s.b, roundId, 31, args);
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect((await failure(guess(s.b, roundId, 31, args))).code).toBe("42501");
  });

  test("placing counts toward the streak and guessing does not", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 30);
    await guess(s.b, roundId, 31);
    const events = await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events.map((event) => [event.activity_kind, event.user_id])).toEqual([["game_turn_completed", s.a.userId]]);
  });

  test("a placed topic is not offered again until the list runs out", async () => {
    const s = await startGame();
    const placed = (await view(s.a)).game!.choices[0].topic_id;
    const roundId = await place(s.a, 30);
    await guess(s.b, roundId, 31);
    for (let i = 0; i < 20; i++) {
      await s.b.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
      expect((await view(s.b)).game!.choices.map((choice) => choice.topic_id)).not.toContain(placed);
    }
  });
});

describe("seen marks", () => {
  test("keep the first time for each partner", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 30);
    expect((await failure(s.a.as.mutation(api.consensio.mark_consensio_reveal_seen, { p_round_id: roundId }))).message).toMatch(/no guess/);
    await guess(s.b, roundId, 31);
    const first = await s.b.as.mutation(api.consensio.mark_consensio_reveal_seen, { p_round_id: roundId });
    tick(60);
    expect(await s.b.as.mutation(api.consensio.mark_consensio_reveal_seen, { p_round_id: roundId })).toEqual(first);
    expect((await view(s.b)).current_round!.my_reveal_seen_at).toBe(first.reveal_seen_at);
    expect((await view(s.a)).current_round!.my_reveal_seen_at).toBeNull();
  });
});

describe("history", () => {
  test("lists guessed rounds newest first, pages, and keeps records per guesser", async () => {
    const s = await startGame();
    let placer = s.a;
    let guesser = s.b;
    for (let i = 0; i < 5; i++) {
      const roundId = await place(placer, 50);
      await guess(guesser, roundId, 50 + i * 5);
      [placer, guesser] = [guesser, placer];
    }
    const open = await place(placer, 10);
    const page = await history(s.a, 2);
    expect(page.rounds.map((round) => round.round_number)).toEqual([5, 4]);
    expect(page.next_before_round_number).toBe(4);
    const rest = await history(s.a, 30, 4);
    expect(rest.rounds.map((round) => round.round_number)).toEqual([3, 2, 1]);
    expect(rest.next_before_round_number).toBeNull();
    expect(JSON.stringify(await history(s.b))).not.toContain(open);
    // b guessed rounds 1, 3 and 5 (0, 10 and 20 off). a guessed rounds 2 and 4 (5 and 15 off).
    expect(page.records.partner).toEqual({ guesses: 3, spot_ons: 1, average_distance: 10 });
    expect(page.records.mine).toEqual({ guesses: 2, spot_ons: 0, average_distance: 10 });
    expect(page.records.shared_points).toBe(5 + 3 + 0 + 4 + 2);
  });
});

describe("pushes", () => {
  const rowsOf = async (s: Setup, kind: string) => (await outbox(s.t)).filter((row) => row.kind === kind);
  const types = (rows: { payload: unknown }[]) => rows.map((row) => (row.payload as { type: string; step?: string }).step ?? (row.payload as { type: string }).type).sort();

  test("a placement tells the guesser, without the topic or the spot", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 72);
    const rows = await rowsOf(s, "game_turn_ready");
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      payload: { game_kind: "consensio", round_id: roundId, actor_user_id: s.a.userId, deeplink: "paeonia://games/consensio" },
    });
    const subject = (await view(s.b)).current_round!.subject;
    expect(JSON.stringify(await outbox(s.t))).not.toContain(subject);
    expect(JSON.stringify(rows.map((row) => row.payload))).not.toMatch(/spot|guess|points/);
  });

  test("a guess then a placement within 5 minutes send one push", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 72);
    await deliverDuePushes(s.t);
    await guess(s.b, roundId, 70);
    expect(await deliverDuePushes(s.t)).toEqual([]);
    tick(60);
    await place(s.b, 20);
    tick(5 * 60);
    expect(types(await deliverDuePushes(s.t))).toEqual(["guessed"]);
    expect((await rowsOf(s, "game_result"))[0].last_error).toBe("notification is out of date");
  });

  test("a guess with no placement sends the result push after 5 minutes", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 72);
    await deliverDuePushes(s.t);
    await guess(s.b, roundId, 70);
    tick(5 * 60);
    expect(types(await deliverDuePushes(s.t))).toEqual(["game_result"]);
    tick(60);
    await place(s.b, 20);
    expect(types(await deliverDuePushes(s.t))).toEqual(["game_turn_ready"]);
  });

  test("a result push is dropped when the placer opened the game during the wait", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 72);
    await deliverDuePushes(s.t);
    await guess(s.b, roundId, 70);
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "consensio", p_present: true });
    tick(5 * 60);
    expect(await deliverDuePushes(s.t)).toEqual([]);
  });

  test("a result push is dropped once the placer saw the reveal", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 72);
    await deliverDuePushes(s.t);
    await guess(s.b, roundId, 70);
    await s.a.as.mutation(api.consensio.mark_consensio_reveal_seen, { p_round_id: roundId });
    tick(5 * 60);
    expect(await deliverDuePushes(s.t)).toEqual([]);
  });

  test("a turn push is dropped once the guess is in", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 72);
    await guess(s.b, roundId, 70);
    expect(types(await deliverDuePushes(s.t))).toEqual([]);
    expect((await rowsOf(s, "game_turn_ready"))[0].last_error).toBe("notification is out of date");
  });

  test("no push while the partner has the game open", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "consensio", p_present: true });
    await place(s.a, 72);
    expect(await outbox(s.t)).toHaveLength(0);
  });
});

describe("turn reminder", () => {
  const run = (s: Setup) => s.t.mutation(internal.consensio.send_due_consensio_reminders, {});
  const reminders = async (s: Setup) => (await outbox(s.t)).filter((row) => row.kind === "game_turn_reminder");

  test("one reminder per turn, for a guess and for a placement", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 40);
    tick(71 * 3600);
    expect(await run(s)).toBe(0);
    tick(3600);
    expect(await run(s)).toBe(1);
    expect(await run(s)).toBe(0);
    expect((await reminders(s))[0]).toMatchObject({ recipient_user_id: s.b.userId, payload: { actor_user_id: s.a.userId, game_id: s.gameId } });

    await guess(s.b, roundId, 40);
    tick(72 * 3600);
    expect(await run(s)).toBe(1);
    expect((await reminders(s)).map((row) => row.recipient_user_id)).toEqual([s.b.userId, s.b.userId]);
  });

  test("a reminder queued for a turn that moved on is dropped", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 40);
    await deliverDuePushes(s.t);
    tick(72 * 3600);
    await run(s);
    await guess(s.b, roundId, 40);
    expect(await deliverDuePushes(s.t)).toEqual([]);
  });
});

describe("cleanup", () => {
  test("deletes every Consensio row of the couple", async () => {
    const s = await startGame();
    const roundId = await place(s.a, 40);
    await guess(s.b, roundId, 40);
    await s.t.run((ctx) => deleteCoupleGameRows(ctx, s.couple.coupleId));
    const left = await s.t.run(async (ctx) => [
      ...(await ctx.db.query("consensio_games").collect()),
      ...(await ctx.db.query("consensio_rounds").collect()),
      ...(await ctx.db.query("consensio_used_topics").collect()),
    ]);
    expect(left).toEqual([]);
  });
});
