import Foundation
import Supabase

/// Canvas reference returned by `get_or_create_widget_canvas`.
nonisolated struct WidgetCanvasReference: Decodable, Sendable {
    let canvasID: UUID
    let coupleID: UUID
    let activeRevisionID: UUID?

    enum CodingKeys: String, CodingKey {
        case canvasID = "canvas_id"
        case coupleID = "couple_id"
        case activeRevisionID = "active_revision_id"
    }
}

/// The drawing metadata the submit RPC records alongside the payload pointer.
/// `parentRevisionID` is mutable so a conflict retry can re-anchor to the new
/// active revision without rebuilding the whole submission.
nonisolated struct WidgetDrawingRevisionSubmission: Sendable {
    let canvasID: UUID
    let payloadMediaAssetID: UUID
    var parentRevisionID: UUID?
    let payloadBytes: Int64
    let strokeCount: Int
    let pointCount: Int
    let bounds: WidgetDrawingBounds
    let sha256Hex: String
    let clientDecodeValidatedAt: Date
}

/// Inputs to finalize a reserved widget drawing upload.
nonisolated struct WidgetDrawingFinalizeInput: Sendable {
    let reservation: PendingMediaUploadResponse
    let revisionID: UUID
    let reservedByOperationID: UUID
    let byteSize: Int64
    let sha256Hex: String
}

/// Stored as the revision `bounds` jsonb. `canvasSide` lets the partner render
/// the preview at the same scale the author drew at.
nonisolated struct WidgetDrawingBounds: Codable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let canvasSide: Double
}

nonisolated struct WidgetDrawingRevisionResult: Decodable, Sendable {
    let revisionID: UUID
    let activeRevisionID: UUID?

    enum CodingKeys: String, CodingKey {
        case revisionID = "revision_id"
        case activeRevisionID = "active_revision_id"
    }
}

/// The couple's current canvas state as read by `get_widget_canvas`. The active
/// revision fields are nil when there is no visible drawing yet.
nonisolated struct WidgetCanvasState: Decodable, Sendable {
    let canvasID: UUID
    let activeRevisionID: UUID?
    let activeRevisionAuthorUserID: UUID?
    let payloadMediaAssetID: UUID?
    let bounds: WidgetDrawingBounds?
    let revisionCreatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case canvasID = "canvas_id"
        case activeRevisionID = "active_revision_id"
        case activeRevisionAuthorUserID = "active_revision_author_user_id"
        case payloadMediaAssetID = "payload_media_asset_id"
        case bounds
        case revisionCreatedAt = "revision_created_at"
    }
}

enum WidgetCanvasGatewayError: Error, Equatable {
    case emptyResponse
    case notFinalized
    /// The canvas advanced (the partner saved) before our submit landed.
    case parentRevisionConflict
}

/// Typed wrapper over the widget canvas RPCs and Storage upload.
nonisolated protocol WidgetCanvasGateway: Sendable {
    func getOrCreateCanvas() async throws -> WidgetCanvasReference

    func reserveDrawingUpload(
        coupleID: UUID,
        canvasID: UUID,
        revisionID: UUID,
        operation: WidgetCanvasClientOperation
    ) async throws -> PendingMediaUploadResponse

    func uploadPayload(bucket: String, storagePath: String, data: Data) async throws

    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput,
        operation: WidgetCanvasClientOperation
    ) async throws -> FinalizedMediaUploadResponse

    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission,
        operation: WidgetCanvasClientOperation
    ) async throws -> WidgetDrawingRevisionResult

    /// Reads the couple's current canvas + active revision. Returns nil when no
    /// canvas exists yet.
    func getCanvasState() async throws -> WidgetCanvasState?

    /// A short-lived signed URL for downloading a finalized payload object.
    func signedPayloadURL(mediaAssetID: UUID) async throws -> URL?

    /// A newest-first page of the canvas's revisions. Pass the last row's
    /// `createdAt`/`revisionID` as the cursor to load the next, older page.
    func listRevisions(
        canvasID: UUID,
        limit: Int,
        createdBefore: Date?,
        createdBeforeRevisionID: UUID?
    ) async throws -> [WidgetDrawingRevisionSummary]
}

