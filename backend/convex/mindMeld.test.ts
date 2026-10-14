import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { deleteCoupleGameRows } from "./lib/gameRegistry";
import { newUuid } from "./lib/ids";
import { endCouple, failure, op } from "./media.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

const START = Date.parse("2026-10-10T12:00:00.000Z");

let scheduled: TestConvex | null = null;
beforeEach(() => {
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(async () => {
  // Locking in queues a push drain. Let it finish before the test ends.
  if (scheduled) await scheduled.finishAllScheduledFunctions(vi.runAllTimers);
  scheduled = null;
  vi.useRealTimers();
});

const tick = (seconds: number) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));

type Setup = { t: TestConvex; couple: TestCouple; a: TestUser; b: TestUser; gameId: string };

/** A couple with devices and a game in play. `a` started it. */
async function startGame(): Promise<Setup> {
  const t = newTest();
  scheduled = t;
  const couple = await createCouple(t);
  const { first: a, second: b } = couple;
  await addDevice(t, a.userId);
  await addDevice(t, b.userId);
  const { game_id } = await a.as.mutation(api.mindMeld.start_mind_meld_game, {});
  return { t, couple, a, b, gameId: game_id };
}

const view = (user: TestUser) => user.as.query(api.mindMeld.get_mind_meld, {});
const lock = (user: TestUser, roundId: string, word: string, args = op()) =>
  user.as.mutation(api.mindMeld.lock_mind_meld_word, { ...args, p_round_id: roundId, p_word: word });
const count = (user: TestUser, roundId: string) => user.as.mutation(api.mindMeld.count_mind_meld_round, { p_round_id: roundId });
const restart = (user: TestUser, gameId: string) => user.as.mutation(api.mindMeld.restart_mind_meld, { p_game_id: gameId });
const history = (user: TestUser, limit = 30, before: number | null = null) =>
  user.as.query(api.mindMeld.get_mind_meld_history, { p_before_game_number: before, p_limit: limit });
const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());

async function current(user: TestUser) {
  const data = await view(user);
  return data.current!;
}

/** The open round of the game in play. */
async function openRound(user: TestUser) {
  const round = (await current(user)).rounds.at(-1)!;
  expect(round.state).toBe("open");
  return round;
}

/** `a` locks in `wordA` and then `b` locks in `wordB`, which reveals the round. */
async function playRound(s: Setup, wordA: string, wordB: string) {
  const round = await openRound(s.a);
  await lock(s.a, round.id, wordA);
  const result = await lock(s.b, round.id, wordB);
  return { round, result };
}

const A_WORDS = ["apple", "bridge", "candle", "dragon", "engine", "forest", "garden", "harbor", "island", "jungle"];
const B_WORDS = ["kettle", "ladder", "magnet", "needle", "orange", "pencil", "quartz", "rocket", "silver", "tunnel"];

describe("access", () => {
  test("a user without a couple cannot use Mind Meld", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect((await failure(loner.as.mutation(api.mindMeld.start_mind_meld_game, {}))).code).toBe("42501");
    expect((await failure(loner.as.query(api.mindMeld.get_mind_meld, {}))).code).toBe("42501");
    expect((await failure(history(loner))).code).toBe("42501");
  });

  test("a couple without a subscription cannot use Mind Meld", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(couple.first.as.mutation(api.mindMeld.start_mind_meld_game, {}))).code).toBe("42501");
    expect((await failure(couple.first.as.query(api.mindMeld.get_mind_meld, {}))).code).toBe("42501");
  });

  test("another couple cannot touch a game, a round, or a word", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    const other = await createCouple(s.t);
    expect((await failure(lock(other.first, round.id, "ocean"))).code).toBe("42501");
    expect((await failure(count(other.first, round.id))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.mindMeld.mark_mind_meld_reveal_seen, { p_round_id: round.id }))).code).toBe("42501");
    expect((await failure(other.first.as.mutation(api.mindMeld.mark_mind_meld_end_seen, { p_game_id: s.gameId }))).code).toBe("42501");
    expect((await failure(restart(other.first, s.gameId))).code).toBe("42501");
    expect((await failure(lock(other.first, newUuid(), "ocean"))).code).toBe("42501");
    expect((await other.first.as.query(api.mindMeld.get_mind_meld, {})).current).toBeNull();
  });

  test("a partner who left cannot play after the relationship ends", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect((await failure(lock(s.b, round.id, "ocean"))).code).toBe("42501");
    expect((await failure(s.b.as.query(api.mindMeld.get_mind_meld, {}))).code).toBe("42501");
  });

  test("a pending account deletion blocks writes", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
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
    expect((await failure(lock(s.a, round.id, "ocean"))).message).toMatch(/account deletion/);
    expect((await failure(count(s.a, round.id))).message).toMatch(/account deletion/);
    expect((await failure(restart(s.a, s.gameId))).message).toMatch(/account deletion/);
    expect((await failure(s.a.as.mutation(api.mindMeld.start_mind_meld_game, {}))).message).toMatch(/account deletion/);
    expect((await failure(s.a.as.mutation(api.mindMeld.mark_mind_meld_end_seen, { p_game_id: s.gameId }))).message).toMatch(/account deletion/);
  });
});

