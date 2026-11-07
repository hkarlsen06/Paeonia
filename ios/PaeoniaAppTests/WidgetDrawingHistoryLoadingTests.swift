import Foundation
import Testing
@testable import PaeoniaApp

// The test doubles mirror async protocols, so some bodies do not await.
// swiftlint:disable async_without_await

/// First-page, newest-page, and older-page loads that fail or overlap in time.
@MainActor
struct WidgetDrawingHistoryLoadingTests {
    @Test func focusedDrawingLoadsOlderPagesBeforeShowingHistory() async {
        let newest = makeSummary(createdAt: date(300))
        let middle = makeSummary(createdAt: date(200))
        let target = makeSummary(createdAt: date(100))
        let gateway = StubGateway(canvasState: makeState(), pages: [[newest], [middle], [target]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 1)

        await viewModel.loadInitialIfNeeded(focusingOn: target.revisionID)

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.items.map(\.id) == [newest.revisionID, middle.revisionID, target.revisionID])
        #expect(gateway.listCursors.count == 3)
        #expect(gateway.listCursors.last?.revisionID == middle.revisionID)
    }

    @Test func missingFocusedDrawingStopsAtTheEndOfHistory() async {
        let newest = makeSummary(createdAt: date(300))
        let gateway = StubGateway(canvasState: makeState(), pages: [[newest], []])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 1)

        await viewModel.loadInitialIfNeeded(focusingOn: UUID())

