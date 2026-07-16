#if DEBUG
  import SwiftUI

  struct DeveloperScenarioMenu: View {
    let runProductionApp: () -> Void

    var body: some View {
      NavigationStack {
        List {
          ForEach(DeveloperScenario.Category.allCases) { category in
            Section(category.rawValue) {
              ForEach(scenarios(in: category)) { scenario in
                NavigationLink {
                  DeveloperScenarioNavigationDestination(scenario: scenario)
                } label: {
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
      .preferredColorScheme(.dark)
      .accessibilityIdentifier("developer.scenario.menu")
    }

    private func scenarios(in category: DeveloperScenario.Category) -> [DeveloperScenario] {
      DeveloperScenario.allCases.filter { $0.category == category }
    }
  }

  private struct DeveloperScenarioNavigationDestination: View {
    let scenario: DeveloperScenario
    @Environment(\.dismiss) private var dismiss

    var body: some View {
      DeveloperScenarioHost(scenario: scenario) {
        dismiss()
      }
      .toolbar(.hidden, for: .navigationBar)
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
        .accessibilityIdentifier("developer.scenario.host.\(scenario.rawValue)")
        .overlay(alignment: .topTrailing) {
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
    }

    @ViewBuilder
    private var scenarioContent: some View {
      switch scenario {
      case .launchLoading:
        AuthLaunchingView()
      case .welcome:
        WelcomeView(
          isWorking: false,
          pendingInviteCode: nil,
          onAppleSignIn: {},
          onGoogleSignIn: {},
          onSubmitInviteCode: { _ in }
        )
      case .signIn:
        SignInView(
          isWorking: false,
          pendingInviteCode: nil,
          onAppleSignIn: {},
          onGoogleSignIn: {},
          onHaveInviteCode: nil
        )
      case .signInInvite:
        SignInView(
          isWorking: false,
          pendingInviteCode: "LOVE26",
          onAppleSignIn: {},
          onGoogleSignIn: {},
          onHaveInviteCode: {}
        )
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
  }
#endif
