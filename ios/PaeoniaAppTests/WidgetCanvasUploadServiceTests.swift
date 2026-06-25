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
        #expect(upload.bucket == "widget-drawings")
        #expect(upload.payloadData == Self.samplePayload.drawingData)

        #expect(gateway.finalizeCount == 1)

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
    let canvas = WidgetCanvasReference(
        canvasID: UUID(),
        coupleID: UUID(),
        activeRevisionID: UUID()
    )
    var refreshedCanvas: WidgetCanvasReference?
    var conflictOnFirstSubmit = false

    struct ReserveCall { let coupleID: UUID; let canvasID: UUID; let revisionID: UUID }
    struct UploadCall { let bucket: String; let storagePath: String; let payloadData: Data }

    private(set) var getOrCreateCount = 0
    private(set) var reserveCalls: [ReserveCall] = []
    private(set) var uploadCalls: [UploadCall] = []
    private(set) var finalizeCount = 0
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
    ) -> PendingMediaUploadResponse {
        reserveCalls.append(ReserveCall(coupleID: coupleID, canvasID: canvasID, revisionID: revisionID))
        return PendingMediaUploadResponse(
            mediaAssetID: UUID(),
            bucket: "widget-drawings",
            storagePath: "\(coupleID)/\(canvasID)/revisions/\(revisionID)/drawing.pkdrawing"
        )
    }

    func uploadPayload(bucket: String, storagePath: String, data: Data) {
        uploadCalls.append(UploadCall(bucket: bucket, storagePath: storagePath, payloadData: data))
    }

    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput,
        operation: WidgetCanvasClientOperation
    ) -> FinalizedMediaUploadResponse {
        finalizeCount += 1
        return FinalizedMediaUploadResponse(mediaAssetID: input.reservation.mediaAssetID, uploadStatus: "finalized")
    }

    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission,
        operation: WidgetCanvasClientOperation
    ) throws -> WidgetDrawingRevisionResult {
        submitCalls.append(submission)
        submitAttempts += 1
        if conflictOnFirstSubmit, submitAttempts == 1 {
            throw WidgetCanvasGatewayError.parentRevisionConflict
        }
        return WidgetDrawingRevisionResult(revisionID: UUID(), activeRevisionID: UUID())
    }

    func getCanvasState() -> WidgetCanvasState? { nil }
    func signedPayloadURL(mediaAssetID: UUID) -> URL? { nil }
}
