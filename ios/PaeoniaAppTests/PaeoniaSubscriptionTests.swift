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
}
