import { describe, expect, test } from "vitest";
import { BOARD_RULES } from "./boardGameRules";
import { BOARD_GAME_KINDS, isMoveInRange, movers, otherPlayer, replay, type BoardRules } from "./boardGames";
import { connectFourRules } from "./connectFour";
import { dotsAndBoxesRules } from "./dotsAndBoxes";
import { ultimateTicTacToeRules } from "./ultimateTicTacToe";

describe("rules map", () => {
  test("has rules for every game kind", () => {
    expect(Object.keys(BOARD_RULES).sort()).toEqual([...BOARD_GAME_KINDS].sort());
    expect(BOARD_RULES.connect_four).toBe(connectFourRules);
    expect(BOARD_RULES.dots_and_boxes).toBe(dotsAndBoxesRules);
    expect(BOARD_RULES.ultimate_tic_tac_toe).toBe(ultimateTicTacToeRules);
  });

  test("move limits", () => {
    expect(BOARD_RULES.connect_four.moveLimit).toBe(7);
    expect(BOARD_RULES.dots_and_boxes.moveLimit).toBe(40);
    expect(BOARD_RULES.ultimate_tic_tac_toe.moveLimit).toBe(81);
  });
});

describe("helpers", () => {
  test("otherPlayer", () => {
    expect(otherPlayer(1)).toBe(2);
    expect(otherPlayer(2)).toBe(1);
  });

  test("isMoveInRange accepts integers below the limit only", () => {
    expect(isMoveInRange(0, 7)).toBe(true);
    expect(isMoveInRange(6, 7)).toBe(true);
    for (const move of [-1, 7, 0.5, Number.NaN, Number.POSITIVE_INFINITY, -0]) expect(isMoveInRange(move, 7)).toBe(false);
  });
});

describe("replay", () => {
  test("an empty move list is the initial state", () => {
    expect(replay(connectFourRules, [])).toEqual(connectFourRules.initial());
    expect(replay(dotsAndBoxesRules, [])).toEqual(dotsAndBoxesRules.initial());
    expect(replay(ultimateTicTacToeRules, [])).toEqual(ultimateTicTacToeRules.initial());
  });

  test("applies the moves in order", () => {
    const state = replay(connectFourRules, [3, 3, 4]);
    expect(state?.cells[38]).toBe(1);
    expect(state?.cells[31]).toBe(2);
    expect(state?.cells[39]).toBe(1);
    expect(state?.moves).toBe(3);
  });

  test("returns null when any move is illegal", () => {
    expect(replay(connectFourRules, [0, 0, 0, 0, 0, 0, 0])).toBeNull();
    expect(replay(connectFourRules, [0, 7])).toBeNull();
    expect(replay(connectFourRules, [0, 1, 0, 1, 0, 1, 0, 2])).toBeNull();
    expect(replay(dotsAndBoxesRules, [5, 5])).toBeNull();
    expect(replay(dotsAndBoxesRules, [40])).toBeNull();
    expect(replay(ultimateTicTacToeRules, [0, 9])).toBeNull();
    expect(replay(ultimateTicTacToeRules, [0, 0])).toBeNull();
  });

  test("returns null for moves that are not integers", () => {
    expect(replay(connectFourRules, [Number.NaN])).toBeNull();
    expect(replay(dotsAndBoxesRules, [1.5])).toBeNull();
  });
});

describe("movers", () => {
  test("alternate when no one moves twice", () => {
    expect(movers(connectFourRules, [])).toEqual([]);
    expect(movers(connectFourRules, [0, 1, 2, 3])).toEqual([1, 2, 1, 2]);
    expect(movers(ultimateTicTacToeRules, [4, 36, 8, 72, 0])).toEqual([1, 2, 1, 2, 1]);
  });

  test("Dots and Boxes: a closed box gives the mover another move", () => {
    // Player 2 closes box 0 with line 21 and draws line 22 right after.
    expect(movers(dotsAndBoxesRules, [0, 4, 20, 21, 22])).toEqual([1, 2, 1, 2, 2]);
    expect(movers(dotsAndBoxesRules, [0, 4, 20, 21, 22, 23])).toEqual([1, 2, 1, 2, 2, 1]);
  });

  test("Dots and Boxes: closing two boxes with one line also gives another move", () => {
    expect(movers(dotsAndBoxesRules, [0, 1, 4, 5, 20, 22, 21, 39])).toEqual([1, 2, 1, 2, 1, 2, 1, 1]);
  });

  test("returns null when any move is illegal", () => {
    expect(movers(connectFourRules, [0, 7])).toBeNull();
    expect(movers(dotsAndBoxesRules, [3, 3])).toBeNull();
    expect(movers(ultimateTicTacToeRules, [0, 40])).toBeNull();
  });

  test("returns null for a move after the game ended", () => {
    expect(movers(connectFourRules, [0, 1, 0, 1, 0, 1, 0, 2])).toBeNull();
  });
});

