import Foundation
import Testing
@testable import PaeoniaApp

struct AccessRouteResolverTests {
    private let resolver = AccessRouteResolver()

    @Test func noRelationshipWithoutEntitlementStaysLimitedAndAllowsInviteAcceptance() {
        let route = resolver.route(for: .test(userEntitlement: .notEntitled()))

        #expect(route == .limitedAuthenticated)
        #expect(route.appState == .limitedAuthenticated)
        #expect(route.allowsInviteAcceptance)
    }

    @Test func directEntitlementWithoutRelationshipRoutesToUnpaired() {
        let route = resolver.route(for: .test(userEntitlement: .entitled()))

        #expect(route == .unpaired)
        #expect(route.appState == .unpaired)
        #expect(route.allowsInviteAcceptance)
    }

    @Test func pendingInviteRoutesToInvitePending() {
        let route = resolver.route(
            for: .test(
                userEntitlement: .entitled(),
                hasPendingInvite: true
            )
        )

        #expect(route == .invitePending)
        #expect(route.appState == .invitePending)
        #expect(route.allowsInviteAcceptance)
    }

    @Test func pendingInviteWithoutEntitlementStaysLimitedAuthenticated() {
        let route = resolver.route(
            for: .test(
                userEntitlement: .notEntitled(),
                hasPendingInvite: true
            )
        )

        #expect(route == .limitedAuthenticated)
        #expect(route.appState == .limitedAuthenticated)
        #expect(route.allowsInviteAcceptance)
    }

    @Test func capturedIncomingInviteOverridesEntitledUnpairedDestination() {
        let resolver = PendingJoinInviteFlowResolver()

        #expect(
            resolver.shouldPresentInviteAcceptance(
                for: .unpaired,
                pendingInviteCode: "01ABCD"
            )
        )
        #expect(
            resolver.shouldPresentInviteAcceptance(
                for: .invitePending,
                pendingInviteCode: "01ABCD"
            )
        )
    }

    @Test func capturedIncomingInviteWaitsThroughAuthAndProfileSetup() {
        let resolver = PendingJoinInviteFlowResolver()

        #expect(
            !resolver.shouldPresentInviteAcceptance(
                for: .unauthenticated,
                pendingInviteCode: "01ABCD"
            )
        )
        #expect(
            !resolver.shouldPresentInviteAcceptance(
                for: .onboarding,
                pendingInviteCode: "01ABCD"
            )
        )
        #expect(
            resolver.shouldPresentInviteAcceptance(
                for: .limitedAuthenticated,
                pendingInviteCode: "01ABCD"
            )
        )
    }

    /// A saved partner code shows the join screen in place of the paywall.
    /// Joining a partner whose subscription has lapsed pairs the couple without
    /// access, and that couple gets the paywall even if the code is still saved.
    @Test func aPartnersCodeReplacesThePaywallOnlyBeforePairing() {
        let resolver = PendingJoinInviteFlowResolver()

        #expect(resolver.shouldPresentInviteAcceptance(for: .limitedAuthenticated, pendingInviteCode: "01ABCD"))
        #expect(!resolver.shouldPresentInviteAcceptance(for: .limitedAuthenticated, pendingInviteCode: nil))
        #expect(!resolver.shouldPresentInviteAcceptance(for: .pairedPaywalled, pendingInviteCode: "01ABCD"))
    }

    @Test func malformedOrCompletedIncomingInviteDoesNotOverrideRouting() {
        let resolver = PendingJoinInviteFlowResolver()

        #expect(
            !resolver.shouldPresentInviteAcceptance(
                for: .unpaired,
                pendingInviteCode: "short"
            )
        )
        #expect(
            !resolver.shouldPresentInviteAcceptance(
                for: .paired,
                pendingInviteCode: "01ABCD"
            )
        )
    }

    @Test func aBannedAccountRoutesToTheClosedScreenWhateverElseItHas() {
        let route = resolver.route(
            for: .test(
                userEntitlement: .entitled(),
                relationshipState: .active(),
                hasPendingInvite: true,
                isBanned: true
            )
        )

        #expect(route == .accountClosed)
        #expect(route.appState == .accountClosed)
        #expect(!route.allowsInviteAcceptance)
    }

    @Test func activeRelationshipWithCoupleEntitlementRoutesToPaired() {
        let route = resolver.route(
            for: .test(
                userEntitlement: .entitled(),
                coupleEntitlement: .entitled(),
                relationshipState: .active()
            )
        )

        #expect(route == .paired)
        #expect(route.appState == .paired)
        #expect(!route.allowsInviteAcceptance)
    }

    @Test func activeRelationshipWithoutCoupleCoverageRoutesToPaywall() {
        let route = resolver.route(
            for: .test(
                userEntitlement: .entitled(),
                coupleEntitlement: .notEntitled(),
                relationshipState: .active()
            )
        )

        #expect(route == .pairedPaywalled)
        #expect(route.appState == .pairedPaywalled)
    }

    @Test func endedNoticePendingRelationshipRoutesToEndedNotice() {
        let route = resolver.route(
            for: .test(
                userEntitlement: .entitled(),
                coupleEntitlement: .entitled(),
                relationshipState: .endedNoticePending()
            )
        )

        #expect(route == .relationshipEndedNotice)
        #expect(route.appState == .relationshipEndedNotice)
    }
}

