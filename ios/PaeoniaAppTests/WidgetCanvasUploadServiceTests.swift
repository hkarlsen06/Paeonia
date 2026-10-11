import CoreGraphics
import Foundation
import Testing
@testable import PaeoniaApp

struct WidgetCanvasUploadServiceTests {
    @Test func uploadRunsReserveUploadFinalizeSubmitInOrder() async throws {
        let gateway = WidgetCanvasGatewaySpy()
        let service = WidgetCanvasUploadService(
            gateway: gateway,
            operationFactory: WidgetCanvasOperationFactorySpy()
        )

        try await service.upload(Self.samplePayload)

        #expect(gateway.getOrCreateCount == 1)

        let reserve = try #require(gateway.reserveCalls.first)
        #expect(reserve.coupleID == gateway.canvas.coupleID)
        #expect(reserve.canvasID == gateway.canvas.canvasID)

        let upload = try #require(gateway.uploadCalls.first)
        #expect(upload.reservation.bucket == "widget-drawings")
        #expect(upload.payloadData == Self.samplePayload.drawingData)

        // The storage id the upload returned reaches finalize as `p_storage_id`.
        #expect(gateway.finalizeInputs.count == 1)
        #expect(gateway.finalizeInputs.first?.storageID == WidgetCanvasGatewaySpy.storageID)
        #expect(gateway.finalizeInputs.first?.reservation == upload.reservation)
        #expect(gateway.callOrder == ["reserve", "upload", "finalize", "submit"])

        let submission = try #require(gateway.submitCalls.first)
        #expect(submission.canvasID == gateway.canvas.canvasID)
        #expect(submission.parentRevisionID == gateway.canvas.activeRevisionID)
        #expect(submission.payloadBytes == Int64(Self.samplePayload.drawingData.count))
        #expect(submission.strokeCount == Self.samplePayload.strokeCount)
        #expect(submission.pointCount == Self.samplePayload.pointCount)
        #expect(submission.bounds.canvasSide == Double(Self.samplePayload.canvasSide))
    }

    @Test func submitConflictReanchorsToRefreshedParentAndRetriesOnce() async throws {
        let gateway = WidgetCanvasGatewaySpy()
        gateway.conflictOnFirstSubmit = true
        gateway.refreshedCanvas = WidgetCanvasReference(
            canvasID: gateway.canvas.canvasID,
            coupleID: gateway.canvas.coupleID,
            activeRevisionID: UUID()
        )
        let service = WidgetCanvasUploadService(
            gateway: gateway,
            operationFactory: WidgetCanvasOperationFactorySpy()
        )

        try await service.upload(Self.samplePayload)

        // First submit conflicts, second submit lands.
        #expect(gateway.submitCalls.count == 2)
        // Re-fetched the canvas to re-anchor the parent revision.
        #expect(gateway.getOrCreateCount == 2)
        #expect(gateway.submitCalls.last?.parentRevisionID == gateway.refreshedCanvas?.activeRevisionID)
        // Did not re-upload the payload for the retry.
        #expect(gateway.uploadCalls.count == 1)
    }

    /// Uploads run one at a time, and a queued upload whose drawing was
    /// replaced by a newer save is skipped. Without this, three quick sends
    /// uploaded all three and could land in the wrong order.
    @Test func uploadsRunOneAtATimeAndTheNewestDrawingWins() async throws {
        let gateway = WidgetCanvasGatewaySpy()
        gateway.holdFirstSubmit = true
        let pendingStore = WidgetPendingUploadStore(
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
        )
        let service = WidgetCanvasUploadService(
            gateway: gateway,
            operationFactory: WidgetCanvasOperationFactorySpy(),
            pendingStore: pendingStore
        )
        let first = Self.payload(byte: 0x01)
        let second = Self.payload(byte: 0x02)
        let third = Self.payload(byte: 0x03)

        _ = await service.markPending(first)
        let firstSend = Task { await service.send(first) }
        while !gateway.isSubmitHeld {
            await Task.yield()
        }

        _ = await service.markPending(second)
        let secondSend = Task { await service.send(second) }
        _ = await service.markPending(third)
        let thirdSend = Task { await service.send(third) }
        gateway.releaseHeldSubmit()

        #expect(await firstSend.value == .delivered)
        #expect(await secondSend.value == .replaced)
        #expect(await thirdSend.value == .delivered)
        #expect(gateway.uploadCalls.map(\.payloadData) == [first.drawingData, third.drawingData])
        #expect(!pendingStore.hasPending)
    }

