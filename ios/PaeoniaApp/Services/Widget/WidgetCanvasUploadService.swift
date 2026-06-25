import CoreGraphics
import CryptoKit
import Foundation
#if DEBUG
import OSLog
#endif

/// Everything the uploader needs about a saved drawing. The view model computes
/// the PencilKit-derived fields on the main actor so the uploader never touches
/// PencilKit off the main actor.
nonisolated struct WidgetDrawingUploadPayload: Sendable {
    let drawingData: Data
    let canvasSide: CGFloat
    let strokeCount: Int
    let pointCount: Int
    let bounds: CGRect
}

/// Uploads a saved drawing to the shared backend so the partner can receive it.
nonisolated protocol WidgetCanvasUploading: Sendable {
    /// Fire-and-forget: starts the upload on a task that outlives the drawing
    /// screen, so navigating back doesn't cancel an in-flight upload.
    func enqueueUpload(_ payload: WidgetDrawingUploadPayload) async

    /// Retries an already-pending local save and clears pending state only
    /// after server confirms it.
    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws
}

/// Orchestrates the canonical upload pipeline: resolve the couple's canvas,
/// reserve + upload + finalize the `.pkdrawing` media asset, then submit the
/// revision. Retries once if the partner advanced the canvas mid-flight.
actor WidgetCanvasUploadService: WidgetCanvasUploading {
    private let gateway: any WidgetCanvasGateway
    private let operationFactory: any WidgetCanvasClientOperationProviding
    private let pendingStore: WidgetPendingUploadStore

    #if DEBUG
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "no.paeonia.app",
        category: "WidgetUpload"
    )
    #endif

    init(
        gateway: any WidgetCanvasGateway,
        operationFactory: any WidgetCanvasClientOperationProviding,
        pendingStore: WidgetPendingUploadStore = .shared
    ) {
        self.gateway = gateway
        self.operationFactory = operationFactory
        self.pendingStore = pendingStore
    }

    // Unstructured task keeps a strong reference to the actor, so the upload runs
    // to completion even after the caller's task (the drawing screen) goes away.
    func enqueueUpload(_ payload: WidgetDrawingUploadPayload) {
        // Mark this drawing as not-yet-on-the-server so a sync can't pull an
        // older revision over it. Cleared only once the upload is confirmed.
        let contentHash = Self.sha256Hex(of: payload.drawingData)
        pendingStore.markPending(payload, contentHash: contentHash)

        Task {
            do {
                try await uploadPending(payload)
            } catch {
                // Leave the pending marker so newer local work isn't overwritten
                // before it reaches the server; a later retry or save clears it.
                #if DEBUG
                logger.error("Widget drawing upload failed: \(String(describing: error))")
                #endif
            }
        }
    }

    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws {
        let contentHash = Self.sha256Hex(of: payload.drawingData)
        pendingStore.recordAttempt(contentHash)
        try await upload(payload)
        pendingStore.clearPending(contentHash)
    }

    func upload(_ payload: WidgetDrawingUploadPayload) async throws {
        let canvas = try await gateway.getOrCreateCanvas()
        let asset = try await reserveUploadAndFinalize(payload, canvas: canvas)

        let submission = WidgetDrawingRevisionSubmission(
            canvasID: canvas.canvasID,
            payloadMediaAssetID: asset.mediaAssetID,
            parentRevisionID: canvas.activeRevisionID,
            payloadBytes: Int64(payload.drawingData.count),
            strokeCount: payload.strokeCount,
            pointCount: payload.pointCount,
            bounds: WidgetDrawingBounds(
                x: Double(payload.bounds.origin.x),
                y: Double(payload.bounds.origin.y),
                width: Double(payload.bounds.width),
                height: Double(payload.bounds.height),
                canvasSide: Double(payload.canvasSide)
            ),
            sha256Hex: asset.sha256Hex,
            clientDecodeValidatedAt: Date()
        )
        try await submit(submission, retryOnConflict: true)
    }

    /// Reserves, uploads, and finalizes the canonical `.pkdrawing` media asset.
    private func reserveUploadAndFinalize(
        _ payload: WidgetDrawingUploadPayload,
        canvas: WidgetCanvasReference
    ) async throws -> (mediaAssetID: UUID, sha256Hex: String) {
        let revisionID = UUID()
        let reserveOperation = await operationFactory.makeOperation()
        let reservation = try await gateway.reserveDrawingUpload(
            coupleID: canvas.coupleID,
            canvasID: canvas.canvasID,
            revisionID: revisionID,
            operation: reserveOperation
        )

        try await gateway.uploadPayload(
            bucket: reservation.bucket,
            storagePath: reservation.storagePath,
            data: payload.drawingData
        )

        let sha256Hex = Self.sha256Hex(of: payload.drawingData)
        let finalizeOperation = await operationFactory.makeOperation()
        _ = try await gateway.finalizeDrawingUpload(
            WidgetDrawingFinalizeInput(
                reservation: reservation,
                revisionID: revisionID,
                reservedByOperationID: reserveOperation.id,
                byteSize: Int64(payload.drawingData.count),
                sha256Hex: sha256Hex
            ),
            operation: finalizeOperation
        )

        return (reservation.mediaAssetID, sha256Hex)
    }

    private func submit(
        _ submission: WidgetDrawingRevisionSubmission,
        retryOnConflict: Bool
    ) async throws {
        let operation = await operationFactory.makeOperation()
        do {
            _ = try await gateway.submitRevision(submission, operation: operation)
        } catch WidgetCanvasGatewayError.parentRevisionConflict where retryOnConflict {
            // The partner saved a revision before ours landed. Re-anchor to the
            // new active revision and submit the same finalized asset once more.
            let refreshed = try await gateway.getOrCreateCanvas()
            var retried = submission
            retried.parentRevisionID = refreshed.activeRevisionID
            try await submit(retried, retryOnConflict: false)
        }
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Used when no Supabase client is configured; saving stays local-only.
nonisolated struct NoOpWidgetCanvasUpload: WidgetCanvasUploading {
    func enqueueUpload(_ payload: WidgetDrawingUploadPayload) {}
    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws {}
}

nonisolated enum WidgetCanvasUploadServiceFactory {
    static func makeDefault() -> any WidgetCanvasUploading {
        guard let client = try? PaeoniaSupabaseClientProvider.shared.client() else {
            return NoOpWidgetCanvasUpload()
        }

        return WidgetCanvasUploadService(
            gateway: LiveSupabaseWidgetCanvasGateway(client: client),
            operationFactory: WidgetCanvasClientOperationFactory.shared
        )
    }
}