        #expect(viewModel.phase == .loaded)
        #expect(viewModel.items.map(\.id) == [newest.revisionID])
        #expect(!viewModel.hasMore)
        #expect(gateway.listCursors.count == 2)
    }

    @Test(arguments: [Optional("A newer server description"), nil])
    func pendingOverlayDoesNotChangeTheNewerServerTextOrVersion(newerText: String?) async throws {
        let owner = UUID()
        let couple = UUID()
        let revision = UUID()
        let summary = makeSummary(createdAt: date(100), revisionID: revision, description: newerText,
                                  version: 1_002, authorUserID: owner)
        let arrivingText = newerText.map { _ in "An even newer server description" }
        let arriving = WidgetDrawingRevisionSummary(
            revisionID: revision, authorUserID: owner, payloadMediaAssetID: summary.payloadMediaAssetID,
            bounds: WidgetDrawingBounds(x: 0, y: 0, width: 10, height: 10, canvasSide: 320,
                                        accessibilityText: arrivingText),
            createdAt: summary.createdAt, descriptionVersion: 1_003
        )
        let gateway = GatedListGateway(canvasState: makeState(coupleID: couple), heldCall: Int.max,
                                      otherPages: [[summary], [arriving]])
        let history = WidgetDrawingHistoryViewModel(
            gateway: gateway,
            identity: WidgetSyncIdentity(currentUserID: owner, currentDisplayName: "Alex", partnerDisplayName: "Robin")
        )
        await history.loadInitialIfNeeded()
        let store = try PaeoniaLocalStore(inMemory: true)
        let pending = SwiftDataPendingSyncOperationRepository(container: store.container)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = MediaAlternativeCacheUpdater(
            chat: FileThreadChatCache(directoryURL: directory.appendingPathComponent("chat")),
            stories: FileStoriesCache(directoryURL: directory.appendingPathComponent("stories")),
            daily: FileDailyChallengeSnapshotCache(directoryURL: directory.appendingPathComponent("daily"))
        )
        let service = MediaAlternativeEditingService(pending: pending, cache: cache)
        let operation = SyncClientOperation(clientID: UUID(), clientSequence: 1, localCreatedAt: Date())
        let target = MediaAlternativeTarget.widgetDrawing(revisionID: revision)
        let edit = MediaAlternativeEdit(coupleID: couple, target: target, text: "Older correction A")
        let stamp = await cache.stamp(ownerUserID: owner)
        try await service.queue(edit, ownerUserID: owner, operation: operation, stamp: stamp)
        let context = ThreadChatContext(
            coupleID: couple, participants: DailyChallengeParticipants(currentUserID: owner)
        )
        let reader = MediaAlternativeEditorModel(target: target, context: context, service: service)
        await reader.prepare()
        await history.refreshDescriptions(service: service, context: context)
        #expect(history.items.first?.accessibilityText == newerText)
        await history.refreshNewest()
        #expect(history.items.first?.accessibilityText == arrivingText)
        #expect(history.items.first?.descriptionVersion == 1_003)
        try await cache.apply(edit, ownerUserID: owner, operation: operation,
                              stamp: stamp, widgetRevisionVersion: 1_001)
        try await pending.markSucceeded(clientOperationID: operation.id, at: Date())
        await history.refreshDescriptions(service: service, context: context)
        await reader.reloadPending()
        let item = try #require(history.items.first)
        #expect(item.accessibilityText == arrivingText)
        #expect(item.descriptionVersion == 1_003)
        #expect(reader.displayedText(source: item.accessibilityText, version: item.descriptionVersion) == arrivingText)
    }

    // MARK: - Newest page

    @Test func refreshNewestReloadsWhenAFullPageOfNewDrawingsArrives() async {
        let existing = makeSummary(createdAt: date(100))
        let arrivedNewer = makeSummary(createdAt: date(300))
        let arrivedOlder = makeSummary(createdAt: date(200))
        // A full page with nothing already loaded in it may hide more new drawings
        // behind it, so the refresh (call 2) is followed by a reload (call 3).
        let gateway = StubGateway(
            canvasState: makeState(),
            pages: [[existing], [arrivedNewer, arrivedOlder], [arrivedNewer, arrivedOlder]]
        )
        let viewModel = makeViewModel(gateway: gateway, pageSize: 2)
        await viewModel.loadInitialIfNeeded()

        await viewModel.refreshNewest()

        #expect(viewModel.items.map(\.id) == [arrivedNewer.revisionID, arrivedOlder.revisionID])
        #expect(viewModel.phase == .loaded)
        #expect(viewModel.hasMore)
        #expect(gateway.listCursors.count == 3)
        #expect(gateway.listCursors[2].before == nil)
    }

    // MARK: - Overlapping loads

    @Test func historySharingRefusesAnotherIdentityOrRelationship() async throws {
        let owner = UUID()
        let couple = UUID()
        let gateway = StubGateway(canvasState: makeState(coupleID: couple),
                                  pages: [[makeSummary(createdAt: date(100))]])
        let viewModel = WidgetDrawingHistoryViewModel(
            gateway: gateway, identity: WidgetSyncIdentity(currentUserID: owner,
                                                           currentDisplayName: "Alex", partnerDisplayName: "Robin")
        )
        await viewModel.loadInitialIfNeeded()
        let item = try #require(viewModel.items.first)
        var changed = ThreadChatContext(coupleID: UUID())
        changed.participants.currentUserID = owner
        await #expect(throws: MediaAlternativeEditingError.self) {
            _ = try await viewModel.prepareShare(for: item, service: nil, context: changed)
        }
        changed.coupleID = couple
        changed.participants.currentUserID = UUID()
        await #expect(throws: MediaAlternativeEditingError.self) {
            _ = try await viewModel.prepareShare(for: item, service: nil, context: changed)
        }
    }

    @Test func olderHistoryReadCannotRollBackACorrectionObservedByANewerRead() async {
        let revisionID = UUID()
        let original = makeSummary(createdAt: date(100), revisionID: revisionID,
                                   description: "Original sun", version: 1_000)
        let corrected = makeSummary(createdAt: date(100), revisionID: revisionID,
                                    description: "A sun above two hills", version: 1_001)
        let gateway = GatedListGateway(canvasState: makeState(), heldCall: 2,
                                      otherPages: [[original], [corrected]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)
        await viewModel.loadInitialIfNeeded()
        let older = Task { await viewModel.refreshNewest() }
        await gateway.waitUntilListIsHeld()
        await viewModel.refreshNewest()
        #expect(viewModel.items.first?.accessibilityText == "A sun above two hills")
        await gateway.releaseHeldList(with: .success([original]))
        await older.value
        #expect(viewModel.items.first?.accessibilityText == "A sun above two hills")
        #expect(viewModel.items.first?.descriptionVersion == 1_001)
        #expect(viewModel.items.first?.createdAt == original.createdAt)
    }

    @Test func retryWinsOverAnEarlierFirstPageLoadThatFinishesLate() async {
        let stale = makeSummary(createdAt: date(100))
        let fresh = makeSummary(createdAt: date(200))
        let gateway = GatedListGateway(canvasState: makeState(), heldCall: 1, otherPages: [[fresh]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)

        let earlierLoad = Task { await viewModel.loadInitialIfNeeded() }
        await gateway.waitUntilListIsHeld()
        await viewModel.retry()
        #expect(viewModel.items.map(\.id) == [fresh.revisionID])

        await gateway.releaseHeldList(with: .success([stale]))
        await earlierLoad.value

        #expect(viewModel.items.map(\.id) == [fresh.revisionID])
        #expect(viewModel.phase == .loaded)
    }

    @Test func aFailedEarlierFirstPageLoadDoesNotOverwriteALoadedTimeline() async {
        let fresh = makeSummary(createdAt: date(200))
        let gateway = GatedListGateway(canvasState: makeState(), heldCall: 1, otherPages: [[fresh]])
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)

        let earlierLoad = Task { await viewModel.loadInitialIfNeeded() }
        await gateway.waitUntilListIsHeld()
        await viewModel.retry()

        await gateway.releaseHeldList(with: .failure(URLError(.timedOut)))
        await earlierLoad.value

        #expect(viewModel.items.map(\.id) == [fresh.revisionID])
        #expect(viewModel.phase == .loaded)
    }

    @Test func refreshNewestDropsItsPageWhenAFirstPageLoadStartedMeanwhile() async {
        let existing = makeSummary(createdAt: date(100))
        let reloaded = makeSummary(createdAt: date(150))
        let arrived = makeSummary(createdAt: date(200))
        // Call 1 is the first load, call 2 (held) is the refresh, call 3 is the retry.
        let gateway = GatedListGateway(
            canvasState: makeState(), heldCall: 2, otherPages: [[existing], [reloaded]]
        )
        let viewModel = makeViewModel(gateway: gateway, pageSize: 10)
        await viewModel.loadInitialIfNeeded()

        let refresh = Task { await viewModel.refreshNewest() }
        await gateway.waitUntilListIsHeld()
        await viewModel.retry()

        await gateway.releaseHeldList(with: .success([arrived]))
        await refresh.value

        #expect(viewModel.items.map(\.id) == [reloaded.revisionID])
    }

    @Test func loadMoreDropsItsPageWhenAFirstPageLoadStartedMeanwhile() async {
        let newer = makeSummary(createdAt: date(500))
        let shared = makeSummary(createdAt: date(400))
        let reloaded = makeSummary(createdAt: date(450))
        let older = makeSummary(createdAt: date(300))
        // Call 1 is the first load, call 2 (held) is the older page, call 3 is the retry.
        let gateway = GatedListGateway(
            canvasState: makeState(), heldCall: 2, otherPages: [[newer, shared], [reloaded]]
        )
        let viewModel = makeViewModel(gateway: gateway, pageSize: 2)
        await viewModel.loadInitialIfNeeded()
        let lastItem = viewModel.items[1]

        let loadMore = Task { await viewModel.loadMoreIfNeeded(currentItem: lastItem) }
        await gateway.waitUntilListIsHeld()
        await viewModel.retry()

        await gateway.releaseHeldList(with: .success([older]))
        await loadMore.value

        #expect(viewModel.items.map(\.id) == [reloaded.revisionID])
        #expect(viewModel.isLoadingMore == false)
        #expect(viewModel.loadMoreFailed == false)
    }

    // MARK: - Helpers

    private func makeViewModel(
        gateway: any WidgetCanvasGateway,
        pageSize: Int = 30
    ) -> WidgetDrawingHistoryViewModel {
        WidgetDrawingHistoryViewModel(
            gateway: gateway,
            identity: WidgetSyncIdentity(currentUserID: nil, currentDisplayName: nil, partnerDisplayName: nil),
            pageSize: pageSize
        )
    }

    private func makeSummary(createdAt: Date, revisionID: UUID = UUID(), description: String? = nil,
                             version: Int64? = nil, authorUserID: UUID = UUID()) -> WidgetDrawingRevisionSummary {
        WidgetDrawingRevisionSummary(
            revisionID: revisionID,
            authorUserID: authorUserID,
            payloadMediaAssetID: UUID(),
            bounds: WidgetDrawingBounds(x: 0, y: 0, width: 10, height: 10, canvasSide: 320,
                                        accessibilityText: description),
            createdAt: createdAt, descriptionVersion: version
        )
    }

    private func makeState(coupleID: UUID? = nil) -> WidgetCanvasState {
        WidgetCanvasState(
            canvasID: UUID(),
            activeRevisionID: nil,
            activeRevisionAuthorUserID: nil,
            payloadMediaAssetID: nil,
            bounds: nil,
            revisionCreatedAt: nil, coupleID: coupleID
        )
    }

    private func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: offset)
    }
}

