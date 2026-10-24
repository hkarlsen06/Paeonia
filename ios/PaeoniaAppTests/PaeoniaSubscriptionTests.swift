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

    @Test func trialReminderNamesTheEndAndReminderDaysOnlyForTrialsCountedInDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Oslo"))
        // 24 October 2026, 12:00 in Oslo. The trial crosses the end of summer time.
        let start = try #require(calendar.date(from: DateComponents(year: 2_026, month: 10, day: 24, hour: 12)))
        let noon = { (month: Int, day: Int) in
            try #require(calendar.date(from: DateComponents(year: 2_026, month: month, day: day, hour: 12)))
        }

        #expect(presentation(trial: PaeoniaFreeTrial(value: 14, unit: .day))
            .trialReminder(startingAt: start, calendar: calendar)
            == .dated(trialEnd: try noon(11, 7), reminder: try noon(11, 5)))
        #expect(presentation(trial: PaeoniaFreeTrial(value: 1, unit: .week))
            .trialReminder(startingAt: start, calendar: calendar)
            == .dated(trialEnd: try noon(10, 31), reminder: try noon(10, 29)))
        #expect(presentation(trial: PaeoniaFreeTrial(value: 1, unit: .month))
            .trialReminder(startingAt: start, calendar: calendar) == .undated)
        #expect(presentation(trial: PaeoniaFreeTrial(value: 2, unit: .day))
            .trialReminder(startingAt: start, calendar: calendar) == .undated)
        #expect(presentation(trial: nil).trialReminder(startingAt: start, calendar: calendar) == nil)
    }

    private func presentation(trial: PaeoniaFreeTrial?) -> PaywallPresentation {
        PaywallPresentation(
            billingPeriod: .monthly,
            product: nil,
            freeTrial: trial,
            isPurchasing: false,
            isLoading: false
        )
    }
}
