import CoreGraphics
import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

@MainActor
struct WidgetDrawingPublicationIdentityTests {
    @Test func uploadedLocalDrawingAcceptsCorrectionsUsingItsServerRevision() async throws {
        let environment = try PublicationEnvironment()
        defer { environment.removeFiles() }
        let gateway = WidgetCanvasGatewaySpy()
        let uploader = environment.uploader(gateway: gateway)
        let payload = makePayload(description: "A sun")
        _ = await uploader.markPending(payload)
        try await environment.publish(payload)
        let original = try environment.files.decodePayload()

        #expect(await uploader.send(payload) == .delivered)
        let revision = try #require(gateway.reserveCalls.first?.revisionID)
        let accepted = try environment.files.decodePayload()
        #expect(accepted.revisionID == revision.uuidString.lowercased())
        #expect(accepted.localPublicationID == payload.publicationID)
        #expect(accepted.previews == original.previews)
        #expect(accepted.contentHash == original.contentHash)
        #expect(accepted.authorName == original.authorName)
        #expect(accepted.createdAt == original.createdAt)

        let owner = UUID()
        try await environment.service.updateDescription(
            .queued(text: "The sun above our house", operationID: UUID()), revisionID: revision,
            privacyToken: LocalPrivacyWriteGuard.shared.token(ownerUserID: owner)
        )
        #expect(await environment.service.loadSavedSnapshot()?.accessibilityText == "The sun above our house")
        #expect(await environment.service.loadSavedDrawing() == payload.drawingData)
    }

    @Test func delayedUploadCannotRelabelSameStrokesWithANewerDescription() async throws {
        let environment = try PublicationEnvironment()
        defer { environment.removeFiles() }
        let gateway = WidgetCanvasGatewaySpy()
        gateway.holdFirstSubmit = true
        let uploader = environment.uploader(gateway: gateway)
        let older = makePayload(description: "A circle")
        var newer = older
        newer.accessibilityText = "The sun above our house"
        _ = await uploader.markPending(older)
        try await environment.publish(older)
        let upload = Task { await uploader.send(older) }
        while !gateway.isSubmitHeld { await Task.yield() }
        _ = await uploader.markPending(newer)
        try await environment.publish(newer)
        let newerPublication = try environment.files.decodePayload()

        gateway.releaseHeldSubmit()
        #expect(await upload.value == .waiting)
        #expect(try environment.files.decodePayload() == newerPublication)
        #expect(environment.pending.pendingSnapshot?.publicationID == newer.publicationID)
        #expect(await uploader.send(newer) == .delivered)
        #expect(try environment.files.decodePayload().revisionID
            == gateway.reserveCalls.last?.revisionID.uuidString.lowercased())
        #expect(await environment.service.loadSavedSnapshot()?.accessibilityText == newer.accessibilityText)
    }

    @Test func purgeInvalidatesAnUploadEvenWhenTheNextPublicationIsIdentical() async throws {
        let environment = try PublicationEnvironment()
        defer { environment.removeFiles() }
        let gateway = WidgetCanvasGatewaySpy()
        gateway.holdFirstSubmit = true
        let uploader = environment.uploader(gateway: gateway)
        let payload = makePayload(description: "A circle")
        _ = await uploader.markPending(payload)
        try await environment.publish(payload)
        let upload = Task { await uploader.send(payload) }
        while !gateway.isSubmitHeld { await Task.yield() }
        await environment.service.clearForPrivacy()
        _ = await uploader.markPending(payload)
        try await environment.publish(payload)
        let afterPurge = try environment.files.decodePayload()

        gateway.releaseHeldSubmit()
        #expect(await upload.value == .waiting)
        #expect(try environment.files.decodePayload() == afterPurge)
        #expect(environment.pending.hasPending)
        #expect(await uploader.send(payload) == .delivered)
        #expect(gateway.reserveCalls.count == 2)
        #expect(try environment.files.decodePayload().revisionID
            == gateway.reserveCalls.last?.revisionID.uuidString.lowercased())
    }

    @Test func failedAcceptanceWriteKeepsProgressForAnIdempotentRetryAfterReopening() async throws {
        let environment = try PublicationEnvironment()
        defer { environment.removeFiles() }
        let gateway = WidgetCanvasGatewaySpy()
        let uploader = environment.uploader(gateway: gateway)
        let payload = makePayload(description: "A circle")
        _ = await uploader.markPending(payload)
        try await environment.publish(payload)
        let directory = environment.files.payloadURL.deletingLastPathComponent()
        gateway.beforeReturningSubmit = {
            try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        }
        let outcome = await uploader.send(payload)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path)
        gateway.beforeReturningSubmit = nil
        #expect(outcome == .waiting)
        #expect(environment.pending.hasPending)
        let progress = try #require(environment.pending.pendingSnapshot?.progress)

        let reopened = environment.makeService()
        let retry = WidgetCanvasUploadService(
            gateway: gateway, operationFactory: WidgetCanvasOperationFactorySpy(),
            pendingStore: environment.pending, localStore: reopened
        )
        try await retry.uploadPending(payload)
        #expect(!environment.pending.hasPending)
        #expect(gateway.reserveCalls.count == 1)
        #expect(gateway.submitOperationIDs.count == 2)
        #expect(gateway.submitOperationIDs.first == gateway.submitOperationIDs.last)
        #expect(try environment.files.decodePayload().revisionID == progress.revisionID.uuidString.lowercased())
        #expect(await reopened.loadSavedDrawing() == payload.drawingData)
    }

    @Test func firstDayUploadAttachesTheRevisionRetainedAfterPairing() async throws {
        let environment = try PublicationEnvironment()
        defer { environment.removeFiles() }
        let gateway = FirstDayGatewaySpy()
        let uploader = FirstDayDrawingUploadService(
            gateway: gateway, operationFactory: FirstDayOperationsFake(),
            pendingStore: environment.pending, localStore: environment.service
        )
        let payload = makePayload(description: "A welcome sun")
        _ = await uploader.markPending(payload)
        try await environment.publish(payload)
        #expect(await uploader.send(payload) == .delivered)
        let accepted = try #require(await gateway.acceptedDrawings.last)
        #expect(try environment.files.decodePayload().revisionID == accepted.revisionID.uuidString.lowercased())
    }

    @Test func supersededFirstDayUploadDoesNotAttachAnotherDrawingsRevision() async throws {
        let environment = try PublicationEnvironment()
        defer { environment.removeFiles() }
        let gateway = FirstDayGatewaySpy()
        await gateway.returnDrawing(FirstDayDrawingReference(mediaAssetID: UUID(), revisionID: UUID()))
        let uploader = FirstDayDrawingUploadService(
            gateway: gateway, operationFactory: FirstDayOperationsFake(),
            pendingStore: environment.pending, localStore: environment.service
        )
        let payload = makePayload(description: "An unsent sun")
        _ = await uploader.markPending(payload)
        try await environment.publish(payload)
        let original = try environment.files.decodePayload()
        #expect(await uploader.send(payload) == .replaced)
        #expect(try environment.files.decodePayload() == original)
        #expect(await environment.service.loadSavedDrawing() == payload.drawingData)
    }

    private func makePayload(description: String) -> WidgetDrawingUploadPayload {
        let drawing = makeNonEmptyDrawing(seed: 30)
        return WidgetDrawingUploadPayload(
            drawingData: drawing.dataRepresentation(), canvasSide: 320,
            strokeCount: drawing.strokes.count, pointCount: drawing.paeoniaPointCount,
            bounds: drawing.bounds, accessibilityText: description
        )
    }
}