describe("start_mind_meld_game", () => {
  test("starts game 1 with an open round 1, and repeating it returns the same game", async () => {
    const t = newTest();
    scheduled = t;
    const { first: a, second: b } = await createCouple(t);
    expect(await view(a)).toMatchObject({ current: null, previous: null, stats: { melds: 0, fewest_rounds: null, games: 0 } });

    const started = await a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    expect(started.created).toBe(true);
    expect(await b.as.mutation(api.mindMeld.start_mind_meld_game, {})).toEqual({ game_id: started.game_id, created: false });
    expect(await a.as.mutation(api.mindMeld.start_mind_meld_game, {})).toEqual({ game_id: started.game_id, created: false });

    const data = await view(b);
    expect(data).toMatchObject({ user_id: b.userId, partner_user_id: a.userId, previous: null });
    expect(data.current).toMatchObject({
      id: started.game_id,
      game_number: 1,
      state: "playing",
      end_reason: null,
      ended_by_user_id: null,
      ended_at: null,
      max_rounds: 10,
      my_end_seen_at: null,
      meld_number: null,
      is_record: false,
      created_by_user_id: a.userId,
      version: 1,
    });
    expect(data.current!.rounds).toHaveLength(1);
    expect(data.current!.rounds[0]).toEqual({
      id: expect.any(String),
      round_number: 1,
      state: "open",
      outcome: null,
      counted_by_user_id: null,
      my_word: null,
      my_locked_at: null,
      partner_locked: false,
      partner_locked_at: null,
      partner_word: null,
      revealed_at: null,
      my_reveal_seen_at: null,
    });
    expect(await t.run((ctx) => ctx.db.query("mind_meld_games").collect())).toHaveLength(1);
  });

  test("starts the next game once the last one finished", async () => {
    const s = await startGame();
    await playRound(s, "fish", "fish");
    const next = await s.b.as.mutation(api.mindMeld.start_mind_meld_game, {});
    expect(next.created).toBe(true);
    expect(next.game_id).not.toBe(s.gameId);
    expect((await current(s.a)).game_number).toBe(2);
    expect((await current(s.a)).rounds).toHaveLength(1);
  });
});

