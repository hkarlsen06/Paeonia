import { describe, expect, test } from "vitest";
import { replay, type BoardPlayer } from "./boardGames";
import {
  LUDO_SAFE_SQUARES,
  ludoCanMove,
  ludoDecode,
  ludoLegalChoices,
  ludoMove,
  ludoPawnIndex,
  ludoRules as rules,
  ludoStartSquare,
  ludoTrackSquare,
  type LudoState,
} from "./ludo";

/**
 * Fixture games, shared with ios/PaeoniaAppTests/Games/BoardGames/Ludo/LudoBoardTests.swift.
 * Copy the moves, progress, next and winner verbatim in both places. Progress is
 * [player 1 pawn 0, player 1 pawn 1, player 2 pawn 0, player 2 pawn 1]. `next` is who rolls next
 * and `winner` is null while the game goes on.
 *
 * exitAndWalk: a 6 brings a pawn out and rolls again, a 5 walks it, and player 2 passes on a 2.
 * capture: player 1 lands on square 28 and sends player 2's pawn home, which rolls again.
 * safeSquare: player 1 lands on square 26 where player 2 has a pawn, and nobody is sent home.
 * playerOneWins and playerTwoWins: whole games with captures, passes and exact finishes.
 */
const FIXTURES: readonly { name: string; moves: readonly number[]; progress: readonly number[]; next: BoardPlayer; winner: BoardPlayer | null }[] = [
  { name: "exitAndWalk", moves: [15, 12, 5], progress: [6, 0, 0, 0], next: 1, winner: null },
  { name: "capture", moves: [15, 15, 15, 15, 15, 6, 15, 3, 0], progress: [29, 0, 0, 0], next: 1, winner: null },
  { name: "safeSquare", moves: [15, 15, 15, 15, 15, 0, 15, 16, 3, 0], progress: [27, 0, 3, 1], next: 2, winner: null },
  {
    name: "playerOneWins",
    moves: [
      15, 3, 11, 3, 11, 6, 14, 6, 5, 3, 14, 12, 15, 3, 12, 6, 3, 0, 12, 16, 9, 6, 0, 0, 16, 4, 9, 15, 0, 13, 9, 13, 12, 16, 4, 6, 5, 13, 2, 13, 14, 10,
      14, 15, 7, 16, 16, 4, 1, 16, 1, 6, 10, 9, 7, 10, 13, 14, 9, 5, 1, 16, 7, 12, 4, 15, 0, 1, 15, 12, 1, 0, 16, 7, 15, 6, 1, 3, 7, 10, 4, 8, 10, 14,
      13, 15, 9, 13, 9, 13, 6, 10, 0, 13, 12, 4, 0, 17, 4,
    ],
    progress: [57, 57, 19, 57],
    next: 1,
    winner: 1,
  },
  {
    name: "playerTwoWins",
    moves: [
      11, 16, 1, 2, 10, 8, 7, 16, 7, 16, 1, 10, 13, 4, 10, 4, 4, 1, 13, 4, 10, 7, 10, 10, 16, 7, 7, 4, 10, 16, 10, 11, 16, 13, 1, 4, 5, 7, 8, 15, 10, 14,
      12, 8, 7, 5, 0, 5, 6, 15, 6, 9, 9, 16, 1, 11, 9, 8, 15, 4, 15, 9, 9, 15, 9, 3, 3, 3, 12, 16, 16, 0, 3, 7, 12, 12, 15, 15, 12, 4, 9, 1, 3, 4, 3, 7,
      17, 6, 11, 12, 14, 4, 14, 10, 8, 13, 8, 13, 1,
    ],
    progress: [43, 34, 57, 57],
    next: 2,
    winner: 2,
  },
];

function fixtureNamed(name: string) {
  return FIXTURES.find((entry) => entry.name === name)!;
}

function play(moves: readonly number[]): LudoState {
  const state = replay(rules, moves);
  if (state === null) throw new Error(`illegal move list ${JSON.stringify(moves)}`);
  return state;
}

function at(progress: readonly number[], next: BoardPlayer = 1): LudoState {
  return { progress, next, outcome: null };
}

