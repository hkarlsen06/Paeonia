import { isMoveInRange, otherPlayer, type BoardOutcome, type BoardPlayer, type BoardRules } from "./boardGames";

/** Dots per side. The board has 4 x 4 boxes. */
const DOTS = 5;
const BOXES_PER_SIDE = DOTS - 1;
const HORIZONTAL_LINES = DOTS * BOXES_PER_SIDE;
const LINE_COUNT = 2 * HORIZONTAL_LINES;
const BOX_COUNT = BOXES_PER_SIDE * BOXES_PER_SIDE;

/**
 * 5 x 5 dots, 4 x 4 boxes, 40 lines. A move is a line index.
 *
 * Horizontal line h(r, c) = r * 4 + c for dot rows r 0..4 and c 0..3 (indexes 0..19).
 * Vertical line v(r, c) = 20 + r * 5 + c for r 0..3 and c 0..4 (indexes 20..39).
 * Box b = r * 4 + c (r, c 0..3) has top h(r, c), bottom h(r + 1, c), left v(r, c) and right v(r, c + 1).
 */
export interface DotsAndBoxesState {
  /** 0 is undrawn, 1 or 2 is the player who drew the line. */
  readonly lines: readonly number[];
  /** 0 is open, 1 or 2 is the player who closed the box. */
  readonly boxes: readonly number[];
  readonly next: BoardPlayer;
  readonly outcome: BoardOutcome | null;
}

/** The four lines of a box as [top, bottom, left, right]. */
export function linesOfBox(box: number): [number, number, number, number] {
  const row = Math.floor(box / BOXES_PER_SIDE);
  const column = box % BOXES_PER_SIDE;
  const vertical = HORIZONTAL_LINES + row * DOTS + column;
  return [row * BOXES_PER_SIDE + column, (row + 1) * BOXES_PER_SIDE + column, vertical, vertical + 1];
}

/** The one or two boxes a line borders, ascending. Empty when `line` is not a line index. */
export function boxesOfLine(line: number): number[] {
  if (!isMoveInRange(line, LINE_COUNT)) return [];
  if (line < HORIZONTAL_LINES) {
    const row = Math.floor(line / BOXES_PER_SIDE);
    const column = line % BOXES_PER_SIDE;
    const boxes: number[] = [];
    if (row > 0) boxes.push((row - 1) * BOXES_PER_SIDE + column);
    if (row < BOXES_PER_SIDE) boxes.push(row * BOXES_PER_SIDE + column);
    return boxes;
  }
  const index = line - HORIZONTAL_LINES;
  const row = Math.floor(index / DOTS);
  const column = index % DOTS;
  const boxes: number[] = [];
  if (column > 0) boxes.push(row * BOXES_PER_SIDE + column - 1);
  if (column < BOXES_PER_SIDE) boxes.push(row * BOXES_PER_SIDE + column);
  return boxes;
}

export const dotsAndBoxesRules: BoardRules<DotsAndBoxesState> = {
  moveLimit: LINE_COUNT,

  initial() {
    return { lines: new Array<number>(LINE_COUNT).fill(0), boxes: new Array<number>(BOX_COUNT).fill(0), next: 1, outcome: null };
  },

  next(state) {
    return state.next;
  },

  outcome(state) {
    return state.outcome;
  },

  apply(state, move) {
    if (state.outcome !== null) return null;
    if (!isMoveInRange(move, LINE_COUNT) || state.lines[move] !== 0) return null;

    const lines = state.lines.slice();
    lines[move] = state.next;
    const boxes = state.boxes.slice();
    let closed = 0;
    for (const box of boxesOfLine(move)) {
      if (linesOfBox(box).every((line) => lines[line] !== 0)) {
        boxes[box] = state.next;
        closed += 1;
      }
    }
    const next = closed > 0 ? state.next : otherPlayer(state.next);

    let outcome: BoardOutcome | null = null;
    if (lines.every((line) => line !== 0)) {
      const first = boxes.filter((owner) => owner === 1).length;
      const second = boxes.filter((owner) => owner === 2).length;
      const winner: BoardPlayer | null = first > second ? 1 : second > first ? 2 : null;
      const line: number[] = [];
      boxes.forEach((owner, box) => {
        if (winner !== null && owner === winner) line.push(box);
      });
      outcome = { winner, line };
    }
    return { lines, boxes, next, outcome };
  },
};
