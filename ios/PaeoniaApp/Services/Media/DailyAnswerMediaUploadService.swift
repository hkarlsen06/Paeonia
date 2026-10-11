import CryptoKit
import Foundation

/// What kind of daily-answer media is being uploaded. Drives the backend
/// `upload_purpose` and `media_type`; both kinds share the `daily_answer_media`
/// reserved parent so they attach to the same answer.
nonisolated enum DailyAnswerMediaPurpose: String, Codable, Sendable, Equatable {
    case photo = "daily_answer_media"
    case voice = "voice_note"
    /// A photo in a question chat message.
    case threadPhoto = "thread_media"

    var mediaType: String {
        switch self {
        case .photo, .threadPhoto:
            "image"
        case .voice:
            "voice"
        }
    }
}

/// A staged media file ready to upload as part of an answer.
nonisolated struct DailyAnswerUploadMedia: Sendable, Equatable {
    let data: Data
    let purpose: DailyAnswerMediaPurpose
    let mimeType: String
    let fileExtension: String
    let width: Int?
    let height: Int?
    let durationMs: Int?

    init(
        data: Data,
        purpose: DailyAnswerMediaPurpose,
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

nonisolated protocol DailyAnswerMediaUploading: Sendable {
    /// Reserves, uploads the bytes, and finalizes one media asset against an answer,
    /// returning its media asset id. The two operations make the reserve and finalize
    /// calls idempotent so a retried upload can't create duplicate assets.
    func uploadMedia(
        _ media: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID
}

nonisolated enum DailyAnswerMediaUploadError: Error, Equatable, Sendable {
    case reservationFailed
    case finalizeFailed
}

/// Uploads daily-answer media through the same reserve → storage → finalize path the
/// profile photo uses, but scoped to the `daily_answer_media` parent so the asset
/// links to a specific answer.
///
/// Question chats reuse it for voice messages with the `thread_message_media` parent.
/// Then `answerID` is the id the message will get.
actor LiveDailyAnswerMediaUploadService: DailyAnswerMediaUploading {
    private let client: PaeoniaConvexClient
    private let reservedParentKind: String

    init(client: PaeoniaConvexClient, reservedParentKind: String = "daily_answer_media") {
        self.client = client
        self.reservedParentKind = reservedParentKind
    }

    static func live() throws -> LiveDailyAnswerMediaUploadService {
        LiveDailyAnswerMediaUploadService(client: try PaeoniaConvexClientProvider.shared.client())
    }

    func uploadMedia(
        _ media: DailyAnswerUploadMedia,
        answerID: UUID,
        coupleID: UUID,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID {
        let reservation: [MediaUploadReservation] = try await client.mutation(
            "media:create_pending_media_upload",
            args: ReserveDailyAnswerMediaRequest(
                operation: reserveOperation,
                reservedParentKind: reservedParentKind,
                answerID: answerID,
                coupleID: coupleID,
                purpose: media.purpose,
                fileExtension: media.fileExtension
            )
        )
        guard let reservation = reservation.first else {
            throw DailyAnswerMediaUploadError.reservationFailed
        }

        let storageID = try await client.upload(
            media.data,
            contentType: media.mimeType,
            to: reservation.uploadURL
        )

        let finalized: [FinalizedMediaUploadResponse] = try await client.mutation(
            "media:finalize_media_upload",
            args: FinalizeDailyAnswerMediaRequest(
                reservation: reservation,
                storageID: storageID,
                reservedByClientOperationID: reserveOperation.id,
                operation: finalizeOperation,
                reservedParentKind: reservedParentKind,
                answerID: answerID,
                media: media
            )
        )
        guard let finalized = finalized.first, finalized.uploadStatus == "finalized" else {
            throw DailyAnswerMediaUploadError.finalizeFailed
        }

        return finalized.mediaAssetID
    }
}

nonisolated struct ReserveDailyAnswerMediaRequest: Encodable {
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
        reservedParentKind: String = "daily_answer_media",
        answerID: UUID,
        coupleID: UUID,
        purpose: DailyAnswerMediaPurpose,
        fileExtension: String
    ) {
        clientOperationID = operation.id
        clientID = operation.clientID
        clientSequence = operation.clientSequence
        localCreatedAt = operation.localCreatedAt
        self.reservedParentKind = reservedParentKind
        reservedParentID = answerID
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

nonisolated struct FinalizeDailyAnswerMediaRequest: Encodable {
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
        reservedParentKind: String = "daily_answer_media",
        answerID: UUID,
        media: DailyAnswerUploadMedia
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
        self.reservedParentKind = reservedParentKind
        reservedParentID = answerID
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
