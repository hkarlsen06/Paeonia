import Foundation

protocol AccessRouteServicing: Actor {
    func resolveAccess(hasPendingInvite: Bool) async throws -> AccessRouteResolution
    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws
}

actor SupabaseAccessRouteService: AccessRouteServicing {
    private let gateway: any SupabaseAccessGateway
    private let resolver: AccessRouteResolver

    init(
        gateway: any SupabaseAccessGateway,
        resolver: AccessRouteResolver = AccessRouteResolver()
    ) {
        self.gateway = gateway
        self.resolver = resolver
    }

    static func live() throws -> SupabaseAccessRouteService {
        let client = try PaeoniaSupabaseClientProvider.shared.client()
        return SupabaseAccessRouteService(
            gateway: LiveSupabaseAccessGateway(client: client)
        )
    }

    func resolveAccess(hasPendingInvite: Bool = false) async throws -> AccessRouteResolution {
        let accessSnapshot = try await gateway.loadAccessSnapshot()
        let snapshot = AccessRouteSnapshot(
            userEntitlement: accessSnapshot.userEntitlement,
            coupleEntitlement: accessSnapshot.coupleEntitlement,
            relationshipState: accessSnapshot.relationshipState,
            hasPendingInvite: hasPendingInvite
        )

        return AccessRouteResolution(
            route: resolver.route(for: snapshot),
            snapshot: snapshot
        )
    }

    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws {
        try await gateway.markRelationshipEndedNoticeSeen(coupleID: coupleID)
    }
}

extension AccessRouteServicing {
    func resolveRoute(hasPendingInvite: Bool = false) async throws -> AccessRoute {
        try await resolveAccess(hasPendingInvite: hasPendingInvite).route
    }
}
