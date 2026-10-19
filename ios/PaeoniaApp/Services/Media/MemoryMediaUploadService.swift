import CryptoKit
import Foundation

nonisolated enum MemoryMediaPurpose: String, Codable, Sendable, Equatable {
    case photo = "memory_photo"
    case voice = "voice_note"
    /// A story photo. It goes through the same upload as a memory photo.
    case story = "story_photo"
    /// A Guess my spot photo, stripped of its metadata before upload.
    case guessMySpot = "guess_my_spot_photo"

    var mediaType: String {
        switch self {
        case .photo, .story, .guessMySpot:
            "image"
        case .voice:
            "voice"
        }
    }

    /// What the upload is reserved for. A story photo belongs to its story, and a
    /// Guess my spot photo to its round.
    var reservedParentKind: String {
        switch self {
        case .photo, .voice:
            "memory_media"
        case .story:
            "story"
        case .guessMySpot:
            "guess_my_spot_round"
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
    private let client: PaeoniaConvexClient
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        self.isSignedIn = isSignedIn
    }

    static func live() throws -> LiveMemoryMediaUploadService {
        LiveMemoryMediaUploadService(client: try PaeoniaConvexClientProvider.shared.client())
    }

    func uploadMedia(
        _ media: MemoryUploadMedia,
        memoryMediaID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> MemoryMediaUploadResult {
        try await PaeoniaSignedIn.require(isSignedIn)

        let reservationRows: [MediaUploadReservation] = try await client.mutation(
            "media:create_pending_media_upload",
            args: ReserveMemoryMediaRequest(
                operation: reserveOperation,
                memoryMediaID: memoryMediaID,
                coupleID: coupleID,
                purpose: media.purpose,
                fileExtension: media.fileExtension
            )
        )
        guard let reservation = reservationRows.first else {
            throw MemoryMediaUploadError.reservationFailed
        }

        let storageID = try await client.upload(
            media.data,
            contentType: media.mimeType,
            to: reservation.uploadURL
        )

        let finalizedRows: [FinalizedMediaUploadResponse] = try await client.mutation(
            "media:finalize_media_upload",
            args: FinalizeMemoryMediaRequest(
                reservation: reservation,
                storageID: storageID,
                reservedByClientOperationID: reserveOperation.id,
                operation: finalizeOperation,
                memoryMediaID: memoryMediaID,
                media: media
            )
        )
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
    let reservedParentKind: String
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
        reservedParentKind = purpose.reservedParentKind
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
    let storageID: String
    let reservedParentKind: String
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
        reservation: MediaUploadReservation,
        storageID: String,
        reservedByClientOperationID: UUID,
        operation: SyncClientOperation,
        memoryMediaID: UUID,
        media: MemoryUploadMedia
    ) {
        mediaAssetID = reservation.mediaAssetID
        self.storageID = storageID
        self.reservedByClientOperationID = reservedByClientOperationID
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
        bucket = reservation.bucket
        storagePath = reservation.storagePath
        reservedParentKind = media.purpose.reservedParentKind
        reservedParentID = memoryMediaID
        uploadPurpose = media.purpose.rawValue
        mediaType = media.purpose.mediaType
        mimeType = media.mimeType
        byteSize = Int64(media.data.count)
        sha256Hex = SHA256.hash(data: media.data).paeoniaHexString
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
        case storageID = "p_storage_id"
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
