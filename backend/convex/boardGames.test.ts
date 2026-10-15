import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { rulesFor } from "./lib/boardGameStore";
import { movers, replay, type BoardGameKind } from "./lib/boardGames";
import { newUuid } from "./lib/ids";
import { notificationAlertBody, notificationAlertTitle } from "./lib/notificationCopy";
import { endCouple, failure, op, photo, setMediaEnv, uploadAsset } from "./media.testing";
import { deliverDuePushes } from "./push.testing";
import { addDevice, createCouple, createSignedInUser, newTest, type TestConvex, type TestCouple, type TestUser } from "./test.setup";

const START = Date.parse("2026-10-10T12:00:00.000Z");

beforeEach(() => {
  setMediaEnv();
  vi.useFakeTimers({ toFake: ["Date"] });
  vi.setSystemTime(new Date(START));
});
afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
});

const tick = (seconds = 10) => vi.setSystemTime(new Date(Date.now() + seconds * 1000));
const nowIso = () => new Date().toISOString();

type Setup = { t: TestConvex; couple: TestCouple; a: TestUser; b: TestUser; byId: Record<string, TestUser> };
type View = Awaited<ReturnType<typeof ensure>>;

/** A couple with game settings. `a` is the first partner. */
async function startCouple(): Promise<Setup> {
  const t = newTest();
  const couple = await createCouple(t);
  const { first: a, second: b } = couple;
  await a.as.mutation(api.games.set_game_settings, { p_play_style: "against", p_language: "en" });
  return { t, couple, a, b, byId: { [a.userId]: a, [b.userId]: b } };
}

function ensure(user: TestUser, kind: BoardGameKind) {
  return user.as.mutation(api.boardGames.ensure_board_game, { p_kind: kind });
}

const list = (user: TestUser) => user.as.query(api.boardGames.get_board_games, {});
const marks = (user: TestUser) => user.as.query(api.boardGames.get_board_game_marks, {});

async function gameOf(user: TestUser, kind: BoardGameKind): Promise<View> {
  const found = (await list(user)).games.find((game) => game.kind === kind);
  if (!found) throw new Error(`no ${kind} game`);
  return found;
}

function move(
  user: TestUser,
  game: Pick<View, "id" | "version">,
  cell: number,
  extra: { p_stake?: string | null; p_ludo_color?: "pink" | "lavender" | "gold" | "sky" | null } = {},
) {
  return user.as.mutation(api.boardGames.make_move, {
    ...op(),
    p_game_id: game.id,
    p_expected_version: game.version,
    p_move: cell,
    ...extra,
  });
}

function rematch(user: TestUser, game: Pick<View, "id" | "version">) {
  return user.as.mutation(api.boardGames.start_rematch, { ...op(), p_game_id: game.id, p_expected_version: game.version });
}

/** Plays `moves` after the moves `game` already has, each by the partner the rules say moves. Returns the last view. */
async function playMoves(s: Setup, game: View, moves: readonly number[]): Promise<View> {
  const players = movers(rulesFor(game.kind), [...game.moves, ...moves]);
  if (players === null) throw new Error("illegal move list");
  const first = s.byId[game.first_user_id];
  const second = first === s.a ? s.b : s.a;
  let current = game;
  for (const [index, cell] of moves.entries()) {
    current = await move(players[game.moves.length + index] === 1 ? first : second, current, cell);
  }
  return current;
}

/** What the rules say about a finished move list, to check the server against. */
function outcomeOf(kind: BoardGameKind, moves: readonly number[]) {
  const rules = rulesFor(kind);
  const state = replay(rules, moves);
  return state === null ? null : rules.outcome(state);
}

const activity = (t: TestConvex) => t.run((ctx) => ctx.db.query("couple_activity_events").collect());
const gameRows = (t: TestConvex) => t.run((ctx) => ctx.db.query("board_games").collect());

// Player one drops four discs in column 0 and wins. Player two plays column 1.
const CONNECT_FOUR_WIN = [0, 1, 0, 1, 0, 1, 0];
// Player two wins column 1 while player one wastes discs.
const CONNECT_FOUR_SECOND_PLAYER_WIN = [0, 1, 0, 1, 0, 1, 2, 1];
// Found by seeded random play. Fills all 42 cells and never makes four in a row.
const CONNECT_FOUR_DRAW = [
  0, 5, 4, 6, 0, 3, 5, 2, 5, 0, 1, 3, 1, 6, 6, 1, 0, 2, 4, 4, 2, 1, 5, 1, 3, 3, 0, 5, 3, 4, 3, 6, 5, 0, 6, 6, 2, 2, 1, 4, 4, 2,
];
// Found by seeded random play. All 40 lines, and player one closes 9 of the 16 boxes.
const DOTS_AND_BOXES_WIN = [
  9, 7, 27, 1, 2, 5, 28, 33, 24, 8, 16, 23, 17, 18, 13, 10, 12, 22, 20, 26, 21, 6, 3, 39, 11, 34, 38, 15, 30, 19, 14, 32, 0, 31, 37, 36, 4,
  29, 35, 25,
];
// Found by seeded random play. Player two wins the middle column of small boards.
const ULTIMATE_WIN = [
  27, 6, 55, 11, 26, 74, 25, 71, 75, 31, 38, 18, 4, 40, 37, 10, 13, 39, 34, 65, 22, 41, 53, 79, 66, 33, 56, 20, 19, 9, 3, 28, 73, 50, 52,
  68,
];
// From the shared Ludo fixtures (lib/ludo.test.ts). Player one gets both pawns home on the last move.
const LUDO_WIN = [
  15, 3, 11, 8, 14, 3, 11, 8, 14, 6, 14, 8, 14, 6, 5, 8, 14, 3, 14, 8, 14, 12, 15, 3, 12, 6, 3, 0, 12, 16, 9, 6, 0, 0, 16, 4, 9, 15, 0, 13, 9, 13,
  12, 16, 4, 6, 5, 8, 14, 13, 2, 8, 14, 13, 14, 8, 14, 10, 14, 8, 14, 15, 7, 16, 16, 4, 1, 16, 1, 6, 10, 9, 7, 10, 13, 14, 8, 14, 9, 5, 8, 14, 1,
  16, 7, 12, 4, 15, 0, 1, 15, 12, 1, 0, 16, 7, 15, 6, 1, 3, 7, 10, 4, 8, 8, 14, 10, 14, 8, 14, 13, 15, 9, 13, 9, 13, 6, 10, 0, 13, 12, 4, 0, 17, 4,
];
// Every kind has a move that is legal on an empty board. Ludo's is a 6 for the first pawn.
const OPENING_MOVE = { connect_four: 0, dots_and_boxes: 0, ultimate_tic_tac_toe: 0, ludo: 15 } as const;

describe("access", () => {
  test("a user without a couple cannot use board games", async () => {
    const t = newTest();
    const loner = await createSignedInUser(t, { name: "Loner" });
    expect((await failure(list(loner))).code).toBe("42501");
    expect((await failure(marks(loner))).code).toBe("42501");
    expect((await failure(ensure(loner, "connect_four"))).code).toBe("42501");
    expect((await failure(loner.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: "aGVsbG8=" }))).code).toBe("42501");
  });

  test("a couple without a subscription cannot use board games", async () => {
    const t = newTest();
    const couple = await createCouple(t, { entitled: false });
    expect((await failure(list(couple.first))).code).toBe("42501");
    expect((await failure(marks(couple.first))).code).toBe("42501");
    expect((await failure(ensure(couple.first, "connect_four"))).code).toBe("42501");
  });

  test("a subscription that ends blocks moves on the existing game", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    await s.t.run(async (ctx) => {
      for (const grant of await ctx.db.query("entitlement_grants").collect()) await ctx.db.delete(grant._id);
    });
    expect((await failure(move(s.a, game, 3))).code).toBe("42501");
    expect((await failure(rematch(s.a, game))).code).toBe("42501");
  });

  test("another couple cannot move or start a rematch", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const other = await createCouple(s.t);
    expect(await failure(move(other.first, game, 3))).toEqual({ code: "42501", message: "active entitled game access is required" });
    expect((await failure(rematch(other.first, game))).code).toBe("42501");
    expect((await list(other.first)).games).toEqual([]);
  });

  test("a move after the relationship ended is refused", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    await endCouple(s.t, s.couple.coupleId, s.b.userId);
    expect((await failure(move(s.a, game, 3))).code).toBe("42501");
  });

  test("a user with a pending account deletion cannot write", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    await s.t.run(async (ctx) => {
      const now = nowIso();
      await ctx.db.insert("account_deletion_jobs", {
        id: newUuid(),
        request_id: newUuid(),
        user_id: s.a.userId,
        auth_provider: "apple",
        status: "ready_for_auth_delete",
        provider_revocation_status: "not_required",
        created_at: now,
        updated_at: now,
      });
    });
    const expected = { code: "42501", message: "account deletion is in progress" };
    expect(await failure(ensure(s.a, "dots_and_boxes"))).toEqual(expected);
    expect(await failure(move(s.a, game, 3))).toEqual(expected);
    expect(await failure(s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: "aGVsbG8=" }))).toEqual(expected);
  });

  test("the first game needs the game settings", async () => {
    const t = newTest();
    const couple = await createCouple(t);
    expect(await failure(ensure(couple.first, "connect_four"))).toEqual({ code: "23514", message: "game settings are required" });
    expect(await gameRows(t)).toEqual([]);
  });
});

