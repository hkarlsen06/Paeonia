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

    case localFlowFresh = "local-flow-fresh"
    case localFlowOnboarding = "local-flow-onboarding"
    case localFlowPaywall = "local-flow-paywall"
    case localFlowPairing = "local-flow-pairing"
    case localFlowPaired = "local-flow-paired"

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

    case gamesSetup = "games-setup"
    case gamesPartnerPicked = "games-partner-picked"
    case gamesHubYourTurn = "games-hub-your-turn"
    case gamesHubWaiting = "games-hub-waiting"
    case gamesHubPartnerHere = "games-hub-partner-here"
    case drawChooseWord = "draw-choose-word"
    case drawWaitingForWord = "draw-waiting-for-word"
    case drawDrawing = "draw-drawing"
    case drawSavedOffline = "draw-saved-offline"
    case drawWaitingForGuess = "draw-waiting-for-guess"
    case drawWaitingForDrawing = "draw-waiting-for-drawing"
    case drawWatchingLive = "draw-watching-live"
    case drawGuessingReplay = "draw-guessing-replay"
    case drawGuessingLongWord = "draw-guessing-long-word"
    case drawRevealSolved = "draw-reveal-solved"
    case drawRevealBonuses = "draw-reveal-bonuses"
    case drawRevealMissed = "draw-reveal-missed"
    case drawRevealAsDrawer = "draw-reveal-as-drawer"
    case drawRevealPartnerDrawing = "draw-reveal-partner-drawing"
    case drawRevealLoading = "draw-reveal-loading"
    case drawHistory = "draw-history"
    case drawHistoryEmpty = "draw-history-empty"
    case storyChainChoose = "story-chain-choose"
    case storyChainChooseOffline = "story-chain-choose-offline"
    case storyChainWriting = "story-chain-writing"
    case storyChainWritingLast = "story-chain-writing-last"
    case storyChainWaitingLive = "story-chain-waiting-live"
    case storyChainWaitingAway = "story-chain-waiting-away"
    case storyChainSavedOffline = "story-chain-saved-offline"
    case storyChainNaming = "story-chain-naming"
    case storyChainWaitingName = "story-chain-waiting-name"
    case storyChainFinished = "story-chain-finished"
    case storyChainWaitingOpening = "story-chain-waiting-opening"
    case storyChainHistory = "story-chain-history"
    case storyChainHistoryEmpty = "story-chain-history-empty"

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

    var id: String { rawValue }

    var title: String {
      switch self {
      case .launchLoading: "Launch loading"
      case .welcome: "Welcome"
      case .signIn: "Sign in"
      case .signInInvite: "Sign in · invite saved"
      case .onboardingEmpty: "Onboarding · empty"
      case .onboardingPrefilled: "Onboarding · name filled"
      case .localFlowFresh: "Local flow · fresh install"
      case .localFlowOnboarding: "Local flow · onboarding"
      case .localFlowPaywall: "Local flow · paywall"
      case .localFlowPairing: "Local flow · pairing"
      case .localFlowPaired: "Local flow · paired app"
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
      case .gamesSetup: "Games · first-time setup"
      case .gamesPartnerPicked: "Games · partner already set up"
      case .gamesHubYourTurn: "Games · hub, your turn"
      case .gamesHubWaiting: "Games · hub, waiting for partner"
      case .gamesHubPartnerHere: "Games · hub, partner is here"
      case .drawChooseWord: "Draw & Guess · choose a word"
      case .drawWaitingForWord: "Draw & Guess · partner picks a word"
      case .drawDrawing: "Draw & Guess · drawing"
      case .drawSavedOffline: "Draw & Guess · drawing sent offline"
      case .drawWaitingForGuess: "Draw & Guess · partner is guessing"
      case .drawWaitingForDrawing: "Draw & Guess · waiting for a drawing"
      case .drawWatchingLive: "Draw & Guess · watching live"
      case .drawGuessingReplay: "Draw & Guess · guessing a replay"
      case .drawGuessingLongWord: "Draw & Guess · guessing a 20-letter word"
      case .drawRevealSolved: "Draw & Guess · reveal, solved"
      case .drawRevealBonuses: "Draw & Guess · reveal with bonuses and reactions"
      case .drawRevealMissed: "Draw & Guess · reveal, missed"
      case .drawRevealAsDrawer: "Draw & Guess · reveal as the drawer"
      case .drawRevealPartnerDrawing: "Draw & Guess · partner drew the next one"
      case .drawRevealLoading: "Draw & Guess · reveal, drawing still loading"
      case .drawHistory: "Draw & Guess · our drawings"
      case .drawHistoryEmpty: "Draw & Guess · our drawings, none yet"
      case .storyChainChoose: "Story Chain · choose an opening"
      case .storyChainChooseOffline: "Story Chain · choose an opening, offline"
      case .storyChainWriting: "Story Chain · your turn to write"
      case .storyChainWritingLast: "Story Chain · line 20, the last line"
      case .storyChainWaitingLive: "Story Chain · Robin is typing live"
      case .storyChainWaitingAway: "Story Chain · waiting for Robin, who is away"
      case .storyChainSavedOffline: "Story Chain · line sent offline"
      case .storyChainNaming: "Story Chain · name the story"
      case .storyChainWaitingName: "Story Chain · Robin is naming the story"
      case .storyChainFinished: "Story Chain · the finished story"
      case .storyChainWaitingOpening: "Story Chain · Robin picks an opening"
      case .storyChainHistory: "Story Chain · our stories"
      case .storyChainHistoryEmpty: "Story Chain · our stories, none yet"
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
        "Visual provider state; use Local flow · fresh install for functional sign-in"
      case .signInInvite:
        "Sign-in with a retained partner code"
      case .onboardingEmpty:
        "New profile with no display name"
      case .onboardingPrefilled:
        "Profile setup with a suggested name"
      case .localFlowFresh:
        "Apple or Google sign-in through the complete local app journey"
      case .localFlowOnboarding:
        "Complete profile setup, purchase access, pair, and continue"
      case .localFlowPaywall:
        "Simulate a purchase, then continue into pairing"
      case .localFlowPairing:
        "Create an invite and use Check pairing to simulate a partner joining"
      case .localFlowPaired:
        "Use the real tabs with local questions, memories, settings, and widget data"
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
      case .gamesSetup:
        "Games tab before the couple chose a play style and language"
      case .gamesPartnerPicked:
        "The one-time moment that shows what the partner picked"
      case .gamesHubYourTurn:
        "Hub with Draw & Guess waiting for your word"
      case .gamesHubWaiting:
        "Hub while Robin has the next move"
      case .gamesHubPartnerHere:
        "Hub with Robin's drawing waiting and Robin in the game"
      case .drawChooseWord:
        "Three words and the draw-your-own field"
      case .drawWaitingForWord:
        "Robin is choosing what to draw"
      case .drawDrawing:
        "The canvas with Robin watching live"
      case .drawSavedOffline:
        "A drawing queued on the phone: saved on this phone, sent later"
      case .drawWaitingForGuess:
        "The sent drawing and Robin's wrong guesses"
      case .drawWaitingForDrawing:
        "Tiles shown while the drawing has not arrived"
      case .drawWatchingLive:
        "Robin's umbrella appears live, with tiles to guess"
      case .drawGuessingReplay:
        "The saved umbrella plays back at the drawn pace"
      case .drawGuessingLongWord:
        "The longest custom word: slots split over two lines"
      case .drawRevealSolved:
        "You solved it: time, speed bonus, points"
      case .drawRevealBonuses:
        "Speed bonus +2, first try, your fastest solve yet, and the reaction row"
      case .drawRevealMissed:
        "You pressed Show me: the word and the drawing"
      case .drawRevealAsDrawer:
        "Robin solved your drawing: the guesses in order"
      case .drawRevealPartnerDrawing:
        "The result, and Robin already draws the next one: the button reads Watch Robin draw"
      case .drawRevealLoading:
        "You solved it while Robin's drawing is still downloading"
      case .drawHistory:
        "Records and a grid of finished drawings, some starred, one missed. Open one to replay it"
      case .drawHistoryEmpty:
        "Our drawings before the first round has finished"
      case .storyChainChoose:
        "Three opening lines and the choice to write your own first line"
      case .storyChainChooseOffline:
        "The offline message when no opening lines are on the phone. Your own first line still works"
      case .storyChainWriting:
        "Robin dared you to use LADDER and is reading along. The last-line switch is available"
      case .storyChainWritingLast:
        "Line 20 is always the last, so the switch is locked on. Robin dared you to use TUESDAY"
      case .storyChainWaitingLive:
        "Robin types line 8 letter by letter with two corrections, sends it, and then your turn opens"
      case .storyChainWaitingAway:
        "Robin has the turn and is not in the game. The page shows the hint and the invite button"
      case .storyChainSavedOffline:
        "Your line is queued after a failed try, so the page says it is saved on this phone"
      case .storyChainNaming:
        "Robin wrote the last line and you give the story a title"
      case .storyChainWaitingName:
        "You wrote the last line and Robin is on the naming screen"
      case .storyChainFinished:
        "Robin named your story and you have not seen it yet. The reveal plays, then Continue"
      case .storyChainWaitingOpening:
        "The last story just ended and Robin is picking the next opening"
      case .storyChainHistory:
        "Three finished stories, two starred. Open one to read it"
      case .storyChainHistoryEmpty:
        "Our stories before the first story has finished"
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
      case .localFlowFresh, .localFlowOnboarding, .localFlowPaywall, .localFlowPairing,
        .localFlowPaired:
        .localFlows
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
      case .gamesSetup, .gamesPartnerPicked, .gamesHubYourTurn, .gamesHubWaiting,
        .gamesHubPartnerHere, .drawChooseWord, .drawWaitingForWord, .drawDrawing, .drawSavedOffline,
        .drawWaitingForGuess, .drawWaitingForDrawing, .drawWatchingLive, .drawGuessingReplay,
        .drawGuessingLongWord, .drawRevealSolved, .drawRevealBonuses, .drawRevealMissed, .drawRevealAsDrawer,
        .drawRevealPartnerDrawing, .drawRevealLoading, .drawHistory, .drawHistoryEmpty,
        .storyChainChoose, .storyChainChooseOffline, .storyChainWriting, .storyChainWritingLast,
        .storyChainWaitingLive, .storyChainWaitingAway, .storyChainSavedOffline, .storyChainNaming,
        .storyChainWaitingName, .storyChainFinished, .storyChainWaitingOpening, .storyChainHistory,
        .storyChainHistoryEmpty:
        .games
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
