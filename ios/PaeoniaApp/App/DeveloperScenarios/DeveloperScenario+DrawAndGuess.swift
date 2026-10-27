#if DEBUG
  import SwiftUI

  /// Draw & Guess scenarios. A round opens in `DeveloperGamesScenarioView` and
  /// Our drawings in `DeveloperGamesHistoryScenarioView`.
  nonisolated extension DeveloperScenario {
    static let drawAndGuess: [DeveloperScenario] = [
      drawChooseWord, drawWaitingForWord, drawDrawing, drawSavedOffline, drawWaitingForGuess, drawWatchingHints,
      drawWaitingForDrawing, drawWatchingLive, drawGuessingReplay, drawGuessingLongWord, drawRevealSolved,
      drawRevealBonuses, drawRevealMissed, drawRevealAsDrawer, drawRevealPartnerDrawing, drawRevealLoading,
      drawHistory, drawHistoryEmpty,
    ]

    static let drawChooseWord = drawRound(
      "draw-choose-word", "Draw & Guess · choose a word", "Three words and the draw-your-own field"
    )
    static let drawWaitingForWord = drawRound(
      "draw-waiting-for-word", "Draw & Guess · partner picks a word", "Robin is choosing what to draw"
    )
    static let drawDrawing = drawRound(
      "draw-drawing", "Draw & Guess · drawing", "The canvas with Robin watching live"
    )
    static let drawSavedOffline = drawRound(
      "draw-saved-offline", "Draw & Guess · drawing sent offline",
      "A drawing queued on the phone: saved on this phone, sent later"
    )
    static let drawWaitingForGuess = drawRound(
      "draw-waiting-for-guess", "Draw & Guess · partner is guessing", "The sent drawing and Robin's wrong guesses"
    )
    static let drawWatchingHints = drawRound(
      "draw-watching-hints", "Draw & Guess · partner used hints",
      "Robin's revealed letters keep their pink outlines on your screen"
    )
    static let drawWaitingForDrawing = drawRound(
      "draw-waiting-for-drawing", "Draw & Guess · waiting for a drawing",
      "Tiles shown while the drawing has not arrived"
    )
    static let drawWatchingLive = drawRound(
      "draw-watching-live", "Draw & Guess · watching live", "Robin's umbrella appears live, with tiles to guess"
    )
    static let drawGuessingReplay = drawRound(
      "draw-guessing-replay", "Draw & Guess · guessing a replay", "The saved umbrella plays back at the drawn pace"
    )
    static let drawGuessingLongWord = drawRound(
      "draw-guessing-long-word", "Draw & Guess · guessing a 20-letter word",
      "The longest custom word: slots split over two lines"
    )
    static let drawRevealSolved = drawRound(
      "draw-reveal-solved", "Draw & Guess · reveal, solved", "You solved it: time, speed bonus, points"
    )
    static let drawRevealBonuses = drawRound(
      "draw-reveal-bonuses", "Draw & Guess · reveal with bonuses and reactions",
      "Speed bonus +2, first try, your fastest solve yet, and the reaction row"
    )
    static let drawRevealMissed = drawRound(
      "draw-reveal-missed", "Draw & Guess · reveal, missed", "You pressed Show me: the word and the drawing"
    )
    static let drawRevealAsDrawer = drawRound(
      "draw-reveal-as-drawer", "Draw & Guess · reveal as the drawer", "Robin solved your drawing: the guesses in order"
    )
    static let drawRevealPartnerDrawing = drawRound(
      "draw-reveal-partner-drawing", "Draw & Guess · partner drew the next one",
      "The result, and Robin already draws the next one: the button reads Watch Robin draw"
    )
    static let drawRevealLoading = drawRound(
      "draw-reveal-loading", "Draw & Guess · reveal, drawing still loading",
      "You solved it while Robin's drawing is still downloading"
    )
    static let drawHistory = drawHistoryScreen(
      "draw-history", "Draw & Guess · our drawings",
      "Records and a grid of finished drawings, some starred, one missed. Open one to replay it"
    )
    static let drawHistoryEmpty = drawHistoryScreen(
      "draw-history-empty", "Draw & Guess · our drawings, none yet", "Our drawings before the first round has finished"
    )

    private static func drawRound(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperGamesScenarioView(scenario: $0) }
    }

    private static func drawHistoryScreen(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperGamesHistoryScenarioView(scenario: $0) }
    }
  }
#endif
