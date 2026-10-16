import Foundation
import Testing
@testable import PaeoniaApp

@Suite("Paeonia subscription products")
struct PaeoniaSubscriptionTests {
    @Test func productIdentifiersMatchChosenStoreKitIDs() {
        #expect(PaeoniaSubscriptionProductID.coupleMonthly.rawValue == "no.paeonia.couple")
        #expect(PaeoniaSubscriptionProductID.coupleYearly.rawValue == "no.paeonia.couple.year")
        #expect(PaeoniaConsumableProductID.streakRestore.rawValue == "no.paeonia.streak.restore")
    }

    @Test func billingPeriodsMatchProductIdentifiers() {
        #expect(PaeoniaSubscriptionProductID.coupleMonthly.billingPeriod == .monthly)
        #expect(PaeoniaSubscriptionProductID.coupleYearly.billingPeriod == .yearly)
    }

    @Test func freeTrialClampsEmptyDurationToOneUnit() {
        #expect(PaeoniaFreeTrial(value: 0, unit: .day).value == 1)
    }

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
    private let nok = Decimal.FormatStyle.Currency(code: "NOK", locale: Locale(identifier: "nb_NO"))

    @Test func trialPresentationUsesTrialCTAAndTrialDisclosure() {
        let presentation = PaywallPresentation(
            billingPeriod: .yearly,
            product: nil,
            freeTrial: PaeoniaFreeTrial(value: 14, unit: .day),
            isPurchasing: false,
            isLoading: false,
            price: PaywallPrice(amount: 399, format: nok)
        )

        #expect(presentation.hasFreeTrial)
        #expect(
            String(localized: presentation.primaryButtonTitle)
                == String(localized: .paywallCtaFreeTrial)
        )
        let renewal = "\(PaywallPrice(amount: 399, format: nok).text) \(String(localized: .paywallPeriodYearly))"
        #expect(
            presentation.billingDisclosure
                == String(localized: .paywallDisclosureTrial(
                    PaeoniaFreeTrial(value: 14, unit: .day).localizedDurationText,
                    renewal
                ))
        )
    }

    @Test func nonTrialPresentationUsesSubscribeCTA() {
        let presentation = PaywallPresentation(
            billingPeriod: .monthly,
            product: nil,
            freeTrial: nil,
            isPurchasing: false,
            isLoading: false
        )

        #expect(!presentation.hasFreeTrial)
        #expect(
            String(localized: presentation.primaryButtonTitle)
                == String(localized: .paywallCtaSubscribe)
        )
        // No price yet, so no billing terms to show.
        #expect(presentation.billingDisclosure == nil)
    }

    @Test func wholePricesDropTheDecimals() throws {
        let halfPrice = try #require(Decimal(string: "49.5"))

        #expect(PaywallPrice(amount: 49, format: nok).text.contains("49"))
        #expect(!PaywallPrice(amount: 49, format: nok).text.contains(","))
        #expect(PaywallPrice(amount: halfPrice, format: nok).text.contains("49,50"))
    }

    @Test func yearlySavingsRoundDownAndSkipSmallSavings() {
        // 12 x 49 = 588, and 399 is 32.1 % less.
        #expect(PaywallPlanOption.savingsPercent(monthly: 49, yearly: 399) == 32)
        // 12 x 10 = 120, and 115 is only 4.2 % less.
        #expect(PaywallPlanOption.savingsPercent(monthly: 10, yearly: 115) == nil)
        #expect(PaywallPlanOption.savingsPercent(monthly: 49, yearly: 600) == nil)
        #expect(PaywallPlanOption.savingsPercent(monthly: nil, yearly: 399) == nil)
        #expect(PaywallPlanOption.savingsPercent(monthly: 0, yearly: 399) == nil)
    }

    @Test func plansListTheYearFirstWithItsMonthlyCost() throws {
        func presentation(_ period: PaeoniaBillingPeriod, _ amount: Decimal) -> PaywallPresentation {
            PaywallPresentation(
                billingPeriod: period,
                product: nil,
                freeTrial: nil,
                isPurchasing: false,
                isLoading: false,
                price: PaywallPrice(amount: amount, format: nok)
            )
        }

        let plans = PaywallPlanOption.options(
            monthly: presentation(.monthly, 49),
            yearly: presentation(.yearly, 399)
        )

        #expect(plans.map(\.period) == [.yearly, .monthly])
        let yearly = try #require(plans.first)
        #expect(yearly.monthlyEquivalent?.amount == Decimal(string: "33.25"))
        #expect(yearly.savingsPercent == 32)
        #expect(plans.last?.monthlyEquivalent == nil)
        #expect(plans.last?.savingsPercent == nil)
    }
}
