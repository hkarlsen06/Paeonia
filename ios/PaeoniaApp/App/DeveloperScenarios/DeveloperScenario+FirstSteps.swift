#if DEBUG
  import Foundation

  /// Home after the first day with the "Things to try together" card.
  nonisolated extension DeveloperScenario {
    static let firstSteps: [DeveloperScenario] = [homeFirstSteps, homeFirstStepsFinished]

    static let homeFirstSteps = DeveloperScenario(
      "home-first-steps", "Home · things to try together",
      "After the first day: a game and a topic answer done, three rows to go", .pairing
    ) { DeveloperPairedScenarioHost(scenario: $0) }

    static let homeFirstStepsFinished = DeveloperScenario(
      "home-first-steps-finished", "Home · things to try together, all done",
      "Every row done: the card plays its finish moment once Home shows it, then goes away", .pairing
    ) { DeveloperPairedScenarioHost(scenario: $0) }

    /// The saved card a first steps scenario starts with. Nil for every other scenario.
    var firstStepsProgress: HomeFirstStepsProgress? {
      switch self {
      case .homeFirstSteps: HomeFirstStepsProgress(doneSteps: [.game, .topic])
      case .homeFirstStepsFinished: HomeFirstStepsProgress(doneSteps: Set(HomeFirstStep.allCases))
      default: nil
      }
    }
  }
#endif
