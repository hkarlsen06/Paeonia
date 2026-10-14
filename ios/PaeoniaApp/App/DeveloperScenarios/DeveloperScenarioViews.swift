#if DEBUG
  import SwiftUI

  struct DeveloperScenarioMenu: View {
    let runProductionApp: () -> Void
    // Scenarios open full screen, not pushed. Several screens own a NavigationStack, and
    // one nested inside the menu's stack can cancel the push (the Games tab binds a path).
    @State private var openScenario: DeveloperScenario?

    var body: some View {
      NavigationStack {
        List {
          ForEach(DeveloperScenario.Category.allCases) { category in
            Section(category.rawValue) {
              ForEach(scenarios(in: category)) { scenario in
                Button {
                  openScenario = scenario
                } label: {
                  HStack {
                    scenarioLabel(scenario)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                      .font(.footnote.weight(.semibold))
                      .foregroundStyle(.paeoniaTextTertiary)
                  }
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("developer.scenario.\(scenario.rawValue)")
              }
            }
          }

          Section {
            Button("Run production app") {
              runProductionApp()
            }
            .accessibilityIdentifier("developer.scenario.production")
          }
        }
        .scrollContentBackground(.hidden)
        .background(.paeoniaBackgroundPrimary)
        .navigationTitle("Developer Scenarios")
      }
      .fullScreenCover(item: $openScenario) { scenario in
        DeveloperScenarioHost(scenario: scenario) {
          openScenario = nil
        }
      }
      .preferredColorScheme(.dark)
      .accessibilityIdentifier("developer.scenario.menu")
    }

    private func scenarioLabel(_ scenario: DeveloperScenario) -> some View {
      VStack(alignment: .leading, spacing: PaeoniaSpacing.space4) {
        Text(scenario.title)
          .foregroundStyle(.paeoniaTextPrimary)
        Text(scenario.detail)
          .font(PaeoniaTypography.caption)
          .foregroundStyle(.paeoniaTextSecondary)
        Text(scenario.rawValue)
          .font(.caption2.monospaced())
          .foregroundStyle(.paeoniaTextTertiary)
      }
      .padding(.vertical, PaeoniaSpacing.space4)
    }

    private func scenarios(in category: DeveloperScenario.Category) -> [DeveloperScenario] {
      DeveloperScenario.allCases.filter { $0.category == category }
    }
  }

  struct DeveloperScenarioHost: View {
    let scenario: DeveloperScenario
    let returnToMenu: () -> Void
    @State private var bannerCenter = PaeoniaBannerCenter()
    @State private var reloadID = UUID()

    var body: some View {
      scenarioContent
        .id(reloadID)
        .environment(bannerCenter)
        .preferredColorScheme(.dark)
        // No host-level accessibilityIdentifier here: a container identifier
        // cascades onto every descendant element, replacing the production
        // identifiers (auth.signIn.apple, legal.privacy, …) UI tests query.
        .overlay(alignment: .topTrailing) {
          // `-paeonia-scenario-hide-controls YES` hides these buttons for screenshots
          // of the toolbar they cover.
          if !UserDefaults.standard.bool(forKey: "paeonia-scenario-hide-controls") {
            scenarioControls
          }
        }
    }

    private var scenarioControls: some View {
      HStack(spacing: PaeoniaSpacing.space8) {
        Button {
          reloadID = UUID()
        } label: {
          Image(systemName: "arrow.counterclockwise")
            .frame(width: 44, height: 44)
            .background(.paeoniaSurfacePrimary.opacity(0.92), in: Circle())
        }
        .accessibilityLabel("Reset scenario")
        .accessibilityIdentifier("developer.scenario.reset")

        Button(action: returnToMenu) {
          Image(systemName: "wrench.and.screwdriver.fill")
            .frame(width: 44, height: 44)
            .background(.paeoniaSurfacePrimary.opacity(0.92), in: Circle())
        }
        .accessibilityLabel("Return to developer scenarios")
        .accessibilityIdentifier("developer.scenario.return")
      }
      .foregroundStyle(.paeoniaTextPrimary)
      .padding(.top, PaeoniaSpacing.space8)
      .padding(.trailing, PaeoniaSpacing.space8)
    }

    @ViewBuilder
    private var scenarioContent: some View {
      switch scenario {
      case .launchLoading:
        AuthLaunchingView()
      case .welcome, .signIn:
        // Welcome and sign-in are one screen.
        welcome(pendingInviteCode: nil)
      case .signInInvite:
        welcome(pendingInviteCode: "LOVE26")
      case .onboardingEmpty, .onboardingPrefilled:
        DeveloperOnboardingScenarioView(prefilled: scenario == .onboardingPrefilled)
      case .localFlowFresh:
        DeveloperLocalFlowHost(seed: .fresh)
      case .localFlowOnboarding:
        DeveloperLocalFlowHost(seed: .onboarding)
      case .localFlowPaywall:
        DeveloperLocalFlowHost(seed: .paywall)
      case .localFlowPairing:
        DeveloperLocalFlowHost(seed: .pairing)
      case .localFlowPaired:
        DeveloperLocalFlowHost(seed: .paired)
      case .pairingInviteReady, .pairingJoin, .pairingInviteExpired, .pairingSafetyWarning,
        .pairingInviteError, .pairingCelebration, .pairingCelebrationSettled:
        DeveloperPairingScenarioView(scenario: scenario)
      case .paywallTrial, .paywallStandard, .paywallPaired, .paywallLoading:
        DeveloperPaywallScenarioView(scenario: scenario)
      case .pairedHome, .questions, .questionsPartial, .questionsRevealed, .questionsEmpty,
        .questionsLoading, .questionsError, .memoriesEmpty, .memoriesPopulated,
        .questionsOfflineQueued, .questionAnswerFlow:
        DeveloperPairedScenarioHost(scenario: scenario)
      case .questionsHistory:
        DeveloperQuestionsHistoryScenarioView()
      case .streakHealthy, .streakBroken, .streakRestored:
        DeveloperStreakScenarioView(scenario: scenario)
      case .memoryEditor:
        DeveloperMemoryEditorScenarioView()
      case .memoryDetail:
        DeveloperMemoryDetailScenarioView()
      case .countdownMissing, .countdownUpcoming, .countdownToday, .locationNotSharing,
        .locationCurrentMissing, .locationLive, .locationStale:
        DeveloperRelationshipScenarioView(scenario: scenario)
      case .gamesSetup, .gamesPartnerPicked, .gamesHubYourTurn, .gamesHubWaiting,
        .gamesHubPartnerHere:
        DeveloperPairedScenarioHost(scenario: scenario)
      case .drawChooseWord, .drawWaitingForWord, .drawDrawing, .drawSavedOffline,
        .drawWaitingForGuess, .drawWaitingForDrawing, .drawWatchingLive, .drawGuessingReplay,
        .drawGuessingLongWord, .drawRevealSolved, .drawRevealBonuses, .drawRevealMissed, .drawRevealAsDrawer,
        .drawRevealPartnerDrawing, .drawRevealLoading:
        DeveloperGamesScenarioView(scenario: scenario)
      case .drawHistory, .drawHistoryEmpty:
        DeveloperGamesHistoryScenarioView(scenario: scenario)
      case .storyChainChoose, .storyChainChooseOffline, .storyChainWriting, .storyChainWritingLast,
        .storyChainWaitingLive, .storyChainWaitingAway, .storyChainSavedOffline, .storyChainNaming,
        .storyChainWaitingName, .storyChainFinished, .storyChainWaitingOpening:
        DeveloperStoryChainScenarioView(scenario: scenario)
      case .storyChainHistory, .storyChainHistoryEmpty:
        DeveloperStoryChainHistoryScenarioView(scenario: scenario)
      case .mindMeldFirstRound, .mindMeldWrite, .mindMeldWriteTyping, .mindMeldWaiting,
        .mindMeldWaitingOffline, .mindMeldRevealMiss, .mindMeldRevealNear, .mindMeldRevealMeld,
        .mindMeldRevealRecord, .mindMeldRevealGotAway, .mindMeldOver, .mindMeldPartnerRestarted,
        .mindMeldHistory, .mindMeldHistoryEmpty:
        DeveloperMindMeldScenarioView(scenario: scenario)
      case .widgetDrawing, .widgetHistoryEmpty, .widgetHistoryPopulated:
        DeveloperWidgetScenarioView(scenario: scenario)
      case .notificationPrimer, .settings, .settingsNotificationsDenied, .privacySafety,
        .reportAndLeave:
        DeveloperSettingsScenarioView(scenario: scenario)
      case .deepLinkDailyToday:
        DeveloperPairedScenarioHost(scenario: .questionAnswerFlow)
      case .deepLinkDailyReveal:
        DeveloperPairedScenarioHost(scenario: .questionsRevealed)
      case .deepLinkWidget:
        DeveloperWidgetScenarioView(scenario: .widgetDrawing)
      case .deepLinkStreak:
        DeveloperStreakScenarioView(scenario: .streakHealthy)
      case .deepLinkSubscription:
        DeveloperSettingsScenarioView(scenario: .settings)
      }
    }

    private func welcome(pendingInviteCode: String?) -> some View {
      WelcomeView(
        isWorking: false,
        signingInWith: nil,
        pendingInviteCode: pendingInviteCode,
        onAppleSignIn: {},
        onGoogleSignIn: {},
        onSubmitInviteCode: { _ in }
      )
    }
  }
#endif
