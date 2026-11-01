import CoreGraphics
import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

@MainActor
struct WidgetMediaAlternativeEditingTests {
    @Test func latestDurableAcceptanceRepairsAnOptimisticWriteThatFailedBehindAnOlderEdit() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let files = WidgetCanvasTestEnvironment()
        let directory = files.payloadURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: files.containerURL.deletingLastPathComponent())
        }
        let canvas = files.makeService()
        let revision = UUID()
        try await canvas.saveDescribedDrawing(makeNonEmptyDrawing().dataRepresentation(),
                                              canvasSize: CGSize(width: 320, height: 320), authorName: "Alex",
                                              createdAt: Date(), revisionID: revision,
                                              accessibilityText: "Original", publicationID: nil)
        let caches = MediaAlternativeCacheUpdater(chat: fixture.chat, stories: fixture.stories,
                                                   daily: fixture.caches.daily, widgetCanvas: canvas)
        let service = MediaAlternativeEditingService(pending: fixture.pending, cache: caches)
        let target = MediaAlternativeTarget.widgetDrawing(revisionID: revision)
        let earlier = fixture.operations.makeOperation()
        try await service.queue(MediaAlternativeEdit(coupleID: fixture.couple, target: target, text: "Correction A"),
                                ownerUserID: fixture.owner, operation: earlier,
                                stamp: await caches.stamp(ownerUserID: fixture.owner))
        let latest = fixture.operations.makeOperation()
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        await #expect(throws: CocoaError.self) {
            try await service.queue(
                MediaAlternativeEdit(coupleID: fixture.couple, target: target, text: "Correction B"),
                ownerUserID: fixture.owner, operation: latest,
                                    stamp: await caches.stamp(ownerUserID: fixture.owner))
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(try files.decodePayload().pendingDescriptionOperationID == earlier.id)
        let pending = try #require(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .updateMediaAlternative
        ).first(where: { $0.operation.id == latest.id }))
        let handler = MediaAlternativePendingOperationHandler(
            gateway: AcceptedWidgetAlternativeGateway(version: 1_002), cache: caches
        )
        #expect(try await handler.send(pending, context: fixture.context) == .succeeded)
        try await fixture.pending.markSucceeded(clientOperationID: latest.id, at: Date())
        let accepted = try files.decodePayload()
        #expect(accepted.accessibilityText == "Correction B")
        #expect(accepted.pendingDescriptionOperationID == nil)
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: fixture.owner)
        try await canvas.updateDescription(.remote(text: "Correction C", version: 1_003),
                                             revisionID: revision, privacyToken: token)
        #expect(try files.decodePayload().accessibilityText == "Correction C")
    }

    @Test func completedWidgetCorrectionDoesNotMaskANewerHistoryVersionOrItsClearedText() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let target = MediaAlternativeTarget.widgetDrawing(revisionID: UUID())
        var context = ThreadChatContext(coupleID: fixture.couple)
        context.participants.currentUserID = fixture.owner
        context.operationProvider = fixture.operations
        let model = MediaAlternativeEditorModel(target: target, context: context, service: fixture.service)
        await model.prepare()
        model.open(currentText: "Original")
        model.text = "My correction"
        await model.save()
        let operation = try #require(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .updateMediaAlternative
        ).first)
        try await fixture.caches.apply(
            MediaAlternativeEdit(coupleID: fixture.couple, target: target, text: "My correction"),
            ownerUserID: fixture.owner, operation: operation.operation,
            stamp: await fixture.caches.stamp(ownerUserID: fixture.owner), widgetRevisionVersion: 1_001
        )
        try await fixture.pending.markSucceeded(clientOperationID: operation.operation.id, at: Date())
        await model.reloadPending()
        #expect(model.displayedText(source: "Stale", version: 1_000) == "My correction")
        #expect(model.displayedText(source: "A newer correction", version: 1_002) == "A newer correction")
        #expect(model.displayedText(source: nil, version: 1_002) == nil)
    }

    @Test func failedWidgetAcceptanceKeepsTheDurableCorrectionUntilTheFileWriteCanRetry() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let files = WidgetCanvasTestEnvironment()
        let directory = files.payloadURL.deletingLastPathComponent()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: files.containerURL.deletingLastPathComponent())
        }
        let canvas = files.makeService()
        let revision = UUID()
        try await canvas.saveDescribedDrawing(makeNonEmptyDrawing().dataRepresentation(),
                                              canvasSize: CGSize(width: 320, height: 320), authorName: "Alex",
                                              createdAt: Date(), revisionID: revision, accessibilityText: "Original",
                                              publicationID: nil)
        let caches = MediaAlternativeCacheUpdater(chat: fixture.chat, stories: fixture.stories,
                                                   daily: fixture.caches.daily, widgetCanvas: canvas)
        let service = MediaAlternativeEditingService(pending: fixture.pending, cache: caches)
        let edit = MediaAlternativeEdit(coupleID: fixture.couple, target: .widgetDrawing(revisionID: revision),
                                         text: "A corrected drawing description")
        try await service.queue(edit, ownerUserID: fixture.owner, operation: fixture.operations.makeOperation(),
                                stamp: await caches.stamp(ownerUserID: fixture.owner))
        let operation = try #require(try await fixture.pending.inFlightOperations(
            ownerUserID: fixture.owner, kind: .updateMediaAlternative
        ).first)
        let handler = MediaAlternativePendingOperationHandler(
            gateway: AcceptedWidgetAlternativeGateway(), cache: caches
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        await #expect(throws: CocoaError.self) {
            try await handler.send(operation, context: fixture.context)
        }
        #expect(try files.decodePayload().pendingDescriptionOperationID == operation.operation.id)
        let reopened = MediaAlternativeEditingService(
            pending: SwiftDataPendingSyncOperationRepository(container: fixture.localStore.container), cache: caches
        )
        #expect(try await reopened.pendingEdit(ownerUserID: fixture.owner, coupleID: fixture.couple,
                                                target: edit.target)?.text == edit.text)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        #expect(try await handler.send(operation, context: fixture.context) == .succeeded)
        try await fixture.pending.markSucceeded(clientOperationID: operation.operation.id, at: Date())
        #expect(try await reopened.pendingEdit(ownerUserID: fixture.owner, coupleID: fixture.couple,
                                                target: edit.target) == nil)
        #expect(try files.decodePayload().pendingDescriptionOperationID == nil)
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: fixture.owner)
        try await canvas.updateDescription(.remote(text: "Newer server text", version: 1_002),
                                             revisionID: revision, privacyToken: token)
        #expect(try files.decodePayload().accessibilityText == "Newer server text")
    }

    @Test func widgetCorrectionSurvivesOutboxReopeningAndCannotBypassTheDrawingLimit() async throws {
        let fixture = try MediaAlternativeEditingFixture()
        defer { fixture.removeFiles() }
        let target = MediaAlternativeTarget.widgetDrawing(revisionID: UUID())
        let edit = MediaAlternativeEdit(coupleID: fixture.couple, target: target, text: "A sun over two hills")
        try await fixture.queue(edit)
        let reopened = MediaAlternativeEditingService(
            pending: SwiftDataPendingSyncOperationRepository(container: fixture.localStore.container),
            cache: fixture.caches
        )
        #expect(try await reopened.pendingEdit(ownerUserID: fixture.owner, coupleID: fixture.couple,
                                               target: target)?.text == edit.text)
        await #expect(throws: MediaAlternativeEditingError.self) {
            try await fixture.queue(MediaAlternativeEdit(coupleID: fixture.couple, target: target,
                                                         text: String(repeating: "a", count: 501)))
        }
        #expect(try await reopened.pendingEdit(ownerUserID: fixture.owner, coupleID: fixture.couple,
                                               target: target)?.text == edit.text)
    }
}

private struct AcceptedWidgetAlternativeGateway: MediaAlternativeGateway {
    let version: Int64
    init(version: Int64 = 1_001) { self.version = version }
    // swiftlint:disable:next async_without_await
    func update(_ edit: MediaAlternativeEdit, operation _: SyncClientOperation) async -> MediaAlternativeAcceptedText {
        MediaAlternativeAcceptedText(accessibilityText: edit.text, widgetRevisionVersion: version)
    }
}