describe("lock_mind_meld_word", () => {
  test("the partner learns that a word is locked in, never the word", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    const locked = await lock(s.a, round.id, "  Volcano ");
    expect(locked).toEqual({ round_id: round.id, round_state: "open", outcome: null, game_state: "playing", locked_at: new Date(START).toISOString() });

    const mine = (await current(s.a)).rounds[0];
    expect(mine).toMatchObject({ my_word: "Volcano", my_locked_at: locked.locked_at, partner_locked: false, partner_word: null });
    const theirs = (await current(s.b)).rounds[0];
    expect(theirs).toMatchObject({
      state: "open",
      my_word: null,
      my_locked_at: null,
      partner_locked: true,
      partner_locked_at: locked.locked_at,
      partner_word: null,
    });
    expect(JSON.stringify(await view(s.b))).not.toContain("Volcano");
    expect(JSON.stringify(await view(s.b)).toLowerCase()).not.toContain("volcano");
    expect(JSON.stringify(await history(s.b))).not.toContain("Volcano");
  });

  test("the second lock-in reveals both words to both partners", async () => {
    const s = await startGame();
    const { round, result } = await playRound(s, "Ocean", "Sushi");
    expect(result).toMatchObject({ round_id: round.id, round_state: "revealed", outcome: "miss", game_state: "playing" });
    for (const [user, mine, theirs] of [
      [s.a, "Ocean", "Sushi"],
      [s.b, "Sushi", "Ocean"],
    ] as const) {
      const shown = (await current(user)).rounds[0];
      expect(shown).toMatchObject({
        state: "revealed",
        outcome: "miss",
        my_word: mine,
        partner_word: theirs,
        partner_locked: true,
        revealed_at: result.locked_at,
        counted_by_user_id: null,
      });
    }
  });

  test("a match melds the game and opens no next round", async () => {
    const s = await startGame();
    const { result } = await playRound(s, "Ice cream", "icecream");
    expect(result).toMatchObject({ round_state: "revealed", outcome: "match", game_state: "melded" });
    const game = await current(s.a);
    expect(game).toMatchObject({ state: "melded", end_reason: null, ended_at: result.locked_at, meld_number: 1, is_record: false });
    expect(game.rounds).toHaveLength(1);
    expect((await view(s.b)).stats).toEqual({ melds: 1, fewest_rounds: 1, games: 1 });
    // The game is over, so the round takes no more words.
    expect((await failure(lock(s.a, game.rounds[0].id, "again"))).message).toBe("this round is already finished");
  });

  test("a miss opens round 2, and a near miss does too", async () => {
    const s = await startGame();
    expect((await playRound(s, "Ocean", "Sushi")).result.game_state).toBe("playing");
    const second = (await current(s.a)).rounds;
    expect(second.map((round) => [round.round_number, round.state])).toEqual([[1, "revealed"], [2, "open"]]);
    const near = await playRound(s, "dog", "dogs");
    expect(near.result).toMatchObject({ outcome: "near", game_state: "playing" });
    expect((await current(s.a)).rounds.map((round) => [round.round_number, round.state, round.outcome])).toEqual([
      [1, "revealed", "miss"],
      [2, "revealed", "near"],
      [3, "open", null],
    ]);
  });

  test("ten rounds without a match end the game", async () => {
    const s = await startGame();
    let last;
    for (let i = 0; i < 10; i += 1) last = await playRound(s, A_WORDS[i], B_WORDS[i]);
    expect(last!.result).toMatchObject({ round_state: "revealed", outcome: "miss", game_state: "ended" });
    const game = await current(s.b);
    expect(game).toMatchObject({ state: "ended", end_reason: "rounds", ended_by_user_id: null, ended_at: last!.result.locked_at, meld_number: null });
    expect(game.rounds).toHaveLength(10);
    expect(game.rounds.every((round) => round.state === "revealed")).toBe(true);
    expect((await view(s.a)).stats).toEqual({ melds: 0, fewest_rounds: null, games: 1 });
    expect((await failure(lock(s.a, game.rounds[9].id, "extra"))).message).toBe("this round is already finished");
  });

  test("a match in round 10 melds the game", async () => {
    const s = await startGame();
    for (let i = 0; i < 9; i += 1) await playRound(s, A_WORDS[i], B_WORDS[i]);
    const last = await playRound(s, "finale", "Finale");
    expect(last.result).toMatchObject({ outcome: "match", game_state: "melded" });
    expect((await view(s.a)).stats).toEqual({ melds: 1, fewest_rounds: 10, games: 1 });
  });

  test("a word either partner said in a revealed round cannot be used again", async () => {
    const s = await startGame();
    await playRound(s, "Ocean", "Sushi");
    const round = await openRound(s.a);
    const used = "that word was already used in this game";
    for (const [user, word] of [
      [s.a, "ocean"],
      [s.a, "OCEAN "],
      [s.a, "sushi"],
      [s.b, "o cean"],
      [s.b, "Sushi"],
    ] as const) {
      expect((await failure(lock(user, round.id, word))).message).toBe(used);
    }
    expect((await failure(lock(s.a, round.id, "ocean"))).code).toBe("23514");
    expect((await current(s.a)).rounds[1].my_word).toBeNull();
    // A near miss of an earlier word is fine.
    await lock(s.a, round.id, "oceans");
    expect((await current(s.a)).rounds[1].my_word).toBe("oceans");
  });

  test("the partner's word in the open round is not a repeat, so the couple can meld", async () => {
    const s = await startGame();
    await playRound(s, "Ocean", "Sushi");
    const { result } = await playRound(s, "Fish", "fish");
    expect(result).toMatchObject({ outcome: "match", game_state: "melded" });
    expect((await view(s.a)).stats).toEqual({ melds: 1, fewest_rounds: 2, games: 1 });
  });

  test("a word from an earlier game can be used again", async () => {
    const s = await startGame();
    await playRound(s, "Fish", "fish");
    await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    const { result } = await playRound(s, "fish", "Fish");
    expect(result.outcome).toBe("match");
  });

  test("refuses words that break the rules", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    const length = "word must be 1 to 30 characters in at most three words";
    const cases: [string, string][] = [
      ["", length],
      ["   ", length],
      ["a".repeat(31), length],
      ["one two three four", length],
      ["12345", "word must contain a letter"],
      ["- - -", "word must contain a letter"],
      ["wow!", "word has characters that are not allowed"],
      ["a_b", "word has characters that are not allowed"],
      ["smile 😀", "word has characters that are not allowed"],
    ];
    for (const [word, message] of cases) {
      const error = await failure(lock(s.a, round.id, word));
      expect(error).toEqual({ code: "23514", message });
    }
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_words").collect())).toHaveLength(0);
    // Letters of any alphabet, a phrase, and a hyphen are fine, with single spaces stored.
    await lock(s.a, round.id, "  New    York ");
    await lock(s.b, round.id, "дом-2");
    expect((await current(s.a)).rounds[0]).toMatchObject({ my_word: "New York", partner_word: "дом-2" });
  });

  test("a word of another alphabet reveals and compares", async () => {
    const s = await startGame();
    expect((await playRound(s, "Дом", "кот")).result.outcome).toBe("miss");
    expect((await playRound(s, "Река", "река")).result).toMatchObject({ outcome: "match", game_state: "melded" });
  });

  test("locks in once per round", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    await lock(s.a, round.id, "ocean");
    const again = await failure(lock(s.a, round.id, "sea"));
    expect(again).toEqual({ code: "23505", message: "you already locked in a word this round" });
    expect((await current(s.a)).rounds[0].my_word).toBe("ocean");
    await lock(s.b, round.id, "sushi");
    expect((await failure(lock(s.b, round.id, "rice"))).message).toBe("this round is already finished");
  });

  test("a replay of the same operation returns the stored result and does not lock in twice", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    const args = op();
    const first = await lock(s.a, round.id, "ocean", args);
    expect(await lock(s.a, round.id, " ocean ", args)).toEqual(first);
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_words").collect())).toHaveLength(1);
    expect(await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect())).toHaveLength(1);
    expect((await failure(lock(s.a, round.id, "Ocean", args))).message).toContain("replay hash mismatch");

    // The stored result stays what the first call saw, even after the round revealed.
    await lock(s.b, round.id, "sushi");
    expect(await lock(s.a, round.id, "ocean", args)).toEqual(first);
  });

  test("a bad round id is refused", async () => {
    const s = await startGame();
    expect((await failure(lock(s.a, "not-a-uuid", "ocean"))).code).toBe("22P02");
    expect((await failure(lock(s.a, newUuid(), "ocean"))).code).toBe("42501");
  });

  test("accepts an uppercase round id", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    const locked = await lock(s.a, round.id.toUpperCase(), "ocean");
    expect(locked.round_id).toBe(round.id);
  });
});

