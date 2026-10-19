import { describe, expect, test } from "vitest";
import { replay } from "./boardGames";
import { boxesOfLine, dotsAndBoxesRules as rules, linesOfBox, type DotsAndBoxesState } from "./dotsAndBoxes";

function play(moves: readonly number[]): DotsAndBoxesState {
  const state = replay(rules, moves);
  if (state === null) throw new Error(`illegal move list ${JSON.stringify(moves)}`);
  return state;
}

/** A board where every line is drawn except `open`, with the given box owners and `next` to move. */
function nearlyDone(open: readonly number[], boxes: readonly number[], next: 1 | 2): DotsAndBoxesState {
  const lines = new Array<number>(40).fill(1);
  for (const line of open) lines[line] = 0;
  return { lines, boxes, next, outcome: null };
}

/** 16 box owners: the first `first` boxes belong to player 1, the next `second` to player 2, the rest are open. */
function boxOwners(first: number, second: number): number[] {
  return Array.from({ length: 16 }, (_, box) => (box < first ? 1 : box < first + second ? 2 : 0));
}

describe("box and line helpers", () => {
  test("linesOfBox lists top, bottom, left, right", () => {
    expect(linesOfBox(0)).toEqual([0, 4, 20, 21]);
    expect(linesOfBox(3)).toEqual([3, 7, 23, 24]);
    expect(linesOfBox(5)).toEqual([5, 9, 26, 27]);
    expect(linesOfBox(15)).toEqual([15, 19, 38, 39]);
  });

  test("boxesOfLine lists the one or two boxes next to a line, ascending", () => {
    expect(boxesOfLine(0)).toEqual([0]);
    expect(boxesOfLine(4)).toEqual([0, 4]);
    expect(boxesOfLine(16)).toEqual([12]);
    expect(boxesOfLine(19)).toEqual([15]);
    expect(boxesOfLine(20)).toEqual([0]);
    expect(boxesOfLine(21)).toEqual([0, 1]);
    expect(boxesOfLine(24)).toEqual([3]);
    expect(boxesOfLine(25)).toEqual([4]);
    expect(boxesOfLine(26)).toEqual([4, 5]);
    expect(boxesOfLine(39)).toEqual([15]);
  });

  test("boxesOfLine is empty for numbers that are not lines", () => {
    for (const line of [-1, 40, 0.5, Number.NaN, -0]) expect(boxesOfLine(line)).toEqual([]);
  });

  test("every box and its four lines agree", () => {
    for (let box = 0; box < 16; box++) {
      const lines = linesOfBox(box);
      expect(new Set(lines).size).toBe(4);
      for (const line of lines) expect(boxesOfLine(line)).toContain(box);
    }
    let borders = 0;
    for (let line = 0; line < 40; line++) {
      const boxes = boxesOfLine(line);
      expect(boxes.length === 1 || boxes.length === 2).toBe(true);
      expect(boxes).toEqual([...boxes].sort((a, b) => a - b));
      for (const box of boxes) expect(linesOfBox(box)).toContain(line);
      borders += boxes.length;
    }
    expect(borders).toBe(64);
  });
});