actor LiveSupabaseWidgetCanvasGateway: WidgetCanvasGateway {
    nonisolated static let payloadMimeType = "application/octet-stream"
    nonisolated static let payloadFileExtension = "pkdrawing"
    nonisolated static let rendererVersion = "1"
    nonisolated static let validationVersion = "1"

    // Internal (not private) so the history-gateway extension in another file
    // can issue its own RPC.
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func getOrCreateCanvas() async throws -> WidgetCanvasReference {
        let rows: [WidgetCanvasReference] = try await client
            .rpc("get_or_create_widget_canvas", params: GetOrCreateWidgetCanvasRequest())
            .execute()
            .value
        guard let canvas = rows.first else {
            throw WidgetCanvasGatewayError.emptyResponse
        }
        return canvas
    }

    func reserveDrawingUpload(
        coupleID: UUID,
        canvasID: UUID,
        revisionID: UUID,
        operation: WidgetCanvasClientOperation
    ) async throws -> PendingMediaUploadResponse {
        let rows: [PendingMediaUploadResponse] = try await client
            .rpc(
                "create_pending_media_upload",
                params: CreatePendingWidgetDrawingUploadRequest(
                    operation: operation,
                    coupleID: coupleID,
                    canvasID: canvasID,
                    revisionID: revisionID
                )
            )
            .execute()
            .value
        guard let reservation = rows.first else {
            throw WidgetCanvasGatewayError.emptyResponse
        }
        return reservation
    }

    func uploadPayload(bucket: String, storagePath: String, data: Data) async throws {
        try await client.storage
            .from(bucket)
            .upload(
                storagePath,
                data: data,
                options: FileOptions(contentType: Self.payloadMimeType)
            )
    }

    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput,
        operation: WidgetCanvasClientOperation
    ) async throws -> FinalizedMediaUploadResponse {
        let rows: [FinalizedMediaUploadResponse] = try await client
            .rpc(
                "finalize_media_upload",
                params: FinalizeWidgetDrawingUploadRequest(input: input, operation: operation)
            )
            .execute()
            .value
        guard let finalized = rows.first else {
            throw WidgetCanvasGatewayError.emptyResponse
        }
        guard finalized.uploadStatus == "finalized" else {
            throw WidgetCanvasGatewayError.notFinalized
        }
        return finalized
    }

    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission,
        operation: WidgetCanvasClientOperation
    ) async throws -> WidgetDrawingRevisionResult {
        do {
            let rows: [WidgetDrawingRevisionResult] = try await client
                .rpc(
                    "submit_widget_drawing_revision",
                    params: SubmitWidgetDrawingRevisionRequest(submission: submission, operation: operation)
                )
                .execute()
                .value
            guard let result = rows.first else {
                throw WidgetCanvasGatewayError.emptyResponse
            }
            return result
        } catch where Self.isParentRevisionConflict(error) {
            throw WidgetCanvasGatewayError.parentRevisionConflict
        }
    }

    func getCanvasState() async throws -> WidgetCanvasState? {
        let rows: [WidgetCanvasState] = try await client
            .rpc("get_widget_canvas", params: GetOrCreateWidgetCanvasRequest())
            .execute()
            .value
        return rows.first
    }

    func signedPayloadURL(mediaAssetID: UUID) async throws -> URL? {
        let rows: [WidgetSignedURLAuthorization] = try await client
            .rpc("get_media_signed_url", params: WidgetSignedURLRequest(mediaAssetID: mediaAssetID))
            .execute()
            .value
        guard let authorization = rows.first else {
            return nil
        }
        return try await client.storage
            .from(authorization.bucket)
            .createSignedURL(path: authorization.storagePath, expiresIn: authorization.expiresInSeconds)
    }

    private static func isParentRevisionConflict(_ error: any Error) -> Bool {
        let description = String(describing: error)
        return description.contains("parent revision conflict") || description.contains("40001")
    }
}

// MARK: - Request payloads

nonisolated private struct GetOrCreateWidgetCanvasRequest: Encodable {
    let coupleID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case coupleID = "p_couple_id"
    }
}

nonisolated private struct WidgetSignedURLRequest: Encodable {
    let mediaAssetID: UUID
    let expiresInSeconds = 900

    enum CodingKeys: String, CodingKey {
        case mediaAssetID = "p_media_asset_id"
        case expiresInSeconds = "p_expires_in_seconds"
    }
}

nonisolated private struct WidgetSignedURLAuthorization: Decodable {
    let bucket: String
    let storagePath: String
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case bucket
        case storagePath = "storage_path"
        case expiresInSeconds = "expires_in_seconds"
    }
}

nonisolated private struct WidgetDrawingPathContext: Encodable {
    let canvasID: UUID

    enum CodingKeys: String, CodingKey {
        case canvasID = "canvas_id"
    }
}

nonisolated private struct CreatePendingWidgetDrawingUploadRequest: Encodable {
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let reservedParentKind = "widget_drawing_revision"
    let reservedParentID: UUID
    let uploadPurpose = "widget_drawing_payload"
    let mediaType = "drawing_payload"
    let fileExtension = LiveSupabaseWidgetCanvasGateway.payloadFileExtension
    let coupleID: UUID
    let pathContext: WidgetDrawingPathContext

    init(
        operation: WidgetCanvasClientOperation,
        coupleID: UUID,
        canvasID: UUID,
        revisionID: UUID
    ) {
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.reservedParentID = revisionID
        self.coupleID = coupleID
        self.pathContext = WidgetDrawingPathContext(canvasID: canvasID)
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
        case coupleID = "p_couple_id"
        case pathContext = "p_path_context"
    }
}

