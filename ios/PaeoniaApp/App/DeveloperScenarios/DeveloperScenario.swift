#if DEBUG
  import SwiftUI

  /// Debug-only destinations for launching a feature without creating accounts,
  /// pairing a couple, or granting a real entitlement. Scenario services are local
  /// and in-memory so using this harness can never change production data.
  ///
  /// A scenario is a value with its id, menu text, category and screen. The app
  /// scenarios are in `DeveloperScenario+App.swift`, and each game declares its
  /// own in `DeveloperScenario+<Game>.swift` as static members and one list.
  /// Code elsewhere matches them like enum cases, as in `case .drawDrawing:`.
  nonisolated struct DeveloperScenario: Hashable, Identifiable, Sendable {
    /// Every scenario, in menu order within each category. A new game adds its
    /// list here.
    static let allCases: [DeveloperScenario] =
      app + inviter + dailyCard + drawAndGuess + storyChain + mindMeld + exquisiteCorpse + boardGames

    nonisolated enum Category: String, CaseIterable, Identifiable, Sendable {
      case launchAndAuth = "State · Launch & authentication"
      case localFlows = "Interactive local flows"
      case pairing = "State · Pairing"
      case paywall = "State · Paywall & entitlement"
      case questions = "State · Questions"
      case streak = "State · Streak"
      case memories = "State · Memories"
      case relationship = "State · Countdown & location"
      case games = "State · Games"
      case widget = "State · Widget"
      case settings = "State · Settings & privacy"
      case deepLinks = "State · Deep links & notifications"

      var id: String { rawValue }
    }

    /// The id for `-paeonia-scenario`, `PAEONIA_SCENARIO` and the menu row.
    let rawValue: String
    let title: String
    let detail: String
    let category: Category
    private let content: @MainActor @Sendable (DeveloperScenario) -> AnyView

    var id: String { rawValue }

    init<Content: View>(
      _ rawValue: String,
      _ title: String,
      _ detail: String,
      _ category: Category,
      content: @escaping @MainActor @Sendable (DeveloperScenario) -> Content
    ) {
      self.rawValue = rawValue
      self.title = title
      self.detail = detail
      self.category = category
      self.content = { AnyView(content($0)) }
    }

    init?(rawValue: String) {
      guard let scenario = Self.allCases.first(where: { $0.rawValue == rawValue }) else { return nil }
      self = scenario
    }

    /// The screen this scenario opens.
    @MainActor func makeView() -> AnyView {
      content(self)
    }

    static func == (lhs: DeveloperScenario, rhs: DeveloperScenario) -> Bool {
      lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
      hasher.combine(rawValue)
    }
  }

  nonisolated enum DeveloperScenarioDestination: Equatable {
    case production
    case menu
    case scenario(DeveloperScenario)
    case tour
  }

  /// Parses the same launch configuration from Xcode schemes and XCUI tests.
  ///
  /// Supported forms:
  /// - `-paeonia-scenarios` opens the catalog.
  /// - `-paeonia-scenario questions` opens one scenario directly.
  /// - `PAEONIA_SCENARIO=questions` is the equivalent environment variable.
  /// - `-paeonia-scenario-tour` opens every scenario in turn, for a UI test.
  enum DeveloperScenarioLaunch {
    static let environmentKey = "PAEONIA_SCENARIO"
    static let menuArgument = "-paeonia-scenarios"
    static let scenarioArgument = "-paeonia-scenario"
    static let tourArgument = "-paeonia-scenario-tour"

    static func destination(
      arguments: [String] = ProcessInfo.processInfo.arguments,
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> DeveloperScenarioDestination {
      if let value = environment[environmentKey], !value.isEmpty {
        return destination(for: value)
      }

      if let index = arguments.firstIndex(of: scenarioArgument),
        arguments.indices.contains(index + 1)
      {
        return destination(for: arguments[index + 1])
      }

      if arguments.contains(menuArgument) {
        return .menu
      }

      if arguments.contains(tourArgument) {
        return .tour
      }

      return .production
    }

    private static func destination(for value: String) -> DeveloperScenarioDestination {
      if value == "menu" {
        return .menu
      }
      if value == "production" {
        return .production
      }
      if let scenario = DeveloperScenario(rawValue: value) {
        return .scenario(scenario)
      }
      return .menu
    }
  }
#endif