@MainActor
private struct PublicationEnvironment {
    let files = WidgetCanvasTestEnvironment()
    let defaults: UserDefaults
    let service: WidgetCanvasService
    let pending: WidgetPendingUploadStore

    init() throws {
        defaults = try #require(UserDefaults(suiteName: "WidgetPublication-\(UUID().uuidString)"))
        service = WidgetCanvasService(
            appGroupContainerURL: files.containerURL, canonicalDrawingURL: files.canonicalURL,
            reloader: files.reloader, sharedDefaults: defaults
        )
        pending = WidgetPendingUploadStore(defaults: defaults, retryDelay: 0)
    }

    func makeService() -> WidgetCanvasService {
        WidgetCanvasService(
            appGroupContainerURL: files.containerURL, canonicalDrawingURL: files.canonicalURL,
            reloader: files.reloader, sharedDefaults: defaults
        )
    }

    func uploader(gateway: WidgetCanvasGatewaySpy) -> WidgetCanvasUploadService {
        WidgetCanvasUploadService(
            gateway: gateway, operationFactory: WidgetCanvasOperationFactorySpy(),
            pendingStore: pending, localStore: service
        )
    }

    func publish(_ payload: WidgetDrawingUploadPayload) async throws {
        try await service.saveDescribedDrawing(
            payload.drawingData, canvasSize: CGSize(width: payload.canvasSide, height: payload.canvasSide),
            authorName: "Alex", createdAt: Date(timeIntervalSince1970: 1_000),
            revisionID: nil, accessibilityText: payload.accessibilityText
        )
    }

    func removeFiles() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: files.payloadURL.deletingLastPathComponent().path
        )
        try? FileManager.default.removeItem(at: files.containerURL.deletingLastPathComponent())
    }
}
