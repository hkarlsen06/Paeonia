import CryptoKit
import Foundation

/// A device-scoped client operation that makes the media reserve/finalize calls
/// idempotent.
nonisolated struct AuthClientOperation: Sendable {
    let id: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
}

nonisolated struct PendingMediaUploadResponse: Decodable, Sendable {
    let mediaAssetID: UUID
    let bucket: String
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case bucket
        case storagePath = "storage_path"
    }
}

nonisolated struct FinalizedMediaUploadResponse: Decodable, Sendable {
    let mediaAssetID: UUID
    let uploadStatus: String

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case uploadStatus = "upload_status"
    }
}

nonisolated struct CreatePendingProfilePhotoUploadRequest: Encodable {
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let reservedParentKind = "profile_photo"
    let reservedParentID: UUID
    let uploadPurpose = "profile_photo"
    let mediaType = "image"
    let fileExtension: String

    init(
        operation: AuthClientOperation,
        reservedParentID: UUID,
        fileExtension: String
    ) {
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.reservedParentID = reservedParentID
        self.fileExtension = fileExtension
    }

    enum CodingKeys: String, CodingKey {
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
        case reservedParentKind = "p_reserved_parent_kind"
        case reservedParentID = "p_reserved_parent_id"
        case uploadPurpose = "p_upload_purpose"
        case mediaType = "p_media_type"
        case fileExtension = "p_file_extension"
    }
}

nonisolated struct FinalizeProfilePhotoUploadRequest: Encodable {
    let mediaAssetID: UUID
    let reservedByClientOperationID: UUID
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let bucket: String
    let storagePath: String
    let reservedParentKind = "profile_photo"
    let reservedParentID: UUID
    let uploadPurpose = "profile_photo"
    let mediaType = "image"
    let mimeType: String
    let byteSize: Int64
    let sha256Hex: String
    let width: Int
    let height: Int

    init(
        reservation: PendingMediaUploadResponse,
        reservedByClientOperationID: UUID,
        operation: AuthClientOperation,
        reservedParentID: UUID,
        image: ImageCompressor.CompressedImage
    ) {
        self.mediaAssetID = reservation.mediaAssetID
        self.reservedByClientOperationID = reservedByClientOperationID
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.bucket = reservation.bucket
        self.storagePath = reservation.storagePath
        self.reservedParentID = reservedParentID
        self.mimeType = image.mediaType
        self.byteSize = Int64(image.data.count)
        self.sha256Hex = SHA256.hash(data: image.data).map { String(format: "%02x", $0) }.joined()
        self.width = image.width
        self.height = image.height
    }

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case reservedByClientOperationID = "p_reserved_by_client_operation_id"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
        case bucket = "p_bucket"
        case storagePath = "p_storage_path"
        case reservedParentKind = "p_reserved_parent_kind"
        case reservedParentID = "p_reserved_parent_id"
        case uploadPurpose = "p_upload_purpose"
        case mediaType = "p_media_type"
        case mimeType = "p_mime_type"
        case byteSize = "p_byte_size"
        case sha256Hex = "p_sha256_hex"
        case width = "p_width"
        case height = "p_height"
    }
}

nonisolated struct MarkMediaForDeletionRequest: Encodable {
    let mediaAssetID: UUID

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
    }
}
