import Foundation

/// The reservation `media:create_pending_media_upload` returns. The app POSTs the
/// bytes to `uploadURL`, then passes the resulting storage id to
/// `media:finalize_media_upload` as `p_storage_id`.
nonisolated struct MediaUploadReservation: Decodable, Sendable, Equatable {
    let mediaAssetID: UUID
    let bucket: String
    let storagePath: String
    let uploadURL: URL

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case bucket
        case storagePath = "storage_path"
        case uploadURL = "upload_url"
    }
}
