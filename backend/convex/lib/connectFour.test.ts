import { describe, expect, test } from "vitest";
import { replay } from "./boardGames";
import { connectFourLandingRow, connectFourRules as rules, type ConnectFourState } from "./connectFour";

function play(moves: readonly number[]): ConnectFourState {
  const state = replay(rules, moves);
  if (state === null) throw new Error(`illegal move list ${JSON.stringify(moves)}`);
  return state;
}

/** Cell index of a disc in the given row (0 is the top) and column. */
function cell(row: number, column: number): number {
  return row * 7 + column;
}

describe("initial state", () => {
  test("is an empty 7 x 6 board with player 1 to move", () => {
    const state = rules.initial();
    expect(state).toEqual({ cells: new Array(42).fill(0), next: 1, outcome: null, moves: 0 });
    expect(rules.moveLimit).toBe(7);
    expect(rules.next(state)).toBe(1);
    expect(rules.outcome(state)).toBeNull();
  });

  test("returns a fresh object each time", () => {
    expect(rules.initial()).not.toBe(rules.initial());
    expect(rules.initial().cells).not.toBe(rules.initial().cells);
  });
});

describe("dropping discs", () => {
  test("a disc falls to the bottom row and the turn passes", () => {
    const state = play([3]);
    expect(state.cells[cell(5, 3)]).toBe(1);
    expect(state.cells.filter((owner) => owner !== 0)).toHaveLength(1);
    expect(state.next).toBe(2);
    expect(state.moves).toBe(1);
    expect(state.outcome).toBeNull();
  });

  test("discs stack, alternating players", () => {
    const state = play([3, 3, 3]);
    expect(state.cells[cell(5, 3)]).toBe(1);
    expect(state.cells[cell(4, 3)]).toBe(2);
    expect(state.cells[cell(3, 3)]).toBe(1);
    expect(state.next).toBe(2);
    expect(state.moves).toBe(3);
  });

  test("the landing row is the lowest empty cell of the column", () => {
    const state = play([2, 2]);
    expect(connectFourLandingRow(rules.initial(), 0)).toBe(5);
    expect(connectFourLandingRow(state, 2)).toBe(3);
    expect(connectFourLandingRow(state, 1)).toBe(5);
    expect(connectFourLandingRow(play([0, 0, 0, 0, 0]), 0)).toBe(0);
  });

  test("the landing row is null for a full column or a bad column", () => {
    const state = play([0, 0, 0, 0, 0, 0]);
    expect(connectFourLandingRow(state, 0)).toBeNull();
    for (const column of [-1, 7, 0.5, Number.NaN, Number.POSITIVE_INFINITY, -0]) {
      expect(connectFourLandingRow(rules.initial(), column)).toBeNull();
    }
  });
});

describe("illegal moves", () => {
  test("out of range and non-integer columns", () => {
    const state = rules.initial();
    for (const move of [-1, 7, 8, 42, 0.5, 2.0000001, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY, -0]) {
      expect(rules.apply(state, move)).toBeNull();
    }
  });

  test("a full column", () => {
    const state = play([0, 0, 0, 0, 0, 0]);
    expect(state.cells.filter((owner) => owner !== 0)).toHaveLength(6);
    expect(state.outcome).toBeNull();
    expect(rules.apply(state, 0)).toBeNull();
    expect(rules.apply(state, 1)).not.toBeNull();
  });

  test("any column after the game ended", () => {
    const won = play([0, 1, 0, 1, 0, 1, 0]);
    expect(won.outcome).not.toBeNull();
    for (let column = 0; column < 7; column++) expect(rules.apply(won, column)).toBeNull();
  });
});

