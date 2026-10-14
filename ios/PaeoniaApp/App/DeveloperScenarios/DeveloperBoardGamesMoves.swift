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

    // MARK: Ludo

    // A move is `(die - 1) * 3 + choice`: choice 0 is the mover's first pawn, 1 the
    // second and 2 a pass. Progress is 0 in the base, 1 to 51 on the track, 52 to 56
    // in the home column and 57 at home. Player one starts on square 0, player two
    // on square 26. A 6, a pawn sent home and a pawn brought home give another roll.
    // A player with no pawn out gets three tries to roll a 6, so their missed 6s come
    // in threes, here as passes with a 3 and a 5 (8 and 14).

    /// The integers are 15 (a 6 for the first pawn), 16 (a 6 for the second pawn), 9 (a
    /// 4 for the first pawn), then player two's three missed 6s. Player one has both
    /// pawns out, the first on progress 5 and the second on 1, and is to move. A 3
    /// gives a real choice: the first pawn to progress 8 or the second to progress 4.
    static let ludoChoice = [15, 16, 9, 8, 8, 14]
    /// The die player one has rolled and kept in that position.
    static let ludoChoiceDie = 3

    /// One whole game of 62 moves that player one wins. Moves 1 to 12 are missed 6s,
    /// three for each player in turn.
    /// - Move 19: player two brings a pawn out with a 6.
    /// - Move 39: player one's 6 takes the first pawn from progress 44 to 50, square
    ///   49, where player two's pawn stood on progress 24. It is sent home, and
    ///   player one rolls again.
    /// - Move 56: a 6 with pawns on 54 and 52 can't move either one, so it passes and
    ///   player one rolls again.
    /// - Move 61: a 3 takes the first pawn from 54 to home. Move 62 is a 1 that takes
    ///   the second pawn from 56 to home and wins.
    static let ludoGame = [
      2, 8, 14, 8, 8, 14, 11, 8, 14, 11, 8, 14, 15, 6, 11, 8, 14, 9, 16, 4, 16, 0, 10, 9,
      10, 15, 16, 9, 13, 13, 7, 15, 15, 16, 12, 10, 9, 1, 15, 9, 5, 8, 14, 16, 16, 13, 14, 8,
      14, 16, 13, 11, 8, 14, 16, 17, 10, 11, 8, 14, 6, 1,
    ]

    /// Player two is to move, after player one's 5 on the first pawn (move 35).
    static let ludoPartnerTurn = Array(ludoGame.prefix(35))

    /// 24 moves. After move 22 player one's pawns are on progress 11 and 3 and
    /// player two's first pawn is on 25. Move 23 is player two's 4, from 25 to 29,
    /// square 2, where player one's second pawn stood. It is sent home and player two
    /// rolls again. Move 24 is another 4 that ends player two's turn, so player one
    /// is to move.
    static let ludoCapture = [2, 8, 14, 15, 12, 14, 8, 14, 12, 14, 8, 14, 12, 15, 9, 12, 6, 0, 16, 6, 6, 4, 9, 9]
  }
#endif