describe("ensure_board_game", () => {
  test("creates the game once with the caller as player one", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    expect(game).toEqual({
      id: game.id,
      kind: "connect_four",
      game_number: 1,
      status: "playing",
      version: 1,
      first_user_id: s.a.userId,
      moves: [],
      turn_user_id: s.a.userId,
      winner_user_id: null,
      win_line: [],
      stake: null,
      stake_by_user_id: null,
      my_color: null,
      partner_color: null,
      photo_media_asset_id: null,
      my_wins: 0,
      partner_wins: 0,
      draws: 0,
      games_finished: 0,
      previous: null,
      started_at: nowIso(),
      finished_at: null,
      turn_started_at: nowIso(),
      updated_at: nowIso(),
    });
    expect(await gameRows(s.t)).toHaveLength(1);
  });

  test("is idempotent, and the partner gets the same game", async () => {
    const s = await startCouple();
    const first = await ensure(s.a, "ultimate_tic_tac_toe");
    tick();
    expect(await ensure(s.a, "ultimate_tic_tac_toe")).toEqual(first);
    expect(await ensure(s.b, "ultimate_tic_tac_toe")).toEqual(first);
    expect(await gameRows(s.t)).toHaveLength(1);
    expect((await gameRows(s.t))[0]).toMatchObject({ couple_id: s.couple.coupleId, created_by_user_id: s.a.userId, version: 1 });
  });

  test("get_board_games returns PAEONIA_DATA_EPOCH, so phones notice a restore", async () => {
    const s = await startCouple();
    process.env.PAEONIA_DATA_EPOCH = "restored-2026-10-14";
    try {
      expect((await list(s.a)).data_epoch).toBe("restored-2026-10-14");
    } finally {
      delete process.env.PAEONIA_DATA_EPOCH;
    }
  });

  test("get_board_games lists the started games in a fixed order and skips the others", async () => {
    const s = await startCouple();
    expect(await list(s.a)).toEqual({ user_id: s.a.userId, partner_user_id: s.b.userId, couple_id: s.couple.coupleId, data_epoch: "", games: [] });
    await ensure(s.b, "ludo");
    await ensure(s.b, "ultimate_tic_tac_toe");
    await ensure(s.a, "dots_and_boxes");
    await ensure(s.a, "connect_four");
    const mine = await list(s.a);
    expect(mine.games.map((game) => game.kind)).toEqual(["connect_four", "dots_and_boxes", "ultimate_tic_tac_toe", "ludo"]);
    const theirs = await list(s.b);
    expect(theirs.user_id).toBe(s.b.userId);
    expect(theirs.partner_user_id).toBe(s.a.userId);
    expect(theirs.games.map((game) => game.id)).toEqual(mine.games.map((game) => game.id));
    expect(mine.games.map((game) => game.first_user_id)).toEqual([s.a.userId, s.a.userId, s.b.userId, s.b.userId]);
  });

  test("each kind has its own game", async () => {
    const s = await startCouple();
    const connect = await ensure(s.a, "connect_four");
    const dots = await ensure(s.a, "dots_and_boxes");
    expect(connect.id).not.toBe(dots.id);
    expect(await gameRows(s.t)).toHaveLength(2);
  });
});

describe("full games", () => {
  test("Connect Four: player one wins and the tallies count it", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    tick();
    const done = await playMoves(s, game, CONNECT_FOUR_WIN);
    expect(done).toMatchObject({
      status: "finished",
      game_number: 1,
      moves: CONNECT_FOUR_WIN,
      turn_user_id: null,
      winner_user_id: s.a.userId,
      win_line: [14, 21, 28, 35],
      my_wins: 1,
      partner_wins: 0,
      draws: 0,
      games_finished: 1,
      previous: null,
      finished_at: nowIso(),
      version: 1 + CONNECT_FOUR_WIN.length,
    });
    const theirs = await gameOf(s.b, "connect_four");
    expect(theirs).toMatchObject({ my_wins: 0, partner_wins: 1, winner_user_id: s.a.userId, status: "finished" });
    const [row] = await gameRows(s.t);
    expect(row.turn_user_id).toBeUndefined();
    expect(row.wins_by_user).toEqual({ [s.a.userId]: 1 });
  });

  test("Connect Four: player two wins", async () => {
    const s = await startCouple();
    const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_SECOND_PLAYER_WIN);
    // The answer is for the partner who moved last, player two.
    expect(done).toMatchObject({ status: "finished", winner_user_id: s.b.userId, win_line: [15, 22, 29, 36], my_wins: 1, partner_wins: 0 });
    expect(await gameOf(s.a, "connect_four")).toMatchObject({ my_wins: 0, partner_wins: 1 });
  });

  test("Connect Four: a full board is a draw", async () => {
    const s = await startCouple();
    expect(outcomeOf("connect_four", CONNECT_FOUR_DRAW)).toEqual({ winner: null, line: [] });
    const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_DRAW);
    expect(done).toMatchObject({
      status: "finished",
      turn_user_id: null,
      winner_user_id: null,
      win_line: [],
      my_wins: 0,
      partner_wins: 0,
      draws: 1,
      games_finished: 1,
    });
    expect((await gameRows(s.t))[0].wins_by_user).toEqual({});
  });

  test("Dots and Boxes: all 40 lines and the player with more boxes wins", async () => {
    const s = await startCouple();
    const outcome = outcomeOf("dots_and_boxes", DOTS_AND_BOXES_WIN);
    expect(outcome?.winner).toBe(1);
    const done = await playMoves(s, await ensure(s.a, "dots_and_boxes"), DOTS_AND_BOXES_WIN);
    expect(done).toMatchObject({
      status: "finished",
      moves: DOTS_AND_BOXES_WIN,
      turn_user_id: null,
      winner_user_id: s.a.userId,
      win_line: outcome?.line,
      my_wins: 1,
      games_finished: 1,
      previous: null,
    });
  });

  test("Ultimate Tic-Tac-Toe: player two wins three boards in a row", async () => {
    const s = await startCouple();
    const outcome = outcomeOf("ultimate_tic_tac_toe", ULTIMATE_WIN);
    expect(outcome).toEqual({ winner: 2, line: [1, 4, 7] });
    await playMoves(s, await ensure(s.a, "ultimate_tic_tac_toe"), ULTIMATE_WIN);
    expect(await gameOf(s.a, "ultimate_tic_tac_toe")).toMatchObject({
      status: "finished",
      turn_user_id: null,
      winner_user_id: s.b.userId,
      win_line: [1, 4, 7],
      my_wins: 0,
      partner_wins: 1,
      games_finished: 1,
      previous: null,
    });
  });

  test("a finished game is marked as reminded so no reminder follows", async () => {
    const s = await startCouple();
    const playing = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN.slice(0, -1));
    expect((await gameRows(s.t))[0].turn_reminder_sent_at).toBeUndefined();
    tick();
    await move(s.a, playing, 0);
    expect((await gameRows(s.t))[0]).toMatchObject({ status: "finished", turn_reminder_sent_at: nowIso() });
  });

  test("the turn follows the rules while the game is on", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const afterFirst = await move(s.a, game, 3);
    expect(afterFirst).toMatchObject({ turn_user_id: s.b.userId, moves: [3], version: 2, status: "playing" });
    const afterSecond = await move(s.b, afterFirst, 3);
    expect(afterSecond).toMatchObject({ turn_user_id: s.a.userId, moves: [3, 3], version: 3 });
    expect(await gameOf(s.b, "connect_four")).toEqual(afterSecond);
  });
});

describe("refused moves", () => {
  test("a move the rules refuse is 23514 and changes nothing", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    for (const bad of [-1, 7, 1.5, 100]) {
      expect(await failure(move(s.a, game, bad))).toEqual({ code: "23514", message: "that move is not allowed" });
    }
    // A full column.
    let current = game;
    for (let index = 0; index < 6; index++) current = await move(index % 2 === 0 ? s.a : s.b, current, 4);
    expect(await failure(move(s.a, current, 4))).toEqual({ code: "23514", message: "that move is not allowed" });
    expect(await gameOf(s.a, "connect_four")).toEqual(current);
    expect(await activity(s.t)).toHaveLength(6);
  });

  test("Ludo: player one gets both pawns home", async () => {
    const s = await startCouple();
    const outcome = outcomeOf("ludo", LUDO_WIN);
    expect(outcome).toEqual({ winner: 1, line: [] });
    await playMoves(s, await ensure(s.a, "ludo"), LUDO_WIN);
    expect(await gameOf(s.a, "ludo")).toMatchObject({
      status: "finished",
      turn_user_id: null,
      winner_user_id: s.a.userId,
      win_line: [],
      my_wins: 1,
      partner_wins: 0,
      games_finished: 1,
      previous: null,
    });
  });

  test("Ludo: a pass is legal only when no pawn can move, three tries for a 6, and a 6 keeps the turn", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "ludo");
    // With both pawns in the base, a 1 can't move a pawn, so only the pass (move 2) is legal.
    expect((await failure(move(s.a, game, 0))).code).toBe("23514");
    const firstTry = await move(s.a, game, 2);
    expect(firstTry.turn_user_id).toBe(s.a.userId);
    const passed = await move(s.a, await move(s.a, firstTry, 5), 8);
    expect(passed.turn_user_id).toBe(s.b.userId);
    // A 6 brings a pawn out and rolls again. A pass on a 6 is illegal while a pawn can leave the base.
    const out = await move(s.b, passed, 15);
    expect(out.turn_user_id).toBe(s.b.userId);
    expect((await failure(move(s.b, out, 17))).code).toBe("23514");
  });

  test("a taken line in Dots and Boxes and a wrong board in Ultimate Tic-Tac-Toe are refused", async () => {
    const s = await startCouple();
    const lines = await move(s.a, await ensure(s.a, "dots_and_boxes"), 5);
    expect((await failure(move(s.b, lines, 5))).code).toBe("23514");
    // Cell 4 of board 0 sends the partner to board 4. Board 0 is the wrong board.
    const ultimate = await move(s.a, await ensure(s.a, "ultimate_tic_tac_toe"), 4);
    expect((await failure(move(s.b, ultimate, 0))).code).toBe("23514");
    expect(await move(s.b, ultimate, 36)).toMatchObject({ moves: [4, 36] });
  });

  test("the partner whose turn it is not gets 42501", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    expect(await failure(move(s.b, game, 3))).toEqual({ code: "42501", message: "it is not your turn" });
    const afterFirst = await move(s.a, game, 3);
    expect(await failure(move(s.a, afterFirst, 3))).toEqual({ code: "42501", message: "it is not your turn" });
  });

  test("a stale version is 40001, even before the turn check", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const afterFirst = await move(s.a, game, 3);
    expect(await failure(move(s.b, game, 3))).toEqual({ code: "40001", message: "the game has changed" });
    expect(await failure(move(s.a, game, 3))).toEqual({ code: "40001", message: "the game has changed" });
    expect(await failure(move(s.b, { ...afterFirst, version: afterFirst.version + 1 }, 3))).toEqual({ code: "40001", message: "the game has changed" });
    expect(await gameOf(s.a, "connect_four")).toEqual(afterFirst);
  });

  test("a move on a finished game is 40001", async () => {
    const s = await startCouple();
    const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
    expect(await failure(move(s.b, done, 5))).toEqual({ code: "40001", message: "the game has changed" });
    expect(await failure(move(s.a, done, 5))).toEqual({ code: "40001", message: "the game has changed" });
    expect(await gameOf(s.a, "connect_four")).toEqual(done);
  });

  test("an unknown game is 40001, so a move queued before a restore of the server is dropped", async () => {
    const s = await startCouple();
    expect((await failure(move(s.a, { id: newUuid(), version: 1 }, 3))).code).toBe("40001");
    expect((await failure(rematch(s.a, { id: newUuid(), version: 1 }))).code).toBe("40001");
  });
});