/** The progress a player's pawn has when it stands on a track square. */
function progressOn(player: BoardPlayer, square: number): number {
  return ((square - ludoStartSquare(player) + 52) % 52) + 1;
}

/** The state after `die` with `choice`, or throws when the move is illegal. */
function roll(state: LudoState, die: number, choice: number): LudoState {
  const after = rules.apply(state, ludoMove(die, choice));
  if (after === null) throw new Error(`illegal move die ${die} choice ${choice}`);
  return after;
}

describe("move numbers and squares", () => {
  test("a move is (die - 1) * 3 + choice", () => {
    expect(ludoMove(1, 0)).toBe(0);
    expect(ludoMove(1, 2)).toBe(2);
    expect(ludoMove(2, 0)).toBe(3);
    expect(ludoMove(6, 0)).toBe(15);
    expect(ludoMove(6, 2)).toBe(17);
    expect(rules.moveLimit).toBe(18);
  });

  test("decode reads back every move and rejects everything else", () => {
    for (let move = 0; move < 18; move++) {
      const { die, choice } = ludoDecode(move)!;
      expect(ludoMove(die, choice)).toBe(move);
    }
    expect(ludoDecode(17)).toEqual({ die: 6, choice: 2 });
    expect(ludoDecode(4)).toEqual({ die: 2, choice: 1 });
    for (const bad of [-1, 18, 1.5, Number.NaN, Number.POSITIVE_INFINITY, -0]) expect(ludoDecode(bad)).toBeNull();
  });

  test("start squares are 0 and 26 and the safe squares are the starts and the square 8 past each", () => {
    expect(ludoStartSquare(1)).toBe(0);
    expect(ludoStartSquare(2)).toBe(26);
    expect([...LUDO_SAFE_SQUARES].sort((a, b) => a - b)).toEqual([0, 8, 13, 21, 26, 34, 39, 47]);
  });

  test("progress 1 to 51 is the track from the player's start square, nothing else is", () => {
    expect(ludoTrackSquare(1, 1)).toBe(0);
    expect(ludoTrackSquare(1, 51)).toBe(50);
    expect(ludoTrackSquare(2, 1)).toBe(26);
    expect(ludoTrackSquare(2, 26)).toBe(51);
    expect(ludoTrackSquare(2, 27)).toBe(0);
    expect(ludoTrackSquare(2, 51)).toBe(24);
    for (const progress of [0, 52, 56, 57]) {
      expect(ludoTrackSquare(1, progress)).toBeNull();
      expect(ludoTrackSquare(2, progress)).toBeNull();
    }
  });

  test("pawn indexes are 0 and 1 for player 1 and 2 and 3 for player 2", () => {
    expect([ludoPawnIndex(1, 0), ludoPawnIndex(1, 1), ludoPawnIndex(2, 0), ludoPawnIndex(2, 1)]).toEqual([0, 1, 2, 3]);
  });
});

describe("initial board", () => {
  test("all four pawns wait in their bases and player 1 moves first", () => {
    expect(rules.initial()).toEqual({ progress: [0, 0, 0, 0], next: 1, outcome: null });
    expect(rules.next(rules.initial())).toBe(1);
    expect(rules.outcome(rules.initial())).toBeNull();
  });
});

