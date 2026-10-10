import Foundation

protocol AccessRouteServicing: Actor {
    func resolveAccess(hasPendingInvite: Bool) async throws -> AccessRouteResolution
    func markRelationshipEndedNoticeSeen(coupleID: UUID) async throws
}

actor RemoteAccessRouteService: AccessRouteServicing {
    private let gateway: any AccessGateway
    private let resolver: AccessRouteResolver

    init(
        gateway: any AccessGateway,
        resolver: AccessRouteResolver = AccessRouteResolver()
    ) {
        self.gateway = gateway
        self.resolver = resolver
    }

    static func live() throws -> RemoteAccessRouteService {
        let client = try PaeoniaConvexClientProvider.shared.client()
        return RemoteAccessRouteService(
            gateway: LiveAccessGateway(client: client)
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
