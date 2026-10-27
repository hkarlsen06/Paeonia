#if DEBUG
  import SwiftUI

  /// The scenarios outside the individual games, including the Games tab's setup
  /// and hub. Each game's own scenarios are in `DeveloperScenario+<Game>.swift`.
  nonisolated extension DeveloperScenario {
    static let app: [DeveloperScenario] = [
      launchLoading, welcome, signIn, signInInvite, onboardingEmpty, onboardingPrefilled, onboardingUsage,
      relationshipEnded, accountClosed, deletingAccount,
      localFlowFresh, localFlowOnboarding, localFlowPaywall, localFlowPairing, localFlowPaired,
      localFlowGameConversation,
      homeLaunchLocationFirst, homeLaunchCalendarFirst, homeLaunchOverlapping,
      pairingInviteReady, pairingJoin, pairingJoinPartner, pairingInviteExpired, pairingSafetyWarning,
      pairingInviteError,
      pairingCelebration, pairingCelebrationSettled, firstDayJoined, firstDayInvited,
      paywallTrial, paywallStandard, paywallDrawing, paywallPaired, paywallPairedEnded, paywallPairedPaymentFailed,
      paywallLoading,
      pairedHome, questions, questionsPartial, questionsRevealed, questionsEmpty, questionsLoading,
      questionsError, questionsHistory, questionsOfflineQueued, questionAnswerFlow, questionPartnerAnswersMeanwhile,
      streakHealthy, streakSaveHome, streakSaveDay, streakSaved, streakBroken, streakRestoreExpired, streakRestored,
      memoriesEmpty, memoriesPopulated, memoriesCards, memoryEditor, memoryDetail,
      countdownMissing, countdownUpcoming, countdownToday,
      locationNotSharing, locationCurrentMissing, locationLive, locationStale,
      widgetDrawing, widgetHistoryEmpty, widgetHistoryPopulated,
      gamesSetup, gamesPartnerPicked, gamesHubYourTurn, gamesHubWaiting, gamesHubReveal, gamesHubPartnerHere,
      gamesHubBoardGames,
      notificationPrimer, settings, settingsPartnerPays, settingsNotificationsDenied, privacySafety, reportAndLeave,
      deepLinkDailyToday, deepLinkDailyReveal, deepLinkWidget, deepLinkStreak, deepLinkSubscription,
    ]

    // MARK: Launch and authentication

    static let homeLaunchLocationFirst = DeveloperScenario(
      "home-launch-location-first", "Home launch, location first",
      "Cold launch through the real root with delayed question and calendar reads", .launchAndAuth
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .locationFirst) }

    static let homeLaunchCalendarFirst = DeveloperScenario(
      "home-launch-calendar-first", "Home launch, calendar first",
      "Cold launch through the real root with delayed question and location reads", .launchAndAuth
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .calendarFirst) }

    static let homeLaunchOverlapping = DeveloperScenario(
      "home-launch-overlapping", "Home launch, overlapping reads",
      "The map arrives while the question and calendar are animating", .launchAndAuth
    ) { _ in DeveloperLocalFlowHost(seed: .paired, homeLaunch: .overlapping) }

    static let launchLoading = DeveloperScenario(
      "launch-loading", "Launch loading", "Copy-free launch surface", .launchAndAuth
    ) { _ in AuthLaunchingView() }
    static let welcome = DeveloperScenario(
      "welcome", "Welcome", "Fresh install before authentication; Start our space walks the date and drawing",
      .launchAndAuth
    ) { _ in DeveloperWelcomeScenarioView(entry: .welcome) }
    static let signIn = DeveloperScenario(
      "sign-in", "Sign in · returning", "Visual provider state; use Local flow · fresh install for functional sign-in",
      .launchAndAuth
    ) { _ in DeveloperWelcomeScenarioView(entry: .returning) }
    static let signInInvite = DeveloperScenario(
      "sign-in-invite", "Sign in · invite saved", "Sign-in with a retained partner code", .launchAndAuth
    ) { _ in DeveloperWelcomeScenarioView(entry: .joining) }
    static let onboardingEmpty = DeveloperScenario(
      "onboarding-empty", "Onboarding · empty", "New profile with no display name", .launchAndAuth
    ) { _ in DeveloperOnboardingScenarioView(prefilled: false) }
    static let onboardingPrefilled = DeveloperScenario(
      "onboarding-prefilled", "Onboarding · name filled", "Profile setup with a suggested name", .launchAndAuth
    ) { _ in DeveloperOnboardingScenarioView(prefilled: true) }
    static let onboardingUsage = DeveloperScenario(
      "onboarding-usage", "Onboarding · usage question", "Second setup page: share usage statistics or not",
      .launchAndAuth
    ) { DeveloperSignedInNoticeScenarioView(scenario: $0) }
    static let relationshipEnded = DeveloperScenario(
      "relationship-ended", "Relationship ended", "The partner left; acknowledge to go back to pairing",
      .launchAndAuth
    ) { DeveloperSignedInNoticeScenarioView(scenario: $0) }
    static let accountClosed = DeveloperScenario(
      "account-closed", "Account closed", "Banned account with support, subscription and account actions",
      .launchAndAuth
    ) { DeveloperSignedInNoticeScenarioView(scenario: $0) }
    static let deletingAccount = DeveloperScenario(
      "deleting-account", "Deleting account", "Progress while the account is deleted", .launchAndAuth
    ) { DeveloperSignedInNoticeScenarioView(scenario: $0) }

    // MARK: Interactive local flows

    static let localFlowFresh = localFlow(
      "local-flow-fresh", "Local flow · fresh install",
      "Apple or Google sign-in through the complete local app journey", seed: .fresh
    )
    static let localFlowOnboarding = localFlow(
      "local-flow-onboarding", "Local flow · onboarding",
      "Complete profile setup, purchase access, pair, and continue", seed: .onboarding
    )
    static let localFlowPaywall = localFlow(
      "local-flow-paywall", "Local flow · paywall", "Simulate a purchase, then continue into pairing", seed: .paywall
    )
    static let localFlowPairing = localFlow(
      "local-flow-pairing", "Local flow · pairing",
      "Create and share an invite", seed: .pairing
    )
    static let localFlowPaired = localFlow(
      "local-flow-paired", "Local flow · paired app",
      "Use the real tabs with local questions, memories, settings, and widget data", seed: .paired
    )

    static let localFlowGameConversation = DeveloperScenario(
      "local-flow-game-conversation", "Local flow · game conversation",
      "Open a finished Mind Meld, write about it, and find the conversation in Chats", .localFlows
    ) { _ in DeveloperLocalFlowHost(seed: .paired, gameConversation: true) }

    // MARK: Pairing

    static let pairingInviteReady = pairing(
      "pairing-invite-ready", "Pairing invite · ready", "Shareable local invite without a second account"
    )
    static let pairingJoin = pairing(
      "pairing-join", "Pairing · enter invite", "Six-character invite entry before authentication"
    )
    static let pairingJoinPartner = pairing(
      "pairing-join-partner", "Pairing · join partner",
      "Join screen for someone with a partner's code, in place of the paywall"
    )
    static let pairingInviteExpired = pairing(
      "pairing-invite-expired", "Pairing invite · expired", "Expired invite recovery state"
    )
    static let pairingSafetyWarning = pairing(
      "pairing-safety-warning", "Pairing · safety warning", "Join screen for a flagged invite"
    )
    static let pairingInviteError = pairing(
      "pairing-invite-error", "Pairing invite · error", "Invite creation failure and retry"
    )
    static let pairingCelebration = pairing(
      "pairing-celebration", "Pairing celebration · intro", "Full relationship-link animation"
    )
    static let pairingCelebrationSettled = pairing(
      "pairing-celebration-settled", "Pairing celebration · settled", "Final celebration layout without animation"
    )
    static let firstDayJoined = DeveloperScenario(
      "first-day-joined", "First day · joined partner",
      "Celebration, then unwrap the gift, draw back, confirm the date, question time and answers", .pairing
    ) { _ in DeveloperPostPairingScenarioView(acceptedInvite: true) }
    static let firstDayInvited = DeveloperScenario(
      "first-day-invited", "First day · inviter",
      "Celebration, then the partner's drawing back. Date, question time and answers are skipped", .pairing
    ) { _ in DeveloperPostPairingScenarioView(acceptedInvite: false) }

    // MARK: Paywall

    static let paywallTrial = paywall(
      "paywall-trial", "Paywall · free trial", "Unpaired offer with eligible-trial copy"
    )
    static let paywallStandard = paywall(
      "paywall-standard", "Paywall · standard", "Unpaired offer without a trial"
    )
    static let paywallDrawing = paywall(
      "paywall-drawing", "Paywall · drawing ready", "Unpaired offer while the first drawing waits to send"
    )
    static let paywallPaired = paywall(
      "paywall-paired", "Paywall · paired", "Couple remains linked but access expired; the partner paid"
    )
    static let paywallPairedEnded = paywall(
      "paywall-paired-ended", "Paywall · paired, payer", "This person's own subscription ended; Manage subscription"
    )
    static let paywallPairedPaymentFailed = paywall(
      "paywall-paired-payment-failed", "Paywall · paired, payment failed",
      "Apple is still retrying this person's payment; Update payment instead of plans"
    )
    static let paywallLoading = paywall(
      "paywall-loading", "Paywall · loading", "Stable blank surface while products settle"
    )

    // MARK: Questions

    static let pairedHome = pairedApp(
      "paired-home", "Paired home", "Entitled, paired couple with sample questions", .questions
    )
    static let questions = pairedApp(
      "questions", "Questions · unanswered", "Questions tab with answerable sample content", .questions
    )
    static let questionsPartial = pairedApp(
      "questions-partial", "Questions · partial", "Mixed answered and unanswered questions", .questions
    )
    static let questionsRevealed = pairedApp(
      "questions-revealed", "Questions · revealed", "Both replies visible in the read list", .questions
    )
    static let questionsEmpty = pairedApp(
      "questions-empty", "Questions · empty", "No challenge available for the day", .questions
    )
    static let questionsLoading = pairedApp(
      "questions-loading", "Questions · loading", "In-flight initial question load", .questions
    )
    static let questionsError = pairedApp(
      "questions-error", "Questions · error", "Failed initial load and retry state", .questions
    )
    static let questionsHistory = pairedApp(
      "questions-history", "Questions · history", "Earlier days listed under today's questions", .questions
    )
    static let questionsOfflineQueued = pairedApp(
      "questions-offline-queued", "Questions · saved offline", "Answer retained locally while waiting to send",
      .questions
    )
    static let questionAnswerFlow = pairedApp(
      "question-answer-flow", "Questions · answer flow", "Full-screen answer composer opened directly", .questions
    )
    static let questionPartnerAnswersMeanwhile = pairedApp(
      "question-partner-answers-meanwhile", "Questions · partner answers meanwhile",
      "Robin's answer lands right after yours, so the flow turns to the reveal", .questions
    )

    // MARK: Streak

    static let streakHealthy = streak(
      "streak-healthy", "Streak · healthy", "Current and longest streak detail"
    )
    static let streakSaveHome = pairedApp(
      "streak-save-home", "Streak · free save on Home", "Home card and paused pill the day after a missed day",
      .streak
    )
    static let streakSaveDay = streak(
      "streak-save-day", "Streak · free save day", "Streak sheet the day after a missed day, partner still to come"
    )
    static let streakSaved = streak(
      "streak-saved", "Streak · saved", "Both showed up on the free save day"
    )
    static let streakBroken = streak(
      "streak-broken", "Streak · restore offer", "Paid restore on the second or third day after the missed one"
    )
    static let streakRestoreExpired = streak(
      "streak-restore-expired", "Streak · gone for good", "The restore offer once the third day is over"
    )
    static let streakRestored = streak(
      "streak-restored", "Streak · restored", "Successful restore celebration"
    )

    // MARK: Memories

    static let memoriesEmpty = pairedApp(
      "memories-empty", "Memories · empty", "Paired Memories tab backed by an empty local store", .memories
    )
    static let memoriesPopulated = pairedApp(
      "memories-populated", "Memories · populated", "Several local memories with both partners' notes", .memories
    )
    static let memoriesCards = pairedApp(
      "memories-cards", "Memories · timeline cards",
      "Short, long and extreme titles, square photos, notes, a place and a memory saved on this phone", .memories
    )
    static let memoryEditor = DeveloperScenario(
      "memory-editor", "Memory · editor", "New-memory form without opening the timeline first", .memories
    ) { _ in DeveloperMemoryEditorScenarioView() }
    static let memoryDetail = DeveloperScenario(
      "memory-detail", "Memory · detail", "One memory with both partners' notes", .memories
    ) { _ in DeveloperMemoryDetailScenarioView() }

    // MARK: Countdown and location

    static let countdownMissing = relationship(
      "countdown-missing", "Countdown · date missing", "Relationship date setup state"
    )
    static let countdownUpcoming = relationship(
      "countdown-upcoming", "Countdown · upcoming", "Next relationship milestone countdown"
    )
    static let countdownToday = relationship(
      "countdown-today", "Countdown · milestone today", "Milestone-day celebration treatment"
    )
    static let locationNotSharing = relationship(
      "location-not-sharing", "Location · partner not sharing", "Partner has not enabled location sharing"
    )
    static let locationCurrentMissing = relationship(
      "location-current-missing", "Location · current missing", "Current device needs a location refresh"
    )
    static let locationLive = relationship(
      "location-live", "Location · live", "Both partners visible on the map"
    )
    static let locationStale = relationship(
      "location-stale", "Location · stale partner", "Partner location older than 24 hours"
    )

    // MARK: Widget

    static let widgetDrawing = widget(
      "widget-drawing", "Widget · drawing canvas", "Isolated PencilKit canvas with local no-op services"
    )
    static let widgetHistoryEmpty = widget(
      "widget-history-empty", "Widget · empty history", "Drawing history empty state"
    )
    static let widgetHistoryPopulated = widget(
      "widget-history-populated", "Widget · populated history", "Drawing history with both partners' revisions"
    )

    // MARK: Games tab

    static let gamesSetup = pairedApp(
      "games-setup", "Games · first-time setup",
      "Hub before the couple chose a play style and language. Open a game for setup", .games
    )
    static let gamesPartnerPicked = pairedApp(
      "games-partner-picked", "Games · partner already set up",
      "Open a game for the one-time moment that shows what the partner picked", .games
    )
    static let gamesHubYourTurn = pairedApp(
      "games-hub-your-turn", "Games · hub, your turn", "Hub with Draw & Guess waiting for your word", .games
    )
    static let gamesHubWaiting = pairedApp(
      "games-hub-waiting", "Games · hub, waiting for partner", "Hub while Robin has the next move", .games
    )
    static let gamesHubReveal = pairedApp(
      "games-hub-reveal", "Games · hub, drawing result",
      "An unseen drawing result can be opened or put aside while Robin has the next turn", .games
    )
    static let gamesHubPartnerHere = pairedApp(
      "games-hub-partner-here", "Games · hub, partner is here",
      "Hub with Robin's drawing waiting and Robin in the game", .games
    )
    static let gamesHubBoardGames = pairedApp(
      "games-hub-board-games", "Games · hub with the board games",
      "All four cards: Four in a Row on your move, Dots and Boxes with Robin in it, "
        + "Ultimate Tic-Tac-Toe won by Robin",
      .games
    )

    // MARK: Settings and privacy

    static let notificationPrimer = settingsScreen(
      "notification-primer", "Notifications · primer", "Pre-permission notification explanation"
    )
    static let settings = settingsScreen(
      "settings", "Settings", "Paired settings; Alex pays and is in the free trial"
    )
    static let settingsPartnerPays = settingsScreen(
      "settings-partner-pays", "Settings · partner pays", "Paired settings while Robin's subscription covers Alex"
    )
    static let settingsNotificationsDenied = settingsScreen(
      "settings-notifications-denied", "Settings · notifications denied",
      "In-app preferences while iOS notifications are off"
    )
    static let privacySafety = settingsScreen(
      "privacy-safety", "Privacy & safety", "Data requests and safety destinations"
    )
    static let reportAndLeave = settingsScreen(
      "report-and-leave", "Report and leave", "Conduct report form without submitting remotely"
    )

    // MARK: Deep links and notifications

    static let deepLinkDailyToday = DeveloperScenario(
      "deep-link-daily-today", "Deep link · today's questions", "Notification route into today's answer flow",
      .deepLinks
    ) { _ in DeveloperPairedScenarioHost(scenario: .questionAnswerFlow) }
    static let deepLinkDailyReveal = DeveloperScenario(
      "deep-link-daily-reveal", "Deep link · revealed answer", "Notification route to a revealed exchange",
      .deepLinks
    ) { _ in DeveloperPairedScenarioHost(scenario: .questionsRevealed) }
    static let deepLinkWidget = DeveloperScenario(
      "deep-link-widget", "Deep link · widget drawing", "Notification route to the drawing canvas", .deepLinks
    ) { _ in DeveloperWidgetScenarioView(scenario: .widgetDrawing) }
    static let deepLinkStreak = DeveloperScenario(
      "deep-link-streak", "Deep link · streak", "Notification route to streak detail", .deepLinks
    ) { _ in DeveloperStreakScenarioView(scenario: .streakHealthy) }
    static let deepLinkSubscription = DeveloperScenario(
      "deep-link-subscription", "Deep link · subscription",
      "Subscription reminder destination without opening App Store", .deepLinks
    ) { _ in DeveloperSettingsScenarioView(scenario: .settings) }

    // MARK: Screens

    private static func localFlow(
      _ id: String, _ title: String, _ detail: String, seed: DeveloperLocalFlowSeed
    ) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .localFlows) { _ in DeveloperLocalFlowHost(seed: seed) }
    }

    private static func pairing(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .pairing) { DeveloperPairingScenarioView(scenario: $0) }
    }

    private static func paywall(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .paywall) { DeveloperPaywallScenarioView(scenario: $0) }
    }

    /// The real paired tabs, opened on the tab the scenario is about.
    private static func pairedApp(
      _ id: String, _ title: String, _ detail: String, _ category: Category
    ) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, category) { DeveloperPairedScenarioHost(scenario: $0) }
    }

    private static func streak(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .streak) { DeveloperStreakScenarioView(scenario: $0) }
    }

    private static func relationship(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .relationship) { DeveloperRelationshipScenarioView(scenario: $0) }
    }

    private static func widget(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .widget) { DeveloperWidgetScenarioView(scenario: $0) }
    }

    private static func settingsScreen(_ id: String, _ title: String, _ detail: String) -> DeveloperScenario {
      DeveloperScenario(id, title, detail, .settings) { DeveloperSettingsScenarioView(scenario: $0) }
    }
  }

  /// The signed-out flow with local stores that count nothing and keep the drawing in
  /// memory, opened at welcome or at sign-in.
  private struct DeveloperWelcomeScenarioView: View {
    enum Entry {
      case welcome
      case returning
      case joining
    }

    @State private var model: WelcomeFlowModel
    @State private var pendingInviteCode: String?

    init(entry: Entry) {
      let model = WelcomeFlowModel(
        store: InMemoryWelcomeFlowStore(),
        funnel: NoOpWelcomeFunnelRecorder(),
        canvas: DeveloperWidgetCanvasService(),
        pendingUploads: WidgetPendingUploadStore(
          defaults: DeveloperInviterFixture.defaults,
          key: WelcomeDrawingStorage.pendingUploadKey
        )
      )
      if entry == .returning {
        model.chooseReturning()
      }
      _model = State(initialValue: model)
      _pendingInviteCode = State(initialValue: entry == .joining ? "LOVE26" : nil)
    }

    var body: some View {
      WelcomeFlowView(
        model: model,
        isWorking: false,
        signingInWith: nil,
        pendingInviteCode: pendingInviteCode,
        onAppleSignIn: {},
        onGoogleSignIn: {},
        onSubmitInviteCode: { pendingInviteCode = $0 },
        onForgetInviteCode: { pendingInviteCode = nil }
      )
    }
  }
#endif
