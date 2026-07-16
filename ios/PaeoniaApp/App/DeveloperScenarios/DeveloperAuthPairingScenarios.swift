#if DEBUG
  import SwiftUI

  struct DeveloperOnboardingScenarioView: View {
    let prefilled: Bool

    var body: some View {
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
      .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
      .padding(.vertical, PaeoniaSpacing.space16)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(.paeoniaBackgroundPrimary)
    }
  }

  @MainActor
  struct DeveloperPairingScenarioView: View {
    let scenario: DeveloperScenario

    var body: some View {
      switch scenario {
      case .pairingJoin:
        WelcomeInviteCodeSheet(onSubmit: { _ in })
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(.paeoniaBackgroundPrimary)
      case .pairingSafetyWarning:
        DeveloperPairingSafetyWarningView()
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
        PairingInviteView(
          session: DeveloperScenarioFixture.completeSession,
          viewModel: inviteViewModel,
          onRefreshAccess: {}
        )
        .padding(.horizontal, PaeoniaSpacing.screenHorizontalPadding)
        .padding(.vertical, PaeoniaSpacing.space16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.paeoniaBackgroundPrimary)
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

  private struct DeveloperPairingSafetyWarningView: View {
    @State private var isPresented = true

    private let preview = PairingInvitePreview(
      inviteID: UUID(),
      inviterUserID: DeveloperScenarioFixture.partnerUserID,
      inviterDisplayName: "Robin",
      expiresAt: DeveloperScenarioFixture.now.addingTimeInterval(86_400),
      hasSafetyWarning: true
    )

    var body: some View {
      Color.paeoniaBackgroundPrimary
        .ignoresSafeArea()
        .alert(
          Text(PaywallInviteConfirmation.title(for: preview)),
          isPresented: $isPresented
        ) {
          Button {
            isPresented = true
          } label: {
            Text(.paywallInviteConfirmAction)
          }
          Button(role: .cancel) {
            isPresented = true
          } label: {
            Text(.paywallInviteConfirmCancel)
          }
        } message: {
          Text(PaywallInviteConfirmation.message(for: preview))
        }
    }
  }

  struct DeveloperPaywallScenarioView: View {
    let scenario: DeveloperScenario

    private var hasTrial: Bool { scenario == .paywallTrial }
    private var audience: PaywallAudience {
      scenario == .paywallPaired ? .paired(partnerName: "Robin") : .unpaired
    }
    private var trial: PaeoniaFreeTrial? {
      hasTrial ? PaeoniaFreeTrial(value: 14, unit: .day) : nil
    }
    var body: some View {
      PaywallView(
        session: DeveloperScenarioFixture.completeSession,
        audience: audience,
        onPurchaseConfirmed: {},
        onInviteAccepted: {},
        onSignOut: {},
        onUnpaired: {},
        onDeleteAccount: {},
        viewModel: viewModel,
        presentationOverride: presentationOverride
      )
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
            isLoading: false
          )
        },
        priceLine: priceLine(for:),
        purchaseIsEnabled: true,
        onPurchase: {}
      )
    }

    private func priceLine(for billingPeriod: PaeoniaBillingPeriod) -> String {
      let amount = billingPeriod == .monthly ? 49 : 399
      let price = amount.formatted(.currency(code: "NOK").precision(.fractionLength(0)))
      let period = String(
        localized: billingPeriod == .monthly
          ? .paywallPeriodMonthlyCompact
          : .paywallPeriodYearlyCompact
      )
      guard let trial else { return "\(price)\(period)" }
      let free = String(localized: .paywallTrialFreeWord)
      let then = String(localized: .paywallTrialThen).lowercased(with: .current)
      return "\(trial.localizedDurationText) \(free), \(then) \(price)\(period)"
    }
  }
#endif