describe("leaving the base", () => {
  test("a pawn in the base can move only on a 6", () => {
    for (let die = 1; die <= 5; die++) expect(ludoCanMove(0, die)).toBe(false);
    expect(ludoCanMove(0, 6)).toBe(true);
    expect(ludoLegalChoices(rules.initial(), 6)).toEqual([0, 1]);
  });

  test("a 6 puts the pawn on its start square and gives another roll", () => {
    const after = roll(rules.initial(), 6, 1);
    expect(after.progress).toEqual([0, 1, 0, 0]);
    expect(after.next).toBe(1);
    expect(roll(at([0, 0, 0, 0], 2), 6, 0).progress).toEqual([0, 0, 1, 0]);
  });

  test("a pawn in the base can't move on 1 to 5 and the pass is the only move", () => {
    for (let die = 1; die <= 5; die++) {
      expect(ludoLegalChoices(rules.initial(), die)).toEqual([2]);
      expect(rules.apply(rules.initial(), ludoMove(die, 0))).toBeNull();
      expect(rules.apply(rules.initial(), ludoMove(die, 1))).toBeNull();
    }
  });

  test("a pawn on the track moves while the other waits in the base", () => {
    expect(ludoLegalChoices(at([5, 0, 0, 0]), 3)).toEqual([0]);
    expect(rules.apply(at([5, 0, 0, 0]), ludoMove(3, 1))).toBeNull();
    expect(roll(at([5, 0, 0, 0]), 3, 0).progress).toEqual([8, 0, 0, 0]);
  });

  test("both choices are legal when both pawns can move", () => {
    expect(ludoLegalChoices(at([5, 9, 0, 0]), 2)).toEqual([0, 1]);
    expect(roll(at([5, 9, 0, 0]), 2, 1).progress).toEqual([5, 11, 0, 0]);
  });

  test("a pawn leaving the base onto a safe start square never captures", () => {
    // Player 2's pawn at progress 27 stands on square 0, player 1's start square.
    const after = roll(at([0, 0, 27, 0]), 6, 0);
    expect(after.progress).toEqual([1, 0, 27, 0]);
  });
});

describe("turns and extra rolls", () => {
  test("a plain move passes the turn", () => {
    expect(roll(at([5, 0, 0, 0]), 3, 0).next).toBe(2);
    expect(roll(at([0, 0, 5, 0], 2), 3, 0).next).toBe(1);
  });

  test("a 6 gives another roll", () => {
    const after = roll(at([5, 0, 0, 0]), 6, 0);
    expect(after.progress).toEqual([11, 0, 0, 0]);
    expect(after.next).toBe(1);
  });

  test("a pawn reaching home gives another roll without a 6", () => {
    const after = roll(at([52, 3, 0, 0]), 5, 0);
    expect(after.progress).toEqual([57, 3, 0, 0]);
    expect(after.next).toBe(1);
    expect(after.outcome).toBeNull();
  });

  test("a capture gives another roll without a 6", () => {
    const after = roll(at([10, 0, 37, 0]), 1, 0);
    expect(after.next).toBe(1);
  });

  test("player 2 gets the same extra rolls", () => {
    expect(roll(at([0, 0, 5, 0], 2), 6, 0).next).toBe(2);
    expect(roll(at([0, 0, 5, 0], 2), 2, 0).next).toBe(1);
  });
});

describe("captures", () => {
  test("landing on a partner pawn sends it back to its base", () => {
    // Player 1 at progress 10 is on square 9. Moving 1 lands on square 10, where player 2's progress 37 stands.
    expect(ludoTrackSquare(2, 37)).toBe(10);
    expect(roll(at([10, 0, 37, 0]), 1, 0).progress).toEqual([11, 0, 0, 0]);
  });

  test("every partner pawn on the square goes back", () => {
    expect(roll(at([10, 0, 37, 37]), 1, 0).progress).toEqual([11, 0, 0, 0]);
  });

  test("partner pawns on other squares stay", () => {
    expect(roll(at([10, 0, 37, 38]), 1, 0).progress).toEqual([11, 0, 0, 38]);
  });

  test("player 2 captures player 1 the same way", () => {
    // Progress 30 for player 1 is square 29. Player 2 at 3 is on square 28 and moves 1 onto it.
    expect(roll(at([30, 0, 3, 0], 2), 1, 0).progress).toEqual([0, 0, 4, 0]);
  });

  test("captures work across the wrap from square 51 to square 0", () => {
    expect(ludoTrackSquare(2, 29)).toBe(2);
    expect(roll(at([2, 0, 0, 29]), 1, 0).progress).toEqual([3, 0, 0, 0]);
  });

  test("a pawn on the last track square of its lap can be captured", () => {
    // Player 2's progress 51 is square 24, which is player 1's progress 25.
    expect(roll(at([24, 0, 51, 0]), 1, 0).progress).toEqual([25, 0, 0, 0]);
  });

  test("pawns of the same player on a square don't capture each other", () => {
    expect(roll(at([10, 11, 0, 0]), 1, 0).progress).toEqual([11, 11, 0, 0]);
  });

  test("a pawn walking past a partner pawn does not capture it", () => {
    expect(roll(at([8, 0, 37, 0]), 4, 0).progress).toEqual([12, 0, 37, 0]);
  });

  test("a pawn that walks into its home column captures nothing", () => {
    // Player 1's progress 51 is square 50 and player 2's progress 26 is square 51. Step 52 leaves the track.
    expect(roll(at([51, 0, 26, 0]), 1, 0).progress).toEqual([52, 0, 26, 0]);
  });
});

