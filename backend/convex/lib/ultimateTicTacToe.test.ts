import { describe, expect, test } from "vitest";
import { replay } from "./boardGames";
import { ultimateTicTacToeOpenBoards, ultimateTicTacToeRules as rules, type UltimateTicTacToeState } from "./ultimateTicTacToe";

function play(moves: readonly number[]): UltimateTicTacToeState {
  const state = replay(rules, moves);
  if (state === null) throw new Error(`illegal move list ${JSON.stringify(moves)}`);
  return state;
}

/** Cell index of `cell` (0..8) in small board `board` (0..8). */
function at(board: number, cell: number): number {
  return board * 9 + cell;
}

/**
 * A state built by hand. `marks` maps a cell index to its player and `boards` lists the nine
 * board values (0 open, 1 or 2 won, 3 full). Marks are not checked against the boards.
 */
function build(options: {
  marks?: Record<number, 1 | 2>;
  boards?: readonly number[];
  forced?: number;
  next?: 1 | 2;
}): UltimateTicTacToeState {
  const cells = new Array<number>(81).fill(0);
  for (const [index, player] of Object.entries(options.marks ?? {})) cells[Number(index)] = player;
  return {
    cells,
    boards: options.boards ?? new Array<number>(9).fill(0),
    forced: options.forced ?? -1,
    next: options.next ?? 1,
    outcome: null,
  };
}

/** Marks for one small board from a nine-entry picture, where 0 is empty. */
function pictureMarks(board: number, picture: readonly number[]): Record<number, 1 | 2> {
  const marks: Record<number, 1 | 2> = {};
  picture.forEach((player, cell) => {
    if (player !== 0) marks[at(board, cell)] = player as 1 | 2;
  });
  return marks;
}

/** A full small board with no three in a row. Cell 0 is left empty so a test can fill it with player 1. */
const DRAWN_BOARD_MISSING_CELL_0 = [0, 2, 1, 1, 2, 2, 2, 1, 1];

describe("forced board", () => {
  test("the first move can go anywhere", () => {
    for (const move of [0, 40, 80, at(2, 7), at(6, 3)]) {
      expect(rules.apply(rules.initial(), move)).not.toBeNull();
    }
  });

  test("the cell played decides the board the next move must use", () => {
    for (const [move, forced] of [
      [at(0, 0), 0],
      [at(4, 4), 4],
      [at(8, 2), 2],
      [at(3, 7), 7],
    ] as const) {
      const state = play([move]);
      expect(state.forced).toBe(forced);
      expect(state.next).toBe(2);
      expect(state.cells[move]).toBe(1);
      expect(ultimateTicTacToeOpenBoards(state)).toEqual([forced]);
    }
  });

  test("a move in a different board is illegal", () => {
    const state = play([at(0, 5)]);
    expect(state.forced).toBe(5);
    expect(rules.apply(state, at(0, 1))).toBeNull();
    expect(rules.apply(state, at(4, 5))).toBeNull();
    expect(rules.apply(state, at(5, 0))).not.toBeNull();
    expect(rules.apply(state, at(5, 8))).not.toBeNull();
  });

  test("the forced board can be the one just played in", () => {
    const state = play([at(4, 4)]);
    expect(rules.apply(state, at(4, 0))).not.toBeNull();
    expect(rules.apply(state, at(0, 0))).toBeNull();
  });
});

