import { isMoveInRange, otherPlayer, type BoardOutcome, type BoardPlayer, type BoardRules } from "./boardGames";

const BOARD_COUNT = 9;
const CELLS_PER_BOARD = 9;
const CELL_COUNT = BOARD_COUNT * CELLS_PER_BOARD;
/** The `boards` value of a full small board that nobody won. */
const BOARD_FULL = 3;
/** The `forced` value that lets the next move use any open board. */
const ANY_BOARD = -1;

/** Rows, columns and diagonals of a 3 x 3 grid, as row-major indexes. */
const THREE_IN_A_ROW: readonly (readonly [number, number, number])[] = [
  [0, 1, 2],
  [3, 4, 5],
  [6, 7, 8],
  [0, 3, 6],
  [1, 4, 7],
  [2, 5, 8],
  [0, 4, 8],
  [2, 4, 6],
];

/**
 * 9 small boards in a 3 x 3 big grid. A move is a cell index, board * 9 + cell,
 * with board 0..8 row-major in the big grid and cell 0..8 row-major in the small board.
 */
export interface UltimateTicTacToeState {
  /** 0 is empty, 1 or 2 is the player whose mark sits there. */
  readonly cells: readonly number[];
  /** 0 is open, 1 or 2 is won by that player, 3 is full with no winner. */
  readonly boards: readonly number[];
  /** The board the next move must be in, or -1 for any open board. */
  readonly forced: number;
  readonly next: BoardPlayer;
  readonly outcome: BoardOutcome | null;
}

/** The rows, columns and diagonals of the 3 x 3 grid at `offset` in `values` that `player` fills completely. */
function filledLines(values: readonly number[], offset: number, player: number): (readonly [number, number, number])[] {
  return THREE_IN_A_ROW.filter((line) => line.every((index) => values[offset + index] === player));
}

/** The boards the next move may use. Empty once the game is over. */
export function ultimateTicTacToeOpenBoards(state: UltimateTicTacToeState): number[] {
  if (state.outcome !== null) return [];
  if (state.forced !== ANY_BOARD) return [state.forced];
  const open: number[] = [];
  state.boards.forEach((board, index) => {
    if (board === 0) open.push(index);
  });
  return open;
}

export const ultimateTicTacToeRules: BoardRules<UltimateTicTacToeState> = {
  moveLimit: CELL_COUNT,

  initial() {
    return {
      cells: new Array<number>(CELL_COUNT).fill(0),
      boards: new Array<number>(BOARD_COUNT).fill(0),
      forced: ANY_BOARD,
      next: 1,
      outcome: null,
    };
  },

  next(state) {
    return state.next;
  },

  outcome(state) {
    return state.outcome;
  },

  apply(state, move) {
    if (state.outcome !== null) return null;
    if (!isMoveInRange(move, CELL_COUNT) || state.cells[move] !== 0) return null;
    const board = Math.floor(move / CELLS_PER_BOARD);
    const cell = move % CELLS_PER_BOARD;
    if (state.boards[board] !== 0) return null;
    if (state.forced !== ANY_BOARD && state.forced !== board) return null;

    const player = state.next;
    const cells = state.cells.slice();
    cells[move] = player;
    const boards = state.boards.slice();
    if (filledLines(cells, board * CELLS_PER_BOARD, player).length > 0) boards[board] = player;
    else if (cells.slice(board * CELLS_PER_BOARD, (board + 1) * CELLS_PER_BOARD).every((mark) => mark !== 0)) boards[board] = BOARD_FULL;
    const forced = boards[cell] === 0 ? cell : ANY_BOARD;

    // Only the mover can have completed a line of boards, and two lines can finish at once.
    const wonLines = filledLines(boards, 0, player);
    let outcome: BoardOutcome | null = null;
    if (wonLines.length > 0) {
      outcome = { winner: player, line: [...new Set(wonLines.flat())].sort((a, b) => a - b) };
    } else if (boards.every((owner) => owner !== 0)) {
      outcome = { winner: null, line: [] };
    }
    return { cells, boards, forced, next: otherPlayer(player), outcome };
  },
};