private extension AccessRouteSnapshot {
    static func test(
        userEntitlement: RemoteUserEntitlement? = nil,
        coupleEntitlement: RemoteCoupleEntitlement? = nil,
        relationshipState: RemoteRelationshipState? = nil,
        hasPendingInvite: Bool = false,
        isBanned: Bool = false
    ) -> AccessRouteSnapshot {
        AccessRouteSnapshot(
            userEntitlement: userEntitlement,
            coupleEntitlement: coupleEntitlement,
            relationshipState: relationshipState,
            hasPendingInvite: hasPendingInvite,
            isBanned: isBanned
        )
    }
}

private extension RemoteUserEntitlement {
    static func entitled() -> RemoteUserEntitlement {
        RemoteUserEntitlement(
            userID: UUID(),
            isEntitled: true,
            source: "storekit",
            status: "active",
            productID: UUID(),
            billingPeriod: nil,
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    static func notEntitled() -> RemoteUserEntitlement {
        RemoteUserEntitlement(
            userID: UUID(),
            isEntitled: false,
            source: nil,
            status: nil,
            productID: nil,
            billingPeriod: nil,
            currentPeriodEnd: nil,
            updatedAt: nil
        )
    }
}

private extension RemoteCoupleEntitlement {
    static func entitled() -> RemoteCoupleEntitlement {
        RemoteCoupleEntitlement(
            coupleID: UUID(),
            isEntitled: true,
            coveringUserID: UUID(),
            source: "storekit",
            status: "active",
            productID: UUID(),
            billingPeriod: nil,
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    static func notEntitled() -> RemoteCoupleEntitlement {
        RemoteCoupleEntitlement(
            coupleID: UUID(),
            isEntitled: false,
            coveringUserID: nil,
            source: nil,
            status: nil,
            productID: nil,
            billingPeriod: nil,
            currentPeriodEnd: nil,
            updatedAt: nil
        )
    }
}

private extension RemoteRelationshipState {
    static func active() -> RemoteRelationshipState {
        test(
            relationshipStatus: .active,
            memberStatus: .active,
            endedNoticeSeenAt: nil
        )
    }

    static func endedNoticePending() -> RemoteRelationshipState {
        test(
            relationshipStatus: .ended,
            memberStatus: .endedNoticePending,
            endedNoticeSeenAt: nil
        )
    }

    static func test(
        relationshipStatus: RemoteRelationshipStatus,
        memberStatus: RemoteRelationshipMemberStatus,
        endedNoticeSeenAt: Date?
    ) -> RemoteRelationshipState {
        RemoteRelationshipState(
            coupleID: UUID(),
            pairID: UUID(),
            relationshipStatus: relationshipStatus,
            memberStatus: memberStatus,
            acceptedInvite: false,
            partnerUserID: UUID(),
            partnerDisplayName: "Riley",
            partnerProfilePhotoAssetID: nil,
            startedOn: "2026-06-23",
            endedAt: relationshipStatus == .ended
                ? Date(timeIntervalSince1970: 1_800_000_000)
                : nil,
            deleteAfter: relationshipStatus == .ended
                ? Date(timeIntervalSince1970: 1_900_000_000)
                : nil,
            endedNoticeSeenAt: endedNoticeSeenAt
        )
    }
}
