#if DEBUG
  import SwiftUI

  /// Consensio scenarios. Each one opens in `DeveloperConsensioScenarioView`.
  nonisolated extension DeveloperScenario {
    static let consensio: [DeveloperScenario] = [
      consensioFirstTurn, consensioOwnTopic, consensioPlace, consensioWaitChoosing, consensioWaitLive,
      consensioWaitLater, consensioGuess, consensioRevealSpotOn, consensioRevealClose, consensioRevealFar,
      consensioRevealPlacer, consensioRevealHeld, consensioHistory,
    ]

    static let consensioFirstTurn = consensioScreen(
      "consensio-first-turn", "Consensio · first turn",
      "A new game: pick one of three topics. Robin is away, so the invite bell shows"
    )
    static let consensioOwnTopic = consensioScreen(
      "consensio-own-topic", "Consensio · write your own", "The topic list with Write your own open"
    )
    static let consensioPlace = consensioScreen(
      "consensio-place", "Consensio · place", "Camping is chosen and the line waits for your marker"
    )
    static let consensioWaitChoosing = consensioScreen(
      "consensio-wait-choosing", "Consensio · Robin picks a topic", "Robin is here and picking a topic"
    )
    static let consensioWaitLive = consensioScreen(
      "consensio-wait-live", "Consensio · watching Robin guess",
      "Your marker is placed and Robin guesses live: his pin moves along the line"
    )
    static let consensioWaitLater = consensioScreen(
      "consensio-wait-later", "Consensio · waiting, Robin away", "Your marker waits for a guess and Robin is away"
    )
    static let consensioGuess = consensioScreen(
      "consensio-guess", "Consensio · guess", "Robin placed a marker on Spicy food. Guess where"
    )
    static let consensioRevealSpotOn = consensioScreen(
      "consensio-reveal-spot-on", "Consensio · reveal, spot on", "You guessed 2% off: Spot on, 5 points"
    )
    static let consensioRevealClose = consensioScreen(
      "consensio-reveal-close", "Consensio · reveal, close", "You guessed 14% off: Close, 2 points"
    )
    static let consensioRevealFar = consensioScreen(
      "consensio-reveal-far", "Consensio · reveal, far", "You guessed 41% off: Now you know more"
    )
    static let consensioRevealPlacer = consensioScreen(
      "consensio-reveal-placer", "Consensio · reveal, Robin guessed",
      "Robin guessed your marker 6% off. You see his pin drop next to yours"
    )
    static let consensioRevealHeld = consensioScreen(
      "consensio-reveal-held", "Consensio · reveal held",
      "Your guess is only saved on the phone and a send failed. The reveal waits for the real spot"
    )
    static let consensioHistory = consensioScreen(
      "consensio-history", "Consensio · what we know", "Records and twelve guessed rounds"
    )

    private static func consensioScreen(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperConsensioScenarioView(scenario: $0) }
    }
  }
#endif