describe("count_mind_meld_round", () => {
  test("counts a near miss as a match and removes the open round with its locked word", async () => {
    const s = await startGame();
    const { round } = await playRound(s, "dog", "dogs");
    const next = await openRound(s.a);
    await lock(s.b, next.id, "cat");
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_words").collect())).toHaveLength(3);

    tick(60);
    const counted = await count(s.a, round.id);
    expect(counted).toEqual({ round_id: round.id, game_id: s.gameId, game_state: "melded" });
    const game = await current(s.b);
    expect(game).toMatchObject({ state: "melded", end_reason: null, ended_at: new Date().toISOString(), meld_number: 1 });
    expect(game.rounds).toHaveLength(1);
    expect(game.rounds[0]).toMatchObject({ outcome: "near", counted_by_user_id: s.a.userId, my_word: "dogs", partner_word: "dog" });
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_words").collect())).toHaveLength(2);
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_rounds").collect())).toHaveLength(1);
    expect((await view(s.a)).stats).toEqual({ melds: 1, fewest_rounds: 1, games: 1 });
    // The deleted round takes no more words.
    expect((await failure(lock(s.a, next.id, "bird"))).code).toBe("42501");
  });

  test("is safe to repeat, from either partner, and changes nothing the second time", async () => {
    const s = await startGame();
    const { round } = await playRound(s, "dog", "dogs");
    await count(s.a, round.id);
    const version = (await current(s.a)).version;
    const endedAt = (await current(s.a)).ended_at;
    tick(5);
    expect(await count(s.a, round.id)).toEqual({ round_id: round.id, game_id: s.gameId, game_state: "melded" });
    expect(await count(s.b, round.id)).toEqual({ round_id: round.id, game_id: s.gameId, game_state: "melded" });
    expect(await current(s.b)).toMatchObject({ version, ended_at: endedAt });
    expect((await current(s.b)).rounds[0].counted_by_user_id).toBe(s.a.userId);
  });

  test("counts a near miss in round 10 after the game ended", async () => {
    const s = await startGame();
    for (let i = 0; i < 9; i += 1) await playRound(s, A_WORDS[i], B_WORDS[i]);
    const { round, result } = await playRound(s, "house", "horse");
    expect(result).toMatchObject({ outcome: "near", game_state: "ended" });
    expect((await current(s.a)).state).toBe("ended");
    await count(s.b, round.id);
    expect(await current(s.a)).toMatchObject({ state: "melded", end_reason: null, meld_number: 1 });
    expect((await view(s.a)).stats).toEqual({ melds: 1, fewest_rounds: 10, games: 1 });
  });

  test("refuses a miss, a match, an open round, and a round that is not the latest", async () => {
    const s = await startGame();
    const cannot = { code: "23514", message: "this round can't be counted" };
    const first = (await playRound(s, "house", "horse")).round;
    const second = (await playRound(s, "Ocean", "Sushi")).round;
    expect(await failure(count(s.a, second.id))).toEqual(cannot);
    // Round 1 was a near miss, but round 2 is the latest revealed round.
    expect(await failure(count(s.a, first.id))).toEqual(cannot);
    const open = await openRound(s.a);
    expect(await failure(count(s.a, open.id))).toEqual(cannot);

    const matched = await startGame();
    const { round } = await playRound(matched, "fish", "fish");
    expect(await failure(count(matched.a, round.id))).toEqual(cannot);
  });

  test("refuses a round of a game that was started over", async () => {
    const s = await startGame();
    const { round } = await playRound(s, "dog", "dogs");
    await restart(s.a, s.gameId);
    expect(await failure(count(s.b, round.id))).toEqual({ code: "23514", message: "this round can't be counted" });
  });
});

describe("streak", () => {
  test("each lock-in counts once per person and round", async () => {
    const s = await startGame();
    const { round } = await playRound(s, "Ocean", "Sushi");
    const events = await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect());
    expect(events.map((event) => event.dedupe_key).sort()).toEqual(
      [`game_turn_completed:${round.id}:${s.a.userId}`, `game_turn_completed:${round.id}:${s.b.userId}`].sort(),
    );
    expect(events.every((event) => event.activity_kind === "game_turn_completed")).toBe(true);
    expect(events.map((event) => event.user_id).sort()).toEqual([s.a.userId, s.b.userId].sort());

    const next = await openRound(s.a);
    await lock(s.a, next.id, "salt");
    expect(await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect())).toHaveLength(3);
  });

  test("both partners locking in on one day qualify the streak", async () => {
    const s = await startGame();
    await playRound(s, "Ocean", "Sushi");
    const streak = await s.t.run((ctx) => ctx.db.query("streak_states").first());
    expect(streak?.current_count).toBe(1);
  });

  test("a refused lock-in does not count", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    await failure(lock(s.a, round.id, "wow!"));
    await lock(s.a, round.id, "ocean");
    await failure(lock(s.a, round.id, "sea"));
    expect(await s.t.run((ctx) => ctx.db.query("couple_activity_events").collect())).toHaveLength(1);
  });
});

