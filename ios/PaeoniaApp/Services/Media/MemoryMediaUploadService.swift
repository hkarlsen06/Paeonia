import CryptoKit
import Foundation
import Supabase

nonisolated enum MemoryMediaPurpose: String, Codable, Sendable, Equatable {
    case photo = "memory_photo"
    case voice = "voice_note"

    var mediaType: String {
        switch self {
        case .photo:
            "image"
        case .voice:
            "voice"
        }
    }
}

nonisolated struct MemoryUploadMedia: Sendable, Equatable {
    let data: Data
    let purpose: MemoryMediaPurpose
    let mimeType: String
    let fileExtension: String
    let width: Int?
    let height: Int?
    let durationMs: Int?

    init(
        data: Data,
        purpose: MemoryMediaPurpose,
        mimeType: String,
        fileExtension: String,
        width: Int? = nil,
        height: Int? = nil,
        durationMs: Int? = nil
    ) {
        self.data = data
        self.purpose = purpose
        self.mimeType = mimeType
        self.fileExtension = fileExtension
        self.width = width
        self.height = height
        self.durationMs = durationMs
    }
}

nonisolated struct MemoryMediaUploadResult: Equatable, Sendable {
    let memoryMediaID: UUID
    let mediaAssetID: UUID

    func optimisticSnapshot(
        ownerUserID: UUID,
        sortOrder: Int,
        updatedAt: Date = Date()
    ) -> MemoryMediaSnapshot {
        MemoryMediaSnapshot(
            memoryMediaID: memoryMediaID,
            mediaAssetID: mediaAssetID,
            ownerUserID: ownerUserID,
            sortOrder: sortOrder,
            updatedAt: updatedAt
        )
    }
}

nonisolated protocol MemoryMediaUploading: Sendable {
    func uploadMedia(
        _ media: MemoryUploadMedia,
        memoryMediaID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> MemoryMediaUploadResult
}

nonisolated enum MemoryMediaUploadError: Error, Equatable, Sendable {
    case reservationFailed
    case finalizeFailed
}

actor LiveMemoryMediaUploadService: MemoryMediaUploading {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    static func live() throws -> LiveMemoryMediaUploadService {
        LiveMemoryMediaUploadService(client: try PaeoniaSupabaseClientProvider.shared.client())
    }

    func uploadMedia(
        _ media: MemoryUploadMedia,
        memoryMediaID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> MemoryMediaUploadResult {
        _ = try await client.auth.session

        let reservationRows: [PendingMediaUploadResponse] = try await client
            .rpc(
                "create_pending_media_upload",
                params: ReserveMemoryMediaRequest(
                    operation: reserveOperation,
                    memoryMediaID: memoryMediaID,
                    coupleID: coupleID,
                    purpose: media.purpose,
                    fileExtension: media.fileExtension
                )
            )
            .execute()
            .value
        guard let reservation = reservationRows.first else {
            throw MemoryMediaUploadError.reservationFailed
        }

        try await client.storage
            .from(reservation.bucket)
            .upload(
                reservation.storagePath,
                data: media.data,
                options: FileOptions(contentType: media.mimeType)
            )

        let finalizedRows: [FinalizedMediaUploadResponse] = try await client
            .rpc(
                "finalize_media_upload",
                params: FinalizeMemoryMediaRequest(
                    reservation: reservation,
                    reservedByClientOperationID: reserveOperation.id,
                    operation: finalizeOperation,
                    memoryMediaID: memoryMediaID,
                    media: media
                )
            )
            .execute()
            .value
        guard let finalized = finalizedRows.first, finalized.uploadStatus == "finalized" else {
            throw MemoryMediaUploadError.finalizeFailed
        }

        return MemoryMediaUploadResult(
            memoryMediaID: memoryMediaID,
            mediaAssetID: finalized.mediaAssetID
        )
    }
}

nonisolated struct ReserveMemoryMediaRequest: Encodable {
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let reservedParentKind = "memory_media"
    let reservedParentID: UUID
    let coupleID: UUID
    let uploadPurpose: String
    let mediaType: String
    let fileExtension: String

    init(
        operation: SyncClientOperation,
        memoryMediaID: UUID,
        coupleID: UUID,
        purpose: MemoryMediaPurpose,
        fileExtension: String
    ) {
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
        reservedParentID = memoryMediaID
        self.coupleID = coupleID
        uploadPurpose = purpose.rawValue
        mediaType = purpose.mediaType
        self.fileExtension = fileExtension
    }

    enum CodingKeys: String, CodingKey {
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
        case reservedParentKind = "p_reserved_parent_kind"
        case reservedParentID = "p_reserved_parent_id"
        case coupleID = "p_couple_id"
        case uploadPurpose = "p_upload_purpose"
        case mediaType = "p_media_type"
        case fileExtension = "p_file_extension"
    }
}

nonisolated struct FinalizeMemoryMediaRequest: Encodable {
    let mediaAssetID: UUID
    let reservedByClientOperationID: UUID
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let bucket: String
    let storagePath: String
    let reservedParentKind = "memory_media"
    let reservedParentID: UUID
    let uploadPurpose: String
    let mediaType: String
    let mimeType: String
    let byteSize: Int64
    let sha256Hex: String
    let width: Int?
    let height: Int?
    let durationMs: Int?

    init(
        reservation: PendingMediaUploadResponse,
        reservedByClientOperationID: UUID,
        operation: SyncClientOperation,
        memoryMediaID: UUID,
        media: MemoryUploadMedia
    ) {
        mediaAssetID = reservation.mediaAssetID
        self.reservedByClientOperationID = reservedByClientOperationID
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
        bucket = reservation.bucket
        storagePath = reservation.storagePath
        reservedParentID = memoryMediaID
        uploadPurpose = media.purpose.rawValue
        mediaType = media.purpose.mediaType
        mimeType = media.mimeType
        byteSize = Int64(media.data.count)
        sha256Hex = SHA256.hash(data: media.data).map { String(format: "%02x", $0) }.joined()
        width = media.width
        height = media.height
        durationMs = media.durationMs
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
        case durationMs = "p_duration_ms"
    }
}