/// Records the cursors it was asked for and replays canned pages in order.
private nonisolated final class StubGateway: WidgetCanvasGateway, @unchecked Sendable {
    var canvasState: WidgetCanvasState?
    var stateError: (any Error)?
    var listError: (any Error)?
    private let pages: [[WidgetDrawingRevisionSummary]]
    private var index = 0
    private(set) var listCursors: [(before: Date?, revisionID: UUID?)] = []

    init(canvasState: WidgetCanvasState?, pages: [[WidgetDrawingRevisionSummary]]) {
        self.canvasState = canvasState
        self.pages = pages
    }

    func getCanvasState() throws -> WidgetCanvasState? {
        if let stateError { throw stateError }
        return canvasState
    }

    func listRevisions(
        canvasID: UUID,
        limit: Int,
        createdBefore: Date?,
        createdBeforeRevisionID: UUID?
    ) throws -> [WidgetDrawingRevisionSummary] {
        if let listError { throw listError }
        listCursors.append((createdBefore, createdBeforeRevisionID))
        defer { index += 1 }
        return index < pages.count ? pages[index] : []
    }

    // Unused by the history timeline.
    func getOrCreateCanvas() throws -> WidgetCanvasReference {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func reserveDrawingUpload(
        coupleID: UUID, canvasID: UUID, revisionID: UUID, operation: WidgetCanvasClientOperation
    ) throws -> MediaUploadReservation {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func uploadPayload(reservation: MediaUploadReservation, data: Data) throws -> String {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput, operation: WidgetCanvasClientOperation
    ) throws {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission, operation: WidgetCanvasClientOperation
    ) throws -> WidgetDrawingRevisionResult {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func signedPayloadURL(mediaAssetID: UUID) -> URL? { nil }
}

/// Suspends one chosen `listRevisions` call until the test releases it and serves
/// every other call from canned pages in order. Lets a test start a second load
/// while the first is still waiting on the network.
private actor GatedListGateway: WidgetCanvasGateway {
    private let canvasState: WidgetCanvasState?
    private let heldCall: Int
    private var otherPages: [[WidgetDrawingRevisionSummary]]
    private var listCallCount = 0
    private var heldList: CheckedContinuation<[WidgetDrawingRevisionSummary], any Error>?
    private var heldListWaiter: CheckedContinuation<Void, Never>?

    /// `heldCall` is the 1-based number of the `listRevisions` call to hold.
    init(canvasState: WidgetCanvasState?, heldCall: Int, otherPages: [[WidgetDrawingRevisionSummary]]) {
        self.canvasState = canvasState
        self.heldCall = heldCall
        self.otherPages = otherPages
    }

    /// Returns once the held call is suspended.
    func waitUntilListIsHeld() async {
        guard heldList == nil else { return }
        await withCheckedContinuation { continuation in
            heldListWaiter = continuation
        }
    }

    func releaseHeldList(with result: Result<[WidgetDrawingRevisionSummary], any Error>) {
        heldList?.resume(with: result)
        heldList = nil
    }

    func getCanvasState() async throws -> WidgetCanvasState? {
        canvasState
    }

    func listRevisions(
        canvasID: UUID,
        limit: Int,
        createdBefore: Date?,
        createdBeforeRevisionID: UUID?
    ) async throws -> [WidgetDrawingRevisionSummary] {
        listCallCount += 1
        guard listCallCount == heldCall else {
            return otherPages.isEmpty ? [] : otherPages.removeFirst()
        }
        return try await withCheckedThrowingContinuation { continuation in
            heldList = continuation
            heldListWaiter?.resume()
            heldListWaiter = nil
        }
    }

    // Unused by the history timeline.
    func getOrCreateCanvas() async throws -> WidgetCanvasReference {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func reserveDrawingUpload(
        coupleID: UUID, canvasID: UUID, revisionID: UUID, operation: WidgetCanvasClientOperation
    ) async throws -> MediaUploadReservation {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func uploadPayload(reservation: MediaUploadReservation, data: Data) async throws -> String {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func finalizeDrawingUpload(
        _ input: WidgetDrawingFinalizeInput, operation: WidgetCanvasClientOperation
    ) async throws {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func submitRevision(
        _ submission: WidgetDrawingRevisionSubmission, operation: WidgetCanvasClientOperation
    ) async throws -> WidgetDrawingRevisionResult {
        throw WidgetCanvasGatewayError.emptyResponse
    }
    func signedPayloadURL(mediaAssetID: UUID) async throws -> URL? { nil }
}

// swiftlint:enable async_without_await