describe("safe squares", () => {
  test("a pawn landing on a safe square where the partner stands sends nobody home", () => {
    // Player 2's progress 35 is square 8. Player 1's progress 8 is square 7, and 1 more lands on square 8.
    expect(ludoTrackSquare(2, 35)).toBe(8);
    const after = roll(at([8, 0, 35, 0]), 1, 0);
    expect(after.progress).toEqual([9, 0, 35, 0]);
    expect(after.next).toBe(2);
  });

  test("a start square is safe too", () => {
    const after = roll(at([26, 0, 1, 0]), 1, 0);
    expect(after.progress).toEqual([27, 0, 1, 0]);
    expect(after.next).toBe(2);
  });

  test("every safe square is safe for both players", () => {
    for (const square of LUDO_SAFE_SQUARES) {
      for (const mover of [1, 2] as const) {
        const partner = mover === 1 ? 2 : 1;
        const target = progressOn(mover, square);
        if (target === 1) continue; // Reaching the mover's own start square from the base is tested above.
        const progress = [0, 0, 0, 0];
        progress[ludoPawnIndex(mover, 0)] = target - 1;
        progress[ludoPawnIndex(partner, 0)] = progressOn(partner, square);
        const after = roll(at(progress, mover), 1, 0);
        expect(after.progress[ludoPawnIndex(mover, 0)]).toBe(target);
        expect(after.progress[ludoPawnIndex(partner, 0)]).toBe(progressOn(partner, square));
      }
    }
  });
});

describe("the way home", () => {
  test("a pawn walks 51 track squares, then its home column, then home", () => {
    expect(roll(at([50, 0, 0, 0]), 1, 0).progress).toEqual([51, 0, 0, 0]);
    expect(roll(at([51, 0, 0, 0]), 1, 0).progress).toEqual([52, 0, 0, 0]);
    expect(roll(at([51, 0, 0, 0]), 6, 0).progress).toEqual([57, 0, 0, 0]);
  });

  test("the exact number reaches home", () => {
    expect(roll(at([52, 0, 0, 0]), 5, 0).progress).toEqual([57, 0, 0, 0]);
    expect(roll(at([56, 0, 0, 0]), 1, 0).progress).toEqual([57, 0, 0, 0]);
  });

  test("a roll past home is illegal for that pawn", () => {
    expect(rules.apply(at([52, 3, 0, 0]), ludoMove(6, 0))).toBeNull();
    expect(rules.apply(at([56, 3, 0, 0]), ludoMove(2, 0))).toBeNull();
    expect(ludoCanMove(52, 5)).toBe(true);
    expect(ludoCanMove(52, 6)).toBe(false);
    expect(ludoCanMove(57, 1)).toBe(false);
  });

  test("the other pawn can take a roll the first pawn can't", () => {
    expect(ludoLegalChoices(at([56, 3, 0, 0]), 2)).toEqual([1]);
    expect(roll(at([56, 3, 0, 0]), 2, 1).progress).toEqual([56, 5, 0, 0]);
  });

  test("a pawn at home never moves again", () => {
    expect(ludoLegalChoices(at([57, 3, 0, 0]), 4)).toEqual([1]);
    expect(rules.apply(at([57, 3, 0, 0]), ludoMove(4, 0))).toBeNull();
  });
});

