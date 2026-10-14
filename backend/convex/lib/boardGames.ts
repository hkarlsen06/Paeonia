/** Player 1 started the game and always moves first. */
export type BoardPlayer = 1 | 2;

/** A finished game. winner is null for a draw. line lists the board indexes to highlight, ascending (empty when there is nothing to highlight). */
export type BoardOutcome = { winner: BoardPlayer | null; line: number[] };

/**
 * The pure rules of one board game. Rules use no database, clock or randomness,
 * so the server and the phone replay the same move list to the same state.
 */
export interface BoardRules<S> {
  /** Moves are integers in 0..<moveLimit. */
  readonly moveLimit: number;
  initial(): S;
  /** Who moves next. Meaningless once outcome is set. */
  next(state: S): BoardPlayer;
  outcome(state: S): BoardOutcome | null;
  /** The state after the next player makes `move`, or null when the move is illegal (out of range, not an integer, occupied, wrong board, or the game is over). Never mutates `state`. */
  apply(state: S, move: number): S | null;
}

export const BOARD_GAME_KINDS = ["connect_four", "dots_and_boxes", "ultimate_tic_tac_toe"] as const;
export type BoardGameKind = (typeof BOARD_GAME_KINDS)[number];

export function otherPlayer(player: BoardPlayer): BoardPlayer {
  return player === 1 ? 2 : 1;
}

/** True for an integer in 0..<limit. Rejects -0, which JSON can carry but a move list should not. */
export function isMoveInRange(move: number, limit: number): boolean {
  return Number.isInteger(move) && move >= 0 && move < limit && !Object.is(move, -0);
}

/** Replays a whole game from the empty board. Returns null if any move is illegal. */
export function replay<S>(rules: BoardRules<S>, moves: readonly number[]): S | null {
  let state = rules.initial();
  for (const move of moves) {
    const after = rules.apply(state, move);
    if (after === null) return null;
    state = after;
  }
  return state;
}

/** Who made each move, in order (needed for Dots and Boxes, where a player can move twice in a row). Returns null if any move is illegal. */
export function movers<S>(rules: BoardRules<S>, moves: readonly number[]): BoardPlayer[] | null {
  let state = rules.initial();
  const players: BoardPlayer[] = [];
  for (const move of moves) {
    const after = rules.apply(state, move);
    if (after === null) return null;
    players.push(rules.next(state));
    state = after;
  }
  return players;
}
