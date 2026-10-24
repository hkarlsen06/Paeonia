import Foundation
import Testing
@testable import PaeoniaApp

struct AccessNoticeTests {
    private let me = UUID()
    private let partner = UUID()
    private let endsAt = Date(timeIntervalSince1970: 2_000_000_000)
    private let day: TimeInterval = 86_400

    @Test func aFailedPaymentShowsOnlyForThePayer() {
        let payer = AccessNotice(
            user: own(paying: true, status: "grace"),
            couple: couple(payer: me, status: "grace", accessEndsAt: nil),
            now: endsAt - 10 * day
        )
        // The server shows the partner a payer's grace period as plain `active`.
        let partnerView = AccessNotice(
            user: own(paying: false, status: nil),
            couple: couple(payer: partner, status: "active", accessEndsAt: nil),
            now: endsAt - 10 * day
        )
        let recovered = AccessNotice(
            user: own(paying: true, status: "active"),
            couple: couple(payer: me, status: "active", accessEndsAt: nil),
            now: endsAt - 10 * day
        )

        // Both partners pay and both payments failed: each one hears of their own.
        let bothFailed = AccessNotice(
            user: own(paying: true, status: "grace"),
            couple: couple(payer: partner, status: "grace", accessEndsAt: nil),
            now: endsAt - 10 * day
        )

        #expect(payer == .paymentProblem)
        #expect(bothFailed == .paymentProblem)
        #expect(partnerView == nil)
        #expect(recovered == nil)
    }

    @Test func endingAccessShowsBothPartnersFromFiveDaysBefore() {
        let payerCouple = couple(payer: me, status: "active", accessEndsAt: endsAt)
        let partnerCouple = couple(payer: partner, status: "active", accessEndsAt: endsAt)

        let payer = own(paying: true, status: "active")
        #expect(AccessNotice(user: payer, couple: payerCouple, now: endsAt - 6 * day) == nil)
        #expect(
            AccessNotice(user: own(paying: true, status: "active"), couple: payerCouple, now: endsAt - 5 * day)
                == .ending(endsAt: endsAt, canRenew: true)
        )
        #expect(
            AccessNotice(user: own(paying: false, status: nil), couple: partnerCouple, now: endsAt - day)
                == .ending(endsAt: endsAt, canRenew: false)
        )
        #expect(AccessNotice(user: own(paying: false, status: nil), couple: partnerCouple, now: endsAt) == nil)
    }

    @Test func renewalTurnedBackOnClearsTheEndingNotice() {
        let renewing = couple(payer: me, status: "active", accessEndsAt: nil)

        #expect(AccessNotice(user: own(paying: true, status: "active"), couple: renewing, now: endsAt - day) == nil)
    }

    private func own(paying: Bool, status: String?) -> RemoteUserEntitlement {
        RemoteUserEntitlement(
            userID: me,
            isEntitled: paying,
            source: paying ? "storekit" : nil,
            status: status,
            productID: nil,
            billingPeriod: paying ? "monthly" : nil,
            currentPeriodEnd: paying ? endsAt : nil,
            updatedAt: nil
        )
    }

    private func couple(payer: UUID, status: String, accessEndsAt: Date?) -> RemoteCoupleEntitlement {
        RemoteCoupleEntitlement(
            coupleID: UUID(),
            isEntitled: true,
            coveringUserID: payer,
            source: "storekit",
            status: status,
            productID: nil,
            billingPeriod: "monthly",
            currentPeriodEnd: endsAt,
            updatedAt: nil,
            accessEndsAt: accessEndsAt
        )
    }
}