describe("passing", () => {
  test("a pass is the only choice when no pawn can move", () => {
    expect(ludoLegalChoices(at([0, 0, 0, 0]), 3)).toEqual([2]);
    expect(ludoLegalChoices(at([56, 57, 0, 0]), 2)).toEqual([2]);
  });

  test("a pass changes nothing but the turn", () => {
    const after = roll(rules.initial(), 3, 2);
    expect(after).toEqual({ progress: [0, 0, 0, 0], next: 2, outcome: null });
  });

  test("a pass on a 6 gives another roll", () => {
    // Both pawns are close to home, so a 6 moves neither.
    const state = at([56, 57, 0, 0]);
    expect(ludoLegalChoices(state, 6)).toEqual([2]);
    const after = roll(state, 6, 2);
    expect(after.progress).toEqual([56, 57, 0, 0]);
    expect(after.next).toBe(1);
  });

  test("a pass is illegal while a pawn could move", () => {
    expect(rules.apply(rules.initial(), ludoMove(6, 2))).toBeNull();
    expect(rules.apply(at([5, 0, 0, 0]), ludoMove(1, 2))).toBeNull();
    expect(rules.apply(at([56, 57, 0, 0]), ludoMove(1, 2))).toBeNull();
    expect(rules.apply(at([56, 57, 0, 0]), ludoMove(2, 2))).not.toBeNull();
  });
});

describe("winning", () => {
  test("the first player with both pawns home wins", () => {
    const after = roll(at([57, 56, 12, 0]), 1, 1);
    expect(after.progress).toEqual([57, 57, 12, 0]);
    expect(after.outcome).toEqual({ winner: 1, line: [] });
    expect(rules.outcome(after)).toEqual({ winner: 1, line: [] });
  });

  test("player 2 can win too", () => {
    const after = roll(at([30, 0, 51, 57], 2), 6, 0);
    expect(after.outcome).toEqual({ winner: 2, line: [] });
  });

  test("a pawn still on the way keeps the game going", () => {
    expect(roll(at([52, 51, 0, 0]), 5, 0).outcome).toBeNull();
    expect(roll(at([57, 52, 0, 0]), 5, 1).outcome).toEqual({ winner: 1, line: [] });
  });

  test("no move is legal once the game is over", () => {
    const done = roll(at([57, 56, 12, 0]), 1, 1);
    for (let move = 0; move < rules.moveLimit; move++) expect(rules.apply(done, move)).toBeNull();
    for (let die = 1; die <= 6; die++) expect(ludoLegalChoices(done, die)).toEqual([]);
  });

  test("a move after the winning move makes the whole move list illegal", () => {
    expect(replay(rules, [...fixtureNamed("playerOneWins").moves, 0])).toBeNull();
    expect(replay(rules, [...fixtureNamed("playerTwoWins").moves, 17])).toBeNull();
  });
});

describe("illegal moves", () => {
  test("anything that isn't a move integer is rejected", () => {
    for (const bad of [-1, 18, 100, 1.5, Number.NaN, Number.POSITIVE_INFINITY, -0]) expect(rules.apply(rules.initial(), bad)).toBeNull();
  });

  test("a pawn that can't move by the die is rejected", () => {
    expect(rules.apply(rules.initial(), ludoMove(5, 0))).toBeNull();
    expect(rules.apply(at([57, 57, 0, 0]), ludoMove(1, 0))).toBeNull();
  });

  test("apply never changes the state it is given", () => {
    const state = at([10, 0, 37, 0]);
    const copy = JSON.stringify(state);
    rules.apply(state, ludoMove(1, 0));
    rules.apply(state, ludoMove(6, 2));
    expect(JSON.stringify(state)).toBe(copy);
  });
});

describe("fixture games", () => {
  for (const fixture of FIXTURES) {
    test(fixture.name, () => {
      const state = play(fixture.moves);
      expect(state.progress).toEqual(fixture.progress);
      expect(state.next).toBe(fixture.next);
      expect(state.outcome?.winner ?? null).toBe(fixture.winner);
    });
  }

  test("capture sends player 2's pawn home on the last move only", () => {
    const fixture = fixtureNamed("capture");
    expect(play(fixture.moves.slice(0, -1)).progress).toEqual([28, 0, 3, 0]);
  });

  test("safeSquare leaves player 2's pawn on square 26", () => {
    const fixture = fixtureNamed("safeSquare");
    expect(play(fixture.moves.slice(0, -1)).progress).toEqual([26, 0, 3, 1]);
  });

  test("the whole games only ever use legal moves and finish on the last move", () => {
    for (const fixture of FIXTURES.filter((entry) => entry.winner !== null)) {
      expect(play(fixture.moves.slice(0, -1)).outcome).toBeNull();
    }
  });
});
