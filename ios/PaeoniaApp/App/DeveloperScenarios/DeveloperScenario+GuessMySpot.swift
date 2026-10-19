#if DEBUG
  import SwiftUI

  /// Guess my spot scenarios. Each one opens in `DeveloperGuessMySpotScenarioView`.
  nonisolated extension DeveloperScenario {
    static let guessMySpot: [DeveloperScenario] = [
      guessMySpotFirstTurn, guessMySpotCheckFound, guessMySpotCheckMissing, guessMySpotWaitChoosing,
      guessMySpotWaitLive, guessMySpotWaitLater, guessMySpotGuess, guessMySpotRevealSpotOn, guessMySpotRevealClose,
      guessMySpotRevealFar, guessMySpotRevealSender, guessMySpotRevealHeld, guessMySpotHistory,
      memoriesMapWithGame,
    ]

    static let guessMySpotFirstTurn = guessMySpotScreen(
      "guess-my-spot-first-turn", "Guess my spot · first turn",
      "A new game: the camera roll opens to pick a photo. Robin is away, so the invite bell shows"
    )
    static let guessMySpotCheckFound = guessMySpotScreen(
      "guess-my-spot-check-found", "Guess my spot · check, spot found",
      "A harbor photo whose spot came from the photo: Bergen"
    )
    static let guessMySpotCheckMissing = guessMySpotScreen(
      "guess-my-spot-check-missing", "Guess my spot · check, no spot",
      "A photo without a location: tap the map to drop the pin"
    )
    static let guessMySpotWaitChoosing = guessMySpotScreen(
      "guess-my-spot-wait-choosing", "Guess my spot · Robin picks a photo", "Robin is here and picking a photo"
    )
    static let guessMySpotWaitLive = guessMySpotScreen(
      "guess-my-spot-wait-live", "Guess my spot · watching Robin guess",
      "Your photo is sent and Robin guesses live: the pin lands closer and closer"
    )
    static let guessMySpotWaitLater = guessMySpotScreen(
      "guess-my-spot-wait-later", "Guess my spot · waiting, Robin away",
      "Your photo waits for a guess and Robin is away"
    )
    static let guessMySpotGuess = guessMySpotScreen(
      "guess-my-spot-guess", "Guess my spot · guess", "Robin sent a photo of a mountain lake. Guess where"
    )
    static let guessMySpotRevealSpotOn = guessMySpotScreen(
      "guess-my-spot-reveal-spot-on", "Guess my spot · reveal, spot on", "You guessed about 460 m off: Spot on"
    )
    static let guessMySpotRevealClose = guessMySpotScreen(
      "guess-my-spot-reveal-close", "Guess my spot · reveal, close", "You guessed about 110 km off: Close"
    )
    static let guessMySpotRevealFar = guessMySpotScreen(
      "guess-my-spot-reveal-far", "Guess my spot · reveal, far", "You guessed Rome for Bergen: Now you know where"
    )
    static let guessMySpotRevealSender = guessMySpotScreen(
      "guess-my-spot-reveal-sender", "Guess my spot · reveal, Robin guessed",
      "Robin guessed your photo about 9 km off. You see the guess fly to your spot"
    )
    static let guessMySpotRevealHeld = guessMySpotScreen(
      "guess-my-spot-reveal-held", "Guess my spot · reveal held",
      "Your guess is only saved on the phone and a send failed. The reveal waits for the real spot"
    )
    static let guessMySpotHistory = guessMySpotScreen(
      "guess-my-spot-history", "Guess my spot · our places", "Records and twelve places on the map"
    )

    /// The Memories tab's "Our places" with the twelve Guess my spot rounds among the memories.
    static let memoriesMapWithGame = DeveloperScenario(
      "memories-map-with-game", "Memories · map with Guess my spot",
      "Our places: the memories and twelve Guess my spot rounds, labelled as from the game", .memories
    ) { _ in DeveloperMemoriesMapWithGameScenarioView() }

    private static func guessMySpotScreen(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperGuessMySpotScenarioView(scenario: $0) }
    }
  }
#endif
