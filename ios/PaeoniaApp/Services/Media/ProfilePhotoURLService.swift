import Foundation

nonisolated protocol ProfilePhotoURLProviding: Sendable {
    func signedProfilePhotoURL(for mediaAssetID: UUID?) async throws -> URL?
}

final class ProfilePhotoURLService: @unchecked Sendable, ProfilePhotoURLProviding {
    private let client: PaeoniaConvexClient
    private let expiresInSeconds = 3_600

    nonisolated init(client: PaeoniaConvexClient) {
        self.client = client
    }

    nonisolated static func live() throws -> ProfilePhotoURLService {
        let client = try PaeoniaConvexClientProvider.shared.client()
        return ProfilePhotoURLService(client: client)
    }

    func signedProfilePhotoURL(for mediaAssetID: UUID?) async throws -> URL? {
        guard let mediaAssetID else {
            return nil
        }

        return try await client.signedMediaURL(for: mediaAssetID, expiresInSeconds: expiresInSeconds)
    }
}