    @Test func failedSendKeepsTheDrawingMarkedAsNotSent() async throws {
        let gateway = WidgetCanvasGatewaySpy()
        gateway.failSubmit = true
        let pendingStore = WidgetPendingUploadStore(
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
        )
        let service = WidgetCanvasUploadService(
            gateway: gateway,
            operationFactory: WidgetCanvasOperationFactorySpy(),
            pendingStore: pendingStore
        )

        _ = await service.markPending(Self.samplePayload)
        let delivery = await service.send(Self.samplePayload)

        #expect(delivery == .waiting)
        #expect(pendingStore.hasPending)
    }

    @Test func restoringAfterAFailedLocalSaveBringsBackTheOlderUnsentDrawing() async throws {
        let pendingStore = WidgetPendingUploadStore(
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
        )
        let service = WidgetCanvasUploadService(
            gateway: WidgetCanvasGatewaySpy(),
            operationFactory: WidgetCanvasOperationFactorySpy(),
            pendingStore: pendingStore
        )
        let older = Self.payload(byte: 0x0A)
        let newer = Self.payload(byte: 0x0B)
        _ = await service.markPending(older)

        let previous = await service.markPending(newer)
        await service.restorePending(previous, replacing: newer)

        #expect(pendingStore.pendingSnapshot?.contentHash == WidgetCanvasUploadService.sha256Hex(of: older.drawingData))
    }

    /// The server applied the submit but the response was lost. The retry must
    /// replay the same operation for the same asset, not reserve a new revision.
    @Test func retryAfterALostSubmitResponseReplaysTheSameOperation() async throws {
        let gateway = WidgetCanvasGatewaySpy()
        gateway.loseFirstSubmitResponse = true
        let (service, pendingStore) = Self.makeService(gateway: gateway)

        _ = await service.markPending(Self.samplePayload)
        #expect(await service.send(Self.samplePayload) == .waiting)
        try await service.uploadPending(Self.samplePayload)

        #expect(gateway.reserveCalls.count == 1)
        #expect(gateway.uploadCalls.count == 1)
        #expect(gateway.finalizeInputs.count == 1)
        #expect(gateway.submitCalls.count == 2)
        #expect(gateway.submitOperationIDs[0] == gateway.submitOperationIDs[1])
        #expect(gateway.submitCalls[0] == gateway.submitCalls[1])
        #expect(!pendingStore.hasPending)
    }

    /// A failed upload retries with the same reservation and operation.
    @Test func retryAfterAFailedUploadReusesTheReservation() async throws {
        let gateway = WidgetCanvasGatewaySpy()
        gateway.failFirstUpload = true
        let (service, pendingStore) = Self.makeService(gateway: gateway)

        _ = await service.markPending(Self.samplePayload)
        #expect(await service.send(Self.samplePayload) == .waiting)
        try await service.uploadPending(Self.samplePayload)

        #expect(gateway.reserveCalls.count == 2)
        #expect(gateway.reserveCalls[0].revisionID == gateway.reserveCalls[1].revisionID)
        #expect(gateway.reserveOperationIDs[0] == gateway.reserveOperationIDs[1])
        #expect(gateway.submitCalls.count == 1)
        #expect(!pendingStore.hasPending)
    }

