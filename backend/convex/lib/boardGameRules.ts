import type { BoardGameKind, BoardRules } from "./boardGames";
import { connectFourRules } from "./connectFour";
import { dotsAndBoxesRules } from "./dotsAndBoxes";
import { ludoRules } from "./ludo";
import { ultimateTicTacToeRules } from "./ultimateTicTacToe";

/**
 * The rules for each game kind. This lives apart from boardGames.ts because
 * every game file imports types from that file, and importing the games back
 * would make a cycle. The state type differs per game, so the map keeps each
 * game's own type and a caller that has only a `kind` reads it through `BoardRules<any>`.
 */
export const BOARD_RULES = {
  connect_four: connectFourRules,
  dots_and_boxes: dotsAndBoxesRules,
  ultimate_tic_tac_toe: ultimateTicTacToeRules,
  ludo: ludoRules,
} as const satisfies Record<BoardGameKind, BoardRules<any>>;
