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
}
