#if DEBUG
  import Testing
  @testable import PaeoniaApp

  struct DeveloperScenarioLaunchTests {
    @Test func defaultsToProduction() {
      #expect(DeveloperScenarioLaunch.destination(arguments: [], environment: [:]) == .production)
    }

    @Test func menuArgumentOpensCatalog() {
      #expect(
        DeveloperScenarioLaunch.destination(
          arguments: [DeveloperScenarioLaunch.menuArgument],
          environment: [:]
        ) == .menu
      )
    }

    @Test func directArgumentOpensRequestedScenario() {
      #expect(
        DeveloperScenarioLaunch.destination(
          arguments: [DeveloperScenarioLaunch.scenarioArgument, "questions"],
          environment: [DeveloperScenarioLaunch.environmentKey: ""]
        ) == .scenario(.questions)
      )
    }

    @Test func environmentTakesPrecedenceAndUnknownValuesFailIntoMenu() {
      #expect(
        DeveloperScenarioLaunch.destination(
          arguments: [DeveloperScenarioLaunch.scenarioArgument, "welcome"],
          environment: [DeveloperScenarioLaunch.environmentKey: "memories-empty"]
        ) == .scenario(.memoriesEmpty)
      )
      #expect(
        DeveloperScenarioLaunch.destination(
          arguments: [],
          environment: [DeveloperScenarioLaunch.environmentKey: "typo"]
        ) == .menu
      )
    }

    @Test func everyCatalogScenarioCanLaunchDirectly() {
      for scenario in DeveloperScenario.allCases {
        #expect(
          DeveloperScenarioLaunch.destination(
            arguments: [],
            environment: [DeveloperScenarioLaunch.environmentKey: scenario.rawValue]
          ) == .scenario(scenario)
        )
      }
    }

    /// Scenarios are values in per-game lists, so the compiler no longer catches a
    /// repeated id or a game list added twice.
    @Test func everyScenarioIDIsUnique() {
      let ids = DeveloperScenario.allCases.map(\.rawValue)
      #expect(Set(ids).count == ids.count)
    }

    @Test func everyCategoryContainsAtLeastOneScenario() {
      for category in DeveloperScenario.Category.allCases {
        #expect(DeveloperScenario.allCases.contains { $0.category == category })
      }
    }
  }
#endif