describe("winning", () => {
  test("three in a row is not a win", () => {
    expect(play([0, 0, 1, 1, 2]).outcome).toBeNull();
  });

  test("horizontal", () => {
    const state = play([0, 0, 1, 1, 2, 2, 3]);
    expect(state.outcome).toEqual({ winner: 1, line: [cell(5, 0), cell(5, 1), cell(5, 2), cell(5, 3)] });
    expect(state.outcome?.line).toEqual([35, 36, 37, 38]);
    expect(rules.outcome(state)).toBe(state.outcome);
  });

  test("vertical", () => {
    const state = play([0, 1, 0, 1, 0, 1, 0]);
    expect(state.outcome).toEqual({ winner: 1, line: [14, 21, 28, 35] });
  });

  test("diagonal rising to the right", () => {
    const state = play([0, 1, 1, 2, 2, 3, 2, 3, 4, 3, 3]);
    expect(state.outcome).toEqual({ winner: 1, line: [17, 23, 29, 35] });
    expect(state.cells[cell(2, 3)]).toBe(1);
    expect(state.cells[cell(5, 0)]).toBe(1);
  });

  test("diagonal falling to the right", () => {
    const state = play([6, 5, 5, 4, 4, 3, 4, 3, 2, 3, 3]);
    expect(state.outcome).toEqual({ winner: 1, line: [17, 25, 33, 41] });
  });

  test("player 2 can win", () => {
    const state = play([0, 3, 0, 4, 1, 5, 1, 2]);
    expect(state.outcome).toEqual({ winner: 2, line: [37, 38, 39, 40] });
  });

  test("a run of five lights every cell", () => {
    const state = play([0, 0, 1, 1, 3, 3, 4, 4, 2]);
    expect(state.outcome).toEqual({ winner: 1, line: [35, 36, 37, 38, 39] });
  });

  test("two runs through the last disc light both", () => {
    // Player 1's last disc at row 5, column 3 finishes the bottom row (columns 0 to 3) and the rising diagonal to column 6.
    const state = play([0, 4, 1, 5, 2, 5, 4, 6, 5, 6, 1, 6, 6, 0, 3]);
    expect(state.moves).toBe(15);
    expect(state.outcome).toEqual({ winner: 1, line: [20, 26, 32, 35, 36, 37, 38] });
  });

  test("the winning line ascends and has no duplicates", () => {
    const line = play([0, 4, 1, 5, 2, 5, 4, 6, 5, 6, 1, 6, 6, 0, 3]).outcome?.line ?? [];
    expect(line).toEqual([...new Set(line)].sort((a, b) => a - b));
  });
});

describe("drawing", () => {
  // Found by seeded random play. Fills all 42 cells and never makes four in a row.
  const drawnGame = [
    0, 5, 4, 6, 0, 3, 5, 2, 5, 0, 1, 3, 1, 6, 6, 1, 0, 2, 4, 4, 2, 1, 5, 1, 3, 3, 0, 5, 3, 4, 3, 6, 5, 0, 6, 6, 2, 2, 1, 4, 4, 2,
  ];

  test("a full board with no four in a row is a draw", () => {
    expect(drawnGame).toHaveLength(42);
    const before = play(drawnGame.slice(0, 41));
    expect(before.outcome).toBeNull();
    const state = play(drawnGame);
    expect(state.moves).toBe(42);
    expect(state.cells.every((owner) => owner !== 0)).toBe(true);
    expect(state.outcome).toEqual({ winner: null, line: [] });
  });

  test("no move is legal on the drawn board", () => {
    const state = play(drawnGame);
    for (let column = 0; column < 7; column++) expect(rules.apply(state, column)).toBeNull();
  });
});

describe("apply", () => {
  test("never mutates the state it is given", () => {
    const state = play([3, 3, 4]);
    const snapshot = structuredClone(state);
    rules.apply(state, 3);
    rules.apply(state, 99);
    expect(state).toEqual(snapshot);

    const nearlyWon = play([0, 1, 0, 1, 0, 1]);
    const nearlySnapshot = structuredClone(nearlyWon);
    expect(rules.apply(nearlyWon, 0)?.outcome).not.toBeNull();
    expect(nearlyWon).toEqual(nearlySnapshot);
  });

  test("the result does not share arrays with the input", () => {
    const state = play([3]);
    const after = rules.apply(state, 4);
    expect(after?.cells).not.toBe(state.cells);
  });
});
