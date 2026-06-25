import CoreGraphics
import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

struct WidgetCanvasSyncServiceTests {
    @Test func syncDownloadsActiveRevisionAndPublishesLocally() async throws {
        let env = SyncEnvironment()
        let partnerID = UUID()
        env.gateway.state = Self.state(authorUserID: partnerID, canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")

        await env.service.sync(identity: Self.identity(partnerID: partnerID))

        let save = try #require(env.localStore.savedCalls.first)
        #expect(env.localStore.savedCalls.count == 1)
        #expect(save.data == env.downloadedData)
        #expect(save.canvasSize.width == 280)
        #expect(save.authorName == "Partner")
        // The widget shows the author's draw time, not our sync time.
        #expect(save.createdAt == Self.revisionCreatedAt)
    }

    @Test func syncSkipsRevisionItAlreadyPublished() async {
        let env = SyncEnvironment()
        env.gateway.state = Self.state(authorUserID: UUID(), canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")

        await env.service.sync(identity: Self.identity(partnerID: UUID()))
        await env.service.sync(identity: Self.identity(partnerID: UUID()))

        #expect(env.localStore.savedCalls.count == 1)
    }

    @Test func syncSkipsWhileLocalUploadIsPending() async {
        let env = SyncEnvironment()
        env.gateway.state = Self.state(authorUserID: UUID(), canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")
        env.pendingStore.markPending("local-work-hash")

        await env.service.sync(identity: Self.identity(partnerID: UUID()))

        #expect(env.localStore.savedCalls.isEmpty)
    }

    @Test func syncDoesNothingWithoutAnActiveRevision() async {
        let env = SyncEnvironment()
        env.gateway.state = WidgetCanvasState(
            canvasID: UUID(),
            activeRevisionID: nil,
            activeRevisionAuthorUserID: nil,
            payloadMediaAssetID: nil,
            bounds: nil,
            revisionCreatedAt: nil
        )

        await env.service.sync(identity: Self.identity(partnerID: UUID()))

        #expect(env.localStore.savedCalls.isEmpty)
    }

    @Test func authorNameMapsToSelfOrPartner() {
        let me = UUID()
        let partner = UUID()
        let identity = WidgetSyncIdentity(currentUserID: me, currentDisplayName: "Me", partnerDisplayName: "Partner")

        #expect(WidgetCanvasSyncService.authorName(for: me, identity: identity) == "Me")
        #expect(WidgetCanvasSyncService.authorName(for: partner, identity: identity) == "Partner")
        #expect(WidgetCanvasSyncService.authorName(for: nil, identity: identity) == nil)
    }

    static let revisionCreatedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private static func state(authorUserID: UUID, canvasSide: Double) -> WidgetCanvasState {
        WidgetCanvasState(
            canvasID: UUID(),
            activeRevisionID: UUID(),
            activeRevisionAuthorUserID: authorUserID,
            payloadMediaAssetID: UUID(),
            bounds: WidgetDrawingBounds(x: 0, y: 0, width: 100, height: 100, canvasSide: canvasSide),
            revisionCreatedAt: revisionCreatedAt
        )
    }

    private static func identity(partnerID: UUID) -> WidgetSyncIdentity {
        WidgetSyncIdentity(currentUserID: UUID(), currentDisplayName: "Me", partnerDisplayName: "Partner")
    }
}

@MainActor
private final class SyncEnvironment {
    let gateway = SyncGatewaySpy()
    let localStore = SyncLocalStoreSpy()
    let pendingStore: WidgetPendingUploadStore
    let downloadedData: Data
    let service: WidgetCanvasSyncService

    init() {
        let drawingData = SyncEnvironment.makeDrawing().dataRepresentation()
        downloadedData = drawingData
        pendingStore = WidgetPendingUploadStore(
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
        )
        service = WidgetCanvasSyncService(
            gateway: gateway,
            localStore: localStore,
            downloader: SyncDownloaderSpy(data: drawingData),
            pendingStore: pendingStore,
            defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard
        )
    }

    static func makeDrawing() -> PKDrawing {
        let point = PKStrokePoint(
            location: CGPoint(x: 10, y: 10),
            timeOffset: 0,
            size: CGSize(width: 4, height: 4),
            opacity: 1,
            force: 1,
            azimuth: 0,
            altitude: 0
        )
        let path = PKStrokePath(controlPoints: [point], creationDate: Date())
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }
}

private nonisolated final class SyncDownloaderSpy: WidgetPayloadDownloading, @unchecked Sendable {
    let data: Data
    init(data: Data) { self.data = data }
    func download(from url: URL) -> Data { data }
}

private nonisolated final class SyncLocalStoreSpy: WidgetCanvasManaging, @unchecked Sendable {
    struct SaveCall {
        let data: Data
        let canvasSize: CGSize
        let authorName: String?
        let createdAt: Date
    }
    private(set) var savedCalls: [SaveCall] = []

    func loadSavedDrawing() -> Data? { nil }
    func saveDrawing(_ drawingData: Data, canvasSize: CGSize, authorName: String?, createdAt: Date) {
        savedCalls.append(
            SaveCall(data: drawingData, canvasSize: canvasSize, authorName: authorName, createdAt: createdAt)
        )
    }
    func clearForPrivacy() {}
}

private nonisolated final class SyncGatewaySpy: WidgetCanvasGateway, @unchecked Sendable {
    var state: WidgetCanvasState?
    var signedURL: URL?

    func getCanvasState() -> WidgetCanvasState? { state }
    func signedPayloadURL(mediaAssetID: UUID) -> URL? { signedURL }

    func getOrCreateCanvas() throws -> WidgetCanvasReference { throw WidgetCanvasGatewayError.emptyResponse }
    func reserveDrawingUpload(
        coupleID: UUID,
        canvasID: UUID,
        revisionID: UUID,
        operation: WidgetCanvasClientOperation
    ) throws -> PendingMediaUploadResponse { throw WidgetCanvasGatewayError.emptyResponse }
    func uploadPayload(bucket: String, storagePath: String, data: Data) {}
    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput,
        operation: WidgetCanvasClientOperation
    ) throws -> FinalizedMediaUploadResponse { throw WidgetCanvasGatewayError.emptyResponse }
    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission,
        operation: WidgetCanvasClientOperation
    ) throws -> WidgetDrawingRevisionResult { throw WidgetCanvasGatewayError.emptyResponse }
}
