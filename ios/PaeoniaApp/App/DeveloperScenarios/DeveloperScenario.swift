#if DEBUG
  import Foundation

  /// Debug-only destinations for launching a feature without creating accounts,
  /// pairing a couple, or granting a real entitlement. Scenario services are local
  /// and in-memory so using this harness can never change production data.
  enum DeveloperScenario: String, CaseIterable, Hashable, Identifiable {
    case launchLoading = "launch-loading"
    case welcome
    case signIn = "sign-in"
    case signInInvite = "sign-in-invite"
    case onboardingEmpty = "onboarding-empty"
    case onboardingPrefilled = "onboarding-prefilled"

    case pairingInviteReady = "pairing-invite-ready"
    case pairingJoin = "pairing-join"
    case pairingInviteExpired = "pairing-invite-expired"
    case pairingSafetyWarning = "pairing-safety-warning"
    case pairingInviteError = "pairing-invite-error"
    case pairingCelebration = "pairing-celebration"
    case pairingCelebrationSettled = "pairing-celebration-settled"

    case paywallTrial = "paywall-trial"
    case paywallStandard = "paywall-standard"
    case paywallPaired = "paywall-paired"
    case paywallLoading = "paywall-loading"

    case pairedHome = "paired-home"
    case questions
    case questionsPartial = "questions-partial"
    case questionsRevealed = "questions-revealed"
    case questionsEmpty = "questions-empty"
    case questionsLoading = "questions-loading"
    case questionsError = "questions-error"
    case questionsHistory = "questions-history"
    case questionsOfflineQueued = "questions-offline-queued"
    case questionAnswerFlow = "question-answer-flow"

    case streakHealthy = "streak-healthy"
    case streakBroken = "streak-broken"
    case streakRestored = "streak-restored"

    case memoriesEmpty = "memories-empty"
    case memoriesPopulated = "memories-populated"
    case memoryEditor = "memory-editor"
    case memoryDetail = "memory-detail"

    case countdownMissing = "countdown-missing"
    case countdownUpcoming = "countdown-upcoming"
    case countdownToday = "countdown-today"

    case locationNotSharing = "location-not-sharing"
    case locationCurrentMissing = "location-current-missing"
    case locationLive = "location-live"
    case locationStale = "location-stale"

    case widgetDrawing = "widget-drawing"
    case widgetHistoryEmpty = "widget-history-empty"
    case widgetHistoryPopulated = "widget-history-populated"

    case notificationPrimer = "notification-primer"
    case settings
    case settingsNotificationsDenied = "settings-notifications-denied"
    case privacySafety = "privacy-safety"
    case reportAndLeave = "report-and-leave"

    case deepLinkDailyToday = "deep-link-daily-today"
    case deepLinkDailyReveal = "deep-link-daily-reveal"
    case deepLinkWidget = "deep-link-widget"
    case deepLinkStreak = "deep-link-streak"
    case deepLinkSubscription = "deep-link-subscription"

    enum Category: String, CaseIterable, Identifiable {
      case launchAndAuth = "Launch & authentication"
      case pairing
      case paywall = "Paywall & entitlement"
      case questions
      case streak
      case memories
      case relationship = "Countdown & location"
      case widget
      case settings = "Settings & privacy"
      case deepLinks = "Deep links & notifications"

      var id: String { rawValue }
    }

    var id: String { rawValue }

    var title: String {
      switch self {
      case .launchLoading: "Launch loading"
      case .welcome: "Welcome"
      case .signIn: "Sign in"
      case .signInInvite: "Sign in · invite saved"
      case .onboardingEmpty: "Onboarding · empty"
      case .onboardingPrefilled: "Onboarding · name filled"
      case .pairingInviteReady: "Pairing invite · ready"
      case .pairingJoin: "Pairing · enter invite"
      case .pairingInviteExpired: "Pairing invite · expired"
      case .pairingSafetyWarning: "Pairing · safety warning"
      case .pairingInviteError: "Pairing invite · error"
      case .pairingCelebration: "Pairing celebration · intro"
      case .pairingCelebrationSettled: "Pairing celebration · settled"
      case .paywallTrial: "Paywall · free trial"
      case .paywallStandard: "Paywall · standard"
      case .paywallPaired: "Paywall · paired"
      case .paywallLoading: "Paywall · loading"
      case .pairedHome: "Paired home"
      case .questions: "Questions · unanswered"
      case .questionsPartial: "Questions · partial"
      case .questionsRevealed: "Questions · revealed"
      case .questionsEmpty: "Questions · empty"
      case .questionsLoading: "Questions · loading"
      case .questionsError: "Questions · error"
      case .questionsHistory: "Questions · history"
      case .questionsOfflineQueued: "Questions · saved offline"
      case .questionAnswerFlow: "Questions · answer flow"
      case .streakHealthy: "Streak · healthy"
      case .streakBroken: "Streak · restore offer"
      case .streakRestored: "Streak · restored"
      case .memoriesEmpty: "Memories · empty"
      case .memoriesPopulated: "Memories · populated"
      case .memoryEditor: "Memory · editor"
      case .memoryDetail: "Memory · detail"
      case .countdownMissing: "Countdown · date missing"
      case .countdownUpcoming: "Countdown · upcoming"
      case .countdownToday: "Countdown · milestone today"
      case .locationNotSharing: "Location · partner not sharing"
      case .locationCurrentMissing: "Location · current missing"
      case .locationLive: "Location · live"
      case .locationStale: "Location · stale partner"
      case .widgetDrawing: "Widget · drawing canvas"
      case .widgetHistoryEmpty: "Widget · empty history"
      case .widgetHistoryPopulated: "Widget · populated history"
      case .notificationPrimer: "Notifications · primer"
      case .settings: "Settings"
      case .settingsNotificationsDenied: "Settings · notifications denied"
      case .privacySafety: "Privacy & safety"
      case .reportAndLeave: "Report and leave"
      case .deepLinkDailyToday: "Deep link · today's questions"
      case .deepLinkDailyReveal: "Deep link · revealed answer"
      case .deepLinkWidget: "Deep link · widget drawing"
      case .deepLinkStreak: "Deep link · streak"
      case .deepLinkSubscription: "Deep link · subscription"
      }
    }

    var detail: String {
      switch self {
      case .launchLoading:
        "Copy-free launch surface"
      case .welcome:
        "Fresh install before authentication"
      case .signIn:
        "Provider choices without starting OAuth"
      case .signInInvite:
        "Sign-in with a retained partner code"
      case .onboardingEmpty:
        "New profile with no display name"
      case .onboardingPrefilled:
        "Profile setup with a suggested name"
      case .pairingInviteReady:
        "Shareable local invite without a second account"
      case .pairingJoin:
        "Six-character invite entry before authentication"
      case .pairingInviteExpired:
        "Expired invite recovery state"
      case .pairingSafetyWarning:
        "Confirmation before joining a flagged invite"
      case .pairingInviteError:
        "Invite creation failure and retry"
      case .pairingCelebration:
        "Full relationship-link animation"
      case .pairingCelebrationSettled:
        "Final celebration layout without animation"
      case .paywallTrial:
        "Unpaired offer with eligible-trial copy"
      case .paywallStandard:
        "Unpaired offer without a trial"
      case .paywallPaired:
        "Couple remains linked but access expired"
      case .paywallLoading:
        "Stable blank surface while products settle"
      case .pairedHome:
        "Entitled, paired couple with sample questions"
      case .questions:
        "Questions tab with answerable sample content"
      case .questionsPartial:
        "Mixed answered and unanswered questions"
      case .questionsRevealed:
        "Both replies visible in the read list"
      case .questionsEmpty:
        "No challenge available for the day"
      case .questionsLoading:
        "In-flight initial question load"
      case .questionsError:
        "Failed initial load and retry state"
      case .questionsHistory:
        "Several completed exchanges grouped by day"
      case .questionsOfflineQueued:
        "Answer retained locally while waiting to send"
      case .questionAnswerFlow:
        "Full-screen answer composer opened directly"
      case .streakHealthy:
        "Current and longest streak detail"
      case .streakBroken:
        "Time-limited streak restore offer"
      case .streakRestored:
        "Successful restore celebration"
      case .memoriesEmpty:
        "Paired Memories tab backed by an empty local store"
      case .memoriesPopulated:
        "Several local memories with both partners' notes"
      case .memoryEditor:
        "New-memory form without opening the timeline first"
      case .memoryDetail:
        "One memory with both partners' notes"
      case .countdownMissing:
        "Relationship date setup state"
      case .countdownUpcoming:
        "Next relationship milestone countdown"
      case .countdownToday:
        "Milestone-day celebration treatment"
      case .locationNotSharing:
        "Partner has not enabled location sharing"
      case .locationCurrentMissing:
        "Current device needs a location refresh"
      case .locationLive:
        "Both partners visible on the map"
      case .locationStale:
        "Partner location older than 24 hours"
      case .widgetDrawing:
        "Isolated PencilKit canvas with local no-op services"
      case .widgetHistoryEmpty:
        "Drawing history empty state"
      case .widgetHistoryPopulated:
        "Drawing history with both partners' revisions"
      case .notificationPrimer:
        "Pre-permission notification explanation"
      case .settings:
        "Paired settings with local preferences"
      case .settingsNotificationsDenied:
        "In-app preferences while iOS notifications are off"
      case .privacySafety:
        "Data requests and safety destinations"
      case .reportAndLeave:
        "Conduct report form without submitting remotely"
      case .deepLinkDailyToday:
        "Notification route into today's answer flow"
      case .deepLinkDailyReveal:
        "Notification route to a revealed exchange"
      case .deepLinkWidget:
        "Notification route to the drawing canvas"
      case .deepLinkStreak:
        "Notification route to streak detail"
      case .deepLinkSubscription:
        "Subscription reminder destination without opening App Store"
      }
    }

    var category: Category {
      switch self {
      case .launchLoading, .welcome, .signIn, .signInInvite, .onboardingEmpty, .onboardingPrefilled:
        .launchAndAuth
      case .pairingInviteReady, .pairingJoin, .pairingInviteExpired, .pairingSafetyWarning,
        .pairingInviteError, .pairingCelebration, .pairingCelebrationSettled:
        .pairing
      case .paywallTrial, .paywallStandard, .paywallPaired, .paywallLoading:
        .paywall
      case .pairedHome, .questions, .questionsPartial, .questionsRevealed, .questionsEmpty,
        .questionsLoading, .questionsError, .questionsHistory, .questionAnswerFlow:
        .questions
      case .streakHealthy, .streakBroken, .streakRestored:
        .streak
      case .questionsOfflineQueued:
        .questions
      case .memoriesEmpty, .memoriesPopulated, .memoryEditor, .memoryDetail:
        .memories
      case .countdownMissing, .countdownUpcoming, .countdownToday, .locationNotSharing,
        .locationCurrentMissing, .locationLive, .locationStale:
        .relationship
      case .widgetDrawing, .widgetHistoryEmpty, .widgetHistoryPopulated:
        .widget
      case .notificationPrimer, .settings, .settingsNotificationsDenied, .privacySafety,
        .reportAndLeave:
        .settings
      case .deepLinkDailyToday, .deepLinkDailyReveal, .deepLinkWidget, .deepLinkStreak,
        .deepLinkSubscription:
        .deepLinks
      }
    }
  }

  enum DeveloperScenarioDestination: Equatable {
    case production
    case menu
    case scenario(DeveloperScenario)
  }

  /// Parses the same launch configuration from Xcode schemes and XCUI tests.
  ///
  /// Supported forms:
  /// - `-paeonia-scenarios` opens the catalog.
  /// - `-paeonia-scenario questions` opens one scenario directly.
  /// - `PAEONIA_SCENARIO=questions` is the equivalent environment variable.
  enum DeveloperScenarioLaunch {
    static let environmentKey = "PAEONIA_SCENARIO"
    static let menuArgument = "-paeonia-scenarios"
    static let scenarioArgument = "-paeonia-scenario"

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