/** A small seeded random number generator (mulberry32) so a failing game can be replayed. */
function seededRandom(seed: number): () => number {
  let a = seed;
  return () => {
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

interface RandomGame<S> {
  moves: number[];
  /** states[i] is the state after i moves, so states[0] is the initial state and the last entry is the finished game. */
  states: S[];
  /** legal[i] is the sorted list of moves that were legal in states[i]. */
  legal: number[][];
}

/** Plays random legal moves until the game ends. Fails if apply mutates a state or the game does not end. */
function playRandomGame<S>(rules: BoardRules<S>, seed: number): RandomGame<S> {
  const random = seededRandom(seed);
  const game: RandomGame<S> = { moves: [], states: [rules.initial()], legal: [] };
  for (let step = 0; step < 200; step++) {
    const state = game.states[step];
    const snapshot = JSON.stringify(state);
    const legal: number[] = [];
    for (let move = 0; move < rules.moveLimit; move++) {
      if (rules.apply(state, move) !== null) legal.push(move);
    }
    expect(JSON.stringify(state), `apply mutated the state at step ${step}`).toBe(snapshot);
    game.legal.push(legal);
    if (rules.outcome(state) !== null) return game;
    expect(legal.length, `no legal move at step ${step} of an unfinished game`).toBeGreaterThan(0);
    const move = legal[Math.floor(random() * legal.length)];
    game.moves.push(move);
    game.states.push(rules.apply(state, move) as S);
  }
  throw new Error(`game with seed ${seed} did not end`);
}

const SEEDS = Array.from({ length: 150 }, (_, index) => index + 1);

/** Checks that hold for every game. */
function expectConsistentGame<S>(rules: BoardRules<S>, game: RandomGame<S>, maxMoves: number): void {
  const { moves, states, legal } = game;
  const final = states[states.length - 1];
  const outcome = rules.outcome(final);
  expect(moves.length).toBeLessThanOrEqual(maxMoves);
  expect(outcome).not.toBeNull();
  expect(legal[legal.length - 1]).toEqual([]);
  for (const state of states.slice(0, -1)) expect(rules.outcome(state)).toBeNull();
  if (outcome === null) return;
  expect(outcome.line).toEqual([...new Set(outcome.line)].sort((a, b) => a - b));
  expect(replay(rules, moves)).toEqual(final);
  expect(movers(rules, moves)).toEqual(states.slice(0, -1).map((state) => rules.next(state)));
  for (const move of [...moves, -1, rules.moveLimit]) expect(rules.apply(final, move)).toBeNull();
}

describe("random Connect Four games", () => {
  const rules = connectFourRules;

  /** Cells that sit in some window of four equal discs, by player. */
  function cellsInFour(cells: readonly number[]): Record<1 | 2, number[]> {
    const found: Record<1 | 2, Set<number>> = { 1: new Set(), 2: new Set() };
    for (let row = 0; row < 6; row++) {
      for (let column = 0; column < 7; column++) {
        for (const [dc, dr] of [[1, 0], [0, 1], [1, 1], [1, -1]]) {
          const window = [0, 1, 2, 3].map((i) => [row + i * dr, column + i * dc]);
          if (window.some(([r, c]) => r < 0 || r > 5 || c < 0 || c > 6)) continue;
          const owners = window.map(([r, c]) => cells[r * 7 + c]);
          if (owners[0] !== 0 && owners.every((owner) => owner === owners[0])) {
            for (const [r, c] of window) found[owners[0] as 1 | 2].add(r * 7 + c);
          }
        }
      }
    }
    return { 1: [...found[1]].sort((a, b) => a - b), 2: [...found[2]].sort((a, b) => a - b) };
  }

  test.each(SEEDS)("seed %i", (seed) => {
    const game = playRandomGame(rules, seed);
    expectConsistentGame(rules, game, 42);

    game.states.forEach((state, index) => {
      expect(state.moves).toBe(index);
      expect(state.next).toBe(index % 2 === 0 ? 1 : 2);
      expect(state.cells.filter((owner) => owner !== 0)).toHaveLength(index);
      expect(state.cells.filter((owner) => owner === 1)).toHaveLength(Math.ceil(index / 2));
      // Discs rest on the bottom or on another disc.
      for (let column = 0; column < 7; column++) {
        for (let row = 0; row < 5; row++) {
          if (state.cells[row * 7 + column] !== 0) expect(state.cells[(row + 1) * 7 + column]).not.toBe(0);
        }
      }
      // A column is legal exactly while its top cell is empty.
      if (state.outcome === null) {
        expect(game.legal[index]).toEqual([0, 1, 2, 3, 4, 5, 6].filter((column) => state.cells[column] === 0));
      }
      const fours = cellsInFour(state.cells);
      if (state.outcome === null) {
        expect(fours).toEqual({ 1: [], 2: [] });
      } else if (state.outcome.winner === null) {
        expect(fours).toEqual({ 1: [], 2: [] });
        expect(state.moves).toBe(42);
        expect(state.outcome.line).toEqual([]);
      } else {
        // The game stops at the first four, so every four runs through the last disc.
        expect(fours[state.outcome.winner]).toEqual(state.outcome.line);
        expect(fours[otherPlayer(state.outcome.winner)]).toEqual([]);
        expect(state.outcome.winner).toBe(game.states[index - 1].next);
      }
    });
  });
});

describe("random Dots and Boxes games", () => {
  const rules = dotsAndBoxesRules;

  test.each(SEEDS)("seed %i", (seed) => {
    const game = playRandomGame(rules, seed);
    expectConsistentGame(rules, game, 40);
    expect(game.moves).toHaveLength(40);
    expect([...game.moves].sort((a, b) => a - b)).toEqual(Array.from({ length: 40 }, (_, line) => line));

    // Replay the game with a separate, simple model of the rules.
    const drawn = new Set<number>();
    const owners = new Array<number>(16).fill(0);
    let player: 1 | 2 = 1;
    game.moves.forEach((line, index) => {
      drawn.add(line);
      let closed = 0;
      for (let box = 0; box < 16; box++) {
        const top = Math.floor(box / 4) * 4 + (box % 4);
        const left = 20 + Math.floor(box / 4) * 5 + (box % 4);
        if (owners[box] === 0 && [top, top + 4, left, left + 1].every((side) => drawn.has(side))) {
          owners[box] = player;
          closed += 1;
        }
      }
      expect(closed).toBeLessThanOrEqual(2);
      const after = game.states[index + 1];
      expect(after.lines[line]).toBe(player);
      expect(after.boxes).toEqual(owners);
      if (closed === 0) player = otherPlayer(player);
      expect(after.next).toBe(player);
      expect(after.lines.filter((owner) => owner !== 0)).toHaveLength(index + 1);
    });

    const final = game.states[40];
    const first = owners.filter((owner) => owner === 1).length;
    const second = owners.filter((owner) => owner === 2).length;
    expect(first + second).toBe(16);
    const winner = first > second ? 1 : second > first ? 2 : null;
    expect(final.outcome).toEqual({
      winner,
      line: winner === null ? [] : owners.flatMap((owner, box) => (owner === winner ? [box] : [])),
    });
  });
});

describe("random Ultimate Tic-Tac-Toe games", () => {
  const rules = ultimateTicTacToeRules;
  const LINES = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  /** Status of each small board worked out from the cells alone. */
  function boardStatus(cells: readonly number[]): number[] {
    return Array.from({ length: 9 }, (_, board) => {
      const marks = cells.slice(board * 9, board * 9 + 9);
      for (const player of [1, 2]) {
        if (LINES.some((line) => line.every((cell) => marks[cell] === player))) return player;
      }
      return marks.every((mark) => mark !== 0) ? 3 : 0;
    });
  }

  test.each(SEEDS)("seed %i", (seed) => {
    const game = playRandomGame(rules, seed);
    expectConsistentGame(rules, game, 81);

    game.states.forEach((state, index) => {
      expect(state.boards).toEqual(boardStatus(state.cells));
      expect(state.next).toBe(index % 2 === 0 ? 1 : 2);
      expect(state.cells.filter((owner) => owner !== 0)).toHaveLength(index);

      // forced comes from the last cell played, and the legal moves follow the rules in the spec.
      const forced = index === 0 ? -1 : state.boards[game.moves[index - 1] % 9] === 0 ? game.moves[index - 1] % 9 : -1;
      expect(state.forced).toBe(forced);
      if (state.outcome === null) {
        const expected: number[] = [];
        for (let move = 0; move < 81; move++) {
          const board = Math.floor(move / 9);
          if (state.cells[move] === 0 && state.boards[board] === 0 && (forced === -1 || forced === board)) expected.push(move);
        }
        expect(game.legal[index]).toEqual(expected);
      }

      // The big result worked out from the small boards alone.
      const wins = [1, 2].map((player) => LINES.filter((line) => line.every((board) => state.boards[board] === player)));
      if (wins[0].length + wins[1].length > 0) {
        const player = wins[0].length > 0 ? 1 : 2;
        expect(wins[player === 1 ? 1 : 0]).toEqual([]);
        expect(state.outcome).toEqual({ winner: player, line: [...new Set(wins[player - 1].flat())].sort((a, b) => a - b) });
        expect(player).toBe(game.states[index - 1].next);
      } else if (state.boards.every((board) => board !== 0)) {
        expect(state.outcome).toEqual({ winner: null, line: [] });
      } else {
        expect(state.outcome).toBeNull();
      }
    });
  });
});
