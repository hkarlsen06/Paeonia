import Foundation
import Supabase

/// One revision row from `get_widget_drawing_revisions`, trimmed to what the
/// history timeline needs. The RPC returns *every* revision but nulls the
/// payload fields for ones that are deleted, hidden, or not finalized, so
/// `payloadMediaAssetID != nil` is the single "this is a showable drawing"
/// signal.
nonisolated struct WidgetDrawingRevisionSummary: Decodable, Sendable {
    let revisionID: UUID
    let authorUserID: UUID?
    let payloadMediaAssetID: UUID?
    let bounds: WidgetDrawingBounds?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case revisionID = "revision_id"
        case authorUserID = "author_user_id"
        case payloadMediaAssetID = "payload_media_asset_id"
        case bounds
        case createdAt = "created_at"
    }
}

extension LiveSupabaseWidgetCanvasGateway {
    func listRevisions(
        canvasID: UUID,
        limit: Int,
        createdBefore: Date?,
        createdBeforeRevisionID: UUID?
    ) async throws -> [WidgetDrawingRevisionSummary] {
        try await client
            .rpc(
                "get_widget_drawing_revisions",
                params: ListWidgetDrawingRevisionsRequest(
                    canvasID: canvasID,
                    limit: limit,
                    createdBefore: createdBefore,
                    createdBeforeRevisionID: createdBeforeRevisionID
                )
            )
            .execute()
            .value
    }
}

/// Used when no Supabase client is configured (previews, signed-out states).
/// History reads resolve to "no canvas / no drawings" instead of erroring.
nonisolated struct NoOpWidgetCanvasGateway: WidgetCanvasGateway {
    func getOrCreateCanvas() throws -> WidgetCanvasReference {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func reserveDrawingUpload(
        coupleID: UUID, canvasID: UUID, revisionID: UUID, operation: WidgetCanvasClientOperation
    ) throws -> PendingMediaUploadResponse {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func uploadPayload(bucket: String, storagePath: String, data: Data) {}
    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput, operation: WidgetCanvasClientOperation
    ) throws -> FinalizedMediaUploadResponse {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission, operation: WidgetCanvasClientOperation
    ) throws -> WidgetDrawingRevisionResult {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func getCanvasState() -> WidgetCanvasState? { nil }
    func signedPayloadURL(mediaAssetID: UUID) -> URL? { nil }
    func listRevisions(
        canvasID: UUID, limit: Int, createdBefore: Date?, createdBeforeRevisionID: UUID?
    ) -> [WidgetDrawingRevisionSummary] { [] }
}

nonisolated private struct ListWidgetDrawingRevisionsRequest: Encodable {
    let canvasID: UUID
    let limit: Int
    let createdBefore: Date?
    let createdBeforeRevisionID: UUID?

    // Nil cursor fields are omitted, so the RPC sees its NULL defaults and its
    // "both-or-neither cursor" check is satisfied on the first (uncursored) page.
    enum CodingKeys: String, CodingKey {
        case canvasID = "p_canvas_id"
        case limit = "p_limit"
        case createdBefore = "p_created_before"
        case createdBeforeRevisionID = "p_created_before_revision_id"
    }
}
