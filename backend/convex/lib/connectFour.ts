import { isMoveInRange, otherPlayer, type BoardOutcome, type BoardPlayer, type BoardRules } from "./boardGames";

export const CONNECT_FOUR_COLUMNS = 7;
export const CONNECT_FOUR_ROWS = 6;
const CELL_COUNT = CONNECT_FOUR_COLUMNS * CONNECT_FOUR_ROWS;
const RUN_LENGTH = 4;

/** Each direction as [column step, row step]. The opposite direction is walked from the same disc. */
const DIRECTIONS: readonly (readonly [number, number])[] = [
  [1, 0],
  [0, 1],
  [1, 1],
  [1, -1],
];

/**
 * Cell index is row * 7 + column. Row 0 is the top row and row 5 the bottom row.
 * A move is a column 0..6.
 */
export interface ConnectFourState {
  /** 0 is empty, 1 or 2 is the player whose disc sits there. */
  readonly cells: readonly number[];
  readonly next: BoardPlayer;
  readonly outcome: BoardOutcome | null;
  /** Discs placed so far. */
  readonly moves: number;
}

/**
 * The row where a disc dropped in `column` lands, or null when the column is
 * out of range, not an integer, or full. It does not look at whether the game is over.
 */
export function connectFourLandingRow(state: ConnectFourState, column: number): number | null {
  if (!isMoveInRange(column, CONNECT_FOUR_COLUMNS)) return null;
  for (let row = CONNECT_FOUR_ROWS - 1; row >= 0; row--) {
    if (state.cells[row * CONNECT_FOUR_COLUMNS + column] === 0) return row;
  }
  return null;
}

/** Every cell of every run of four or more through the disc at (row, column), ascending. */
function winningCells(cells: readonly number[], row: number, column: number): number[] {
  const player = cells[row * CONNECT_FOUR_COLUMNS + column];
  const line = new Set<number>();
  for (const [columnStep, rowStep] of DIRECTIONS) {
    const run = [row * CONNECT_FOUR_COLUMNS + column];
    for (const sign of [1, -1]) {
      let r = row + sign * rowStep;
      let c = column + sign * columnStep;
      while (r >= 0 && r < CONNECT_FOUR_ROWS && c >= 0 && c < CONNECT_FOUR_COLUMNS && cells[r * CONNECT_FOUR_COLUMNS + c] === player) {
        run.push(r * CONNECT_FOUR_COLUMNS + c);
        r += sign * rowStep;
        c += sign * columnStep;
      }
    }
    if (run.length >= RUN_LENGTH) for (const index of run) line.add(index);
  }
  return [...line].sort((a, b) => a - b);
}

export const connectFourRules: BoardRules<ConnectFourState> = {
  moveLimit: CONNECT_FOUR_COLUMNS,

  initial() {
    return { cells: new Array<number>(CELL_COUNT).fill(0), next: 1, outcome: null, moves: 0 };
  },

  next(state) {
    return state.next;
  },

  outcome(state) {
    return state.outcome;
  },

  apply(state, move) {
    if (state.outcome !== null) return null;
    const row = connectFourLandingRow(state, move);
    if (row === null) return null;

    const cells = state.cells.slice();
    cells[row * CONNECT_FOUR_COLUMNS + move] = state.next;
    const moves = state.moves + 1;
    const line = winningCells(cells, row, move);
    let outcome: BoardOutcome | null = null;
    if (line.length > 0) outcome = { winner: state.next, line };
    else if (moves === CELL_COUNT) outcome = { winner: null, line: [] };
    return { cells, next: otherPlayer(state.next), outcome, moves };
  },
};
