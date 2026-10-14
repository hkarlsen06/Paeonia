import { isMoveInRange, otherPlayer, type BoardOutcome, type BoardPlayer, type BoardRules } from "./boardGames";

export const LUDO_PAWNS_PER_PLAYER = 2;
export const LUDO_TRACK_LENGTH = 52;
/** Progress of a pawn that reached the home in the middle of the board. */
export const LUDO_HOME_PROGRESS = 57;
/** The last progress on the shared track. Progress 52 to 56 is the pawn's own home column. */
const LAST_TRACK_PROGRESS = 51;
const DICE_FACES = 6;
/** Choices per die value: the first pawn, the second pawn and a pass. */
const CHOICES = LUDO_PAWNS_PER_PLAYER + 1;
export const LUDO_PASS = LUDO_PAWNS_PER_PLAYER;
/** The four start squares and the square 8 past each. A pawn on one of them can't be sent home. */
export const LUDO_SAFE_SQUARES: ReadonlySet<number> = new Set([0, 8, 13, 21, 26, 34, 39, 47]);

/**
 * Two pawns each on the classic cross board. Pawn indexes are 0 and 1 for player 1, 2 and 3 for player 2.
 *
 * Each pawn has a progress. 0 is the base, 1 to 51 is the track at square
 * (start + progress - 1) % 52 with start 0 for player 1 and 26 for player 2, 52 to 56 is the
 * pawn's own home column and 57 is home.
 *
 * A move is (die - 1) * 3 + choice, where choice is 0 for the mover's first pawn, 1 for the second
 * and 2 for a pass. The die roll is part of the move, so the rules use no randomness.
 */
export interface LudoState {
  readonly progress: readonly number[];
  readonly next: BoardPlayer;
  readonly outcome: BoardOutcome | null;
}

export function ludoMove(die: number, choice: number): number {
  return (die - 1) * CHOICES + choice;
}

/** The die and choice inside a move, or null when `move` is not a move integer. */
export function ludoDecode(move: number): { die: number; choice: number } | null {
  if (!isMoveInRange(move, DICE_FACES * CHOICES)) return null;
  return { die: Math.floor(move / CHOICES) + 1, choice: move % CHOICES };
}

export function ludoPawnIndex(player: BoardPlayer, pawn: number): number {
  return (player - 1) * LUDO_PAWNS_PER_PLAYER + pawn;
}

export function ludoStartSquare(player: BoardPlayer): number {
  return player === 1 ? 0 : LUDO_TRACK_LENGTH / 2;
}

/** The track square for a progress of 1 to 51, or null when the pawn is not on the shared track. */
export function ludoTrackSquare(player: BoardPlayer, progress: number): number | null {
  if (progress < 1 || progress > LAST_TRACK_PROGRESS) return null;
  return (ludoStartSquare(player) + progress - 1) % LUDO_TRACK_LENGTH;
}

/** Whether a pawn at `progress` can move by `die`. A pawn in the base needs a 6 and a pawn needs the exact number to reach home. */
export function ludoCanMove(progress: number, die: number): boolean {
  if (progress === 0) return die === DICE_FACES;
  return progress + die <= LUDO_HOME_PROGRESS;
}

/** The choices `state.next` has with `die`: each pawn that can move, or only the pass. Empty once the game is over. */
export function ludoLegalChoices(state: LudoState, die: number): number[] {
  if (state.outcome !== null) return [];
  const choices: number[] = [];
  for (let pawn = 0; pawn < LUDO_PAWNS_PER_PLAYER; pawn++) {
    if (ludoCanMove(state.progress[ludoPawnIndex(state.next, pawn)], die)) choices.push(pawn);
  }
  return choices.length > 0 ? choices : [LUDO_PASS];
}

export const ludoRules: BoardRules<LudoState> = {
  moveLimit: DICE_FACES * CHOICES,

  initial() {
    return { progress: new Array<number>(LUDO_PAWNS_PER_PLAYER * 2).fill(0), next: 1, outcome: null };
  },

  next(state) {
    return state.next;
  },

  outcome(state) {
    return state.outcome;
  },

  apply(state, move) {
    if (state.outcome !== null) return null;
    const decoded = ludoDecode(move);
    if (decoded === null) return null;
    const { die, choice } = decoded;
    const mover = state.next;
    const legal = ludoLegalChoices(state, die);
    if (!legal.includes(choice)) return null;

    const progress = state.progress.slice();
    let again = die === DICE_FACES;
    if (choice !== LUDO_PASS) {
      const index = ludoPawnIndex(mover, choice);
      const arrived = progress[index] === 0 ? 1 : progress[index] + die;
      progress[index] = arrived;
      const square = ludoTrackSquare(mover, arrived);
      if (square !== null && !LUDO_SAFE_SQUARES.has(square)) {
        const partner = otherPlayer(mover);
        for (let pawn = 0; pawn < LUDO_PAWNS_PER_PLAYER; pawn++) {
          const partnerIndex = ludoPawnIndex(partner, pawn);
          if (ludoTrackSquare(partner, progress[partnerIndex]) === square) {
            progress[partnerIndex] = 0;
            again = true;
          }
        }
      }
      if (arrived === LUDO_HOME_PROGRESS) again = true;
    }

    const won = [0, 1].every((pawn) => progress[ludoPawnIndex(mover, pawn)] === LUDO_HOME_PROGRESS);
    if (won) return { progress, next: mover, outcome: { winner: mover, line: [] } };
    return { progress, next: again ? mover : otherPlayer(mover), outcome: null };
  },
};
