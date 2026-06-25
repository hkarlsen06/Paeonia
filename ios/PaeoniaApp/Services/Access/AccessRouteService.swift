protocol AccessRouteServicing: Actor {
    func resolveAccess(hasPendingInvite: Bool) async throws -> AccessRouteResolution
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
        let userEntitlement = try await gateway.loadMyEntitlement()
        let coupleEntitlement = try await gateway.loadMyCoupleEntitlement()
        let relationshipState = try await gateway.loadCurrentRelationshipState()
        let snapshot = AccessRouteSnapshot(
            userEntitlement: userEntitlement,
            coupleEntitlement: coupleEntitlement,
            relationshipState: relationshipState,
            hasPendingInvite: hasPendingInvite
        )

        return AccessRouteResolution(
            route: resolver.route(for: snapshot),
            snapshot: snapshot
        )
    }
}

extension AccessRouteServicing {
    func resolveRoute(hasPendingInvite: Bool = false) async throws -> AccessRoute {
        try await resolveAccess(hasPendingInvite: hasPendingInvite).route
    }
}