describe("Dots and Boxes extra turns", () => {
  test("closing a box keeps the turn and the turn clock", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "dots_and_boxes");
    // Box 0 has lines 0, 4, 20 and 21. Player two closes it with line 21.
    tick();
    const first = await move(s.a, game, 0);
    expect(first).toMatchObject({ turn_user_id: s.b.userId, turn_started_at: nowIso() });
    tick();
    const second = await move(s.b, first, 4);
    expect(second).toMatchObject({ turn_user_id: s.a.userId, turn_started_at: nowIso() });
    tick();
    const third = await move(s.a, second, 20);
    const passedAt = nowIso();
    expect(third).toMatchObject({ turn_user_id: s.b.userId, turn_started_at: passedAt });

    tick();
    const closed = await move(s.b, third, 21);
    expect(closed).toMatchObject({ status: "playing", turn_user_id: s.b.userId, turn_started_at: passedAt, updated_at: nowIso() });
    expect(closed.version).toBe(third.version + 1);

    tick();
    const extra = await move(s.b, closed, 22);
    expect(extra).toMatchObject({ turn_user_id: s.a.userId, turn_started_at: nowIso() });
  });

  test("a passed turn clears the reminder mark and an extra turn leaves it", async () => {
    const s = await startCouple();
    const marked = nowIso();
    const markReminder = () =>
      s.t.run(async (ctx) => {
        const [row] = await ctx.db.query("board_games").collect();
        await ctx.db.patch(row._id, { turn_reminder_sent_at: marked });
      });
    const reminder = async () => (await gameRows(s.t))[0].turn_reminder_sent_at;

    // Box 0 has lines 0, 4, 20 and 21. Player two closes it with line 21.
    const game = await ensure(s.a, "dots_and_boxes");
    await markReminder();
    const first = await move(s.a, game, 0);
    expect(await reminder()).toBeUndefined();
    await markReminder();
    const second = await move(s.b, first, 4);
    expect(await reminder()).toBeUndefined();
    await markReminder();
    const third = await move(s.a, second, 20);
    expect(await reminder()).toBeUndefined();

    await markReminder();
    const closed = await move(s.b, third, 21);
    expect(closed.turn_user_id).toBe(s.b.userId);
    expect(await reminder()).toBe(marked);
    await move(s.b, closed, 22);
    expect(await reminder()).toBeUndefined();
  });
});

describe("Ludo colors", () => {
  test("a new game gives player one pink and the partner lavender, each seeing both", async () => {
    const s = await startCouple();
    await ensure(s.a, "ludo");
    expect(await gameOf(s.a, "ludo")).toMatchObject({ my_color: "pink", partner_color: "lavender" });
    expect(await gameOf(s.b, "ludo")).toMatchObject({ my_color: "lavender", partner_color: "pink" });
  });

  test("the first move can pick a color, and the partner sees it", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "ludo");
    const after = await move(s.a, game, 15, { p_ludo_color: "gold" });
    expect(after).toMatchObject({ my_color: "gold", partner_color: "lavender", moves: [15] });
    expect(await gameOf(s.b, "ludo")).toMatchObject({ my_color: "lavender", partner_color: "gold" });
  });

  test("the partner's current color is ignored, and the move still goes through", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "ludo");
    const after = await move(s.a, game, 15, { p_ludo_color: "lavender" });
    expect(after).toMatchObject({ my_color: "pink", partner_color: "lavender", moves: [15] });
  });

  test("player two picks with their own first move, and a color the first partner just took is ignored", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "ludo");
    const firstTry = await move(s.a, game, 2, { p_ludo_color: "sky" });
    // Player one misses a 6 three times, so the turn goes to player two.
    const first = await move(s.a, await move(s.a, firstTry, 5), 8);
    // Player two wanted sky too, but sky is taken now.
    expect(await move(s.b, first, 15, { p_ludo_color: "sky" })).toMatchObject({ my_color: "lavender", partner_color: "sky" });
    const again = await ensure(s.b, "ludo");
    expect(again).toMatchObject({ my_color: "lavender", partner_color: "sky" });
  });

  test("a pick after the mover's first move of the game is ignored", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "ludo");
    const first = await move(s.a, game, 15);
    // A 6 keeps the turn, so this is player one's second move.
    const second = await move(s.a, first, 15, { p_ludo_color: "gold" });
    expect(second).toMatchObject({ my_color: "pink", moves: [15, 15] });
  });

  test("colors stay across a rematch, and the next game's first move can change them", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "ludo");
    await move(s.a, game, LUDO_WIN[0], { p_ludo_color: "gold" });
    const finished = await playMoves(s, await gameOf(s.a, "ludo"), LUDO_WIN.slice(1));
    expect(finished.status).toBe("finished");
    const next = await rematch(s.a, finished);
    expect(next).toMatchObject({ game_number: 2, my_color: "gold", partner_color: "lavender" });
    // Player two starts game two and picks sky.
    expect(await move(s.b, next, 15, { p_ludo_color: "sky" })).toMatchObject({ my_color: "sky", partner_color: "gold" });
  });

  test("other board games refuse a color", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    expect(await failure(move(s.a, game, 3, { p_ludo_color: "gold" }))).toEqual({ code: "23514", message: "that color is not allowed" });
    expect((await gameOf(s.a, "connect_four")).moves).toEqual([]);
  });

  test("an unknown color is refused by the argument check", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "ludo");
    await expect(move(s.a, game, 15, { p_ludo_color: "green" as never })).rejects.toThrow();
  });
});

describe("stakes", () => {
  test("the starter sets a stake with the first move, trimmed", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const afterFirst = await move(s.a, game, 3, { p_stake: "  Loser makes coffee \n " });
    expect(afterFirst).toMatchObject({ stake: "Loser makes coffee", stake_by_user_id: s.a.userId });
    expect(await gameOf(s.b, "connect_four")).toMatchObject({ stake: "Loser makes coffee", stake_by_user_id: s.a.userId });
  });

  test("the stake stays through the game and the result", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const first = await move(s.a, game, 0, { p_stake: "Dinner" });
    const done = await playMoves(s, first, CONNECT_FOUR_WIN.slice(1));
    expect(done).toMatchObject({ status: "finished", stake: "Dinner", stake_by_user_id: s.a.userId });
  });

  test("the partner cannot set a stake", async () => {
    const s = await startCouple();
    const first = await move(s.a, await ensure(s.a, "connect_four"), 3);
    expect(await failure(move(s.b, first, 3, { p_stake: "Dinner" }))).toEqual({ code: "23514", message: "that stake is not allowed" });
    expect((await gameOf(s.a, "connect_four")).moves).toEqual([3]);
  });

  test("a stake after the first move is refused", async () => {
    const s = await startCouple();
    const first = await move(s.a, await ensure(s.a, "connect_four"), 3);
    const second = await move(s.b, first, 3);
    expect((await failure(move(s.a, second, 3, { p_stake: "Dinner" }))).code).toBe("23514");
    expect((await gameOf(s.a, "connect_four")).stake).toBeNull();
  });

  test("the starter cannot set a stake when the partner started the game", async () => {
    const s = await startCouple();
    const game = await ensure(s.b, "connect_four");
    expect(game.first_user_id).toBe(s.b.userId);
    expect((await failure(move(s.a, game, 3, { p_stake: "Dinner" }))).code).toBe("42501");
    expect(await move(s.b, game, 3, { p_stake: "Dinner" })).toMatchObject({ stake: "Dinner", stake_by_user_id: s.b.userId });
  });

  test("a stake is at most 60 characters", async () => {
    const s = await startCouple();
    const long = await ensure(s.a, "connect_four");
    expect(await failure(move(s.a, long, 3, { p_stake: "x".repeat(61) }))).toEqual({ code: "23514", message: "that stake is not allowed" });
    expect((await gameOf(s.a, "connect_four")).moves).toEqual([]);
    expect(await move(s.a, long, 3, { p_stake: "x".repeat(60) })).toMatchObject({ stake: "x".repeat(60) });

    // Characters are counted, not UTF-16 units. A pizza is two units.
    const emoji = await ensure(s.a, "dots_and_boxes");
    expect((await failure(move(s.a, emoji, 0, { p_stake: "🍕".repeat(61) }))).code).toBe("23514");
    expect(await move(s.a, emoji, 0, { p_stake: "🍕".repeat(60) })).toMatchObject({ stake: "🍕".repeat(60) });
  });

  test("a stake cannot hold a line break", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    for (const text of ["Dinner\nand a movie", "Dinner\r\nand", "a\u2028b", "a\u2029b"]) {
      expect(await failure(move(s.a, game, 3, { p_stake: text }))).toEqual({ code: "23514", message: "that stake is not allowed" });
    }
    expect((await gameOf(s.a, "connect_four")).moves).toEqual([]);
  });

  test("an empty or blank stake means none", async () => {
    const s = await startCouple();
    for (const [index, kind] of (["connect_four", "dots_and_boxes", "ultimate_tic_tac_toe"] as const).entries()) {
      const game = await ensure(s.a, kind);
      const stake = [null, "", "   \n "][index];
      const after = await move(s.a, game, 0, { p_stake: stake });
      expect(after).toMatchObject({ stake: null, stake_by_user_id: null, moves: [0] });
    }
    const game = await ensure(s.a, "connect_four");
    const second = await move(s.b, game, 1, { p_stake: "" });
    expect(second.stake).toBeNull();
  });

  test("a stake does not save a move the rules refuse", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    expect((await failure(move(s.a, game, 9, { p_stake: "Dinner" }))).code).toBe("23514");
    expect((await gameOf(s.a, "connect_four")).stake).toBeNull();
  });
});