describe("pushes", () => {
  const rowsOf = async (s: Setup, kind: string) => (await outbox(s.t)).filter((row) => row.kind === kind);

  test("the first lock-in tells the partner it is their turn", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    await lock(s.a, round.id, "Volcano");
    const rows = await outbox(s.t);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      kind: "game_turn_ready",
      recipient_user_id: s.b.userId,
      // The outbox adds the recipient's device to the key.
      dedupe_key: expect.stringContaining(`game_turn_ready:${round.id}`),
      payload: {
        type: "game_turn_ready",
        game_kind: "mind_meld",
        couple_id: s.couple.coupleId,
        game_id: s.gameId,
        round_id: round.id,
        actor_user_id: s.a.userId,
        route: "games",
        deeplink: "paeonia://games/mind-meld",
      },
    });
  });

  test("the second lock-in tells the first partner the words are in, without a word or the outcome", async () => {
    const s = await startGame();
    const { round } = await playRound(s, "Volcano", "Pizza");
    const results = await rowsOf(s, "game_result");
    expect(results).toHaveLength(1);
    expect(results[0]).toMatchObject({
      recipient_user_id: s.a.userId,
      dedupe_key: expect.stringContaining(`game_result:${round.id}`),
      payload: { type: "game_result", game_kind: "mind_meld", round_id: round.id, actor_user_id: s.b.userId, deeplink: "paeonia://games/mind-meld" },
    });
    expect(await rowsOf(s, "game_turn_ready")).toHaveLength(1);
    expect(JSON.stringify(await outbox(s.t))).not.toMatch(/volcano|pizza|miss|match/i);
  });

  test("a meld sends the same result push", async () => {
    const s = await startGame();
    await playRound(s, "fish", "fish");
    expect((await rowsOf(s, "game_result")).map((row) => row.recipient_user_id)).toEqual([s.a.userId]);
  });

  test("no push while the partner has the game open", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    const round = await openRound(s.a);
    await lock(s.a, round.id, "ocean");
    expect(await outbox(s.t)).toHaveLength(0);

    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "mind_meld", p_present: true });
    await lock(s.b, round.id, "sushi");
    expect(await outbox(s.t)).toHaveLength(0);
  });

  test("the Games switch turns the pushes off", async () => {
    const s = await startGame();
    await s.b.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    const round = await openRound(s.a);
    await lock(s.a, round.id, "ocean");
    expect(await outbox(s.t)).toHaveLength(0);
  });

  describe("drain", () => {
    const claim = (s: Setup) => s.t.mutation(internal.pushQueue.claim_notification_batch, {});
    const types = (rows: { payload: unknown }[]) => rows.map((row) => (row.payload as { type: string }).type).sort();
    const errorsOf = async (s: Setup, kind: string) => (await rowsOf(s, kind)).map((row) => row.last_error ?? null);

    test("a turn push goes out while the partner still has to lock in", async () => {
      const s = await startGame();
      await lock(s.a, (await openRound(s.a)).id, "ocean");
      expect(types(await claim(s))).toEqual(["game_turn_ready"]);
    });

    test("a turn push is dropped once the recipient locked in, and the result push still goes out", async () => {
      const s = await startGame();
      await playRound(s, "ocean", "sushi");
      expect(types(await claim(s))).toEqual(["game_result"]);
      expect(await errorsOf(s, "game_turn_ready")).toEqual(["notification is out of date"]);
    });

    test("a result push is dropped once the recipient saw the reveal", async () => {
      const s = await startGame();
      const { round } = await playRound(s, "ocean", "sushi");
      await s.a.as.mutation(api.mindMeld.mark_mind_meld_reveal_seen, { p_round_id: round.id });
      expect(await claim(s)).toEqual([]);
      expect(await errorsOf(s, "game_result")).toEqual(["notification is out of date"]);
    });

    test("a turn push is dropped when the game was started over", async () => {
      const s = await startGame();
      await lock(s.a, (await openRound(s.a)).id, "ocean");
      await restart(s.b, s.gameId);
      expect(await claim(s)).toEqual([]);
      expect(await errorsOf(s, "game_turn_ready")).toEqual(["notification is out of date"]);
    });

    test("a turn push is dropped when the round went away", async () => {
      const s = await startGame();
      const { round } = await playRound(s, "dog", "dogs");
      await lock(s.b, (await openRound(s.a)).id, "cat");
      await count(s.a, round.id);
      expect(types(await claim(s))).toEqual(["game_result"]);
      expect(await errorsOf(s, "game_turn_ready")).toEqual(["notification is out of date", "notification is out of date"]);
    });

    test("drops every push queued before the relationship ended", async () => {
      const s = await startGame();
      await lock(s.a, (await openRound(s.a)).id, "ocean");
      await endCouple(s.t, s.couple.coupleId, s.a.userId);
      expect(await claim(s)).toEqual([]);
      expect(await errorsOf(s, "game_turn_ready")).toEqual(["notification target is no longer eligible"]);
    });
  });
});

describe("turn reminder", () => {
  const run = (s: Setup) => s.t.mutation(internal.mindMeld.send_due_mind_meld_reminders, {});
  const reminders = async (s: Setup) => (await outbox(s.t)).filter((row) => row.kind === "game_turn_reminder");

  test("goes out once, 72 hours after the first lock-in, to the partner who has not locked in", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    // Nobody locked in yet, so nobody waits.
    tick(100 * 3600);
    expect(await run(s)).toBe(0);

    await lock(s.a, round.id, "ocean");
    tick(71 * 3600);
    expect(await run(s)).toBe(0);
    tick(3600);
    expect(await run(s)).toBe(1);
    expect(await run(s)).toBe(0);
    tick(10 * 3600);
    expect(await run(s)).toBe(0);

    const rows = await reminders(s);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.b.userId,
      dedupe_key: expect.stringContaining(`game_turn_reminder:${round.id}`),
      payload: {
        type: "game_turn_reminder",
        game_kind: "mind_meld",
        game_id: s.gameId,
        round_id: round.id,
        actor_user_id: s.a.userId,
        deeplink: "paeonia://games/mind-meld",
      },
    });
    const stored = await s.t.run((ctx) => ctx.db.query("mind_meld_rounds").collect());
    expect(stored[0].reminder_sent_at).toBeDefined();
  });

  test("the shared reminder cron sends it too", async () => {
    const s = await startGame();
    await lock(s.a, (await openRound(s.a)).id, "ocean");
    tick(73 * 3600);
    expect(await s.t.mutation(internal.games.send_due_game_turn_reminders, {})).toBe(1);
    expect(await reminders(s)).toHaveLength(1);
    expect(await run(s)).toBe(0);
  });

  test("the next round gets its own reminder", async () => {
    const s = await startGame();
    await playRound(s, "ocean", "sushi");
    const next = await openRound(s.a);
    await lock(s.b, next.id, "salt");
    tick(73 * 3600);
    expect(await run(s)).toBe(1);
    expect((await reminders(s)).map((row) => row.recipient_user_id)).toEqual([s.a.userId]);
  });

  test("counts as a change to the game, so the version goes up", async () => {
    const s = await startGame();
    await lock(s.a, (await openRound(s.a)).id, "ocean");
    const before = await current(s.b);
    tick(73 * 3600);
    expect(await run(s)).toBe(1);
    const after = await current(s.b);
    expect(after.version).toBe(before.version + 1);
    expect(after.updated_at).toBe(new Date().toISOString());
  });

  test("a revealed round is never reminded", async () => {
    const s = await startGame();
    await playRound(s, "ocean", "sushi");
    tick(100 * 3600);
    expect(await run(s)).toBe(0);
    expect(await reminders(s)).toHaveLength(0);
  });

  test("a game that was started over is never reminded", async () => {
    const s = await startGame();
    await lock(s.a, (await openRound(s.a)).id, "ocean");
    await restart(s.b, s.gameId);
    tick(100 * 3600);
    expect(await run(s)).toBe(0);
    expect(await reminders(s)).toHaveLength(0);
  });

  test("a couple that is no longer active is never reminded, and the round is marked", async () => {
    const s = await startGame();
    await lock(s.a, (await openRound(s.a)).id, "ocean");
    await endCouple(s.t, s.couple.coupleId, s.b.userId);
    tick(100 * 3600);
    expect(await run(s)).toBe(0);
    expect(await reminders(s)).toHaveLength(0);
    expect((await s.t.run((ctx) => ctx.db.query("mind_meld_rounds").collect()))[0].reminder_sent_at).toBeDefined();
  });

  test("the Games switch stops the reminder", async () => {
    const s = await startGame();
    await lock(s.a, (await openRound(s.a)).id, "ocean");
    await s.b.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    tick(80 * 3600);
    expect(await run(s)).toBe(0);
  });
});