nonisolated private struct FinalizeWidgetDrawingUploadRequest: Encodable {
    let mediaAssetID: UUID
    let reservedByClientOperationID: UUID
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date
    let bucket: String
    let storagePath: String
    let reservedParentKind = "widget_drawing_revision"
    let reservedParentID: UUID
    let uploadPurpose = "widget_drawing_payload"
    let mediaType = "drawing_payload"
    let mimeType = LiveSupabaseWidgetCanvasGateway.payloadMimeType
    let byteSize: Int64
    let sha256Hex: String

    init(input: WidgetDrawingFinalizeInput, operation: WidgetCanvasClientOperation) {
        self.mediaAssetID = input.reservation.mediaAssetID
        self.reservedByClientOperationID = input.reservedByOperationID
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
        self.bucket = input.reservation.bucket
        self.storagePath = input.reservation.storagePath
        self.reservedParentID = input.revisionID
        self.byteSize = input.byteSize
        self.sha256Hex = input.sha256Hex
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
    }
}

nonisolated private struct SubmitWidgetDrawingRevisionRequest: Encodable {
    let canvasID: UUID
    let payloadMediaAssetID: UUID
    let parentRevisionID: UUID?
    let payloadBytes: Int64
    let uncompressedBytes: Int64
    let compression = "none"
    let strokeCount: Int
    let pointCount: Int
    let bounds: WidgetDrawingBounds
    let sha256Hex: String
    let clientDecodeValidatedAt: Date
    let clientRendererVersion = LiveSupabaseWidgetCanvasGateway.rendererVersion
    let clientValidationVersion = LiveSupabaseWidgetCanvasGateway.validationVersion
    let clientOperationID: UUID
    let clientID: UUID
    let clientSequence: Int64
    let localCreatedAt: Date

    init(submission: WidgetDrawingRevisionSubmission, operation: WidgetCanvasClientOperation) {
        self.canvasID = submission.canvasID
        self.payloadMediaAssetID = submission.payloadMediaAssetID
        self.parentRevisionID = submission.parentRevisionID
        self.payloadBytes = submission.payloadBytes
        self.uncompressedBytes = submission.payloadBytes
        self.strokeCount = submission.strokeCount
        self.pointCount = submission.pointCount
        self.bounds = submission.bounds
        self.sha256Hex = submission.sha256Hex
        self.clientDecodeValidatedAt = submission.clientDecodeValidatedAt
        self.clientOperationID = operation.id
        self.clientID = operation.clientID
        self.clientSequence = operation.clientSequence
        self.localCreatedAt = operation.localCreatedAt
    }

    enum CodingKeys: String, CodingKey {
        case canvasID = "p_canvas_id"
        case payloadMediaAssetID = "p_payload_media_asset_id"
        case parentRevisionID = "p_parent_revision_id"
        case payloadBytes = "p_payload_bytes"
        case uncompressedBytes = "p_uncompressed_bytes"
        case compression = "p_compression"
        case strokeCount = "p_stroke_count"
        case pointCount = "p_point_count"
        case bounds = "p_bounds"
        case sha256Hex = "p_sha256_hex"
        case clientDecodeValidatedAt = "p_client_decode_validated_at"
        case clientRendererVersion = "p_client_renderer_version"
        case clientValidationVersion = "p_client_validation_version"
        case clientOperationID = "p_client_operation_id"
        case clientID = "p_client_id"
        case clientSequence = "p_client_sequence"
        case localCreatedAt = "p_local_created_at"
    }

    // `p_parent_revision_id` has no SQL default, so the first revision must send
    // an explicit `null`. The synthesized encoder would omit a nil optional, so
    // encode every key explicitly.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canvasID, forKey: .canvasID)
        try container.encode(payloadMediaAssetID, forKey: .payloadMediaAssetID)
        try container.encode(parentRevisionID, forKey: .parentRevisionID)
        try container.encode(payloadBytes, forKey: .payloadBytes)
        try container.encode(uncompressedBytes, forKey: .uncompressedBytes)
        try container.encode(compression, forKey: .compression)
        try container.encode(strokeCount, forKey: .strokeCount)
        try container.encode(pointCount, forKey: .pointCount)
        try container.encode(bounds, forKey: .bounds)
        try container.encode(sha256Hex, forKey: .sha256Hex)
        try container.encode(clientDecodeValidatedAt, forKey: .clientDecodeValidatedAt)
        try container.encode(clientRendererVersion, forKey: .clientRendererVersion)
        try container.encode(clientValidationVersion, forKey: .clientValidationVersion)
        try container.encode(clientOperationID, forKey: .clientOperationID)
        try container.encode(clientID, forKey: .clientID)
        try container.encode(clientSequence, forKey: .clientSequence)
        try container.encode(localCreatedAt, forKey: .localCreatedAt)
    }
}
