#if DEBUG
  import Foundation

  /// The games behind the board game scenarios, as move lists. Player one moves
  /// first. Every list is legal under the real rules, and
  /// `BoardGameScenarioFixturesTests` replays all of them.
  nonisolated enum DeveloperBoardGamesMoves {
    // MARK: Connect Four

    /// Columns, 0 to 6 from the left. Ten discs, nobody has four, player one moves.
    static let connectFourMidGame = [3, 3, 2, 4, 4, 2, 3, 4, 5, 3]

    /// Player one wins on the diagonal that runs from the bottom of column 0 up
    /// to column 3, on the eleventh disc. Cells 35, 29, 23 and 17.
    static let connectFourWin = [0, 1, 1, 2, 3, 2, 2, 3, 4, 3, 3]

    /// Player two wins with four discs stacked in column 3, on the eighth disc.
    static let connectFourLostGame = [0, 3, 0, 3, 1, 3, 1, 3]

    // MARK: Dots and Boxes

    /// One whole game of 40 lines. Player one closes the last seven boxes in a
    /// row and wins 10 to 6. After 22 lines each player holds three boxes.
    static let dotsAndBoxesGame = [
      0, 20, 4, 21, 1, 8, 5, 22, 9, 25, 26, 14, 27, 10, 15, 32, 33, 19, 2, 38, 39, 3,
      30, 17, 16, 24, 35, 29, 31, 12, 13, 36, 28, 6, 23, 37, 7, 18, 11, 34,
    ]

    /// Player one moves and no box can be closed.
    static let dotsAndBoxesMidGame = Array(dotsAndBoxesGame.prefix(22))

    /// Player two moves and no box can be closed.
    static let dotsAndBoxesPartnerTurn = Array(dotsAndBoxesGame.prefix(18))

    /// Player two just drew a third side of the box in the third row, last column.
    /// Player one closes it with line 34 and moves again.
    static let dotsAndBoxesExtraTurn = Array(dotsAndBoxesGame.prefix(21)) + [11]
    static let dotsAndBoxesExtraTurnLine = 34

    // MARK: Ultimate Tic-Tac-Toe

    /// One game of 39 moves, `board * 9 + cell`. Player one wins the top right,
    /// center and bottom left boards, the anti-diagonal, with the last move.
    static let ultimateTicTacToeGame = [
      5, 47, 23, 45, 4, 43, 71, 73, 12, 29, 18, 3, 27, 7, 63, 6, 58, 39, 31, 42, 60, 56,
      21, 35, 79, 67, 44, 76, 36, 0, 24, 59, 46, 15, 62, 74, 40, 72, 54,
    ]

    /// Player two's last move sent player one to the bottom left board (6).
    /// Each player has won one small board.
    static let ultimateTicTacToeForced = Array(ultimateTicTacToeGame.prefix(34))
    static let ultimateTicTacToeForcedBoard = 6

    /// Player two's last move pointed at the top right board, which player one
    /// already won, so player one may play in any open board.
    static let ultimateTicTacToeFree = Array(ultimateTicTacToeGame.prefix(36))
  }
#endif
