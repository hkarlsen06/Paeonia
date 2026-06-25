import Foundation
import Supabase

nonisolated protocol ProfilePhotoURLProviding: Sendable {
    func signedProfilePhotoURL(for mediaAssetID: UUID?) async throws -> URL?
}

final class SupabaseProfilePhotoURLService: @unchecked Sendable, ProfilePhotoURLProviding {
    private let client: SupabaseClient
    private let expiresInSeconds = 3_600

    nonisolated init(client: SupabaseClient) {
        self.client = client
    }

    nonisolated static func live() throws -> SupabaseProfilePhotoURLService {
        let client = try PaeoniaSupabaseClientProvider.shared.client()
        return SupabaseProfilePhotoURLService(client: client)
    }

    func signedProfilePhotoURL(for mediaAssetID: UUID?) async throws -> URL? {
        guard let mediaAssetID else {
            return nil
        }

        let rows: [ProfilePhotoSignedURLAuthorization] = try await client
            .rpc(
                "get_media_signed_url",
                params: ProfilePhotoSignedURLRequest(
                    mediaAssetID: mediaAssetID,
                    expiresInSeconds: expiresInSeconds
                )
            )
            .execute()
            .value

        guard let authorization = rows.first else {
            return nil
        }

        return try await client.storage
            .from(authorization.bucket)
            .createSignedURL(
                path: authorization.storagePath,
                expiresIn: authorization.expiresInSeconds
            )
    }
}

nonisolated private struct ProfilePhotoSignedURLRequest: Encodable, Sendable {
    let mediaAssetID: UUID
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case expiresInSeconds = "p_expires_in_seconds"
    }
}

nonisolated private struct ProfilePhotoSignedURLAuthorization: Decodable, Sendable {
    let mediaAssetID: UUID
    let bucket: String
    let storagePath: String
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case bucket
        case storagePath = "storage_path"
        case expiresInSeconds = "expires_in_seconds"
    }
}
