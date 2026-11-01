import CoreGraphics
import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

@MainActor
struct WidgetDrawingDescriptionCorrectionTests {
    @Test func staleExtensionReadCannotReplaceQueuedTextAndAcceptedVersionsSurviveReopening() async throws {
        let environment = WidgetCanvasTestEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.containerURL.deletingLastPathComponent()) }
        let service = environment.makeService()
        let owner = UUID()
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: owner)
        let revision = UUID()
        let data = makeNonEmptyDrawing().dataRepresentation()
        try await service.saveDescribedDrawing(data, canvasSize: CGSize(width: 320, height: 320),
                                               authorName: "Alex", createdAt: Date(timeIntervalSince1970: 1),
                                               revisionID: revision, accessibilityText: "Original sun")
        await service.updateDescription(.remote(text: "Original sun", version: 1_000),
                                         revisionID: revision, privacyToken: token)
        // The widget's network read finishes before the app queues an offline correction.
        let staleRead = try environment.decodePayload()
        let operationID = UUID()
        await service.updateDescription(.queued(text: "A sun above two hills", operationID: operationID),
                                         revisionID: revision, privacyToken: token)
        // This is the same locked, fresh read and merge that the extension uses after its query.
        _ = try WidgetSharePayload.updateFile(in: environment.containerURL) { current in
            current.applyDescription(.remote(text: staleRead.accessibilityText,
                                              version: try #require(staleRead.descriptionVersion)))
        }
        let queued = try environment.decodePayload()
        #expect(queued.accessibilityText == "A sun above two hills")
        #expect(queued.pendingDescriptionOperationID == operationID)
        let reopenedService = environment.makeService()
        let reopened = await reopenedService.loadSavedSnapshot()
        let protocolReader: any WidgetCanvasManaging = reopenedService
        #expect(reopened?.accessibilityText == queued.accessibilityText)
        #expect(await protocolReader.loadSavedSnapshot() == reopened)
        await service.updateDescription(.accepted(text: queued.accessibilityText, version: 1_001,
                                                   operationID: operationID), revisionID: revision, privacyToken: token)
        await service.updateDescription(.remote(text: "Stale server description", version: 1_000),
                                         revisionID: revision, privacyToken: token)
        let accepted = try environment.decodePayload()
        #expect(accepted.accessibilityText == queued.accessibilityText)
        #expect(accepted.pendingDescriptionOperationID == nil)
        #expect(accepted.descriptionVersion == 1_001)
        #expect(accepted.revisionID == staleRead.revisionID)
        #expect(accepted.authorName == staleRead.authorName)
        #expect(accepted.createdAt == staleRead.createdAt)
        #expect(accepted.renderedAt == staleRead.renderedAt)
        #expect(accepted.contentHash == staleRead.contentHash)
        #expect(accepted.previews == staleRead.previews)
        #expect(await service.loadSavedDrawing() == data)
    }

    @Test func historicalAndLateAcceptedEditsCannotReplaceANewerDraftOrRecreatePurgedContent() async throws {
        let environment = WidgetCanvasTestEnvironment()
        defer { try? FileManager.default.removeItem(at: environment.containerURL.deletingLastPathComponent()) }
        let service = environment.makeService()
        let owner = UUID()
        let token = LocalPrivacyWriteGuard.shared.token(ownerUserID: owner)
        let revision = UUID()
        try await service.saveDescribedDrawing(makeNonEmptyDrawing().dataRepresentation(),
                                               canvasSize: CGSize(width: 320, height: 320), authorName: "Alex",
                                               createdAt: Date(), revisionID: revision, accessibilityText: "Original")
        let older = UUID()
        let latest = UUID()
        await service.updateDescription(.queued(text: "Newer correction", operationID: latest),
                                         revisionID: revision, privacyToken: token)
        await service.updateDescription(.accepted(text: "Older correction", version: 2_000, operationID: older),
                                         revisionID: revision, privacyToken: token)
        await service.updateDescription(.queued(text: "Historic description", operationID: UUID()),
                                         revisionID: UUID(), privacyToken: token)
        #expect(try environment.decodePayload().accessibilityText == "Newer correction")
        #expect(try environment.decodePayload().pendingDescriptionOperationID == latest)
        LocalPrivacyWriteGuard.shared.invalidate(ownerUserID: owner)
        await service.clearForPrivacy()
        await service.updateDescription(.accepted(text: "Must stay removed", version: 3_000, operationID: latest),
                                         revisionID: revision, privacyToken: token)
        #expect(!FileManager.default.fileExists(atPath: environment.payloadURL.path))
        #expect(await service.loadSavedDrawing() == nil)
    }
}
