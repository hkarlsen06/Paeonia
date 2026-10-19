import Foundation
import Testing
@testable import PaeoniaApp

@Suite("Paeonia subscription products")
struct PaeoniaSubscriptionTests {
    @Test func configuredTrialIsShownOnlyWhenStoreKitSaysTheAccountIsEligible() {
        let configuredTrial = PaeoniaFreeTrial(value: 14, unit: .day)

        #expect(
            PaeoniaStoreKitOfferEligibility.freeTrial(
                configuredOffer: configuredTrial,
                isEligible: false
            ) == nil
        )
        #expect(
            PaeoniaStoreKitOfferEligibility.freeTrial(
                configuredOffer: configuredTrial,
                isEligible: true
            ) == configuredTrial
        )
    }
}

@MainActor
@Suite("Paywall presentation")
struct PaywallPresentationTests {
    @Test func yearlySavingsRoundDownAndSkipSmallSavings() {
        // 12 x 49 = 588, and 399 is 32.1 % less.
        #expect(PaywallPlanOption.savingsPercent(monthly: 49, yearly: 399) == 32)
        // 12 x 10 = 120, and 115 is only 4.2 % less.
        #expect(PaywallPlanOption.savingsPercent(monthly: 10, yearly: 115) == nil)
        #expect(PaywallPlanOption.savingsPercent(monthly: 49, yearly: 600) == nil)
        #expect(PaywallPlanOption.savingsPercent(monthly: nil, yearly: 399) == nil)
        #expect(PaywallPlanOption.savingsPercent(monthly: 0, yearly: 399) == nil)
    }
}
