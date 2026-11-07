import CoreGraphics
import Foundation

/// The calls behind the inviter's first day draft: the start date, the answer to the
/// first question, and the first drawing. Every write refuses a person who is already paired.
nonisolated protocol FirstDayGateway: Sendable {
    /// Creates the draft and picks its question the first time, then returns it.
    func startDraft() async throws -> FirstDayDraft

    func setStartedOn(_ startedOn: String?, operation: SyncClientOperation) async throws

    func saveAnswer(questionVersionID: UUID, text: String, operation: SyncClientOperation) async throws

    func reserveDrawingUpload(revisionID: UUID, operation: SyncClientOperation) async throws -> MediaUploadReservation

    /// Uploads the payload bytes and returns the storage id for finalize.
    func uploadDrawingPayload(reservation: MediaUploadReservation, data: Data) async throws -> String

    func finalizeDrawingUpload(_ input: WidgetDrawingFinalizeInput, operation: SyncClientOperation) async throws

    func saveDrawing(
        _ payload: WidgetDrawingUploadPayload,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> FirstDayDrawingReference

    /// A short-lived URL for downloading the draft's drawing.
    func signedDrawingURL(mediaAssetID: UUID) async throws -> URL?
}

actor LiveFirstDayGateway: FirstDayGateway {
    private let client: PaeoniaConvexClient
    /// The drawing upload, finalize and download are the widget's own calls.
    private let widget: LiveWidgetCanvasGateway
    private let isSignedIn: PaeoniaSignedInCheck

    init(client: PaeoniaConvexClient, isSignedIn: @escaping PaeoniaSignedInCheck = PaeoniaSignedIn.live) {
        self.client = client
        widget = LiveWidgetCanvasGateway(client: client)
        self.isSignedIn = isSignedIn
    }

    func startDraft() async throws -> FirstDayDraft {
        try await client.mutation("firstDay:start_first_day_draft")
    }

    func setStartedOn(_ startedOn: String?, operation: SyncClientOperation) async throws {
        // The start date is sent from the pending operations. Failing locally without a
        // session keeps it queued until the person is signed in again.
        try await PaeoniaSignedIn.require(isSignedIn)
        try await client.mutation(
            "firstDay:set_first_day_started_on",
            args: SetFirstDayStartedOnRequest(startedOn: startedOn, operation: operation)
        )
    }

    func saveAnswer(questionVersionID: UUID, text: String, operation: SyncClientOperation) async throws {
        try await client.mutation(
            "firstDay:save_first_day_answer",
            args: SaveFirstDayAnswerRequest(questionVersionID: questionVersionID, text: text, operation: operation)
        )
    }

    func reserveDrawingUpload(revisionID: UUID, operation: SyncClientOperation) async throws -> MediaUploadReservation {
        try await MediaUploader(client: client).reserve(
            .widgetDrawing(revisionID: revisionID, pathContext: .firstDayDraft),
            operation: operation
        )
    }

    func uploadDrawingPayload(reservation: MediaUploadReservation, data: Data) async throws -> String {
        try await widget.uploadPayload(reservation: reservation, data: data)
    }

    func finalizeDrawingUpload(_ input: WidgetDrawingFinalizeInput, operation: SyncClientOperation) async throws {
        try await widget.finalizeDrawingUpload(input, operation: operation)
    }

    func saveDrawing(
        _ payload: WidgetDrawingUploadPayload,
        mediaAssetID: UUID,
        operation: SyncClientOperation
    ) async throws -> FirstDayDrawingReference {
        try await client.mutation(
            "firstDay:save_first_day_drawing",
            args: SaveFirstDayDrawingRequest(payload: payload, mediaAssetID: mediaAssetID, operation: operation)
        )
    }

    func signedDrawingURL(mediaAssetID: UUID) async throws -> URL? {
        try await widget.signedPayloadURL(mediaAssetID: mediaAssetID)
    }
}

nonisolated enum FirstDayGatewayFactory {
    static func makeDefault() -> (any FirstDayGateway)? {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return nil
        }
        return LiveFirstDayGateway(client: client)
    }
}

// MARK: - Requests

nonisolated struct SetFirstDayStartedOnRequest: Encodable {
    let startedOn: String?
    let operation: SyncClientOperation

    enum CodingKeys: String, CodingKey {
        case startedOn = "p_started_on"
    }

    // `p_started_on` is required, so clearing the date sends an explicit null.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(startedOn, forKey: .startedOn)
        try ClientOperationFields(operation).encode(to: encoder)
    }
}

nonisolated struct SaveFirstDayAnswerRequest: Encodable {
    let questionVersionID: UUID
    let text: String
    let operation: SyncClientOperation

    enum CodingKeys: String, CodingKey {
        case questionVersionID = "p_question_version_id"
        case text = "p_text"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(questionVersionID, forKey: .questionVersionID)
        try container.encode(text, forKey: .text)
        try ClientOperationFields(operation).encode(to: encoder)
    }
}

/// The same payload description `widget:submit_widget_drawing_revision` takes, without
/// a canvas or a parent revision.
nonisolated struct SaveFirstDayDrawingRequest: Encodable {
    let payload: WidgetDrawingUploadPayload
    let mediaAssetID: UUID
    let operation: SyncClientOperation

    enum CodingKeys: String, CodingKey {
        case payloadMediaAssetID = "p_payload_media_asset_id"
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
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let byteCount = Int64(payload.drawingData.count)
        try container.encode(mediaAssetID, forKey: .payloadMediaAssetID)
        try container.encode(byteCount, forKey: .payloadBytes)
        try container.encode(byteCount, forKey: .uncompressedBytes)
        try container.encode("none", forKey: .compression)
        try container.encode(payload.strokeCount, forKey: .strokeCount)
        try container.encode(payload.pointCount, forKey: .pointCount)
        try container.encode(
            WidgetDrawingBounds(
                x: Double(payload.bounds.origin.x),
                y: Double(payload.bounds.origin.y),
                width: Double(payload.bounds.width),
                height: Double(payload.bounds.height),
                canvasSide: Double(payload.canvasSide),
                accessibilityText: payload.accessibilityText
            ),
            forKey: .bounds
        )
        try container.encode(WidgetCanvasUploadService.sha256Hex(of: payload.drawingData), forKey: .sha256Hex)
        try container.encode(operation.localCreatedAt, forKey: .clientDecodeValidatedAt)
        try container.encode(LiveWidgetCanvasGateway.rendererVersion, forKey: .clientRendererVersion)
        try container.encode(LiveWidgetCanvasGateway.validationVersion, forKey: .clientValidationVersion)
        try ClientOperationFields(operation).encode(to: encoder)
    }
}
