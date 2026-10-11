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

/// How a send ended, as far as the person is concerned.
nonisolated enum WidgetDrawingDelivery: Equatable, Sendable {
    /// The server has the drawing, so the partner gets it.
    case delivered
    /// The upload failed (usually no network). The drawing stays marked as not
    /// sent and goes out on a later sync.
    case waiting
    /// A newer drawing was saved before this one started uploading, so this
    /// one is skipped.
    case replaced
}

extension Notification.Name {
    /// Posted on the main thread when a drawing that was waiting to be sent
    /// reached the server.
    nonisolated static let paeoniaWidgetUploadDidFinish = Notification.Name("paeonia.widgetCanvas.uploadDidFinish")
}

/// Uploads a saved drawing to the shared backend so the partner can receive it.
nonisolated protocol WidgetCanvasUploading: Sendable {
    /// Marks the drawing as saved here but not on the server yet. Call it before
    /// the drawing is shown locally, so no sync can pull an older drawing over
    /// it. Returns the marker it replaced, for `restorePending`.
    func markPending(_ payload: WidgetDrawingUploadPayload) async -> WidgetPendingUploadSnapshot?

    /// Puts back the marker from before `markPending` when showing the drawing
    /// locally failed, so an older unsent drawing is not forgotten.
    func restorePending(_ previous: WidgetPendingUploadSnapshot?, replacing payload: WidgetDrawingUploadPayload) async

    /// Sends a drawing and reports how it went. The upload runs on a task that
    /// outlives the drawing screen, so leaving the screen does not cancel it.
    func send(_ payload: WidgetDrawingUploadPayload) async -> WidgetDrawingDelivery

    /// Retries an already-pending local save and clears pending state only
    /// after the server confirms it.
    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws

    /// True while a saved drawing has not reached the server.
    var hasPendingUpload: Bool { get async }
}

extension WidgetCanvasUploading {
    func markPending(_: WidgetDrawingUploadPayload) -> WidgetPendingUploadSnapshot? { nil }
    func restorePending(_: WidgetPendingUploadSnapshot?, replacing _: WidgetDrawingUploadPayload) {}
    var hasPendingUpload: Bool { false }
}