describe("client operations", () => {
  test("a retry moves once and returns the game as it is now", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const args = { ...op(), p_game_id: game.id, p_expected_version: game.version, p_move: 3 };
    const first = await s.a.as.mutation(api.boardGames.make_move, args);
    tick();
    expect(await s.a.as.mutation(api.boardGames.make_move, args)).toEqual(first);
    expect(await gameOf(s.a, "connect_four")).toMatchObject({ moves: [3], version: 2 });
    expect(await activity(s.t)).toHaveLength(1);
    // After the game moved on, a retry shows the partner's move too.
    await move(s.b, first, 3);
    expect(await s.a.as.mutation(api.boardGames.make_move, args)).toMatchObject({ moves: [3, 3], version: 3 });
  });

  test("a retry after the relationship ended is refused and returns nothing", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const args = { ...op(), p_game_id: game.id, p_expected_version: game.version, p_move: 3, p_stake: "Dinner" };
    await s.a.as.mutation(api.boardGames.make_move, args);
    await endCouple(s.t, s.couple.coupleId, s.b.userId);
    expect((await failure(s.a.as.mutation(api.boardGames.make_move, args))).code).toBe("42501");
  });

  test("the same operation id with a different request is refused", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const args = { ...op(), p_game_id: game.id, p_expected_version: game.version, p_move: 3 };
    await s.a.as.mutation(api.boardGames.make_move, args);
    for (const changed of [{ p_move: 4 }, { p_expected_version: 5 }, { p_stake: "Dinner" }, { p_ludo_color: "gold" as const }]) {
      expect(await failure(s.a.as.mutation(api.boardGames.make_move, { ...args, ...changed }))).toEqual({
        code: "23505",
        message: "client operation replay hash mismatch",
      });
    }
  });

  test("a failed move leaves no operation behind, so the phone can send it again", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const args = { ...op(), p_game_id: game.id, p_expected_version: game.version, p_move: 99 };
    expect((await failure(s.a.as.mutation(api.boardGames.make_move, args))).code).toBe("23514");
    expect((await failure(s.a.as.mutation(api.boardGames.make_move, args))).code).toBe("23514");
    expect(await s.t.run((ctx) => ctx.db.query("client_operations").collect())).toEqual([]);
  });

  test("the rematch is a client operation too", async () => {
    const s = await startCouple();
    const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
    const args = { ...op(), p_game_id: done.id, p_expected_version: done.version };
    const first = await s.b.as.mutation(api.boardGames.start_rematch, args);
    expect(await s.b.as.mutation(api.boardGames.start_rematch, args)).toEqual(first);
    expect(first.game_number).toBe(2);
    expect(await failure(s.b.as.mutation(api.boardGames.start_rematch, { ...args, p_expected_version: 99 }))).toEqual({
      code: "23505",
      message: "client operation replay hash mismatch",
    });
  });
});

describe("streak", () => {
  test("every move records game_turn_completed with its own dedupe key", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const first = await move(s.a, game, 3);
    await move(s.b, first, 4);
    const events = (await activity(s.t)).sort((x, y) => x.dedupe_key.localeCompare(y.dedupe_key));
    expect(events.map((event) => [event.dedupe_key, event.user_id, event.activity_kind, event.metadata])).toEqual([
      [`game_turn_completed:${game.id}:1:1`, s.a.userId, "game_turn_completed", { game_id: game.id, kind: "connect_four" }],
      [`game_turn_completed:${game.id}:1:2`, s.b.userId, "game_turn_completed", { game_id: game.id, kind: "connect_four" }],
    ]);
    expect(events.every((event) => event.couple_id === s.couple.coupleId)).toBe(true);
  });

  test("the move that ends the game counts, and a rematch uses the next game number", async () => {
    const s = await startCouple();
    const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
    expect(await activity(s.t)).toHaveLength(CONNECT_FOUR_WIN.length);
    expect((await activity(s.t)).map((event) => event.dedupe_key)).toContain(`game_turn_completed:${done.id}:1:7`);
    const next = await rematch(s.b, done);
    await move(s.b, next, 2);
    expect((await activity(s.t)).map((event) => event.dedupe_key)).toContain(`game_turn_completed:${done.id}:2:1`);
  });

  test("both partners moving on one day count toward the couple's day", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    const first = await move(s.a, game, 3);
    await move(s.b, first, 3);
    const days = new Set((await activity(s.t)).map((event) => event.couple_day_id));
    expect(days.size).toBe(1);
  });
});

describe("history", () => {
  const history = (user: TestUser, kind: BoardGameKind, before?: number, limit = 10) =>
    user.as.query(api.boardGames.get_board_game_history, { p_kind: kind, p_before_game_number: before ?? null, p_limit: limit });

  test("a finished game is kept for both partners, with its moves and stake", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "ultimate_tic_tac_toe");
    const started = game.started_at;
    expect(await history(s.a, "ultimate_tic_tac_toe")).toEqual({ games: [], next_before_game_number: null });
    const withStake = await move(s.a, game, ULTIMATE_WIN[0], { p_stake: "Dinner" });
    tick();
    await playMoves(s, withStake, ULTIMATE_WIN.slice(1));
    const expected = {
      game_number: 1,
      first_user_id: s.a.userId,
      moves: ULTIMATE_WIN,
      winner_user_id: s.b.userId,
      win_line: [1, 4, 7],
      stake: "Dinner",
      started_at: started,
      finished_at: nowIso(),
    };
    expect(await history(s.a, "ultimate_tic_tac_toe")).toEqual({ games: [expected], next_before_game_number: null });
    expect(await history(s.b, "ultimate_tic_tac_toe")).toEqual({ games: [expected], next_before_game_number: null });
    // Other kinds have their own history.
    expect((await history(s.a, "connect_four")).games).toEqual([]);
  });

  test("a game still on is not in the history, and a draw has no winner", async () => {
    const s = await startCouple();
    const playing = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_DRAW.slice(0, -1));
    expect((await history(s.a, "connect_four")).games).toEqual([]);
    await playMoves(s, playing, CONNECT_FOUR_DRAW.slice(-1));
    expect((await history(s.a, "connect_four")).games).toMatchObject([{ winner_user_id: null, win_line: [], stake: null }]);
  });

  test("pages newest first", async () => {
    const s = await startCouple();
    let game = await ensure(s.a, "connect_four");
    for (let round = 0; round < 3; round += 1) {
      const done = await playMoves(s, game, CONNECT_FOUR_WIN);
      game = round < 2 ? await rematch(s.a, done) : done;
    }
    const first = await history(s.b, "connect_four", undefined, 2);
    expect(first.games.map((row) => row.game_number)).toEqual([3, 2]);
    expect(first.next_before_game_number).toBe(2);
    const second = await history(s.b, "connect_four", 2, 2);
    expect(second.games.map((row) => row.game_number)).toEqual([1]);
    expect(second.next_before_game_number).toBeNull();
    // Each game remembers who started it.
    expect([...first.games, ...second.games].map((row) => row.first_user_id)).toEqual([s.a.userId, s.b.userId, s.a.userId]);
  });

  test("needs an entitled couple and a limit of 1 or more", async () => {
    const s = await startCouple();
    expect((await failure(history(s.a, "connect_four", undefined, 0))).code).toBe("23514");
    const loner = await createSignedInUser(s.t, { name: "Loner" });
    expect((await failure(history(loner, "connect_four"))).code).toBe("42501");
  });
});

