import Foundation
import Testing
@testable import PaeoniaApp

struct SubscriptionDetailsTests {
    private let me = UUID()
    private let partner = UUID()
    private let periodEnd = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func coupleSubscriptionPaidByMeShowsPlanDateAndPayer() {
        let details = SubscriptionDetails(snapshot: snapshot(
            own: own(isEntitled: true, source: "storekit", status: "active", billingPeriod: "yearly"),
            couple: couple(coveringUserID: me, source: "storekit", status: "active", billingPeriod: "yearly")
        ))

        #expect(details.status == .active)
        #expect(details.billingPeriod == .yearly)
        #expect(details.periodEnd == periodEnd)
        #expect(details.payer == .you)
    }

    @Test func coupleSubscriptionPaidByPartnerNamesThePartner() {
        let details = SubscriptionDetails(snapshot: snapshot(
            own: own(isEntitled: false, source: nil, status: nil, billingPeriod: nil),
            couple: couple(coveringUserID: partner, source: "storekit", status: "grace", billingPeriod: "monthly"),
            partnerName: "Sam"
        ))

        #expect(details.status == .paymentProblem)
        #expect(details.billingPeriod == .monthly)
        #expect(details.payer == .partner(name: "Sam"))
    }

    @Test func withoutCoupleAccessTheOwnRecordExplainsWhy() {
        let refunded = SubscriptionDetails(snapshot: snapshot(
            own: own(isEntitled: false, source: "storekit", status: "refunded", billingPeriod: "monthly"),
            couple: nil
        ))
        let retrying = SubscriptionDetails(snapshot: snapshot(
            own: own(isEntitled: false, source: "storekit", status: "billing_retry", billingPeriod: "monthly"),
            couple: nil
        ))
        let lapsed = SubscriptionDetails(snapshot: snapshot(
            own: own(isEntitled: false, source: "storekit", status: "active", billingPeriod: "monthly"),
            couple: nil
        ))

        #expect(refunded.status == .refunded)
        #expect(refunded.payer == nil)
        #expect(retrying.status == .paymentProblem)
        #expect(lapsed.status == .ended)
    }

    @Test func grantsShowAsLifetimeOrFreeAccess() {
        let lifetime = SubscriptionDetails(snapshot: snapshot(
            own: own(isEntitled: true, source: "lifetime_grant", status: "lifetime", billingPeriod: nil),
            couple: nil
        ))
        let review = SubscriptionDetails(snapshot: snapshot(
            own: own(isEntitled: true, source: "review_grant", status: "active", billingPeriod: nil),
            couple: nil
        ))

        #expect(lifetime.status == .lifetime)
        #expect(lifetime.periodEnd == nil)
        #expect(review.status == .freeAccess)
    }

    @Test func nothingOnRecordShowsNoSubscription() {
        let details = SubscriptionDetails(snapshot: snapshot(
            own: own(isEntitled: false, source: nil, status: nil, billingPeriod: nil),
            couple: nil
        ))

        #expect(details.status == .none)
        #expect(details.billingPeriod == nil)
        #expect(details.periodEnd == nil)
    }

    private func snapshot(
        own: RemoteUserEntitlement,
        couple: RemoteCoupleEntitlement?,
        partnerName: String? = nil
    ) -> RemoteAccessSnapshot {
        RemoteAccessSnapshot(
            userEntitlement: own,
            coupleEntitlement: couple,
            relationshipState: RemoteRelationshipState(
                coupleID: UUID(),
                pairID: UUID(),
                relationshipStatus: .active,
                memberStatus: .active,
                acceptedInvite: false,
                partnerUserID: partner,
                partnerAccountName: partnerName,
                partnerProfilePhotoAssetID: nil,
                startedOn: nil,
                endedAt: nil,
                deleteAfter: nil,
                endedNoticeSeenAt: nil
            )
        )
    }

    private func own(
        isEntitled: Bool,
        source: String?,
        status: String?,
        billingPeriod: String?
    ) -> RemoteUserEntitlement {
        RemoteUserEntitlement(
            userID: me,
            isEntitled: isEntitled,
            source: source,
            status: status,
            productID: nil,
            billingPeriod: billingPeriod,
            currentPeriodEnd: status == nil ? nil : periodEnd,
            updatedAt: nil
        )
    }

    private func couple(
        coveringUserID: UUID,
        source: String,
        status: String,
        billingPeriod: String
    ) -> RemoteCoupleEntitlement {
        RemoteCoupleEntitlement(
            coupleID: UUID(),
            isEntitled: true,
            coveringUserID: coveringUserID,
            source: source,
            status: status,
            productID: nil,
            billingPeriod: billingPeriod,
            currentPeriodEnd: periodEnd,
            updatedAt: nil
        )
    }
}