describe("restart_mind_meld", () => {
  test("ends the game in play and starts a new one", async () => {
    const s = await startGame();
    await playRound(s, "ocean", "sushi");
    const result = await restart(s.a, s.gameId);
    expect(result.created).toBe(true);
    expect(result.game_id).not.toBe(s.gameId);

    const data = await view(s.a);
    expect(data.current).toMatchObject({ id: result.game_id, game_number: 2, state: "playing", my_end_seen_at: null });
    expect(data.current!.rounds).toHaveLength(1);
    expect(data.current!.rounds[0]).toMatchObject({ round_number: 1, state: "open" });
    // The caller started it over, so they have seen the end.
    expect(data.previous).toBeNull();
    const old = (await s.t.run((ctx) => ctx.db.query("mind_meld_games").collect())).find((game) => game.id === s.gameId)!;
    expect(old).toMatchObject({ state: "ended", end_reason: "restart", ended_by_user_id: s.a.userId, ended_at: new Date().toISOString() });
    expect(Object.keys(old.end_seen_by_user)).toEqual([s.a.userId]);
  });

  test("the partner sees the old game as previous until they see its end", async () => {
    const s = await startGame();
    await playRound(s, "ocean", "sushi");
    const open = await openRound(s.a);
    await lock(s.b, open.id, "salt");
    const result = await restart(s.a, s.gameId);

    const data = await view(s.b);
    expect(data.current!.id).toBe(result.game_id);
    expect(data.previous).toMatchObject({
      id: s.gameId,
      game_number: 1,
      state: "ended",
      end_reason: "restart",
      ended_by_user_id: s.a.userId,
      my_end_seen_at: null,
    });
    // b's word for the open round is b's own and the other side never learns it.
    expect(data.previous!.rounds[1]).toMatchObject({ state: "open", my_word: "salt", partner_word: null, partner_locked: false });
    expect((await view(s.a)).previous).toBeNull();

    tick(30);
    const seen = await s.b.as.mutation(api.mindMeld.mark_mind_meld_end_seen, { p_game_id: s.gameId });
    expect(seen.end_seen_at).toBe(new Date().toISOString());
    expect((await view(s.b)).previous).toBeNull();
  });

  test("the word locked in for the open round is never revealed", async () => {
    const s = await startGame();
    await lock(s.a, (await openRound(s.a)).id, "secret");
    await restart(s.b, s.gameId);
    const old = (await history(s.b)).games[0];
    expect(old).toMatchObject({ id: s.gameId, state: "ended", end_reason: "restart", rounds: [] });
    expect(JSON.stringify(await history(s.b))).not.toContain("secret");
    expect(JSON.stringify(await view(s.b))).not.toContain("secret");
    expect((await view(s.a)).previous).toMatchObject({ id: s.gameId });
    expect(JSON.stringify((await view(s.a)).previous!.rounds[0].partner_word)).toBe("null");
  });

  test("a lock-in for the old round is refused afterwards", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    await restart(s.a, s.gameId);
    expect(await failure(lock(s.b, round.id, "ocean"))).toEqual({ code: "23514", message: "this round is already finished" });
  });

  test("the other partner's tap on the same game returns the new game instead of starting a third", async () => {
    const s = await startGame();
    const first = await restart(s.a, s.gameId);
    expect(await restart(s.b, s.gameId)).toEqual({ game_id: first.game_id, created: false });
    expect(await restart(s.a, s.gameId)).toEqual({ game_id: first.game_id, created: false });
    expect(await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {})).toEqual({ game_id: first.game_id, created: false });
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_games").collect())).toHaveLength(2);
  });

  test("play again after a finished game starts a new game once, and the partner joins it", async () => {
    const s = await startGame();
    await playRound(s, "fish", "fish");
    const again = await restart(s.b, s.gameId);
    expect(again.created).toBe(true);
    expect(await restart(s.a, s.gameId)).toEqual({ game_id: again.game_id, created: false });
    expect((await current(s.a)).game_number).toBe(2);
    // a never marked the end of game 1 as seen, so it is still previous for a.
    expect((await view(s.a)).previous).toMatchObject({ id: s.gameId, state: "melded" });
  });

  test("a stale id of an older finished game starts the game after the newest", async () => {
    const s = await startGame();
    await playRound(s, "fish", "fish");
    const second = await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    await playRound(s, "salt", "salt");
    const third = await restart(s.b, s.gameId);
    expect(third.created).toBe(true);
    expect(third.game_id).not.toBe(second.game_id);
    expect((await current(s.a)).game_number).toBe(3);
  });
});