describe("start_rematch", () => {
  test("is refused while the game is on", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    expect(await failure(rematch(s.a, game))).toEqual({ code: "23514", message: "the game is not over" });
    const afterFirst = await move(s.a, game, 3);
    expect((await failure(rematch(s.b, afterFirst))).code).toBe("23514");
  });

  test("a stale version is 40001 before the game state is looked at", async () => {
    const s = await startCouple();
    const game = await ensure(s.a, "connect_four");
    expect(await failure(rematch(s.a, { ...game, version: 9 }))).toEqual({ code: "40001", message: "the game has changed" });
  });

  test("starts a fresh board on the same row, started by the other partner", async () => {
    const s = await startCouple();
    const first = await ensure(s.a, "connect_four");
    const withStake = await move(s.a, first, 0, { p_stake: "Dinner" });
    const done = await playMoves(s, withStake, CONNECT_FOUR_WIN.slice(1));
    tick();
    const next = await rematch(s.a, done);
    expect(next).toEqual({
      id: first.id,
      kind: "connect_four",
      game_number: 2,
      status: "playing",
      version: done.version + 1,
      first_user_id: s.b.userId,
      moves: [],
      turn_user_id: s.b.userId,
      winner_user_id: null,
      win_line: [],
      stake: null,
      stake_by_user_id: null,
      photo_media_asset_id: null,
      my_color: null,
      partner_color: null,
      my_wins: 1,
      partner_wins: 0,
      draws: 0,
      games_finished: 1,
      previous: {
        game_number: 1,
        first_user_id: s.a.userId,
        moves: CONNECT_FOUR_WIN,
        winner_user_id: s.a.userId,
        win_line: [14, 21, 28, 35],
        stake: "Dinner",
        photo_media_asset_id: null,
        finished_at: done.finished_at,
      },
      started_at: nowIso(),
      finished_at: null,
      turn_started_at: nowIso(),
      updated_at: nowIso(),
    });
    expect(await gameOf(s.b, "connect_four")).toMatchObject({ my_wins: 0, partner_wins: 1, previous: { winner_user_id: s.a.userId } });
    expect(await gameRows(s.t)).toHaveLength(1);
    const [row] = await gameRows(s.t);
    expect([row.turn_reminder_sent_at, row.finished_at, row.winner_user_id, row.stake, row.stake_by_user_id]).toEqual([
      undefined,
      undefined,
      undefined,
      undefined,
      undefined,
    ]);
  });

  test("the partner who did not start the last game moves first, then the starters alternate", async () => {
    const s = await startCouple();
    let game = await ensure(s.a, "connect_four");
    const starters = [game.first_user_id];
    for (let round = 0; round < 3; round++) {
      const starter = s.byId[game.first_user_id];
      expect((await failure(move(starter === s.a ? s.b : s.a, game, 0))).code).toBe("42501");
      game = await playMoves(s, game, CONNECT_FOUR_WIN);
      expect(game.winner_user_id).toBe(starter.userId);
      game = await rematch(s.a, game);
      starters.push(game.first_user_id);
    }
    expect(starters).toEqual([s.a.userId, s.b.userId, s.a.userId, s.b.userId]);
    expect(game).toMatchObject({ game_number: 4, my_wins: 2, partner_wins: 1, games_finished: 3 });
  });

  test("a draw and a win add up in the tallies, and previous holds the latest game only", async () => {
    const s = await startCouple();
    let game = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_DRAW);
    game = await rematch(s.b, game);
    expect(game.previous).toMatchObject({ game_number: 1, winner_user_id: null, win_line: [], moves: CONNECT_FOUR_DRAW });
    game = await playMoves(s, game, CONNECT_FOUR_WIN);
    game = await rematch(s.b, game);
    expect(game.previous).toMatchObject({ game_number: 2, winner_user_id: s.b.userId, moves: CONNECT_FOUR_WIN });
    expect(game).toMatchObject({ game_number: 3, draws: 1, games_finished: 2, my_wins: 1, partner_wins: 0 });
    expect((await gameRows(s.t))[0].wins_by_user).toEqual({ [s.b.userId]: 1 });
  });

  test("a second tap with the old version is 40001, and the first tap's game stands", async () => {
    const s = await startCouple();
    const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
    const next = await rematch(s.a, done);
    expect(await failure(rematch(s.b, done))).toEqual({ code: "40001", message: "the game has changed" });
    expect(await gameOf(s.a, "connect_four")).toEqual(next);
    // The new version is not over, whoever taps.
    expect((await failure(rematch(s.b, next))).code).toBe("23514");
  });

  test("the move that finished the game cannot be played again after a rematch", async () => {
    const s = await startCouple();
    const playing = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN.slice(0, -1));
    const done = await move(s.a, playing, 0);
    const next = await rematch(s.b, done);
    expect(await failure(move(s.a, done, 0))).toEqual({ code: "40001", message: "the game has changed" });
    expect(next.moves).toEqual([]);
  });

  test("a finished Dots and Boxes game restarts with the other partner first", async () => {
    const s = await startCouple();
    const done = await playMoves(s, await ensure(s.a, "dots_and_boxes"), DOTS_AND_BOXES_WIN);
    const next = await rematch(s.a, done);
    expect(next).toMatchObject({ game_number: 2, first_user_id: s.b.userId, turn_user_id: s.b.userId, moves: [] });
  });
});