describe("drawing lines", () => {
  test("a line that closes nothing passes the turn", () => {
    const state = play([0]);
    expect(state.lines[0]).toBe(1);
    expect(state.next).toBe(2);
    expect(state.boxes).toEqual(new Array(16).fill(0));
    expect(play([0, 21]).lines[21]).toBe(2);
  });

  test("the fourth side of a box gives it to the mover, who moves again", () => {
    const three = play([0, 4, 20]);
    expect(three.boxes[0]).toBe(0);
    expect(three.next).toBe(2);

    const state = play([0, 4, 20, 21]);
    expect(state.boxes[0]).toBe(2);
    expect(state.boxes.filter((owner) => owner !== 0)).toHaveLength(1);
    expect(state.next).toBe(2);
    expect(state.outcome).toBeNull();
  });

  test("the turn passes again after the extra move closes nothing", () => {
    expect(play([0, 4, 20, 21, 22]).next).toBe(1);
  });

  test("one line can close two boxes, and the mover moves again", () => {
    // Boxes 0 and 1 each have three sides drawn. Their shared side is line 21.
    const ready = play([0, 1, 4, 5, 20, 22]);
    expect(ready.boxes).toEqual(new Array(16).fill(0));
    expect(ready.next).toBe(1);

    const state = rules.apply(ready, 21);
    expect(state).not.toBeNull();
    expect(state?.boxes[0]).toBe(1);
    expect(state?.boxes[1]).toBe(1);
    expect(state?.boxes.filter((owner) => owner !== 0)).toHaveLength(2);
    expect(state?.next).toBe(1);
  });

  test("a horizontal line can close the box below it", () => {
    // Box 4 sits under box 0 and its top is line 4. Lines 8, 25 and 26 are its other sides.
    const state = play([8, 25, 26, 4]);
    expect(state.boxes[4]).toBe(2);
    expect(state.boxes[0]).toBe(0);
    expect(state.next).toBe(2);
  });

  test("one horizontal line can close the boxes above and below it", () => {
    // Boxes 0 and 4 share line 4. Each has its other three sides drawn.
    const ready = play([0, 20, 21, 8, 25, 26]);
    expect(ready.boxes).toEqual(new Array(16).fill(0));
    const state = rules.apply(ready, 4);
    expect(state?.boxes[0]).toBe(1);
    expect(state?.boxes[4]).toBe(1);
    expect(state?.next).toBe(1);
  });
});

describe("illegal moves", () => {
  test("out of range and non-integer lines", () => {
    const state = rules.initial();
    for (const move of [-1, 40, 41, 100, 0.5, Number.NaN, Number.POSITIVE_INFINITY, -0]) {
      expect(rules.apply(state, move)).toBeNull();
    }
  });

  test("a line that is already drawn", () => {
    const state = play([7, 12]);
    expect(rules.apply(state, 7)).toBeNull();
    expect(rules.apply(state, 12)).toBeNull();
    expect(rules.apply(state, 8)).not.toBeNull();
  });

  test("any line after the game ended", () => {
    const state = rules.apply(nearlyDone([39], boxOwners(8, 7), 2), 39);
    expect(state?.outcome).not.toBeNull();
    if (state === undefined || state === null) return;
    for (let line = 0; line < 40; line++) expect(rules.apply(state, line)).toBeNull();
  });

  test("any undrawn line after an outcome is set", () => {
    expect(rules.apply({ ...rules.initial(), outcome: { winner: 1, line: [] } }, 0)).toBeNull();
  });
});

describe("ending", () => {
  test("the game does not end while a line is missing", () => {
    expect(nearlyDone([39], boxOwners(8, 7), 2).outcome).toBeNull();
    expect(rules.apply(nearlyDone([38, 39], boxOwners(8, 6), 2), 38)?.outcome).toBeNull();
  });

  test("8 to 8 is a draw", () => {
    const state = rules.apply(nearlyDone([39], boxOwners(8, 7), 2), 39);
    expect(state?.boxes.filter((owner) => owner === 1)).toHaveLength(8);
    expect(state?.boxes.filter((owner) => owner === 2)).toHaveLength(8);
    expect(state?.outcome).toEqual({ winner: null, line: [] });
  });

  test("more boxes wins, and the line is the winner's boxes ascending", () => {
    const state = rules.apply(nearlyDone([39], boxOwners(9, 6), 2), 39);
    expect(state?.boxes[15]).toBe(2);
    expect(state?.outcome).toEqual({ winner: 1, line: [0, 1, 2, 3, 4, 5, 6, 7, 8] });
  });

  test("player 2 can win", () => {
    const owners = Array.from({ length: 16 }, (_, box) => (box < 7 ? 1 : box < 15 ? 2 : 0));
    const state = rules.apply(nearlyDone([39], owners, 2), 39);
    expect(state?.outcome).toEqual({ winner: 2, line: [7, 8, 9, 10, 11, 12, 13, 14, 15] });
  });

  test("the last line can close two boxes at once", () => {
    // Boxes 14 and 15 are side by side. Their shared side is the vertical line 38.
    const owners = boxOwners(8, 6);
    owners[14] = 0;
    owners[15] = 0;
    const state = rules.apply(nearlyDone([38], owners, 1), 38);
    expect(state?.boxes[14]).toBe(1);
    expect(state?.boxes[15]).toBe(1);
    expect(state?.outcome).toEqual({ winner: 1, line: [0, 1, 2, 3, 4, 5, 6, 7, 14, 15] });
  });
});

