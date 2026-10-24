#if DEBUG
  import Foundation

  /// Home with the notice before access ends (`AccessNotice`), for the person who pays and for the
  /// partner. Each one builds what the server sends that person and runs the app's own rule on it.
  nonisolated extension DeveloperScenario {
    static let accessNotices: [DeveloperScenario] = [
      homePaymentProblemPayer, homePaymentProblemPartner, homeAccessEndingPayer, homeAccessEndingPartner,
    ]

    static let homePaymentProblemPayer = DeveloperScenario(
      "home-payment-problem-payer", "Home · payment failed · payer",
      "Apple could not take the payment; the payer sees the notice", .paywall
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let homePaymentProblemPartner = DeveloperScenario(
      "home-payment-problem-partner", "Home · payment failed · partner",
      "Same couple from the partner's side; no notice", .paywall
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let homeAccessEndingPayer = DeveloperScenario(
      "home-access-ending-payer", "Home · access ending · payer",
      "Renewal is off and access ends in four days; the payer can turn it back on", .paywall
    ) { DeveloperPairedScenarioHost(scenario: $0) }
    static let homeAccessEndingPartner = DeveloperScenario(
      "home-access-ending-partner", "Home · access ending · partner",
      "Renewal is off and access ends in four days; the partner sees one line", .paywall
    ) { DeveloperPairedScenarioHost(scenario: $0) }

    /// The notice Home shows in this scenario, from the entitlements the server would send.
    var accessNotice: AccessNotice? {
      let now = Date.now
      let periodEnd = now.addingTimeInterval(4 * 86_400)
      let me = DeveloperScenarioFixture.currentUserID
      let partner = DeveloperScenarioFixture.partnerUserID
      func entitlements(
        payer: UUID, status: String, accessEndsAt: Date?
      ) -> (RemoteUserEntitlement, RemoteCoupleEntitlement) {
        let paying = payer == me
        let user = RemoteUserEntitlement(
          userID: me, isEntitled: paying, source: paying ? "storekit" : nil, status: paying ? status : nil,
          productID: nil, billingPeriod: paying ? "yearly" : nil, currentPeriodEnd: paying ? periodEnd : nil,
          updatedAt: now
        )
        // The server shows the partner a payer's grace period as plain `active`.
        let couple = RemoteCoupleEntitlement(
          coupleID: DeveloperScenarioFixture.coupleID, isEntitled: true, coveringUserID: payer, source: "storekit",
          status: paying || status != "grace" ? status : "active", productID: nil, billingPeriod: "yearly",
          currentPeriodEnd: periodEnd, updatedAt: now, accessEndsAt: accessEndsAt
        )
        return (user, couple)
      }
      let pair: (RemoteUserEntitlement, RemoteCoupleEntitlement)
      switch self {
      case .homePaymentProblemPayer: pair = entitlements(payer: me, status: "grace", accessEndsAt: nil)
      case .homePaymentProblemPartner: pair = entitlements(payer: partner, status: "grace", accessEndsAt: nil)
      case .homeAccessEndingPayer: pair = entitlements(payer: me, status: "active", accessEndsAt: periodEnd)
      case .homeAccessEndingPartner: pair = entitlements(payer: partner, status: "active", accessEndsAt: periodEnd)
      default: return nil
      }
      return AccessNotice(user: pair.0, couple: pair.1, now: now)
    }
  }
#endif
