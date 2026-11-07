import CryptoKit
import Foundation

/// One file sent through `media:create_pending_media_upload`, the storage upload and
/// `media:finalize_media_upload`. The backend checks the parent kind, the purpose and
/// the media type together (`media.ts`).
nonisolated struct MediaUpload: Sendable, Equatable {
    /// `reserved_parent_kind`, such as `memory_media`.
    var parentKind: String
    /// `reserved_parent_id`: the row the file belongs to.
    var parentID: UUID
    /// `upload_purpose`, such as `memory_photo`.
    var purpose: String
    /// `media_type`: `image`, `voice` or `drawing_payload`.
    var mediaType: String
    var mimeType: String
    var fileExtension: String
    var coupleID: UUID?
    var pathContext: MediaUploadPathContext?
    var accessibilityText: String?
    var width: Int?
    var height: Int?
    var durationMs: Int?
}

nonisolated extension MediaUpload {
    /// The `.pkdrawing` of a widget drawing revision. The first day drawing uses it too,
    /// before the couple's canvas exists.
    static func widgetDrawing(
        revisionID: UUID,
        coupleID: UUID? = nil,
        pathContext: MediaUploadPathContext? = nil
    ) -> MediaUpload {
        MediaUpload(
            parentKind: "widget_drawing_revision",
            parentID: revisionID,
            purpose: "widget_drawing_payload",
            mediaType: "drawing_payload",
            mimeType: LiveWidgetCanvasGateway.payloadMimeType,
            fileExtension: LiveWidgetCanvasGateway.payloadFileExtension,
            coupleID: coupleID,
            pathContext: pathContext
        )
    }
}

/// Where the server files an upload whose parent alone does not say.
nonisolated enum MediaUploadPathContext: Sendable, Equatable, Encodable {
    case game(UUID)
    case widgetCanvas(UUID)
    /// The inviter's first drawing, kept with the draft before the couple exists.
    case firstDayDraft

    private enum CodingKeys: String, CodingKey {
        case gameID = "game_id"
        case canvasID = "canvas_id"
        case firstDayDraft = "first_day_draft"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .game(id): try container.encode(id, forKey: .gameID)
        case let .widgetCanvas(id): try container.encode(id, forKey: .canvasID)
        case .firstDayDraft: try container.encode(true, forKey: .firstDayDraft)
        }
    }
}

nonisolated enum MediaUploadError: Error, Equatable, Sendable {
    case reservationFailed
    case finalizeFailed
}

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

nonisolated private struct FinalizedMediaUploadResponse: Decodable, Sendable {
    let mediaAssetID: UUID
    let uploadStatus: String

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "media_asset_id"
        case uploadStatus = "upload_status"
    }
}

/// Runs the three upload steps. The two client operations make reserve and finalize
/// idempotent, so a retry after a lost response returns the same asset.
nonisolated struct MediaUploader: Sendable {
    let client: PaeoniaConvexClient

    /// Reserves, uploads and finalizes `data`, and returns its media asset id.
    func upload(
        _ data: Data,
        as upload: MediaUpload,
        reserveOperation: SyncClientOperation,
        finalizeOperation: SyncClientOperation
    ) async throws -> UUID {
        let reservation = try await reserve(upload, operation: reserveOperation)
        let storageID = try await client.upload(data, contentType: upload.mimeType, to: reservation.uploadURL)
        return try await finalize(
            upload,
            reservation: reservation,
            storageID: storageID,
            content: MediaUploadContent(data),
            reservedBy: reserveOperation.id,
            operation: finalizeOperation
        )
    }

    func reserve(_ upload: MediaUpload, operation: SyncClientOperation) async throws -> MediaUploadReservation {
        let rows: [MediaUploadReservation] = try await client.mutation(
            "media:create_pending_media_upload",
            args: ReserveRequest(upload: upload, operation: operation)
        )
        guard let reservation = rows.first else { throw MediaUploadError.reservationFailed }
        return reservation
    }

    // swiftlint:disable:next function_parameter_count
    func finalize(
        _ upload: MediaUpload,
        reservation: MediaUploadReservation,
        storageID: String,
        content: MediaUploadContent,
        reservedBy reserveOperationID: UUID,
        operation: SyncClientOperation
    ) async throws -> UUID {
        let rows: [FinalizedMediaUploadResponse] = try await client.mutation(
            "media:finalize_media_upload",
            args: FinalizeRequest(
                upload: upload,
                reservation: reservation,
                storageID: storageID,
                content: content,
                reserveOperationID: reserveOperationID,
                operation: operation
            )
        )
        guard let finalized = rows.first, finalized.uploadStatus == "finalized" else {
            throw MediaUploadError.finalizeFailed
        }
        return finalized.mediaAssetID
    }
}