    /// An expired reservation cannot be replayed. Nothing was submitted for it,
    /// so the retry starts over with new IDs.
    @Test func expiredReservationStartsOverWithNewIDs() async throws {
        let gateway = WidgetCanvasGatewaySpy()
        gateway.expireFirstReserve = true
        let (service, _) = Self.makeService(gateway: gateway)

        _ = await service.markPending(Self.samplePayload)
        #expect(await service.send(Self.samplePayload) == .waiting)
        try await service.uploadPending(Self.samplePayload)

        #expect(gateway.reserveCalls.count == 2)
        #expect(gateway.reserveCalls[0].revisionID != gateway.reserveCalls[1].revisionID)
        #expect(gateway.reserveOperationIDs[0] != gateway.reserveOperationIDs[1])
        #expect(gateway.submitCalls.count == 1)
    }

    /// Sign-out and the privacy purge cancel the sync that retries an upload and
    /// wait for it. The upload used to keep running, so they waited for the network.
    @Test(.timeLimit(.minutes(1))) func cancellingARetryStopsItsUpload() async throws {
        let gateway = WidgetCanvasGatewaySpy()
        gateway.hangFirstSubmitUntilCancelled = true
        let (service, pendingStore) = Self.makeService(gateway: gateway)
        _ = await service.markPending(Self.samplePayload)

        let retry = Task { try await service.uploadPending(Self.samplePayload) }
        while !gateway.isSubmitHeld {
            await Task.yield()
        }
        retry.cancel()

        await #expect(throws: CancellationError.self) { try await retry.value }
        #expect(pendingStore.hasPending)

        // The next upload is not blocked, and it replays the saved submit.
        try await service.uploadPending(Self.samplePayload)
        #expect(gateway.submitOperationIDs.count == 2)
        #expect(gateway.submitOperationIDs[0] == gateway.submitOperationIDs[1])
        #expect(!pendingStore.hasPending)
    }

    private static func makeService(
        gateway: WidgetCanvasGatewaySpy
    ) -> (WidgetCanvasUploadService, WidgetPendingUploadStore) {
        let pendingStore = WidgetPendingUploadStore(
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
        )
        let service = WidgetCanvasUploadService(
            gateway: gateway,
            operationFactory: WidgetCanvasOperationFactorySpy(),
            pendingStore: pendingStore
        )
        return (service, pendingStore)
    }

    private static func payload(byte: UInt8) -> WidgetDrawingUploadPayload {
        WidgetDrawingUploadPayload(
            drawingData: Data([byte, byte, byte]),
            canvasSide: 300,
            strokeCount: 1,
            pointCount: 2,
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
        )
    }

    private static let samplePayload = WidgetDrawingUploadPayload(
        drawingData: Data([0x01, 0x02, 0x03, 0x04]),
        canvasSide: 300,
        strokeCount: 2,
        pointCount: 12,
        bounds: CGRect(x: 0, y: 0, width: 100, height: 120)
    )
}

private nonisolated final class WidgetCanvasOperationFactorySpy:
    WidgetCanvasClientOperationProviding, @unchecked Sendable {
    private var count = 0

    func makeOperation() -> WidgetCanvasClientOperation {
        count += 1
        return WidgetCanvasClientOperation(
            id: UUID(),
            clientID: UUID(),
            clientSequence: Int64(count),
            localCreatedAt: Date()
        )
    }
}