describe("seen marks", () => {
  test("a reveal is seen per person and keeps the first time", async () => {
    const s = await startGame();
    const { round } = await playRound(s, "ocean", "sushi");
    const mark = (user: TestUser) => user.as.mutation(api.mindMeld.mark_mind_meld_reveal_seen, { p_round_id: round.id });

    const first = await mark(s.a);
    expect(first).toEqual({ round_id: round.id, reveal_seen_at: new Date().toISOString() });
    tick(60);
    expect(await mark(s.a)).toEqual(first);
    expect((await current(s.a)).rounds[0].my_reveal_seen_at).toBe(first.reveal_seen_at);
    expect((await current(s.b)).rounds[0].my_reveal_seen_at).toBeNull();
    const second = await mark(s.b);
    expect(second.reveal_seen_at).toBe(new Date().toISOString());
    expect((await current(s.b)).rounds[0].my_reveal_seen_at).toBe(second.reveal_seen_at);
  });

  test("a round that is not revealed cannot be marked", async () => {
    const s = await startGame();
    const round = await openRound(s.a);
    await lock(s.a, round.id, "ocean");
    expect(await failure(s.a.as.mutation(api.mindMeld.mark_mind_meld_reveal_seen, { p_round_id: round.id }))).toEqual({
      code: "23514",
      message: "the round is not revealed yet",
    });
  });

  test("an ending is seen per person and keeps the first time", async () => {
    const s = await startGame();
    const mark = (user: TestUser) => user.as.mutation(api.mindMeld.mark_mind_meld_end_seen, { p_game_id: s.gameId });
    expect((await failure(mark(s.a))).code).toBe("23514");
    await playRound(s, "fish", "fish");

    const first = await mark(s.a);
    expect(first).toEqual({ game_id: s.gameId, end_seen_at: new Date().toISOString() });
    tick(60);
    expect(await mark(s.a)).toEqual(first);
    expect((await current(s.a)).my_end_seen_at).toBe(first.end_seen_at);
    expect((await current(s.b)).my_end_seen_at).toBeNull();
    expect((await mark(s.b)).end_seen_at).toBe(new Date().toISOString());
  });
});

