#if DEBUG
  import SwiftUI

  struct DeveloperOnboardingScenarioView: View {
    let prefilled: Bool

    var body: some View {
      PaeoniaScreenFrame {
        onboarding
      }
    }

    private var onboarding: some View {
      AuthOnboardingView(
        session: AuthSession(
          id: DeveloperScenarioFixture.currentUserID.uuidString,
          provider: .development,
          displayName: prefilled ? "Alex" : nil,
          timeZoneID: nil,
          profilePhotoAssetID: nil,
          profileStatus: .needsOnboarding
        ),
        isWorking: false,
        onCompleteOnboarding: { _, _ in },
        onSignOut: {},
        onDeleteAccount: {}
      )
    }
  }

  /// The single-purpose screens after sign-in, in the root's frame.
  struct DeveloperSignedInNoticeScenarioView: View {
    let scenario: DeveloperScenario

    var body: some View {
      PaeoniaScreenFrame {
        switch scenario {
        case .onboardingUsage:
          UsageSharingQuestionView { _ in }
        case .relationshipEnded:
          RelationshipEndedNoticeView(isWorking: false, onAcknowledge: {})
        case .accountClosed:
          AccountClosedView(isWorking: false, onSignOut: {}, onDeleteAccount: {})
        default:
          AuthDeletingAccountView()
        }
      }
    }
  }

  @MainActor
  struct DeveloperPairingScenarioView: View {
    let scenario: DeveloperScenario

    var body: some View {
      switch scenario {
      case .pairingJoin:
        PairingCodeEntrySheet(
          title: .welcomeInviteCodeTitle,
          message: .welcomeInviteCodeSubtitle,
          submitTitle: .welcomeInviteCodeContinue,
          onSubmit: { _ in true }
        )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.paeoniaBackgroundPrimary)
      case .pairingJoinPartner, .pairingSafetyWarning:
        DeveloperJoinScenarioView(hasSafetyWarning: scenario == .pairingSafetyWarning)
      case .pairingCelebration, .pairingCelebrationSettled:
        PairingCelebrationView(
          currentDisplayName: "Alex",
          partnerDisplayName: "Robin",
          playsIntro: scenario == .pairingCelebration
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
      default:
        PaeoniaScreenFrame {
          PairingInviteView(
            session: DeveloperScenarioFixture.completeSession,
            viewModel: inviteViewModel,
            firstDayModel: DeveloperInviterFixture.firstDayModel(answered: false),
            showsManageSubscription: true,
            onSubmitJoinCode: { _ in true },
            onRefreshAccess: {}
          )
        }
      }
    }

    private var inviteViewModel: PairingInviteViewModel {
      let mode: DeveloperScenarioPairingService.Mode =
        switch scenario {
        case .pairingInviteReady: .ready
        case .pairingInviteExpired: .expired
        default: .failing
        }
      return PairingInviteViewModel(
        userID: DeveloperScenarioFixture.currentUserID.uuidString,
        pairingService: DeveloperScenarioPairingService(mode: mode),
        operationProvider: DeveloperScenarioOperationProvider(),
        inviteStore: DeveloperScenarioInviteStore(invite: cachedInvite),
        now: { DeveloperScenarioFixture.now }
      )
    }

    private var cachedInvite: PairingInvite? {
      guard scenario == .pairingInviteExpired,
        let joinURL = URL(string: "https://paeonia.no/join/OLD126")
      else { return nil }
      return PairingInvite(
        id: UUID(),
        code: "OLD126",
        joinURL: joinURL,
        expiresAt: DeveloperScenarioFixture.now.addingTimeInterval(-60)
      )
    }
  }

  /// The join screen in place of the paywall, with a local partner code.
  private struct DeveloperJoinScenarioView: View {
    let hasSafetyWarning: Bool
    @State private var viewModel: PairingJoinViewModel

    init(hasSafetyWarning: Bool) {
      self.hasSafetyWarning = hasSafetyWarning
      _viewModel = State(
        initialValue: PairingJoinViewModel(
          pairingService: DeveloperScenarioPairingService(mode: hasSafetyWarning ? .safetyWarning : .ready),
          operationProvider: DeveloperScenarioOperationProvider()
        )
      )
    }

    var body: some View {
      PaeoniaScreenFrame {
        PairingJoinView(
          viewModel: viewModel,
          code: "LOVE26",
          currentUserID: DeveloperScenarioFixture.currentUserID.uuidString,
          replacesPaywall: true,
          onSubmitCode: { _ in true },
          onAccepted: {},
          onForgetCode: {},
          onSignOut: {},
          onDeleteAccount: {}
        )
      }
    }
  }

  struct DeveloperPaywallScenarioView: View {
    let scenario: DeveloperScenario

    private var hasTrial: Bool { scenario == .paywallTrial || scenario == .paywallDrawing }
    private var audience: PaywallAudience {
      switch scenario {
      case .paywallPaired: .paired(partnerName: "Robin")
      case .paywallDrawing: .unpairedWithDrawing
      default: .unpaired
      }
    }
    private var trial: PaeoniaFreeTrial? {
      hasTrial ? PaeoniaFreeTrial(value: 14, unit: .day) : nil
    }
    var body: some View {
      PaeoniaScreenFrame {
        PaywallView(
          session: DeveloperScenarioFixture.completeSession,
          audience: audience,
          onPurchaseConfirmed: {},
          onSubmitInviteCode: { _ in true },
          onSignOut: {},
          onUnpaired: {},
          onDeleteAccount: {},
          viewModel: viewModel,
          presentationOverride: presentationOverride
        )
      }
    }

    private var viewModel: PaywallViewModel {
      PaywallViewModel(
        userID: DeveloperScenarioFixture.currentUserID.uuidString,
        storeKitService: DeveloperScenarioStoreKitService(
          blocksProductLoad: scenario == .paywallLoading
        ),
        pairingService: DeveloperScenarioPairingService(mode: .ready),
        operationProvider: DeveloperScenarioOperationProvider()
      )
    }

    private var presentationOverride: PaywallPresentationOverride? {
      guard scenario != .paywallLoading else { return nil }
      return PaywallPresentationOverride(
        presentation: { billingPeriod in
          PaywallPresentation(
            billingPeriod: billingPeriod,
            product: nil,
            freeTrial: trial,
            isPurchasing: false,
            isLoading: false,
            price: PaywallPrice(
              amount: billingPeriod == .monthly ? 49 : 399,
              format: .currency(code: "NOK")
            )
          )
        },
        purchaseIsEnabled: true,
        onPurchase: { true }
      )
    }
  }
#endif
