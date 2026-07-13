import Foundation
import Testing
@testable import PaeoniaApp

@Suite("Paeonia subscription products")
struct PaeoniaSubscriptionTests {
    @Test func productIdentifiersMatchChosenStoreKitIDs() {
        #expect(PaeoniaSubscriptionProductID.coupleMonthly.rawValue == "no.paeonia.couple")
        #expect(PaeoniaSubscriptionProductID.coupleYearly.rawValue == "no.paeonia.couple.year")
    }

    @Test func billingPeriodsMatchProductIdentifiers() {
        #expect(PaeoniaSubscriptionProductID.coupleMonthly.billingPeriod == .monthly)
        #expect(PaeoniaSubscriptionProductID.coupleYearly.billingPeriod == .yearly)
    }

    @Test func freeTrialApproximatesDurationInDays() {
        #expect(PaeoniaFreeTrial(value: 14, unit: .day).approximateDayCount == 14)
        #expect(PaeoniaFreeTrial(value: 2, unit: .week).approximateDayCount == 14)
        #expect(PaeoniaFreeTrial(value: 1, unit: .month).approximateDayCount == 30)
        #expect(PaeoniaFreeTrial(value: 1, unit: .year).approximateDayCount == 365)
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

@Suite("Paywall presentation")
struct PaywallPresentationTests {
    @Test func trialPresentationUsesTrialCTAAndSharedSpaceTimeline() throws {
        let presentation = PaywallPresentation(
            billingPeriod: .yearly,
            product: nil,
            freeTrial: PaeoniaFreeTrial(value: 14, unit: .day),
            isPurchasing: false,
            isLoading: false
        )
        let timeline = presentation.timelineItems
        let firstTimelineItem = try #require(timeline.first)
        let reminderItem = try #require(timeline.dropFirst().first)
        let lastTimelineItem = try #require(timeline.last)

        #expect(presentation.hasFreeTrial)
        #expect(
            String(localized: presentation.primaryButtonTitle)
                == String(localized: .paywallCtaFreeTrial)
        )
        #expect(firstTimelineItem.message == String(localized: .paywallTimelineTodayBody))
        #expect(reminderItem.title == "\(String(localized: .paywallTimelineDayPrefix)) 12")
        #expect(reminderItem.message == String(localized: .paywallTimelineReminderBody))
        #expect(lastTimelineItem.message == String(localized: .paywallTimelineChargeBody))
    }

    @Test func nonTrialPresentationKeepsSubscriptionAndRenewalCopy() throws {
        let presentation = PaywallPresentation(
            billingPeriod: .monthly,
            product: nil,
            freeTrial: nil,
            isPurchasing: false,
            isLoading: false
        )
        let timeline = presentation.timelineItems
        let lastTimelineItem = try #require(timeline.last)

        #expect(!presentation.hasFreeTrial)
        #expect(
            String(localized: presentation.primaryButtonTitle)
                == String(localized: .paywallCtaSubscribe)
        )
        #expect(lastTimelineItem.message == String(localized: .paywallTimelineRenewalMonthlyBody))
    }
}
