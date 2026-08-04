import CoreGraphics
import Foundation
import PencilKit
import Testing
@testable import PaeoniaApp

@MainActor
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

    @Test func syncCoalescesDuplicateInFlightRequests() async throws {
        let downloadedData = SyncEnvironment.makeDrawing().dataRepresentation()
        let downloader = SyncSuspendingDownloaderSpy(data: downloadedData)
        let env = SyncEnvironment(downloadedData: downloadedData, downloader: downloader)
        let partnerID = UUID()
        let identity = Self.identity(partnerID: partnerID)
        env.gateway.state = Self.state(authorUserID: partnerID, canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")

        async let firstSync: Void = env.service.sync(identity: identity)
        await downloader.waitUntilDownloadStarted()
        async let duplicateSync: Void = env.service.sync(identity: identity)
        await Task.yield()

        await downloader.resume()
        await firstSync
        await duplicateSync

        // The duplicate collapses onto the in-flight run, then triggers a single trailing
        // re-check so a revision committed after the first pass read the canvas state is
        // still seen. So the gateway state is read twice (once per pass), but the
        // expensive download + save runs only once: the trailing pass finds the revision
        // already applied and stops before downloading it again.
        #expect(env.gateway.getCanvasStateCallCount == 2)
        #expect(await downloader.downloadCount == 1)
        #expect(env.localStore.savedCalls.count == 1)
    }

    @Test func syncSkipsWhileLocalUploadIsPending() async {
        let env = SyncEnvironment()
        env.gateway.state = Self.state(authorUserID: UUID(), canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")
        env.pendingStore.markPending(
            Self.uploadPayload(for: env.downloadedData),
            contentHash: WidgetCanvasUploadService.sha256Hex(of: env.downloadedData)
        )

        await env.service.sync(identity: Self.identity(partnerID: UUID()))

        #expect(env.localStore.savedCalls.isEmpty)
        #expect(env.uploadSpy.uploadedPayloads.isEmpty)
    }

    @Test func syncSkipsRemoteRevisionForLegacyPendingUploadMarker() async {
        let env = SyncEnvironment()
        env.gateway.state = Self.state(authorUserID: UUID(), canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")
        env.pendingDefaults.set(
            "legacy-local-work-hash",
            forKey: "paeonia.widgetCanvas.pendingUploadHash"
        )

        await env.service.sync(identity: Self.identity(partnerID: UUID()))

        #expect(env.localStore.savedCalls.isEmpty)
        #expect(env.uploadSpy.uploadedPayloads.isEmpty)
    }

    @Test func syncRetriesStalePendingUploadBeforePullingRemoteRevision() async {
        let env = SyncEnvironment()
        let contentHash = WidgetCanvasUploadService.sha256Hex(of: env.downloadedData)
        env.localStore.savedDrawingData = env.downloadedData
        env.gateway.state = Self.state(authorUserID: UUID(), canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")
        env.pendingStore.markPending(
            Self.uploadPayload(for: env.downloadedData),
            contentHash: contentHash,
            at: Date(timeIntervalSince1970: 0)
        )

        await env.service.sync(identity: Self.identity(partnerID: UUID()))

        #expect(env.uploadSpy.uploadedPayloads.count == 1)
        #expect(!env.pendingStore.hasPending)
        #expect(env.localStore.savedCalls.count == 1)
    }

    @Test func syncKeepsPendingUploadWhenRetryFails() async {
        let env = SyncEnvironment()
        let contentHash = WidgetCanvasUploadService.sha256Hex(of: env.downloadedData)
        env.localStore.savedDrawingData = env.downloadedData
        env.uploadSpy.error = WidgetCanvasGatewayError.emptyResponse
        env.gateway.state = Self.state(authorUserID: UUID(), canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")
        env.pendingStore.markPending(
            Self.uploadPayload(for: env.downloadedData),
            contentHash: contentHash,
            at: Date(timeIntervalSince1970: 0)
        )

        await env.service.sync(identity: Self.identity(partnerID: UUID()))

        #expect(env.uploadSpy.uploadedPayloads.count == 1)
        #expect(env.pendingStore.hasPending)
        #expect(env.localStore.savedCalls.isEmpty)
    }

    @Test func temporaryPrivacyHidePreservesPendingDrawingUntilPermanentPurge() async {
        let env = SyncEnvironment()
        env.pendingStore.markPending(
            Self.uploadPayload(for: env.downloadedData),
            contentHash: WidgetCanvasUploadService.sha256Hex(of: env.downloadedData)
        )

        await env.service.hideForPrivacy()

        #expect(env.pendingStore.hasPending)

        await env.service.clearForPrivacy()

        #expect(!env.pendingStore.hasPending)
    }

    @Test func privacyClearPreventsWaitingDifferentIdentityFromRestartingSync() async {
        let downloadedData = SyncEnvironment.makeDrawing().dataRepresentation()
        let downloader = SyncSuspendingDownloaderSpy(data: downloadedData)
        let env = SyncEnvironment(downloadedData: downloadedData, downloader: downloader)
        let partnerID = UUID()
        env.gateway.state = Self.state(authorUserID: partnerID, canvasSide: 280)
        env.gateway.signedURL = URL(string: "https://example.com/payload")

        let firstSync = Task {
            await env.service.sync(identity: Self.identity(partnerID: partnerID))
        }
        await downloader.waitUntilDownloadStarted()

        let waitingSync = Task {
            await env.service.sync(
                identity: WidgetSyncIdentity(
                    currentUserID: UUID(),
                    currentDisplayName: "Different user",
                    partnerDisplayName: "Different partner"
                )
            )
        }
        let privacyClear = Task { await env.service.clearForPrivacy() }
        await downloader.waitUntilDownloadCancelled()
        await downloader.resume()

        await firstSync.value
        await waitingSync.value
        await privacyClear.value

        #expect(env.gateway.getCanvasStateCallCount == 1)
        #expect(await downloader.downloadCount == 1)
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

    private static func uploadPayload(for data: Data) -> WidgetDrawingUploadPayload {
        WidgetDrawingUploadPayload(
            drawingData: data,
            canvasSide: 320,
            strokeCount: 1,
            pointCount: 1,
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100)
        )
    }
}

@MainActor
private final class SyncEnvironment {
    let gateway = SyncGatewaySpy()
    let localStore = SyncLocalStoreSpy()
    let uploadSpy: SyncUploadSpy
    let pendingStore: WidgetPendingUploadStore
    /// The defaults backing `pendingStore`, exposed so tests can seed legacy markers
    /// without reaching into the store's private storage.
    let pendingDefaults: UserDefaults
    let downloadedData: Data
    let service: WidgetCanvasSyncService

    init(
        downloadedData: Data? = nil,
        downloader: (any WidgetPayloadDownloading)? = nil
    ) {
        let drawingData = downloadedData ?? Self.makeDrawing().dataRepresentation()
        self.downloadedData = drawingData
        let pendingDefaults = UserDefaults(suiteName: UUID().uuidString) ?? .standard
        self.pendingDefaults = pendingDefaults
        pendingStore = WidgetPendingUploadStore(defaults: pendingDefaults)
        uploadSpy = SyncUploadSpy(pendingStore: pendingStore)
        service = WidgetCanvasSyncService(
            gateway: gateway,
            localStore: localStore,
            downloader: downloader ?? SyncDownloaderSpy(data: drawingData),
            pendingStore: pendingStore,
            pendingUploader: uploadSpy,
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

private actor SyncSuspendingDownloaderSpy: WidgetPayloadDownloading {
    private let data: Data
    private var downloadContinuation: CheckedContinuation<Data, Never>?
    private var downloadStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var didStartDownload = false
    private(set) var downloadCount = 0

    init(data: Data) {
        self.data = data
    }

    func download(from url: URL) async -> Data {
        downloadCount += 1
        if downloadCount > 1 {
            return data
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                downloadContinuation = continuation
                didStartDownload = true
                let waiters = downloadStartWaiters
                downloadStartWaiters.removeAll()
                waiters.forEach { $0.resume() }
            }
        } onCancel: {
            Task { await self.markDownloadCancelled() }
        }
    }

    func waitUntilDownloadStarted() async {
        guard !didStartDownload else {
            return
        }

        await withCheckedContinuation { continuation in
            downloadStartWaiters.append(continuation)
        }
    }

    /// Suspends until the in-flight download's task has been cancelled, so a test
    /// can order a privacy clear strictly before resuming the download.
    func waitUntilDownloadCancelled() async {
        guard !didObserveCancellation else {
            return
        }

        await withCheckedContinuation { continuation in
            cancellationWaiters.append(continuation)
        }
    }

    private var didObserveCancellation = false
    private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

    private func markDownloadCancelled() {
        didObserveCancellation = true
        let waiters = cancellationWaiters
        cancellationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func resume() {
        downloadContinuation?.resume(returning: data)
        downloadContinuation = nil
    }
}

private nonisolated final class SyncLocalStoreSpy: WidgetCanvasManaging, @unchecked Sendable {
    struct SaveCall {
        let data: Data
        let canvasSize: CGSize
        let authorName: String?
        let createdAt: Date
    }
    private(set) var savedCalls: [SaveCall] = []
    var savedDrawingData: Data?

    func loadSavedDrawing() -> Data? { savedDrawingData }
    func saveDrawing(_ drawingData: Data, canvasSize: CGSize, authorName: String?, createdAt: Date) {
        savedCalls.append(
            SaveCall(data: drawingData, canvasSize: canvasSize, authorName: authorName, createdAt: createdAt)
        )
    }
    func clearForPrivacy() {}
}

private nonisolated final class SyncUploadSpy: WidgetCanvasUploading, @unchecked Sendable {
    private let pendingStore: WidgetPendingUploadStore
    private(set) var uploadedPayloads: [WidgetDrawingUploadPayload] = []
    var error: Error?

    init(pendingStore: WidgetPendingUploadStore) {
        self.pendingStore = pendingStore
    }

    func enqueueUpload(_ payload: WidgetDrawingUploadPayload) {}

    // swiftlint:disable:next async_without_await
    func uploadPending(_ payload: WidgetDrawingUploadPayload) async throws {
        uploadedPayloads.append(payload)
        if let error {
            throw error
        }
        pendingStore.clearPending(WidgetCanvasUploadService.sha256Hex(of: payload.drawingData))
    }
}

private nonisolated final class SyncGatewaySpy: WidgetCanvasGateway, @unchecked Sendable {
    var state: WidgetCanvasState?
    var signedURL: URL?
    private(set) var getCanvasStateCallCount = 0

    func getCanvasState() -> WidgetCanvasState? {
        getCanvasStateCallCount += 1
        return state
    }
    func signedPayloadURL(mediaAssetID: UUID) -> URL? { signedURL }
    func listRevisions(
        canvasID: UUID,
        limit: Int,
        createdBefore: Date?,
        createdBeforeRevisionID: UUID?
    ) -> [WidgetDrawingRevisionSummary] { [] }

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