describe("small boards", () => {
  test("three in a row wins the small board and sends the partner anywhere", () => {
    // Player 1 takes the diagonal of board 0 while player 2 is sent around.
    const before = play([at(0, 4), at(4, 0), at(0, 8), at(8, 0)]);
    expect(before.boards[0]).toBe(0);
    expect(before.forced).toBe(0);

    const state = rules.apply(before, at(0, 0));
    expect(state?.boards).toEqual([1, 0, 0, 0, 0, 0, 0, 0, 0]);
    expect(state?.forced).toBe(-1);
    expect(state?.next).toBe(2);
    expect(state?.outcome).toBeNull();
    expect(ultimateTicTacToeOpenBoards(state as UltimateTicTacToeState)).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test("a won board takes no more moves", () => {
    const state = play([at(0, 4), at(4, 0), at(0, 8), at(8, 0), at(0, 0)]);
    expect(rules.apply(state, at(0, 1))).toBeNull();
    expect(rules.apply(state, at(0, 2))).toBeNull();
    expect(rules.apply(state, at(5, 5))).not.toBeNull();
  });

  test("sending the partner to a board that is already won gives a free move", () => {
    const won = play([at(0, 4), at(4, 0), at(0, 8), at(8, 0), at(0, 0)]);
    // Player 2 plays board 5 cell 0, which points at board 0. Board 0 is won, so player 1 may play anywhere open.
    const state = rules.apply(won, at(5, 0));
    expect(state?.forced).toBe(-1);
    expect(state?.next).toBe(1);
    expect(ultimateTicTacToeOpenBoards(state as UltimateTicTacToeState)).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
    expect(rules.apply(state as UltimateTicTacToeState, at(7, 7))).not.toBeNull();
    expect(rules.apply(state as UltimateTicTacToeState, at(0, 1))).toBeNull();
  });

  test("a board won by player 2 shows 2", () => {
    const state = rules.apply(
      build({ marks: { [at(2, 0)]: 2, [at(2, 1)]: 2, [at(2, 5)]: 1 }, forced: 2, next: 2 }),
      at(2, 2),
    );
    expect(state?.boards[2]).toBe(2);
    expect(state?.forced).toBe(-1);
  });

  test("a full board with no winner becomes 3 and sends the partner anywhere", () => {
    const start = build({ marks: pictureMarks(0, DRAWN_BOARD_MISSING_CELL_0), forced: 0 });
    const state = rules.apply(start, at(0, 0));
    expect(state?.cells[at(0, 0)]).toBe(1);
    expect(state?.boards[0]).toBe(3);
    // Cell 0 points back at board 0, which is now full.
    expect(state?.forced).toBe(-1);
    expect(state?.outcome).toBeNull();
    expect(ultimateTicTacToeOpenBoards(state as UltimateTicTacToeState)).toEqual([1, 2, 3, 4, 5, 6, 7, 8]);
    expect(rules.apply(state as UltimateTicTacToeState, at(0, 1))).toBeNull();
  });

  test("a winning move that fills the board makes it a win, not a draw", () => {
    // Board 0 is full after this move, and the move completes the top row.
    const picture = [0, 1, 1, 2, 2, 1, 1, 2, 2];
    const state = rules.apply(build({ marks: pictureMarks(0, picture), forced: 0 }), at(0, 0));
    expect(state?.boards[0]).toBe(1);
  });

  test("sending the partner to a full board gives a free move", () => {
    // Board 3 is full. Player 1 plays board 6 cell 3 and points at it.
    const full = build({ boards: [0, 0, 0, 3, 0, 0, 0, 0, 0], forced: 6 });
    const state = rules.apply(full, at(6, 3));
    expect(state?.forced).toBe(-1);
    expect(rules.apply(state as UltimateTicTacToeState, at(3, 0))).toBeNull();
    expect(rules.apply(state as UltimateTicTacToeState, at(1, 1))).not.toBeNull();
  });
});

describe("illegal moves", () => {
  test("out of range and non-integer cells", () => {
    for (const move of [-1, 81, 82, 1000, 0.5, 40.0001, Number.NaN, Number.POSITIVE_INFINITY, -0]) {
      expect(rules.apply(rules.initial(), move)).toBeNull();
    }
  });

  test("a taken cell", () => {
    const state = play([at(0, 0)]);
    expect(rules.apply(state, at(0, 0))).toBeNull();
    const free = build({ marks: { [at(5, 5)]: 2 } });
    expect(rules.apply(free, at(5, 5))).toBeNull();
    expect(rules.apply(free, at(5, 4))).not.toBeNull();
  });

  test("a move in a closed board even when it is forced by mistake", () => {
    expect(rules.apply(build({ boards: [3, 0, 0, 0, 0, 0, 0, 0, 0], forced: 0 }), at(0, 4))).toBeNull();
  });

  test("any cell after the game ended", () => {
    const end = rules.apply(
      build({ marks: { [at(2, 0)]: 1, [at(2, 1)]: 1 }, boards: [1, 1, 0, 0, 0, 0, 0, 0, 0], forced: 2 }),
      at(2, 2),
    );
    expect(end?.outcome).not.toBeNull();
    for (let move = 0; move < 81; move++) expect(rules.apply(end as UltimateTicTacToeState, move)).toBeNull();
    expect(ultimateTicTacToeOpenBoards(end as UltimateTicTacToeState)).toEqual([]);
  });
});

describe("the big grid", () => {
  test("three won boards in a row win the game", () => {
    const start = build({
      marks: { [at(2, 0)]: 1, [at(2, 1)]: 1 },
      boards: [1, 1, 0, 0, 2, 0, 0, 0, 0],
      forced: 2,
    });
    const state = rules.apply(start, at(2, 2));
    expect(state?.boards[2]).toBe(1);
    expect(state?.outcome).toEqual({ winner: 1, line: [0, 1, 2] });
    expect(rules.outcome(state as UltimateTicTacToeState)).toBe(state?.outcome);
  });

  test("columns and diagonals win too", () => {
    const column = rules.apply(
      build({ marks: { [at(6, 0)]: 2, [at(6, 4)]: 2 }, boards: [2, 0, 0, 2, 0, 0, 0, 1, 0], forced: 6, next: 2 }),
      at(6, 8),
    );
    expect(column?.outcome).toEqual({ winner: 2, line: [0, 3, 6] });

    const diagonal = rules.apply(
      build({ marks: { [at(8, 0)]: 1, [at(8, 1)]: 1 }, boards: [1, 0, 0, 0, 1, 0, 0, 0, 0], forced: 8 }),
      at(8, 2),
    );
    expect(diagonal?.outcome).toEqual({ winner: 1, line: [0, 4, 8] });
    const antiDiagonal = rules.apply(
      build({ marks: { [at(6, 0)]: 1, [at(6, 1)]: 1 }, boards: [0, 0, 1, 0, 1, 0, 0, 0, 0], forced: 6 }),
      at(6, 2),
    );
    expect(antiDiagonal?.outcome).toEqual({ winner: 1, line: [2, 4, 6] });
  });

  test("two lines finishing at once light every board of both", () => {
    // Board 2 closes the top row (0, 1, 2) and the right column (2, 5, 8).
    const start = build({
      marks: { [at(2, 0)]: 1, [at(2, 1)]: 1 },
      boards: [1, 1, 0, 0, 0, 1, 0, 0, 1],
      forced: 2,
    });
    expect(rules.apply(start, at(2, 2))?.outcome).toEqual({ winner: 1, line: [0, 1, 2, 5, 8] });
  });

  test("full boards with no winner never count as a line", () => {
    const start = build({
      marks: { [at(2, 0)]: 1, [at(2, 1)]: 1 },
      boards: [3, 3, 0, 0, 0, 0, 0, 0, 0],
      forced: 2,
    });
    const state = rules.apply(start, at(2, 2));
    expect(state?.boards[2]).toBe(1);
    expect(state?.outcome).toBeNull();
  });

  test("a win beats a draw when the last board closes the line", () => {
    const start = build({
      marks: { [at(2, 0)]: 1, [at(2, 1)]: 1 },
      boards: [1, 1, 0, 3, 3, 3, 3, 3, 3],
      forced: 2,
    });
    const state = rules.apply(start, at(2, 2));
    expect(state?.boards.every((board) => board !== 0)).toBe(true);
    expect(state?.outcome).toEqual({ winner: 1, line: [0, 1, 2] });
  });

  test("every board closed with no three in a row is a draw", () => {
    // Boards 0 to 7 hold 1 2 1 / 1 2 2 / 2 1 and board 8 is about to be filled with a drawn picture.
    const marks = pictureMarks(8, [1, 2, 1, 1, 2, 2, 2, 1, 0]);
    const start = build({ marks, boards: [1, 2, 1, 1, 2, 2, 2, 1, 0], forced: 8 });
    const state = rules.apply(start, at(8, 8));
    expect(state?.boards).toEqual([1, 2, 1, 1, 2, 2, 2, 1, 3]);
    expect(state?.outcome).toEqual({ winner: null, line: [] });
    expect(ultimateTicTacToeOpenBoards(state as UltimateTicTacToeState)).toEqual([]);
  });

  test("the draw also happens when the last board is won without making a line", () => {
    const start = build({
      marks: { [at(8, 0)]: 1, [at(8, 1)]: 1 },
      boards: [1, 2, 1, 1, 2, 2, 2, 1, 0],
      forced: 8,
    });
    const state = rules.apply(start, at(8, 2));
    expect(state?.boards[8]).toBe(1);
    expect(state?.outcome).toEqual({ winner: null, line: [] });
  });
});

describe("open boards", () => {
  test("lists every open board when the move is free", () => {
    expect(ultimateTicTacToeOpenBoards(build({ boards: [1, 0, 2, 3, 0, 0, 1, 0, 3] }))).toEqual([1, 4, 5, 7]);
  });

  test("lists only the forced board otherwise", () => {
    expect(ultimateTicTacToeOpenBoards(build({ forced: 6 }))).toEqual([6]);
  });
});

describe("apply", () => {
  test("never mutates the state it is given", () => {
    const state = play([at(0, 4), at(4, 0), at(0, 8), at(8, 0)]);
    const snapshot = structuredClone(state);
    rules.apply(state, at(0, 0));
    rules.apply(state, at(1, 1));
    rules.apply(state, 999);
    expect(state).toEqual(snapshot);
  });

  test("the result does not share arrays with the input", () => {
    const state = play([at(0, 0)]);
    const after = rules.apply(state, at(0, 1));
    expect(after?.cells).not.toBe(state.cells);
    expect(after?.boards).not.toBe(state.boards);
  });
});