describe("whole games", () => {
  // Found by seeded random play and counted by hand against the rules.
  const player1Wins = [
    3, 35, 39, 32, 36, 16, 37, 20, 21, 18, 29, 12, 15, 9, 17, 4, 24, 2, 31, 34, 28, 8, 10, 13, 5, 27, 30, 0, 19, 26, 25, 22, 14, 11, 38, 7, 6, 1,
    23, 33,
  ];
  const player2Wins = [
    19, 3, 10, 9, 16, 18, 4, 22, 26, 30, 24, 7, 35, 11, 32, 2, 15, 37, 14, 31, 12, 13, 25, 8, 6, 0, 39, 23, 38, 20, 21, 28, 36, 27, 29, 5, 33, 34,
    17, 1,
  ];
  const draw = [
    33, 9, 25, 34, 28, 38, 0, 37, 12, 39, 31, 10, 16, 26, 1, 24, 17, 11, 6, 29, 30, 3, 8, 18, 32, 19, 15, 36, 14, 35, 22, 21, 13, 4, 5, 2, 7, 27,
    20, 23,
  ];

  function score(state: DotsAndBoxesState): [number, number] {
    return [state.boxes.filter((owner) => owner === 1).length, state.boxes.filter((owner) => owner === 2).length];
  }

  test("player 1 wins 13 to 3", () => {
    const state = play(player1Wins);
    expect(score(state)).toEqual([13, 3]);
    expect(state.outcome?.winner).toBe(1);
    expect(state.outcome?.line).toEqual(state.boxes.flatMap((owner, box) => (owner === 1 ? [box] : [])));
    expect(state.outcome?.line).toHaveLength(13);
  });

  test("player 2 wins 13 to 3", () => {
    const state = play(player2Wins);
    expect(score(state)).toEqual([3, 13]);
    expect(state.outcome?.winner).toBe(2);
    expect(state.outcome?.line).toEqual(state.boxes.flatMap((owner, box) => (owner === 2 ? [box] : [])));
  });

  test("8 to 8 is a draw", () => {
    const state = play(draw);
    expect(score(state)).toEqual([8, 8]);
    expect(state.outcome).toEqual({ winner: null, line: [] });
  });

  test("every line is drawn exactly once and each game has no outcome until the last line", () => {
    for (const moves of [player1Wins, player2Wins, draw]) {
      expect(new Set(moves).size).toBe(40);
      expect(play(moves.slice(0, 39)).outcome).toBeNull();
      expect(play(moves).lines.every((owner) => owner !== 0)).toBe(true);
    }
  });
});

describe("apply", () => {
  test("never mutates the state it is given", () => {
    const state = play([0, 4, 20]);
    const snapshot = structuredClone(state);
    rules.apply(state, 21);
    rules.apply(state, 0);
    rules.apply(state, 99);
    expect(state).toEqual(snapshot);

    const last = nearlyDone([39], boxOwners(8, 7), 2);
    const lastSnapshot = structuredClone(last);
    rules.apply(last, 39);
    expect(last).toEqual(lastSnapshot);
  });

  test("the result does not share arrays with the input", () => {
    const state = play([0]);
    const after = rules.apply(state, 1);
    expect(after?.lines).not.toBe(state.lines);
    expect(after?.boxes).not.toBe(state.boxes);
  });
});