describe("version", () => {
  test("goes up with every change to the game, its rounds, and its words", async () => {
    const s = await startGame();
    const versions: number[] = [(await current(s.a)).version];
    const note = async () => versions.push((await current(s.a)).version);

    const round = await openRound(s.a);
    await lock(s.a, round.id, "ocean");
    await note();
    await lock(s.b, round.id, "sushi");
    await note();
    await s.a.as.mutation(api.mindMeld.mark_mind_meld_reveal_seen, { p_round_id: round.id });
    await note();
    const next = await openRound(s.a);
    await lock(s.a, next.id, "dog");
    await note();
    await lock(s.b, next.id, "dogs");
    await note();
    await count(s.a, next.id);
    await note();
    await s.a.as.mutation(api.mindMeld.mark_mind_meld_end_seen, { p_game_id: s.gameId });
    await note();
    expect(versions).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test("a change to the previous game also bumps the newest game", async () => {
    const s = await startGame();
    await playRound(s, "fish", "fish");
    await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    const before = await view(s.b);
    expect(before.current!.version).toBe(1);

    await s.b.as.mutation(api.mindMeld.mark_mind_meld_end_seen, { p_game_id: s.gameId });
    const after = await view(s.b);
    expect(after.current!.version).toBe(2);
    expect(after.previous).toBeNull();
    const old = (await s.t.run((ctx) => ctx.db.query("mind_meld_games").collect())).find((game) => game.id === s.gameId)!;
    expect(old.version).toBe(4);
  });

  test("a restart bumps the ended game and starts the new one at 1", async () => {
    const s = await startGame();
    const result = await restart(s.a, s.gameId);
    const games = await s.t.run((ctx) => ctx.db.query("mind_meld_games").collect());
    expect(games.find((game) => game.id === s.gameId)!.version).toBe(2);
    expect(games.find((game) => game.id === result.game_id)!.version).toBe(1);
  });

  test("updated_at follows the change", async () => {
    const s = await startGame();
    tick(120);
    await lock(s.a, (await openRound(s.a)).id, "ocean");
    expect((await current(s.a)).updated_at).toBe(new Date().toISOString());
    expect((await current(s.a)).created_at).toBe(new Date(START).toISOString());
  });
});

describe("meld numbers and records", () => {
  test("number the melds in order and flag a meld with fewer rounds than every earlier one", async () => {
    const s = await startGame();
    await playRound(s, "ocean", "sushi");
    await playRound(s, "fish", "fish");
    const gameTwo = await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    await playRound(s, "salt", "pepper");
    await playRound(s, "bread", "butter");
    await playRound(s, "toast", "toast");
    const gameThree = await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    await playRound(s, "sun", "sun");
    const gameFour = await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    await playRound(s, "moon", "moon");

    const games = (await history(s.a)).games;
    const byId = (id: string) => games.find((game) => game.id === id)!;
    expect(games.map((game) => game.meld_number)).toEqual([4, 3, 2, 1]);
    expect(byId(s.gameId).rounds).toHaveLength(2);
    expect(byId(gameTwo.game_id).rounds).toHaveLength(3);
    expect((await view(s.a)).stats).toEqual({ melds: 4, fewest_rounds: 1, games: 4 });

    const current = (await view(s.a)).current!;
    expect(current).toMatchObject({ id: gameFour.game_id, meld_number: 4, is_record: false });
    expect((await view(s.a)).previous).toMatchObject({ id: gameThree.game_id, meld_number: 3, is_record: true });
    // The first meld is no record because nothing came before it, and a tie is not a record.
    expect(byId(s.gameId)).toMatchObject({ meld_number: 1 });
  });

  test("the first meld and a tie are not records", async () => {
    const s = await startGame();
    await playRound(s, "fish", "fish");
    expect((await current(s.a)).is_record).toBe(false);
    await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    await playRound(s, "salt", "salt");
    expect((await current(s.a)).is_record).toBe(false);
    expect((await current(s.a)).meld_number).toBe(2);
  });

  test("a counted near miss is a meld in the round it was counted", async () => {
    const s = await startGame();
    await playRound(s, "ocean", "sushi");
    const { round } = await playRound(s, "dog", "dogs");
    await count(s.a, round.id);
    expect((await view(s.a)).stats).toEqual({ melds: 1, fewest_rounds: 2, games: 1 });
  });
});

describe("get_mind_meld_history", () => {
  /** Game 1 melds in two rounds, game 2 is started over after one round, game 3 is still in play. */
  async function playedGames() {
    const s = await startGame();
    await playRound(s, "ocean", "sushi");
    await playRound(s, "fish", "fish");
    const second = await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {});
    await playRound(s, "salt", "pepper");
    await lock(s.a, (await openRound(s.a)).id, "hidden");
    const third = await restart(s.b, second.game_id);
    return { s, first: s.gameId, second: second.game_id, third: third.game_id };
  }

  test("lists finished games newest first with their revealed rounds, my word first", async () => {
    const { s, first, second, third } = await playedGames();
    const result = await history(s.a);
    expect(result.next_before_game_number).toBeNull();
    expect(result.stats).toEqual({ melds: 1, fewest_rounds: 2, games: 2 });
    expect(result.games.map((game) => [game.id, game.state, game.end_reason, game.meld_number])).toEqual([
      [second, "ended", "restart", null],
      [first, "melded", null, 1],
    ]);
    expect(result.games.some((game) => game.id === third)).toBe(false);

    const [ended, melded] = result.games;
    expect(ended).toMatchObject({ game_number: 2, ended_by_user_id: s.b.userId, rounds: [{ round_number: 1, my_word: "salt", partner_word: "pepper", outcome: "miss", counted_by_user_id: null }] });
    expect(ended.ended_at).toBeTruthy();
    expect(melded.rounds).toEqual([
      { round_number: 1, my_word: "ocean", partner_word: "sushi", outcome: "miss", counted_by_user_id: null },
      { round_number: 2, my_word: "fish", partner_word: "fish", outcome: "match", counted_by_user_id: null },
    ]);
    expect(Object.keys(melded).sort()).toEqual(
      ["created_at", "end_reason", "ended_at", "ended_by_user_id", "game_number", "id", "meld_number", "rounds", "state"].sort(),
    );

    const theirs = await history(s.b);
    expect(theirs.games[1].rounds[0]).toMatchObject({ my_word: "sushi", partner_word: "ocean" });
  });

  test("shows a counted near miss with who counted it", async () => {
    const s = await startGame();
    const { round } = await playRound(s, "dog", "dogs");
    await count(s.b, round.id);
    expect((await history(s.a)).games[0].rounds).toEqual([
      { round_number: 1, my_word: "dog", partner_word: "dogs", outcome: "near", counted_by_user_id: s.b.userId },
    ]);
  });

  test("pages by game number", async () => {
    const s = await startGame();
    const ids: string[] = [s.gameId];
    for (let i = 0; i < 4; i += 1) {
      await playRound(s, `word${String.fromCharCode(97 + i)}`, `word${String.fromCharCode(97 + i)}`);
      if (i < 3) ids.push((await s.a.as.mutation(api.mindMeld.start_mind_meld_game, {})).game_id);
    }
    const first = await history(s.a, 2);
    expect(first.games.map((game) => game.id)).toEqual([ids[3], ids[2]]);
    expect(first.next_before_game_number).toBe(3);
    const second = await history(s.a, 2, first.next_before_game_number);
    expect(second.games.map((game) => game.id)).toEqual([ids[1], ids[0]]);
    expect(second.next_before_game_number).toBeNull();
    expect((await history(s.a, 4)).next_before_game_number).toBeNull();
    expect((await history(s.a, 1000)).games).toHaveLength(4);
    expect((await history(s.a, 3, 2)).games.map((game) => game.game_number)).toEqual([1]);
  });

  test("refuses a limit under 1 and an empty history is empty", async () => {
    const s = await startGame();
    expect(await failure(history(s.a, 0))).toEqual({ code: "23514", message: "limit must be 1 or more" });
    expect((await failure(history(s.a, -3))).code).toBe("23514");
    expect(await history(s.a)).toEqual({ games: [], next_before_game_number: null, stats: { melds: 0, fewest_rounds: null, games: 0 } });
  });
});

describe("relationship cleanup", () => {
  test("the shared cleanup deletes the three tables for one couple only", async () => {
    const s = await startGame();
    await playRound(s, "ocean", "sushi");
    const other = await createCouple(s.t);
    await other.first.as.mutation(api.mindMeld.start_mind_meld_game, {});

    const deleted = await s.t.run((ctx) => deleteCoupleGameRows(ctx, s.couple.coupleId));
    // One game, two rounds, and two words.
    expect(deleted).toBe(5);
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_games").collect())).toHaveLength(1);
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_rounds").collect())).toHaveLength(1);
    expect(await s.t.run((ctx) => ctx.db.query("mind_meld_words").collect())).toHaveLength(0);
  });
});