/// The size and hash finalize checks the stored file against.
nonisolated struct MediaUploadContent: Sendable, Equatable {
    let byteSize: Int64
    let sha256Hex: String

    init(byteSize: Int64, sha256Hex: String) {
        self.byteSize = byteSize
        self.sha256Hex = sha256Hex
    }

    init(_ data: Data) {
        byteSize = Int64(data.count)
        sha256Hex = SHA256.hash(data: data).paeoniaHexString
    }
}

nonisolated private struct ReserveRequest: Encodable {
    let upload: MediaUpload
    let operation: SyncClientOperation

    enum CodingKeys: String, CodingKey {
        case reservedParentKind = "p_reserved_parent_kind"
        case reservedParentID = "p_reserved_parent_id"
        case uploadPurpose = "p_upload_purpose"
        case mediaType = "p_media_type"
        case fileExtension = "p_file_extension"
        case coupleID = "p_couple_id"
        case pathContext = "p_path_context"
        case accessibilityText = "p_accessibility_text"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(upload.parentKind, forKey: .reservedParentKind)
        try container.encode(upload.parentID, forKey: .reservedParentID)
        try container.encode(upload.purpose, forKey: .uploadPurpose)
        try container.encode(upload.mediaType, forKey: .mediaType)
        try container.encode(upload.fileExtension, forKey: .fileExtension)
        try container.encodeIfPresent(upload.coupleID, forKey: .coupleID)
        try container.encodeIfPresent(upload.pathContext, forKey: .pathContext)
        try container.encodeIfPresent(upload.accessibilityText, forKey: .accessibilityText)
        try ClientOperationFields(operation).encode(to: encoder)
    }
}

nonisolated private struct FinalizeRequest: Encodable {
    let upload: MediaUpload
    let reservation: MediaUploadReservation
    let storageID: String
    let content: MediaUploadContent
    let reserveOperationID: UUID
    let operation: SyncClientOperation

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case reservedByClientOperationID = "p_reserved_by_client_operation_id"
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

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reservation.mediaAssetID, forKey: .mediaAssetID)
        try container.encode(reserveOperationID, forKey: .reservedByClientOperationID)
        try container.encode(reservation.bucket, forKey: .bucket)
        try container.encode(reservation.storagePath, forKey: .storagePath)
        try container.encode(storageID, forKey: .storageID)
        try container.encode(upload.parentKind, forKey: .reservedParentKind)
        try container.encode(upload.parentID, forKey: .reservedParentID)
        try container.encode(upload.purpose, forKey: .uploadPurpose)
        try container.encode(upload.mediaType, forKey: .mediaType)
        try container.encode(upload.mimeType, forKey: .mimeType)
        try container.encode(content.byteSize, forKey: .byteSize)
        try container.encode(content.sha256Hex, forKey: .sha256Hex)
        try container.encodeIfPresent(upload.width, forKey: .width)
        try container.encodeIfPresent(upload.height, forKey: .height)
        try container.encodeIfPresent(upload.durationMs, forKey: .durationMs)
        try ClientOperationFields(operation).encode(to: encoder)
    }
}
