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

    @Test func serviceLoadsRpcContractsBeforeResolvingRoute() async throws {
        let gateway = FakeSupabaseAccessGateway(
            userEntitlement: .entitled(),
            coupleEntitlement: nil,
            relationshipState: nil
        )
        let service = SupabaseAccessRouteService(gateway: gateway)

        let route = try await service.resolveRoute()

        #expect(route == .unpaired)
        #expect(await gateway.calls == [
            .loadMyEntitlement,
            .loadMyCoupleEntitlement,
            .loadCurrentRelationshipState,
        ])
    }
}

// swiftlint:disable async_without_await
private actor FakeSupabaseAccessGateway: SupabaseAccessGateway {
    enum Call: Equatable, Sendable {
        case loadMyEntitlement
        case loadMyCoupleEntitlement
        case loadCurrentRelationshipState
    }

    private let userEntitlement: SupabaseUserEntitlement?
    private let coupleEntitlement: SupabaseCoupleEntitlement?
    private let relationshipState: SupabaseRelationshipState?
    private(set) var calls: [Call] = []

    init(
        userEntitlement: SupabaseUserEntitlement?,
        coupleEntitlement: SupabaseCoupleEntitlement?,
        relationshipState: SupabaseRelationshipState?
    ) {
        self.userEntitlement = userEntitlement
        self.coupleEntitlement = coupleEntitlement
        self.relationshipState = relationshipState
    }

    func loadMyEntitlement() async throws -> SupabaseUserEntitlement? {
        calls.append(.loadMyEntitlement)
        return userEntitlement
    }

    func loadMyCoupleEntitlement() async throws -> SupabaseCoupleEntitlement? {
        calls.append(.loadMyCoupleEntitlement)
        return coupleEntitlement
    }

    func loadCurrentRelationshipState() async throws -> SupabaseRelationshipState? {
        calls.append(.loadCurrentRelationshipState)
        return relationshipState
    }
}
// swiftlint:enable async_without_await

private extension AccessRouteSnapshot {
    static func test(
        userEntitlement: SupabaseUserEntitlement? = nil,
        coupleEntitlement: SupabaseCoupleEntitlement? = nil,
        relationshipState: SupabaseRelationshipState? = nil,
        hasPendingInvite: Bool = false
    ) -> AccessRouteSnapshot {
        AccessRouteSnapshot(
            userEntitlement: userEntitlement,
            coupleEntitlement: coupleEntitlement,
            relationshipState: relationshipState,
            hasPendingInvite: hasPendingInvite
        )
    }
}

private extension SupabaseUserEntitlement {
    static func entitled() -> SupabaseUserEntitlement {
        SupabaseUserEntitlement(
            userID: UUID(),
            isEntitled: true,
            source: "storekit",
            status: "active",
            productID: UUID(),
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    static func notEntitled() -> SupabaseUserEntitlement {
        SupabaseUserEntitlement(
            userID: UUID(),
            isEntitled: false,
            source: nil,
            status: nil,
            productID: nil,
            currentPeriodEnd: nil,
            updatedAt: nil
        )
    }
}

private extension SupabaseCoupleEntitlement {
    static func entitled() -> SupabaseCoupleEntitlement {
        SupabaseCoupleEntitlement(
            coupleID: UUID(),
            isEntitled: true,
            coveringUserID: UUID(),
            source: "storekit",
            status: "active",
            productID: UUID(),
            currentPeriodEnd: Date(timeIntervalSince1970: 2_000_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    static func notEntitled() -> SupabaseCoupleEntitlement {
        SupabaseCoupleEntitlement(
            coupleID: UUID(),
            isEntitled: false,
            coveringUserID: nil,
            source: nil,
            status: nil,
            productID: nil,
            currentPeriodEnd: nil,
            updatedAt: nil
        )
    }
}

private extension SupabaseRelationshipState {
    static func active() -> SupabaseRelationshipState {
        test(
            relationshipStatus: .active,
            memberStatus: .active,
            endedNoticeSeenAt: nil
        )
    }

    static func endedNoticePending() -> SupabaseRelationshipState {
        test(
            relationshipStatus: .ended,
            memberStatus: .endedNoticePending,
            endedNoticeSeenAt: nil
        )
    }

    static func test(
        relationshipStatus: SupabaseRelationshipStatus,
        memberStatus: SupabaseRelationshipMemberStatus,
        endedNoticeSeenAt: Date?
    ) -> SupabaseRelationshipState {
        SupabaseRelationshipState(
            coupleID: UUID(),
            pairID: UUID(),
            relationshipStatus: relationshipStatus,
            memberStatus: memberStatus,
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
