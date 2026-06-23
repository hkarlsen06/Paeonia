protocol AccessRouteServicing: Actor {
    func resolveRoute(hasPendingInvite: Bool) async throws -> AccessRoute
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

    func resolveRoute(hasPendingInvite: Bool = false) async throws -> AccessRoute {
        let userEntitlement = try await gateway.loadMyEntitlement()
        let coupleEntitlement = try await gateway.loadMyCoupleEntitlement()
        let relationshipState = try await gateway.loadCurrentRelationshipState()

        return resolver.route(
            for: AccessRouteSnapshot(
                userEntitlement: userEntitlement,
                coupleEntitlement: coupleEntitlement,
                relationshipState: relationshipState,
                hasPendingInvite: hasPendingInvite
            )
        )
    }
}
