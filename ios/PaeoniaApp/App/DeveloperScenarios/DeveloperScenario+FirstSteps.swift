#if DEBUG
  import Foundation

  /// Home after the first day with the "Things to try together" card, part done.
  nonisolated extension DeveloperScenario {
    static let firstSteps: [DeveloperScenario] = [homeFirstSteps]

    static let homeFirstSteps = DeveloperScenario(
      "home-first-steps", "Home · things to try together",
      "After the first day: a game and a topic answer done, three rows to go", .pairing
    ) { DeveloperPairedScenarioHost(scenario: $0) }
  }
#endif