describe("hidden photo", () => {
  /** Creates a memory with one uploaded photo and returns its ids. */
  async function addMemoryPhoto(s: Setup, owner = s.a) {
    const up = await uploadAsset(s.t, owner, photo(s.couple.coupleId));
    const memoryId = newUuid();
    await owner.as.mutation(api.memories.create_memory, {
      ...op(),
      p_memory_id: memoryId,
      p_title: "Beach weekend",
      p_memory_date: "2026-10-01",
      p_note_body: null,
      p_media_asset_ids: [up.assetId],
    });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    return { memoryId, assetId: up.assetId };
  }

  test("a couple without photos gets none, in every kind", async () => {
    const s = await startCouple();
    for (const kind of ["connect_four", "dots_and_boxes", "ultimate_tic_tac_toe", "ludo"] as const) {
      expect((await ensure(s.a, kind)).photo_media_asset_id).toBeNull();
    }
    expect((await gameRows(s.t)).map((row) => row.photo_media_asset_id)).toEqual([undefined, undefined, undefined, undefined]);
  });

  test("a new Dots and Boxes game gets a photo from the couple's memories, and both partners see it", async () => {
    const s = await startCouple();
    const { assetId } = await addMemoryPhoto(s);
    const game = await ensure(s.b, "dots_and_boxes");
    expect(game.photo_media_asset_id).toBe(assetId);
    expect((await gameOf(s.a, "dots_and_boxes")).photo_media_asset_id).toBe(assetId);
    // Only Dots and Boxes uses a photo.
    expect((await ensure(s.a, "connect_four")).photo_media_asset_id).toBeNull();
    expect((await gameRows(s.t)).find((row) => row.kind === "connect_four")?.photo_media_asset_id).toBeUndefined();
  });

  test("the pick is random among the photos, and each rematch picks again", async () => {
    const s = await startCouple();
    const one = await addMemoryPhoto(s, s.a);
    const two = await addMemoryPhoto(s, s.b);
    const random = vi.spyOn(Math, "random");
    random.mockReturnValue(0);
    const low = await ensure(s.a, "dots_and_boxes");
    random.mockReturnValue(0.99);
    const done = await playMoves(s, low, DOTS_AND_BOXES_WIN);
    const next = await rematch(s.a, done);
    expect(new Set([low.photo_media_asset_id, next.photo_media_asset_id])).toEqual(new Set([one.assetId, two.assetId]));
    expect(next.previous?.photo_media_asset_id).toBe(low.photo_media_asset_id);
    expect(done.photo_media_asset_id).toBe(low.photo_media_asset_id);
  });

  test("only visible memory photos are picked", async () => {
    const s = await startCouple();
    const gone = await addMemoryPhoto(s);
    const kept = await addMemoryPhoto(s);
    await s.a.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: gone.memoryId, p_expected_revision: 1 });
    const random = vi.spyOn(Math, "random");
    for (const value of [0, 0.5, 0.99]) {
      random.mockReturnValue(value);
      const game = await ensure(s.a, "dots_and_boxes");
      expect(game.photo_media_asset_id).toBe(kept.assetId);
      await s.t.run(async (ctx) => {
        for (const row of await ctx.db.query("board_games").collect()) await ctx.db.delete(row._id);
      });
    }
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("another couple's photos are never picked", async () => {
    const s = await startCouple();
    const other = await createCouple(s.t);
    const up = await uploadAsset(s.t, other.first, photo(other.coupleId));
    await other.first.as.mutation(api.memories.create_memory, {
      ...op(),
      p_memory_id: newUuid(),
      p_title: "Theirs",
      p_memory_date: "2026-10-01",
      p_note_body: null,
      p_media_asset_ids: [up.assetId],
    });
    expect((await ensure(s.a, "dots_and_boxes")).photo_media_asset_id).toBeNull();
  });

  test("the view hides the photo once its memory is deleted, and shows plain boxes from then on", async () => {
    const s = await startCouple();
    const { memoryId, assetId } = await addMemoryPhoto(s);
    const first = await ensure(s.a, "dots_and_boxes");
    const playing = await move(s.a, first, 0);
    expect(playing.photo_media_asset_id).toBe(assetId);

    tick();
    await s.b.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1 });
    const hidden = await gameOf(s.a, "dots_and_boxes");
    expect(hidden.photo_media_asset_id).toBeNull();
    expect((await gameOf(s.b, "dots_and_boxes")).photo_media_asset_id).toBeNull();
    // The row still names the photo. The read decides.
    expect((await gameRows(s.t))[0].photo_media_asset_id).toBe(assetId);
    // A move after the photo is gone still works and answers without it.
    expect((await move(s.b, hidden, 1)).photo_media_asset_id).toBeNull();
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the photo of the previous game is hidden the same way", async () => {
    const s = await startCouple();
    const { memoryId, assetId } = await addMemoryPhoto(s);
    const done = await playMoves(s, await ensure(s.a, "dots_and_boxes"), DOTS_AND_BOXES_WIN);
    const next = await rematch(s.a, done);
    expect(next.previous?.photo_media_asset_id).toBe(assetId);
    await s.b.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: memoryId, p_expected_revision: 1 });
    const after = await gameOf(s.a, "dots_and_boxes");
    expect(after.previous?.photo_media_asset_id).toBeNull();
    expect(after.photo_media_asset_id).toBeNull();
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a new game picks another photo when the old one is gone", async () => {
    const s = await startCouple();
    const gone = await addMemoryPhoto(s);
    const done = await playMoves(s, await ensure(s.a, "dots_and_boxes"), DOTS_AND_BOXES_WIN);
    expect(done.photo_media_asset_id).toBe(gone.assetId);
    await s.a.as.mutation(api.memories.hide_memory, { ...op(), p_memory_id: gone.memoryId, p_expected_revision: 1 });
    expect((await rematch(s.b, done)).photo_media_asset_id).toBeNull();
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("marks", () => {
  const MARK = "aGVsbG8=";

  test("start empty", async () => {
    const s = await startCouple();
    expect(await marks(s.a)).toEqual({ user_id: s.a.userId, mine: null, partner: null });
  });

  test("a mark saves, updates and clears", async () => {
    const s = await startCouple();
    expect(await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: MARK })).toEqual({ updated_at: nowIso() });
    expect(await marks(s.a)).toEqual({ user_id: s.a.userId, mine: { drawing: MARK, updated_at: nowIso() }, partner: null });
    const created = nowIso();

    tick();
    expect(await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: "AAAA" })).toEqual({ updated_at: nowIso() });
    expect((await marks(s.a)).mine).toEqual({ drawing: "AAAA", updated_at: nowIso() });
    const rows = await s.t.run((ctx) => ctx.db.query("board_game_marks").collect());
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ couple_id: s.couple.coupleId, user_id: s.a.userId, created_at: created, updated_at: nowIso() });

    expect(await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: null })).toBeNull();
    expect(await marks(s.a)).toEqual({ user_id: s.a.userId, mine: null, partner: null });
    expect(await s.t.run((ctx) => ctx.db.query("board_game_marks").collect())).toEqual([]);
    expect(await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: null })).toBeNull();
  });

  test("the partner sees my mark as theirs, and each keeps their own", async () => {
    const s = await startCouple();
    await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: MARK });
    tick();
    await s.b.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: "AAAA" });
    const mineA = { drawing: MARK, updated_at: new Date(START).toISOString() };
    const mineB = { drawing: "AAAA", updated_at: nowIso() };
    expect(await marks(s.a)).toEqual({ user_id: s.a.userId, mine: mineA, partner: mineB });
    expect(await marks(s.b)).toEqual({ user_id: s.b.userId, mine: mineB, partner: mineA });
    await s.b.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: null });
    expect((await marks(s.a)).partner).toBeNull();
    expect((await marks(s.a)).mine).toEqual(mineA);
  });

  test("another couple's marks stay apart", async () => {
    const s = await startCouple();
    const other = await createCouple(s.t);
    await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: MARK });
    expect(await marks(other.first)).toEqual({ user_id: other.first.userId, mine: null, partner: null });
  });

  test("a mark that is not base64 is refused", async () => {
    const s = await startCouple();
    await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: MARK });
    for (const bad of ["", "not base64!", "abc", "aGVsbG8", "AA=A", "A===", "====", "aGVs bG8=", "aGVsbG8=\n", "aGVs-G8_"]) {
      expect(await failure(s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: bad }))).toEqual({
        code: "23514",
        message: "that mark is not allowed",
      });
    }
    expect((await marks(s.a)).mine?.drawing).toBe(MARK);
  });

  test("a mark is at most 48 KB once decoded", async () => {
    const s = await startCouple();
    // 65536 base64 characters decode to exactly 49152 bytes.
    const biggest = "A".repeat(65536);
    expect(await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: biggest })).toEqual({ updated_at: nowIso() });
    // One more byte needs 65540 characters.
    const tooBig = "A".repeat(65540);
    expect(await failure(s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: tooBig }))).toEqual({
      code: "23514",
      message: "that mark is not allowed",
    });
    expect((await marks(s.a)).mine?.drawing).toBe(biggest);
    // Padding shortens the decoded size: this is 65536 characters and 49150 bytes.
    expect((await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: `${"A".repeat(65532)}AA==` }))?.updated_at).toBe(nowIso());
  });

  test("a mark does not need a started game", async () => {
    const s = await startCouple();
    await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: MARK });
    expect(await gameRows(s.t)).toEqual([]);
  });
});

// --- Pushes -------------------------------------------------------------------

const ALL_KINDS = ["connect_four", "dots_and_boxes", "ultimate_tic_tac_toe", "ludo"] as const;
const deepLink = (kind: BoardGameKind) => `paeonia://games/${kind.replaceAll("_", "-")}`;

/** A couple whose partners both have a push device, so pushes reach the outbox. `locale` is the second partner's. */
async function startPushCouple(locale?: string): Promise<Setup> {
  const s = await startCouple();
  await addDevice(s.t, s.a.userId);
  await addDevice(s.t, s.b.userId, { locale });
  return s;
}

const outbox = (t: TestConvex) => t.run((ctx) => ctx.db.query("notification_outbox").collect());
const pushesOf = async (t: TestConvex, kind: string) => (await outbox(t)).filter((row) => row.kind === kind);
const claim = (s: Setup) => deliverDuePushes(s.t);
const runReminders = (s: Setup) => s.t.mutation(internal.games.send_due_game_turn_reminders, {});
const hours = (count: number) => tick(count * 3600);
/** Who a push goes to and which turn it names, for a push kind. */
const turnsOf = async (s: Setup, kind: string) =>
  (await pushesOf(s.t, kind)).map((row) => [row.recipient_user_id, (row.payload as { round_id: string }).round_id]);