private nonisolated final class WidgetCanvasGatewaySpy: WidgetCanvasGateway, @unchecked Sendable {
    static let storageID = "kg2storage-id"

    let canvas = WidgetCanvasReference(
        canvasID: UUID(),
        coupleID: UUID(),
        activeRevisionID: UUID()
    )
    var refreshedCanvas: WidgetCanvasReference?
    var conflictOnFirstSubmit = false
    var failSubmit = false
    var holdFirstSubmit = false
    /// Like a network request, the first submit waits until its task is cancelled.
    var hangFirstSubmitUntilCancelled = false
    /// The server applies the first submit, but the response never arrives.
    var loseFirstSubmitResponse = false
    var failFirstUpload = false
    var expireFirstReserve = false
    private(set) var reserveOperationIDs: [UUID] = []
    private(set) var submitOperationIDs: [UUID] = []
    /// Like the server, a replayed reserve operation returns the same asset.
    private var reservedAssetIDs: [UUID: UUID] = [:]
    private var heldSubmit: CheckedContinuation<Void, Never>?
    private(set) var isSubmitHeld = false

    struct ReserveCall { let coupleID: UUID; let canvasID: UUID; let revisionID: UUID }
    struct UploadCall { let reservation: MediaUploadReservation; let payloadData: Data }

    private(set) var getOrCreateCount = 0
    private(set) var reserveCalls: [ReserveCall] = []
    private(set) var uploadCalls: [UploadCall] = []
    private(set) var finalizeInputs: [WidgetDrawingFinalizeInput] = []
    private(set) var callOrder: [String] = []
    private(set) var submitCalls: [WidgetDrawingRevisionSubmission] = []
    private var submitAttempts = 0

    func getOrCreateCanvas() -> WidgetCanvasReference {
        getOrCreateCount += 1
        if getOrCreateCount >= 2, let refreshedCanvas {
            return refreshedCanvas
        }
        return canvas
    }

    func reserveDrawingUpload(
        coupleID: UUID,
        canvasID: UUID,
        revisionID: UUID,
        operation: WidgetCanvasClientOperation
    ) throws -> MediaUploadReservation {
        callOrder.append("reserve")
        reserveCalls.append(ReserveCall(coupleID: coupleID, canvasID: canvasID, revisionID: revisionID))
        reserveOperationIDs.append(operation.id)
        if expireFirstReserve, reserveCalls.count == 1 {
            throw PaeoniaConvexError.server(code: "22023", message: "media upload reservation is expired")
        }
        let assetID = reservedAssetIDs[operation.id] ?? UUID()
        reservedAssetIDs[operation.id] = assetID
        return MediaUploadReservation(
            mediaAssetID: assetID,
            bucket: "widget-drawings",
            storagePath: "\(coupleID)/\(canvasID)/revisions/\(revisionID)/drawing.pkdrawing",
            uploadURL: URL(filePath: "/upload/\(revisionID)")
        )
    }

    func uploadPayload(reservation: MediaUploadReservation, data: Data) throws -> String {
        callOrder.append("upload")
        uploadCalls.append(UploadCall(reservation: reservation, payloadData: data))
        if failFirstUpload, uploadCalls.count == 1 {
            throw URLError(.networkConnectionLost)
        }
        return Self.storageID
    }

    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput,
        operation: WidgetCanvasClientOperation
    ) -> FinalizedMediaUploadResponse {
        callOrder.append("finalize")
        finalizeInputs.append(input)
        return FinalizedMediaUploadResponse(mediaAssetID: input.reservation.mediaAssetID, uploadStatus: "finalized")
    }

    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission,
        operation: WidgetCanvasClientOperation
    ) async throws -> WidgetDrawingRevisionResult {
        callOrder.append("submit")
        submitCalls.append(submission)
        submitOperationIDs.append(operation.id)
        submitAttempts += 1
        if loseFirstSubmitResponse, submitAttempts == 1 {
            throw URLError(.networkConnectionLost)
        }
        if hangFirstSubmitUntilCancelled, submitAttempts == 1 {
            isSubmitHeld = true
            try await Task.sleep(for: .seconds(600))
        }
        if holdFirstSubmit, submitAttempts == 1 {
            await withCheckedContinuation { continuation in
                heldSubmit = continuation
                isSubmitHeld = true
            }
        }
        if failSubmit {
            throw URLError(.notConnectedToInternet)
        }
        if conflictOnFirstSubmit, submitAttempts == 1 {
            throw WidgetCanvasGatewayError.parentRevisionConflict
        }
        return WidgetDrawingRevisionResult(revisionID: UUID(), activeRevisionID: UUID())
    }

    func releaseHeldSubmit() {
        heldSubmit?.resume()
        heldSubmit = nil
    }

    func getCanvasState() -> WidgetCanvasState? { nil }
    func signedPayloadURL(mediaAssetID: UUID) -> URL? { nil }
    func listRevisions(
        canvasID: UUID,
        limit: Int,
        createdBefore: Date?,
        createdBeforeRevisionID: UUID?
    ) -> [WidgetDrawingRevisionSummary] { [] }
}