/// Orchestrates the canonical upload pipeline: resolve the couple's canvas,
/// reserve + upload + finalize the `.pkdrawing` media asset, then submit the
/// revision. Retries once if the partner advanced the canvas mid-flight.
///
/// Uploads run one at a time. Two quick sends could otherwise finish in the
/// wrong order and leave the older drawing on the partner's widget, and the
/// sync's retry could upload the same drawing twice. A queued upload whose
/// drawing was replaced by a newer save is skipped.
actor WidgetCanvasUploadService: WidgetCanvasUploading {
    private let gateway: any WidgetCanvasGateway
    private let operationFactory: any WidgetCanvasClientOperationProviding
    private let pendingStore: WidgetPendingUploadStore
    private var lastUpload: Task<Void, Never>?
    private var deliveredContentHash: String?

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

    var hasPendingUpload: Bool {
        pendingStore.hasPending
    }

    func markPending(_ payload: WidgetDrawingUploadPayload) -> WidgetPendingUploadSnapshot? {
        let previous = pendingStore.pendingSnapshot
        pendingStore.markPending(payload, contentHash: Self.sha256Hex(of: payload.drawingData))
        return previous
    }

    func restorePending(_ previous: WidgetPendingUploadSnapshot?, replacing payload: WidgetDrawingUploadPayload) {
        pendingStore.restore(previous, replacingContentHash: Self.sha256Hex(of: payload.drawingData))
    }

    /// Call `markPending` first. A drawing that is not (or no longer) the one
    /// marked as not sent is reported as replaced and not uploaded.
    func send(_ payload: WidgetDrawingUploadPayload) async -> WidgetDrawingDelivery {
        let contentHash = Self.sha256Hex(of: payload.drawingData)
        do {
            return try await uploadSerially(payload, contentHash: contentHash)
        } catch {
            // Keep the marker so newer local work is not overwritten before it
            // reaches the server. A later sync retries it.
            #if DEBUG
            logger.error("Widget drawing upload failed: \(String(describing: error))")
            #endif
            return .waiting
        }
    }

    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws {
        _ = try await uploadSerially(payload, contentHash: Self.sha256Hex(of: payload.drawingData))
    }

    /// Waits for the upload before it, then uploads only if this drawing is
    /// still the one marked as not sent. The unstructured task keeps a strong
    /// reference to the actor, so the upload finishes even after the drawing
    /// screen goes away. Cancelling the caller (sign-out or a privacy purge
    /// stopping the sync) cancels the upload too. The next upload still waits
    /// until this one has stopped, so two never overlap.
    private func uploadSerially(
        _ payload: WidgetDrawingUploadPayload,
        contentHash: String
    ) async throws -> WidgetDrawingDelivery {
        let previous = lastUpload
        let upload = Task { () async throws -> WidgetDrawingDelivery in
            await previous?.value
            try Task.checkCancellation()
            return try await self.uploadIfStillPending(payload, contentHash: contentHash)
        }
        lastUpload = Task { _ = await upload.result }
        return try await withTaskCancellationHandler {
            try await upload.value
        } onCancel: {
            upload.cancel()
        }
    }

    private func uploadIfStillPending(
        _ payload: WidgetDrawingUploadPayload,
        contentHash: String
    ) async throws -> WidgetDrawingDelivery {
        guard let pending = pendingStore.pendingSnapshot else {
            // Either an earlier upload (for example the sync's retry) already
            // sent this drawing, or a newer one was sent after it.
            return deliveredContentHash == contentHash ? .delivered : .replaced
        }
        guard pending.contentHash == contentHash else {
            return .replaced
        }
        pendingStore.recordAttempt(contentHash)
        try await upload(payload, resumingFrom: pending.progress) { progress in
            pendingStore.saveProgress(progress, contentHash: contentHash)
        }
        pendingStore.clearPending(contentHash)
        deliveredContentHash = contentHash
        await MainActor.run {
            NotificationCenter.default.post(name: .paeoniaWidgetUploadDidFinish, object: nil)
        }
        return .delivered
    }

    /// Uploads with fresh IDs and keeps no progress. Retries go through
    /// `uploadPending`, which saves progress with the pending marker.
    func upload(_ payload: WidgetDrawingUploadPayload) async throws {
        try await upload(payload, resumingFrom: nil) { _ in }
    }

    /// Runs reserve, upload, finalize, and submit, skipping the steps `saved`
    /// already finished. Every ID and request is saved through `persist` before
    /// it is sent, so a retry after a lost response replays the same operation.
    private func upload(
        _ payload: WidgetDrawingUploadPayload,
        resumingFrom saved: WidgetUploadProgress?,
        persist: (WidgetUploadProgress?) -> Void
    ) async throws {
        var progress: WidgetUploadProgress
        if let saved {
            progress = saved
        } else {
            progress = WidgetUploadProgress(
                revisionID: UUID(),
                reserveOperation: await operationFactory.makeOperation(),
                finalizeOperation: await operationFactory.makeOperation()
            )
            persist(progress)
        }

        let canvas = try await gateway.getOrCreateCanvas()
        if !progress.isFinalized {
            do {
                try await reserveUploadAndFinalize(payload, canvas: canvas, progress: &progress, persist: persist)
            } catch let error where Self.isGoneReservation(error) {
                // The reservation expired or its object is gone. Nothing was
                // submitted for it, so the next retry starts over with new IDs.
                persist(nil)
                throw error
            }
        }

        if progress.submission == nil {
            guard let mediaAssetID = progress.reservation?.mediaAssetID else {
                throw WidgetCanvasGatewayError.emptyResponse
            }
            progress.submission = Self.submission(for: payload, canvas: canvas, mediaAssetID: mediaAssetID)
            progress.submitOperation = await operationFactory.makeOperation()
            persist(progress)
        }
        try await submit(progress: &progress, persist: persist)
    }

    /// Reserves, uploads, and finalizes the canonical `.pkdrawing` media asset.
    /// Replaying the saved reserve operation returns the same asset with a fresh
    /// upload URL, and finalize accepts a second upload of the same bytes.
    private func reserveUploadAndFinalize(
        _ payload: WidgetDrawingUploadPayload,
        canvas: WidgetCanvasReference,
        progress: inout WidgetUploadProgress,
        persist: (WidgetUploadProgress?) -> Void
    ) async throws {
        if progress.reservation == nil || progress.storageID == nil {
            let reservation = try await gateway.reserveDrawingUpload(
                coupleID: canvas.coupleID,
                canvasID: canvas.canvasID,
                revisionID: progress.revisionID,
                operation: progress.reserveOperation
            )
            progress.reservation = WidgetUploadProgress.Reservation(reservation)
            persist(progress)
            progress.storageID = try await gateway.uploadPayload(
                reservation: reservation,
                data: payload.drawingData
            )
            persist(progress)
        }

        guard let reservation = progress.reservation, let storageID = progress.storageID else {
            throw WidgetCanvasGatewayError.emptyResponse
        }
        _ = try await gateway.finalizeDrawingUpload(
            WidgetDrawingFinalizeInput(
                reservation: reservation.mediaUploadReservation,
                storageID: storageID,
                revisionID: progress.revisionID,
                reservedByOperationID: progress.reserveOperation.id,
                byteSize: Int64(payload.drawingData.count),
                sha256Hex: Self.sha256Hex(of: payload.drawingData)
            ),
            operation: progress.finalizeOperation
        )
        progress.isFinalized = true
        persist(progress)
    }

    private func submit(
        progress: inout WidgetUploadProgress,
        persist: (WidgetUploadProgress?) -> Void
    ) async throws {
        guard var submission = progress.submission, let operation = progress.submitOperation else {
            throw WidgetCanvasGatewayError.emptyResponse
        }
        do {
            _ = try await gateway.submitRevision(submission, operation: operation)
        } catch WidgetCanvasGatewayError.parentRevisionConflict {
            // The partner saved a revision before ours landed. Re-anchor to the
            // new active revision and submit the same finalized asset once more.
            // A changed request needs a new operation; it is saved before it is
            // sent, so a lost response is replayed rather than repeated.
            let refreshed = try await gateway.getOrCreateCanvas()
            submission.parentRevisionID = refreshed.activeRevisionID
            let retryOperation = await operationFactory.makeOperation()
            progress.submission = submission
            progress.submitOperation = retryOperation
            persist(progress)
            _ = try await gateway.submitRevision(submission, operation: retryOperation)
        }
    }

    private static func submission(
        for payload: WidgetDrawingUploadPayload,
        canvas: WidgetCanvasReference,
        mediaAssetID: UUID
    ) -> WidgetDrawingRevisionSubmission {
        WidgetDrawingRevisionSubmission(
            canvasID: canvas.canvasID,
            payloadMediaAssetID: mediaAssetID,
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
            sha256Hex: sha256Hex(of: payload.drawingData),
            clientDecodeValidatedAt: Date()
        )
    }

    /// `22023` from reserve or finalize: the reservation expired or its
    /// storage object is gone, so the saved IDs cannot be used again.
    private static func isGoneReservation(_ error: any Error) -> Bool {
        guard case let .server(code, _) = error as? PaeoniaConvexError else {
            return false
        }
        return code == "22023"
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Used when no Convex client is configured; saving stays local-only.
nonisolated struct NoOpWidgetCanvasUpload: WidgetCanvasUploading {
    func send(_: WidgetDrawingUploadPayload) -> WidgetDrawingDelivery { .delivered }
    func uploadPending(_: WidgetDrawingUploadPayload) throws {}
}

nonisolated enum WidgetCanvasUploadServiceFactory {
    /// One uploader for the app, shared by the drawing screen and the sync's
    /// retry, so their uploads queue behind each other.
    static let shared: any WidgetCanvasUploading = makeLive()

    static func makeDefault() -> any WidgetCanvasUploading {
        shared
    }

    private static func makeLive() -> any WidgetCanvasUploading {
        guard let client = try? PaeoniaConvexClientProvider.shared.client() else {
            return NoOpWidgetCanvasUpload()
        }

        return WidgetCanvasUploadService(
            gateway: LiveWidgetCanvasGateway(client: client),
            operationFactory: WidgetCanvasClientOperationFactory.shared
        )
    }
}