describe("pushes", () => {
  test("a move that passes the turn queues a lock-screen-safe turn push for the partner", async () => {
    const s = await startPushCouple();
    const game = await ensure(s.a, "connect_four");
    expect(await outbox(s.t)).toEqual([]);

    const first = await move(s.a, game, 3, { p_stake: "Dinner" });
    const [row] = await pushesOf(s.t, "game_turn_ready");
    expect(row).toMatchObject({
      recipient_user_id: s.b.userId,
      apns_push_type: "alert",
      title: "Your turn in Connect Four",
      body: "Open Paeonia to make your move.",
    });
    expect(row.payload).toEqual({
      type: "game_turn_ready",
      game_kind: "connect_four",
      couple_id: s.couple.coupleId,
      game_id: game.id,
      round_id: "1:1",
      actor_user_id: s.a.userId,
      route: "games",
      deeplink: "paeonia://games/connect-four",
    });
    expect(JSON.stringify(row)).not.toContain("Dinner");

    await move(s.b, first, 4);
    expect(await turnsOf(s, "game_turn_ready")).toEqual([
      [s.b.userId, "1:1"],
      [s.a.userId, "1:2"],
    ]);
    const keys = (await pushesOf(s.t, "game_turn_ready")).map((item) => item.dedupe_key);
    expect(new Set(keys).size).toBe(2);
    expect(await pushesOf(s.t, "game_result")).toEqual([]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a Dots and Boxes extra turn queues nothing, and the move that passes the turn after it does", async () => {
    const s = await startPushCouple();
    // Box 0 has lines 0, 4, 20 and 21. Player two closes it with line 21 and moves again.
    const third = await playMoves(s, await ensure(s.a, "dots_and_boxes"), [0, 4, 20]);
    expect(await turnsOf(s, "game_turn_ready")).toEqual([
      [s.b.userId, "1:1"],
      [s.a.userId, "1:2"],
      [s.b.userId, "1:3"],
    ]);
    const closed = await move(s.b, third, 21);
    expect(closed.turn_user_id).toBe(s.b.userId);
    expect(await turnsOf(s, "game_turn_ready")).toHaveLength(3);

    await move(s.b, closed, 22);
    expect((await turnsOf(s, "game_turn_ready")).at(-1)).toEqual([s.a.userId, "1:5"]);
    expect(await turnsOf(s, "game_turn_ready")).toHaveLength(4);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test.each([
    ["connect_four", CONNECT_FOUR_WIN, "Your game of Connect Four is over"],
    ["dots_and_boxes", DOTS_AND_BOXES_WIN, "Your game of Dots and Boxes is over"],
    ["ultimate_tic_tac_toe", ULTIMATE_WIN, "Your game of Ultimate Tic-Tac-Toe is over"],
    ["ludo", LUDO_WIN, "Your game of Ludo is over"],
  ] as const)("%s: the move that ends the game queues one result push for the partner instead of a turn push", async (kind, moves, title) => {
    const s = await startPushCouple();
    const players = movers(rulesFor(kind), moves)!;
    const finisher = players.at(-1) === 1 ? s.a : s.b;
    const receiver = finisher === s.a ? s.b : s.a;
    const game = await ensure(s.a, kind);
    const beforeLast = await playMoves(s, game, moves.slice(0, -1));
    expect(await pushesOf(s.t, "game_result")).toEqual([]);

    const done = await move(finisher, beforeLast, moves.at(-1)!);
    expect(done.status).toBe("finished");
    const turn = `1:${moves.length}`;
    expect((await turnsOf(s, "game_turn_ready")).filter(([, token]) => token === turn)).toEqual([]);
    const [row, ...rest] = await pushesOf(s.t, "game_result");
    expect(rest).toEqual([]);
    expect(row).toMatchObject({ recipient_user_id: receiver.userId, title, body: "Open Paeonia to see how it ended." });
    expect(row.payload).toEqual({
      type: "game_result",
      game_kind: kind,
      couple_id: s.couple.coupleId,
      game_id: game.id,
      round_id: turn,
      actor_user_id: finisher.userId,
      route: "games",
      deeplink: deepLink(kind),
    });
    expect(JSON.stringify(row)).not.toContain("winner");
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a draw also sends the result push", async () => {
    const s = await startPushCouple();
    const players = movers(rulesFor("connect_four"), CONNECT_FOUR_DRAW)!;
    const receiver = players.at(-1) === 1 ? s.b : s.a;
    await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_DRAW);
    const rows = await pushesOf(s.t, "game_result");
    expect(rows.map((row) => row.recipient_user_id)).toEqual([receiver.userId]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("pushes are in the recipient's language", async () => {
    const s = await startPushCouple("nb-NO");
    const game = await ensure(s.a, "connect_four");
    await playMoves(s, game, CONNECT_FOUR_WIN);
    const [turn] = await pushesOf(s.t, "game_turn_ready");
    expect(turn).toMatchObject({ recipient_user_id: s.b.userId, title: "Din tur i Fire på rad", body: "Åpne Paeonia for å gjøre trekket ditt." });
    const [result] = await pushesOf(s.t, "game_result");
    expect(result).toMatchObject({
      recipient_user_id: s.b.userId,
      title: "Spillet deres i Fire på rad er ferdig",
      body: "Åpne Paeonia for å se hvordan det endte.",
    });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("an open game screen on the recipient's phone suppresses the turn and result pushes of that game only", async () => {
    const s = await startPushCouple();
    const c4 = await ensure(s.a, "connect_four");
    const dots = await ensure(s.a, "dots_and_boxes");
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "connect_four", p_present: true });

    await move(s.a, dots, 0);
    expect(await turnsOf(s, "game_turn_ready")).toEqual([[s.b.userId, "1:1"]]);

    // Player one wins Connect Four. b's moves still push a, because a has no screen open.
    await playMoves(s, c4, CONNECT_FOUR_WIN);
    expect((await turnsOf(s, "game_turn_ready")).filter(([userId]) => userId === s.b.userId)).toHaveLength(1);
    expect((await turnsOf(s, "game_turn_ready")).filter(([userId]) => userId === s.a.userId)).toHaveLength(3);
    expect(await pushesOf(s.t, "game_result")).toEqual([]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a screen that stopped its heartbeats does not suppress the push, and closing the screen removes it", async () => {
    const s = await startPushCouple();
    const game = await ensure(s.a, "connect_four");
    // The presence component times sessions out with scheduled functions, so fake every timer.
    vi.useFakeTimers();
    await s.b.as.mutation(api.games.set_game_presence, { p_kind: "connect_four", p_present: true });
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    const first = await move(s.a, game, 3);
    expect(await pushesOf(s.t, "game_turn_ready")).toHaveLength(1);

    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "connect_four", p_present: true });
    await s.a.as.mutation(api.games.set_game_presence, { p_kind: "connect_four", p_present: false });
    await move(s.b, first, 4);
    expect(await pushesOf(s.t, "game_turn_ready")).toHaveLength(2);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a retried move queues one push", async () => {
    const s = await startPushCouple();
    const game = await ensure(s.a, "connect_four");
    const args = { ...op(), p_game_id: game.id, p_expected_version: game.version, p_move: 3, p_stake: null };
    const first = await s.a.as.mutation(api.boardGames.make_move, args);
    expect(await s.a.as.mutation(api.boardGames.make_move, args)).toEqual(first);
    expect(await pushesOf(s.t, "game_turn_ready")).toHaveLength(1);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the Games switch turns every board game push off", async () => {
    const s = await startPushCouple();
    await s.b.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    const game = await ensure(s.a, "connect_four");
    await move(s.a, game, 3);
    expect(await outbox(s.t)).toEqual([]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  describe("start_rematch", () => {
    test("pushes the new starter when the partner asks for the rematch", async () => {
      const s = await startPushCouple();
      const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
      const before = (await pushesOf(s.t, "game_turn_ready")).length;
      await rematch(s.a, done);
      const rows = (await pushesOf(s.t, "game_turn_ready")).slice(before);
      expect(rows).toHaveLength(1);
      expect(rows[0]).toMatchObject({ recipient_user_id: s.b.userId, title: "Your turn in Connect Four", body: "Open Paeonia to make your move." });
      expect(rows[0].payload).toMatchObject({ game_id: done.id, round_id: "2:0", actor_user_id: s.a.userId, deeplink: "paeonia://games/connect-four" });
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("queues nothing when the caller is the new starter", async () => {
      const s = await startPushCouple();
      const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
      const before = (await outbox(s.t)).length;
      const next = await rematch(s.b, done);
      expect(next.turn_user_id).toBe(s.b.userId);
      expect(await outbox(s.t)).toHaveLength(before);
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });

    test("is skipped while the new starter has the game open", async () => {
      const s = await startPushCouple();
      const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
      const before = (await outbox(s.t)).length;
      await s.b.as.mutation(api.games.set_game_presence, { p_kind: "connect_four", p_present: true });
      await rematch(s.a, done);
      expect(await outbox(s.t)).toHaveLength(before);
      await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    });
  });
});

describe("push drain", () => {
  /** What a drain picked up, as [push kind, turn]. */
  const claimed = async (s: Setup) => (await claim(s)).map((item) => [item.payload.type, item.payload.round_id]);
  const errors = async (s: Setup) => (await outbox(s.t)).map((row) => [row.payload.type, row.payload.round_id, row.last_error ?? null]);
  const OUT_OF_DATE = "notification is out of date";

  test("drops a turn push once the partner has moved, and keeps the one for the last move", async () => {
    const s = await startPushCouple();
    const first = await move(s.a, await ensure(s.a, "connect_four"), 3);
    await move(s.b, first, 4);
    expect(await claimed(s)).toEqual([["game_turn_ready", "1:2"]]);
    expect(await errors(s)).toEqual([
      ["game_turn_ready", "1:1", OUT_OF_DATE],
      ["game_turn_ready", "1:2", null],
    ]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("drops a turn push when the recipient's turn is a later move, such as a Dots and Boxes extra turn", async () => {
    const s = await startPushCouple();
    const third = await playMoves(s, await ensure(s.a, "dots_and_boxes"), [0, 4, 20]);
    const closed = await move(s.b, third, 21);
    // It is still b's turn, but not the turn the push named.
    expect(closed.turn_user_id).toBe(s.b.userId);
    expect(await claimed(s)).toEqual([]);
    await move(s.b, closed, 22);
    expect(await claimed(s)).toEqual([["game_turn_ready", "1:5"]]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("keeps a result push while its game is the current or the previous one, and drops older ones", async () => {
    const s = await startPushCouple();
    // Game 1: a starts and wins. Game 2: b starts and wins. Game 3: a starts.
    const first = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
    const second = await playMoves(s, await rematch(s.a, first), CONNECT_FOUR_WIN);
    await rematch(s.b, second);
    expect(await turnsOf(s, "game_result")).toEqual([
      [s.b.userId, "1:7"],
      [s.a.userId, "2:7"],
    ]);
    // Every turn push of games 1 and 2 is out of date. The result of game 2 is the previous game, and game 3 waits for a.
    expect((await claimed(s)).sort()).toEqual([
      ["game_result", "2:7"],
      ["game_turn_ready", "3:0"],
    ]);
    const droppedResult = (await outbox(s.t)).filter((row) => row.kind === "game_result" && row.payload.round_id === "1:7");
    expect(droppedResult.map((row) => row.last_error)).toEqual([OUT_OF_DATE]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("drops the turn pushes of a finished game and keeps its result push", async () => {
    const s = await startPushCouple();
    await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
    expect(await claimed(s)).toEqual([["game_result", "1:7"]]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("drops every push queued before the relationship ended", async () => {
    const s = await startPushCouple();
    const game = await ensure(s.a, "connect_four");
    await move(s.a, game, 3);
    await s.a.as.mutation(api.games.send_game_invite, { p_kind: "dots_and_boxes" });
    expect((await outbox(s.t)).map((row) => row.kind).sort()).toEqual(["game_invite", "game_turn_ready"]);
    await endCouple(s.t, s.couple.coupleId, s.a.userId);
    expect(await claim(s)).toEqual([]);
    for (const row of await outbox(s.t)) {
      expect(row).toMatchObject({ last_error: "notification target is no longer eligible" });
      expect(row.failed_at).toBeDefined();
    }
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("turn reminder", () => {
  const reminders = (s: Setup) => pushesOf(s.t, "game_turn_reminder");

  test("goes out once after 72 hours to the partner whose turn it is, and again only for a new turn", async () => {
    const s = await startPushCouple();
    const game = await ensure(s.a, "connect_four");

    hours(71);
    expect(await runReminders(s)).toBe(0);
    hours(1);
    expect(await runReminders(s)).toBe(1);
    expect(await runReminders(s)).toBe(0);
    hours(10);
    expect(await runReminders(s)).toBe(0);
    let rows = await reminders(s);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({
      recipient_user_id: s.a.userId,
      title: "Your turn in Connect Four",
      body: "Open Paeonia to take your turn.",
    });
    expect(rows[0].payload).toEqual({
      type: "game_turn_reminder",
      game_kind: "connect_four",
      couple_id: s.couple.coupleId,
      game_id: game.id,
      round_id: "1:0",
      actor_user_id: s.b.userId,
      route: "games",
      deeplink: "paeonia://games/connect-four",
    });

    // a finally moves. The turn passes to b and b's wait starts now.
    await move(s.a, await gameOf(s.a, "connect_four"), 3);
    hours(73);
    expect(await runReminders(s)).toBe(1);
    expect(await runReminders(s)).toBe(0);
    rows = await reminders(s);
    expect(rows.map((row) => row.recipient_user_id)).toEqual([s.a.userId, s.b.userId]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("sends one reminder for each game, whichever kinds the couple plays", async () => {
    const s = await startPushCouple();
    for (const kind of ALL_KINDS) await ensure(s.a, kind);
    hours(73);
    expect(await runReminders(s)).toBe(ALL_KINDS.length);
    expect(await runReminders(s)).toBe(0);
    expect((await reminders(s)).map((row) => row.payload.game_kind).sort()).toEqual([...ALL_KINDS].sort());
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("does not change the version, so a move already on its way still goes through", async () => {
    const s = await startPushCouple();
    const game = await ensure(s.a, "connect_four");
    hours(73);
    expect(await runReminders(s)).toBe(1);
    expect((await gameOf(s.a, "connect_four")).version).toBe(game.version);
    expect((await move(s.a, game, 3)).turn_user_id).toBe(s.b.userId);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("never reminds about a finished game", async () => {
    const s = await startPushCouple();
    await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
    hours(200);
    expect(await runReminders(s)).toBe(0);
    expect(await reminders(s)).toEqual([]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("starts over with a rematch", async () => {
    const s = await startPushCouple();
    const done = await playMoves(s, await ensure(s.a, "connect_four"), CONNECT_FOUR_WIN);
    hours(100);
    await rematch(s.a, done);
    hours(73);
    expect(await runReminders(s)).toBe(1);
    expect((await reminders(s)).map((row) => row.recipient_user_id)).toEqual([s.b.userId]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("respects the Games switch and a couple that is no longer active", async () => {
    const s = await startPushCouple();
    await ensure(s.a, "connect_four");
    await s.a.as.mutation(api.identity.set_notification_preference, { p_column: "games_enabled", p_enabled: false });
    hours(80);
    expect(await runReminders(s)).toBe(0);
    expect(await outbox(s.t)).toEqual([]);

    const other = await startPushCouple();
    await ensure(other.a, "dots_and_boxes");
    await endCouple(other.t, other.couple.coupleId, other.a.userId);
    hours(80);
    expect(await runReminders(other)).toBe(0);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
    await other.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the drain keeps a reminder while the turn still waits", async () => {
    const s = await startPushCouple();
    await ensure(s.a, "connect_four");
    hours(73);
    expect(await runReminders(s)).toBe(1);
    expect((await claim(s)).map((item) => [item.payload.type, item.payload.round_id])).toEqual([["game_turn_reminder", "1:0"]]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("the drain drops a reminder once the turn moved on", async () => {
    const s = await startPushCouple();
    const game = await ensure(s.a, "connect_four");
    hours(73);
    expect(await runReminders(s)).toBe(1);
    await move(s.a, game, 3);
    // Only the turn push for b goes out.
    expect((await claim(s)).map((item) => item.payload.type)).toEqual(["game_turn_ready"]);
    expect((await reminders(s)).map((row) => row.last_error)).toEqual(["notification is out of date"]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });

  test("a reminder that waited in the outbox never goes out for a later turn of the same person", async () => {
    const s = await startPushCouple();
    const game = await ensure(s.a, "connect_four");
    hours(73);
    expect(await runReminders(s)).toBe(1);
    // a moves and b replies before the drain runs. The turn is a's again, but a later one.
    const after = await move(s.a, game, 3);
    await move(s.b, after, 3);
    hours(73);
    expect(await runReminders(s)).toBe(1);
    // Only the reminder for the new turn and nothing for the old one.
    const sent = (await claim(s)).filter((item) => item.payload.type === "game_turn_reminder");
    expect(sent.map((item) => item.payload.round_id)).toEqual(["1:2"]);
    await s.t.finishAllScheduledFunctions(vi.runAllTimers);
  });
});

describe("relationship end", () => {
  const BOARD_TABLES = ["board_games", "board_game_marks", "board_game_history"] as const;
  const count = (t: TestConvex, coupleId: string) =>
    t.run(async (ctx) => {
      const result: Record<string, number> = {};
      for (const table of BOARD_TABLES) {
        result[table] = (await ctx.db.query(table).collect()).filter((row) => row.couple_id === coupleId).length;
      }
      return result;
    });

  async function playedCouple() {
    const s = await startCouple();
    for (const kind of ALL_KINDS) await move(s.a, await ensure(s.a, kind), OPENING_MOVE[kind]);
    await playMoves(s, await gameOf(s.a, "connect_four"), CONNECT_FOUR_WIN.slice(1));
    await s.a.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: "aGVsbG8=" });
    await s.b.as.mutation(api.boardGames.set_board_game_mark, { p_drawing: "AAAA" });
    return s;
  }

  test("cleanup deletes the games and marks of the couple", async () => {
    const s = await playedCouple();
    expect(await count(s.t, s.couple.coupleId)).toEqual({ board_games: 4, board_game_marks: 2, board_game_history: 1 });

    await s.a.as.mutation(api.relationship.leave_relationship, op());
    // The rows stay until the content is cleaned up.
    expect(await count(s.t, s.couple.coupleId)).toEqual({ board_games: 4, board_game_marks: 2, board_game_history: 1 });
    await s.t.mutation(internal.relationship.cleanup_expired_relationship_content, { p_now: "2027-01-01T00:00:00.000Z" });
    expect(await count(s.t, s.couple.coupleId)).toEqual({ board_games: 0, board_game_marks: 0, board_game_history: 0 });
  });

  test("another couple on the same deployment keeps its rows", async () => {
    const s = await playedCouple();
    const other = await createCouple(s.t);
    await other.first.as.mutation(api.games.set_game_settings, { p_play_style: "together", p_language: "en" });
    await ensure(other.first, "connect_four");
    await s.a.as.mutation(api.relationship.leave_relationship, op());
    await s.t.mutation(internal.relationship.cleanup_expired_relationship_content, { p_now: "2027-01-01T00:00:00.000Z" });
    expect(await count(s.t, other.coupleId)).toEqual({ board_games: 1, board_game_marks: 0, board_game_history: 0 });
  });

  test("the game row count is exact although the backend is registered for four kinds", async () => {
    const s = await playedCouple();
    // 1 settings row, 4 games, 2 marks and 1 finished game.
    const deleted = await s.t.run(async (ctx) => {
      const { deleteCoupleGameRows } = await import("./lib/gameRegistry");
      return await deleteCoupleGameRows(ctx, s.couple.coupleId);
    });
    expect(deleted).toBe(8);
    expect(await count(s.t, s.couple.coupleId)).toEqual({ board_games: 0, board_game_marks: 0, board_game_history: 0 });
  });

  test("a purge without an earlier cleanup still removes the rows", async () => {
    const s = await playedCouple();
    await s.t.run(async (ctx) => {
      const { purgeCoupleContent } = await import("./lib/relationshipCleanup");
      const couple = (await ctx.db.query("couples").first())!;
      await purgeCoupleContent(ctx, couple);
    });
    expect(await count(s.t, s.couple.coupleId)).toEqual({ board_games: 0, board_game_marks: 0, board_game_history: 0 });
  });
});

describe("push copy", () => {
  const NAMES = {
    connect_four: { en: "Connect Four", nb: "Fire på rad" },
    dots_and_boxes: { en: "Dots and Boxes", nb: "Prikker og streker" },
    ultimate_tic_tac_toe: { en: "Ultimate Tic-Tac-Toe", nb: "Ultimat bondesjakk" },
    ludo: { en: "Ludo", nb: "Ludo" },
  } as const;
  // The exact lock-screen text of every board game push. "First Partner" is the partner's profile name.
  const WORDING = {
    en: {
      game_turn_ready: (name: string) => [`Your turn in ${name}`, "Open Paeonia to make your move."],
      game_turn_reminder: (name: string) => [`Your turn in ${name}`, "Open Paeonia to take your turn."],
      game_result: (name: string) => [`Your game of ${name} is over`, "Open Paeonia to see how it ended."],
      game_invite: (name: string) => [`First Partner wants to play ${name} with you`, "Open Paeonia to join in."],
    },
    nb: {
      game_turn_ready: (name: string) => [`Din tur i ${name}`, "Åpne Paeonia for å gjøre trekket ditt."],
      game_turn_reminder: (name: string) => [`Din tur i ${name}`, "Åpne Paeonia for å ta turen din."],
      game_result: (name: string) => [`Spillet deres i ${name} er ferdig`, "Åpne Paeonia for å se hvordan det endte."],
      game_invite: (name: string) => [`First Partner vil spille ${name} med deg`, "Åpne Paeonia for å bli med."],
    },
  } as const;

  test.each(ALL_KINDS)("%s has its title and body in English and Norwegian Bokmål", async (kind) => {
    const t = newTest();
    const couple = await createCouple(t);
    const payload = { game_kind: kind, actor_user_id: couple.first.userId };
    for (const language of ["en", "nb"] as const) {
      for (const push of ["game_turn_ready", "game_turn_reminder", "game_result", "game_invite"] as const) {
        const title = await t.run((ctx) => notificationAlertTitle(ctx, push, payload, language));
        expect([title, notificationAlertBody(push, payload, language)]).toEqual(WORDING[language][push](NAMES[kind][language]));
      }
    }
  });
});
