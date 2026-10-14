#if DEBUG
  import SwiftUI

  /// Exquisite corpse scenarios. The hub ones run the real tabs, and the others
  /// open one screen in `ExquisiteCorpseDeveloperScenarioView`.
  nonisolated extension DeveloperScenario {
    static let exquisiteCorpse: [DeveloperScenario] = [
      exquisiteCorpseHubYourTurn, exquisiteCorpseHubPartnerDrawing, exquisiteCorpseHubReveal,
      exquisiteCorpseHubNotStarted, exquisiteCorpseDrawHead, exquisiteCorpseDrawBody, exquisiteCorpseDrawLegs,
      exquisiteCorpseWaiting, exquisiteCorpseWatching, exquisiteCorpseHandoff, exquisiteCorpseWaitingToSync,
      exquisiteCorpseReveal, exquisiteCorpseRevealLoading, exquisiteCorpseHistory, exquisiteCorpseHistoryEmpty,
      exquisiteCorpseHistoryStarred, exquisiteCorpseHistoryDetail,
    ]

    static let exquisiteCorpseHubYourTurn = exquisiteCorpseHub(
      "corpse-hub-your-turn", "Exquisite corpse · hub, your turn",
      "Hub card when you draw the body of creature 2, with 12 creatures made and the Our creatures link"
    )
    static let exquisiteCorpseHubPartnerDrawing = exquisiteCorpseHub(
      "corpse-hub-partner-drawing", "Exquisite corpse · hub, Robin is drawing",
      "Hub card while Robin draws the legs, with Robin in the game"
    )
    static let exquisiteCorpseHubReveal = exquisiteCorpseHub(
      "corpse-hub-reveal", "Exquisite corpse · hub, creature is ready",
      "Hub card when a finished creature waits for you to look at it"
    )
    static let exquisiteCorpseHubNotStarted = exquisiteCorpseHub(
      "corpse-hub-not-started", "Exquisite corpse · hub, not started",
      "Hub card before the couple has drawn anything"
    )
    static let exquisiteCorpseDrawHead = exquisiteCorpseScreen(
      "corpse-draw-head", "Exquisite corpse · drawing the head",
      "The first head of a new game, with the line that explains the fold"
    )
    static let exquisiteCorpseDrawBody = exquisiteCorpseScreen(
      "corpse-draw-body", "Exquisite corpse · drawing the body",
      "The canvas with the bottom of Robin's head above it as a strip"
    )
    static let exquisiteCorpseDrawLegs = exquisiteCorpseScreen(
      "corpse-draw-legs", "Exquisite corpse · drawing the legs",
      "The legs with the bottom of Robin's body above them and an idea chip"
    )
    static let exquisiteCorpseWaiting = exquisiteCorpseScreen(
      "corpse-waiting", "Exquisite corpse · waiting for Robin",
      "Robin is not in the game: the progress paper and the invite button"
    )
    static let exquisiteCorpseWatching = exquisiteCorpseScreen(
      "corpse-watching", "Exquisite corpse · watching Robin draw",
      "Robin draws the body live: the folded paper, a glow where the pen moves, and the strip"
    )
    static let exquisiteCorpseHandoff = exquisiteCorpseScreen(
      "corpse-handoff", "Exquisite corpse · hand-off to your turn",
      "Watch Robin finish the body, then the strip slides into your canvas for the legs"
    )
    static let exquisiteCorpseWaitingToSync = exquisiteCorpseScreen(
      "corpse-waiting-to-sync", "Exquisite corpse · legs saved offline",
      "Your legs are saved on the phone and not sent yet"
    )
    static let exquisiteCorpseReveal = exquisiteCorpseScreen(
      "corpse-reveal", "Exquisite corpse · reveal", "A finished creature unfolds part by part, with the credits"
    )
    static let exquisiteCorpseRevealLoading = exquisiteCorpseScreen(
      "corpse-reveal-loading", "Exquisite corpse · reveal, drawings still loading",
      "Robin's parts are still downloading: the folded paper waits"
    )
    static let exquisiteCorpseHistory = exquisiteCorpseScreen(
      "corpse-history", "Exquisite corpse · our creatures",
      "Twelve creatures in a grid, some starred. Open one to unfold it again"
    )
    static let exquisiteCorpseHistoryEmpty = exquisiteCorpseScreen(
      "corpse-history-empty", "Exquisite corpse · our creatures, none yet",
      "Our creatures before the first creature is finished"
    )
    static let exquisiteCorpseHistoryStarred = exquisiteCorpseScreen(
      "corpse-history-starred", "Exquisite corpse · our creatures, starred",
      "Our creatures with the Starred filter on"
    )
    static let exquisiteCorpseHistoryDetail = exquisiteCorpseScreen(
      "corpse-history-detail", "Exquisite corpse · one creature",
      "One creature opened from the grid: unfold, credits, star and Play again"
    )

    /// The real paired tabs on the Games tab, where the card sits next to Draw & Guess's.
    private static func exquisiteCorpseHub(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { DeveloperPairedScenarioHost(scenario: $0) }
    }

    private static func exquisiteCorpseScreen(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .games) { ExquisiteCorpseDeveloperScenarioView(scenario: $0) }
    }
  }
#endif
