import Foundation

/// Sends the inviter's first drawing to their first day draft, for the widget drawing
/// screen in place of the couple's uploader. The screen still saves the drawing on this
/// phone first and shows it on the person's own widget.
///
/// It uses the same "not sent yet" marker as the couple's uploader
/// (`WidgetPendingUploadStore.shared`), so a drawing never gets lost between the two:
/// the invite screen retries it here while the person waits, and if the partner joins
/// before it went out, the paired widget sync sends it to the couple's canvas instead.
/// Once paired, the server refuses it here (`23505`), so the two never both send it.
/// The marker says it is a first day drawing (`isFirstDay`), which an ended
/// relationship's purge keeps, since it belongs to no couple.
///
/// Uploads run one at a time, and a queued upload whose drawing was replaced by a
/// newer save is skipped.
actor FirstDayDrawingUploadService: WidgetCanvasUploading {
    private let gateway: any FirstDayGateway
    private let operationFactory: any WidgetCanvasClientOperationProviding
    private let pendingStore: WidgetPendingUploadStore
    private let localStore: any WidgetCanvasManaging
    private var lastUpload: Task<Void, Never>?
    private var deliveredContentHash: String?

    init(
        gateway: any FirstDayGateway,
        operationFactory: any WidgetCanvasClientOperationProviding = WidgetCanvasClientOperationFactory.shared,
        pendingStore: WidgetPendingUploadStore = .shared,
        localStore: any WidgetCanvasManaging = WidgetCanvasService.shared
    ) {
        self.gateway = gateway
        self.operationFactory = operationFactory
        self.pendingStore = pendingStore
        self.localStore = localStore
    }

    var hasPendingUpload: Bool {
        pendingStore.hasPending
    }

    func markPending(_ payload: WidgetDrawingUploadPayload) -> WidgetPendingUploadSnapshot? {
        let previous = pendingStore.pendingSnapshot
        pendingStore.markPending(payload, contentHash: Self.sha256Hex(of: payload.drawingData), isFirstDay: true)
        return previous
    }

    func restorePending(_ previous: WidgetPendingUploadSnapshot?, replacing payload: WidgetDrawingUploadPayload) {
        pendingStore.restore(previous, replacingContentHash: Self.sha256Hex(of: payload.drawingData))
    }

    func send(_ payload: WidgetDrawingUploadPayload) async -> WidgetDrawingDelivery {
        do {
            return try await uploadSerially(payload)
        } catch {
            // The marker stays, so the drawing goes out on a later retry.
            return .waiting
        }
    }

    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws {
        _ = try await uploadSerially(payload)
    }

    /// Sends the first drawing that is saved on this phone but not on the server yet.
    /// Returns false while it still waits.
    @discardableResult
    func retryPending() async -> Bool {
        guard let snapshot = pendingStore.pendingSnapshot else {
            return true
        }
        guard snapshot.isFirstDay else {
            // Not the first drawing, so the couple's uploader owns it.
            return false
        }
        guard let drawingData = await localStore.loadSavedDrawing(),
              Self.sha256Hex(of: drawingData) == snapshot.contentHash
        else {
            // The marker describes a drawing that is no longer on this phone.
            pendingStore.clearPending(snapshot.contentHash)
            return true
        }
        do {
            try await uploadPending(snapshot.uploadPayload(with: drawingData))
            return true
        } catch {
            return false
        }
    }

    private func uploadSerially(_ payload: WidgetDrawingUploadPayload) async throws -> WidgetDrawingDelivery {
        let contentHash = Self.sha256Hex(of: payload.drawingData)
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
            return deliveredContentHash == contentHash ? .delivered : .replaced
        }
        guard pending.contentHash == contentHash else {
            return .replaced
        }
        pendingStore.recordAttempt(contentHash)
        try await upload(payload, contentHash: contentHash)
        pendingStore.clearPending(contentHash)
        deliveredContentHash = contentHash
        await MainActor.run {
            NotificationCenter.default.post(name: .paeoniaWidgetUploadDidFinish, object: nil)
        }
        return .delivered
    }

    /// Reserve, upload, finalize, then save on the draft.
    private func upload(_ payload: WidgetDrawingUploadPayload, contentHash: String) async throws {
        // ponytail: no saved progress, so a retry reserves a new upload and the server
        // replaces the draft's drawing. Save progress like the couple's uploader if
        // retries get frequent.
        let revisionID = UUID()
        let reserveOperation = await operationFactory.makeOperation()
        let reservation = try await gateway.reserveDrawingUpload(revisionID: revisionID, operation: reserveOperation)
        let storageID = try await gateway.uploadDrawingPayload(reservation: reservation, data: payload.drawingData)
        try await gateway.finalizeDrawingUpload(
            WidgetDrawingFinalizeInput(
                reservation: reservation,
                storageID: storageID,
                revisionID: revisionID,
                reservedByOperationID: reserveOperation.id,
                byteSize: Int64(payload.drawingData.count),
                sha256Hex: contentHash
            ),
            operation: await operationFactory.makeOperation()
        )
        try await gateway.saveDrawing(
            payload,
            mediaAssetID: reservation.mediaAssetID,
            operation: await operationFactory.makeOperation()
        )
    }

    static func sha256Hex(of data: Data) -> String {
        WidgetCanvasUploadService.sha256Hex(of: data)
    }
}
