import Foundation

nonisolated private struct MediaSignedURLRequest: Encodable, Sendable {
    let mediaAssetID: UUID
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case expiresInSeconds = "p_expires_in_seconds"
    }
}

/// A row of `media:get_media_signed_url`. `signed_url` is a plain GET URL that
/// needs no auth header.
nonisolated struct MediaSignedURLRow: Decodable, Sendable {
    let signedURL: URL

    enum CodingKeys: String, CodingKey {
        case signedURL = "signed_url"
    }
}

extension PaeoniaConvexClient {
    /// Returns a download URL for a media asset, or nil when the backend returns no row.
    nonisolated func signedMediaURL(for mediaAssetID: UUID, expiresInSeconds: Int) async throws -> URL? {
        let rows: [MediaSignedURLRow] = try await mutation(
            "media:get_media_signed_url",
            args: MediaSignedURLRequest(
                mediaAssetID: mediaAssetID,
                expiresInSeconds: expiresInSeconds
            )
        )
        return rows.first?.signedURL
    }
}
