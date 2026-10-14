#if DEBUG
  import SwiftUI

  /// Connect Four, Dots and Boxes and Ultimate Tic-Tac-Toe scenarios. Each one
  /// opens its game in `DeveloperBoardGamesScenarioView`. The hub with all the
  /// board game cards is `gamesHubBoardGames` in `DeveloperScenario+App.swift`.
  nonisolated extension DeveloperScenario {
    static let boardGames: [DeveloperScenario] = [
      connectFourYourTurn, connectFourPartnerTurn, connectFourPartnerMove, connectFourWon, connectFourFirstMove,
      connectFourMissedEnding, connectFourOffline,
      dotsAndBoxesPhoto, dotsAndBoxesExtraTurn, dotsAndBoxesWonPhoto, dotsAndBoxesPlain,
      ultimateTicTacToeForced, ultimateTicTacToeFree, ultimateTicTacToePartnerMove, ultimateTicTacToeWon,
      boardGameMarkEditor,
    ]

    static let connectFourYourTurn = boardGameScreen(
      "connect-four-your-turn", "Connect Four · your turn",
      "Ten discs in, Robin in the game, a stake above the board, and both marks are initials"
    )
    static let connectFourPartnerTurn = boardGameScreen(
      "connect-four-partner-turn", "Connect Four · Robin's turn",
      "Robin is away, so Tell Robin you want to play shows under the board"
    )
    static let connectFourPartnerMove = boardGameScreen(
      "connect-four-partner-move", "Connect Four · Robin's disc arrives",
      "Opens one disc behind: Robin's last disc hovers over its column, then drops"
    )
    static let connectFourWon = boardGameScreen(
      "connect-four-won", "Connect Four · you win",
      "Your last disc makes four on a diagonal: the line, the petals and the result with your stake"
    )
    static let connectFourFirstMove = boardGameScreen(
      "connect-four-first-move", "Connect Four · first move",
      "A new game you start, with Play for something above the board"
    )
    static let connectFourMissedEnding = boardGameScreen(
      "connect-four-missed-ending", "Connect Four · missed ending",
      "Robin won and started the next game before you looked: the ending plays first, then Continue"
    )
    static let connectFourOffline = boardGameScreen(
      "connect-four-offline", "Connect Four · move saved offline",
      "Your move is on the board and waits on this phone: Saved on this phone"
    )
    static let dotsAndBoxesPhoto = boardGameScreen(
      "dots-and-boxes-photo", "Dots and Boxes · hidden photo",
      "Six boxes closed by both of you, each uncovering a piece of the hidden photo"
    )
    static let dotsAndBoxesExtraTurn = boardGameScreen(
      "dots-and-boxes-extra-turn", "Dots and Boxes · box ready to close",
      "A box has three sides drawn. Close it for another turn"
    )
    static let dotsAndBoxesWonPhoto = boardGameScreen(
      "dots-and-boxes-won-photo", "Dots and Boxes · last box, photo reveal",
      "Opens one line before the end: the last box closes, then the whole photo shows"
    )
    static let dotsAndBoxesPlain = boardGameScreen(
      "dots-and-boxes-plain", "Dots and Boxes · no photo", "A couple with no photos: plain boxes with the initials"
    )
    static let ultimateTicTacToeForced = boardGameScreen(
      "ultimate-tic-tac-toe-forced", "Ultimate Tic-Tac-Toe · sent to one board",
      "Robin's last move sent you to the bottom left board, which zooms in"
    )
    static let ultimateTicTacToeFree = boardGameScreen(
      "ultimate-tic-tac-toe-free", "Ultimate Tic-Tac-Toe · free choice",
      "The board you were sent to is already won, so you may play in any open board"
    )
    static let ultimateTicTacToePartnerMove = boardGameScreen(
      "ultimate-tic-tac-toe-partner-move", "Ultimate Tic-Tac-Toe · Robin's move arrives",
      "Opens one move behind: Robin's move plays, then the board you are sent to zooms in"
    )
    static let ultimateTicTacToeWon = boardGameScreen(
      "ultimate-tic-tac-toe-won", "Ultimate Tic-Tac-Toe · you win",
      "Your last move wins three boards in a row: the strike line, the petals and the result"
    )
    static let boardGameMarkEditor = boardGameScreen(
      "board-game-mark-editor", "Board games · your mark",
      "The Your mark sheet over Connect Four. Saving takes about a second, then the mark shows on your discs"
    )

    private static func boardGameScreen(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperBoardGamesScenarioView(scenario: $0) }
    }
  }
#endif
