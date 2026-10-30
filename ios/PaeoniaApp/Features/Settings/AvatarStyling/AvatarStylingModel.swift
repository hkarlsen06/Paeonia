import Observation
import SwiftUI

nonisolated protocol AvatarDecorationSaving: Sendable {
    func save(_ decoration: AvatarDecoration) async throws
}

nonisolated struct LiveAvatarDecorationGateway: AvatarDecorationSaving {
    let client: PaeoniaConvexClient

    func save(_ decoration: AvatarDecoration) async throws {
        let _: AvatarDecoration = try await client.mutation(
            "avatarDecorations:set_own_decoration", args: ["p_decoration": decoration.rawValue]
        )
    }

    static func makeDefault() -> Self? {
        (try? PaeoniaConvexClientProvider.shared.client()).map(Self.init)
    }
}

/// The tabs share the saved choice. The editor keeps its draft until a save succeeds or is cancelled.
@MainActor
@Observable
final class AvatarStylingModel {
    private(set) var decorations = CoupleAvatarDecorations()
    private(set) var isSaving = false
    @ObservationIgnored private let gateway: (any AvatarDecorationSaving)?

    init(gateway: (any AvatarDecorationSaving)? = LiveAvatarDecorationGateway.makeDefault()) {
        self.gateway = gateway
    }

    func update(_ decorations: CoupleAvatarDecorations) {
        self.decorations = decorations
    }

    func save(_ decoration: AvatarDecoration) async throws {
        guard let gateway else { throw URLError(.cannotConnectToHost) }
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        try await gateway.save(decoration)
        decorations.own = decoration
    }
}

extension EnvironmentValues {
    @Entry var avatarStyling: AvatarStylingModel?
}
